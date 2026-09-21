import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "TaskbarModel.js" as Model

// Shared state and window actions. The bottom bar and the top-bar widget
// each own one of these; both read the same shell.json entry and the same
// minimize records, so they always agree.
Item {
  id: actions

  property string pluginId: Model.PLUGIN_ID
  property var shell: null
  // Only one instance (the bottom bar's) posts agent notifications.
  property bool notifyAgents: false

  property var settings: Model.normalizeSettings(null)
  property var entry: null
  readonly property bool grouped: settings.groupByWorkspace && settings.scope !== "workspace"

  visible: false

  // ------------------------------------------------------------- settings
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      actions.entry = Model.entryFromText(text(), actions.pluginId)
      actions.settings = Model.normalizeSettings(actions.entry)
    }
    onLoadFailed: actions.settings = Model.normalizeSettings(null)
  }

  // Persist a settings change on this plugin's shell.json entry, keeping
  // every other key the user set.
  function updateSettings(changes) {
    var next = actions.entry ? JSON.parse(JSON.stringify(actions.entry)) : { id: actions.pluginId }
    for (var k in changes) next[k] = changes[k]
    actions.entry = next
    actions.settings = Model.normalizeSettings(next)
    if (actions.shell && typeof actions.shell.updateEntryInline === "function")
      actions.shell.updateEntryInline(actions.pluginId, next)
  }

  // ------------------------------------------------------------- minimize
  // Shared with AppDock and friends: origins of minimized windows keyed by
  // address, plus a newest-first history used by "restore last" tools.
  readonly property string minimizerDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hyprland-minimizer"
  property var minState: ({})

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", actions.minimizerDir])
    // Seed the agent map without notifying: agents already waiting at
    // startup didn't just finish.
    actions.syncAgentStates()
    actions.previousAgentStates = actions.agentStates
  }

  FileView {
    id: stateFile
    path: actions.minimizerDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: actions.minState = Model.parseState(text())
    onLoadFailed: actions.minState = ({})
  }

  FileView {
    id: historyFile
    path: actions.minimizerDir + "/history.txt"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  function historyText() {
    try { return historyFile.loaded ? historyFile.text() : "" } catch (e) { return "" }
  }

  function writeState(next) {
    actions.minState = next
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

  // Reads the title, so call it from per-button bindings, not from anything
  // that rebuilds a list: agent spinners change titles several times a second.
  function agentStateOf(t) {
    return t && actions.settings.agents ? Model.agentState(t.title, actions.settings) : ""
  }

  function describe(t) {
    return {
      workspaceId: t.workspace ? t.workspace.id : NaN,
      workspaceName: t.workspace ? String(t.workspace.name) : "",
      monitorName: t.monitor ? String(t.monitor.name) : "",
      origin: actions.minState[actions.addressOf(t)] || null
    }
  }

  // The windows a monitor's strip lists, in display order, each with the
  // workspace group it belongs to. Deliberately doesn't read titles.
  function windowsFor(hyprMonitor, scopeOverride) {
    var scope = scopeOverride || actions.settings.scope
    var monitorName = hyprMonitor ? String(hyprMonitor.name) : ""
    var ws = hyprMonitor ? hyprMonitor.activeWorkspace : null
    var view = {
      scope: scope,
      monitorName: monitorName,
      activeWorkspaceId: ws ? ws.id : -9999,
      activeWorkspaceName: ws ? String(ws.name) : ""
    }
    var grouped = actions.settings.groupByWorkspace && scope !== "workspace"

    var shown = []
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var info = actions.describe(all[i])
      if (!Model.windowVisible(info, view)) continue
      var group = Model.groupFor(info)
      shown.push({ toplevel: all[i], groupKey: group.key, groupLabel: group.label })
    }

    var order = Model.displayOrder(shown.map(function(w) { return w.groupKey }), grouped)
    var out = order.map(function(i) { return shown[i] })
    var starts = Model.groupStarts(out.map(function(w) { return w.groupKey }))
    for (var j = 0; j < out.length; j++) out[j].groupStart = grouped && starts[j]
    return out
  }

  // Every window everywhere, grouped by workspace: the order the keyboard
  // "next agent" command and the summary popup walk.
  function allWindows() { return actions.windowsFor(null, "all") }

  // ------------------------------------------------------------- agents
  // Address -> agent state for every window. The raw map re-evaluates on
  // every title change (spinner frames included); agentStates only changes
  // when some agent's state really does, so chips and popups stay put.
  readonly property var rawAgentStates: {
    var out = ({})
    if (!actions.settings.agents) return out
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var state = Model.agentState(all[i].title, actions.settings)
      if (state) out[actions.addressOf(all[i])] = state
    }
    return out
  }

  property var agentStates: ({})
  property string agentStatesKey: ""

  function syncAgentStates() {
    var key = JSON.stringify(actions.rawAgentStates)
    if (key === actions.agentStatesKey) return
    actions.agentStatesKey = key
    actions.agentStates = actions.rawAgentStates
  }

  onRawAgentStatesChanged: syncAgentStates()

  readonly property var agentTotals: {
    var list = []
    for (var addr in actions.agentStates) list.push(actions.agentStates[addr])
    return Model.agentCounts(list)
  }

  property var previousAgentStates: ({})

  onAgentStatesChanged: {
    var finished = Model.finishedAgents(actions.previousAgentStates, actions.agentStates)
    actions.previousAgentStates = actions.agentStates
    if (!actions.notifyAgents || !actions.settings.agentNotify) return
    var all = Hyprland.toplevels.values
    for (var i = 0; i < finished.length; i++) {
      for (var j = 0; j < all.length; j++) {
        var t = all[j]
        if (actions.addressOf(t) !== finished[i] || actions.isActive(t)) continue
        var where = t.workspace ? "workspace " + Model.workspaceLabel(t.workspace.id) : ""
        Quickshell.execDetached(["notify-send", "-a", "Lanes", "-i", "dialog-information",
          "Agent waiting for you", Model.agentLabel(t.title) + (where ? "  ·  " + where : "")])
      }
    }
  }

  // Focus the next agent that's waiting for input, in workspace order.
  function focusNextWaiting() {
    var list = actions.allWindows()
    var states = list.map(function(w) { return actions.agentStates[actions.addressOf(w.toplevel)] || "" })
    var current = -1
    for (var i = 0; i < list.length; i++) if (actions.isActive(list[i].toplevel)) { current = i; break }
    var next = Model.nextWaitingIndex(states, current)
    if (next < 0) return false
    actions.activate(list[next].toplevel)
    return true
  }

  // ------------------------------------------------------------- actions
  function dispatch(expr) { Hyprland.dispatch(expr) }

  function activate(t) {
    if (!t) return
    if (actions.isMinimized(t)) actions.restore(t)
    else actions.dispatch(Model.dispatch.focusWindow(t.address))
  }

  // Left click / Ctrl+Alt+N
  function primaryAction(t) {
    if (!t) return
    if (actions.isMinimized(t)) actions.restore(t)
    else if (actions.isActive(t) && actions.settings.clickToMinimize) actions.minimize(t)
    else actions.activate(t)
  }

  function minimize(t) {
    if (!t || actions.isMinimized(t)) return
    var address = actions.addressOf(t)
    // Record the origin first so a workspace-scoped strip keeps showing the
    // button (dimmed) the moment the window leaves.
    actions.writeState(Model.stateWith(actions.minState, address, {
      workspace: t.workspace ? String(t.workspace.name) : "",
      monitor: t.monitor ? String(t.monitor.name) : "",
      thumb: ""
    }))
    historyFile.setText(Model.historyWith(actions.historyText(), address))
    actions.dispatch(Model.dispatch.moveToWorkspace(address, Model.MINIMIZED_WORKSPACE, false))
  }

  function restore(t) {
    if (!t) return
    var address = actions.addressOf(t)
    var origin = actions.minState[address]
    var target = origin && origin.workspace && origin.workspace !== Model.MINIMIZED_WORKSPACE ? String(origin.workspace) : ""
    if (!target) {
      var focused = Hyprland.focusedMonitor
      target = focused && focused.activeWorkspace ? String(focused.activeWorkspace.name) : "1"
    }
    actions.dispatch(Model.dispatch.moveToWorkspace(address, target, true))
    actions.dispatch(Model.dispatch.focusWindow(address))
    actions.writeState(Model.stateWithout(actions.minState, address))
    historyFile.setText(Model.historyWithout(actions.historyText(), address))
  }

  function close(t) {
    if (!t) return
    if (t.wayland) t.wayland.close()
    if (actions.isMinimized(t)) actions.writeState(Model.stateWithout(actions.minState, actions.addressOf(t)))
  }

  function toggleFloating(t) { if (t) actions.dispatch(Model.dispatch.toggleFloating(t.address)) }
  function togglePin(t) { if (t) actions.dispatch(Model.dispatch.togglePin(t.address)) }
  function toggleFullscreen(t) { if (t) actions.dispatch(Model.dispatch.toggleFullscreen(t.address)) }
  function moveToWorkspace(t, name) { if (t) actions.dispatch(Model.dispatch.moveToWorkspace(t.address, name, false)) }
  function moveToNextMonitor(t) { if (t) actions.dispatch(Model.dispatch.moveToMonitor(t.address, "+1")) }
  function focusWorkspace(name) { actions.dispatch(Model.dispatch.focusWorkspace(name)) }

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
      for (var i = 0; i < all.length; i++) live[actions.addressOf(all[i])] = true
      var next = actions.minState
      var changed = false
      for (var addr in actions.minState) if (!live[addr]) { next = Model.stateWithout(next, addr); changed = true }
      if (changed) actions.writeState(next)
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
    var entry = actions.desktopEntryFor(appId)
    return actions.iconSource(entry && entry.icon ? entry.icon : appId)
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
      if (Model.appMatches(actions.appIdOf(items[i].toplevel), desktopId, startupClass)) {
        actions.activate(items[i].toplevel)
        return
      }
    }
    actions.launch(desktopId)
  }
}
