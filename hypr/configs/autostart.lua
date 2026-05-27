-----------------
--- AUTOSTART ---
-----------------
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- `hl.exec_cmd()` spawns an asynchronous process — no `& disown` needed.

-- Runs once, on Hyprland start (old `exec-once`).
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/scripts/brightness-restore.sh")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("fcitx5")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh")
    hl.exec_cmd("~/.config/hypr/scripts/hide-unplugged-sinks.sh")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("xembedsniproxy")
    hl.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ 0")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("env QT_FONT_DPI=80 qs -c desktop")
    hl.exec_cmd("hyprsunset")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")

end)

-- Runs on every config (re)load — this file is re-executed each reload,
-- which mirrors the old `exec` keyword.
--hl.exec_cmd("~/.config/hypr/scripts/lid.sh init")
