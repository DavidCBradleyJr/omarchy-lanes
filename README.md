# Omarchy Taskbar

A window taskbar for the [Omarchy](https://omarchy.org) shell. It runs as a native
Omarchy shell plugin (Quickshell), so it picks up your theme's colors, font,
corner rounding and bar sizing and restyles itself when you switch themes.

![Taskbar screenshot](docs/screenshot.png)

- One button per open window, with the app icon and title
- The focused window is highlighted with the theme accent. Urgent windows use the theme's alert color
- Optional pinned launchers: click to focus the running app, or launch it if it isn't open
- One bar per monitor. Show windows from the active workspace, the whole monitor, or everywhere
- Left-click focuses a window, middle-click closes it, and the scroll wheel cycles through them
- Settings live in `shell.json` and hot-reload when you save

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
    "showWorkspace": true,
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
| `showWorkspace` | bool | `true` | Workspace number on each button (when `scope` isn't `workspace`) |
| `maxButtonWidth` | number ≥ 40 | `220` | Longer titles are truncated |
| `transparent` | bool | `false` | No background behind the strip |
| `pinned` | desktop entry ids | `[]` | Launchers, e.g. `firefox`, `org.gnome.Nautilus` |

Windows on special (scratchpad) workspaces are only listed with `scope: "all"`.

## Show / hide

The taskbar can be toggled over shell IPC, so you can bind it to a key:

```bash
omarchy-shell shell call davidcbradleyjr.taskbar toggleVisible ""
```

For example, in `~/.config/hypr/bindings.lua`, bind that command with `o.bind`.

## Develop

```bash
git clone https://github.com/DavidCBradleyJr/omarchy-taskbar.git
ln -s "$PWD/omarchy-taskbar" ~/.config/omarchy/plugins/davidcbradleyjr.taskbar
omarchy-shell shell rescanPlugins
omarchy plugin enable davidcbradleyjr.taskbar
node tests/model.test.js   # unit tests for the pure logic in TaskbarModel.js
```

Saving plugin files reloads them automatically; with a symlinked checkout run
`omarchy-shell shell rescanPlugins` if a change doesn't show up. Shell logs:
`journalctl --user -f | grep omarchy-shell`.

| File | Role |
|---|---|
| `manifest.json` | Plugin manifest (`panel`, `keepLoaded`) |
| `Taskbar.qml` | Per-monitor layer-shell windows, settings, window list |
| `TaskButton.qml` | A single themed button |
| `TaskbarModel.js` | Pure logic: settings parsing, filtering, cycling, app matching |

## License

MIT
