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
  // One instance (the bottom bar's) runs the agent helper and posts
  // notifications; every instance reads the helper's snapshot.
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
    actions.syncAgentItems()
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
    if (!t || !actions.settings.agents) return ""
    return Model.agentState(t.title, actions.settings) || actions.agentStates[actions.addressOf(t)] || ""
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
  // Two sources, merged per window:
  //   titles  Claude Code puts ✳ / a spinner in its terminal title. Instant,
  //           no setup, but says nothing about model or task.
  //   helper  bin/lanes-agents reads the tails of Codex and Claude Code
  //           session logs every few seconds: state, model, task title,
  //           current step, and which window runs it. This is what sees the
  //           Codex app, whose window title never changes.

  readonly property string helperPath: String(Qt.resolvedUrl("bin/lanes-agents")).replace(/^file:\/\//, "")
  readonly property string snapshotPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-lanes/agents.json"
  property var sessions: []

  Process {
    id: helper
    command: ["python3", actions.helperPath]
    running: actions.notifyAgents && actions.settings.agents
    onExited: if (actions.notifyAgents && actions.settings.agents) helperRestart.restart()
  }

  // If the helper dies (a Python error, say), try again later rather than
  // spinning.
  Timer { id: helperRestart; interval: 30000; onTriggered: helper.running = actions.notifyAgents && actions.settings.agents }

  // The helper replaces the file atomically (write + rename), which a file
  // watch can't follow, and the file may not exist yet at startup. It's a
  // few hundred bytes, so just re-read it on the helper's own cadence.
  FileView {
    id: snapshotFile
    path: actions.snapshotPath
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        actions.sessions = Array.isArray(parsed.sessions) ? parsed.sessions : []
      } catch (e) {
        actions.sessions = []
      }
    }
    onLoadFailed: actions.sessions = []
  }

  Timer {
    interval: 2000
    repeat: true
    running: actions.settings.agents
    triggeredOnStart: true
    onTriggered: snapshotFile.reload()
  }

  // Title-derived state per window. Re-evaluates on every title change
  // (spinner frames included), so nothing heavy hangs off it directly.
  readonly property var titleStates: {
    var out = ({})
    if (!actions.settings.agents) return out
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var state = Model.agentState(all[i].title, actions.settings)
      if (state) out[actions.addressOf(all[i])] = state
    }
    return out
  }

  // One entry per agent: helper sessions first, then title-detected windows
  // the helper didn't account for (other agents, or no helper running).
  //   { key, state, app, title, model, activity, address, link }
  readonly property var rawAgentItems: {
    var items = []
    if (!actions.settings.agents) return items
    var covered = ({})
    for (var i = 0; i < actions.sessions.length; i++) {
      var s = actions.sessions[i]
      if (s.state !== "working" && s.state !== "waiting") continue
      var addr = Model.normalizeAddress(s.address)
      // For a terminal, the live title beats the helper's 3-second-old read.
      var state = s.agent === "claude" && actions.titleStates[addr] ? actions.titleStates[addr] : s.state
      items.push({ key: s.agent + ":" + s.id, state: state, app: s.app || s.agent, title: s.title || "",
        model: s.model || "", activity: s.activity || "", address: addr, link: s.link || "" })
      if (addr && s.agent !== "codex") covered[addr] = true
    }
    var all = Hyprland.toplevels.values
    for (var j = 0; j < all.length; j++) {
      var a = actions.addressOf(all[j])
      var ts = actions.titleStates[a]
      if (!ts || covered[a]) continue
      items.push({ key: "window:" + a, state: ts, app: actions.appIdOf(all[j]), title: Model.agentLabel(all[j].title),
        model: "", activity: "", address: a, link: "" })
    }
    return items
  }

  // Published only when something other than spinner frames changed.
  property var agentItems: []
  property string agentItemsKey: ""

  function syncAgentItems() {
    var key = JSON.stringify(actions.rawAgentItems)
    if (key === actions.agentItemsKey) return
    actions.agentItemsKey = key
    actions.agentItems = actions.rawAgentItems
  }

  onRawAgentItemsChanged: syncAgentItems()

  // Address -> "waiting" / "working" for badges and chips. Waiting wins: a
  // window with one agent waiting on you needs you, whatever else runs there.
  readonly property var agentStates: {
    var out = ({})
    for (var i = 0; i < actions.agentItems.length; i++) {
      var it = actions.agentItems[i]
      if (!it.address) continue
      if (it.state === "waiting" || !out[it.address]) out[it.address] = it.state
    }
    return out
  }

  readonly property var agentTotals: Model.agentCounts(actions.agentItems.map(function(it) { return it.state }))

  function agentItemsIn(state) {
    return actions.agentItems.filter(function(it) { return it.state === state })
  }

  property var previousAgentItems: ({})

  onAgentItemsChanged: {
    var current = ({})
    for (var i = 0; i < actions.agentItems.length; i++) current[actions.agentItems[i].key] = actions.agentItems[i].state
    var finished = Model.finishedAgents(actions.previousAgentItems, current)
    actions.previousAgentItems = current
    if (!actions.notifyAgents || !actions.settings.agentNotify) return
    for (var j = 0; j < finished.length; j++) {
      var item = actions.agentItems.filter(function(it) { return it.key === finished[j] })[0]
      if (!item) continue
      var t = actions.toplevelFor(item.address)
      // Looking at it already: no need to announce.
      if (t && actions.isActive(t)) continue
      var where = t && t.workspace ? "workspace " + Model.workspaceLabel(t.workspace.id) : ""
      Quickshell.execDetached(["notify-send", "-a", "Lanes", "-i", "dialog-information",
        "Agent waiting for you", item.title + "  ·  " + item.app + (where ? "  ·  " + where : "")])
    }
  }

  function toplevelFor(address) {
    var addr = Model.normalizeAddress(address)
    if (!addr) return null
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) if (actions.addressOf(all[i]) === addr) return all[i]
    return null
  }

  // Jump to an agent: open its deep link (the Codex app switches to that
  // thread), then focus or restore its window.
  function openAgent(item) {
    if (!item) return
    if (item.link) Quickshell.execDetached(["xdg-open", item.link])
    var t = actions.toplevelFor(item.address)
    if (t) actions.activate(t)
  }

  // Focus the next agent that's waiting for input, cycling through them.
  function focusNextWaiting() {
    var list = actions.agentItems
    var states = list.map(function(it) { return it.state })
    var current = -1
    for (var i = 0; i < list.length; i++) {
      var t = actions.toplevelFor(list[i].address)
      if (t && actions.isActive(t) && list[i].state === "waiting") { current = i; break }
    }
    var next = Model.nextWaitingIndex(states, current)
    if (next < 0) return false
    actions.openAgent(list[next])
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
