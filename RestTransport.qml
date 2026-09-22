import QtQuick
import Quickshell
import Quickshell.Io

// Polling transport over the Home Assistant REST API. Always available since
// it only needs curl. The token travels via the process environment, never
// on the command line, so it stays out of `ps`.
Item {
  id: root

  property string baseUrl: ""
  property string token: ""
  property bool enabled: false
  property int intervalSec: 10

  readonly property string kind: "polling"
  property bool connected: false
  property bool busy: statesProc.running || checkProc.running || callProc.running

  signal statesReceived(var states)
  signal configReceived(var config)
  signal authOk()
  signal authInvalid(string message)
  signal transportError(string message)
  signal callFinished(var call, bool success, string message)

  property var _callQueue: []
  property var _activeCall: null
  property bool _checked: false

  onEnabledChanged: enabled ? start() : stop()
  onBaseUrlChanged: if (enabled) restart()
  onTokenChanged: if (enabled) restart()

  function start() {
    _checked = false
    connected = false
    if (baseUrl === "" || token === "") return
    check()
  }

  function stop() {
    pollTimer.stop()
    statesProc.running = false
    checkProc.running = false
    connected = false
    _checked = false
  }

  function restart() {
    stop()
    if (enabled) start()
  }

  function refresh() {
    if (!enabled || baseUrl === "" || token === "") return
    if (!_checked) { check(); return }
    fetchStates()
  }

  function check() {
    if (checkProc.running) return
    checkProc.command = curlCommand("GET", "/api/config", "")
    checkProc.environment = env("")
    checkProc.running = true
  }

  function fetchStates() {
    if (statesProc.running) return
    statesProc.command = curlCommand("GET", "/api/states", "")
    statesProc.environment = env("")
    statesProc.running = true
  }

  // call = { domain, service, data }
  function callService(call) {
    _callQueue.push(call)
    pumpCalls()
  }

  function pumpCalls() {
    if (callProc.running || _callQueue.length === 0) return
    _activeCall = _callQueue.shift()
    var body = JSON.stringify(_activeCall.data || {})
    callProc.command = curlCommand("POST", "/api/services/" + _activeCall.domain + "/" + _activeCall.service, body)
    callProc.environment = env(body)
    callProc.running = true
  }

  property var _historyQueue: []
  property var _activeHistory: null

  function fetchHistory(entityId, startIso, endIso, callback) {
    _historyQueue.push({ entityId: entityId, start: startIso, end: endIso, callback: callback })
    pumpHistory()
  }

  function pumpHistory() {
    if (historyProc.running || _historyQueue.length === 0) return
    _activeHistory = _historyQueue.shift()
    var path = "/api/history/period/" + encodeURIComponent(_activeHistory.start)
      + "?filter_entity_id=" + encodeURIComponent(_activeHistory.entityId)
      + "&end_time=" + encodeURIComponent(_activeHistory.end)
      + "&minimal_response&no_attributes"
    historyProc.command = curlCommand("GET", path, "")
    historyProc.environment = env("")
    historyProc.running = true
  }

  Process {
    id: historyProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var res = root.splitResponse(historyProc.stdout.text)
      var job = root._activeHistory
      root._activeHistory = null
      var parsed = null
      if (res.code === 200) { try { parsed = JSON.parse(res.body) } catch (e) { parsed = null } }
      if (job && job.callback) job.callback(parsed !== null, parsed)
      root.pumpHistory()
    }
  }

  function env(body) {
    return ({ HA_TOKEN: root.token, HA_BODY: body })
  }

  function curlCommand(method, path, body) {
    var script = "curl -sS -m 12 -X \"$1\" -H \"Authorization: Bearer $HA_TOKEN\" -H \"Content-Type: application/json\""
    if (method === "POST") script += " --data \"$HA_BODY\""
    script += " -w '\\n%{http_code}' \"$2\""
    return ["sh", "-c", script, "curl", method, root.baseUrl + path]
  }

  // Splits curl output into { code, body }. The status code is the last line.
  function splitResponse(raw) {
    var text = String(raw || "")
    var nl = text.lastIndexOf("\n")
    if (nl === -1) return { code: 0, body: text }
    var code = parseInt(text.slice(nl + 1).trim(), 10)
    return { code: isFinite(code) ? code : 0, body: text.slice(0, nl) }
  }

  function describeFailure(code, body, stderr) {
    if (code === 401 || code === 403) return "Authentication failed. Check the access token."
    if (code === 404) return "Not a Home Assistant API endpoint. Check the URL."
    if (code >= 500) return "Home Assistant returned an error (" + code + ")."
    if (code === 0) {
      var err = String(stderr || "").trim()
      if (err !== "") return err.replace(/^curl:\s*\(\d+\)\s*/, "")
      return "Could not reach " + root.baseUrl
    }
    return "Unexpected response (" + code + ")."
  }

  Process {
    id: checkProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var res = root.splitResponse(checkProc.stdout.text)
      if (res.code === 200) {
        var cfg = null
        try { cfg = JSON.parse(res.body) } catch (e) { cfg = null }
        root._checked = true
        root.connected = true
        root.authOk()
        if (cfg) root.configReceived(cfg)
        root.fetchStates()
        pollTimer.restart()
        return
      }
      root.connected = false
      if (res.code === 401 || res.code === 403) root.authInvalid(root.describeFailure(res.code, res.body, ""))
      else root.transportError(root.describeFailure(res.code, res.body, checkProc.stderr.text))
      pollTimer.restart()
    }
  }

  Process {
    id: statesProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var res = root.splitResponse(statesProc.stdout.text)
      if (res.code === 200) {
        var states = null
        try { states = JSON.parse(res.body) } catch (e) { states = null }
        if (states && typeof states.length === "number") {
          root.connected = true
          root.statesReceived(states)
          return
        }
        root.transportError("Could not parse the states response.")
        return
      }
      root.connected = false
      if (res.code === 401 || res.code === 403) { root._checked = false; root.authInvalid(root.describeFailure(res.code, res.body, "")) }
      else root.transportError(root.describeFailure(res.code, res.body, statesProc.stderr.text))
    }
  }

  Process {
    id: callProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var res = root.splitResponse(callProc.stdout.text)
      var call = root._activeCall
      root._activeCall = null
      if (res.code >= 200 && res.code < 300) {
        root.callFinished(call, true, "")
        // Services take a moment to settle; fetch fresh states shortly after.
        settleTimer.restart()
      } else {
        root.callFinished(call, false, root.describeFailure(res.code, res.body, callProc.stderr.text))
      }
      root.pumpCalls()
    }
  }

  Timer {
    id: settleTimer
    interval: 700
    onTriggered: root.fetchStates()
  }

  Timer {
    id: pollTimer
    interval: Math.max(2, root.intervalSec) * 1000
    repeat: true
    running: root.enabled && root.baseUrl !== "" && root.token !== ""
    onTriggered: root.refresh()
  }
}
