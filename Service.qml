import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Connection + entity store for one Home Assistant instance. Owns the
// transport (WebSocket when available, REST polling otherwise), the
// optimistic-update bookkeeping, and the two user files:
//   ~/.config/omarchy/homeassistant/connection.json  (url + token, mode 600)
//   ~/.config/omarchy/homeassistant/dashboard.json   (picked entities, bar pin)
Item {
  id: root

  // Injected by the shell when this runs as the plugin's shared service.
  property var shell: null
  property var manifest: null

  // Pushed by the bar widget (the shell injects settings into widgets, not
  // services). Every bar instance pushes the same entry, so order is moot.
  property var settings: ({})

  // A widget keeps a private instance as a fallback for shells that cannot
  // hand out the shared service; that instance stays dormant unless enabled.
  property bool active: true

  // ---- Connection configuration -----------------------------------------
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/homeassistant"
  readonly property string connectionPath: configDir + "/connection.json"
  readonly property string dashboardPath: configDir + "/dashboard.json"

  property string url: ""
  property string token: ""
  property bool configLoaded: false
  readonly property bool configured: url !== "" && token !== ""

  // ---- Status -------------------------------------------------------------
  // idle | connecting | connected | auth_failed | error | unsupported
  property string status: "idle"
  property string lastError: ""
  property string actionStatus: ""
  readonly property bool connected: status === "connected"
  property var haConfig: ({})
  readonly property string locationName: haConfig && haConfig.location_name ? String(haConfig.location_name) : "Home Assistant"
  readonly property string haVersion: haConfig && haConfig.version ? String(haConfig.version) : ""

  readonly property string transportSetting: String(setting("transport", "Auto"))
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 2, 600)
  // The live transport runs through ha-ws-bridge.py (python3 ships with
  // Omarchy). If the bridge cannot start at all, polling takes over.
  readonly property bool wsAvailable: !ws.unavailable
  readonly property bool useWs: wsAvailable && transportSetting !== "Polling"
  readonly property bool useRest: !useWs && transportSetting !== "WebSocket"
  readonly property var activeTransport: useWs ? ws : (useRest ? rest : null)
  readonly property string transportKind: useWs ? "websocket" : (useRest ? "polling" : "none")
  readonly property string transportLabel: transportKind === "websocket" ? "Live" : (transportKind === "polling" ? "Polling every " + refreshIntervalSec + "s" : "No transport")
  readonly property bool busy: activeTransport ? activeTransport.busy : false

  // ---- Entities -----------------------------------------------------------
  property var entities: ({})
  property var entityList: []
  property int revision: 0
  property var pending: ({})
  property var areas: ({})
  property var devices: ({})
  property var entityArea: ({})
  property var entityMeta: ({})
  readonly property int entityCount: entityList.length
  readonly property bool hasAreas: Object.keys(areas).length > 0

  // ---- Dashboard ----------------------------------------------------------
  property var dashboardIds: []
  property var barIds: []
  property var alertIds: []
  property var prefs: ({})
  property bool dashboardLoaded: false
  // First pinned entity, kept for callers that want a single value.
  readonly property string barEntityId: barIds.length > 0 ? barIds[0] : ""
  readonly property var barEntity: revision >= 0 ? entityFor(barEntityId) : null
  readonly property var barEntities: revision >= 0 ? barIds.map(function(id) { return entityFor(id) }) : []
  readonly property int dashboardOnCount: countOn()
  readonly property bool attention: revision >= 0 ? needsAttention() : false
  readonly property bool persistentNotificationsEnabled: pref("persistentNotifications", true) === true
  readonly property bool alertNotificationsEnabled: pref("alertNotifications", true) === true
  property bool _initialStatesLoaded: false
  property var _lastAlertAt: ({})
  property var _lastNotifiedState: ({})

  signal probeFinished(bool ok, string message)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // ---- Entity access ------------------------------------------------------

  // Returns the entity with any optimistic state applied. Read `revision`
  // in the binding that calls this so the row refreshes on every update.
  function entityFor(entityId) {
    var id = String(entityId || "")
    if (id === "") return null
    var e = entities[id]
    if (!e) return null
    var p = pending[id]
    if (p && p.expires > Date.now()) {
      var copy = {}
      for (var key in e) copy[key] = e[key]
      copy.state = p.state
      if (p.attributes) {
        var attrs = {}
        for (var a in (e.attributes || {})) attrs[a] = e.attributes[a]
        for (var b in p.attributes) attrs[b] = p.attributes[b]
        copy.attributes = attrs
      }
      copy.__pending = true
      return copy
    }
    return e
  }

  function areaNameFor(entityId) {
    var areaId = entityArea[String(entityId || "")]
    if (!areaId) return ""
    return areas[areaId] || ""
  }

  function decorate(state) {
    if (!state || !state.entity_id) return state
    var meta = entityMeta[state.entity_id]
    state.__diagnostic = !!(meta && meta.diagnostic)
    state.__hidden = !!(meta && meta.hidden)
    // Sort key cached once per state object; the comparator below runs
    // tens of thousands of times for a large instance.
    state.__sortName = Model.friendlyName(state).toLowerCase()
    return state
  }

  property real lastSyncMs: 0

  function rebuildList() {
    var list = []
    for (var id in entities) {
      var e = entities[id]
      if (e && !e.__hidden) list.push(e)
    }
    list.sort(function(a, b) {
      var an = a.__sortName, bn = b.__sortName
      return an < bn ? -1 : (an > bn ? 1 : 0)
    })
    entityList = list
  }

  // Same ids, names and visibility as before: swap the objects in place so
  // rows read fresh state without `entityList` (and the browser's search
  // results bound to it) being rebuilt on every poll.
  function refreshList() {
    var list = entityList
    for (var i = 0; i < list.length; i++) {
      var e = entities[list[i].entity_id]
      if (e) list[i] = e
    }
  }

  function applyStates(states) {
    var started = Date.now()
    var map = {}
    var changed = []
    var structural = false
    var count = 0
    for (var i = 0; i < states.length; i++) {
      var s = states[i]
      if (!s || !Model.isValidEntityId(s.entity_id)) continue
      var prev = entities[s.entity_id]
      map[s.entity_id] = decorate(s)
      count++
      if (!prev) structural = true
      else {
        if (prev.state !== s.state) changed.push([s, prev])
        if (prev.__sortName !== s.__sortName || prev.__hidden !== s.__hidden) structural = true
      }
    }
    if (!structural && count !== Object.keys(entities).length) structural = true
    entities = map
    for (var c = 0; c < changed.length; c++) maybeAlert(changed[c][0], changed[c][1])
    for (var id in pending) {
      var p = pending[id]
      var e = map[id]
      if (e && (e.state === p.state || p.expires <= Date.now())) delete pending[id]
    }
    if (structural) rebuildList()
    else refreshList()
    revision++
    _initialStatesLoaded = true
    lastSyncMs = Date.now() - started
  }

  // Pushed events arrive in bursts (a power meter alone can send several per
  // second). Each revision bump re-evaluates every visible binding, so bumps
  // are coalesced into one per frame-ish tick instead of one per event.
  property int eventsTotal: 0
  property int _eventsWindow: 0
  property real eventsPerSecond: 0

  function bumpRevision() {
    if (!revisionTimer.running) revisionTimer.start()
  }

  Timer {
    id: revisionTimer
    interval: 60
    onTriggered: root.revision++
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.connected
    onTriggered: { root.eventsPerSecond = Math.round(root._eventsWindow / 5 * 10) / 10; root._eventsWindow = 0 }
  }

  function applyStateChange(state) {
    if (!state || !Model.isValidEntityId(state.entity_id)) return
    eventsTotal++
    _eventsWindow++
    var previous = entities[state.entity_id]
    var isNew = !previous
    entities[state.entity_id] = decorate(state)
    if (pending[state.entity_id]) delete pending[state.entity_id]
    if (isNew) rebuildList()
    bumpRevision()
    if (previous && previous.state !== state.state) maybeAlert(state, previous)
  }

  // ---- Notifications --------------------------------------------------------

  function maybeAlert(state, previous) {
    if (!alertNotificationsEnabled || !_initialStatesLoaded) return
    var id = state.entity_id
    if (alertIds.indexOf(id) === -1) return
    // Flapping guard: one notification per entity per 3 s, and never twice
    // for the same state in a row.
    var now = Date.now()
    if (_lastAlertAt[id] && now - _lastAlertAt[id] < 3000) return
    if (_lastNotifiedState[id] === state.state) return
    _lastAlertAt[id] = now
    _lastNotifiedState[id] = state.state
    var urgency = state.state === "unavailable" ? "critical" : (Model.isOn(state) ? "normal" : "low")
    notify(Model.friendlyName(state), Model.alertText(state), Model.iconFor(state), urgency,
      ["omarchy-shell", "rewisch.homeassistant", "detail", id])
  }

  function onPersistentNotifications(kind, notifications) {
    if (!persistentNotificationsEnabled) return
    // "current" replays everything that already exists on (re)connect; only
    // fresh additions are worth a desktop notification.
    if (kind !== "added") return
    for (var key in notifications) {
      var n = notifications[key]
      if (!n) continue
      var title = String(n.title || "Home Assistant")
      var message = String(n.message || "")
      notify(title, message, Model.GLYPH.home, "normal", ["xdg-open", url + "/"])
    }
  }

  function notify(title, body, glyph, urgency, execArgs) {
    var cmd = ["omarchy-notification-send", "--app-name", "Home Assistant", "-g", glyph || Model.GLYPH.home, "-u", urgency || "normal", String(title || ""), String(body || "")]
    if (execArgs && execArgs.length) cmd = cmd.concat(["--exec"]).concat(execArgs)
    Quickshell.execDetached(cmd)
  }

  property var _entityRows: []

  function applyRegistry(kind, rows) {
    if (!rows || typeof rows.length !== "number") return
    var i
    if (kind === "area") {
      var a = {}
      for (i = 0; i < rows.length; i++) if (rows[i] && rows[i].area_id) a[rows[i].area_id] = String(rows[i].name || rows[i].area_id)
      areas = a
    } else if (kind === "device") {
      var d = {}
      for (i = 0; i < rows.length; i++) if (rows[i] && rows[i].id) d[rows[i].id] = rows[i].area_id || ""
      devices = d
    } else if (kind === "entity") {
      _entityRows = rows
      var em = {}
      for (i = 0; i < rows.length; i++) {
        var r = rows[i]
        if (!r || !r.entity_id) continue
        em[r.entity_id] = {
          diagnostic: r.entity_category === "diagnostic" || r.entity_category === "config",
          hidden: !!r.hidden_by || !!r.disabled_by
        }
      }
      entityMeta = em
      for (var id in entities) decorate(entities[id])
      rebuildList()
    }
    // An entity's area may come from its device, and the two registries can
    // answer in either order, so areas are recomputed whenever either lands.
    if (kind === "device" || kind === "entity") resolveAreas()
    revision++
  }

  function resolveAreas() {
    var ea = {}
    for (var i = 0; i < _entityRows.length; i++) {
      var r = _entityRows[i]
      if (!r || !r.entity_id) continue
      var areaId = r.area_id || (r.device_id ? devices[r.device_id] : "") || ""
      if (areaId) ea[r.entity_id] = areaId
    }
    entityArea = ea
  }

  function countOn() {
    var rev = revision
    var n = 0
    for (var i = 0; i < dashboardIds.length; i++) {
      var e = entityFor(dashboardIds[i])
      if (e && Model.isOn(e) && Model.controlKind(e) === "switch") n++
    }
    return n
  }

  // ---- Actions ------------------------------------------------------------

  function call(domain, service, data) {
    if (!activeTransport || !connected) {
      flashAction("Not connected")
      return false
    }
    activeTransport.callService({ domain: domain, service: service, data: data || {} })
    return true
  }

  function markPending(entityId, state, attributes) {
    pending[entityId] = { state: state, attributes: attributes || null, expires: Date.now() + 6000 }
    pendingSweep.restart()
    revision++
  }

  function runPrimary(entityId) {
    var e = entityFor(entityId)
    if (!e) return false
    var action = Model.primaryAction(e)
    if (!action) return false
    var expected = Model.optimisticState(e)
    if (expected !== null && !Model.isUnavailable(e)) markPending(entityId, expected)
    var ok = call(action.domain, action.service, action.data)
    if (ok && expected === null) flashAction(Model.friendlyName(e) + " activated")
    return ok
  }

  function turnOn(entityId) { return call(Model.domainOf(entityId), "turn_on", { entity_id: entityId }) }
  function turnOff(entityId) { return call(Model.domainOf(entityId), "turn_off", { entity_id: entityId }) }

  function setLightBrightness(entityId, percent) {
    var pct = Math.round(Model.clamp(percent, 0, 100))
    if (pct === 0) {
      markPending(entityId, "off")
      return call("light", "turn_off", { entity_id: entityId })
    }
    markPending(entityId, "on", { brightness: Math.round(pct / 100 * 255) })
    return call("light", "turn_on", { entity_id: entityId, brightness_pct: pct })
  }

  function setLightColorTemp(entityId, kelvin) {
    markPending(entityId, "on", { color_temp_kelvin: Math.round(kelvin) })
    return call("light", "turn_on", { entity_id: entityId, color_temp_kelvin: Math.round(kelvin) })
  }

  function setClimateTemperature(entityId, value) {
    var e = entityFor(entityId)
    markPending(entityId, e ? e.state : "heat", { temperature: value })
    return call("climate", "set_temperature", { entity_id: entityId, temperature: value })
  }

  function setHvacMode(entityId, mode) {
    markPending(entityId, mode)
    return call("climate", "set_hvac_mode", { entity_id: entityId, hvac_mode: mode })
  }

  function setPresetMode(entityId, mode) {
    var e = entityFor(entityId)
    markPending(entityId, e ? e.state : "heat", { preset_mode: mode })
    return call("climate", "set_preset_mode", { entity_id: entityId, preset_mode: mode })
  }

  function setFanPercentage(entityId, percent) {
    var pct = Math.round(Model.clamp(percent, 0, 100))
    markPending(entityId, pct === 0 ? "off" : "on", { percentage: pct })
    return call("fan", "set_percentage", { entity_id: entityId, percentage: pct })
  }

  function coverCommand(entityId, command) {
    var expected = command === "open_cover" ? "opening" : (command === "close_cover" ? "closing" : null)
    if (expected) markPending(entityId, expected)
    return call("cover", command, { entity_id: entityId })
  }

  function setCoverPosition(entityId, percent) {
    var pct = Math.round(Model.clamp(percent, 0, 100))
    var e = entityFor(entityId)
    markPending(entityId, e ? e.state : "open", { current_position: pct })
    return call("cover", "set_cover_position", { entity_id: entityId, position: pct })
  }

  function mediaCommand(entityId, command) {
    var e = entityFor(entityId)
    if (command === "media_play_pause" && e) markPending(entityId, e.state === "playing" ? "paused" : "playing")
    else if (command === "media_play") markPending(entityId, "playing")
    else if (command === "media_pause") markPending(entityId, "paused")
    else if (command === "turn_off") markPending(entityId, "off")
    else if (command === "turn_on") markPending(entityId, "on")
    return call("media_player", command, { entity_id: entityId })
  }

  function setVolume(entityId, level) {
    var e = entityFor(entityId)
    markPending(entityId, e ? e.state : "playing", { volume_level: level })
    return call("media_player", "volume_set", { entity_id: entityId, volume_level: Math.round(level * 100) / 100 })
  }

  function selectOption(entityId, option) {
    var domain = Model.domainOf(entityId)
    markPending(entityId, option)
    return call(domain, "select_option", { entity_id: entityId, option: option })
  }

  function setNumber(entityId, value) {
    var domain = Model.domainOf(entityId)
    markPending(entityId, String(value))
    return call(domain, "set_value", { entity_id: entityId, value: value })
  }

  function setLightColor(entityId, hue, saturation) {
    var h = Math.round(Model.clamp(hue, 0, 360)), sat = Math.round(Model.clamp(saturation, 0, 100))
    markPending(entityId, "on", { hs_color: [h, sat], color_mode: "hs" })
    return call("light", "turn_on", { entity_id: entityId, hs_color: [h, sat] })
  }

  // ---- History ----------------------------------------------------------------
  property var _historyCache: ({})
  signal historyReceived(string entityId, int hours, var points)
  signal historyFailed(string entityId, int hours)

  function requestHistory(entityId, hours) {
    var key = entityId + ":" + hours
    var cached = _historyCache[key]
    if (cached && Date.now() - cached.at < 60000) {
      historyReceived(entityId, hours, cached.points)
      return
    }
    if (!activeTransport || !connected || typeof activeTransport.fetchHistory !== "function") { historyFailed(entityId, hours); return }
    var end = new Date()
    var start = new Date(end.getTime() - hours * 3600 * 1000)
    activeTransport.fetchHistory(entityId, start.toISOString(), end.toISOString(), function(ok, raw) {
      if (!ok) { historyFailed(entityId, hours); return }
      var points = Model.parseHistory(raw, entityId)
      var keys = Object.keys(_historyCache)
      if (keys.length >= 40) delete _historyCache[keys[0]]
      _historyCache[key] = { at: Date.now(), points: points }
      historyReceived(entityId, hours, points)
    })
  }

  function setDashboardOrder(ids) {
    var next = []
    for (var i = 0; i < ids.length; i++) if (dashboardIds.indexOf(ids[i]) !== -1 && next.indexOf(ids[i]) === -1) next.push(ids[i])
    for (var j = 0; j < dashboardIds.length; j++) if (next.indexOf(dashboardIds[j]) === -1) next.push(dashboardIds[j])
    var same = next.length === dashboardIds.length
    for (var k = 0; same && k < next.length; k++) if (next[k] !== dashboardIds[k]) same = false
    if (same) return
    dashboardIds = next
    persistDashboard()
  }

  readonly property string dashboardGroup: String(pref("dashboardGroup", "none"))
  function cycleDashboardGroup() {
    var idx = Model.groupModeIndex(dashboardGroup)
    var next = Model.DASHBOARD_GROUPS[(idx + 1) % Model.DASHBOARD_GROUPS.length]
    setPref("dashboardGroup", next.key)
    flashAction(next.label)
  }

  function flashAction(text) {
    actionStatus = String(text || "")
    actionClear.restart()
  }

  function refresh() {
    if (activeTransport) activeTransport.refresh()
  }

  function reconnect() {
    lastError = ""
    if (!configured) return
    if (useWs) ws.reconnectNow()
    else if (useRest) rest.restart()
  }

  // ---- Dashboard editing --------------------------------------------------

  function isOnDashboard(entityId) {
    return dashboardIds.indexOf(String(entityId || "")) !== -1
  }

  function addToDashboard(entityId) {
    var id = String(entityId || "")
    if (id === "" || isOnDashboard(id)) return
    var next = dashboardIds.slice()
    next.push(id)
    dashboardIds = next
    persistDashboard()
  }

  function removeFromDashboard(entityId) {
    var id = String(entityId || "")
    var idx = dashboardIds.indexOf(id)
    if (idx === -1) return
    var next = dashboardIds.slice()
    next.splice(idx, 1)
    dashboardIds = next
    if (barIds.indexOf(id) !== -1) barIds = barIds.filter(function(b) { return b !== id })
    persistDashboard()
  }

  function toggleDashboard(entityId) {
    if (isOnDashboard(entityId)) removeFromDashboard(entityId)
    else addToDashboard(entityId)
  }

  function moveOnDashboard(entityId, delta) {
    var idx = dashboardIds.indexOf(String(entityId || ""))
    if (idx === -1) return false
    var target = idx + delta
    if (target < 0 || target >= dashboardIds.length) return false
    var next = dashboardIds.slice()
    var tmp = next[idx]
    next[idx] = next[target]
    next[target] = tmp
    dashboardIds = next
    persistDashboard()
    return true
  }

  function isPinned(entityId) {
    return barIds.indexOf(String(entityId || "")) !== -1
  }

  function togglePin(entityId) {
    var id = String(entityId || "")
    if (id === "") return
    var next = barIds.slice()
    var idx = next.indexOf(id)
    if (idx === -1) next.push(id)
    else next.splice(idx, 1)
    barIds = next
    persistDashboard()
  }

  function isAlerted(entityId) {
    return alertIds.indexOf(String(entityId || "")) !== -1
  }

  function toggleAlert(entityId) {
    var id = String(entityId || "")
    if (id === "") return
    var next = alertIds.slice()
    var idx = next.indexOf(id)
    if (idx === -1) next.push(id)
    else next.splice(idx, 1)
    alertIds = next
    persistDashboard()
    flashAction(idx === -1 ? "You will be notified when " + Model.friendlyName(entityFor(id)) + " changes" : "Alerts off for " + Model.friendlyName(entityFor(id)))
  }

  function needsAttention() {
    var rev = revision
    for (var i = 0; i < barIds.length; i++) {
      var e = entityFor(barIds[i])
      if (e && e.state === "unavailable") return true
    }
    for (var j = 0; j < alertIds.length; j++) {
      var a = entityFor(alertIds[j])
      if (!a) continue
      var domain = Model.domainOf(a.entity_id)
      if (domain === "alarm_control_panel" && (a.state === "triggered" || a.state === "pending")) return true
      if (domain === "binary_sensor" && a.state === "on") {
        var cls = (a.attributes || {}).device_class
        if (cls === "smoke" || cls === "gas" || cls === "moisture" || cls === "safety" || cls === "problem" || cls === "tamper" || cls === "carbon_monoxide") return true
      }
    }
    return false
  }

  function persistDashboard() {
    writeFile(dashboardPath, Model.serializeDashboard(dashboardIds, barIds, alertIds, prefs))
  }

  // ---- Automations ----------------------------------------------------------
  // Presence hooks. Omarchy has no lock/unlock hook, so the shared service
  // polls the shell's lock and idle status while any automation is set and
  // fires the chosen scene or script on each transition.
  readonly property var automations: pref("automations", {}) || {}
  readonly property bool automationsActive: automation("lock") !== "" || automation("unlock") !== "" || automation("screensaver") !== ""
  property int _lockedState: -1
  property int _screensaverState: -1

  function automation(kind) {
    var v = automations ? automations[kind] : ""
    return Model.isValidEntityId(v) ? v : ""
  }

  function setAutomation(kind, entityId) {
    var next = {}
    for (var k in automations) next[k] = automations[k]
    next[kind] = String(entityId || "")
    setPref("automations", next)
    _lockedState = -1
    _screensaverState = -1
    var e = entityFor(entityId)
    flashAction(entityId ? (e ? Model.friendlyName(e) : entityId) + " will run " + (kind === "lock" ? "on lock" : (kind === "unlock" ? "on unlock" : "when the screensaver starts")) : "Automation cleared")
  }

  function runAutomation(kind) {
    var id = automation(kind)
    if (id === "" || !connected) return
    var e = entityFor(id)
    if (!e) return
    if (Model.primaryAction(e)) runPrimary(id)
    else turnOn(id)
    flashAction("Ran " + Model.friendlyName(e) + " (" + kind + ")")
  }

  function applyPresence(locked, screensaver) {
    if (_lockedState !== -1 && locked !== (_lockedState === 1)) runAutomation(locked ? "lock" : "unlock")
    if (_screensaverState !== -1 && screensaver && _screensaverState === 0) runAutomation("screensaver")
    _lockedState = locked ? 1 : 0
    _screensaverState = screensaver ? 1 : 0
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.active && root.connected && root.automationsActive
    triggeredOnStart: true
    onTriggered: if (!presenceProc.running) presenceProc.running = true
  }

  Process {
    id: presenceProc
    command: ["sh", "-c", "omarchy-shell lock status 2>/dev/null; echo; omarchy-shell idle status 2>/dev/null"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var lines = String(presenceProc.stdout.text || "").split("\n").filter(function(l) { return l.trim() !== "" })
      if (lines.length < 2) return
      var lock = Model.parseJson(lines[0], null)
      var idle = Model.parseJson(lines[1], null)
      if (!lock || !idle) return
      var screensaverOn = idle.screensaverStarted === true || Number(idle.screensaverWindows || 0) > 0
        || (idle.processes && idle.processes.screensaver === true)
      root.applyPresence(lock.locked === true || lock.sessionLocked === true, screensaverOn)
    }
  }

  // ---- Omarchy menu ---------------------------------------------------------
  // A generated block between marker comments in the user's menu extension
  // file. Everything outside the markers is preserved byte for byte.
  readonly property string menuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  readonly property string menuMarkerStart: "  // >>> rewisch.homeassistant — generated from your dashboard, edits here are overwritten"
  readonly property string menuMarkerEnd: "  // <<< rewisch.homeassistant"
  readonly property bool menuSync: pref("menuSync", false) === true

  function setMenuSync(on) {
    setPref("menuSync", !!on)
    syncMenu()
  }

  function menuBlock() {
    var lines = [menuMarkerStart]
    lines.push('  "home": {"icon":"' + Model.GLYPH.home + '","label":"Home","aliases":["home-assistant","ha"]},')
    lines.push('  "home.open": {"icon":"' + Model.GLYPH.home + '","label":"Open panel","action":"omarchy-shell rewisch.homeassistant open"},')
    lines.push('  "home.browse": {"icon":"' + Model.GLYPH.search + '","label":"Browse entities","action":"omarchy-shell rewisch.homeassistant browse"},')
    var used = {}
    for (var i = 0; i < dashboardIds.length; i++) {
      var id = dashboardIds[i]
      if (!Model.isValidEntityId(id)) continue
      var e = entityFor(id)
      var name = e ? Model.friendlyName(e) : id
      var key = Model.slug(name) || Model.slug(id)
      var n = 2
      while (used[key]) key = Model.slug(name) + "-" + (n++)
      used[key] = true
      var glyph = Model.domainMeta(Model.domainOf(id)).icon
      var entry = { icon: glyph, label: name }
      // Both fields are run by the menu through a shell (`checked` on every
      // open, without a click), so the id is validated above and quoted here.
      var qid = Model.shellQuote(id)
      if (e && Model.primaryAction(e)) {
        entry.action = "omarchy-shell rewisch.homeassistant toggleEntity " + qid
        if (Model.controlKind(e) === "switch")
          entry.checked = "[[ \"$(omarchy-shell rewisch.homeassistant state " + qid + ")\" == on ]]"
      } else {
        entry.action = "omarchy-shell rewisch.homeassistant detail " + qid
      }
      lines.push('  "home.' + key + '": ' + JSON.stringify(entry) + ",")
    }
    lines.push(menuMarkerEnd)
    return lines.join("\n")
  }

  function spliceMenu(text) {
    return Model.spliceMenuBlock(text, menuSync ? menuBlock() : "", menuMarkerStart, menuMarkerEnd)
  }

  function syncMenu() {
    if (!active || !dashboardLoaded) return
    if (menuReadProc.running) { menuSyncPending = true; return }
    menuReadProc.running = true
  }

  property bool menuSyncPending: false

  Process {
    id: menuReadProc
    command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "read", root.menuPath]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var current = String(menuReadProc.stdout.text || "")
      var next = root.spliceMenu(current)
      if (next !== current) root.writeFile(root.menuPath, next)
      if (root.menuSyncPending) { root.menuSyncPending = false; Qt.callLater(root.syncMenu) }
    }
  }

  onDashboardIdsChanged: if (menuSync && dashboardLoaded) menuSyncTimer.restart()
  onEntityCountChanged: if (menuSync && dashboardLoaded && entityCount > 0) menuSyncTimer.restart()

  Timer {
    id: menuSyncTimer
    interval: 800
    onTriggered: root.syncMenu()
  }

  function pref(key, fallback) {
    var v = prefs ? prefs[key] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function setPref(key, value) {
    var next = {}
    for (var k in prefs) next[k] = prefs[k]
    next[key] = value
    prefs = next
    persistDashboard()
  }

  // ---- Connection editing -------------------------------------------------

  // One-off check with candidate credentials, independent of the live
  // transport, so the setup view can validate before anything is saved.
  // An address without a scheme is tried over https first; plain http only
  // when nothing answers there, so the token is not sent in the clear when
  // the instance does offer TLS. `probedUrl` is the address that succeeded.
  property string probedUrl: ""
  property string _probeBase: ""
  property string _probeFallback: ""
  property string _probeToken: ""

  function probe(candidateUrl, candidateToken) {
    var raw = String(candidateUrl || "").trim()
    var tok = String(candidateToken || "").trim()
    if (raw === "") { probeFinished(false, "Enter the URL of your Home Assistant instance."); return }
    if (tok === "") { probeFinished(false, "Paste a long-lived access token."); return }
    if (probeProc.running) return
    probedUrl = ""
    _probeToken = tok
    _probeFallback = Model.hasScheme(raw) ? "" : Model.normalizeUrl(raw, "http")
    runProbe(Model.hasScheme(raw) ? Model.normalizeUrl(raw) : Model.normalizeUrl(raw, "https"))
  }

  function runProbe(base) {
    _probeBase = base
    probeProc.environment = ({ HA_TOKEN: _probeToken })
    probeProc.command = ["sh", "-c", "curl -sS -m 10 --max-filesize 1048576 -H \"Authorization: Bearer $HA_TOKEN\" -w '\\n%{http_code}' \"$1\" | head -c 1048576", "curl", base + "/api/config"]
    probeProc.running = true
  }

  function saveConnection(candidateUrl, candidateToken) {
    var base = Model.normalizeUrl(candidateUrl)
    var tok = String(candidateToken || "").trim()
    url = base
    token = tok
    lastError = ""
    status = configured ? "connecting" : "idle"
    writeFile(connectionPath, Model.serializeConnection(base, tok))
  }

  function clearConnection() {
    saveConnection("", "")
    applyStates([])
    haConfig = ({})
    status = "idle"
  }

  // ---- Files --------------------------------------------------------------

  property var _writeQueue: []

  function writeFile(path, content) {
    if (!active) return
    for (var i = 0; i < _writeQueue.length; i++) {
      if (_writeQueue[i].path === path) { _writeQueue[i].content = content; pumpWrites(); return }
    }
    _writeQueue.push({ path: path, content: content })
    pumpWrites()
  }

  function pumpWrites() {
    if (writer.running || _writeQueue.length === 0) return
    var job = _writeQueue.shift()
    writer.environment = ({ HA_CONTENT: job.content })
    // New files (the plugin's own) are created owner-only through the umask;
    // an existing file keeps its mode, so the user's menu extension is not
    // silently tightened to 600 when the block is written into it.
    writer.command = ["sh", "-c", "umask 077; mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$HA_CONTENT\" > \"$1.tmp\" && { [ ! -e \"$1\" ] || chmod --reference=\"$1\" \"$1.tmp\"; } && mv -f \"$1.tmp\" \"$1\"", "write", job.path]
    writer.running = true
  }

  Process {
    id: writer
    onExited: function(exitCode) {
      if (exitCode !== 0) root.flashAction("Could not save settings")
      root.pumpWrites()
    }
  }

  Process {
    id: probeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var text = String(probeProc.stdout.text || "")
      var nl = text.lastIndexOf("\n")
      var code = nl === -1 ? 0 : parseInt(text.slice(nl + 1).trim(), 10)
      if (code === 0 && root._probeFallback !== "") {
        // Nothing answered over TLS (refused, reset, or not a TLS port); the
        // fallback is only taken when the server was not reached at all.
        var fallback = root._probeFallback
        root._probeFallback = ""
        root.runProbe(fallback)
        return
      }
      root._probeFallback = ""
      root._probeToken = ""
      if (text.length >= 1048576) { root.probeFinished(false, "The response was larger than expected for a Home Assistant instance."); return }
      if (code === 200) {
        var cfg = null
        try { cfg = JSON.parse(text.slice(0, nl)) } catch (e) { cfg = null }
        if (cfg && cfg.location_name) root.haConfig = cfg
        root.probedUrl = root._probeBase
        var msg = cfg && cfg.location_name ? "Connected to " + cfg.location_name : "Connected"
        if (root._probeBase.indexOf("http://") === 0) msg += " (unencrypted connection)"
        root.probeFinished(true, msg)
      } else if (code === 401 || code === 403) {
        root.probeFinished(false, "Home Assistant rejected the token.")
      } else if (code === 404) {
        root.probeFinished(false, "That URL does not look like a Home Assistant instance.")
      } else if (code > 0) {
        root.probeFinished(false, "Unexpected response (" + code + ").")
      } else {
        var err = String(probeProc.stderr.text || "").trim().replace(/^curl:\s*\(\d+\)\s*/, "")
        root.probeFinished(false, err !== "" ? err : "Could not reach that URL.")
      }
    }
  }

  FileView {
    id: connectionFile
    path: root.active ? root.connectionPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseConnectionFile(text())
      root.url = parsed.url
      root.token = parsed.token
      root.configLoaded = true
      if (root.configured && root.status === "idle") root.status = "connecting"
    }
    onLoadFailed: {
      root.configLoaded = true
    }
  }

  FileView {
    id: dashboardFile
    path: root.active ? root.dashboardPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseDashboardFile(text())
      root.dashboardIds = parsed.entities
      root.barIds = parsed.bar
      root.alertIds = parsed.alerts
      root.prefs = parsed.prefs
      root.dashboardLoaded = true
    }
    onLoadFailed: root.dashboardLoaded = true
  }

  // A startup race can leave the first read empty, and a file created after
  // the shell started (first-run on another monitor, hand edits) is not
  // always reported by the watcher. Reload on a short delay and again every
  // time the panel opens; identical content changes nothing.
  function reloadFiles() {
    if (!active) return
    connectionFile.reload()
    dashboardFile.reload()
  }

  onActiveChanged: if (active) Qt.callLater(reloadFiles)

  Timer {
    interval: 1500
    running: root.active
    onTriggered: root.reloadFiles()
  }

  Timer {
    interval: 5000
    running: root.active && !root.configured
    repeat: true
    onTriggered: connectionFile.reload()
  }

  // ---- Transports ---------------------------------------------------------

  WsTransport {
    id: ws
    baseUrl: root.url
    token: root.token
    enabled: root.active && root.useWs && root.configured
    onStatesReceived: function(states) { root.onStates(states) }
    onEntityStateChanged: function(state) { root.applyStateChange(state) }
    onConfigReceived: function(cfg) { root.haConfig = cfg }
    onRegistryReceived: function(kind, rows) { root.applyRegistry(kind, rows) }
    onPersistentNotifications: function(kind, notifications) { root.onPersistentNotifications(kind, notifications) }
    onAuthOk: root.onAuthOk()
    onAuthInvalid: function(message) { root.onAuthInvalid(message) }
    onTransportError: function(message) { root.onTransportError(message) }
    onCallFinished: function(call, success, message) { root.onCallFinished(call, success, message) }
  }

  RestTransport {
    id: rest
    baseUrl: root.url
    token: root.token
    intervalSec: root.refreshIntervalSec
    enabled: root.active && root.useRest && root.configured
    onStatesReceived: function(states) { root.onStates(states) }
    onConfigReceived: function(cfg) { root.haConfig = cfg }
    onAuthOk: root.onAuthOk()
    onAuthInvalid: function(message) { root.onAuthInvalid(message) }
    onTransportError: function(message) { root.onTransportError(message) }
    onCallFinished: function(call, success, message) { root.onCallFinished(call, success, message) }
  }

  function onStates(states) {
    applyStates(states)
    status = "connected"
    lastError = ""
  }

  function onAuthOk() {
    status = "connected"
    lastError = ""
  }

  function onAuthInvalid(message) {
    status = "auth_failed"
    lastError = String(message || "Authentication failed")
  }

  function onTransportError(message) {
    lastError = String(message || "Connection error")
    if (status !== "auth_failed") status = "error"
  }

  function onCallFinished(call, success, message) {
    if (success) return
    var id = call && call.data ? call.data.entity_id : ""
    if (id && pending[id]) { delete pending[id]; revision++ }
    flashAction(message || "Service call failed")
  }

  onConfiguredChanged: {
    if (!configured) { status = "idle"; return }
    if (status === "idle") status = "connecting"
  }

  onTransportKindChanged: {
    if (transportKind === "none" && configured) {
      status = "unsupported"
      lastError = transportSetting === "WebSocket" ? "WebSocket forced but the live transport cannot start (python3 missing)." : "No transport available."
    }
  }

  Timer {
    id: pendingSweep
    interval: 2000
    repeat: true
    onTriggered: {
      var now = Date.now()
      var changed = false
      var any = false
      for (var id in root.pending) {
        any = true
        if (root.pending[id].expires <= now) { delete root.pending[id]; changed = true }
      }
      if (changed) root.revision++
      if (!any) stop()
    }
  }

  Timer {
    id: actionClear
    interval: 3500
    onTriggered: root.actionStatus = ""
  }
}
