import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Rich controls for a single entity, plus its attributes.
Item {
  id: detail

  property var panel
  // Follows the panel's service so a view created before the shared service
  // was injected picks it up instead of keeping the dormant fallback.
  property var ha: panel ? panel.ha : null
  property string entityId: ""

  readonly property var entity: ha.revision >= 0 ? ha.entityFor(entityId) : null
  readonly property string domain: Model.domainOf(entityId)
  readonly property var attrs: entity && entity.attributes ? entity.attributes : ({})
  readonly property bool unavailable: Model.isUnavailable(entity)
  readonly property Item focusItem: null
  readonly property bool ownsKeyboard: false
  readonly property string areaName: ha.areaNameFor(entityId)

  property string cursorId: ""

  // ---- Colour (lights) --------------------------------------------------------
  readonly property bool colorCapable: domain === "light" && Model.lightSupportsColor(entity)
  readonly property var hs: Model.lightHs(entity)
  readonly property real currentHue: hs ? hs.h : 30
  readonly property real currentSat: hs ? hs.s : 0
  readonly property color currentColor: Qt.hsla(currentHue / 360, currentSat / 100, 0.6, 1)

  // ---- Snapshots (cameras, album art) ---------------------------------------
  readonly property string pictureBase: {
    var p = attrs.entity_picture
    if (typeof p !== "string" || p === "") return ""
    return p.indexOf("http") === 0 ? p : ha.url + p
  }
  property int snapshotTick: 0
  readonly property string snapshotUrl: pictureBase === "" ? "" : pictureBase + (pictureBase.indexOf("?") !== -1 ? "&" : "?") + "_t=" + snapshotTick
  Timer {
    interval: 5000
    repeat: true
    running: detail.domain === "camera" && detail.pictureBase !== ""
    onTriggered: detail.snapshotTick++
  }

  // ---- History (numeric sensors) --------------------------------------------
  readonly property bool hasHistory: Model.hasHistory(entity)
  property int historyHours: 24
  property var historyPoints: []
  property bool historyLoading: false
  readonly property var historyStats: Model.historyStats(historyPoints)
  readonly property string unit: String(attrs.unit_of_measurement || "")

  function loadHistory() {
    if (!hasHistory) return
    historyLoading = true
    ha.requestHistory(entityId, historyHours)
  }
  onHistoryHoursChanged: { historyPoints = []; loadHistory() }
  onHasHistoryChanged: if (hasHistory && historyPoints.length === 0) loadHistory()
  Component.onCompleted: loadHistory()
  Connections {
    target: ha
    function onHistoryReceived(id, hours, points) {
      if (id !== detail.entityId || hours !== detail.historyHours) return
      detail.historyPoints = points
      detail.historyLoading = false
      spark.requestPaint()
    }
    function onHistoryFailed(id, hours) {
      if (id !== detail.entityId || hours !== detail.historyHours) return
      detail.historyLoading = false
    }
  }

  // Keeps the relative "Last changed" row ticking while the panel is open.
  property int clockTick: 0
  Timer {
    interval: 30000
    repeat: true
    running: detail.panel ? detail.panel.opened === true : false
    onTriggered: detail.clockTick++
  }
  property var rowItems: ({})
  readonly property var rowOrder: ["power", "brightness", "colortemp", "hue", "saturation", "swatches", "target", "hvac", "preset", "fanpct", "coverbtn", "position", "transport", "volume", "lock", "run", "options", "number", "range"]

  implicitHeight: column.implicitHeight

  function registerRow(id, item) { rowItems[id] = item }

  function visibleRows() {
    var out = []
    for (var i = 0; i < rowOrder.length; i++) {
      var item = rowItems[rowOrder[i]]
      if (item && item.visible) out.push(rowOrder[i])
    }
    return out
  }

  function move(dx, dy) {
    var rows = visibleRows()
    if (dy !== 0) {
      if (rows.length === 0) return
      var idx = rows.indexOf(cursorId)
      if (idx === -1) { cursorId = dy > 0 ? rows[0] : rows[rows.length - 1]; return }
      cursorId = rows[Math.max(0, Math.min(rows.length - 1, idx + dy))]
    } else if (dx !== 0) {
      if (cursorId === "") { if (dx < 0) panel.goBack(); return }
      var item = rowItems[cursorId]
      if (item && item.adjust) item.adjust(dx)
    }
  }

  function activate() {
    if (cursorId === "") {
      if (Model.primaryAction(entity)) ha.runPrimary(entityId)
      return
    }
    var item = rowItems[cursorId]
    if (item && item.activate) item.activate()
  }

  function handleEscape() { return false }
  function removeCurrent() { ha.removeFromDashboard(entityId) }

  function textKey(t) {
    if (t === "p" || t === "P") { ha.togglePin(entityId); return true }
    if (t === "s" || t === "S" || t === "d" || t === "D") { ha.toggleDashboard(entityId); return true }
    if (t === "+" || t === "=") { move(1, 0); return true }
    if (t === "-") { move(-1, 0); return true }
    if (t === "t" || t === "T") { if (Model.primaryAction(entity)) ha.runPrimary(entityId); return true }
    if (t === "n" || t === "N") { ha.toggleAlert(entityId); return true }
    if (t === "c" || t === "C") { copyCommand(); return true }
    return false
  }

  function onShown() { cursorId = "" }

  // Puts the IPC command for this entity on the clipboard, ready to paste
  // into ~/.config/hypr/bindings.lua.
  function copyCommand() {
    var method = Model.primaryAction(entity) ? "toggleEntity" : "detail"
    var command = "omarchy-shell rewisch.homeassistant " + method + " " + entityId
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "copy", command])
    ha.flashAction("Copied: " + command)
  }

  readonly property string heroMeta: {
    var parts = []
    if (areaName !== "") parts.push(areaName)
    parts.push(Model.domainMeta(domain).label)
    return parts.join(" · ")
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      PanelActionButton {
        iconText: Model.GLYPH.chevronLeft
        tooltipText: "Back  (esc)"
        foreground: panel.dim
        fontFamily: panel.fontFamily
        Layout.alignment: Qt.AlignTop
        onClicked: panel.goBack()
      }

      PanelHero {
        Layout.fillWidth: true
        title: detail.entity ? Model.friendlyName(detail.entity) : detail.entityId
        meta: detail.heroMeta
        detail: detail.entity ? Model.displayState(detail.entity) : "Not found"
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        iconOpacity: detail.unavailable ? 0.4 : 1.0
        iconComponent: Component {
          Text {
            textFormat: Text.PlainText
            text: detail.entity ? Model.iconFor(detail.entity) : "󰇘"
            color: Model.isOn(detail.entity) ? (detail.colorCapable && detail.hs && detail.currentSat > 5 ? detail.currentColor : panel.foreground) : panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }
        trailingControl: Component {
          Row {
            spacing: Style.space(2)
            PanelActionButton {
              iconText: ha.isOnDashboard(detail.entityId) ? Model.GLYPH.star : Model.GLYPH.starOutline
              tooltipText: ha.isOnDashboard(detail.entityId) ? "Remove from dashboard  (s)" : "Add to dashboard  (s)"
              foreground: ha.isOnDashboard(detail.entityId) ? panel.foreground : panel.dim
              fontFamily: panel.fontFamily
              onClicked: ha.toggleDashboard(detail.entityId)
            }
            PanelActionButton {
              iconText: ha.isPinned(detail.entityId) ? Model.GLYPH.pin : Model.GLYPH.pinOff
              tooltipText: ha.isPinned(detail.entityId) ? "Unpin from bar  (p)" : "Pin to bar  (p)"
              foreground: ha.isPinned(detail.entityId) ? panel.foreground : panel.dim
              fontFamily: panel.fontFamily
              onClicked: ha.togglePin(detail.entityId)
            }
            PanelActionButton {
              iconText: ha.isAlerted(detail.entityId) ? Model.GLYPH.bell : Model.GLYPH.bellOff
              tooltipText: ha.isAlerted(detail.entityId) ? "Stop notifying on changes  (n)" : "Notify me when this changes  (n)"
              foreground: ha.isAlerted(detail.entityId) ? panel.foreground : panel.dim
              fontFamily: panel.fontFamily
              onClicked: ha.toggleAlert(detail.entityId)
            }
            PanelActionButton {
              iconText: Model.GLYPH.copy
              tooltipText: "Copy shell command for a keybinding  (c)"
              foreground: panel.dim
              fontFamily: panel.fontFamily
              onClicked: detail.copyCommand()
            }
          }
        }
      }
    }

    // Camera: live snapshot, refreshed every few seconds while open.
    Column {
      visible: detail.domain === "camera" && detail.pictureBase !== ""
      width: parent.width
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      spacing: Style.space(4)

      Rectangle {
        width: parent.width - Style.space(20)
        height: Math.round(width * 9 / 16)
        radius: Style.cornerRadius
        color: Style.normalFillFor(panel.foreground, panel.accent)
        clip: true

        Image {
          id: snapshot
          anchors.fill: parent
          source: detail.snapshotUrl
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: false
          smooth: true
        }
        Text {
          anchors.centerIn: parent
          visible: snapshot.status !== Image.Ready
          textFormat: Text.PlainText
          text: snapshot.status === Image.Error ? "No snapshot available" : "Loading snapshot…"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      Text {
        textFormat: Text.PlainText
        text: "Refreshes every 5 s while open"
        color: panel.dimmer
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Media: what is playing.
    RowLayout {
      visible: detail.domain === "media_player" && (detail.attrs.media_title || detail.attrs.media_artist)
      width: parent.width
      spacing: Style.space(10)

      Rectangle {
        visible: detail.pictureBase !== ""
        Layout.leftMargin: Style.space(10)
        Layout.preferredWidth: Style.space(56)
        Layout.preferredHeight: Style.space(56)
        radius: Style.cornerRadius
        color: Style.normalFillFor(panel.foreground, panel.accent)
        clip: true
        Image {
          anchors.fill: parent
          source: detail.pictureBase
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }
      }

      Column {
      Layout.fillWidth: true
      leftPadding: detail.pictureBase !== "" ? 0 : Style.space(10)
      spacing: Style.space(1)
      Text {
        textFormat: Text.PlainText
        text: String(detail.attrs.media_title || "")
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width - Style.space(20)
      }
      Text {
        visible: text !== ""
        textFormat: Text.PlainText
        text: [detail.attrs.media_artist, detail.attrs.media_album_name].filter(function(v) { return !!v }).join(" · ")
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: parent.width - Style.space(20)
      }
      }
    }

    // ---- Controls -----------------------------------------------------------

    ControlRow {
      rowId: "power"
      label: "Power"
      visible: Model.controlKind(detail.entity) === "switch"
        || (detail.domain === "media_player" && (Model.supportsFeature(detail.entity, Model.MEDIA_TURN_ON) || Model.supportsFeature(detail.entity, Model.MEDIA_TURN_OFF)))
      valueText: Model.isOn(detail.entity) ? "On" : "Off"
      control: Component {
        ToggleSwitch {
          checked: Model.isOn(detail.entity)
          busy: !!(detail.entity && detail.entity.__pending)
          interactive: !detail.unavailable
          foreground: panel.foreground
          hasCursor: detail.cursorId === "power"
          onToggled: detail.togglePower()
        }
      }
      function activate() { detail.togglePower() }
    }

    SliderRow {
      rowId: "brightness"
      label: "Brightness"
      visible: detail.domain === "light" && Model.lightSupportsBrightness(detail.entity)
      minimum: 0; maximum: 100; step: 5
      value: detail.entity && detail.entity.state === "on" && Model.isNumeric(detail.attrs.brightness) ? Math.round(Number(detail.attrs.brightness) / 255 * 100) : 0
      formatValue: function(v) { return Math.round(v) + "%" }
      onCommitted: function(v) { ha.setLightBrightness(detail.entityId, v) }
    }

    SliderRow {
      rowId: "colortemp"
      label: "Color temperature"
      visible: detail.domain === "light" && Model.lightSupportsColorTemp(detail.entity)
      minimum: Model.isNumeric(detail.attrs.min_color_temp_kelvin) ? Number(detail.attrs.min_color_temp_kelvin) : 2000
      maximum: Model.isNumeric(detail.attrs.max_color_temp_kelvin) ? Number(detail.attrs.max_color_temp_kelvin) : 6500
      step: 100
      value: Model.isNumeric(detail.attrs.color_temp_kelvin) ? Number(detail.attrs.color_temp_kelvin) : (minimum + maximum) / 2
      formatValue: function(v) { return Math.round(v) + " K · " + Model.kelvinToLabel(v) }
      onCommitted: function(v) { ha.setLightColorTemp(detail.entityId, v) }
    }

    HueRow {
      rowId: "hue"
      visible: detail.colorCapable
    }

    SliderRow {
      rowId: "saturation"
      label: "Saturation"
      visible: detail.colorCapable
      minimum: 0; maximum: 100; step: 10
      value: detail.currentSat
      formatValue: function(v) { return Math.round(v) + "%" }
      onCommitted: function(v) { ha.setLightColor(detail.entityId, detail.currentHue, v) }
    }

    ChipsRow {
      rowId: "swatches"
      label: "Presets"
      visible: detail.colorCapable
      options: Model.SWATCHES.map(function(sw) { return sw.name })
      current: ""
      labelFor: function(o) { return "󰝤 " + o }
      colorFor: function(o) {
        for (var i = 0; i < Model.SWATCHES.length; i++) if (Model.SWATCHES[i].name === o) return Qt.hsla(Model.SWATCHES[i].h / 360, Model.SWATCHES[i].s / 100, 0.6, 1)
        return panel.foreground
      }
      onPicked: function(o) {
        for (var i = 0; i < Model.SWATCHES.length; i++) if (Model.SWATCHES[i].name === o) ha.setLightColor(detail.entityId, Model.SWATCHES[i].h, Model.SWATCHES[i].s)
      }
    }

    StepperRow {
      rowId: "target"
      label: "Target"
      visible: detail.domain === "climate" && Model.supportsFeature(detail.entity, Model.CLIMATE_TARGET_TEMP)
      minimum: Model.isNumeric(detail.attrs.min_temp) ? Number(detail.attrs.min_temp) : 5
      maximum: Model.isNumeric(detail.attrs.max_temp) ? Number(detail.attrs.max_temp) : 35
      step: Model.isNumeric(detail.attrs.target_temp_step) ? Number(detail.attrs.target_temp_step) : 0.5
      value: Model.isNumeric(detail.attrs.temperature) ? Number(detail.attrs.temperature) : minimum
      unit: detail.attrs.temperature_unit || "°"
      hint: Model.isNumeric(detail.attrs.current_temperature) ? "now " + Model.withUnit(Model.formatNumber(detail.attrs.current_temperature, 1), detail.attrs.temperature_unit || "°") : ""
      onCommitted: function(v) { ha.setClimateTemperature(detail.entityId, v) }
    }

    ChipsRow {
      rowId: "hvac"
      label: "Mode"
      visible: detail.domain === "climate" && detail.attrs.hvac_modes && detail.attrs.hvac_modes.length > 0
      options: detail.attrs.hvac_modes || []
      current: detail.entity ? String(detail.entity.state) : ""
      labelFor: function(o) { return Model.stateLabel(o) }
      onPicked: function(o) { ha.setHvacMode(detail.entityId, o) }
    }

    ChipsRow {
      rowId: "preset"
      label: "Preset"
      visible: detail.domain === "climate" && detail.attrs.preset_modes && detail.attrs.preset_modes.length > 0
      options: detail.attrs.preset_modes || []
      current: String(detail.attrs.preset_mode || "")
      labelFor: function(o) { return Model.titleCase(o) }
      onPicked: function(o) { ha.setPresetMode(detail.entityId, o) }
    }

    SliderRow {
      rowId: "fanpct"
      label: "Speed"
      visible: detail.domain === "fan" && Model.isNumeric(detail.attrs.percentage)
      minimum: 0; maximum: 100
      step: Model.isNumeric(detail.attrs.percentage_step) ? Math.max(1, Number(detail.attrs.percentage_step)) : 10
      value: detail.entity && detail.entity.state === "on" ? Number(detail.attrs.percentage) : 0
      formatValue: function(v) { return Math.round(v) + "%" }
      onCommitted: function(v) { ha.setFanPercentage(detail.entityId, v) }
    }

    ChipsRow {
      rowId: "coverbtn"
      label: "Cover"
      visible: detail.domain === "cover"
      options: ["open_cover", "stop_cover", "close_cover"]
      current: detail.entity ? (detail.entity.state === "open" || detail.entity.state === "opening" ? "open_cover" : (detail.entity.state === "closed" || detail.entity.state === "closing" ? "close_cover" : "")) : ""
      labelFor: function(o) { return o === "open_cover" ? Model.GLYPH.arrowUp + " Open" : (o === "stop_cover" ? Model.GLYPH.stop + " Stop" : Model.GLYPH.arrowDown + " Close") }
      onPicked: function(o) { ha.coverCommand(detail.entityId, o) }
    }

    SliderRow {
      rowId: "position"
      label: "Position"
      visible: detail.domain === "cover" && Model.supportsFeature(detail.entity, Model.COVER_SET_POSITION)
      minimum: 0; maximum: 100; step: 10
      value: Model.isNumeric(detail.attrs.current_position) ? Number(detail.attrs.current_position) : 0
      formatValue: function(v) { return Math.round(v) + "%" }
      onCommitted: function(v) { ha.setCoverPosition(detail.entityId, v) }
    }

    ChipsRow {
      rowId: "transport"
      label: "Playback"
      visible: detail.domain === "media_player"
      options: ["media_previous_track", "media_play_pause", "media_next_track"]
      current: ""
      labelFor: function(o) {
        if (o === "media_previous_track") return Model.GLYPH.prev
        if (o === "media_next_track") return Model.GLYPH.next
        return detail.entity && detail.entity.state === "playing" ? Model.GLYPH.pause : Model.GLYPH.play
      }
      onPicked: function(o) { ha.mediaCommand(detail.entityId, o) }
    }

    SliderRow {
      rowId: "volume"
      label: "Volume"
      visible: detail.domain === "media_player" && Model.supportsFeature(detail.entity, Model.MEDIA_VOLUME_SET)
      minimum: 0; maximum: 100; step: 5
      value: Model.isNumeric(detail.attrs.volume_level) ? Math.round(Number(detail.attrs.volume_level) * 100) : 0
      formatValue: function(v) { return Math.round(v) + "%" }
      onCommitted: function(v) { ha.setVolume(detail.entityId, v / 100) }
    }

    ChipsRow {
      rowId: "lock"
      label: "Lock"
      visible: detail.domain === "lock"
      options: ["lock", "unlock"]
      current: detail.entity && detail.entity.state === "locked" ? "lock" : (detail.entity && detail.entity.state === "unlocked" ? "unlock" : "")
      labelFor: function(o) { return o === "lock" ? "󰌾 Lock" : "󰿆 Unlock" }
      onPicked: function(o) { ha.call("lock", o, { entity_id: detail.entityId }) }
    }

    ChipsRow {
      rowId: "run"
      label: Model.domainMeta(detail.domain).label
      visible: detail.domain === "scene" || detail.domain === "script" || detail.domain === "button" || detail.domain === "input_button" || detail.domain === "vacuum"
      options: ["run"]
      current: ""
      labelFor: function(o) { return Model.GLYPH.play + " " + (detail.domain === "vacuum" ? (detail.entity && detail.entity.state === "cleaning" ? "Return to dock" : "Start cleaning") : "Activate") }
      onPicked: function(o) { ha.runPrimary(detail.entityId) }
    }

    ChipsRow {
      rowId: "options"
      label: "Option"
      visible: (detail.domain === "select" || detail.domain === "input_select") && detail.attrs.options && detail.attrs.options.length > 0
      options: detail.attrs.options || []
      current: detail.entity ? String(detail.entity.state) : ""
      labelFor: function(o) { return String(o) }
      onPicked: function(o) { ha.selectOption(detail.entityId, o) }
    }

    SliderRow {
      rowId: "number"
      label: "Value"
      visible: (detail.domain === "number" || detail.domain === "input_number") && Model.isNumeric(detail.entity ? detail.entity.state : NaN)
      minimum: Model.isNumeric(detail.attrs.min) ? Number(detail.attrs.min) : 0
      maximum: Model.isNumeric(detail.attrs.max) ? Number(detail.attrs.max) : 100
      step: Model.isNumeric(detail.attrs.step) ? Number(detail.attrs.step) : 1
      value: detail.entity ? Number(detail.entity.state) : 0
      formatValue: function(v) { return Model.withUnit(Model.formatNumber(v), detail.attrs.unit_of_measurement) }
      onCommitted: function(v) { ha.setNumber(detail.entityId, v) }
    }

    // ---- History ------------------------------------------------------------

    Column {
      visible: detail.hasHistory
      width: parent.width
      spacing: Style.space(4)

      ChipsRow {
        rowId: "range"
        label: "History"
        visible: detail.hasHistory
        options: Model.HISTORY_RANGES.map(function(r) { return r.key })
        current: detail.historyHours === 3 ? "3h" : (detail.historyHours === 168 ? "7d" : "24h")
        labelFor: function(o) {
          for (var i = 0; i < Model.HISTORY_RANGES.length; i++) if (Model.HISTORY_RANGES[i].key === o) return Model.HISTORY_RANGES[i].label
          return o
        }
        onPicked: function(o) {
          for (var i = 0; i < Model.HISTORY_RANGES.length; i++) if (Model.HISTORY_RANGES[i].key === o) detail.historyHours = Model.HISTORY_RANGES[i].hours
        }
      }

      Item {
        width: parent.width - Style.space(20)
        x: Style.space(10)
        height: Style.space(72)

        Canvas {
          id: spark
          anchors.fill: parent
          onWidthChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var pts = detail.historyPoints
            if (!pts || pts.length < 2) return
            var st = Model.historyStats(pts)
            var vmin = st.min, vmax = st.max
            if (vmax === vmin) { vmax += 1; vmin -= 1 }
            var t0 = pts[0].t, span = Math.max(1, pts[pts.length - 1].t - t0)
            var pad = 4, w = width, h = height
            var fg = panel.foreground
            var xs = [], ys = []
            for (var i = 0; i < pts.length; i++) {
              xs.push(pad + (pts[i].t - t0) / span * (w - 2 * pad))
              ys.push(pad + (1 - (pts[i].v - vmin) / (vmax - vmin)) * (h - 2 * pad))
            }
            ctx.beginPath()
            ctx.moveTo(xs[0], ys[0])
            for (var j = 1; j < xs.length; j++) ctx.lineTo(xs[j], ys[j])
            ctx.lineTo(xs[xs.length - 1], h)
            ctx.lineTo(xs[0], h)
            ctx.closePath()
            ctx.fillStyle = "rgba(" + Math.round(fg.r * 255) + "," + Math.round(fg.g * 255) + "," + Math.round(fg.b * 255) + ",0.12)"
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(xs[0], ys[0])
            for (var k = 1; k < xs.length; k++) ctx.lineTo(xs[k], ys[k])
            ctx.strokeStyle = fg
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(xs[xs.length - 1], ys[ys.length - 1], 3, 0, Math.PI * 2)
            ctx.fillStyle = fg
            ctx.fill()
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !detail.historyPoints || detail.historyPoints.length < 2
          textFormat: Text.PlainText
          text: detail.historyLoading ? "Loading history…" : "No history for this range"
          color: panel.dimmer
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      RowLayout {
        visible: !!detail.historyStats
        width: parent.width - Style.space(20)
        x: Style.space(10)
        Text {
          textFormat: Text.PlainText
          text: detail.historyStats ? "min " + Model.withUnit(Model.formatNumber(detail.historyStats.min), detail.unit) : ""
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Item { Layout.fillWidth: true }
        Text {
          textFormat: Text.PlainText
          text: detail.historyStats ? "max " + Model.withUnit(Model.formatNumber(detail.historyStats.max), detail.unit) : ""
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Item { Layout.fillWidth: true }
        Text {
          textFormat: Text.PlainText
          text: detail.historyStats ? detail.historyStats.count + " points" : ""
          color: panel.dimmer
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- Attributes ---------------------------------------------------------

    PanelSeparator { width: parent.width; foreground: panel.foreground }

    PanelSectionHeader {
      text: "Details"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      leftPadding: Style.space(10)
    }

    ListView {
      id: attrList
      width: parent.width
      height: Math.min(contentHeight, Style.space(190))
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      model: detail.clockTick >= 0 ? Model.attributeRows(detail.entity) : []
      delegate: Item {
        required property var modelData
        width: ListView.view.width
        height: attrRow.implicitHeight + Style.space(6)
        RowLayout {
          id: attrRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            text: modelData.key
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            Layout.preferredWidth: Style.space(130)
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.value
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }
        }
      }
    }

    Text {
      visible: ha.actionStatus !== ""
      textFormat: Text.PlainText
      text: ha.actionStatus
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      leftPadding: Style.space(10)
      width: parent.width
      elide: Text.ElideRight
    }

    PanelSeparator { width: parent.width; foreground: panel.foreground }

    HintBar {
      width: parent.width
      panel: detail.panel
      hints: [["j/k", "row"], ["←/→", "adjust"], ["⏎", "apply"], ["s", "star"], ["p", "pin"], ["n", "alert"], ["c", "copy cmd"], ["esc", "back"]]
    }
  }

  function togglePower() {
    if (domain === "media_player") ha.mediaCommand(entityId, Model.isOn(entity) ? "turn_off" : "turn_on")
    else ha.runPrimary(entityId)
  }

  // ---- Row components -------------------------------------------------------

  component ControlRow: CursorSurface {
    id: controlRow
    property string rowId: ""
    property string label: ""
    property string valueText: ""
    property Component control: null
    width: parent ? parent.width : 0
    foreground: panel.foreground
    hasCursor: detail.cursorId === rowId
    implicitHeight: controlRowLayout.implicitHeight + Style.space(14)
    Component.onCompleted: detail.registerRow(rowId, controlRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: detail.cursorId = controlRow.rowId
      onClicked: controlRow.activate()
    }

    RowLayout {
      id: controlRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        text: controlRow.label
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        Layout.fillWidth: true
      }
      Text {
        textFormat: Text.PlainText
        text: controlRow.valueText
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Loader { sourceComponent: controlRow.control; Layout.alignment: Qt.AlignVCenter }
    }
  }

  component SliderRow: CursorSurface {
    id: sliderRow
    property string rowId: ""
    property string label: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property real value: 0
    property var formatValue: function(v) { return String(v) }
    signal committed(real value)
    // What the row shows and edits. `value` is bound to the entity by the
    // instance and is never assigned here: that would replace the binding
    // and freeze the row at the last local number once another client
    // changes the light. Edits land in `local`, which follows `value` again
    // as soon as no edit is in flight.
    property real local: value
    onValueChanged: if (!commitTimer.running && !slider.dragging) local = value
    property real shownValue: slider.dragging ? slider.liveValue : local

    width: parent ? parent.width : 0
    foreground: panel.foreground
    hasCursor: detail.cursorId === rowId
    implicitHeight: sliderLayout.implicitHeight + Style.space(12)
    Component.onCompleted: detail.registerRow(rowId, sliderRow)

    function adjust(dx) {
      var next = Model.clamp(Math.round((local + dx * step) / step) * step, minimum, maximum)
      if (next === local) return
      local = next
      commitTimer.restart()
    }
    function activate() {}

    Timer {
      id: commitTimer
      interval: 250
      onTriggered: sliderRow.committed(sliderRow.local)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      propagateComposedEvents: true
      onEntered: detail.cursorId = sliderRow.rowId
      onPressed: function(mouse) { mouse.accepted = false }
    }

    ColumnLayout {
      id: sliderLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)
      RowLayout {
        Layout.fillWidth: true
        Text {
          textFormat: Text.PlainText
          text: sliderRow.label
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }
        Text {
          textFormat: Text.PlainText
          text: sliderRow.formatValue(sliderRow.shownValue)
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      PanelSlider {
        id: slider
        Layout.fillWidth: true
        bar: panel.bar
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        value: sliderRow.local
        onReleased: function(v) { sliderRow.local = v; sliderRow.committed(v) }
      }
    }
  }

  component StepperRow: CursorSurface {
    id: stepperRow
    property string rowId: ""
    property string label: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property real value: 0
    property string unit: ""
    property string hint: ""
    signal committed(real value)
    // See SliderRow: edits go to `local`, `value` keeps its binding.
    property real local: value
    onValueChanged: if (!stepTimer.running) local = value

    width: parent ? parent.width : 0
    foreground: panel.foreground
    hasCursor: detail.cursorId === rowId
    implicitHeight: stepperLayout.implicitHeight + Style.space(10)
    Component.onCompleted: detail.registerRow(rowId, stepperRow)

    function adjust(dx) {
      var next = Model.clamp(Math.round((local + dx * step) / step) * step, minimum, maximum)
      next = Math.round(next * 100) / 100
      if (next === local) return
      local = next
      stepTimer.restart()
    }
    function activate() {}

    Timer {
      id: stepTimer
      interval: 400
      onTriggered: stepperRow.committed(stepperRow.local)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: detail.cursorId = stepperRow.rowId
    }

    RowLayout {
      id: stepperLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          text: stepperRow.label
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          visible: text !== ""
          textFormat: Text.PlainText
          text: stepperRow.hint
          color: panel.dimmer
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      PanelActionButton {
        iconText: Model.GLYPH.minus
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: stepperRow.adjust(-1)
      }
      Text {
        textFormat: Text.PlainText
        text: Model.withUnit(Model.formatNumber(stepperRow.local, 1), stepperRow.unit)
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        Layout.preferredWidth: Style.space(70)
        horizontalAlignment: Text.AlignHCenter
      }
      PanelActionButton {
        iconText: Model.GLYPH.plus
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: stepperRow.adjust(1)
      }
    }
  }

  component ChipsRow: CursorSurface {
    id: chipsRow
    property string rowId: ""
    property string label: ""
    property var options: []
    property string current: ""
    property var labelFor: function(o) { return String(o) }
    property var colorFor: null
    property int chipCursor: -1
    signal picked(string option)

    width: parent ? parent.width : 0
    foreground: panel.foreground
    hasCursor: detail.cursorId === rowId
    implicitHeight: chipsLayout.implicitHeight + Style.space(12)
    Component.onCompleted: detail.registerRow(rowId, chipsRow)

    onHasCursorChanged: if (hasCursor && chipCursor === -1) chipCursor = Math.max(0, options.indexOf(current))

    function adjust(dx) {
      if (options.length === 0) return
      if (chipCursor === -1) chipCursor = Math.max(0, options.indexOf(current))
      chipCursor = Math.max(0, Math.min(options.length - 1, chipCursor + dx))
    }
    function activate() {
      if (chipCursor === -1) chipCursor = Math.max(0, options.indexOf(current))
      if (chipCursor >= 0 && chipCursor < options.length) picked(String(options[chipCursor]))
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      propagateComposedEvents: true
      onEntered: detail.cursorId = chipsRow.rowId
      onPressed: function(mouse) { mouse.accepted = false }
    }

    RowLayout {
      id: chipsLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)
      Text {
        textFormat: Text.PlainText
        text: chipsRow.label
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(90)
        Layout.alignment: Qt.AlignTop
        topPadding: Style.space(4)
      }
      Flow {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Repeater {
          model: chipsRow.options
          Button {
            required property var modelData
            required property int index
            text: chipsRow.labelFor(modelData)
            selected: String(modelData) === chipsRow.current && chipsRow.current !== ""
            hasCursor: chipsRow.hasCursor && chipsRow.chipCursor === index
            bordered: true
            foreground: chipsRow.colorFor ? chipsRow.colorFor(modelData) : panel.foreground
            fontFamily: panel.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(9)
            verticalPadding: Style.space(4)
            enabled: !detail.unavailable
            onHovered: function(on) { if (on) { detail.cursorId = chipsRow.rowId; chipsRow.chipCursor = index } }
            onClicked: chipsRow.picked(String(modelData))
          }
        }
      }
    }
  }
  component HueRow: CursorSurface {
    id: hueRow
    property string rowId: ""
    property real hue: detail.currentHue
    property bool scrubbing: false

    width: parent ? parent.width : 0
    foreground: panel.foreground
    hasCursor: detail.cursorId === rowId
    implicitHeight: hueLayout.implicitHeight + Style.space(12)
    Component.onCompleted: detail.registerRow(rowId, hueRow)

    Connections {
      target: detail
      function onCurrentHueChanged() { if (!hueRow.scrubbing) hueRow.hue = detail.currentHue }
    }

    function commit() { ha.setLightColor(detail.entityId, hue, detail.currentSat < 5 ? 100 : detail.currentSat) }
    function adjust(dx) {
      hue = ((hue + dx * 10) % 360 + 360) % 360
      hueCommit.restart()
    }
    function activate() { commit() }

    Timer { id: hueCommit; interval: 250; onTriggered: hueRow.commit() }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      propagateComposedEvents: true
      onEntered: detail.cursorId = hueRow.rowId
      onPressed: function(mouse) { mouse.accepted = false }
    }

    ColumnLayout {
      id: hueLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      RowLayout {
        Layout.fillWidth: true
        Text {
          textFormat: Text.PlainText
          text: "Colour"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }
        Rectangle {
          width: Style.space(12); height: Style.space(12); radius: width / 2
          color: Qt.hsla(hueRow.hue / 360, Math.max(0.3, detail.currentSat / 100), 0.55, 1)
        }
        Text {
          textFormat: Text.PlainText
          text: Math.round(hueRow.hue) + "°"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Item {
        Layout.fillWidth: true
        height: Style.space(18)

        Rectangle {
          id: hueTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(8)
          radius: height / 2
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.00; color: "#ff4040" }
            GradientStop { position: 0.17; color: "#ffd040" }
            GradientStop { position: 0.33; color: "#40ff60" }
            GradientStop { position: 0.50; color: "#40ffff" }
            GradientStop { position: 0.67; color: "#4060ff" }
            GradientStop { position: 0.83; color: "#ff40ff" }
            GradientStop { position: 1.00; color: "#ff4040" }
          }
        }

        Rectangle {
          width: Style.space(16); height: width; radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: Math.round(hueRow.hue / 360 * (parent.width - width))
          color: Qt.hsla(hueRow.hue / 360, 1, 0.5, 1)
          border.width: 2
          border.color: panel.foreground
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          function setFrom(x) { hueRow.hue = Model.clamp(x / width, 0, 1) * 360 }
          onPressed: function(mouse) { hueRow.scrubbing = true; setFrom(mouse.x) }
          onPositionChanged: function(mouse) { if (pressed) setFrom(mouse.x) }
          onReleased: { hueRow.scrubbing = false; hueRow.commit() }
        }
      }
    }
  }
}
