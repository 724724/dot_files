-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- GDK Settings
hl.env("GDK_SCALE",                  "2")

-- Cursor
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- IME / Fcitx
hl.env("GTK_IM_MODULE",  "fcitx")
hl.env("QT_IM_MODULE",   "fcitx")
hl.env("XMODIFIERS",     "@im=fcitx")
hl.env("SDL_IM_MODULE",  "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- Wayland app compatibility
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
