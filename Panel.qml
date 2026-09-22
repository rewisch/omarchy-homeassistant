import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill + popup panel. The panel is a tiny app with four views:
//   setup   - enter URL and token, verify, save
//   home    - the dashboard: entities the user picked, in their order
//   browse  - search every entity, star to add, pin to the bar
//   detail  - rich controls for one entity plus its attributes
Panel {
  id: root
  moduleName: "rewisch.homeassistant"
  ipcTarget: "rewisch.homeassistant"
  manageIpc: false

  property string view: "home"
  property string detailEntityId: ""
  property string detailReturnView: "home"
  property string browseInitialQuery: ""
  property var browseOptions: ({})
  property int settingsCursor: -1

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color dimmer: Qt.darker(foreground, 2.0)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)
  readonly property int panelWidth: Style.space(440)

  readonly property string barGlyph: Model.GLYPH.home
  readonly property string barLabel: {
    var parts = []
    var list = ha.barEntities
    for (var i = 0; i < list.length; i++) if (list[i]) parts.push(Model.barLabel(list[i]))
    return parts.join(" · ")
  }
  readonly property string statusText: {
    if (!ha.configured) return "Not set up"
    if (ha.status === "connected") return ha.transportKind === "websocket" ? "Live" : "Polling"
    if (ha.status === "connecting") return "Connecting…"
    if (ha.status === "auth_failed") return "Token rejected"
    if (ha.status === "unsupported") return "No transport"
    return "Offline"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // One connection per shell: the service instance the host created for this
  // plugin. The private instance only wakes up if the host cannot provide one.
  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null
  readonly property var ha: sharedService || localService
  readonly property bool usingSharedService: sharedService !== null

  Service {
    id: localService
    active: root.bar !== null && root.sharedService === null
    settings: root.settings
  }

  function pushSettings() {
    if (root.sharedService) root.sharedService.settings = root.settings
  }
  onSharedServiceChanged: pushSettings()
  onSettingsChanged: pushSettings()

  function initialView() {
    if (!ha.configured) return "setup"
    return "home"
  }

  function showView(name) {
    if (view === name) { loadView(); return }
    view = name
  }

  function openHome() { showView("home") }

  function openBrowse(query, options) {
    browseInitialQuery = String(query || "")
    browseOptions = options || {}
    showView("browse")
  }

  function openSettings() { showView("settings") }

  function openDetail(entityId, returnTo) {
    detailEntityId = String(entityId || "")
    detailReturnView = returnTo || view
    if (detailEntityId !== "") showView("detail")
  }

  function openSetup() { showView("setup") }

  function goBack() {
    if (view === "detail") showView(detailReturnView === "detail" ? "home" : detailReturnView)
    else if (view === "browse") showView(browseOptions && browseOptions.pickFor ? "settings" : "home")
    else if (view === "settings") showView("home")
    else if (view === "setup" && ha.configured) showView("settings")
    else close()
  }

  function refocus() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (viewLoader.item && viewLoader.item.focusEntry) viewLoader.item.focusEntry()
      else keyCatcher.forceActiveFocus()
    })
  }

  onOpenedChanged: {
    if (!opened) return
    ha.reloadFiles()
    view = (!ha.configured) ? "setup" : (view === "setup" ? "home" : view)
    // Live mode already has current state; a full re-sync of thousands of
    // entities on every open is exactly the stall it would be trying to avoid.
    if (ha.transportKind !== "websocket" || !ha.connected) ha.refresh()
    refocus()
  }

  onViewChanged: loadView()

  Connections {
    target: ha
    function onConfiguredChanged() {
      if (!root.opened) return
      if (!ha.configured) root.view = "setup"
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { ha.refresh(); return "ok" }
    function browse(): void { root.open(); root.openBrowse("") }
    function setup(): void { root.open(); root.openSetup() }
    function settings(): void { root.open(); root.openSettings() }
    function status(): string { return root.statusText }
    function info(): string {
      return JSON.stringify({ shared: root.usingSharedService, transport: root.ha.transportKind, status: root.ha.status, entities: root.ha.entityCount,
        automations: root.ha.automations, automationsActive: root.ha.automationsActive, presence: [root.ha._lockedState, root.ha._screensaverState],
        eventsTotal: root.ha.eventsTotal, eventsPerSecond: root.ha.eventsPerSecond, revision: root.ha.revision, lastSyncMs: root.ha.lastSyncMs })
    }
    function toggleEntity(entityId: string): string { return ha.runPrimary(entityId) ? "ok" : "unknown" }
    function turnOn(entityId: string): string { return ha.turnOn(entityId) ? "ok" : "error" }
    function turnOff(entityId: string): string { return ha.turnOff(entityId) ? "ok" : "error" }
    function state(entityId: string): string {
      var e = ha.entityFor(entityId)
      return e ? String(e.state) : ""
    }
    function call(service: string, entityId: string): string {
      var parts = String(service || "").split(".")
      if (parts.length !== 2) return "usage: call <domain.service> <entity_id>"
      return ha.call(parts[0], parts[1], entityId ? { entity_id: entityId } : {}) ? "ok" : "error"
    }
    function detail(entityId: string): void { root.open(); root.openDetail(entityId, "home") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || root.barLabel === "" ? root.barGlyph : root.barGlyph + " " + root.barLabel
    dimmed: ha.configured && !ha.connected
    active: ha.attention
    tooltipText: {
      var lines = []
      var list = ha.barEntities
      for (var i = 0; i < list.length; i++) if (list[i]) lines.push(Model.friendlyName(list[i]) + " · " + Model.displayState(list[i]))
      lines.push("Home Assistant · " + root.statusText)
      return lines.join("\n")
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (ha.barEntity && Model.primaryAction(ha.barEntity)) ha.runPrimary(ha.barEntityId)
        else ha.refresh()
      } else if (buttonCode === Qt.MiddleButton) {
        ha.refresh()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: viewLoader.item && viewLoader.item.focusItem ? viewLoader.item.focusItem : keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(viewLoader.item ? viewLoader.item.implicitHeight : Style.space(120), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: viewLoader.item ? viewLoader.item.ownsKeyboard === true : false

      onMoveRequested: function(dx, dy) { if (viewLoader.item) viewLoader.item.move(dx, dy) }
      onActivateRequested: if (viewLoader.item) viewLoader.item.activate()
      onCloseRequested: { if (!viewLoader.item || !viewLoader.item.handleEscape()) root.goBack() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: if (viewLoader.item && viewLoader.item.removeCurrent) viewLoader.item.removeCurrent()
      onTextKey: function(t) {
        if (viewLoader.item && viewLoader.item.textKey(t)) return
        if (t === "r" || t === "R") ha.refresh()
        else if (t === "/" || t === "a" || t === "A") root.openBrowse("")
        else if (t === "," ) root.openSettings()
      }

      Loader {
        id: viewLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        asynchronous: false
      }
    }
  }

  function viewFile(name) {
    if (name === "setup") return "SetupView.qml"
    if (name === "settings") return "SettingsView.qml"
    if (name === "browse") return "BrowseView.qml"
    if (name === "detail") return "DetailView.qml"
    return "HomeView.qml"
  }

  function loadView() {
    var props = { panel: root }
    if (view === "browse") { props.initialQuery = browseInitialQuery; props.pickFor = browseOptions && browseOptions.pickFor ? String(browseOptions.pickFor) : "" }
    if (view === "detail") props.entityId = detailEntityId
    viewLoader.setSource(Qt.resolvedUrl(viewFile(view)), props)
    refocus()
  }

  Component.onCompleted: loadView()
}
