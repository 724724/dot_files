-----------------
--- AUTOSTART ---
-----------------
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- `hl.exec_cmd()` spawns an asynchronous process — no `& disown` needed.

-- Runs once, on Hyprland start (old `exec-once`).
hl.on("hyprland.start", function()
    -- Export env to systemd/D-Bus, then bring up graphical-session.target
    -- (xdg-desktop-portal & hyprpolkitagent require it -> screen capture/share).
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user start hyprland-session.target && systemctl --user start hyprpolkitagent")
    hl.exec_cmd("~/.config/hypr/scripts/brightness-restore.sh")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("fcitx5 -r")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh")
    hl.exec_cmd("~/.config/hypr/scripts/hide-unplugged-sinks.sh")
    hl.exec_cmd("wl-clip-persist --clipboard regular")
    hl.exec_cmd("xembedsniproxy")
    hl.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ 0")
    hl.exec_cmd("env QT_FONT_DPI=80 qs -c desktop")
    hl.exec_cmd("hyprsunset")

end)

hl.on("monitor.removed", function()
    hl.exec_cmd("~/.config/hypr/scripts/clamshell.sh monitor-removed")
end)
