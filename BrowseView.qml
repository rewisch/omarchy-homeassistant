import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Search every entity Home Assistant knows about. Star adds to the
// dashboard, pin puts one in the bar, right arrow opens details.
Item {
  id: browse

  property var panel
  property var ha
  property string initialQuery: ""
  // Set when the browser is used as a picker (automation targets): Enter
  // selects instead of starring and returns to settings.
  property string pickFor: ""
  readonly property bool picking: pickFor !== ""

  property string query: ""
  property int groupIndex: 0
  property int cursorIndex: 0
  readonly property Item focusItem: searchField
  readonly property bool ownsKeyboard: searchField.activeFocus
  readonly property var group: Model.GROUPS[groupIndex]
  readonly property var results: ha.revision >= 0
    ? Model.searchEntities(ha.entityList, query, group, function(id) { return ha.areaNameFor(id) }, 300)
    : []
  readonly property string cursorId: cursorIndex >= 0 && cursorIndex < results.length ? results[cursorIndex].entity_id : ""

  implicitHeight: column.implicitHeight

  function focusEntry() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function onShown() { focusEntry() }

  Component.onCompleted: {
    if (initialQuery !== "") { searchField.text = initialQuery; query = initialQuery }
    if (picking) groupIndex = Model.groupIndexForKey("scene")
  }

  onResultsChanged: cursorIndex = Math.max(0, Math.min(cursorIndex, results.length - 1))
  onQueryChanged: cursorIndex = 0
  onGroupIndexChanged: cursorIndex = 0

  function move(dx, dy) {
    if (dy !== 0 && results.length > 0) {
      cursorIndex = Math.max(0, Math.min(results.length - 1, cursorIndex + dy))
      list.positionViewAtIndex(cursorIndex, ListView.Contain)
    } else if (dx !== 0) {
      cycleGroup(dx)
    }
  }

  function cycleGroup(delta) {
    var n = Model.GROUPS.length
    groupIndex = ((groupIndex + delta) % n + n) % n
  }

  function activate() {
    if (cursorId === "") return
    if (picking) { ha.setAutomation(pickFor, cursorId); panel.openSettings(); return }
    ha.toggleDashboard(cursorId)
  }

  function handleEscape() {
    if (searchField.text !== "") { searchField.text = ""; return true }
    return false
  }

  function textKey(t) { return false }
  function removeCurrent() { activate() }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J) || (ctrl && event.key === Qt.Key_N)) { move(0, 1); event.accepted = true; return }
    if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K) || (ctrl && event.key === Qt.Key_P)) { move(0, -1); event.accepted = true; return }
    if (event.key === Qt.Key_PageDown) { move(0, 8); event.accepted = true; return }
    if (event.key === Qt.Key_PageUp) { move(0, -8); event.accepted = true; return }
    if (event.key === Qt.Key_Tab) { cycleGroup(1); event.accepted = true; return }
    if (event.key === Qt.Key_Backtab) { cycleGroup(-1); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (ctrl) { if (cursorId !== "") ha.runPrimary(cursorId) }
      else activate()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) {
      if (searchField.text !== "") searchField.text = ""
      else panel.goBack()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right && (ctrl || searchField.text === "" || searchField.cursorPosition === searchField.text.length)) {
      if (cursorId !== "") panel.openDetail(cursorId, "browse")
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left && ctrl) { panel.goBack(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_Space) { if (cursorId !== "") ha.togglePin(cursorId); event.accepted = true; return }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      PanelActionButton {
        iconText: Model.GLYPH.chevronLeft
        tooltipText: "Back to dashboard  (esc)"
        foreground: panel.dim
        fontFamily: panel.fontFamily
        onClicked: panel.goBack()
      }

      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: browse.picking ? "Pick what should run…" : "Search " + ha.entityCount + " entities…"
        foreground: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        onTextChanged: browse.query = text
        Keys.onPressed: function(event) { browse.handleKey(event) }
      }

      Text {
        textFormat: Text.PlainText
        text: browse.results.length + (browse.results.length >= 300 ? "+" : "")
        color: panel.dimmer
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(4)
      leftPadding: Style.space(2)

      Repeater {
        model: Model.GROUPS
        Button {
          required property var modelData
          required property int index
          text: modelData.label
          selected: index === browse.groupIndex
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          onClicked: { browse.groupIndex = index; browse.focusEntry() }
        }
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.min(Math.max(contentHeight, Style.space(60)), Style.space(400))
      spacing: Style.space(2)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      model: browse.results
      delegate: EntityRow {
        required property var modelData
        required property int index
        width: ListView.view.width
        panel: browse.panel
        ha: browse.ha
        entity: browse.ha.revision >= 0 ? browse.ha.entityFor(modelData.entity_id) : modelData
        secondary: {
          var area = browse.ha.areaNameFor(modelData.entity_id)
          var domain = Model.domainMeta(Model.domainOf(modelData.entity_id)).label
          return area !== "" ? area + " · " + domain : domain
        }
        showStar: !browse.picking
        showChevron: browse.picking && hasCursor
        starred: browse.ha.isOnDashboard(modelData.entity_id)
        pinned: browse.ha.isPinned(modelData.entity_id)
        alerted: browse.ha.isAlerted(modelData.entity_id)
        hasCursor: browse.cursorIndex === index
        onEntered: browse.cursorIndex = index
        onBodyClicked: { browse.cursorIndex = index; browse.activate() }
        onStarClicked: browse.ha.toggleDashboard(modelData.entity_id)
      }

      Text {
        visible: browse.results.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: ha.entityCount === 0 ? (ha.connected ? "No entities yet" : "Waiting for Home Assistant…") : "No matches"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSeparator { width: parent.width; foreground: panel.foreground }

    HintBar {
      width: parent.width
      panel: browse.panel
      hints: browse.picking
        ? [["↑↓", "move"], ["⏎", "choose"], ["⇥", "category"], ["esc", "cancel"]]
        : [["↑↓", "move"], ["⏎", "star"], ["⇥", "category"], ["→", "details"], ["^⏎", "toggle"], ["esc", "back"]]
    }
  }
}
