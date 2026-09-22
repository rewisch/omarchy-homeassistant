import QtQuick
import QtWebSockets

// Live transport over the Home Assistant WebSocket API. Requires the
// qt6-websockets package; the service falls back to RestTransport when this
// file fails to load.
Item {
  id: root

  property string baseUrl: ""
  property string token: ""
  property bool enabled: false

  readonly property string kind: "websocket"
  property bool connected: false
  property bool busy: socket.status === WebSocket.Connecting

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
  property int _subscriptionId: -1
  property int _notificationSubId: -1
  property int _reconnectMs: 1500
  property bool _authed: false
  property bool _manualClose: false

  readonly property string socketUrl: {
    var url = String(baseUrl || "").replace(/\/+$/, "")
    if (url === "") return ""
    return url.replace(/^http/i, "ws") + "/api/websocket"
  }

  onEnabledChanged: enabled ? openSocket() : closeSocket()
  onBaseUrlChanged: if (enabled) reconnectNow()
  onTokenChanged: if (enabled) reconnectNow()

  function openSocket() {
    if (!enabled || socketUrl === "" || token === "") return
    _manualClose = false
    _authed = false
    socket.active = false
    socket.url = socketUrl
    socket.active = true
  }

  function closeSocket() {
    _manualClose = true
    reconnectTimer.stop()
    pingTimer.stop()
    socket.active = false
    connected = false
    _authed = false
  }

  function reconnectNow() {
    closeSocket()
    _reconnectMs = 1500
    if (enabled) openSocket()
  }

  function refresh() {
    if (!connected) { if (enabled && socket.status !== WebSocket.Open) openSocket(); return }
    send({ type: "get_states" }, function(ok, result) { if (ok && result) root.statesReceived(result) })
  }

  function send(message, callback) {
    if (socket.status !== WebSocket.Open) return -1
    var id = _nextId++
    message.id = id
    if (callback) _pending[id] = callback
    socket.sendTextMessage(JSON.stringify(message))
    return id
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

  function handleMessage(text) {
    var msg = null
    try { msg = JSON.parse(text) } catch (e) { return }
    if (!msg || typeof msg.type !== "string") return
    switch (msg.type) {
    case "auth_required":
      socket.sendTextMessage(JSON.stringify({ type: "auth", access_token: root.token }))
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
      socket.active = false
      break
    case "result": {
      var cb = _pending[msg.id]
      if (cb) {
        delete _pending[msg.id]
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
      socket.sendTextMessage(JSON.stringify({ id: msg.id, type: "pong" }))
      break
    case "pong":
      break
    }
  }

  WebSocket {
    id: socket
    active: false
    onTextMessageReceived: function(message) { root.handleMessage(message) }
    onStatusChanged: function(status) {
      if (status === WebSocket.Open) return
      if (status === WebSocket.Error) {
        root.connected = false
        root._authed = false
        root.transportError(socket.errorString || "WebSocket error")
        root.scheduleReconnect()
      } else if (status === WebSocket.Closed) {
        var wasConnected = root.connected
        root.connected = false
        root._authed = false
        pingTimer.stop()
        root._pending = ({})
        if (!root._manualClose) {
          if (wasConnected) root.transportError("Connection closed")
          root.scheduleReconnect()
        }
      }
    }
  }

  function scheduleReconnect() {
    if (!enabled || _manualClose) return
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
