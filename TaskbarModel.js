.pragma library

// Pure helpers for the taskbar. Nothing here touches QML objects, so the
// logic can be exercised with plain node (see tests/model.test.js).

var PLUGIN_ID = "davidcbradleyjr.taskbar"

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
  // Prefix buttons with their workspace number when scope isn't "workspace".
  showWorkspace: true,
  // Paint no background behind the strip.
  transparent: false,
  // Where the buttons sit along the bar: "left", "center" or "right".
  align: "left",
  // Desktop entry ids (e.g. "firefox", "org.gnome.Nautilus") shown as
  // launchers. Clicking one focuses a running window of that app, or
  // launches it.
  pinned: []
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function oneOf(value, allowed, fallback) {
  return allowed.indexOf(value) !== -1 ? value : fallback
}

// Find this plugin's entry in a parsed shell.json. Enabled third-party
// plugins live in the top-level plugins[] array with inline settings.
function findEntry(config, id) {
  if (!isPlainObject(config) || !Array.isArray(config.plugins)) return null
  for (var i = 0; i < config.plugins.length; i++) {
    var entry = config.plugins[i]
    if (isPlainObject(entry) && entry.id === id) return entry
  }
  return null
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
    showTitles: typeof e.showTitles === "boolean" ? e.showTitles : DEFAULTS.showTitles,
    maxButtonWidth: isFinite(width) && width >= 40 ? Math.round(width) : DEFAULTS.maxButtonWidth,
    showWorkspace: typeof e.showWorkspace === "boolean" ? e.showWorkspace : DEFAULTS.showWorkspace,
    transparent: typeof e.transparent === "boolean" ? e.transparent : DEFAULTS.transparent,
    align: oneOf(e.align, ["left", "center", "right"], DEFAULTS.align),
    pinned: pinned
  }
}

function settingsFromText(text, id) {
  var parsed = null
  try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = null }
  return normalizeSettings(findEntry(parsed, id || PLUGIN_ID))
}

// Decide whether a window belongs on a given monitor's taskbar.
//   win:  { workspaceId, monitorName }
//   view: { scope, monitorName, activeWorkspaceId }
// Special (scratchpad) workspaces have negative ids and are only listed in
// "all" scope, where the user asked to see everything.
function windowVisible(win, view) {
  if (!win || !view) return false
  var wsId = Number(win.workspaceId)
  if (!isFinite(wsId)) return false

  if (view.scope === "all") return true
  if (wsId < 0) return false
  if (win.monitorName !== view.monitorName) return false
  if (view.scope === "monitor") return true
  return wsId === Number(view.activeWorkspaceId)
}

// Index to focus when the wheel moves over the bar. Wraps at both ends.
// Returns -1 when there is nothing to cycle to.
function cycleIndex(count, current, delta) {
  if (count <= 0) return -1
  var step = delta < 0 ? 1 : -1
  if (current < 0 || current >= count) return step > 0 ? 0 : count - 1
  return (current + step + count) % count
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
