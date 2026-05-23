-------------------
--- KEYBINDINGS ---
-------------------
-- See https://wiki.hypr.land/Configuring/Basics/Binds/

local mainMod     = "SUPER" -- Sets "Windows" key as main modifier
local terminal    = "kitty"
local fileManager = "nautilus"

-- ── Applications ────────────────────────────────────────────────────────
hl.bind(mainMod .. " + T",            hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",            hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SPACE",        hl.dsp.exec_cmd("qs ipc -c desktop call spotlight toggle"))
hl.bind("ALT + SPACE",                hl.dsp.exec_cmd("qs ipc -c desktop call launchpad toggle"))
hl.bind(mainMod .. " + B",            hl.dsp.exec_cmd("qs ipc -c desktop call bar toggle"))
--hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.exec_cmd("/usr/bin/smile"))

-- ── System ──────────────────────────────────────────────────────────────
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("hyprctl activewindow -j | jq '.pid' | xargs kill -9"))
hl.bind(mainMod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind("XF86PowerOff",            hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + P",         hl.dsp.window.float({ action = "toggle" }))

-- ── App Switcher (macOS Cmd+Tab style) ──────────────────────────────────
hl.bind(mainMod .. " + TAB",         hl.dsp.global("switcher:next"))
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.global("switcher:prev"))

-- ── Screenshots ─────────────────────────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.exec_cmd("~/.config/hypr/scripts/shot.sh output"))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.exec_cmd("~/.config/hypr/scripts/shot.sh region"))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.exec_cmd("~/.config/hypr/scripts/winshot.sh"))
hl.bind("Print", hl.dsp.exec_cmd('grim - | wl-copy && qs ipc -c desktop call osd custom "󰹑" "Screenshot copied to clipboard"'), { locked = true })

-- ── Special Workspace (Magic) ───────────────────────────────────────────
hl.bind(mainMod .. " + M",         hl.dsp.window.move({ workspace = "special:magic", follow = false }))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.workspace.toggle_special("magic"))

-- ── Focus / Movement ────────────────────────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + ALT + left",  hl.dsp.workspace.move({ monitor = "+1" }))
hl.bind(mainMod .. " + ALT + right", hl.dsp.workspace.move({ monitor = "-1" }))
hl.bind(mainMod .. " + ALT + up",    hl.dsp.workspace.move({ monitor = "+1" }))
hl.bind(mainMod .. " + ALT + down",  hl.dsp.workspace.move({ monitor = "-1" }))

-- ── Workspaces ──────────────────────────────────────────────────────────
-- mainMod + [1-9,0]        -> switch to workspace
-- mainMod + CTRL + [1-9,0] -> move active window to workspace
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,            hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + CTRL + " .. key,     hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + page_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + page_down", hl.dsp.focus({ workspace = "e+1" }))

-- ── Move / resize windows ───────────────────────────────────────────────
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 50,  y = 0,   relative = true }))
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -50, y = 0,   relative = true }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -50, relative = true }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 50,  relative = true }))
hl.bind("SUPER + SHIFT + 0",           hl.dsp.layout("splitratio 1.0 exact"))

hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.swap({ direction = "down" }))

-- ── Media & Brightness ──────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume",         hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-osd.sh 5%+"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-osd.sh 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",         hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-osd.sh 5%-"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-osd.sh 2%-"), { locked = true, repeating = true })

hl.bind("XF86AudioMute",    hl.dsp.exec_cmd("~/.config/hypr/scripts/speaker_mute.sh"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/mic_mute.sh"),     { locked = true, repeating = true })

hl.bind("XF86MonBrightnessUp",         hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-osd.sh raise"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-osd.sh +2"),    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",         hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-osd.sh lower"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-osd.sh -2"),    { locked = true, repeating = true })

hl.bind("F23",            hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh next"),       { locked = true })
hl.bind("XF86Favorites",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh play-pause"), { locked = true })
hl.bind("XF86Launch7",    hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh prev"),       { locked = true })

-- ── Keyboard Lock ───────────────────────────────────────────────────────
hl.bind("XF86Display", hl.dsp.exec_cmd("~/.config/hypr/scripts/keyboard-lock.sh"), { locked = true })

-- ── Night Shift — Hyprsunset toggle ─────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + XF86MonBrightnessUp",   hl.dsp.exec_cmd('hyprctl hyprsunset temperature 4500 && qs ipc -c desktop call osd custom "󰃟" "Blue Light Filter ON"'),  { locked = true })
hl.bind(mainMod .. " + SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd('hyprctl hyprsunset identity && qs ipc -c desktop call osd custom "󰃠" "Blue Light Filter OFF"'),         { locked = true })

-- ── Lid Switch (MacBook clamshell behavior) ─────────────────────────────
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/scripts/lid.sh close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/lid.sh open"),  { locked = true })
