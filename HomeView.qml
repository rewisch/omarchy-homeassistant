import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The dashboard: entities the user starred, in the order they chose.
Item {
  id: home

  property var panel
  // Follows the panel's service so a view created before the shared service
  // was injected picks it up instead of keeping the dormant fallback.
  property var ha: panel ? panel.ha : null

  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property Item focusItem: null
  readonly property bool ownsKeyboard: false
  readonly property var ids: ha.dashboardIds
  readonly property bool empty: ids.length === 0
  readonly property string groupMode: ha.dashboardGroup
  readonly property bool grouped: groupMode !== "none"
  readonly property var groupMeta: Model.DASHBOARD_GROUPS[Model.groupModeIndex(groupMode)]
  property bool dragging: false
  readonly property string cursorId: cursorActive && cursorIndex >= 0 && cursorIndex < rowsModel.count ? rowsModel.get(cursorIndex).id : ""

  implicitHeight: column.implicitHeight

  // Display rows live in a ListModel so drag reordering can move() items
  // without recreating delegates. Rebuilt only when the computed order or
  // grouping actually differs from what is shown.
  ListModel { id: rowsModel }

  function syncModel() {
    if (dragging) return
    var rows = Model.orderDashboard(ids, groupMode,
      function(id) { return ha.entityFor(id) }, function(id) { return ha.areaNameFor(id) })
    var same = rows.length === rowsModel.count
    for (var i = 0; same && i < rows.length; i++) {
      var cur = rowsModel.get(i)
      if (cur.id !== rows[i].id || cur.group !== rows[i].group) same = false
    }
    if (same) return
    var keepId = cursorId
    rowsModel.clear()
    for (var j = 0; j < rows.length; j++) rowsModel.append({ id: rows[j].id, group: rows[j].group })
    if (keepId !== "") for (var k = 0; k < rowsModel.count; k++) if (rowsModel.get(k).id === keepId) cursorIndex = k
    clampCursor()
  }

  function modelIds() {
    var out = []
    for (var i = 0; i < rowsModel.count; i++) out.push(rowsModel.get(i).id)
    return out
  }

  function clampCursor() {
    if (rowsModel.count === 0) { cursorActive = false; cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(cursorIndex, rowsModel.count - 1))
  }

  onIdsChanged: syncModel()
  onGroupModeChanged: syncModel()
  Connections {
    target: ha
    // Areas arrive after the first states, and status grouping follows live state.
    function onRevisionChanged() { if (home.grouped) home.syncModel() }
  }
  Component.onCompleted: syncModel()

  function move(dx, dy) {
    if (empty) return
    if (!cursorActive) { cursorActive = true; if (dy >= 0 && dx === 0) return }
    if (dy !== 0) {
      cursorIndex = Math.max(0, Math.min(rowsModel.count - 1, cursorIndex + dy))
      list.positionViewAtIndex(cursorIndex, ListView.Contain)
    } else if (dx > 0) {
      panel.openDetail(cursorId, "home")
    }
  }

  function moveCursorRow(delta) {
    if (cursorId === "") return
    if (grouped) { ha.flashAction("Switch to \"No grouping\" (g) to reorder"); return }
    if (ha.moveOnDashboard(cursorId, delta)) cursorIndex += delta
  }

  function activate() {
    if (!cursorActive || cursorId === "") return
    var e = ha.entityFor(cursorId)
    if (e && Model.primaryAction(e)) ha.runPrimary(cursorId)
    else panel.openDetail(cursorId, "home")
  }

  function handleEscape() { return false }

  function removeCurrent() {
    if (cursorId !== "") ha.removeFromDashboard(cursorId)
  }

  function textKey(t) {
    if (t === "p" || t === "P") { if (cursorId !== "") ha.togglePin(cursorId); return true }
    if (t === "d" || t === "D") { removeCurrent(); return true }
    if (t === "J") { moveCursorRow(1); return true }
    if (t === "K") { moveCursorRow(-1); return true }
    if (t === "g" || t === "G") { ha.cycleDashboardGroup(); return true }
    if (t === "e" || t === "E" || t === "i" || t === "I") { if (cursorId !== "") panel.openDetail(cursorId, "home"); return true }
    if (t === "L") { if (ha.wsMissing) installLiveUpdates(); return true }
    if (t === "n" || t === "N") { if (cursorId !== "") ha.toggleAlert(cursorId); return true }
    return false
  }

  function onShown() { cursorActive = false }

  function installLiveUpdates() {
    if (!panel.bar || typeof panel.bar.run !== "function") return
    panel.bar.run(ha.installLiveCommand)
    panel.close()
  }

  readonly property string heroMeta: {
    if (!ha.configured) return "Not set up"
    if (ha.status === "connected") {
      var parts = [ha.transportKind === "websocket" ? "Live" : "Polling"]
      parts.push(ha.entityCount + " entities")
      if (ha.dashboardOnCount > 0) parts.push(ha.dashboardOnCount + " on")
      return parts.join(" · ")
    }
    if (ha.status === "connecting") return "Connecting…"
    if (ha.status === "auth_failed") return "Access token rejected"
    return "Offline"
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    PanelHero {
      id: hero
      width: parent.width
      title: ha.locationName
      meta: home.heroMeta
      foreground: panel.foreground
      fontFamily: panel.fontFamily
      iconOpacity: ha.connected ? 1.0 : 0.45
      iconComponent: Component {
        Text {
          textFormat: Text.PlainText
          text: Model.GLYPH.home
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }
      trailingControl: Component {
        Row {
          spacing: Style.space(2)
          PanelActionButton {
            iconText: home.groupMeta.icon
            tooltipText: home.groupMeta.label + "  (g)"
            foreground: home.grouped ? panel.foreground : panel.dim
            fontFamily: panel.fontFamily
            onClicked: ha.cycleDashboardGroup()
          }
          PanelActionButton {
            iconText: Model.GLYPH.search
            tooltipText: "Browse entities  (a)"
            foreground: panel.foreground
            fontFamily: panel.fontFamily
            onClicked: panel.openBrowse("")
          }
          PanelActionButton {
            iconText: Model.GLYPH.refresh
            tooltipText: "Refresh  (r)"
            foreground: panel.dim
            fontFamily: panel.fontFamily
            onClicked: ha.refresh()
          }
          PanelActionButton {
            iconText: Model.GLYPH.cog
            tooltipText: "Settings  (,)"
            foreground: panel.dim
            fontFamily: panel.fontFamily
            onClicked: panel.openSettings()
          }
        }
      }
    }

    // Connection trouble, shown above the list so stale data stays visible.
    Rectangle {
      visible: ha.configured && !ha.connected && ha.status !== "connecting"
      width: parent.width
      radius: Style.cornerRadius
      color: Style.hoverFillFor(panel.urgent, panel.urgent)
      implicitHeight: bannerRow.implicitHeight + Style.space(16)

      RowLayout {
        id: bannerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: Model.GLYPH.alert
          color: panel.urgent
          font.family: panel.fontFamily
          font.pixelSize: Style.font.heading
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: ha.lastError !== "" ? ha.lastError : "Not connected"
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Button {
          text: ha.status === "auth_failed" ? "Fix" : "Retry"
          bordered: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: ha.status === "auth_failed" ? panel.openSetup() : ha.reconnect()
        }
      }
    }

    // Offer the WebSocket module once: the plugin installer cannot pull
    // packages, so this is where "live updates" gets installed.
    Rectangle {
      visible: ha.connected && ha.wsMissing && !ha.pref("liveHintDismissed", false)
      width: parent.width
      radius: Style.cornerRadius
      color: Style.normalFillFor(panel.foreground, panel.accent)
      implicitHeight: liveRow.implicitHeight + Style.space(16)

      RowLayout {
        id: liveRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: Model.GLYPH.bolt
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.heading
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Get live updates"
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "States are polled every " + ha.refreshIntervalSec + "s. Installing " + ha.wsPackage + " switches to instant pushes and area names."
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
        Button {
          text: "Install"
          iconText: Model.GLYPH.check
          bordered: true
          selected: true
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: home.installLiveUpdates()
        }
        Button {
          text: "Later"
          foreground: panel.dim
          fontFamily: panel.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: ha.setPref("liveHintDismissed", true)
        }
      }
    }

    Text {
      visible: ha.status === "connecting" && ha.entityCount === 0
      textFormat: Text.PlainText
      text: "Connecting to " + ha.url + "…"
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: Style.space(10)
    }

    // Empty state.
    Column {
      visible: home.empty && ha.configured
      width: parent.width
      spacing: Style.space(8)
      topPadding: Style.space(14)
      bottomPadding: Style.space(8)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Model.GLYPH.starOutline
        color: panel.dimmer
        font.family: panel.fontFamily
        font.pixelSize: Style.font.displayLarge
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "Your dashboard is empty"
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(60)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Browse every entity in " + ha.locationName + ", star the ones you care about, and pin one to the bar."
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
      Item { width: 1; height: Style.space(4) }
      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Browse entities"
        iconText: Model.GLYPH.search
        bordered: true
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: panel.openBrowse("")
      }
    }

    ListView {
      id: list
      visible: !home.empty
      width: parent.width
      height: Math.min(contentHeight, Style.space(430))
      spacing: Style.space(2)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height && !home.dragging
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      model: rowsModel
      section.property: "group"
      section.criteria: ViewSection.FullString
      section.delegate: PanelSectionHeader {
        required property string section
        visible: section !== ""
        height: visible ? implicitHeight + Style.space(10) : 0
        text: section
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        leftPadding: Style.space(10)
        verticalAlignment: Text.AlignBottom
      }

      displaced: Transition { NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic } }
      move: Transition { NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic } }

      // Each delegate is a drop target; the row inside is the draggable. While
      // dragging, the row is reparented to the list so it floats above its
      // siblings, and entering another delegate moves the model item.
      delegate: DropArea {
        id: slot
        required property var model
        required property int index
        width: ListView.view.width
        height: row.implicitHeight
        keys: ["ha-row"]

        onEntered: function(drag) {
          var from = drag.source.rowIndex
          var to = slot.index
          if (from >= 0 && from !== to) { rowsModel.move(from, to, 1); home.cursorIndex = to }
        }

        EntityRow {
          id: row
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: slot.width
          panel: home.panel
          ha: home.ha
          rowIndex: slot.index
          entity: home.ha.revision >= 0 ? home.ha.entityFor(slot.model.id) : null
          fallbackId: slot.model.id
          secondary: home.groupMode === "area" ? "" : home.ha.areaNameFor(slot.model.id)
          pinned: home.ha.isPinned(slot.model.id)
          alerted: home.ha.isAlerted(slot.model.id)
          showChevron: hasCursor && !dragEnabled
          dragEnabled: !home.grouped && rowsModel.count > 1
          hasCursor: home.cursorActive && home.cursorIndex === slot.index
          z: dragging ? 10 : 0
          opacity: dragging ? 0.92 : 1

          Drag.active: row.dragging
          Drag.source: row
          Drag.keys: ["ha-row"]
          Drag.hotSpot.x: width / 2
          Drag.hotSpot.y: height / 2

          onDraggingChanged: home.dragging = dragging
          onDragFinished: { home.dragging = false; home.ha.setDashboardOrder(home.modelIds()) }
          onEntered: { home.cursorActive = true; home.cursorIndex = slot.index }
          onBodyClicked: {
            home.cursorActive = true
            home.cursorIndex = slot.index
            var e = home.ha.entityFor(slot.model.id)
            if (e && Model.primaryAction(e)) home.ha.runPrimary(slot.model.id)
            else home.panel.openDetail(slot.model.id, "home")
          }

          states: State {
            when: row.dragging
            ParentChange { target: row; parent: list }
            AnchorChanges { target: row; anchors.horizontalCenter: undefined; anchors.verticalCenter: undefined }
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
      elide: Text.ElideRight
      width: parent.width
    }

    PanelSeparator { width: parent.width; foreground: panel.foreground; visible: !home.empty }

    HintBar {
      width: parent.width
      panel: home.panel
      visible: !home.empty
      hints: [["j/k", "move"], ["⏎", "toggle"], ["→", "details"], ["p", "pin"], ["n", "alert"], ["g", "group"], ["J/K", "reorder"], ["x", "remove"], ["a", "add"]]
    }
  }
}
