import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "TaskbarModel.js" as Model

// Omarchy shell panel plugin: a window taskbar on every monitor.
//
// Mounted at startup (keepLoaded) and stays mounted. Settings are read from
// this plugin's entry in ~/.config/omarchy/shell.json and hot-reload on save.
Item {
  id: root

  // Injected by the shell host.
  property var manifest: null
  property var shell: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : Model.PLUGIN_ID
  property var settings: Model.normalizeSettings(null)
  property bool hidden: false

  readonly property bool edgeTop: settings.position === "top"
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property bool grouped: settings.groupByWorkspace && settings.scope !== "workspace"

  // ------------------------------------------------------------- IPC
  //   omarchy-shell shell call davidcbradleyjr.taskbar <method> <arg>
  function toggleVisible() { root.hidden = !root.hidden; return root.hidden ? "hidden" : "shown" }
  function showBar() { root.hidden = false }
  function hideBar() { root.hidden = true }

  // Ctrl+Alt+N: act on the Nth window of the focused monitor's taskbar, the
  // same as clicking it (focus, restore, or minimize if already focused).
  function focusIndex(n) {
    var monitor = Hyprland.focusedMonitor
    if (!monitor) return "no-monitor"
    var list = root.windowsFor(monitor)
    var index = Model.nthIndex(list.length, n)
    if (index < 0) return "none"
    root.primaryAction(list[index].toplevel)
    return "ok"
  }

  // Toggle the right-click menu for the focused window from the keyboard.
  function menu() {
    var monitor = Hyprland.focusedMonitor
    for (var i = 0; i < root.panels.length; i++) {
      var panel = root.panels[i]
      if (monitor && panel.hyprMonitor === monitor) return panel.openMenuForActive() ? "ok" : "none"
    }
    return "none"
  }

  property var panels: []

  // ------------------------------------------------------------- settings
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.settings = Model.settingsFromText(text(), root.pluginId)
    onLoadFailed: root.settings = Model.normalizeSettings(null)
  }

  // ------------------------------------------------------------- minimize
  // Shared with AppDock and friends: origins of minimized windows keyed by
  // address, plus a newest-first history used by "restore last" tools.
  readonly property string minimizerDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hyprland-minimizer"
  property var minState: ({})

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.minimizerDir])

  FileView {
    id: stateFile
    path: root.minimizerDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.minState = Model.parseState(text())
    onLoadFailed: root.minState = ({})
  }

  FileView {
    id: historyFile
    path: root.minimizerDir + "/history.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  function historyText() {
    try { return historyFile.loaded ? historyFile.text() : "" } catch (e) { return "" }
  }

  function writeState(next) {
    root.minState = next
    stateFile.setText(JSON.stringify(next))
  }

  // ------------------------------------------------------------- windows
  function addressOf(t) { return Model.normalizeAddress(t ? t.address : "") }

  // The Wayland toplevel's state is correct from startup; Hyprland's own
  // flag only updates on the next focus change after the shell (re)starts.
  function isActive(t) {
    if (!t) return false
    return t.wayland ? !!t.wayland.activated : !!t.activated
  }

  function isMinimized(t) {
    return !!(t && t.workspace && String(t.workspace.name) === Model.MINIMIZED_WORKSPACE)
  }

  function describe(t) {
    return {
      workspaceId: t.workspace ? t.workspace.id : NaN,
      workspaceName: t.workspace ? String(t.workspace.name) : "",
      monitorName: t.monitor ? String(t.monitor.name) : "",
      origin: root.minState[root.addressOf(t)] || null
    }
  }

  // The windows a monitor's taskbar lists, in display order, each with the
  // workspace group it belongs to. Bindings that call this re-evaluate when
  // any window, workspace, setting or minimize record changes.
  function windowsFor(hyprMonitor) {
    var monitorName = hyprMonitor ? String(hyprMonitor.name) : ""
    var ws = hyprMonitor ? hyprMonitor.activeWorkspace : null
    var view = {
      scope: root.settings.scope,
      monitorName: monitorName,
      activeWorkspaceId: ws ? ws.id : -9999,
      activeWorkspaceName: ws ? String(ws.name) : ""
    }

    var shown = []
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var info = root.describe(all[i])
      if (!Model.windowVisible(info, view)) continue
      var group = Model.groupFor(info)
      shown.push({ toplevel: all[i], groupKey: group.key, groupLabel: group.label })
    }

    var order = Model.displayOrder(shown.map(function(w) { return w.groupKey }), root.grouped)
    var out = order.map(function(i) { return shown[i] })
    var starts = Model.groupStarts(out.map(function(w) { return w.groupKey }))
    for (var j = 0; j < out.length; j++) out[j].groupStart = root.grouped && starts[j]
    return out
  }

  // ------------------------------------------------------------- actions
  function dispatch(expr) { Hyprland.dispatch(expr) }

  function activate(t) {
    if (!t) return
    if (root.isMinimized(t)) root.restore(t)
    else root.dispatch(Model.dispatch.focusWindow(t.address))
  }

  // Left click / Ctrl+Alt+N
  function primaryAction(t) {
    if (!t) return
    if (root.isMinimized(t)) root.restore(t)
    else if (root.isActive(t) && root.settings.clickToMinimize) root.minimize(t)
    else root.activate(t)
  }

  function minimize(t) {
    if (!t || root.isMinimized(t)) return
    var address = root.addressOf(t)
    // Record the origin first so a workspace-scoped taskbar keeps showing
    // the button (dimmed) the moment the window leaves.
    root.writeState(Model.stateWith(root.minState, address, {
      workspace: t.workspace ? String(t.workspace.name) : "",
      monitor: t.monitor ? String(t.monitor.name) : "",
      thumb: ""
    }))
    historyFile.setText(Model.historyWith(root.historyText(), address))
    root.dispatch(Model.dispatch.moveToWorkspace(address, Model.MINIMIZED_WORKSPACE, false))
  }

  function restore(t) {
    if (!t) return
    var address = root.addressOf(t)
    var origin = root.minState[address]
    var target = origin && origin.workspace && origin.workspace !== Model.MINIMIZED_WORKSPACE ? String(origin.workspace) : ""
    if (!target) {
      var focused = Hyprland.focusedMonitor
      target = focused && focused.activeWorkspace ? String(focused.activeWorkspace.name) : "1"
    }
    root.dispatch(Model.dispatch.moveToWorkspace(address, target, true))
    root.dispatch(Model.dispatch.focusWindow(address))
    root.writeState(Model.stateWithout(root.minState, address))
    historyFile.setText(Model.historyWithout(root.historyText(), address))
  }

  function close(t) {
    if (!t) return
    if (t.wayland) t.wayland.close()
    if (root.isMinimized(t)) root.writeState(Model.stateWithout(root.minState, root.addressOf(t)))
  }

  function toggleFloating(t) { if (t) root.dispatch(Model.dispatch.toggleFloating(t.address)) }
  function togglePin(t) { if (t) root.dispatch(Model.dispatch.togglePin(t.address)) }
  function toggleFullscreen(t) { if (t) root.dispatch(Model.dispatch.toggleFullscreen(t.address)) }
  function moveToWorkspace(t, name) { if (t) root.dispatch(Model.dispatch.moveToWorkspace(t.address, name, false)) }
  function moveToNextMonitor(t) { if (t) root.dispatch(Model.dispatch.moveToMonitor(t.address, "+1")) }
  function focusWorkspace(name) { root.dispatch(Model.dispatch.focusWorkspace(name)) }

  // Forget records for windows that no longer exist (closed while minimized).
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { pruneTimer.restart() }
  }

  Timer {
    id: pruneTimer
    interval: 1500
    onTriggered: {
      var live = ({})
      var all = Hyprland.toplevels.values
      for (var i = 0; i < all.length; i++) live[root.addressOf(all[i])] = true
      var next = root.minState
      var changed = false
      for (var addr in root.minState) if (!live[addr]) { next = Model.stateWithout(next, addr); changed = true }
      if (changed) root.writeState(next)
    }
  }

  // ------------------------------------------------------------- icons
  function appIdOf(toplevel) {
    if (!toplevel) return ""
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    var ipc = toplevel.lastIpcObject
    return ipc && ipc["class"] ? String(ipc["class"]) : ""
  }

  function desktopEntryFor(appId) {
    if (!appId) return null
    try { return DesktopEntries.heuristicLookup(appId) } catch (e) { return null }
  }

  function iconSource(iconName) {
    var value = String(iconName || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function iconForApp(appId) {
    var entry = root.desktopEntryFor(appId)
    return root.iconSource(entry && entry.icon ? entry.icon : appId)
  }

  function monogram(text) {
    var s = String(text || "").replace(/^.*\./, "")
    return s ? s.charAt(0).toUpperCase() : "?"
  }

  function launch(desktopId) {
    var id = String(desktopId || "").replace(/\.desktop$/, "")
    if (id) Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // Pinned launcher: focus the first matching window in view, else launch.
  function openPinned(desktopId, items) {
    var entry = null
    try { entry = DesktopEntries.byId(desktopId) } catch (e) { entry = null }
    var startupClass = entry ? entry.startupClass : ""
    for (var i = 0; i < items.length; i++) {
      if (Model.appMatches(root.appIdOf(items[i].toplevel), desktopId, startupClass)) {
        root.activate(items[i].toplevel)
        return
      }
    }
    root.launch(desktopId)
  }

  // ------------------------------------------------------------- windows
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: panel

        required property var modelData
        screen: modelData

        readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
        readonly property string activeWorkspaceName: hyprMonitor && hyprMonitor.activeWorkspace ? String(hyprMonitor.activeWorkspace.name) : ""
        readonly property var items: root.windowsFor(hyprMonitor)

        function openMenuForActive() {
          for (var i = 0; i < strip.children.length; i++) {
            var cell = strip.children[i]
            if (cell.toplevel && root.isActive(cell.toplevel)) {
              contextMenu.toggleFor(cell.button, cell.toplevel)
              return true
            }
          }
          return false
        }

        Component.onCompleted: root.panels = root.panels.concat([panel])
        Component.onDestruction: root.panels = root.panels.filter(function(p) { return p !== panel })

        function cycle(delta) {
          var current = -1
          for (var i = 0; i < items.length; i++) if (root.isActive(items[i].toplevel)) { current = i; break }
          var next = Model.cycleIndex(items.length, current, delta)
          if (next >= 0) root.activate(items[next].toplevel)
        }

        // Park off-screen instead of unmapping, like the Omarchy bar does, so
        // showing again is only a margin change.
        exclusionMode: root.hidden ? ExclusionMode.Ignore : ExclusionMode.Auto
        anchors {
          top: root.edgeTop
          bottom: !root.edgeTop
          left: true
          right: true
        }
        margins {
          top: root.hidden && root.edgeTop ? -root.barSize : 0
          bottom: root.hidden && !root.edgeTop ? -root.barSize : 0
        }
        implicitHeight: root.barSize
        color: root.settings.transparent ? "transparent" : Color.bar.background
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-taskbar"
        WlrLayershell.layer: WlrLayer.Top
        // Take the keyboard only while the menu is open, so Escape can close it.
        WlrLayershell.keyboardFocus: contextMenu.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        ContextMenu {
          id: contextMenu
          anchorItem: null
          actions: root
          edgeTop: root.edgeTop
          monitorCount: Quickshell.screens.length
        }

        // Wheel anywhere on the strip cycles focus through the listed windows.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.NoButton
          onWheel: function(event) { panel.cycle(event.angleDelta.y) }
        }

        Row {
          id: strip
          spacing: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          x: root.settings.align === "center" ? Math.round((parent.width - width) / 2)
            : root.settings.align === "right" ? parent.width - width - Style.space(8)
            : Style.space(8)

          Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          // Pinned launchers
          Repeater {
            model: root.settings.pinned

            TaskButton {
              required property string modelData
              readonly property var entry: {
                try { return DesktopEntries.byId(modelData) } catch (e) { return null }
              }

              barSize: root.barSize
              edgeTop: root.edgeTop
              showLabel: false
              iconSource: root.iconSource(entry && entry.icon ? entry.icon : modelData)
              fallbackGlyph: root.monogram(entry && entry.name ? entry.name : modelData)
              onClicked: function(button) {
                if (button === Qt.MiddleButton) root.launch(modelData)
                else if (button === Qt.LeftButton) root.openPinned(modelData, panel.items)
              }
              onWheel: function(delta) { panel.cycle(delta) }
            }
          }

          // Divider between launchers and windows
          Rectangle {
            visible: root.settings.pinned.length > 0 && panel.items.length > 0
            width: Math.max(1, Style.space(1))
            height: Math.round(root.barSize * 0.45)
            anchors.verticalCenter: parent.verticalCenter
            color: Color.bar.text
            opacity: 0.2
          }

          // Open windows, optionally preceded by a workspace chip per group
          Repeater {
            model: panel.items

            Row {
              id: cell
              required property var modelData
              required property int index
              readonly property var toplevel: modelData.toplevel
              readonly property string appId: root.appIdOf(toplevel)
              readonly property string windowTitle: toplevel.title || appId
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
                barSize: root.barSize
                label: cell.modelData.groupLabel
                current: cell.modelData.groupLabel === Model.workspaceLabel(panel.activeWorkspaceName)
                onClicked: {
                  var n = Number(cell.modelData.groupKey)
                  if (n > 0 && n < 1000) root.focusWorkspace(String(n))
                }
              }

              TaskButton {
                id: button
                barSize: root.barSize
                edgeTop: root.edgeTop
                showLabel: root.settings.showTitles
                maxWidth: root.settings.maxButtonWidth
                active: root.isActive(cell.toplevel)
                urgent: cell.toplevel.urgent
                minimized: root.isMinimized(cell.toplevel)
                label: cell.windowTitle
                iconSource: root.iconForApp(cell.appId)
                fallbackGlyph: root.monogram(cell.appId || cell.windowTitle)
                onClicked: function(b) {
                  if (b === Qt.MiddleButton) root.close(cell.toplevel)
                  else if (b === Qt.RightButton) contextMenu.openFor(button, cell.toplevel)
                  else root.primaryAction(cell.toplevel)
                }
                onWheel: function(delta) { panel.cycle(delta) }
              }
            }
          }
        }
      }
    }
  }
}
