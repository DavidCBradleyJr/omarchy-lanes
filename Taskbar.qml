import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "TaskbarModel.js" as Model

// Lanes: an Omarchy shell panel plugin that puts a window taskbar on every
// monitor. Mounted at startup (keepLoaded) and stays mounted. Settings come
// from this plugin's shell.json entry and hot-reload on save.
Item {
  id: root

  // Injected by the shell host.
  property var manifest: null
  property var shell: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : Model.PLUGIN_ID
  readonly property var settings: core.settings
  property bool hidden: false

  readonly property bool edgeTop: settings.position === "top"
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property bool autoHide: settings.autoHide
  // How much of an auto-hidden bar stays on screen as the reveal hotspot.
  readonly property int peek: 2

  Actions {
    id: core
    pluginId: root.pluginId
    shell: root.shell
    notifyAgents: true
  }

  // ------------------------------------------------------------- IPC
  //   omarchy-shell shell call davidcbradleyjr.lanes <method> <arg>
  function toggleVisible() { root.hidden = !root.hidden; return root.hidden ? "hidden" : "shown" }
  function showBar() { root.hidden = false }
  function hideBar() { root.hidden = true }

  // Flip auto-hide and save it, so it survives restarts.
  function toggleAutoHide() {
    core.updateSettings({ autoHide: !root.autoHide })
    return root.autoHide ? "auto-hide on" : "auto-hide off"
  }

  // Ctrl+Alt+N: act on the Nth window of the focused monitor's lanes, the
  // same as clicking it (focus, restore, or minimize if already focused).
  function focusIndex(n) {
    var monitor = Hyprland.focusedMonitor
    if (!monitor) return "no-monitor"
    var list = core.windowsFor(monitor)
    var index = Model.nthIndex(list.length, n)
    if (index < 0) return "none"
    core.primaryAction(list[index].toplevel)
    return "ok"
  }

  // Ctrl+Alt+A: jump to the next agent waiting for input.
  function nextAgent() { return core.focusNextWaiting() ? "ok" : "none" }

  // Toggle the top-bar widget's agent list: "working", "waiting" or
  // "minimized". Opens on the focused monitor's widget.
  function agents(filter) {
    var monitor = Hyprland.focusedMonitor
    var list = Model.widgetList()
    for (var i = 0; i < list.length; i++) {
      if (list[i].visible && list[i].mode === "summary" && (!monitor || list[i].screenMonitor === monitor))
        return list[i].showList(filter || "working") ? "open" : "closed"
    }
    return "none"
  }

  // Ctrl+Alt+M: toggle the window menu for the focused window, on whichever
  // strip (bottom bar or top-bar lanes) shows it on the focused monitor.
  function menu() {
    var monitor = Hyprland.focusedMonitor
    var strips = Model.stripList()
    for (var i = 0; i < strips.length; i++) {
      if (monitor && strips[i].hyprMonitor === monitor && strips[i].visible && strips[i].openMenuForActive()) return "ok"
    }
    return "none"
  }

  // ------------------------------------------------------------- windows
  // Create the bar windows a tick after settings change, so a change that
  // turns the bar on and flips auto-hide at once has fully settled first. A
  // layer surface given a new margin before it first maps keeps the old one.
  property bool bottomBarOn: false
  function syncBottomBar() { root.bottomBarOn = root.settings.bottomBar === "show" }
  onSettingsChanged: Qt.callLater(root.syncBottomBar)
  Component.onCompleted: Qt.callLater(root.syncBottomBar)

  Variants {
    model: root.bottomBarOn ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: panel

        required property var modelData
        screen: modelData

        readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
        // Auto-hide keeps the bar out while the pointer is elsewhere and no
        // menu is open. A short delay stops it snapping shut on the way out.
        property bool hovered: false
        readonly property bool revealed: !root.autoHide || hovered || hideDelay.running || strip.menuOpen
        readonly property int offset: root.hidden ? root.barSize
          : (root.autoHide && !revealed ? root.barSize - root.peek : 0)

        Timer { id: hideDelay; interval: 600 }

        // Park off-screen instead of unmapping, like the Omarchy bar does, so
        // showing again is only a margin change.
        exclusionMode: root.hidden || root.autoHide ? ExclusionMode.Ignore : ExclusionMode.Auto
        anchors {
          top: root.edgeTop
          bottom: !root.edgeTop
          left: true
          right: true
        }
        margins {
          top: root.edgeTop ? -panel.offset : 0
          bottom: root.edgeTop ? 0 : -panel.offset
        }
        implicitHeight: root.barSize
        color: root.settings.transparent || (root.autoHide && !revealed) ? "transparent" : Color.bar.background
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-lanes"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        HoverHandler {
          onHoveredChanged: {
            panel.hovered = hovered
            if (!hovered) hideDelay.restart()
          }
        }

        LaneStrip {
          id: strip
          actions: core
          hyprMonitor: panel.hyprMonitor
          barSize: root.barSize
          edgeTop: root.edgeTop
          anchors.verticalCenter: parent.verticalCenter
          opacity: panel.revealed ? 1 : 0
          x: root.settings.align === "center" ? Math.round((parent.width - width) / 2)
            : root.settings.align === "right" ? parent.width - width - Style.space(8)
            : Style.space(8)

          Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }
      }
    }
  }
}
