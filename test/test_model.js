// Unit tests for Model.js, the plugin's pure helpers. Run with:
//   node --test test/
// Model.js is a QML `.pragma library`; it is evaluated in a bare VM context so
// every top-level function becomes a property of `M`.
const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const M = {}
vm.runInNewContext(source, M)

// Values built inside the VM have that realm's prototypes; strip them so
// deepEqual compares structure only.
const plain = v => JSON.parse(JSON.stringify(v))

// Mirror of MenuModel.stripJsonc in the Omarchy shell: full-line comments and
// trailing commas are removed, nothing else is forgiven.
function shellParseJsonc(raw) {
  return JSON.parse(String(raw).replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1"))
}

const START = "  // >>> rewisch.homeassistant — generated"
const END = "  // <<< rewisch.homeassistant"
const BLOCK = [START, '  "home": {"label":"Home"},', '  "home.open": {"label":"Open","action":"omarchy-shell rewisch.homeassistant open"},', END].join("\n")

function ent(id, state, attrs) { return { entity_id: id, state: state, attributes: attrs || {} } }

test("entity ids: only the Home Assistant alphabet passes", () => {
  for (const ok of ["light.kitchen", "sensor.room_1_temperature", "binary_sensor.a"]) assert.equal(M.isValidEntityId(ok), true, ok)
  for (const bad of ["light.x; rm -rf ~", "Light.Kitchen", "light", "light.", ".kitchen", "light.a b", "light.a.b", "$(id).x", "light.x\n", "", null, undefined, 42, "a".repeat(300) + ".b"])
    assert.equal(M.isValidEntityId(bad), false, String(bad))
  assert.equal(M.isValidService("cover.open_cover"), true)
  assert.equal(M.isValidService("cover.open cover"), false)
})

test("shellQuote survives single quotes", () => {
  assert.equal(M.shellQuote("light.kitchen"), "'light.kitchen'")
  assert.equal(M.shellQuote("it's"), "'it'\\''s'")
  assert.equal(M.shellQuote(null), "''")
})

test("normalizeUrl and hasScheme", () => {
  assert.equal(M.hasScheme("homeassistant.local:8123"), false)
  assert.equal(M.hasScheme("HTTPS://x"), true)
  assert.equal(M.normalizeUrl(" homeassistant.local:8123/ "), "http://homeassistant.local:8123")
  assert.equal(M.normalizeUrl("homeassistant.local:8123", "https"), "https://homeassistant.local:8123")
  assert.equal(M.normalizeUrl("https://ha.example//", "http"), "https://ha.example")
  assert.equal(M.normalizeUrl(""), "")
})

test("parseDashboardFile drops malformed ids and duplicates", () => {
  const parsed = M.parseDashboardFile(JSON.stringify({
    entities: ["light.a", "light.a", "light.x; rm -rf ~", 7, "switch.b"],
    bar: "sensor.t",
    alerts: ["binary_sensor.door", "bad id"],
    prefs: { menuSync: true }
  }))
  assert.deepEqual(plain(parsed.entities), ["light.a", "switch.b"])
  assert.deepEqual(plain(parsed.bar), ["sensor.t"])
  assert.deepEqual(plain(parsed.alerts), ["binary_sensor.door"])
  assert.deepEqual(plain(parsed.prefs), { menuSync: true })
  assert.deepEqual(plain(M.parseDashboardFile("not json").entities), [])
  assert.deepEqual(plain(M.parseDashboardFile(JSON.stringify({ bar: ["a.b", "a.b", "c.d"] })).bar), ["a.b", "c.d"])
})

test("spliceMenuBlock: appending after an entry without a trailing comma stays parseable", () => {
  const user = '{\n  "personal.notes": {"label":"Notes","action":"x"}\n}\n'
  const out = M.spliceMenuBlock(user, BLOCK, START, END)
  const obj = shellParseJsonc(out)
  assert.equal(obj["personal.notes"].label, "Notes")
  assert.equal(obj["home.open"].label, "Open")
  assert.ok(out.indexOf('"action":"x"},') !== -1, "comma added to the previous entry")
})

test("spliceMenuBlock: trailing comma, comments and empty files", () => {
  for (const user of ['{\n  "a": {"label":"A"},\n}\n', '{\n  // only a comment\n}\n', "", "{}"]) {
    const out = M.spliceMenuBlock(user, BLOCK, START, END)
    const obj = shellParseJsonc(out)
    assert.equal(obj["home"].label, "Home", JSON.stringify(user))
  }
  assert.equal(M.spliceMenuBlock('{\n  "a": {"label":"A"},\n}\n', BLOCK, START, END).split(",,").length, 1, "no doubled comma")
})

test("spliceMenuBlock: replaces an existing block and removes it when empty", () => {
  const user = '{\n  "a": {"label":"A"}\n' + BLOCK + '\n  // trailing user comment\n}\n'
  const newBlock = [START, '  "home": {"label":"Renamed"},', END].join("\n")
  const replaced = M.spliceMenuBlock(user, newBlock, START, END)
  assert.equal(shellParseJsonc(replaced).home.label, "Renamed")
  assert.equal(shellParseJsonc(replaced).a.label, "A", "an older file without the comma before the block is repaired on rewrite")
  assert.ok(replaced.indexOf("trailing user comment") !== -1)
  const removed = M.spliceMenuBlock(user, "", START, END)
  assert.equal(removed.indexOf("rewisch.homeassistant"), -1)
  assert.equal(removed, '{\n  "a": {"label":"A"}\n  // trailing user comment\n}\n', "everything outside the markers is untouched")
  assert.equal(M.spliceMenuBlock(user, "", START, END) === user, false)
  assert.equal(M.spliceMenuBlock('{\n  "a": 1\n}\n', "", START, END), '{\n  "a": 1\n}\n', "nothing to remove: byte for byte")
})

test("ensureTrailingComma", () => {
  assert.equal(M.ensureTrailingComma('{\n  "a": {}\n'), '{\n  "a": {},\n')
  assert.equal(M.ensureTrailingComma('{\n  "a": {},\n'), '{\n  "a": {},\n')
  assert.equal(M.ensureTrailingComma('{\n'), '{\n')
  assert.equal(M.ensureTrailingComma('{\n  "a": 1 \n  // c\n\n'), '{\n  "a": 1,\n  // c\n\n')
})

test("parseHistory accepts both transport formats", () => {
  const ws = { "sensor.t": [{ s: "21.5", lu: 1700000100 }, { s: "unavailable", lu: 1700000200 }, { s: "20", lu: 1700000000 }] }
  assert.deepEqual(plain(M.parseHistory(ws, "sensor.t")), [{ t: 1700000000000, v: 20 }, { t: 1700000100000, v: 21.5 }])
  const rest = [[{ state: "1", last_updated: "2026-09-22T10:00:00+00:00" }, { state: "x", last_updated: "2026-09-22T11:00:00+00:00" }]]
  const pts = M.parseHistory(rest, "sensor.t")
  assert.equal(pts.length, 1)
  assert.equal(pts[0].v, 1)
  assert.deepEqual(plain(M.parseHistory(null, "sensor.t")), [])
  assert.deepEqual(plain(M.historyStats([{ t: 0, v: 3 }, { t: 1, v: 1 }, { t: 2, v: 2 }])), { min: 1, max: 3, first: 3, last: 2, count: 3 })
})

test("searchEntities ranks exact, prefix, word, substring, id, area", () => {
  const list = [
    ent("light.kitchen", "on", { friendly_name: "Kitchen" }),
    ent("light.kitchen_counter", "off", { friendly_name: "Kitchen Counter" }),
    ent("switch.old_kitchen_radio", "off", { friendly_name: "Radio" }),
    ent("sensor.temp", "21", { friendly_name: "Temperature" }),
    ent("light.lamp", "on", { friendly_name: "Big Kitchen Lamp" })
  ]
  const areas = { "sensor.temp": "Kitchen" }
  const ids = M.searchEntities(list, "kitchen", M.GROUPS[0], id => areas[id] || "").map(e => e.entity_id)
  assert.deepEqual(plain(ids), ["light.kitchen", "light.kitchen_counter", "light.lamp", "switch.old_kitchen_radio", "sensor.temp"])
  assert.deepEqual(plain(M.searchEntities(list, "kitchen", M.GROUPS[1]).map(e => e.entity_id)), ["light.kitchen", "light.kitchen_counter", "light.lamp"])
  assert.equal(M.searchEntities(list, "", M.GROUPS[0], null, 2).length, 2)
  assert.equal(M.matchRank(list[4], "lamp kitchen", ""), 7)
  assert.equal(M.matchRank(list[4], "lamp garage", ""), -1)
})

test("orderDashboard groups by status in a fixed order and keeps user order inside", () => {
  const entities = {
    "light.a": ent("light.a", "off"), "light.b": ent("light.b", "on"), "sensor.c": ent("sensor.c", "3"),
    "scene.d": ent("scene.d", "unknown"), "light.e": ent("light.e", "unavailable"), "light.f": ent("light.f", "on")
  }
  const rows = M.orderDashboard(["light.a", "light.b", "sensor.c", "scene.d", "light.e", "light.f"], "status", id => entities[id], () => "")
  assert.deepEqual(plain(rows.map(r => r.id)), ["light.b", "light.f", "light.a", "sensor.c", "scene.d", "light.e"])
  assert.deepEqual(plain(rows.map(r => r.group)), ["On", "On", "Off", "Sensors", "Scenes & scripts", "Unavailable"])
  assert.equal(M.orderDashboard(["b.a", "a.b"], "none", () => null, () => "")[0].group, "")
})

test("state text", () => {
  assert.equal(M.displayState(ent("sensor.t", "21.44", { unit_of_measurement: "°C" })), "21.4°C")
  assert.equal(M.displayState(ent("sensor.h", "63", { unit_of_measurement: "%" })), "63%")
  assert.equal(M.displayState(ent("light.k", "on", { brightness: 128 })), "50%")
  assert.equal(M.displayState(ent("climate.c", "heat", { temperature: 22, temperature_unit: "°C" })), "Heating · 22.0°C")
  assert.equal(M.displayState(ent("cover.g", "open", { current_position: 70 })), "70% open")
  assert.equal(M.barLabel(ent("sensor.t", "unavailable")), "—")
  assert.equal(M.alertText(ent("binary_sensor.d", "on", { device_class: "door" })), "Opened")
  assert.equal(M.alertText(ent("binary_sensor.m", "off", { device_class: "motion" })), "Clear")
  assert.equal(M.slug("Büro Licht"), "b-ro-licht")
  assert.equal(M.friendlyName(ent("light.living_room_lamp", "on")), "Living room lamp")
})

test("primary actions and optimistic states", () => {
  assert.deepEqual(plain(M.primaryAction(ent("lock.f", "locked"))), { domain: "lock", service: "unlock", data: { entity_id: "lock.f" } })
  assert.equal(M.optimisticState(ent("cover.g", "closed")), "opening")
  assert.equal(M.optimisticState(ent("scene.x", "unknown")), null)
  assert.equal(M.controlKind(ent("vacuum.r", "docked")), "run")
  assert.equal(M.supportsFeature(ent("media_player.x", "on", { supported_features: 21437 }), M.MEDIA_VOLUME_SET), true)
})
