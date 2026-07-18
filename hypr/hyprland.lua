-- #######################################################################################
-- MAIN HYPRLAND CONFIG (Lua — Hyprland 0.55+)
-- #######################################################################################
-- hyprlang is deprecated since 0.55. See https://wiki.hypr.land/Configuring/Basics/

package.path = package.path .. ";" .. (os.getenv("HOME") or "") .. "/.config/hypr/?.lua"

-- Source external config files
require("configs.autostart")
require("configs.env")
require("configs.input")
require("configs.keybindings")
require("configs.monitors")
require("configs.theme")
require("configs.windowrules")

-- XWayland Specifics / Debug / Rendering & NVIDIA Optimizations
hl.config({
    xwayland = {
        enabled              = true,
        use_nearest_neighbor = false,
        force_zero_scaling   = true,
    },

    debug = {
        disable_scale_checks = true,
        damage_tracking      = 2,
        disable_logs         = true,
    },
})
