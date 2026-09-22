import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// First-run and connection editor. Verifies the credentials against
// /api/config before anything is saved.
Item {
  id: setup

  property var panel
  // Follows the panel's service so a view created before the shared service
  // was injected picks it up instead of keeping the dormant fallback.
  property var ha: panel ? panel.ha : null

  property bool revealToken: false
  property bool probing: false
  property string message: ""
  property bool messageIsError: false
  readonly property Item focusItem: urlField.text === "" ? urlField : tokenField
  readonly property bool ownsKeyboard: urlField.activeFocus || tokenField.activeFocus

  implicitHeight: column.implicitHeight

  function focusEntry() {
    if (urlField.text === "") urlField.forceActiveFocus()
    else tokenField.forceActiveFocus()
  }

  function onShown() { focusEntry() }
  function move(dx, dy) {}
  function activate() { connectNow() }
  function handleEscape() { return false }
  function textKey(t) { return false }

  Component.onCompleted: {
    urlField.text = ha.url
    tokenField.text = ha.token
  }

  function connectNow() {
    if (probing) return
    message = ""
    messageIsError = false
    probing = true
    ha.probe(urlField.text, tokenField.text)
  }

  Connections {
    target: ha
    function onProbeFinished(ok, text) {
      setup.probing = false
      setup.message = text
      setup.messageIsError = !ok
      if (ok) {
        ha.saveConnection(urlField.text, tokenField.text)
        saveTimer.restart()
      }
    }
  }

  Timer {
    id: saveTimer
    interval: 650
    onTriggered: panel.openHome()
  }

  function fieldKey(event, field) {
    if (event.key === Qt.Key_Escape) { panel.goBack(); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (field === urlField && tokenField.text === "") tokenField.forceActiveFocus()
      else connectNow()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab) { (field === urlField ? tokenField : urlField).forceActiveFocus(); event.accepted = true; return }
    if (event.key === Qt.Key_Backtab) { (field === urlField ? tokenField : urlField).forceActiveFocus(); event.accepted = true; return }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      PanelActionButton {
        visible: ha.configured
        iconText: Model.GLYPH.chevronLeft
        tooltipText: "Back  (esc)"
        foreground: panel.dim
        fontFamily: panel.fontFamily
        onClicked: panel.goBack()
      }
      PanelHero {
        Layout.fillWidth: true
        title: "Home Assistant"
        meta: ha.configured ? "Connection settings" : "Let's connect to your home"
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        iconComponent: Component {
          Text {
            textFormat: Text.PlainText
            text: Model.GLYPH.home
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }
      }
    }

    Text {
      width: parent.width
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      textFormat: Text.PlainText
      text: "Enter the address of your instance and a long-lived access token. Create the token in Home Assistant under your profile: Security → Long-lived access tokens."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)

      PanelSectionHeader { text: "Address"; foreground: panel.foreground; fontFamily: panel.fontFamily }
      TextField {
        id: urlField
        width: parent.width - Style.space(20)
        placeholderText: "http://homeassistant.local:8123"
        foreground: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        enabled: !setup.probing
        Keys.onPressed: function(event) { setup.fieldKey(event, urlField) }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)

      PanelSectionHeader { text: "Access token"; foreground: panel.foreground; fontFamily: panel.fontFamily }
      RowLayout {
        width: parent.width - Style.space(20)
        spacing: Style.space(6)
        TextField {
          id: tokenField
          Layout.fillWidth: true
          password: !setup.revealToken
          placeholderText: "eyJhbGciOi…"
          foreground: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          enabled: !setup.probing
          Keys.onPressed: function(event) { setup.fieldKey(event, tokenField) }
        }
        PanelActionButton {
          iconText: setup.revealToken ? Model.GLYPH.eyeOff : Model.GLYPH.eye
          tooltipText: setup.revealToken ? "Hide token" : "Show token"
          foreground: panel.dim
          fontFamily: panel.fontFamily
          onClicked: setup.revealToken = !setup.revealToken
        }
      }
    }

    RowLayout {
      width: parent.width - Style.space(20)
      x: Style.space(10)
      spacing: Style.space(8)

      Button {
        text: setup.probing ? "Connecting…" : (ha.configured ? "Save" : "Connect")
        iconText: setup.probing ? Model.GLYPH.spinner : Model.GLYPH.check
        iconSpinning: setup.probing
        bordered: true
        selected: true
        enabled: !setup.probing
        foreground: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: setup.connectNow()
      }
      Button {
        visible: ha.configured
        text: "Cancel"
        foreground: panel.dim
        fontFamily: panel.fontFamily
        onClicked: panel.goBack()
      }
      Item { Layout.fillWidth: true }
      Button {
        visible: ha.configured
        text: "Forget"
        iconText: Model.GLYPH.close
        foreground: panel.urgent
        fontFamily: panel.fontFamily
        onClicked: { ha.clearConnection(); urlField.text = ""; tokenField.text = ""; setup.message = ""; urlField.forceActiveFocus() }
      }
    }

    Text {
      visible: setup.message !== ""
      width: parent.width
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      textFormat: Text.PlainText
      text: setup.message
      color: setup.messageIsError ? panel.urgent : panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      leftPadding: Style.space(10)
      textFormat: Text.PlainText
      text: "Saved to ~/.config/omarchy/homeassistant/connection.json (only you can read it)."
      color: panel.dimmer
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    PanelSeparator { width: parent.width; foreground: panel.foreground }

    HintBar {
      width: parent.width
      panel: setup.panel
      hints: [["⇥", "next field"], ["⏎", "connect"], ["esc", ha.configured ? "back" : "close"]]
    }
  }
}
