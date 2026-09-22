import QtQuick
import Quickshell
import Quickshell.Io

// Live transport over the Home Assistant WebSocket API, driven through
// ha-ws-bridge.py. The bridge owns the socket and enforces frame, message,
// rate and per-session ceilings before any payload is buffered; the shell
// only ever sees one bounded JSON line per message. Python 3 ships with
// Omarchy, so there is nothing to install.
Item {
  id: root

  property string baseUrl: ""
  property string token: ""
  property bool enabled: false

  readonly property string kind: "websocket"
  property bool connected: false
  readonly property bool busy: bridge.running && !connected
  // Set when the bridge cannot run at all (no python3); the service then
  // falls back to REST polling for the rest of the session.
  property bool unavailable: false

  // Ceilings handed to the bridge. Values are bytes and counts.
  readonly property int maxFrameBytes: 32 * 1024 * 1024
  readonly property int maxMessageBytes: 64 * 1024 * 1024
  readonly property int maxMessagesPerSecond: 500
  readonly property int maxMessageBurst: 5000
  readonly property int maxPendingCalls: 500

  signal statesReceived(var states)
  signal entityStateChanged(var newState)
  signal configReceived(var config)
  signal registryReceived(string kind, var rows)
  signal persistentNotifications(string kind, var notifications)
  signal authOk()
  signal authInvalid(string message)
  signal transportError(string message)
  signal callFinished(var call, bool success, string message)

  property int _nextId: 1
  property var _pending: ({})
  property var _pendingOrder: []
  property int _subscriptionId: -1
  property int _notificationSubId: -1
  property int _reconnectMs: 1500
  property bool _authed: false
  property bool _manualClose: false
  property bool _open: false
  // Set when a reconnect is requested while the bridge is still shutting
  // down: Quickshell keeps `running` true until the child has exited, so the
  // new bridge is started from onExited instead.
  property bool _reopenOnExit: false

  readonly property string bridgePath: {
    var url = String(Qt.resolvedUrl("ha-ws-bridge.py"))
    // A home directory with a space or non-ASCII characters is percent-encoded here.
    return decodeURIComponent(url.indexOf("file://") === 0 ? url.slice(7) : url)
  }

  onEnabledChanged: enabled ? openSocket() : closeSocket()
  onBaseUrlChanged: if (enabled) reconnectNow()
  onTokenChanged: if (enabled) reconnectNow()

  function openSocket() {
    if (!enabled || unavailable || baseUrl === "" || token === "") return
    if (bridge.running) return
    _manualClose = false
    _authed = false
    _open = false
    _pending = ({})
    _pendingOrder = []
    bridge.environment = ({
      HA_URL: baseUrl,
      HA_WS_MAX_FRAME: String(maxFrameBytes),
      HA_WS_MAX_MESSAGE: String(maxMessageBytes),
      HA_WS_MAX_RATE: String(maxMessagesPerSecond),
      HA_WS_MAX_BURST: String(maxMessageBurst)
    })
    bridge.running = true
  }

  function closeSocket() {
    _manualClose = true
    _reopenOnExit = false
    reconnectTimer.stop()
    pingTimer.stop()
    failPending("Connection closed")
    if (bridge.running) bridge.running = false
    connected = false
    _authed = false
    _open = false
  }

  function reconnectNow() {
    closeSocket()
    _reconnectMs = 1500
    if (!enabled) return
    if (bridge.running) _reopenOnExit = true
    else openSocket()
  }

  // Answers every outstanding request callback with a failure so nothing
  // upstream waits forever for a reply that cannot come.
  function failPending(reason) {
    var order = _pendingOrder
    var map = _pending
    _pending = ({})
    _pendingOrder = []
    for (var i = 0; i < order.length; i++) {
      var cb = map[order[i]]
      if (cb) cb(false, null, { message: reason })
    }
  }

  function refresh() {
    if (!connected) { if (enabled && !bridge.running) openSocket(); return }
    send({ type: "get_states" }, function(ok, result) { if (ok && result) root.statesReceived(result) })
  }

  function send(message, callback) {
    if (!bridge.running || !_open) return -1
    var id = _nextId++
    message.id = id
    if (callback) {
      _pending[id] = callback
      _pendingOrder.push(id)
      // A server that never answers must not grow this map without bound.
      while (_pendingOrder.length > maxPendingCalls) {
        var stale = _pendingOrder.shift()
        var staleCb = _pending[stale]
        delete _pending[stale]
        if (staleCb) staleCb(false, null, { message: "No response from Home Assistant" })
      }
    }
    bridge.write(JSON.stringify(message) + "\n")
    return id
  }

  // callback(ok, rawResult)
  function fetchHistory(entityId, startIso, endIso, callback) {
    var id = send({
      type: "history/history_during_period",
      start_time: startIso,
      end_time: endIso,
      entity_ids: [entityId],
      minimal_response: true,
      no_attributes: true,
      significant_changes_only: false
    }, function(ok, result) { callback(ok, result) })
    if (id === -1) callback(false, null)
  }

  function callService(call) {
    var message = { type: "call_service", domain: call.domain, service: call.service }
    var data = {}
    var target = null
    for (var key in (call.data || {})) {
      if (key === "entity_id") target = { entity_id: call.data[key] }
      else data[key] = call.data[key]
    }
    message.service_data = data
    if (target) message.target = target
    var id = send(message, function(ok, result, error) {
      root.callFinished(call, ok, ok ? "" : (error && error.message ? error.message : "Service call failed"))
    })
    if (id === -1) root.callFinished(call, false, "Not connected")
  }

  function bootstrap() {
    send({ type: "get_config" }, function(ok, result) { if (ok && result) root.configReceived(result) })
    send({ type: "get_states" }, function(ok, result) { if (ok && result) root.statesReceived(result) })
    _subscriptionId = send({ type: "subscribe_events", event_type: "state_changed" })
    _notificationSubId = send({ type: "persistent_notification/subscribe" })
    send({ type: "config/area_registry/list" }, function(ok, result) { if (ok && result) root.registryReceived("area", result) })
    send({ type: "config/device_registry/list" }, function(ok, result) { if (ok && result) root.registryReceived("device", result) })
    send({ type: "config/entity_registry/list" }, function(ok, result) { if (ok && result) root.registryReceived("entity", result) })
    pingTimer.restart()
  }

  function handleLine(line) {
    var text = String(line || "")
    if (text.length === 0) return
    if (text.length > maxMessageBytes) return
    var msg = null
    try { msg = JSON.parse(text) } catch (e) { return }
    if (!msg || typeof msg.type !== "string") return
    switch (msg.type) {
    case "_transport":
      handleTransport(msg)
      break
    case "auth_required":
      bridge.write(JSON.stringify({ type: "auth", access_token: root.token }) + "\n")
      break
    case "auth_ok":
      _authed = true
      connected = true
      _reconnectMs = 1500
      root.authOk()
      bootstrap()
      break
    case "auth_invalid":
      _manualClose = true
      root.authInvalid(msg.message || "Authentication failed. Check the access token.")
      if (bridge.running) bridge.running = false
      break
    case "result": {
      var cb = _pending[msg.id]
      if (cb) {
        delete _pending[msg.id]
        var at = _pendingOrder.indexOf(msg.id)
        if (at !== -1) _pendingOrder.splice(at, 1)
        cb(msg.success === true, msg.result, msg.error)
      }
      break
    }
    case "event": {
      var ev = msg.event
      if (!ev) break
      if (msg.id === _notificationSubId && typeof ev.type === "string") {
        root.persistentNotifications(ev.type, ev.notifications || {})
      } else if (ev.event_type === "state_changed" && ev.data && ev.data.new_state) {
        root.entityStateChanged(ev.data.new_state)
      }
      break
    }
    case "ping":
      bridge.write(JSON.stringify({ id: msg.id, type: "pong" }) + "\n")
      break
    case "pong":
      break
    }
  }

  function handleTransport(msg) {
    if (msg.event === "open") {
      _open = true
    } else if (msg.event === "error") {
      root.transportError(String(msg.reason || "Connection error"))
    } else if (msg.event === "closed") {
      var reason = String(msg.reason || "closed")
      if (reason !== "closed" && reason !== "closed by server") root.transportError("Connection reset: " + reason)
    }
  }

  Process {
    id: bridge
    command: ["python3", root.bridgePath]
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: StdioCollector { waitForEnd: false }
    onExited: function(exitCode) {
      var wasConnected = root.connected
      root.connected = false
      root._authed = false
      root._open = false
      pingTimer.stop()
      root.failPending("Connection closed")
      if (exitCode === 127 || exitCode === 126) {
        root.unavailable = true
        root.transportError("Live transport needs python3; falling back to polling")
        return
      }
      if (root._reopenOnExit) {
        root._reopenOnExit = false
        root.openSocket()
        return
      }
      if (root._manualClose) return
      if (wasConnected && exitCode === 0) root.transportError("Connection closed")
      root.scheduleReconnect()
    }
  }

  function scheduleReconnect() {
    if (!enabled || _manualClose || unavailable) return
    reconnectTimer.interval = _reconnectMs
    _reconnectMs = Math.min(30000, Math.round(_reconnectMs * 1.8))
    reconnectTimer.restart()
  }

  Timer {
    id: reconnectTimer
    repeat: false
    onTriggered: if (root.enabled && !root._manualClose) root.openSocket()
  }

  Timer {
    id: pingTimer
    interval: 30000
    repeat: true
    running: false
    onTriggered: root.send({ type: "ping" })
  }
}
