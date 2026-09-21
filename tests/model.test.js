// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// TaskbarModel.js is a QML JS library (".pragma library"); strip the pragma
// and evaluate it as a plain script.
const src = fs.readFileSync(path.join(__dirname, "..", "TaskbarModel.js"), "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { PLUGIN_ID, MINIMIZED_WORKSPACE, DEFAULTS, findEntry, normalizeSettings, settingsFromText, windowVisible, groupFor, displayOrder, groupStarts, cycleIndex, nthIndex, appMatches, workspaceLabel, normalizeAddress, dispatch, parseState, stateWith, stateWithout, historyWith, historyWithout }")()

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

console.log(`\n${passed} tests passed`)
