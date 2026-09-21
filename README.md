# Omarchy Taskbar

A window taskbar for the [Omarchy](https://omarchy.org) shell. It runs as a native
Omarchy shell plugin (Quickshell), so it picks up your theme's colors, font,
corner rounding and bar sizing and restyles itself when you switch themes.

![Taskbar screenshot](docs/screenshot.png)

- **Built around workspaces.** In `monitor` or `all` scope, windows are grouped
  by workspace behind a clickable workspace chip, and the current workspace is highlighted
- **Minimize, compatible with other plugins.** Click the focused window to minimize it; it stays on the taskbar,
  dimmed, until you click it again. Uses the community `special:minimized`
  convention, so it interoperates with AppDock and minimize-aware Alt-Tab switchers
- **Right-click menu:** minimize, floating, pin, fullscreen, move to
  workspace 1–0, move to the next monitor, close
- **Keyboard:** Ctrl+Alt+1…0 acts on the Nth window, Ctrl+Alt+M opens its menu
- App icons and titles, with the focused window underlined in the theme accent
- Optional pinned launchers: focus the running app, or launch it
- Middle-click closes a window, and the scroll wheel cycles focus through the windows
- One bar per monitor. Settings live in `shell.json` and hot-reload when you save

## Install

Requires an Omarchy release with the Quickshell-based `omarchy-shell` (tested on Omarchy 4.0.4, Quickshell 0.3.1, Hyprland 0.56).

```bash
omarchy plugin add https://github.com/DavidCBradleyJr/omarchy-taskbar.git --enable
```

Update with `omarchy plugin update davidcbradleyjr.taskbar`. Remove with
`omarchy plugin remove davidcbradleyjr.taskbar`.

## Configure

Settings are inline on the plugin's entry in `~/.config/omarchy/shell.json`.
Every key is optional:

```json
"plugins": [
  {
    "id": "davidcbradleyjr.taskbar",
    "position": "bottom",
    "scope": "workspace",
    "align": "left",
    "showTitles": true,
    "groupByWorkspace": true,
    "clickToMinimize": true,
    "maxButtonWidth": 220,
    "transparent": false,
    "pinned": ["chromium", "org.gnome.Nautilus"]
  }
]
```

| Key | Values | Default | |
|---|---|---|---|
| `position` | `bottom`, `top` | `bottom` | Screen edge. If you choose `top`, move the Omarchy bar to the bottom |
| `scope` | `workspace`, `monitor`, `all` | `workspace` | Which windows each monitor's taskbar lists |
| `align` | `left`, `center`, `right` | `left` | Where the buttons sit |
| `showTitles` | bool | `true` | Set to `false` for an icon-only dock strip |
| `groupByWorkspace` | bool | `true` | Sort by workspace with a chip per group (when `scope` isn't `workspace`) |
| `clickToMinimize` | bool | `true` | Clicking the focused window minimizes it |
| `maxButtonWidth` | number ≥ 40 | `220` | Longer titles are truncated |
| `transparent` | bool | `false` | No background behind the strip |
| `pinned` | desktop entry ids | `[]` | Launchers, e.g. `firefox`, `org.gnome.Nautilus` |

Windows on special (scratchpad) workspaces are only listed with `scope: "all"`.
Minimized windows show on the taskbar of the workspace they were minimized from.

## Mouse and keyboard

| | |
|---|---|
| Left-click | Focus the window. If it's already focused, minimize it. If it's minimized, restore it |
| Middle-click | Close the window |
| Right-click | Window menu |
| Scroll wheel | Cycle focus through the listed windows |
| Click a workspace chip | Switch to that workspace |
| Ctrl+Alt+1 … 9, 0 | Same as left-clicking the Nth window on the focused monitor |
| Ctrl+Alt+M | Window menu for the focused window (Esc closes it) |
| Ctrl+Alt+B | Show / hide the taskbar |

Omarchy already uses Super+number for workspaces, so the taskbar uses Ctrl+Alt.
The bindings are in [`hypr/taskbar.lua`](hypr/taskbar.lua):

```bash
ln -s ~/.config/omarchy/plugins/davidcbradleyjr.taskbar/hypr/taskbar.lua ~/.config/hypr/taskbar.lua
# then in ~/.config/hypr/hyprland.lua, after require("hypr.bindings"):
#   pcall(require, "hypr.taskbar")
```

Keyboard layouts where AltGr acts as Ctrl+Alt (German, Polish, …) use AltGr+digits for
characters. On those, edit the modifier in `taskbar.lua`.

## Minimize convention

Minimized windows are moved to `special:minimized`, and their origin is recorded in
`$XDG_RUNTIME_DIR/hyprland-minimizer/state.json` (plus a newest-first
`history.txt`). This is the same format [AppDock](https://github.com/gdeyoung/omarchy-appdock)
uses, so windows minimized by either tool can be restored by the other.

## IPC

```bash
omarchy-shell shell call davidcbradleyjr.taskbar focusIndex 3
omarchy-shell shell call davidcbradleyjr.taskbar menu ""
omarchy-shell shell call davidcbradleyjr.taskbar toggleVisible ""
```

## Develop

```bash
git clone https://github.com/DavidCBradleyJr/omarchy-taskbar.git
ln -s "$PWD/omarchy-taskbar" ~/.config/omarchy/plugins/davidcbradleyjr.taskbar
omarchy-shell shell rescanPlugins
omarchy plugin enable davidcbradleyjr.taskbar
node tests/model.test.js   # unit tests for the pure logic in TaskbarModel.js
```

After editing an already-loaded plugin, run `omarchy restart shell`. The shell's
hot-reload rescans plugins but doesn't clear Qt's component cache, so QML files that
were already loaded keep their old code. Shell logs:
`journalctl --user -f | grep omarchy-shell`.

| File | Role |
|---|---|
| `manifest.json` | Plugin manifest (`panel`, `keepLoaded`) |
| `Taskbar.qml` | Per-monitor layer-shell windows, settings, window list |
| `TaskButton.qml` | A single themed button |
| `WorkspaceChip.qml` | Workspace group label |
| `ContextMenu.qml` | Right-click menu (built on Omarchy's `PopupCard`) |
| `hypr/taskbar.lua` | Keybindings |
| `TaskbarModel.js` | Pure logic: settings, filtering, grouping, minimize records, dispatch strings |

## License

MIT
