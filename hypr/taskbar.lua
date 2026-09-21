-- Omarchy Taskbar keybindings.
--
-- Install: ln -s <repo>/hypr/taskbar.lua ~/.config/hypr/taskbar.lua
-- then add this line to ~/.config/hypr/hyprland.lua after require("hypr.bindings"):
--   pcall(require, "hypr.taskbar")
--
-- Super+number already switches workspaces in Omarchy, so the taskbar uses
-- Ctrl+Alt. Keys are bound by keycode (code:10 = the 1 key) like Omarchy's
-- own workspace bindings, so they work on any keyboard layout.

local call = "omarchy-shell shell call davidcbradleyjr.taskbar "

for n = 1, 10 do
  local digit = n % 10
  o.bind("CTRL + ALT + code:" .. tostring(n + 9), "Taskbar window " .. (n == 10 and 10 or n),
    call .. "focusIndex " .. tostring(digit))
end

o.bind("CTRL + ALT + M", "Taskbar window menu", call .. "menu ''")
o.bind("CTRL + ALT + B", "Toggle taskbar", call .. "toggleVisible ''")
