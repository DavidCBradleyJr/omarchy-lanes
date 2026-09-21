// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// TaskbarModel.js is a QML JS library (".pragma library"); strip the pragma
// and evaluate it as a plain script.
const src = fs.readFileSync(path.join(__dirname, "..", "TaskbarModel.js"), "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { PLUGIN_ID, DEFAULTS, findEntry, normalizeSettings, settingsFromText, windowVisible, cycleIndex, appMatches, workspaceLabel }")()

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

console.log(`\n${passed} tests passed`)
