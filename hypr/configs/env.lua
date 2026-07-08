-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- Qt HiDPI 스케일링 설정
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_ENABLE_HIGHDPI_SCALING", "1")

-- GDK Settings
hl.env("GDK_SCALE",                  "2")

-- Qt theming — make QWidget platform menus (e.g. the quickshell tray
-- right-click DBusMenus) follow the GTK theme + gsettings color-scheme.
-- Without this Qt falls back to its default light palette, so the menus
-- render white even while GTK is in dark mode.
hl.env("QT_QPA_PLATFORMTHEME",       "gtk3")

-- Cursor
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")

-- IME / Fcitx
hl.env("GTK_IM_MODULE",  "fcitx")
hl.env("QT_IM_MODULE",   "fcitx")
hl.env("XMODIFIERS",     "@im=fcitx")
hl.env("SDL_IM_MODULE",  "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- Wayland app compatibility
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- XDG Specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
