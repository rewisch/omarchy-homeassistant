import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Everything that is not an entity: connection, notifications, the Omarchy
// menu block, and the presence automations.
Item {
  id: settings

  property var panel
  // Follows the panel's service so a view created before the shared service
  // was injected picks it up instead of keeping the dormant fallback.
  property var ha: panel ? panel.ha : null

  property int cursorIndex: panel.settingsCursor
  onCursorIndexChanged: panel.settingsCursor = cursorIndex
  readonly property Item focusItem: null
  readonly property bool ownsKeyboard: false

  readonly property var rows: [
    { key: "connection", section: "Connection" },
    { key: "persistentNotifications", section: "Notifications" },
    { key: "alertNotifications" },
    { key: "menuSync", section: "Omarchy menu" },
    { key: "auto:lock", section: "Automations" },
    { key: "auto:unlock" },
    { key: "auto:screensaver" }
  ]
  readonly property var automationLabels: ({
    "lock": "When the screen locks",
    "unlock": "When it unlocks",
    "screensaver": "When the screensaver starts"
  })

  implicitHeight: column.implicitHeight

  function onShown() {}
  function handleEscape() { return false }
  function removeCurrent() {
    var row = rows[cursorIndex]
    if (row && row.key.indexOf("auto:") === 0) ha.setAutomation(row.key.slice(5), "")
  }
  function textKey(t) {
    if (t === "d" || t === "D") { removeCurrent(); return true }
    return false
  }

  function move(dx, dy) {
    if (dy !== 0) cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + dy))
    else if (dx < 0) panel.goBack()
    else if (dx > 0) activate()
  }

  function activate() {
    if (cursorIndex < 0) return
    activateRow(rows[cursorIndex].key)
  }

  function activateRow(key) {
    if (key === "connection") panel.openSetup()
    else if (key === "persistentNotifications" || key === "alertNotifications") ha.setPref(key, !(ha.pref(key, true) === true))
    else if (key === "menuSync") ha.setMenuSync(!(ha.pref("menuSync", false) === true))
    else if (key.indexOf("auto:") === 0) panel.openBrowse("", { pickFor: key.slice(5) })
  }

  function automationValue(kind) {
    var id = ha.automation(kind)
    if (id === "") return "Nothing"
    var e = ha.entityFor(id)
    return e ? Model.friendlyName(e) : id
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      PanelActionButton {
        iconText: Model.GLYPH.chevronLeft
        tooltipText: "Back  (esc)"
        foreground: panel.dim
        fontFamily: panel.fontFamily
        onClicked: panel.goBack()
      }
      PanelHero {
        Layout.fillWidth: true
        title: "Settings"
        meta: ha.locationName + " · " + ha.transportLabel
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        iconComponent: Component {
          Text {
            textFormat: Text.PlainText
            text: Model.GLYPH.cog
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }
      }
    }

    Repeater {
      model: settings.rows
      Column {
        required property var modelData
        required property int index
        width: column.width
        spacing: Style.space(4)

        PanelSectionHeader {
          visible: !!modelData.section
          text: modelData.section || ""
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          leftPadding: Style.space(10)
          topPadding: index === 0 ? Style.space(2) : Style.space(10)
        }

        SettingRow {
          rowKey: modelData.key
          rowIndex: index
        }
      }
    }

    // What the menu block looks like, so the toggle is not a leap of faith.
    Text {
      visible: ha.pref("menuSync", false) === true
      width: parent.width
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      textFormat: Text.PlainText
      text: "A \"Home\" entry with your dashboard now lives in the Omarchy menu (Super+Alt+Space). It is regenerated whenever the dashboard changes."
      color: panel.dimmer
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
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
      panel: settings.panel
      hints: [["j/k", "move"], ["⏎", "toggle / pick"], ["x", "clear"], ["esc", "back"]]
    }
  }

  component SettingRow: CursorSurface {
    id: row
    property string rowKey: ""
    property int rowIndex: 0
    readonly property bool isToggle: rowKey === "persistentNotifications" || rowKey === "alertNotifications" || rowKey === "menuSync"
    readonly property bool isAutomation: rowKey.indexOf("auto:") === 0
    readonly property bool checked: rowKey === "menuSync" ? ha.pref("menuSync", false) === true : ha.pref(rowKey, true) === true
    readonly property string title: {
      if (rowKey === "connection") return ha.configured ? ha.locationName : "Not connected"
      if (rowKey === "persistentNotifications") return "Home Assistant notifications"
      if (rowKey === "alertNotifications") return "Entity alerts"
      if (rowKey === "menuSync") return "Home submenu in the Omarchy menu"
      return settings.automationLabels[rowKey.slice(5)] || rowKey
    }
    readonly property string subtitle: {
      if (rowKey === "connection") return ha.configured ? ha.url : "Set up the connection"
      if (rowKey === "persistentNotifications") return "Show notifications Home Assistant raises on this desktop"
      if (rowKey === "alertNotifications") return "Notify when an entity marked with the bell changes"
      if (rowKey === "menuSync") return "Your dashboard's scenes and toggles, one keystroke away"
      return settings.automationValue(rowKey.slice(5))
    }

    width: column.width
    foreground: panel.foreground
    hasCursor: settings.cursorIndex === rowIndex
    implicitHeight: rowLayout.implicitHeight + Style.space(14)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: settings.cursorIndex = row.rowIndex
      onClicked: settings.activateRow(row.rowKey)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.title
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.subtitle
          color: row.isAutomation && row.subtitle !== "Nothing" ? panel.dim : panel.dimmer
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        visible: row.isToggle
        checked: row.checked
        foreground: panel.foreground
        hasCursor: row.hasCursor
        cursorRing: false
        onToggled: settings.activateRow(row.rowKey)
      }

      Text {
        visible: !row.isToggle
        textFormat: Text.PlainText
        text: Model.GLYPH.chevronRight
        color: panel.dimmer
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
