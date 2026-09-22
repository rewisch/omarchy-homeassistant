#!/usr/bin/env python3
"""WebSocket bridge for the Omarchy Home Assistant plugin.

Owns the TCP/TLS socket to Home Assistant so that every limit is enforced
*before* data is retained: frame and message size, messages per second, and
cumulative bytes per connection. The shell talks to it over pipes: one JSON
message per line on stdin (sent to Home Assistant as a text frame) and one
JSON message per line on stdout (received text frames). Transport events use
{"type": "_transport", ...}, a type Home Assistant never emits.

No third-party modules; only the Python standard library.
"""
import base64
import json
import os
import socket
import ssl
import struct
import sys
import threading
import time
import urllib.parse

MAX_FRAME = int(os.environ.get("HA_WS_MAX_FRAME", 32 * 1024 * 1024))
MAX_MESSAGE = int(os.environ.get("HA_WS_MAX_MESSAGE", 64 * 1024 * 1024))
MAX_MESSAGES_PER_SECOND = int(os.environ.get("HA_WS_MAX_RATE", 500))
# Token bucket: sustained MAX_MESSAGES_PER_SECOND, with this much headroom for
# the burst a restarting Home Assistant emits while its integrations load.
MAX_MESSAGE_BURST = int(os.environ.get("HA_WS_MAX_BURST", 5000))
MAX_SESSION_BYTES = int(os.environ.get("HA_WS_MAX_SESSION", 2 * 1024 * 1024 * 1024))
MAX_MESSAGES_PER_SESSION = int(os.environ.get("HA_WS_MAX_SESSION_MESSAGES", 2_000_000))
CONNECT_TIMEOUT = 15
IDLE_TIMEOUT = 90  # seconds without any frame (the plugin pings every 30 s)

OUT_LOCK = threading.Lock()


def emit(obj):
    line = json.dumps(obj, separators=(",", ":"))
    with OUT_LOCK:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def transport(event, **fields):
    obj = {"type": "_transport", "event": event}
    obj.update(fields)
    emit(obj)


def fail(reason, code=2):
    transport("error", reason=reason)
    sys.exit(code)


def parse_url(base):
    u = urllib.parse.urlsplit(base)
    if u.scheme not in ("http", "https", "ws", "wss") or not u.hostname:
        fail("invalid url")
    tls = u.scheme in ("https", "wss")
    port = u.port or (443 if tls else 80)
    path = (u.path.rstrip("/") or "") + "/api/websocket"
    return u.hostname, port, tls, path


def connect(host, port, tls, path):
    raw = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    raw.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if tls:
        ctx = ssl.create_default_context()
        if os.environ.get("HA_WS_INSECURE") == "1":
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        sock = ctx.wrap_socket(raw, server_hostname=host)
    else:
        sock = raw
    key = base64.b64encode(os.urandom(16)).decode()
    hostname = host if port in (80, 443) else "%s:%d" % (host, port)
    req = (
        "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nUser-Agent: omarchy-homeassistant\r\n\r\n"
    ) % (path, hostname, key)
    sock.sendall(req.encode())
    # Bounded handshake read: headers must fit in 16 KiB.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            fail("connection closed during handshake")
        buf += chunk
        if len(buf) > 16384:
            fail("handshake response too large")
    head, rest = buf.split(b"\r\n\r\n", 1)
    lines = head.decode("latin-1").split("\r\n")
    status = lines[0].split(" ")
    if len(status) < 2 or status[1] != "101":
        fail("handshake rejected: " + lines[0][:120])
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    import hashlib
    expect = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    if headers.get("sec-websocket-accept") != expect:
        fail("handshake accept mismatch")
    sock.settimeout(IDLE_TIMEOUT)
    return sock, rest


def recv_exact(sock, n, pending):
    """Read exactly n bytes, using and updating the pending buffer.

    Chunks are collected and joined once: repeated `bytes +=` copies the whole
    buffer per receive, which is quadratic and costs close to a second for a
    frame at the 32 MiB cap.
    """
    buf = pending[0]
    if len(buf) >= n:
        pending[0] = buf[n:]
        return buf[:n]
    parts = [buf]
    got = len(buf)
    while got < n:
        chunk = sock.recv(min(65536, n - got))
        if not chunk:
            raise ConnectionError("connection closed")
        parts.append(chunk)
        got += len(chunk)
    pending[0] = b""
    return b"".join(parts)


def send_frame(sock, opcode, payload, lock):
    n = len(payload)
    header = bytes([0x80 | opcode])
    if n < 126:
        header += bytes([0x80 | n])
    elif n < 65536:
        header += bytes([0x80 | 126]) + struct.pack("!H", n)
    else:
        header += bytes([0x80 | 127]) + struct.pack("!Q", n)
    mask = os.urandom(4)
    with lock:
        sock.sendall(header + mask + _mask_fast(payload, mask))


def _mask_fast(payload, mask):
    # XOR in 4-byte words via int.from_bytes to avoid a per-byte Python loop.
    # Symmetric, so it also unmasks.
    if not payload:
        return payload
    reps = (len(payload) + 3) // 4
    key = int.from_bytes(mask * reps, "big")
    padded = payload + b"\x00" * (reps * 4 - len(payload))
    return (int.from_bytes(padded, "big") ^ key).to_bytes(reps * 4, "big")[: len(payload)]


def stdin_pump(sock, lock, stop):
    """Forward stdin lines to Home Assistant as text frames."""
    for line in sys.stdin:
        if stop.is_set():
            break
        line = line.strip()
        if not line:
            continue
        if len(line) > MAX_FRAME:
            transport("error", reason="outgoing message too large")
            continue
        try:
            send_frame(sock, 0x1, line.encode(), lock)
        except OSError:
            break
    stop.set()
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass


def main():
    base = os.environ.get("HA_URL", "")
    if not base:
        fail("HA_URL not set", 1)
    host, port, tls, path = parse_url(base)
    try:
        sock, rest = connect(host, port, tls, path)
    except (OSError, ssl.SSLError) as e:
        fail("connect failed: %s" % (str(e)[:160] or e.__class__.__name__))
    transport("open")
    lock = threading.Lock()
    stop = threading.Event()
    threading.Thread(target=stdin_pump, args=(sock, lock, stop), daemon=True).start()

    pending = [rest]
    session_bytes = 0
    session_messages = 0
    # Token bucket for the message rate: starts full, refills continuously.
    tokens = float(MAX_MESSAGE_BURST)
    last_refill = time.monotonic()
    fragments = []
    fragments_len = 0
    fragment_opcode = 0
    reason = "closed"
    try:
        while not stop.is_set():
            try:
                b1, b2 = recv_exact(sock, 2, pending)
            except socket.timeout:
                reason = "idle timeout"
                break
            fin = b1 & 0x80
            opcode = b1 & 0x0F
            masked = b2 & 0x80
            length = b2 & 0x7F
            if length == 126:
                length = struct.unpack("!H", recv_exact(sock, 2, pending))[0]
            elif length == 127:
                length = struct.unpack("!Q", recv_exact(sock, 8, pending))[0]
            # Limits are checked on the announced length, before any payload is read.
            if length > MAX_FRAME:
                reason = "frame too large (%d bytes)" % length
                break
            if fragments_len + length > MAX_MESSAGE:
                reason = "message too large"
                break
            session_bytes += length + 2
            if session_bytes > MAX_SESSION_BYTES:
                reason = "session byte limit reached"
                break
            mask = recv_exact(sock, 4, pending) if masked else None  # servers must not mask (RFC 6455 5.1); tolerate
            payload = recv_exact(sock, length, pending) if length else b""
            if mask:
                payload = _mask_fast(payload, mask)
            if opcode == 0x8:
                reason = "closed by server"
                break
            if opcode == 0x9:
                send_frame(sock, 0xA, payload, lock)
                continue
            if opcode == 0xA:
                continue
            if opcode in (0x1, 0x2):
                fragment_opcode = opcode
                fragments = [payload]
                fragments_len = length
            elif opcode == 0x0:
                fragments.append(payload)
                fragments_len += length
            else:
                continue
            if not fin:
                continue
            data = b"".join(fragments)
            fragments = []
            fragments_len = 0
            if fragment_opcode != 0x1:
                continue
            now = time.monotonic()
            tokens = min(MAX_MESSAGE_BURST, tokens + (now - last_refill) * MAX_MESSAGES_PER_SECOND)
            last_refill = now
            session_messages += 1
            if tokens < 1.0:
                reason = "message rate limit exceeded"
                break
            tokens -= 1.0
            if session_messages > MAX_MESSAGES_PER_SESSION:
                reason = "session message limit reached"
                break
            text = data.decode("utf-8", "replace")
            if "\n" in text or "\r" in text:
                try:
                    text = json.dumps(json.loads(text), separators=(",", ":"))
                except ValueError:
                    continue
            with OUT_LOCK:
                sys.stdout.write(text + "\n")
                sys.stdout.flush()
    except (ConnectionError, OSError) as e:
        reason = "connection error: %s" % (str(e)[:120] or e.__class__.__name__)
    finally:
        stop.set()
        try:
            send_frame(sock, 0x8, struct.pack("!H", 1000), lock)
        except OSError:
            pass
        try:
            sock.close()
        except OSError:
            pass
    transport("closed", reason=reason, bytes=session_bytes, messages=session_messages)
    sys.exit(0 if reason in ("closed", "closed by server") else 2)


if __name__ == "__main__":
    main()
