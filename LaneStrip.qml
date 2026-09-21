import QtQuick
import Quickshell
import qs.Commons
import "TaskbarModel.js" as Model

// The row of lanes for one monitor: pinned launchers, then windows grouped by
// workspace. Used by the bottom bar and by the top-bar widget's inline mode.
Item {
  id: strip

  property var actions: null
  property var hyprMonitor: null
  property int barSize: Style.bar.sizeHorizontal
  property bool edgeTop: false
  // Space the strip may take. Over it, titles drop to icons only; still
  // over, the strip clips. Only the inline top-bar mode sets this.
  property real maxWidth: Infinity

  // Width the strip needed with titles on, remembered while compact so it
  // can tell when titles fit again (hysteresis, so it doesn't flap).
  property real labelledWidth: 0
  property bool compact: false
  readonly property bool titles: !!actions && actions.settings.showTitles && !compact

  function fitCheck() {
    if (!isFinite(maxWidth)) { compact = false; return }
    if (!compact && row.implicitWidth > maxWidth) {
      labelledWidth = row.implicitWidth
      compact = true
    } else if (compact && labelledWidth > 0 && labelledWidth < maxWidth - Style.space(16)) {
      compact = false
    }
  }

  onMaxWidthChanged: fitTimer.restart()
  onItemsChanged: { labelledWidth = 0; compact = false; fitTimer.restart() }
  Timer { id: fitTimer; interval: 250; onTriggered: strip.fitCheck() }

  readonly property var items: actions ? actions.windowsFor(hyprMonitor) : []
  readonly property bool menuOpen: contextMenu.open
  readonly property string activeWorkspaceName: hyprMonitor && hyprMonitor.activeWorkspace ? String(hyprMonitor.activeWorkspace.name) : ""

  implicitWidth: Math.min(row.implicitWidth, maxWidth)
  implicitHeight: barSize
  clip: isFinite(maxWidth) && row.implicitWidth > maxWidth

  function cycle(delta) {
    var current = -1
    for (var i = 0; i < items.length; i++) if (actions.isActive(items[i].toplevel)) { current = i; break }
    var next = Model.cycleIndex(items.length, current, delta)
    if (next >= 0) actions.activate(items[next].toplevel)
  }

  function openMenuForActive() {
    for (var i = 0; i < row.children.length; i++) {
      var cell = row.children[i]
      if (cell.toplevel && actions.isActive(cell.toplevel)) {
        contextMenu.toggleFor(cell.button, cell.toplevel)
        return true
      }
    }
    return false
  }

  // "waiting" if any window in the workspace group waits on you, else
  // "working" if any agent there is busy.
  function groupAgentState(groupKey) {
    var states = actions ? actions.agentStates : ({})
    var working = false
    for (var i = 0; i < items.length; i++) {
      if (items[i].groupKey !== groupKey) continue
      var state = states[actions.addressOf(items[i].toplevel)]
      if (state === "waiting") return "waiting"
      if (state === "working") working = true
    }
    return working ? "working" : ""
  }

  Component.onCompleted: Model.registerStrip(strip)
  Component.onDestruction: Model.unregisterStrip(strip)

  ContextMenu {
    id: contextMenu
    anchorItem: null
    actions: strip.actions
    edgeTop: strip.edgeTop
    monitorCount: Quickshell.screens.length
  }

  // Wheel anywhere on the strip cycles focus through the listed windows.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(event) { strip.cycle(event.angleDelta.y) }
  }

  Row {
    id: row
    spacing: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter

    // Pinned launchers
    Repeater {
      model: strip.actions ? strip.actions.settings.pinned : []

      TaskButton {
        required property string modelData
        readonly property var entry: {
          try { return DesktopEntries.byId(modelData) } catch (e) { return null }
        }

        barSize: strip.barSize
        edgeTop: strip.edgeTop
        showLabel: false
        iconSource: strip.actions.iconSource(entry && entry.icon ? entry.icon : modelData)
        fallbackGlyph: strip.actions.monogram(entry && entry.name ? entry.name : modelData)
        onClicked: function(button) {
          if (button === Qt.MiddleButton) strip.actions.launch(modelData)
          else if (button === Qt.LeftButton) strip.actions.openPinned(modelData, strip.items)
        }
        onWheel: function(delta) { strip.cycle(delta) }
      }
    }

    // Divider between launchers and windows
    Rectangle {
      visible: !!strip.actions && strip.actions.settings.pinned.length > 0 && strip.items.length > 0
      width: Math.max(1, Style.space(1))
      height: Math.round(strip.barSize * 0.45)
      anchors.verticalCenter: parent.verticalCenter
      color: Color.bar.text
      opacity: 0.2
    }

    // Open windows, each group preceded by its workspace chip
    Repeater {
      model: strip.items

      Row {
        id: cell
        required property var modelData
        required property int index
        readonly property var toplevel: modelData.toplevel
        readonly property string appId: strip.actions.appIdOf(toplevel)
        readonly property string agent: strip.actions.agentStateOf(toplevel)
        readonly property string windowTitle: {
          var title = toplevel.title || appId
          return agent ? Model.agentLabel(title) : title
        }
        property alias button: button

        spacing: Style.space(2)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Item {
          visible: cell.modelData.groupStart && cell.index > 0
          width: Style.space(6)
          height: 1
        }

        WorkspaceChip {
          visible: cell.modelData.groupStart
          barSize: strip.barSize
          label: cell.modelData.groupLabel
          current: cell.modelData.groupLabel === Model.workspaceLabel(strip.activeWorkspaceName)
          agent: visible ? strip.groupAgentState(cell.modelData.groupKey) : ""
          onClicked: {
            var n = Number(cell.modelData.groupKey)
            if (n > 0 && n < 1000) strip.actions.focusWorkspace(String(n))
          }
        }

        TaskButton {
          id: button
          barSize: strip.barSize
          edgeTop: strip.edgeTop
          showLabel: strip.titles
          onImplicitWidthChanged: fitTimer.restart()
          maxWidth: strip.actions.settings.maxButtonWidth
          active: strip.actions.isActive(cell.toplevel)
          urgent: cell.toplevel.urgent
          minimized: strip.actions.isMinimized(cell.toplevel)
          agent: cell.agent
          label: cell.windowTitle
          iconSource: strip.actions.iconForApp(cell.appId)
          fallbackGlyph: strip.actions.monogram(cell.appId || cell.windowTitle)
          onClicked: function(b) {
            if (b === Qt.MiddleButton) strip.actions.close(cell.toplevel)
            else if (b === Qt.RightButton) contextMenu.openFor(button, cell.toplevel)
            else strip.actions.primaryAction(cell.toplevel)
          }
          onWheel: function(delta) { strip.cycle(delta) }
        }
      }
    }
  }
}
