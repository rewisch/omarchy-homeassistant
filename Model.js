.pragma library

// Pure helpers shared by the service and the views. No QML state in here so
// every function is trivially testable and hot-reload safe.

function domainOf(entityId) {
  var id = String(entityId || "")
  var dot = id.indexOf(".")
  return dot === -1 ? "" : id.slice(0, dot)
}

function objectIdOf(entityId) {
  var id = String(entityId || "")
  var dot = id.indexOf(".")
  return dot === -1 ? id : id.slice(dot + 1)
}

function friendlyName(entity) {
  if (!entity) return ""
  var attrs = entity.attributes || {}
  var name = attrs.friendly_name
  if (typeof name === "string" && name.trim() !== "") return name.trim()
  return titleCase(objectIdOf(entity.entity_id).replace(/_/g, " "))
}

function titleCase(text) {
  var s = String(text || "").replace(/_/g, " ").trim()
  if (s === "") return ""
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// ---- Icons (Nerd Font, Material Design set) -------------------------------

var GLYPH = {
  home: "󰟐",           // home-assistant
  homePlain: "󰋜",
  search: "󰍉",
  cog: "󰒓",
  refresh: "󰑐",
  plus: "󰐕",
  minus: "󰍴",
  star: "󰓎",
  starOutline: "󰓒",
  pin: "󰐃",
  pinOff: "󰐄",
  check: "󰄬",
  close: "󰅖",
  chevronLeft: "󰅁",
  chevronRight: "󰅂",
  chevronUp: "󰅃",
  chevronDown: "󰅀",
  play: "󰐊",
  pause: "󰏤",
  next: "󰒭",
  prev: "󰒮",
  volume: "󰕾",
  volumeOff: "󰖁",
  power: "󰐥",
  flash: "󰉁",
  eye: "󰈈",
  eyeOff: "󰈉",
  linkOn: "󰌘",
  linkOff: "󰌙",
  arrowUp: "󰁝",
  arrowDown: "󰁅",
  stop: "󰓛",
  tune: "󰘮",
  bolt: "󱐋",
  alert: "󰀦",
  spinner: "󰦖",
  bell: "󰂚",
  bellOff: "󰂛",
  copy: "󰆏",
  drag: "󰇙",
  camera: "󰄀",
  chart: "󰧌"
}

var DOMAINS = {
  light:               { label: "Light",        icon: "󰌵", offIcon: "󰌶" },
  switch:              { label: "Switch",       icon: "󰔡", offIcon: "󰔢" },
  input_boolean:       { label: "Toggle",       icon: "󰔡", offIcon: "󰔢" },
  fan:                 { label: "Fan",          icon: "󰈐" },
  sensor:              { label: "Sensor",       icon: "󰓅" },
  binary_sensor:       { label: "Binary sensor",icon: "󰐾", offIcon: "󰐽" },
  climate:             { label: "Climate",      icon: "󰔏" },
  humidifier:          { label: "Humidifier",   icon: "󰖎" },
  water_heater:        { label: "Water heater", icon: "󰖎" },
  cover:               { label: "Cover",        icon: "󱄜" },
  media_player:        { label: "Media",        icon: "󰓃" },
  scene:               { label: "Scene",        icon: "󰏘" },
  script:              { label: "Script",       icon: "󰆍" },
  automation:          { label: "Automation",   icon: "󰚩" },
  button:              { label: "Button",       icon: "󱈖" },
  input_button:        { label: "Button",       icon: "󱈖" },
  lock:                { label: "Lock",         icon: "󰌾", offIcon: "󰿆" },
  alarm_control_panel: { label: "Alarm",        icon: "󰒃" },
  siren:               { label: "Siren",        icon: "󰀡" },
  camera:              { label: "Camera",       icon: "󰄀" },
  weather:             { label: "Weather",      icon: "󰖕" },
  sun:                 { label: "Sun",          icon: "󰖙" },
  person:              { label: "Person",       icon: "󰀄" },
  device_tracker:      { label: "Tracker",      icon: "󰍎" },
  vacuum:              { label: "Vacuum",       icon: "󰜥" },
  remote:              { label: "Remote",       icon: "󰑔" },
  number:              { label: "Number",       icon: "󰎠" },
  input_number:        { label: "Number",       icon: "󰎠" },
  select:              { label: "Select",       icon: "󰉹" },
  input_select:        { label: "Select",       icon: "󰉹" },
  update:              { label: "Update",       icon: "󰚰" },
  calendar:            { label: "Calendar",     icon: "󰃭" },
  timer:               { label: "Timer",        icon: "󰔛" },
  zone:                { label: "Zone",         icon: "󰍎" },
  counter:             { label: "Counter",      icon: "󰎠" },
  input_datetime:      { label: "Date/time",    icon: "󰅐" },
  input_text:          { label: "Text",         icon: "󰈚" },
  event:               { label: "Event",        icon: "󰉁" },
  image:               { label: "Image",        icon: "󰋩" },
  todo:                { label: "To-do",        icon: "󰄬" },
  valve:               { label: "Valve",        icon: "󰔏" },
  lawn_mower:          { label: "Mower",        icon: "󰜥" },
  text:                { label: "Text",         icon: "󰈚" },
  date:                { label: "Date",         icon: "󰃭" },
  time:                { label: "Time",         icon: "󰅐" },
  datetime:            { label: "Date/time",    icon: "󰅐" },
  notify:              { label: "Notify",       icon: "󰂚" },
  tts:                 { label: "Speech",       icon: "󰓃" },
  stt:                 { label: "Speech",       icon: "󰍬" },
  conversation:        { label: "Assist",       icon: "󰚩" },
  wake_word:           { label: "Wake word",    icon: "󰍬" },
  assist_satellite:    { label: "Assist",       icon: "󰍬" }
}

var DEVICE_CLASS_ICONS = {
  temperature: "󰔏", humidity: "󰖎", power: "󰉁", energy: "󰚥", battery: "󰁹",
  illuminance: "󰖙", pressure: "󰓅", atmospheric_pressure: "󰓅", motion: "󰶑",
  moving: "󰶑", occupancy: "󰀄", presence: "󰀄", door: "󰠚", garage_door: "󰠚",
  window: "󰖮", opening: "󰠚", connectivity: "󰌘", moisture: "󰖌", smoke: "󰀡",
  gas: "󰀡", carbon_dioxide: "󰟤", carbon_monoxide: "󰟤", co2: "󰟤",
  timestamp: "󰅐", date: "󰃭", duration: "󰔛", signal_strength: "󰖩",
  voltage: "󰥛", current: "󰥜", frequency: "󰥛", distance: "󰑫", speed: "󰖝",
  wind_speed: "󰖝", precipitation: "󰖗", precipitation_intensity: "󰖗",
  monetary: "󰄔", pm25: "󰟤", pm10: "󰟤", pm1: "󰟤", volatile_organic_compounds: "󰟤",
  aqi: "󰟤", data_size: "󰋊", data_rate: "󰓅", plug: "󰚥", outlet: "󰚥",
  light: "󰌵", lock: "󰌾", running: "󰐊", problem: "󰀦", safety: "󰒃",
  sound: "󰓃", vibration: "󰶑", update: "󰚰", cold: "󰔏", heat: "󰔏",
  tamper: "󰀦", water: "󰖌", weight: "󰓅", volume: "󰖌", area: "󰓅",
  ph: "󰖌", irradiance: "󰖙", sound_pressure: "󰓃", shutter: "󱄜", blind: "󱄜",
  curtain: "󱄜", awning: "󱄜", damper: "󱄜", gate: "󰠚", shade: "󱄜",
  tv: "󰔂", speaker: "󰓃", receiver: "󰓃"
}

function domainMeta(domain) {
  return DOMAINS[domain] || { label: titleCase(domain), icon: "󰇘" }
}

function iconFor(entity) {
  if (!entity) return "󰇘"
  var attrs = entity.attributes || {}
  var domain = domainOf(entity.entity_id)
  var cls = attrs.device_class
  if (typeof cls === "string" && DEVICE_CLASS_ICONS[cls]) {
    if (domain === "binary_sensor") {
      if (cls === "door" || cls === "garage_door" || cls === "opening" || cls === "gate")
        return entity.state === "on" ? "󰠜" : "󰠚"
      if (cls === "window") return entity.state === "on" ? "󰖯" : "󰖮"
      if (cls === "connectivity") return entity.state === "on" ? "󰌘" : "󰌙"
    }
    return DEVICE_CLASS_ICONS[cls]
  }
  if (domain === "media_player") {
    if (entity.state === "playing") return "󰐊"
    if (entity.state === "paused") return "󰏤"
    return "󰓃"
  }
  if (domain === "cover") {
    if (entity.state === "open" || entity.state === "opening") return "󰕑"
    return "󱄜"
  }
  var meta = domainMeta(domain)
  if (meta.offIcon && (entity.state === "off" || entity.state === "unlocked")) return meta.offIcon
  return meta.icon
}

// ---- State formatting ----------------------------------------------------

var STATE_LABELS = {
  on: "On", off: "Off", unavailable: "Unavailable", unknown: "—",
  open: "Open", closed: "Closed", opening: "Opening…", closing: "Closing…",
  playing: "Playing", paused: "Paused", idle: "Idle", standby: "Standby", buffering: "Buffering…",
  heat: "Heating", cool: "Cooling", heat_cool: "Auto", auto: "Auto", dry: "Dry", fan_only: "Fan", 
  home: "Home", not_home: "Away", locked: "Locked", unlocked: "Unlocked", locking: "Locking…", unlocking: "Unlocking…", jammed: "Jammed",
  docked: "Docked", cleaning: "Cleaning", returning: "Returning", error: "Error",
  armed_home: "Armed home", armed_away: "Armed away", armed_night: "Armed night", disarmed: "Disarmed", pending: "Pending", triggered: "Triggered", arming: "Arming…",
  above_horizon: "Up", below_horizon: "Down", active: "Active", paused_timer: "Paused"
}

function isNumeric(value) {
  if (typeof value === "number") return isFinite(value)
  if (typeof value !== "string" || value.trim() === "") return false
  return isFinite(Number(value))
}

function formatNumber(value, precision) {
  var n = Number(value)
  if (!isFinite(n)) return String(value)
  if (precision !== undefined && precision !== null) return n.toFixed(precision)
  if (Math.abs(n) >= 100) return String(Math.round(n))
  if (Number.isInteger(n)) return String(n)
  return String(Math.round(n * 10) / 10)
}

function withUnit(value, unit) {
  var u = String(unit || "")
  if (u === "") return value
  if (u === "%" || u.charAt(0) === "°") return value + u
  return value + " " + u
}

function stateLabel(state) {
  var s = String(state === undefined || state === null ? "" : state)
  if (STATE_LABELS[s]) return STATE_LABELS[s]
  return titleCase(s)
}

// One-line state for list rows and the bar pill.
function displayState(entity) {
  if (!entity) return ""
  var attrs = entity.attributes || {}
  var domain = domainOf(entity.entity_id)
  var state = entity.state
  if (state === "unavailable" || state === "unknown") return stateLabel(state)
  if (domain === "climate") {
    var target = attrs.temperature
    var current = attrs.current_temperature
    var unit = attrs.temperature_unit || "°"
    var parts = [stateLabel(state)]
    if (isNumeric(target)) parts.push(withUnit(formatNumber(target, 1), unit))
    else if (isNumeric(current)) parts.push(withUnit(formatNumber(current, 1), unit))
    return parts.join(" · ")
  }
  if (domain === "media_player") {
    if ((state === "playing" || state === "paused") && attrs.media_title)
      return stateLabel(state) + " · " + attrs.media_title
    return stateLabel(state)
  }
  if (domain === "light" && state === "on" && isNumeric(attrs.brightness))
    return Math.round(Number(attrs.brightness) / 255 * 100) + "%"
  if (domain === "fan" && state === "on" && isNumeric(attrs.percentage))
    return Math.round(Number(attrs.percentage)) + "%"
  if (domain === "cover" && isNumeric(attrs.current_position) && state !== "closed" && state !== "open")
    return stateLabel(state) + " · " + Math.round(Number(attrs.current_position)) + "%"
  if (domain === "cover" && isNumeric(attrs.current_position) && state === "open" && Number(attrs.current_position) < 100)
    return Math.round(Number(attrs.current_position)) + "% open"
  if (domain === "sun") return stateLabel(state)
  if (domain === "update") return state === "on" ? "Update available" : "Up to date"
  if (isNumeric(state)) {
    var precision = isNumeric(attrs.display_precision) ? Number(attrs.display_precision) : undefined
    return withUnit(formatNumber(state, precision), attrs.unit_of_measurement)
  }
  if (domain === "device_tracker" || domain === "person") return stateLabel(state)
  if (domain === "timer" && state === "active" && attrs.remaining) return "Active · " + attrs.remaining
  return stateLabel(state)
}

// Short form for the bar pill.
function barLabel(entity) {
  if (!entity) return ""
  var domain = domainOf(entity.entity_id)
  var attrs = entity.attributes || {}
  if (entity.state === "unavailable" || entity.state === "unknown") return "—"
  if (domain === "climate") {
    var t = isNumeric(attrs.current_temperature) ? attrs.current_temperature : attrs.temperature
    return isNumeric(t) ? withUnit(formatNumber(t, 1), attrs.temperature_unit || "°") : stateLabel(entity.state)
  }
  if (isNumeric(entity.state)) {
    var precision = isNumeric(attrs.display_precision) ? Number(attrs.display_precision) : undefined
    return withUnit(formatNumber(entity.state, precision), attrs.unit_of_measurement)
  }
  return stateLabel(entity.state)
}

function isOn(entity) {
  if (!entity) return false
  var s = entity.state
  return s === "on" || s === "open" || s === "opening" || s === "playing" || s === "unlocked"
    || s === "heat" || s === "cool" || s === "heat_cool" || s === "auto" || s === "dry" || s === "fan_only"
    || s === "cleaning" || s === "home" || s === "active"
}

function isUnavailable(entity) {
  return !entity || entity.state === "unavailable" || entity.state === "unknown"
}

// ---- Capabilities ---------------------------------------------------------

var TOGGLE_DOMAINS = {
  light: true, switch: true, input_boolean: true, fan: true, automation: true,
  humidifier: true, siren: true, remote: true, media_player: false
}

// Which trailing control a list row shows.
//   "switch" -> ToggleSwitch, "run" -> activate button, "lock" -> lock/unlock,
//   "media" -> play/pause, "cover" -> up/down, "none" -> just the state text.
function controlKind(entity) {
  if (!entity) return "none"
  var domain = domainOf(entity.entity_id)
  if (TOGGLE_DOMAINS[domain]) return "switch"
  if (domain === "scene" || domain === "script" || domain === "button" || domain === "input_button") return "run"
  if (domain === "lock") return "lock"
  if (domain === "media_player") return "media"
  if (domain === "cover") return "cover"
  if (domain === "vacuum") return "run"
  return "none"
}

function hasDetail(entity) {
  if (!entity) return false
  var domain = domainOf(entity.entity_id)
  return domain === "light" || domain === "climate" || domain === "media_player" || domain === "cover" || domain === "fan" || true
}

// The service call fired by Enter / click on the row body.
function primaryAction(entity) {
  if (!entity) return null
  var domain = domainOf(entity.entity_id)
  var id = entity.entity_id
  if (TOGGLE_DOMAINS[domain]) return { domain: domain, service: "toggle", data: { entity_id: id } }
  if (domain === "scene") return { domain: "scene", service: "turn_on", data: { entity_id: id } }
  if (domain === "script") return { domain: "script", service: "turn_on", data: { entity_id: id } }
  if (domain === "button" || domain === "input_button") return { domain: domain, service: "press", data: { entity_id: id } }
  if (domain === "lock") return { domain: "lock", service: entity.state === "locked" ? "unlock" : "lock", data: { entity_id: id } }
  if (domain === "media_player") return { domain: "media_player", service: "media_play_pause", data: { entity_id: id } }
  if (domain === "cover") return { domain: "cover", service: "toggle", data: { entity_id: id } }
  if (domain === "vacuum") return { domain: "vacuum", service: entity.state === "cleaning" ? "return_to_base" : "start", data: { entity_id: id } }
  return null
}

// The state we expect right after primaryAction, for optimistic UI.
function optimisticState(entity) {
  if (!entity) return null
  var domain = domainOf(entity.entity_id)
  if (TOGGLE_DOMAINS[domain]) return entity.state === "on" ? "off" : "on"
  if (domain === "lock") return entity.state === "locked" ? "unlocking" : "locking"
  if (domain === "media_player") return entity.state === "playing" ? "paused" : "playing"
  if (domain === "cover") return entity.state === "open" || entity.state === "opening" ? "closing" : "opening"
  return null
}

function supportsFeature(entity, bit) {
  if (!entity) return false
  var f = Number((entity.attributes || {}).supported_features || 0)
  return (f & bit) === bit
}

var LIGHT_BRIGHTNESS_MODES = { brightness: true, color_temp: true, hs: true, xy: true, rgb: true, rgbw: true, rgbww: true, white: true }

function lightSupportsBrightness(entity) {
  var modes = (entity && entity.attributes || {}).supported_color_modes
  if (!modes || typeof modes.length !== "number") return false
  for (var i = 0; i < modes.length; i++) if (LIGHT_BRIGHTNESS_MODES[modes[i]]) return true
  return false
}

var LIGHT_COLOR_MODES = { hs: true, xy: true, rgb: true, rgbw: true, rgbww: true }

function lightSupportsColor(entity) {
  var modes = (entity && entity.attributes || {}).supported_color_modes
  if (!modes || typeof modes.length !== "number") return false
  for (var i = 0; i < modes.length; i++) if (LIGHT_COLOR_MODES[modes[i]]) return true
  return false
}

// Current hue/saturation of a light, derived from whatever colour attribute
// Home Assistant exposes. Returns null when the light shows white.
function lightHs(entity) {
  var attrs = entity && entity.attributes || {}
  var mode = attrs.color_mode
  if (mode === "color_temp" || mode === "white") return null
  var hs = attrs.hs_color
  if (hs && typeof hs.length === "number" && hs.length >= 2 && isNumeric(hs[0]) && isNumeric(hs[1])) return { h: Number(hs[0]), s: Number(hs[1]) }
  var rgb = attrs.rgb_color
  if (rgb && typeof rgb.length === "number" && rgb.length >= 3) return rgbToHs(Number(rgb[0]), Number(rgb[1]), Number(rgb[2]))
  return null
}

function rgbToHs(r, g, b) {
  r /= 255; g /= 255; b /= 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var d = max - min
  var h = 0
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  var s = max === 0 ? 0 : d / max
  return { h: h, s: s * 100 }
}

var SWATCHES = [
  { name: "Warm", h: 30, s: 60 }, { name: "Red", h: 0, s: 100 }, { name: "Orange", h: 30, s: 100 },
  { name: "Yellow", h: 55, s: 100 }, { name: "Green", h: 120, s: 100 }, { name: "Teal", h: 175, s: 100 },
  { name: "Blue", h: 220, s: 100 }, { name: "Purple", h: 275, s: 100 }, { name: "Pink", h: 320, s: 80 }
]

function lightSupportsColorTemp(entity) {
  var modes = (entity && entity.attributes || {}).supported_color_modes
  if (!modes || typeof modes.length !== "number") return false
  for (var i = 0; i < modes.length; i++) if (modes[i] === "color_temp") return true
  return false
}

// Cover supported_features bits (homeassistant.components.cover)
var COVER_OPEN = 1, COVER_CLOSE = 2, COVER_SET_POSITION = 4, COVER_STOP = 8
// Climate supported_features bits
var CLIMATE_TARGET_TEMP = 1, CLIMATE_TARGET_TEMP_RANGE = 2, CLIMATE_FAN_MODE = 8, CLIMATE_PRESET = 16
// Media player supported_features bits
var MEDIA_PAUSE = 1, MEDIA_SEEK = 2, MEDIA_VOLUME_SET = 4, MEDIA_VOLUME_MUTE = 8, MEDIA_PREV = 16, MEDIA_NEXT = 32, MEDIA_TURN_ON = 128, MEDIA_TURN_OFF = 256, MEDIA_PLAY = 16384, MEDIA_SELECT_SOURCE = 2048
// Fan
var FAN_SET_SPEED = 1

// ---- History ----------------------------------------------------------------

// Normalises both history formats into [{ t: ms, v: number }]:
//   WebSocket history/history_during_period: { id: [{ s, lu }, ...] }
//   REST /api/history/period:                 [[{ state, last_updated }, ...]]
function parseHistory(raw, entityId) {
  var rows = null
  if (raw && !Array.isArray(raw) && raw[entityId]) rows = raw[entityId]
  else if (Array.isArray(raw)) rows = raw.length > 0 && Array.isArray(raw[0]) ? raw[0] : raw
  if (!rows || typeof rows.length !== "number") return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!r) continue
    var state = r.s !== undefined ? r.s : r.state
    if (!isNumeric(state)) continue
    var t = r.lu !== undefined ? Number(r.lu) * 1000 : Date.parse(r.last_updated || r.last_changed || "")
    if (!isFinite(t)) continue
    out.push({ t: t, v: Number(state) })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

function historyStats(points) {
  if (!points || points.length === 0) return null
  var min = points[0].v, max = points[0].v
  for (var i = 1; i < points.length; i++) { if (points[i].v < min) min = points[i].v; if (points[i].v > max) max = points[i].v }
  return { min: min, max: max, first: points[0].v, last: points[points.length - 1].v, count: points.length }
}

var HISTORY_RANGES = [
  { key: "3h", label: "3 h", hours: 3 },
  { key: "24h", label: "24 h", hours: 24 },
  { key: "7d", label: "7 days", hours: 168 }
]

function hasHistory(entity) {
  if (!entity) return false
  var domain = domainOf(entity.entity_id)
  return (domain === "sensor" || domain === "number" || domain === "input_number" || domain === "counter") && isNumeric(entity.state)
}

// ---- Dashboard grouping -----------------------------------------------------

var DASHBOARD_GROUPS = [
  { key: "none", label: "No grouping", icon: "󰒺" },
  { key: "area", label: "Group by area", icon: "󰋜" },
  { key: "type", label: "Group by type", icon: "󰈙" },
  { key: "status", label: "Group by status", icon: "󰔡" }
]

function groupModeIndex(key) {
  for (var i = 0; i < DASHBOARD_GROUPS.length; i++) if (DASHBOARD_GROUPS[i].key === key) return i
  return 0
}

function statusGroup(entity) {
  if (!entity) return "Unavailable"
  var kind = controlKind(entity)
  if (kind === "run") return "Scenes & scripts"
  if (isUnavailable(entity)) return "Unavailable"
  if (kind === "switch" || kind === "lock" || kind === "cover" || kind === "media") return isOn(entity) ? "On" : "Off"
  return "Sensors"
}

// Returns [{ id, group }] in display order: groups in a stable order, your
// own order kept inside each group. `group` is "" when not grouping.
function orderDashboard(ids, mode, entityFor, areaNameFor) {
  var rows = []
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i]
    var e = entityFor(id)
    var group = ""
    if (mode === "area") group = areaNameFor(id) || "No area"
    else if (mode === "type") group = domainMeta(domainOf(id)).label + "s"
    else if (mode === "status") group = statusGroup(e)
    rows.push({ id: id, group: group, index: i })
  }
  if (mode === "none") return rows
  var rank = { "On": 0, "Off": 1, "Sensors": 2, "Scenes & scripts": 3, "Unavailable": 4, "No area": 99 }
  rows.sort(function(a, b) {
    if (a.group !== b.group) {
      var ra = rank[a.group], rb = rank[b.group]
      if (ra !== undefined || rb !== undefined) return (ra === undefined ? 50 : ra) - (rb === undefined ? 50 : rb)
      return a.group < b.group ? -1 : 1
    }
    return a.index - b.index
  })
  return rows
}

// ---- Browser groups -------------------------------------------------------

var GROUPS = [
  { key: "all",     label: "All",     domains: null },
  { key: "light",   label: "Lights",  domains: ["light"] },
  { key: "switch",  label: "Switches",domains: ["switch", "input_boolean"] },
  { key: "climate", label: "Climate", domains: ["climate", "fan", "humidifier", "water_heater"] },
  { key: "sensor",  label: "Sensors", domains: ["sensor", "binary_sensor"] },
  { key: "media",   label: "Media",   domains: ["media_player"] },
  { key: "cover",   label: "Covers",  domains: ["cover"] },
  { key: "scene",   label: "Scenes",  domains: ["scene", "script", "button", "input_button"] },
  { key: "auto",    label: "Automations", domains: ["automation"] },
  { key: "security",label: "Security",domains: ["lock", "alarm_control_panel", "camera", "siren"] },
  { key: "other",   label: "Other",   domains: [] }
]

function groupIndexForKey(key) {
  for (var i = 0; i < GROUPS.length; i++) if (GROUPS[i].key === key) return i
  return 0
}

function knownGroupDomains() {
  var set = {}
  for (var i = 0; i < GROUPS.length; i++) {
    var d = GROUPS[i].domains
    if (!d) continue
    for (var j = 0; j < d.length; j++) set[d[j]] = true
  }
  return set
}

var KNOWN_GROUP_DOMAINS = knownGroupDomains()

function entityInGroup(entity, group) {
  if (!group || !group.domains) return true
  var domain = domainOf(entity.entity_id)
  if (group.key === "other") return !KNOWN_GROUP_DOMAINS[domain]
  return group.domains.indexOf(domain) !== -1
}

// ---- Search ---------------------------------------------------------------

function normalize(text) {
  return String(text || "").toLowerCase().replace(/[_\-.]/g, " ").replace(/\s+/g, " ").trim()
}

// Lower is better. -1 means no match.
function matchRank(entity, query, areaName) {
  var q = normalize(query)
  if (q === "") return 0
  var name = normalize(friendlyName(entity))
  var id = normalize(entity.entity_id)
  var area = normalize(areaName)
  var domain = normalize(domainMeta(domainOf(entity.entity_id)).label)
  if (name === q) return 0
  if (name.indexOf(q) === 0) return 1
  var words = name.split(" ")
  for (var i = 0; i < words.length; i++) if (words[i].indexOf(q) === 0) return 2
  if (name.indexOf(q) !== -1) return 3
  if (id.indexOf(q) !== -1) return 4
  if (area !== "" && area.indexOf(q) !== -1) return 5
  if (domain.indexOf(q) !== -1) return 6
  // Multi-word queries: every word must appear somewhere.
  var qWords = q.split(" ")
  if (qWords.length > 1) {
    var haystack = name + " " + id + " " + area + " " + domain
    for (var w = 0; w < qWords.length; w++) if (haystack.indexOf(qWords[w]) === -1) return -1
    return 7
  }
  return -1
}

function searchEntities(list, query, group, areaNameFor, limit) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!entityInGroup(e, group)) continue
    var rank = matchRank(e, query, areaNameFor ? areaNameFor(e.entity_id) : "")
    if (rank < 0) continue
    out.push({ entity: e, rank: rank, name: friendlyName(e).toLowerCase() })
  }
  out.sort(function(a, b) {
    if (a.rank !== b.rank) return a.rank - b.rank
    var ad = a.entity.__diagnostic ? 1 : 0, bd = b.entity.__diagnostic ? 1 : 0
    if (ad !== bd) return ad - bd
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })
  var result = []
  var max = limit || 250
  for (var j = 0; j < out.length && j < max; j++) result.push(out[j].entity)
  return result
}

// ---- Config / persistence -------------------------------------------------

function normalizeUrl(raw) {
  var url = String(raw || "").trim()
  if (url === "") return ""
  if (!/^https?:\/\//i.test(url)) url = "http://" + url
  return url.replace(/\/+$/, "")
}

function websocketUrl(baseUrl) {
  var url = normalizeUrl(baseUrl)
  if (url === "") return ""
  return url.replace(/^http/i, "ws") + "/api/websocket"
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null || parsed === undefined ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

function parseConnectionFile(text) {
  var data = parseJson(text, {})
  return {
    url: normalizeUrl(data.url),
    token: typeof data.token === "string" ? data.token.trim() : ""
  }
}

function parseDashboardFile(text) {
  var data = parseJson(text, {})
  var ids = []
  if (data.entities && typeof data.entities.length === "number") {
    for (var i = 0; i < data.entities.length; i++) {
      var id = String(data.entities[i] || "")
      if (id !== "" && ids.indexOf(id) === -1) ids.push(id)
    }
  }
  var bar = []
  if (typeof data.bar === "string") { if (data.bar !== "") bar.push(data.bar) }
  else if (data.bar && typeof data.bar.length === "number") {
    for (var b = 0; b < data.bar.length; b++) {
      var bid = String(data.bar[b] || "")
      if (bid !== "" && bar.indexOf(bid) === -1) bar.push(bid)
    }
  }
  var alerts = []
  if (data.alerts && typeof data.alerts.length === "number") {
    for (var a = 0; a < data.alerts.length; a++) {
      var aid = String(data.alerts[a] || "")
      if (aid !== "" && alerts.indexOf(aid) === -1) alerts.push(aid)
    }
  }
  return {
    entities: ids,
    bar: bar,
    alerts: alerts,
    prefs: data.prefs && typeof data.prefs === "object" ? data.prefs : {}
  }
}

function serializeDashboard(entities, bar, alerts, prefs) {
  return JSON.stringify({ entities: entities, bar: bar || [], alerts: alerts || [], prefs: prefs || {} }, null, 2) + "\n"
}

function slug(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
}

// Text for a desktop notification about a state change.
function alertText(entity) {
  if (!entity) return ""
  var domain = domainOf(entity.entity_id)
  var attrs = entity.attributes || {}
  var cls = attrs.device_class
  var s = entity.state
  if (domain === "binary_sensor") {
    var onOff = {
      door: ["Opened", "Closed"], garage_door: ["Opened", "Closed"], window: ["Opened", "Closed"], opening: ["Opened", "Closed"],
      motion: ["Motion detected", "Clear"], occupancy: ["Occupied", "Clear"], presence: ["Home", "Away"],
      moisture: ["Wet", "Dry"], smoke: ["Smoke detected", "Clear"], gas: ["Gas detected", "Clear"],
      connectivity: ["Connected", "Disconnected"], battery: ["Battery low", "Battery ok"], problem: ["Problem", "OK"],
      lock: ["Unlocked", "Locked"], power: ["Power detected", "No power"], running: ["Running", "Not running"],
      vibration: ["Vibration", "Clear"], sound: ["Sound detected", "Clear"], tamper: ["Tampering", "Clear"],
      safety: ["Unsafe", "Safe"], cold: ["Cold", "Normal"], heat: ["Hot", "Normal"], update: ["Update available", "Up to date"]
    }
    var pair = onOff[cls]
    if (pair) return s === "on" ? pair[0] : (s === "off" ? pair[1] : stateLabel(s))
  }
  return displayState(entity)
}


function serializeConnection(url, token) {
  return JSON.stringify({ url: normalizeUrl(url), token: String(token || "") }, null, 2) + "\n"
}

// ---- Attributes for the detail view ---------------------------------------

var HIDDEN_ATTRS = {
  friendly_name: true, icon: true, supported_features: true, supported_color_modes: true,
  entity_picture: true, attribution: true, device_class: true, state_class: true,
  hvac_modes: true, fan_modes: true, preset_modes: true, swing_modes: true, effect_list: true,
  source_list: true, sound_mode_list: true, options: true, min_color_temp_kelvin: true,
  max_color_temp_kelvin: true, min_mireds: true, max_mireds: true, min_temp: true, max_temp: true,
  target_temp_step: true, editable: true, id: true, last_triggered: false, mode: true, current: true
}

function attributeRows(entity) {
  var rows = []
  if (!entity) return rows
  var attrs = entity.attributes || {}
  var keys = Object.keys(attrs).sort()
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    if (HIDDEN_ATTRS[key]) continue
    var value = attrs[key]
    if (value === null || value === undefined) continue
    var text
    if (typeof value === "object") {
      if (typeof value.length === "number") {
        if (value.length === 0) continue
        text = value.map(function(v) { return typeof v === "object" ? JSON.stringify(v) : String(v) }).join(", ")
      } else {
        text = JSON.stringify(value)
      }
    } else if (typeof value === "number") {
      text = formatNumber(value)
    } else {
      text = String(value)
    }
    if (text.length > 120) text = text.slice(0, 117) + "…"
    rows.push({ key: titleCase(key), value: text })
  }
  rows.push({ key: "Entity id", value: entity.entity_id })
  if (entity.last_changed) rows.push({ key: "Last changed", value: relativeTime(entity.last_changed) })
  return rows
}

function relativeTime(iso) {
  var t = Date.parse(iso)
  if (!isFinite(t)) return String(iso)
  var diff = Math.max(0, Date.now() - t)
  var s = Math.round(diff / 1000)
  if (s < 5) return "just now"
  if (s < 60) return s + "s ago"
  var m = Math.round(s / 60)
  if (m < 60) return m + " min ago"
  var h = Math.round(m / 60)
  if (h < 48) return h + " h ago"
  return Math.round(h / 24) + " days ago"
}

function kelvinToLabel(k) {
  var n = Number(k)
  if (!isFinite(n)) return ""
  if (n < 2700) return "Candle"
  if (n < 3300) return "Warm"
  if (n < 4500) return "Neutral"
  if (n < 5600) return "Cool"
  return "Daylight"
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}
