---------------------
--- LOOK AND FEEL ---
---------------------
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
    -- https://wiki.hypr.land/Configuring/Basics/Variables/#general
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 1,
        col = {
            active_border   = { colors = { "rgba(1e293bee)", "rgba(020617ee)" }, angle = 45 },
            inactive_border = "rgba(27272faa)",
        },
        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
    decoration = {
        rounding         = 7,
        rounding_power   = 3,
        active_opacity   = 1.0,
        inactive_opacity = 0.8,
        dim_special      = 0.7,

        shadow = {
            enabled      = true,
            range        = 5,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#blur
        blur = {
            enabled           = true,
            size              = 5,
            passes            = 5,
            new_optimizations = true,
            xray              = false,
            ignore_opacity    = true,
        },
    },

    -- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
    animations = {
        enabled = true,
    },

    -- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
    -- Note: the old `dwindle:pseudotile` master switch no longer exists.
    -- Pseudotiling is now per-window — use the `pseudo` window rule or the
    -- `hl.dsp.window.pseudo()` dispatcher on a keybind.
    dwindle = {
        preserve_split = true, -- You probably want this
    },

    -- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
    master = {
        new_status = "master",
    },

    -- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
    scrolling = {
        fullscreen_on_one_column = true,
        column_width             = 0.9,
        direction                = "right",
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#misc
    misc = {
        force_default_wallpaper = -1,   -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
    },
})

----------------
--- CURVES   ---
----------------
hl.curve("overshot",  { type = "bezier", points = { { 0.05, 0.9 }, { 0.1,  1.05 } } })
hl.curve("smoothOut", { type = "bezier", points = { { 0.36, 0   }, { 0.66, -0.56 } } })
hl.curve("smoothIn",  { type = "bezier", points = { { 0.25, 1   }, { 0.5,  1 } } })
-- Non-overshooting ease-out for layer surfaces — prevents the small
-- upward bounce that the default curve introduced when the NC / dock
-- preview / spotlight result list grew in size.
hl.curve("layerEase", { type = "bezier", points = { { 0.25, 0.46 }, { 0.45, 0.94 } } })

----------------
--- ANIMATIONS ---
----------------
hl.animation({ leaf = "windows",          enabled = true, speed = 3, bezier = "overshot",  style = "slide" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 3, bezier = "smoothOut", style = "slide" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "border",           enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "fade",             enabled = true, speed = 3, bezier = "smoothIn" })
hl.animation({ leaf = "fadeDim",          enabled = true, speed = 3, bezier = "smoothIn" })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 3, bezier = "default" })
hl.animation({ leaf = "layers",           enabled = true, speed = 2, bezier = "layerEase", style = "fade" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "default",   style = "slidevert 50%" })
