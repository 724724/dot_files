-- #######################################################################################
-- MAIN HYPRLAND CONFIG (Lua — Hyprland 0.55+)
-- #######################################################################################
-- hyprlang is deprecated since 0.55. See https://wiki.hypr.land/Configuring/Basics/
--
-- Note: hypridle.conf and hyprlock.conf are NOT touched here — hypridle and hyprlock
-- are separate programs that still use the hyprlang format.

-- Make `require("configs.xxx")` resolve regardless of the working directory.
-- Each require()d file is its own Lua scope, so an error in one file does not
-- abort the others.
package.path = package.path .. ";" .. (os.getenv("HOME") or "") .. "/.config/hypr/?.lua"

-- Source external config files
require("monitors")
require("configs.env")
require("configs.theme")
require("configs.input")
require("configs.keybindings")
require("configs.windowrules")
require("configs.autostart")

-- XWayland Specifics / Debug / Rendering & NVIDIA Optimizations
hl.config({
    xwayland = {
        enabled              = true,
        use_nearest_neighbor = false,
        force_zero_scaling   = true,
    },

    debug = {
        disable_scale_checks = true,
    },

    render = {
        direct_scanout = 1,
    },
})
