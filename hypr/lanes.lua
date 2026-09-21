-- Lanes (Omarchy taskbar) keybindings.
--
-- Install: ln -s <repo>/hypr/lanes.lua ~/.config/hypr/lanes.lua
-- then add this line to ~/.config/hypr/hyprland.lua after require("hypr.bindings"):
--   pcall(require, "hypr.lanes")
--
-- Super+number already switches workspaces in Omarchy, so the taskbar uses
-- Ctrl+Alt. Keys are bound by keycode (code:10 = the 1 key) like Omarchy's
-- own workspace bindings, so they work on any keyboard layout.

local call = "omarchy-shell shell call davidcbradleyjr.lanes "

for n = 1, 10 do
  local digit = n % 10
  o.bind("CTRL + ALT + code:" .. tostring(n + 9), "Lanes window " .. (n == 10 and 10 or n),
    call .. "focusIndex " .. tostring(digit))
end

o.bind("CTRL + ALT + M", "Lanes window menu", call .. "menu ''")
o.bind("CTRL + ALT + B", "Toggle Lanes", call .. "toggleVisible ''")
