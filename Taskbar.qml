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

  // ------------------------------------------------------------- IPC
  // omarchy-shell shell call davidcbradleyjr.taskbar toggleVisible ""
  function toggleVisible() { root.hidden = !root.hidden; return root.hidden ? "hidden" : "shown" }
  function showBar() { root.hidden = false }
  function hideBar() { root.hidden = true }

  // ------------------------------------------------------------- settings
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.settings = Model.settingsFromText(text(), root.pluginId)
    onLoadFailed: root.settings = Model.normalizeSettings(null)
  }

  // ------------------------------------------------------------- helpers
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

  function activate(toplevel) {
    if (toplevel && toplevel.wayland) toplevel.wayland.activate()
  }

  function close(toplevel) {
    if (toplevel && toplevel.wayland) toplevel.wayland.close()
  }

  function launch(desktopId) {
    var id = String(desktopId || "").replace(/\.desktop$/, "")
    if (id) Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // Pinned launcher: focus the first matching window in view, else launch.
  function openPinned(desktopId, visibleToplevels) {
    var entry = null
    try { entry = DesktopEntries.byId(desktopId) } catch (e) { entry = null }
    var startupClass = entry ? entry.startupClass : ""
    for (var i = 0; i < visibleToplevels.length; i++) {
      if (Model.appMatches(root.appIdOf(visibleToplevels[i]), desktopId, startupClass)) {
        root.activate(visibleToplevels[i])
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
        readonly property string monitorName: hyprMonitor ? String(hyprMonitor.name) : String(modelData.name || "")
        readonly property int activeWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : -9999

        // Windows currently shown on this monitor, in Hyprland's (stable,
        // creation) order. Rebuilt whenever anything it reads changes.
        readonly property var shownToplevels: {
          var out = []
          var all = Hyprland.toplevels.values
          var view = { scope: root.settings.scope, monitorName: panel.monitorName, activeWorkspaceId: panel.activeWorkspaceId }
          for (var i = 0; i < all.length; i++) {
            var t = all[i]
            var win = {
              workspaceId: t.workspace ? t.workspace.id : NaN,
              monitorName: t.monitor ? String(t.monitor.name) : ""
            }
            if (Model.windowVisible(win, view)) out.push(t)
          }
          return out
        }

        function cycle(delta) {
          var list = panel.shownToplevels
          var current = -1
          for (var i = 0; i < list.length; i++) if (list[i].activated) { current = i; break }
          var next = Model.cycleIndex(list.length, current, delta)
          if (next >= 0) root.activate(list[next])
        }

        // Park off-screen instead of unmapping, like the Omarchy bar does, so
        // showing again is only a margin change.
        visible: true
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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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
                else if (button === Qt.LeftButton) root.openPinned(modelData, panel.shownToplevels)
              }
              onWheel: function(delta) { panel.cycle(delta) }
            }
          }

          // Divider between launchers and windows
          Rectangle {
            visible: root.settings.pinned.length > 0 && panel.shownToplevels.length > 0
            width: Math.max(1, Style.space(1))
            height: Math.round(root.barSize * 0.45)
            anchors.verticalCenter: parent.verticalCenter
            color: Color.bar.text
            opacity: 0.2
          }

          // Open windows
          Repeater {
            model: panel.shownToplevels

            TaskButton {
              required property var modelData
              readonly property string appId: root.appIdOf(modelData)
              readonly property string windowTitle: modelData.title || appId

              barSize: root.barSize
              edgeTop: root.edgeTop
              showLabel: root.settings.showTitles
              maxWidth: root.settings.maxButtonWidth
              active: modelData.activated
              urgent: modelData.urgent
              label: windowTitle
              badge: root.settings.showWorkspace && root.settings.scope !== "workspace" && modelData.workspace
                ? Model.workspaceLabel(modelData.workspace.id) : ""
              iconSource: root.iconForApp(appId)
              fallbackGlyph: root.monogram(appId || windowTitle)
              onClicked: function(button) {
                if (button === Qt.MiddleButton) root.close(modelData)
                else if (button === Qt.LeftButton) root.activate(modelData)
              }
              onWheel: function(delta) { panel.cycle(delta) }
            }
          }
        }
      }
    }
  }
}
