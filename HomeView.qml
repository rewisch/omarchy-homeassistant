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
  property var ha

  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property Item focusItem: null
  readonly property bool ownsKeyboard: false
  readonly property var ids: ha.dashboardIds
  readonly property bool empty: ids.length === 0
  readonly property string cursorId: cursorActive && cursorIndex >= 0 && cursorIndex < ids.length ? ids[cursorIndex] : ""

  implicitHeight: column.implicitHeight

  function clampCursor() {
    if (ids.length === 0) { cursorActive = false; cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(cursorIndex, ids.length - 1))
  }

  onIdsChanged: clampCursor()

  function move(dx, dy) {
    if (empty) return
    if (!cursorActive) { cursorActive = true; if (dy >= 0 && dx === 0) return }
    if (dy !== 0) {
      cursorIndex = Math.max(0, Math.min(ids.length - 1, cursorIndex + dy))
      list.positionViewAtIndex(cursorIndex, ListView.Contain)
    } else if (dx > 0) {
      panel.openDetail(cursorId, "home")
    }
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
    if (t === "J") { if (cursorId !== "" && ha.moveOnDashboard(cursorId, 1)) cursorIndex++; return true }
    if (t === "K") { if (cursorId !== "" && ha.moveOnDashboard(cursorId, -1)) cursorIndex--; return true }
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
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      model: home.ids
      delegate: EntityRow {
        required property var modelData
        required property int index
        width: ListView.view.width
        panel: home.panel
        ha: home.ha
        entity: home.ha.revision >= 0 ? home.ha.entityFor(modelData) : null
        fallbackId: modelData
        secondary: home.ha.areaNameFor(modelData)
        pinned: home.ha.isPinned(modelData)
        alerted: home.ha.isAlerted(modelData)
        showChevron: hasCursor
        hasCursor: home.cursorActive && home.cursorIndex === index
        onEntered: { home.cursorActive = true; home.cursorIndex = index }
        onBodyClicked: {
          home.cursorActive = true
          home.cursorIndex = index
          var e = home.ha.entityFor(modelData)
          if (e && Model.primaryAction(e)) home.ha.runPrimary(modelData)
          else home.panel.openDetail(modelData, "home")
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
      hints: [["j/k", "move"], ["⏎", "toggle"], ["→", "details"], ["p", "pin"], ["n", "alert"], ["J/K", "reorder"], ["x", "remove"], ["a", "add"]]
    }
  }
}
