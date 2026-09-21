.pragma library

// Pure helpers for the taskbar. Nothing here touches QML objects, so the
// logic can be exercised with plain node (see tests/model.test.js).

var PLUGIN_ID = "davidcbradleyjr.lanes"

// Community minimize convention shared with AppDock and the window switcher
// plugins: minimized windows live on this special workspace, and each one's
// origin is recorded in $XDG_RUNTIME_DIR/hyprland-minimizer/state.json.
var MINIMIZED_WORKSPACE = "special:minimized"

var DEFAULTS = {
  // Screen edge to sit on: "bottom" or "top".
  position: "bottom",
  // Which windows each monitor's taskbar lists:
  //   "workspace" - windows on the monitor's active workspace
  //   "monitor"   - every window on this monitor, any workspace
  //   "all"       - every window everywhere
  scope: "workspace",
  // Show window titles next to icons. false gives an icon-only dock strip.
  showTitles: true,
  // Upper bound on a single button's width, before scaling.
  maxButtonWidth: 220,
  // In "monitor"/"all" scope, sort windows by workspace and put a clickable
  // workspace chip in front of each group.
  groupByWorkspace: true,
  // Clicking the already-focused window minimizes it.
  clickToMinimize: true,
  // Paint no background behind the strip.
  transparent: false,
  // Where the buttons sit along the bar: "left", "center" or "right".
  align: "left",
  // Desktop entry ids (e.g. "firefox", "org.gnome.Nautilus") shown as
  // launchers. Clicking one focuses a running window of that app, or
  // launches it.
  pinned: [],
  // Top-bar widget: "summary" (agent + minimized counts with a popup) or
  // "lanes" (the whole strip inline in the top bar).
  mode: "summary",
  // Bottom bar: "show" or "off". Defaults to "off" in lanes mode, since the
  // strip already lives in the top bar.
  bottomBar: null,
  // Slide the bottom bar away until the pointer reaches the screen edge.
  autoHide: false,
  // Agent badges from terminal titles (Claude Code sets "✳ …" when waiting
  // for input and a spinner while working).
  agents: true,
  // Desktop notification when an agent finishes and you aren't looking at it.
  agentNotify: true,
  // Optional regexes (as strings) matched against window titles, for agents
  // that mark their state differently.
  agentWorkingPattern: "",
  agentWaitingPattern: "",
  // Inline mode: space (px, before scaling) kept free on each side of the
  // top bar's center for the clock and friends.
  centerReserve: 260
}

// Leading glyphs Claude Code puts in the terminal title.
var WORKING_RE = /^[\u25D0-\u25D3\u2800-\u28FF]\s/   // ◐◑◒◓ and braille spinners
var WAITING_RE = /^\u2733\s/                           // ✳

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function oneOf(value, allowed, fallback) {
  return allowed.indexOf(value) !== -1 ? value : fallback
}

function boolOr(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

// Find this plugin's entry in a parsed shell.json. Enabling a plugin that
// ships a bar widget puts its entry in the bar layout; older installs (and
// panel-only setups) keep it in the top-level plugins[] array. Both the
// bottom bar and the top-bar widget read their settings from this one entry.
function findEntry(config, id) {
  if (!isPlainObject(config)) return null
  // Same order as the shell's own updateEntryInline: a bar layout entry wins,
  // so settings the shell writes are the ones we read back.
  var layout = isPlainObject(config.bar) && isPlainObject(config.bar.layout) ? config.bar.layout : null
  if (layout) {
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var j = 0; j < list.length; j++)
        if (isPlainObject(list[j]) && list[j].id === id) return list[j]
    }
  }
  if (Array.isArray(config.plugins)) {
    for (var i = 0; i < config.plugins.length; i++) {
      var entry = config.plugins[i]
      if (isPlainObject(entry) && entry.id === id) return entry
    }
  }
  return null
}

function stringOr(value, fallback) {
  return typeof value === "string" ? value : fallback
}

function normalizeSettings(entry) {
  var e = isPlainObject(entry) ? entry : {}
  var width = Number(e.maxButtonWidth)
  var pinned = Array.isArray(e.pinned)
    ? e.pinned.filter(function(p) { return typeof p === "string" && p.length > 0 })
    : DEFAULTS.pinned

  return {
    position: oneOf(e.position, ["bottom", "top"], DEFAULTS.position),
    scope: oneOf(e.scope, ["workspace", "monitor", "all"], DEFAULTS.scope),
    showTitles: boolOr(e.showTitles, DEFAULTS.showTitles),
    maxButtonWidth: isFinite(width) && width >= 40 ? Math.round(width) : DEFAULTS.maxButtonWidth,
    groupByWorkspace: boolOr(e.groupByWorkspace, DEFAULTS.groupByWorkspace),
    clickToMinimize: boolOr(e.clickToMinimize, DEFAULTS.clickToMinimize),
    transparent: boolOr(e.transparent, DEFAULTS.transparent),
    align: oneOf(e.align, ["left", "center", "right"], DEFAULTS.align),
    pinned: pinned,
    mode: oneOf(e.mode, ["summary", "lanes"], DEFAULTS.mode),
    bottomBar: oneOf(e.bottomBar, ["show", "off"], e.mode === "lanes" ? "off" : "show"),
    autoHide: boolOr(e.autoHide, DEFAULTS.autoHide),
    agents: boolOr(e.agents, DEFAULTS.agents),
    agentNotify: boolOr(e.agentNotify, DEFAULTS.agentNotify),
    agentWorkingPattern: stringOr(e.agentWorkingPattern, ""),
    agentWaitingPattern: stringOr(e.agentWaitingPattern, ""),
    centerReserve: isFinite(Number(e.centerReserve)) && Number(e.centerReserve) >= 0 ? Math.round(Number(e.centerReserve)) : DEFAULTS.centerReserve
  }
}

// The raw entry (all keys) so a settings change can be written back without
// dropping anything the user added by hand.
function entryFromText(text, id) {
  var parsed = null
  try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = null }
  var entry = findEntry(parsed, id || PLUGIN_ID)
  return entry ? JSON.parse(JSON.stringify(entry)) : null
}

function settingsFromText(text, id) {
  var parsed = null
  try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = null }
  return normalizeSettings(findEntry(parsed, id || PLUGIN_ID))
}

function isMinimized(win) {
  return !!win && win.workspaceName === MINIMIZED_WORKSPACE
}

// Decide whether a window belongs on a given monitor's taskbar.
//   win:  { workspaceId, workspaceName, monitorName, origin }
//         origin is the minimizer sidecar entry ({ workspace, monitor }) or null
//   view: { scope, monitorName, activeWorkspaceId, activeWorkspaceName }
// Minimized windows show where they came from, so a workspace-scoped taskbar
// only lists the ones minimized from that workspace. One with no recorded
// origin shows on its monitor's taskbar in every workspace, so it can't get
// lost. Other special (scratchpad) workspaces are only listed in "all" scope.
function windowVisible(win, view) {
  if (!win || !view) return false

  if (isMinimized(win)) {
    if (view.scope === "all") return true
    var origin = isPlainObject(win.origin) ? win.origin : null
    var monitor = origin && origin.monitor ? String(origin.monitor) : win.monitorName
    if (monitor !== view.monitorName) return false
    if (view.scope === "monitor") return true
    return !origin || !origin.workspace || String(origin.workspace) === String(view.activeWorkspaceName)
  }

  var wsId = Number(win.workspaceId)
  if (!isFinite(wsId)) return false

  if (view.scope === "all") return true
  if (wsId < 0) return false
  if (win.monitorName !== view.monitorName) return false
  if (view.scope === "monitor") return true
  return wsId === Number(view.activeWorkspaceId)
}

// Workspace a window is grouped under: its origin while minimized.
// Returns { key, label } where key sorts numerically and label is what the
// workspace chip shows.
var SPECIAL_KEY = 1000

function groupFor(win) {
  if (!win) return { key: SPECIAL_KEY + 1, label: "?" }
  if (isMinimized(win)) {
    var origin = isPlainObject(win.origin) ? win.origin : null
    var n = origin ? Number(origin.workspace) : NaN
    return isFinite(n) && n > 0 ? { key: n, label: workspaceLabel(n) } : { key: SPECIAL_KEY + 1, label: "–" }
  }
  var id = Number(win.workspaceId)
  if (!isFinite(id)) return { key: SPECIAL_KEY + 1, label: "?" }
  return id < 0 ? { key: SPECIAL_KEY, label: "S" } : { key: id, label: workspaceLabel(id) }
}

// Display order for windows given their group keys. Stable: windows in the
// same workspace keep Hyprland's creation order, so buttons never jump around
// when focus changes. Returns a permutation of indices.
function displayOrder(keys, grouped) {
  var idx = []
  for (var i = 0; i < keys.length; i++) idx.push(i)
  if (!grouped) return idx
  return idx.sort(function(a, b) { return (keys[a] - keys[b]) || (a - b) })
}

// For already-ordered keys: true where a new workspace group starts.
function groupStarts(orderedKeys) {
  var out = []
  for (var i = 0; i < orderedKeys.length; i++) out.push(i === 0 || orderedKeys[i] !== orderedKeys[i - 1])
  return out
}

// Index to focus when the wheel moves over the bar. Wraps at both ends.
// Returns -1 when there is nothing to cycle to.
function cycleIndex(count, current, delta) {
  if (count <= 0) return -1
  var step = delta < 0 ? 1 : -1
  if (current < 0 || current >= count) return step > 0 ? 0 : count - 1
  return (current + step + count) % count
}

// Ctrl+Alt+N → list index. N is 1-based and "0" means the tenth window.
function nthIndex(count, n) {
  var k = Number(n)
  if (!isFinite(k) || k < 0 || k > 10 || Math.floor(k) !== k) return -1
  var index = k === 0 ? 9 : k - 1
  return index < count ? index : -1
}

// Case-insensitive app matching between a desktop entry and a window's
// app id. Covers the common mismatches: reverse-DNS ids
// ("org.gnome.Nautilus" vs "nautilus") and StartupWMClass.
function appMatches(appId, entryId, startupClass) {
  var a = String(appId || "").toLowerCase()
  if (!a) return false
  var candidates = [entryId, startupClass]
  for (var i = 0; i < candidates.length; i++) {
    var c = String(candidates[i] || "").toLowerCase().replace(/\.desktop$/, "")
    if (!c) continue
    if (a === c) return true
    var tail = c.split(".").pop()
    if (tail && a === tail) return true
    var appTail = a.split(".").pop()
    if (appTail && appTail === tail) return true
  }
  return false
}

function workspaceLabel(id) {
  var n = Number(id)
  if (!isFinite(n)) return ""
  if (n < 0) return "S"
  return n === 10 ? "0" : String(n)
}

// ---- agents

function compilePattern(source) {
  if (!source) return null
  try { return new RegExp(source) } catch (e) { return null }
}

// "working", "waiting" or "" from a window title. Custom patterns win over
// the built-in Claude Code glyphs.
function agentState(title, settings) {
  var t = String(title || "")
  var s = settings || {}
  var working = compilePattern(s.agentWorkingPattern)
  var waiting = compilePattern(s.agentWaitingPattern)
  if (working && working.test(t)) return "working"
  if (waiting && waiting.test(t)) return "waiting"
  if (WORKING_RE.test(t)) return "working"
  if (WAITING_RE.test(t)) return "waiting"
  return ""
}

// Title without the leading status glyph, for when a badge shows the state.
function agentLabel(title) {
  var t = String(title || "")
  return WORKING_RE.test(t) || WAITING_RE.test(t) ? t.replace(/^\S+\s+/, "") : t
}

// Addresses whose agent went from working to waiting since the last look.
function finishedAgents(previous, current) {
  var out = []
  for (var addr in current)
    if (current[addr] === "waiting" && previous[addr] === "working") out.push(addr)
  return out
}

// Next waiting agent after `current` in list order, wrapping. -1 if none.
function nextWaitingIndex(states, current) {
  var n = states.length
  for (var step = 1; step <= n; step++) {
    var i = ((current < 0 ? -1 : current) + step + n) % n
    if (states[i] === "waiting") return i
  }
  return -1
}

function agentCounts(states) {
  var c = { working: 0, waiting: 0 }
  for (var i = 0; i < states.length; i++) if (c[states[i]] !== undefined) c[states[i]]++
  return c
}

// Hyprland addresses are "0x…" in hyprctl and the sidecar; Quickshell may
// hand them over without the prefix.
function normalizeAddress(address) {
  var s = String(address || "")
  if (!s) return ""
  return s.indexOf("0x") === 0 ? s : "0x" + s
}

// Lua dispatch expressions for Hyprland 0.56+. Addresses and workspace names
// are interpolated into a Lua string, so strip anything that could end it.
function luaString(value) {
  return "\"" + String(value).replace(/[\\"\n\r]/g, "") + "\""
}

function windowSelector(address) {
  return "window = " + luaString("address:" + normalizeAddress(address))
}

var dispatch = {
  focusWindow: function(address) { return "hl.dsp.focus({ " + windowSelector(address) + " })" },
  focusWorkspace: function(name) { return "hl.dsp.focus({ workspace = " + luaString(name) + " })" },
  moveToWorkspace: function(address, name, follow) {
    return "hl.dsp.window.move({ " + windowSelector(address) + ", workspace = " + luaString(name)
      + ", follow = " + (follow ? "true" : "false") + " })"
  },
  moveToMonitor: function(address, monitor) {
    return "hl.dsp.window.move({ " + windowSelector(address) + ", monitor = " + luaString(monitor) + " })"
  },
  toggleFloating: function(address) { return "hl.dsp.window.float({ action = \"toggle\", " + windowSelector(address) + " })" },
  togglePin: function(address) { return "hl.dsp.window.pin({ " + windowSelector(address) + " })" },
  toggleFullscreen: function(address) { return "hl.dsp.window.fullscreen({ mode = \"fullscreen\", " + windowSelector(address) + " })" }
}

// ---- minimizer sidecar (state.json + history.txt), shared with AppDock

function parseState(text) {
  try {
    var parsed = JSON.parse(text || "{}")
    return isPlainObject(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

function stateWith(state, address, entry) {
  var out = {}
  for (var k in state) out[k] = state[k]
  out[normalizeAddress(address)] = entry
  return out
}

function stateWithout(state, address) {
  var addr = normalizeAddress(address)
  var out = {}
  for (var k in state) if (k !== addr) out[k] = state[k]
  return out
}

// history.txt: one address per line, newest first.
function historyWith(text, address) {
  var addr = normalizeAddress(address)
  return [addr].concat(historyLines(text).filter(function(l) { return l !== addr })).join("\n") + "\n"
}

function historyWithout(text, address) {
  var addr = normalizeAddress(address)
  var lines = historyLines(text).filter(function(l) { return l !== addr })
  return lines.length ? lines.join("\n") + "\n" : ""
}

function historyLines(text) {
  return String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l.length > 0 })
}

// ---- strip registry
// .pragma library state is shared by every importer in the shell, so the
// bottom bar and the top-bar widget can find each other's strips (used by the
// keyboard "menu" command, which needs a button to anchor to).
var strips = []

function registerStrip(strip) { if (strips.indexOf(strip) === -1) strips.push(strip) }
function unregisterStrip(strip) {
  var i = strips.indexOf(strip)
  if (i !== -1) strips.splice(i, 1)
}
function stripList() { return strips.slice() }
