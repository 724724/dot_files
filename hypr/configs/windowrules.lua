------------------------------
--- WINDOWS AND WORKSPACES ---
------------------------------
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Rules are evaluated top to bottom — order matters.

-- Position a floating window relative to the cursor but keep it fully on-screen.
-- NOTE: the Lua `move` field only accepts math expressions — the hyprlang
-- `move onscreen cursor 50% 50%` keyword syntax does NOT work here and silently
-- falls back to monitor-centering. So we clamp by hand: move expressions are in
-- monitor-local coords, and only min()/max() (not clamp()) are supported, with
-- vars cursor_x/y, window_w/h, monitor_w/h. dx/dy are the cursor offset strings.
local function cursor_on_screen(dx, dy)
    return {
        "max(0, min(cursor_x" .. dx .. ", monitor_w-window_w))",
        "max(0, min(cursor_y" .. dy .. ", monitor_h-window_h))",
    }
end

-- Same clamp for windows that ALSO get an explicit `size` rule. window_w/h in
-- move expressions substitute the client's *initial* surface size — the size
-- rule hasn't taken effect yet — so the right/bottom clamp is computed against
-- the wrong size and the resized window overflows those edges (left/top are
-- size-independent, which is why only right/bottom escaped). Bake the ruled
-- size in as literals instead. fx/fy = cursor offset as a fraction of w/h
-- (-0.5/-0.5 centers, matching cursor_on_screen's dx/dy convention).
local function cursor_on_screen_sized(w, h, fx, fy)
    local function off(d)
        d = math.floor(d + 0.5)
        return (d >= 0 and "+" or "") .. d
    end
    return {
        "max(0, min(cursor_x" .. off(w * fx) .. ", monitor_w-" .. w .. "))",
        "max(0, min(cursor_y" .. off(h * fy) .. ", monitor_h-" .. h .. "))",
    }
end

-- -----------------------------------------------------
-- Opacity Rules
-- -----------------------------------------------------
hl.window_rule({ match = { title = ".*(YouTube|HBO|Prime Video|Netflix|Disney|Twitch|Kick).*" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(google-chrome)$" },      opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(firefox)$" },            opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(org.gnome.Showtime)$" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(virt-manager)$" },       opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" },    opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(resolve)$" },            opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(Notion)$" },             opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(mpv)$" },                opacity = "1.0 override" })

-- -----------------------------------------------------
-- Floating & PIP
-- -----------------------------------------------------

-- Floating mode on all windows
hl.window_rule({ 
    match = { class = ".*" }, 
    float = true,
    move = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)")
})

-- Notion Command Search (Spotlight style)
hl.window_rule({ match = { title = "^(Notion - Command Search)$" }, float = true })
hl.window_rule({
    match = { title = "^(Notion - Command Search)$" },
    move  = cursor_on_screen("-(window_w*0.95)", "+(window_h*0.05)"),
})

-- Picture-in-Picture
hl.window_rule({
    match              = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float              = true,
    pin                = true,
    keep_aspect_ratio  = true,
    opacity            = "1.0 override",
})

-- Sticky Notes
hl.window_rule({ match = { class = "^(com.vixalien.sticky)$" }, float = true, size = { 400, 300 }, move = cursor_on_screen_sized(400, 300, -0.5, -0.5) })

-- Spotify Premium
hl.window_rule({ match = { class = "^(Spotify)$" }, float = true, size = { 1000, 600 } })
-- Cider (Apple Music)
hl.window_rule({ match = { class = "^(Cider)$", title = "^(Cider)$" }, float = true, size = { 1000, 600 }, move = cursor_on_screen_sized(1000, 600, -0.5, -0.5) })
-- Loupe
hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" }, float = true })
-- Nautilus
hl.window_rule({ match = { class = "^(org.gnome.NautilusPreviewer)$" }, float = true })

-- Center on cursor
hl.window_rule({
    match = { class = "^(spotify)$", title = "^(Spotify Premium)$" },
    move  = cursor_on_screen_sized(1000, 600, -0.5, -0.5),
})

-- -----------------------------------------------------
-- Dialogs & Popups (Center on Cursor)
-- -----------------------------------------------------
hl.window_rule({ match = { class = "^(org.gnome.clocks)$",   title = "^(Clocks)$" },           float = true })
hl.window_rule({ match = { class = "^(blueman-manager)$",    title = "^(Bluetooth Devices)$" }, float = true })

hl.window_rule({ match = { class = "org.gnome.Nautilus" }, float = true, size = { 1000, 600 } })
hl.window_rule({
    match = { class = "^(org.gnome.Nautilus)$" },
    move  = cursor_on_screen_sized(1000, 600, -0.5, -0.5),
})

hl.window_rule({ match = { class = "^(org.gnome.Calculator)$", title = "^(Calculator)$" }, float = true })
hl.window_rule({
    match = { class = "^(org.gnome.Calculator)$", title = "^(Calculator)$" },
    move  = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)"),
})

hl.window_rule({ match = { title = "^(Open Folder)$" },              float = true })
hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk)$" },   float = true })

hl.window_rule({ match = { class = "^(org.gnome.SystemMonitor)$", title = "^(System Monitor)$" }, float = true })
hl.window_rule({
    match = { class = "^(org.gnome.SystemMonitor)$", title = "^(System Monitor)$" },
    move  = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)"),
})

hl.window_rule({ match = { class = "^(me.kavishdevar.librepods)$", title = "^(LibrePods)$" }, float = true })
hl.window_rule({
    match = { class = "^(me.kavishdevar.librepods)$", title = "^(LibrePods)$" },
    move  = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)"),
})

hl.window_rule({ match = { class = "^(anki)$" },      float = true })
hl.window_rule({ match = { class = "^(GStreamer)$" }, float = true })

hl.window_rule({ match = { class = "^(org.gnome.Solanum)$" }, float = true })
hl.window_rule({
    match = { class = "^(org.gnome.Solanum)$" },
    move  = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)"),
})

hl.window_rule({ match = { class = "^(vesktop)$" }, float = true })
hl.window_rule({
    match = { class = "^(vesktop)$" },
    move  = cursor_on_screen("-(window_w*0.5)", "-(window_h*0.5)"),
})

hl.window_rule({ match = { class = "^(it.mijorus.smile)$" }, float = true, size = { 320, 400 } })
hl.window_rule({
    match = { class = "^(it.mijorus.smile)$" },
    move  = cursor_on_screen_sized(320, 400, 0, -1),
})

hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true, size = { 800, 700 } })
hl.window_rule({
    match = { class = "^(org.pulseaudio.pavucontrol)$" },
    move  = cursor_on_screen_sized(800, 700, -1.15, 0.06),
})

hl.window_rule({
    match = { class = "^(explorer.exe)$" },
    float = true,
    move  = cursor_on_screen("-(window_w*1.15)", "+(window_h*0.06)"),
})

-- -----------------------------------------------------
-- Fixes & Hacks
-- -----------------------------------------------------

-- It Takes Two
hl.window_rule({ match = { class = "^()$", title = "^(It Takes Two)$" }, stay_focused = true })

-- xembedsniproxy 컨테이너 숨기기
hl.window_rule({
    match     = { class = "^(xembedsniproxy)$" },
    float     = true,
    no_focus  = true,
    no_shadow = true,
    no_blur   = true,
    opacity   = "0.0 override",
})

-- Ableton
hl.window_rule({ match = { title = "^(WineDesktop - Wine Desktop)$" }, fullscreen = true })

-- KakaoTalk
hl.window_rule({ match = { class = "^(kakaotalk.exe)$" }, float = true })
hl.window_rule({ match = { class = "^(kakaotalk.exe)$", title = "^()$" }, stay_focused = true })
hl.window_rule({ match = { class = "^(kakaotalk.exe)$" }, opacity = "1.0 override" })
hl.window_rule({
    match             = { class = "^(kakaotalk.exe)$", title = "^(KakaoTalkShadowWnd)$" },
    opacity           = "0.0 override 0.0 override",
    no_shadow         = true,
    no_blur           = true,
    no_focus          = true,
    no_initial_focus  = true,
})
hl.window_rule({
    match             = { class = "^(kakaotalk.exe)$", title = "^(KakaoTalkEdgeWnd)$" },
    opacity           = "0.0 override 0.0 override",
    no_shadow         = true,
    no_blur           = true,
    no_focus          = true,
    no_initial_focus  = true,
})

-- "Winboat" / Office Apps
hl.window_rule({
    match          = { class = "^(Microsoft Word|Microsoft Excel|Microsoft PowerPoint|Photoshop|File Explorer)$" },
    suppress_event = "fullscreen maximize activate activatefocus",
})
hl.window_rule({
    match            = { class = "^(Microsoft Word|Microsoft Excel|Microsoft PowerPoint|Photoshop|File Explorer)$" },
    no_initial_focus = true,
    fullscreen       = true,
    no_anim          = true,
    rounding         = 0,
    border_size      = 0,
    no_shadow        = true,
    no_blur          = true,
    xray             = false,
    opaque           = true,
})

hl.window_rule({ match = { class = "^(wlfreerdp)$" }, opaque = true, xray = false })

-- -----------------------------------------------------
-- Layer Rules
-- -----------------------------------------------------
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true })
hl.layer_rule({ match = { namespace = "selection" },  no_anim = true })

-- Quickshell bar (dedicated "qs-bar" namespace, set in bar/Bar.qml). ignore_alpha
-- is below the pill background alpha (~0.25) so the translucent pills actually get
-- blurred; the fully transparent gaps between pills stay unblurred (click-through).
hl.layer_rule({ match = { namespace = "qs-bar" }, animation = "slide top", blur = true, ignore_alpha = 0.1 })

-- Quickshell dock — dedicated namespace so its panel can resize (preview open/close)
-- without retriggering the slide-top animation. Blur kept for the glass look.
hl.layer_rule({ match = { namespace = "qs-dock" }, no_anim = true, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "qs-dock-menu" }, no_anim = true, blur = true, ignore_alpha = 0.1 })

-- Quickshell OSD — separate namespace; QML handles its own fade animation.
hl.layer_rule({ match = { namespace = "qs-osd" }, no_anim = true, blur = true, ignore_alpha = 0.5 })

-- Quickshell Spotlight — fade animation via QML; blur for the macOS look.
hl.layer_rule({ match = { namespace = "qs-spotlight" }, blur = true, ignore_alpha = 0.5 })

-- Quickshell Launchpad — fullscreen overlay, fade via QML.
-- Lowered ignore_alpha so the very-translucent backdrop (~0.45) still triggers
-- the blur (Hyprland skips blur for pixels with alpha below the threshold).
hl.layer_rule({ match = { namespace = "qs-launchpad" }, no_anim = true, blur = true, ignore_alpha = 0.1 })

-- Quickshell Mission Control (macOS overview) — opaque wallpaper, no slide-in.
hl.layer_rule({ match = { namespace = "qs-missioncontrol" }, no_anim = true, blur = true, ignore_alpha = 0.1 })

-- Quickshell App Switcher (macOS Cmd+Tab style)
hl.layer_rule({ match = { namespace = "qs-switcher" }, no_anim = true, blur = true, ignore_alpha = 0.4 })
hl.layer_rule({ match = { namespace = "qs-emoji" }, no_anim = true, blur = true, ignore_alpha = 0.1 })

-- Quickshell Widgets board (macOS-style notes/clock/weather/reminders) —
-- fullscreen overlay, fade via QML. Low ignore_alpha so the ~0.5 dark veil
-- still blurs the workspace windows behind.
hl.layer_rule({ match = { namespace = "qs-widgets" }, no_anim = true, blur = true, ignore_alpha = 0.1 })

hl.layer_rule({ match = { namespace = "qs-cc" }, blur = true, ignore_alpha = 0.5 })

-- Clock + calendar popup that drops from the bar clock pill.
hl.layer_rule({ match = { namespace = "qs-clock" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "qs-shazam" }, blur = true, ignore_alpha = 0.1 })

-- Notification popups (transient toasts at top-right when CC closed)
hl.layer_rule({ match = { namespace = "qs-notif" }, blur = true, ignore_alpha = 0.5 })

-- nwg-dock
hl.layer_rule({ match = { namespace = "nwg-dock" }, blur = true, ignore_alpha = 0.5 })

-- Waydroid (Always Fullscreen)
hl.window_rule({ match = { class = "^(Waydroid.*)$" }, fullscreen = true })

hl.window_rule({ match = { class = "^(firefox)$" }, size = { 1600, 950 }, move = cursor_on_screen_sized(1600, 950, -0.5, -0.5) })
