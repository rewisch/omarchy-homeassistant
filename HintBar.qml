import QtQuick
import qs.Commons

// Footer with keyboard hints: [["j/k", "move"], ["⏎", "toggle"], ...]
Item {
  id: root
  property var panel
  property var hints: []

  implicitHeight: flow.implicitHeight + Style.space(4)

  Flow {
    id: flow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(12)

    Repeater {
      model: root.hints
      Row {
        required property var modelData
        spacing: Style.space(4)
        Text {
          textFormat: Text.PlainText
          text: modelData[0]
          color: root.panel.dim
          font.family: root.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: modelData[1]
          color: root.panel.dimmer
          font.family: root.panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
