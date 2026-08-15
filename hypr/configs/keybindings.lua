-------------------
--- KEYBINDINGS ---
-------------------
-- See https://wiki.hypr.land/Configuring/Basics/Binds/

local mainMod     = "SUPER" -- Sets "Windows" key as main modifier
local terminal    = "kitty"
local fileManager = "nautilus"
-- Focus guard: routes app launches through the Pomodoro focus check so blocked
-- apps can't be started by a keybinding either (see scripts/focus-guard.sh).
local guard       = "~/.config/quickshell/scripts/focus-guard.sh"

-- ── Applications ────────────────────────────────────────────────────────
hl.bind(mainMod .. " + T",            hl.dsp.exec_cmd(guard .. " " .. terminal))
hl.bind(mainMod .. " + E",            hl.dsp.exec_cmd(guard .. " " .. fileManager))
hl.bind(mainMod .. " + SPACE",        hl.dsp.global("spotlight:toggle"))
hl.bind("ALT + SPACE",                hl.dsp.global("launchpad:toggle"))
hl.bind("XF86Display",                hl.dsp.global("mc:toggle"))
hl.bind("XF86LaunchA",                hl.dsp.global("mc:toggle"))
hl.bind(mainMod .. " + B",            hl.dsp.global("bar:toggle"))
hl.bind(mainMod .. " + C",            hl.dsp.global("nc:toggle"))
hl.bind(mainMod .. " + V",            hl.dsp.global("dock:toggle"))
hl.bind(mainMod .. " + W",            hl.dsp.global("widgets:toggle"))
hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.global("emoji:toggle"))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd('hyprpicker -a | xargs -I {} notify-send "󰏘   Color Copied" "{}"'))

-- ── System ──────────────────────────────────────────────────────────────
-- Routed through the shell so it can branch: with the switcher open it quits the
-- highlighted app (macOS Cmd+Tab→Q), otherwise it closes the active window.
hl.bind(mainMod .. " + Q",         hl.dsp.global("switcher:close"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("hyprctl activewindow -j | jq '.pid' | xargs kill -9"))
hl.bind(mainMod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind("XF86PowerOff",            hl.dsp.exec_cmd("~/.config/quickshell/scripts/quickshell-lock.sh lock"))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + P",         hl.dsp.window.float({ action = "toggle" }))

-- ── App Switcher (macOS Cmd+Tab style) ──────────────────────────────────
hl.bind(mainMod .. " + TAB",         hl.dsp.global("switcher:next"))
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.global("switcher:prev"))
hl.bind("SUPER_L", hl.dsp.global("switcher:commit"), { release = true, non_consuming = true, ignore_mods = true })
hl.bind("SUPER_R", hl.dsp.global("switcher:commit"), { release = true, non_consuming = true, ignore_mods = true })

-- ── Screenshots ─────────────────────────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.global("capture:screen"))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.global("capture:portion"))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.global("capture:toggle"))
hl.bind("Print", hl.dsp.exec_cmd('grim - | wl-copy && qs ipc -c desktop call osd custom "󰹑" "Screenshot copied to clipboard"'), { locked = true })

-- ── Special Workspace (Magic) ───────────────────────────────────────────
hl.bind(mainMod .. " + M",         hl.dsp.window.move({ workspace = "special:magic", follow = false }))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.workspace.toggle_special("magic"))

-- ── Focus / Movement ────────────────────────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.global("switcher:left"))
hl.bind(mainMod .. " + right", hl.dsp.global("switcher:right"))
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

hl.bind("XF86LinkPhone",            hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh next"),       { locked = true })
hl.bind("XF86AudioNext",            hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh next"),       { locked = true })
hl.bind("XF86Favorites",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh play-pause"), { locked = true })
hl.bind("XF86SelectiveScreenshot",    hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh prev"),       { locked = true })
hl.bind("XF86AudioPrev",    hl.dsp.exec_cmd("~/.config/hypr/scripts/media-osd.sh prev"),       { locked = true })

-- ── Keyboard Lock ───────────────────────────────────────────────────────
hl.bind(mainMod .. " + XF86Display", hl.dsp.exec_cmd("~/.config/hypr/scripts/keyboard-lock.sh"), { locked = true })

-- ── Night Shift — Hyprsunset toggle ─────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + XF86MonBrightnessUp",   hl.dsp.exec_cmd('hyprctl hyprsunset temperature 4500 && printf on > "$XDG_RUNTIME_DIR/qs-nightshift" && qs ipc -c desktop call osd custom "󰃟" "Blue Light Filter ON"'),  { locked = true })
hl.bind(mainMod .. " + SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd('hyprctl hyprsunset identity && printf off > "$XDG_RUNTIME_DIR/qs-nightshift" && qs ipc -c desktop call osd custom "󰃠" "Blue Light Filter OFF"'),         { locked = true })

-- ── Apple-style Clamshell / Lid Switch ──────────────────────────────────
-- Lid, monitor hotplug, AC change, and resume events all converge on the
-- single state machine in scripts/clamshell.sh.
--   switch:on  = lid closed, switch:off = lid open
--   { locked = true } keeps the physical switch active while locked/DPMS-off.
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/scripts/clamshell.sh closed"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/clamshell.sh open"),   { locked = true })
