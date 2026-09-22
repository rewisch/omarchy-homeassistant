import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One entity in a list: icon, name, secondary line, state, trailing control.
// Visuals derive from `hasCursor` only (CursorSurface contract); hover
// reports back through `entered` so the owning view moves its cursor.
CursorSurface {
  id: row

  property var panel
  property var ha
  property var entity: null
  property string fallbackId: ""
  property string secondary: ""
  property bool showControl: true
  property bool showStar: false
  property bool starred: false
  property bool pinned: false
  property bool alerted: false
  property bool showChevron: false

  signal entered()
  signal bodyClicked()
  signal starClicked()

  readonly property string entityId: entity ? entity.entity_id : fallbackId
  readonly property string kind: Model.controlKind(entity)
  readonly property bool unavailable: Model.isUnavailable(entity)
  readonly property bool on: Model.isOn(entity)
  readonly property bool pendingState: !!(entity && entity.__pending)
  readonly property string domain: Model.domainOf(entityId)
  readonly property bool statelessDomain: domain === "scene" || domain === "button" || domain === "input_button" || (domain === "script" && entity && entity.state === "off")
  readonly property string stateText: entity ? (statelessDomain ? "" : (domain === "media_player" ? Model.stateLabel(entity.state) : Model.displayState(entity))) : (ha && ha.entityCount === 0 ? "Loading…" : "Not found")
  readonly property bool stateInline: kind === "switch" && (stateText === "On" || stateText === "Off")
  readonly property string secondaryText: {
    var parts = []
    if (secondary !== "") parts.push(secondary)
    if (domain === "media_player" && entity && (entity.state === "playing" || entity.state === "paused") && entity.attributes && entity.attributes.media_title) {
      var track = String(entity.attributes.media_title)
      if (entity.attributes.media_artist) track += " · " + entity.attributes.media_artist
      parts.push(track)
    }
    return parts.join(" · ")
  }
  readonly property string title: entity ? Model.friendlyName(entity) : Model.titleCase(Model.objectIdOf(fallbackId).replace(/_/g, " "))
  readonly property color iconColor: unavailable ? panel.dimmer : (on ? panel.foreground : panel.dim)

  foreground: panel.foreground
  implicitHeight: content.implicitHeight + Style.space(14)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.entered()
    onClicked: row.bodyClicked()
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: entity ? Model.iconFor(entity) : "󰇘"
      color: row.iconColor
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.heading
      Layout.preferredWidth: Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      Layout.alignment: Qt.AlignVCenter
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Text {
          textFormat: Text.PlainText
          text: row.title
          color: row.unavailable ? row.panel.dim : row.panel.foreground
          font.family: row.panel.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
        Text {
          visible: row.pinned
          textFormat: Text.PlainText
          text: Model.GLYPH.pin
          color: row.panel.dim
          font.family: row.panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: row.alerted
          textFormat: Text.PlainText
          text: Model.GLYPH.bell
          color: row.panel.dim
          font.family: row.panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.secondaryText
        color: row.panel.dimmer
        font.family: row.panel.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }

    Text {
      visible: !row.stateInline && row.stateText !== ""
      textFormat: Text.PlainText
      text: row.stateText
      color: row.kind === "none" && !row.unavailable ? row.panel.foreground : row.panel.dim
      font.family: row.panel.fontFamily
      font.pixelSize: row.kind === "none" ? Style.font.subtitle : Style.font.bodySmall
      elide: Text.ElideRight
      Layout.maximumWidth: Style.space(150)
      Layout.alignment: Qt.AlignVCenter
      opacity: row.pendingState ? 0.6 : 1
    }

    Loader {
      active: row.showControl && row.kind !== "none"
      visible: active
      Layout.alignment: Qt.AlignVCenter
      sourceComponent: row.kind === "switch" ? switchControl
        : (row.kind === "cover" ? coverControl
        : (row.kind === "media" ? mediaControl
        : (row.kind === "lock" ? lockControl : runControl)))
    }

    PanelActionButton {
      visible: row.showStar
      iconText: row.starred ? Model.GLYPH.star : Model.GLYPH.starOutline
      tooltipText: row.starred ? "Remove from dashboard" : "Add to dashboard"
      foreground: row.starred ? row.panel.foreground : row.panel.dim
      fontFamily: row.panel.fontFamily
      Layout.alignment: Qt.AlignVCenter
      onClicked: row.starClicked()
    }

    Text {
      visible: row.showChevron
      textFormat: Text.PlainText
      text: Model.GLYPH.chevronRight
      color: row.panel.dimmer
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      Layout.alignment: Qt.AlignVCenter
    }
  }

  Component {
    id: switchControl
    ToggleSwitch {
      checked: row.on
      busy: row.pendingState
      interactive: !row.unavailable
      foreground: row.panel.foreground
      hasCursor: false
      cursorRing: false
      onToggled: row.ha.runPrimary(row.entityId)
    }
  }

  Component {
    id: runControl
    PanelActionButton {
      iconText: Model.GLYPH.play
      tooltipText: "Activate"
      foreground: row.panel.foreground
      fontFamily: row.panel.fontFamily
      bordered: true
      enabled: !row.unavailable
      onClicked: row.ha.runPrimary(row.entityId)
    }
  }

  Component {
    id: lockControl
    PanelActionButton {
      iconText: row.entity && row.entity.state === "locked" ? "󰌾" : "󰿆"
      tooltipText: row.entity && row.entity.state === "locked" ? "Unlock" : "Lock"
      foreground: row.panel.foreground
      fontFamily: row.panel.fontFamily
      bordered: true
      enabled: !row.unavailable
      onClicked: row.ha.runPrimary(row.entityId)
    }
  }

  Component {
    id: mediaControl
    Row {
      spacing: Style.space(2)
      PanelActionButton {
        iconText: Model.GLYPH.prev
        tooltipText: "Previous"
        foreground: row.panel.dim
        fontFamily: row.panel.fontFamily
        enabled: !row.unavailable
        onClicked: row.ha.mediaCommand(row.entityId, "media_previous_track")
      }
      PanelActionButton {
        iconText: row.entity && row.entity.state === "playing" ? Model.GLYPH.pause : Model.GLYPH.play
        tooltipText: row.entity && row.entity.state === "playing" ? "Pause" : "Play"
        foreground: row.panel.foreground
        fontFamily: row.panel.fontFamily
        bordered: true
        enabled: !row.unavailable
        onClicked: row.ha.mediaCommand(row.entityId, "media_play_pause")
      }
      PanelActionButton {
        iconText: Model.GLYPH.next
        tooltipText: "Next"
        foreground: row.panel.dim
        fontFamily: row.panel.fontFamily
        enabled: !row.unavailable
        onClicked: row.ha.mediaCommand(row.entityId, "media_next_track")
      }
    }
  }

  Component {
    id: coverControl
    Row {
      spacing: Style.space(2)
      PanelActionButton {
        iconText: Model.GLYPH.arrowUp
        tooltipText: "Open"
        foreground: row.panel.foreground
        fontFamily: row.panel.fontFamily
        enabled: !row.unavailable && row.entity.state !== "open"
        onClicked: row.ha.coverCommand(row.entityId, "open_cover")
      }
      PanelActionButton {
        iconText: Model.GLYPH.stop
        tooltipText: "Stop"
        foreground: row.panel.dim
        fontFamily: row.panel.fontFamily
        enabled: !row.unavailable
        onClicked: row.ha.coverCommand(row.entityId, "stop_cover")
      }
      PanelActionButton {
        iconText: Model.GLYPH.arrowDown
        tooltipText: "Close"
        foreground: row.panel.foreground
        fontFamily: row.panel.fontFamily
        enabled: !row.unavailable && row.entity.state !== "closed"
        onClicked: row.ha.coverCommand(row.entityId, "close_cover")
      }
    }
  }
}
