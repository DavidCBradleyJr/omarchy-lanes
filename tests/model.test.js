// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// TaskbarModel.js is a QML JS library (".pragma library"); strip the pragma
// and evaluate it as a plain script.
const src = fs.readFileSync(path.join(__dirname, "..", "TaskbarModel.js"), "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { PLUGIN_ID, MINIMIZED_WORKSPACE, DEFAULTS, findEntry, normalizeSettings, settingsFromText, windowVisible, groupFor, displayOrder, groupStarts, cycleIndex, nthIndex, appMatches, workspaceLabel, normalizeAddress, dispatch, parseState, stateWith, stateWithout, historyWith, historyWithout, entryFromText, agentState, agentLabel, finishedAgents, nextWaitingIndex, agentCounts }")()
const shadeSrc = fs.readFileSync(path.join(__dirname, "..", "ShadeModel.js"), "utf8").replace(".pragma library", "")
const S = new Function(shadeSrc + "; return { TILE_SIZE, RADAR_MIN_ZOOM, RADAR_MAX_ZOOM, dateKey, monthGrid, stepMonth, clamp, formatDuration, weatherIcon, weatherLabel, radarFrames, mercatorPoint, radarTiles, radarMarker }")()

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok -", name) }

test("defaults when shell.json has no entry", () => {
  assert.deepStrictEqual(M.settingsFromText('{"version":1,"plugins":[]}'), M.normalizeSettings(null))
  assert.strictEqual(M.settingsFromText("not json").position, "bottom")
})

test("reads inline settings from plugins[]", () => {
  const s = M.settingsFromText(JSON.stringify({ version: 1, plugins: [
    { id: "someone.else", position: "top" },
    { id: M.PLUGIN_ID, position: "top", scope: "all", showTitles: false, pinned: ["firefox", 3, ""] }
  ] }))
  assert.strictEqual(s.position, "top")
  assert.strictEqual(s.scope, "all")
  assert.strictEqual(s.showTitles, false)
  assert.deepStrictEqual(s.pinned, ["firefox"])
})

test("rejects bad values", () => {
  const s = M.normalizeSettings({ position: "left", scope: "galaxy", maxButtonWidth: 5, align: 1 })
  assert.strictEqual(s.position, "bottom")
  assert.strictEqual(s.scope, "workspace")
  assert.strictEqual(s.maxButtonWidth, 220)
  assert.strictEqual(s.align, "left")
})

test("window scope filtering", () => {
  const view = (scope) => ({ scope, monitorName: "DP-1", activeWorkspaceId: 2 })
  const here = { workspaceId: 2, monitorName: "DP-1" }
  const otherWs = { workspaceId: 3, monitorName: "DP-1" }
  const otherMon = { workspaceId: 5, monitorName: "HDMI-A-1" }
  const special = { workspaceId: -98, monitorName: "DP-1" }

  assert.ok(M.windowVisible(here, view("workspace")))
  assert.ok(!M.windowVisible(otherWs, view("workspace")))
  assert.ok(M.windowVisible(otherWs, view("monitor")))
  assert.ok(!M.windowVisible(otherMon, view("monitor")))
  assert.ok(M.windowVisible(otherMon, view("all")))
  assert.ok(!M.windowVisible(special, view("monitor")))
  assert.ok(M.windowVisible(special, view("all")))
  assert.ok(!M.windowVisible({ workspaceId: NaN, monitorName: "DP-1" }, view("all")))
})

test("wheel cycling wraps", () => {
  assert.strictEqual(M.cycleIndex(0, -1, -120), -1)
  assert.strictEqual(M.cycleIndex(3, 2, -120), 0)
  assert.strictEqual(M.cycleIndex(3, 0, 120), 2)
  assert.strictEqual(M.cycleIndex(3, -1, 120), 2)
})

test("app matching", () => {
  assert.ok(M.appMatches("firefox", "firefox"))
  assert.ok(M.appMatches("org.gnome.Nautilus", "org.gnome.Nautilus.desktop"))
  assert.ok(M.appMatches("nautilus", "org.gnome.Nautilus"))
  assert.ok(M.appMatches("Alacritty", "", "alacritty"))
  assert.ok(!M.appMatches("firefox", "chromium"))
  assert.ok(!M.appMatches("", "firefox"))
})

test("workspace labels", () => {
  assert.strictEqual(M.workspaceLabel(1), "1")
  assert.strictEqual(M.workspaceLabel(10), "0")
  assert.strictEqual(M.workspaceLabel(-98), "S")
})

test("minimized windows show where they came from", () => {
  const min = (origin, monitorName = "DP-1") => ({ workspaceId: -99, workspaceName: M.MINIMIZED_WORKSPACE, monitorName, origin })
  const view = (scope, ws = "2") => ({ scope, monitorName: "DP-1", activeWorkspaceId: Number(ws), activeWorkspaceName: ws })

  assert.ok(M.windowVisible(min({ workspace: "2", monitor: "DP-1" }), view("workspace")))
  assert.ok(!M.windowVisible(min({ workspace: "3", monitor: "DP-1" }), view("workspace")))
  assert.ok(M.windowVisible(min({ workspace: "3", monitor: "DP-1" }), view("monitor")))
  assert.ok(!M.windowVisible(min({ workspace: "3", monitor: "HDMI-A-1" }), view("monitor")))
  // origin monitor wins over the monitor the special workspace sits on
  assert.ok(M.windowVisible(min({ workspace: "2", monitor: "DP-1" }, "HDMI-A-1"), view("workspace")))
  // no sidecar entry: visible on its monitor in every workspace
  assert.ok(M.windowVisible(min(null), view("workspace", "7")))
  assert.ok(!M.windowVisible(min(null, "HDMI-A-1"), view("workspace")))
  assert.ok(M.windowVisible(min(null, "HDMI-A-1"), view("all")))
})

test("scratchpad windows remain accessible on their monitor", () => {
  const scratchpad = { workspaceId: -98, workspaceName: "special:scratchpad", monitorName: "DP-1", origin: null }
  const otherSpecial = { workspaceId: -97, workspaceName: "special:other", monitorName: "DP-1", origin: null }
  const view = (scope, monitorName = "DP-1") => ({ scope, monitorName, activeWorkspaceId: 2, activeWorkspaceName: "2" })
  assert.ok(M.windowVisible(scratchpad, view("workspace")))
  assert.ok(M.windowVisible(scratchpad, view("monitor")))
  assert.ok(!M.windowVisible(scratchpad, view("workspace", "HDMI-A-1")))
  assert.ok(M.windowVisible(scratchpad, view("all", "HDMI-A-1")))
  assert.ok(!M.windowVisible(otherSpecial, view("workspace")))
})

test("grouping by workspace", () => {
  assert.deepStrictEqual(M.groupFor({ workspaceId: 3, workspaceName: "3" }), { key: 3, label: "3" })
  assert.deepStrictEqual(M.groupFor({ workspaceId: 10, workspaceName: "10" }), { key: 10, label: "0" })
  assert.strictEqual(M.groupFor({ workspaceId: -98, workspaceName: "special:scratchpad" }).label, "S")
  assert.deepStrictEqual(M.groupFor({ workspaceId: -99, workspaceName: M.MINIMIZED_WORKSPACE, origin: { workspace: "4" } }), { key: 4, label: "4" })
  assert.strictEqual(M.groupFor({ workspaceId: -99, workspaceName: M.MINIMIZED_WORKSPACE, origin: null }).label, "–")

  const keys = [6, 1, 6, 2, 1, 1000]
  const order = M.displayOrder(keys, true)
  assert.deepStrictEqual(order, [1, 4, 3, 0, 2, 5]) // stable within a workspace
  assert.deepStrictEqual(M.displayOrder(keys, false), [0, 1, 2, 3, 4, 5])
  assert.deepStrictEqual(M.groupStarts(order.map(i => keys[i])), [true, false, true, true, false, true])
})

test("Ctrl+Alt+N index", () => {
  assert.strictEqual(M.nthIndex(3, 1), 0)
  assert.strictEqual(M.nthIndex(3, 3), 2)
  assert.strictEqual(M.nthIndex(3, 4), -1)
  assert.strictEqual(M.nthIndex(10, 0), 9)
  assert.strictEqual(M.nthIndex(10, "2"), 1)
  assert.strictEqual(M.nthIndex(10, "x"), -1)
  assert.strictEqual(M.nthIndex(10, 11), -1)
})

test("dispatch expressions", () => {
  assert.strictEqual(M.normalizeAddress("5b4f2f749480"), "0x5b4f2f749480")
  assert.strictEqual(M.normalizeAddress("0x5b4f"), "0x5b4f")
  assert.strictEqual(M.dispatch.focusWindow("abc"), 'hl.dsp.focus({ window = "address:0xabc" })')
  assert.strictEqual(M.dispatch.moveToWorkspace("0xabc", "special:minimized", false),
    'hl.dsp.window.move({ window = "address:0xabc", workspace = "special:minimized", follow = false })')
  assert.strictEqual(M.dispatch.toggleFloating("0x1"), 'hl.dsp.window.float({ action = "toggle", window = "address:0x1" })')
  // nothing can break out of the Lua string
  assert.strictEqual(M.dispatch.focusWorkspace('1" }) os.execute("x'), 'hl.dsp.focus({ workspace = "1 }) os.execute(x" })')
})

test("minimizer sidecar round trip", () => {
  let state = M.parseState("garbage")
  assert.deepStrictEqual(state, {})
  state = M.stateWith(state, "abc", { workspace: "2", monitor: "DP-1", thumb: "" })
  assert.deepStrictEqual(Object.keys(state), ["0xabc"])
  state = M.stateWith(state, "0xdef", { workspace: "3", monitor: "DP-1", thumb: "" })
  assert.deepStrictEqual(Object.keys(M.stateWithout(state, "abc")), ["0xdef"])

  let hist = M.historyWith("", "0xabc")
  hist = M.historyWith(hist, "0xdef")
  hist = M.historyWith(hist, "0xabc")
  assert.strictEqual(hist, "0xabc\n0xdef\n")
  assert.strictEqual(M.historyWithout(hist, "abc"), "0xdef\n")
  assert.strictEqual(M.historyWithout("0xabc\n", "0xabc"), "")
})

test("entry lives in plugins[] or the bar layout", () => {
  const inBar = JSON.stringify({ version: 1, plugins: [], bar: { layout: { left: [{ id: "omarchy.menu" }], center: [], right: [{ id: M.PLUGIN_ID, mode: "lanes" }] } } })
  assert.strictEqual(M.settingsFromText(inBar).mode, "lanes")
  assert.deepStrictEqual(M.entryFromText(inBar), { id: M.PLUGIN_ID, mode: "lanes" })
  // the bar layout entry wins when both exist, matching the shell's writes
  const both = JSON.stringify({ plugins: [{ id: M.PLUGIN_ID, scope: "all" }], bar: { layout: { right: [{ id: M.PLUGIN_ID, scope: "monitor" }] } } })
  assert.strictEqual(M.settingsFromText(both).scope, "monitor")
  assert.strictEqual(M.entryFromText("{}"), null)
})

test("bottom bar and auto-hide settings", () => {
  const d = M.normalizeSettings(null)
  assert.strictEqual(d.mode, "summary")
  assert.strictEqual(d.bottomBar, "show")
  assert.strictEqual(d.autoHide, false)
  assert.strictEqual(M.normalizeSettings({ mode: "lanes" }).bottomBar, "off")
  assert.strictEqual(M.normalizeSettings({ mode: "lanes", bottomBar: "show" }).bottomBar, "show")
  assert.strictEqual(M.normalizeSettings({ bottomBar: "sometimes" }).bottomBar, "show")
  assert.strictEqual(M.normalizeSettings({ autoHide: true }).autoHide, true)
})

test("top shade settings", () => {
  const defaults = M.normalizeSettings(null)
  assert.strictEqual(defaults.shade, true)
  assert.strictEqual(defaults.shadeHeight, 480)
  assert.strictEqual(M.normalizeSettings({ shade: false, shadeHeight: 620 }).shade, false)
  assert.strictEqual(M.normalizeSettings({ shade: false, shadeHeight: 620 }).shadeHeight, 620)
  assert.strictEqual(M.normalizeSettings({ shadeHeight: 120 }).shadeHeight, 480)
  assert.strictEqual(M.normalizeSettings({ shadeHeight: 900 }).shadeHeight, 480)
})

test("shade calendar produces a fixed six-week grid", () => {
  const cells = S.monthGrid(2026, 8, 1, "2026-09-21")
  assert.strictEqual(cells.length, 42)
  assert.strictEqual(cells[0].key, "2026-08-31")
  assert.strictEqual(cells.filter(cell => cell.today).length, 1)
  assert.strictEqual(cells.find(cell => cell.today).day, 21)
  assert.deepStrictEqual(S.stepMonth(2026, 11, 1), { year: 2027, month: 0 })
})

test("shade media and radar helpers", () => {
  assert.strictEqual(S.RADAR_MIN_ZOOM, 4)
  assert.strictEqual(S.RADAR_MAX_ZOOM, 7)
  assert.strictEqual(S.formatDuration(0), "0:00")
  assert.strictEqual(S.formatDuration(367), "6:07")
  assert.strictEqual(S.weatherLabel(0), "Clear")
  assert.strictEqual(S.weatherLabel(95), "Thunderstorms")

  const tiles = S.radarTiles(40.7128, -74.006, 6, 4, 3)
  const marker = S.radarMarker(40.7128, -74.006, 6, 4, 3)
  assert.strictEqual(tiles.length, 12)
  assert.ok(marker.x >= 0 && marker.x <= 4 * S.TILE_SIZE)
  assert.ok(marker.y >= 0 && marker.y <= 3 * S.TILE_SIZE)
})

test("radar history is normalized, ordered, and limited", () => {
  const data = { radar: { past: [
    { time: 300, path: "/three" },
    { time: 100, path: "/one" },
    { time: 200, path: "/two" },
    { time: "bad", path: "/bad-time" },
    { time: 400 },
    null
  ] } }
  assert.deepStrictEqual(S.radarFrames(data, 2), [
    { time: 200, path: "/two" },
    { time: 300, path: "/three" }
  ])
  assert.deepStrictEqual(S.radarFrames(data, 20).map(frame => frame.time), [100, 200, 300])
  assert.deepStrictEqual(S.radarFrames(null, 10), [])
  assert.deepStrictEqual(S.radarFrames({ radar: { past: "invalid" } }, 10), [])
})

test("agent state from titles", () => {
  assert.strictEqual(M.agentState("✳ Local models on Omarchy", {}), "waiting")
  assert.strictEqual(M.agentState("◐ Omarchy taskbar customization", {}), "working")
  assert.strictEqual(M.agentState("⠙ codex", {}), "working")
  assert.strictEqual(M.agentState("deej@omarchy:~", {}), "")
  assert.strictEqual(M.agentState("✳nospace", {}), "")
  // custom patterns win
  assert.strictEqual(M.agentState("[busy] opencode", { agentWorkingPattern: "^\\[busy\\]" }), "working")
  assert.strictEqual(M.agentState("✳ x", { agentWorkingPattern: "^✳" }), "working")
  // a broken pattern is ignored, not fatal
  assert.strictEqual(M.agentState("✳ x", { agentWaitingPattern: "(" }), "waiting")
  assert.strictEqual(M.agentLabel("✳ Local models"), "Local models")
  assert.strictEqual(M.agentLabel("plain title"), "plain title")
})

test("agent transitions, cycling and counts", () => {
  assert.deepStrictEqual(M.finishedAgents({ a: "working", b: "waiting", c: "working" }, { a: "waiting", b: "waiting", c: "working", d: "waiting" }), ["a"])
  const states = ["", "waiting", "working", "waiting"]
  assert.strictEqual(M.nextWaitingIndex(states, -1), 1)
  assert.strictEqual(M.nextWaitingIndex(states, 1), 3)
  assert.strictEqual(M.nextWaitingIndex(states, 3), 1)
  assert.strictEqual(M.nextWaitingIndex(["", "working"], 0), -1)
  assert.deepStrictEqual(M.agentCounts(states), { working: 1, waiting: 2 })
})

console.log(`\n${passed} tests passed`)
