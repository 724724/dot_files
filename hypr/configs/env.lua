-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- NVIDIA
hl.env("LIBVA_DRIVER_NAME",         "iHD")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

hl.env("XDG_SESSION_TYPE",     "wayland")
hl.env("XDG_CURRENT_DESKTOP",  "Hyprland")
hl.env("XDG_SESSION_DESKTOP",  "Hyprland")

hl.env("GBM_BACKEND",                "nvidia-drm")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("NVD_BACKEND",                "direct")
hl.env("MOZ_DISABLE_RDD_SANDBOX",    "1")
hl.env("GDK_SCALE",                  "2")

-- Required so Qt's QGtk3Theme reads gsettings and picks up the user's GTK
-- icon theme (kora). Without this, QIcon::fromTheme falls back to `hicolor`
-- and many symbolic icons (system-search-symbolic, network-wired, etc.)
-- can't be found.
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("XCURSOR_SIZE",      "24")
hl.env("XCURSOR_THEME",     "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE",   "24")
hl.env("HYPRCURSOR_THEME",  "Bibata-Modern-Ice")

-- IME / Fcitx
hl.env("GTK_IM_MODULE",  "fcitx")
hl.env("QT_IM_MODULE",   "fcitx")
hl.env("XMODIFIERS",     "@im=fcitx")
hl.env("SDL_IM_MODULE",  "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
