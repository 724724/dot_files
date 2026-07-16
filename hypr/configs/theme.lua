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
        inactive_opacity = 0.7,
        dim_special      = 0.7,

        shadow = {
            enabled      = false,
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
        -- windowsMove animates compositor-driven geometry (including
        -- fullscreen/maximize), while direct manipulation remains 1:1.
        animate_manual_resizes      = false,
        animate_mouse_windowdragging = false,
    },
})

----------------
--- CURVES   ---
----------------
-- Match Quickshell's AppleSpring house style with real physical springs.
-- appleFluid is effectively critically damped (zeta ~= 0.99, response ~= .39s):
-- no decorative bounce, interruption starts from the current presentation.
-- appleSheet mirrors Apple's drawer/sheet recipe (zeta ~= .8, response ~= .37s)
-- and is reserved for spatial, momentum-like transitions.
hl.curve("appleFluid", {
    type = "spring", mass = 1, stiffness = 260, dampening = 32,
})
hl.curve("appleSheet", {
    type = "spring", mass = 1, stiffness = 280, dampening = 27,
})

----------------
--- ANIMATIONS ---
----------------
-- speed is in deciseconds: keep the 0.3–0.4s response used by AppleSpring.
-- Window drag/resize remains unanimated for true 1:1 direct manipulation.
hl.animation({ leaf = "windows",          enabled = true,  speed = 4, spring = "appleFluid", style = "popin 96%" })
hl.animation({ leaf = "windowsOut",       enabled = true,  speed = 4, spring = "appleFluid", style = "popin 96%" })
-- Fullscreen/maximize uses the same critically damped spring in both
-- directions. Hyprland retargets the running spring on rapid reversal.
hl.animation({ leaf = "windowsMove",      enabled = true,  speed = 4, spring = "appleFluid" })
hl.animation({ leaf = "border",           enabled = true,  speed = 2, spring = "appleFluid" })
hl.animation({ leaf = "fade",             enabled = true,  speed = 3, spring = "appleFluid" })
hl.animation({ leaf = "fadeDim",          enabled = true,  speed = 3, spring = "appleFluid" })
hl.animation({ leaf = "workspaces",       enabled = true,  speed = 4, spring = "appleFluid", style = "slidefade 18%" })
hl.animation({ leaf = "layers",           enabled = true,  speed = 3, spring = "appleFluid", style = "fade" })
hl.animation({ leaf = "specialWorkspace", enabled = true,  speed = 3, spring = "appleSheet", style = "slidefadevert 20%" })
