#!/usr/bin/env python3
"""HA mock with REST + WebSocket (/api/websocket) on one port. No third-party deps."""
import sys, json, base64, hashlib, struct, threading, time, socket, random
sys.argv = [sys.argv[0]]
import mock_ha
from mock_ha import STATES, TOKEN, now
from http.server import HTTPServer

PORT = 18124
AREAS = [{"area_id": "kitchen", "name": "Kitchen"}, {"area_id": "living", "name": "Living Room"}, {"area_id": "bedroom", "name": "Bedroom"}, {"area_id": "outside", "name": "Outside"}]
DEVICES = [{"id": "dev-speaker", "area_id": "living", "name": "Speaker"}, {"id": "dev-tv", "area_id": "living", "name": "TV"}]
ENTITY_REG = [
    {"entity_id": "light.kitchen", "area_id": "kitchen", "device_id": None},
    {"entity_id": "switch.coffee_machine", "area_id": "kitchen"},
    {"entity_id": "light.living_room", "area_id": "living"},
    {"entity_id": "climate.living_room", "area_id": "living"},
    {"entity_id": "sensor.living_room_temperature", "area_id": "living"},
    {"entity_id": "media_player.living_room_speaker", "device_id": "dev-speaker"},
    {"entity_id": "media_player.tv", "device_id": "dev-tv"},
    {"entity_id": "fan.bedroom", "area_id": "bedroom"},
    {"entity_id": "cover.bedroom_blinds", "area_id": "bedroom"},
    {"entity_id": "sensor.outside_humidity", "area_id": "outside"},
    {"entity_id": "sensor.solar_power", "area_id": "outside"},
    {"entity_id": "sensor.phone_battery", "entity_category": "diagnostic"},
    {"entity_id": "sensor.room_39_temperature", "hidden_by": "user"},
]
CLIENTS = []  # (conn, subscription_id)
NOTIF_SUBS = []  # (conn, sub_id)
LOCK = threading.Lock()

def frame(text):
    data = text.encode()
    n = len(data)
    if n < 126: hdr = struct.pack("!BB", 0x81, n)
    elif n < 65536: hdr = struct.pack("!BBH", 0x81, 126, n)
    else: hdr = struct.pack("!BBQ", 0x81, 127, n)
    return hdr + data

def read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk: raise ConnectionError
        buf += chunk
    return buf

def read_frame(conn):
    b1, b2 = read_exact(conn, 2)
    op = b1 & 0x0F; masked = b2 & 0x80; n = b2 & 0x7F
    if n == 126: n = struct.unpack("!H", read_exact(conn, 2))[0]
    elif n == 127: n = struct.unpack("!Q", read_exact(conn, 8))[0]
    key = read_exact(conn, 4) if masked else None
    data = read_exact(conn, n)
    if key: data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
    return op, data

def send(conn, obj):
    try: conn.sendall(frame(json.dumps(obj)))
    except OSError: pass

def broadcast_change(eid):
    e = STATES[eid]
    with LOCK:
        for conn, sub in list(CLIENTS):
            if sub is None: continue
            send(conn, {"id": sub, "type": "event", "event": {"event_type": "state_changed", "data": {"entity_id": eid, "old_state": None, "new_state": e}}})

def apply_service(domain, service, data):
    # reuse mock_ha's REST mutation by faking a request is messy; replicate minimal logic
    eid = data.get("entity_id"); e = STATES.get(eid)
    print(f"WS CALL {domain}.{service} {json.dumps(data)}", flush=True)
    if not e: return
    a = e["attributes"]
    if service == "toggle":
        if domain == "cover": e["state"] = "closed" if e["state"] in ("open", "opening") else "open"
        else: e["state"] = "off" if e["state"] == "on" else "on"
    elif service == "turn_on":
        e["state"] = "on"
        if "brightness_pct" in data: a["brightness"] = round(data["brightness_pct"] * 255 / 100)
        if "color_temp_kelvin" in data: a["color_temp_kelvin"] = data["color_temp_kelvin"]; a["color_mode"] = "color_temp"
        if "hs_color" in data: a["hs_color"] = data["hs_color"]; a["color_mode"] = "hs"
        if domain == "scene": e["state"] = "unknown"
    elif service == "turn_off": e["state"] = "off"
    elif service == "set_temperature": a["temperature"] = data["temperature"]
    elif service == "set_hvac_mode": e["state"] = data["hvac_mode"]
    elif service == "set_preset_mode": a["preset_mode"] = data["preset_mode"]
    elif service == "set_percentage": a["percentage"] = data["percentage"]; e["state"] = "off" if data["percentage"] == 0 else "on"
    elif service == "open_cover": e["state"] = "open"; a["current_position"] = 100
    elif service == "close_cover": e["state"] = "closed"; a["current_position"] = 0
    elif service == "set_cover_position": a["current_position"] = data["position"]
    elif service == "media_play_pause": e["state"] = "paused" if e["state"] == "playing" else "playing"
    elif service == "volume_set": a["volume_level"] = data["volume_level"]
    elif service == "lock": e["state"] = "locked"
    elif service == "unlock": e["state"] = "unlocked"
    elif service == "select_option": e["state"] = data["option"]
    elif service == "set_value": e["state"] = str(data["value"])
    e["last_changed"] = now()
    broadcast_change(eid)

def handle_ws(conn):
    send(conn, {"type": "auth_required", "ha_version": "2026.9.1"})
    sub = None
    authed = False
    try:
        while True:
            op, data = read_frame(conn)
            if op == 8: break
            if op == 9: conn.sendall(struct.pack("!BB", 0x8A, len(data)) + data); continue
            if op != 1: continue
            msg = json.loads(data)
            t = msg.get("type")
            if t == "auth":
                if msg.get("access_token") == TOKEN:
                    authed = True; send(conn, {"type": "auth_ok", "ha_version": "2026.9.1"})
                else:
                    send(conn, {"type": "auth_invalid", "message": "Invalid access token or password"}); break
                continue
            if not authed: continue
            mid = msg.get("id")
            if t == "get_states": send(conn, {"id": mid, "type": "result", "success": True, "result": list(STATES.values())})
            elif t == "get_config": send(conn, {"id": mid, "type": "result", "success": True, "result": {"location_name": "Casa Wietlisbach (live)", "version": "2026.9.1"}})
            elif t == "subscribe_events":
                sub = mid
                with LOCK: CLIENTS.append((conn, sub))
                send(conn, {"id": mid, "type": "result", "success": True, "result": None})
            elif t == "config/area_registry/list": send(conn, {"id": mid, "type": "result", "success": True, "result": AREAS})
            elif t == "config/device_registry/list": send(conn, {"id": mid, "type": "result", "success": True, "result": DEVICES})
            elif t == "config/entity_registry/list": send(conn, {"id": mid, "type": "result", "success": True, "result": ENTITY_REG})
            elif t == "call_service":
                d = dict(msg.get("service_data") or {})
                tgt = msg.get("target") or {}
                if "entity_id" in tgt: d["entity_id"] = tgt["entity_id"]
                apply_service(msg["domain"], msg["service"], d)
                send(conn, {"id": mid, "type": "result", "success": True, "result": {"context": {"id": "x"}}})
            elif t == "ping": send(conn, {"id": mid, "type": "pong"})
            elif t == "history/history_during_period":
                eid = (msg.get("entity_ids") or [""])[0]
                rows = [{"s": r["s"], "lu": r["lu"]} for r in mock_ha.history_rows(eid, msg.get("start_time", ""), msg.get("end_time", ""))]
                send(conn, {"id": mid, "type": "result", "success": True, "result": {eid: rows}})
            elif t == "persistent_notification/subscribe":
                with LOCK: NOTIF_SUBS.append((conn, mid))
                send(conn, {"id": mid, "type": "result", "success": True, "result": None})
                send(conn, {"id": mid, "type": "event", "event": {"type": "current", "notifications": {"old": {"notification_id": "old", "title": "Old", "message": "Should not be shown", "created_at": now()}}}})
            else: send(conn, {"id": mid, "type": "result", "success": False, "error": {"code": "unknown_command", "message": "Unknown command"}})
    except (ConnectionError, OSError, json.JSONDecodeError):
        pass
    finally:
        with LOCK:
            CLIENTS[:] = [c for c in CLIENTS if c[0] is not conn]
            NOTIF_SUBS[:] = [c for c in NOTIF_SUBS if c[0] is not conn]
        try: conn.close()
        except OSError: pass
        print("WS client disconnected", flush=True)

def blast(size, count):
    """Send `count` text frames of `size` bytes to every subscriber: the limit test."""
    payload = json.dumps({"type": "event", "junk": "x" * max(0, size - 40)})
    with LOCK:
        for conn, sub in list(CLIENTS):
            for _ in range(count):
                try: conn.sendall(frame(payload))
                except OSError: break

def push_notification(title, message):
    nid = "n%d" % int(time.time())
    with LOCK:
        for conn, sub in list(NOTIF_SUBS):
            send(conn, {"id": sub, "type": "event", "event": {"type": "added", "notifications": {nid: {"notification_id": nid, "title": title, "message": message, "created_at": now()}}}})

class Handler(mock_ha.H):
    protocol_version = "HTTP/1.1"
    def do_POST(self):
        if self.path == "/mock/blast":
            n = int(self.headers.get("Content-Length", 0)); data = json.loads(self.rfile.read(n) or b"{}")
            threading.Thread(target=blast, args=(int(data.get("size", 1024)), int(data.get("count", 1))), daemon=True).start()
            return self._send(200, {"ok": True})
        if self.path == "/mock/notify":
            n = int(self.headers.get("Content-Length", 0)); data = json.loads(self.rfile.read(n) or b"{}")
            push_notification(data.get("title", "Mock"), data.get("message", ""))
            return self._send(200, {"ok": True})
        return super().do_POST()
    def do_GET(self):
        if self.path == "/api/websocket" and "upgrade" in self.headers.get("Connection", "").lower():
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101); self.send_header("Upgrade", "websocket"); self.send_header("Connection", "Upgrade"); self.send_header("Sec-WebSocket-Accept", accept); self.end_headers()
            print("WS client connected", flush=True)
            self.close_connection = True
            conn = self.connection
            handle_ws(conn)
            return
        return super().do_GET()

def ticker():
    while True:
        time.sleep(4)
        e = STATES["sensor.solar_power"]
        e["state"] = str(random.randint(1800, 3200)); e["last_changed"] = now()
        broadcast_change("sensor.solar_power")
        e2 = STATES["binary_sensor.hallway_motion"]
        e2["state"] = "off" if e2["state"] == "on" else "on"; e2["last_changed"] = now()
        broadcast_change("binary_sensor.hallway_motion")

threading.Thread(target=ticker, daemon=True).start()
from socketserver import ThreadingMixIn
class Srv(ThreadingMixIn, HTTPServer): daemon_threads = True
Srv(("127.0.0.1", PORT), Handler).serve_forever()
