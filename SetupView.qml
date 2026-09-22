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
  // Explicit per-host allowance for an unencrypted http:// address. Off by
  // default; only offered when the typed address is cleartext to a
  // non-loopback host, and saved for exactly that host.
  property bool allowInsecure: false
  readonly property string candidateUrl: Model.normalizeUrl(urlField.text)
  readonly property bool candidateInsecure: candidateUrl !== "" && !Model.isSecureUrl(candidateUrl) && !Model.isLoopbackHost(Model.urlHostname(candidateUrl))
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
    allowInsecure = ha.allowInsecureFor !== "" && ha.allowInsecureFor === Model.urlHost(ha.url)
  }

  function connectNow() {
    if (probing) return
    message = ""
    messageIsError = false
    probing = true
    ha.probe(urlField.text, tokenField.text, allowInsecure && candidateInsecure)
  }

  Connections {
    target: ha
    function onProbeFinished(ok, text) {
      setup.probing = false
      setup.message = text
      setup.messageIsError = !ok
      if (ok) {
        // The probe may have settled on https for a bare host; keep that.
        var url = ha.probedUrl !== "" ? ha.probedUrl : urlField.text
        urlField.text = url
        ha.saveConnection(url, tokenField.text, setup.allowInsecure && setup.candidateInsecure)
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
    if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { if (setup.candidateInsecure) setup.allowInsecure = !setup.allowInsecure; event.accepted = true; return }
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
        placeholderText: "https://homeassistant.local:8123"
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

    // Cleartext opt-in, shown only when the typed address needs it.
    Rectangle {
      visible: setup.candidateInsecure
      width: parent.width - Style.space(20)
      x: Style.space(10)
      radius: Style.cornerRadius
      color: Style.hoverFillFor(panel.urgent, panel.urgent)
      implicitHeight: insecureRow.implicitHeight + Style.space(16)

      RowLayout {
        id: insecureRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        spacing: Style.space(10)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Allow unencrypted connection to " + Model.urlHost(setup.candidateUrl)
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "http:// sends your access token and everything you control in the clear; anyone on the network path can read and replay it. Only for a network you fully trust. Prefer https:// whenever your instance offers it.  (Ctrl+U)"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
        ToggleSwitch {
          checked: setup.allowInsecure
          foreground: panel.urgent
          hasCursor: false
          cursorRing: false
          Layout.alignment: Qt.AlignVCenter
          onToggled: setup.allowInsecure = !setup.allowInsecure
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
