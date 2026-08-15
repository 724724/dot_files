-------------
--- INPUT ---
-------------
-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            tap_to_click         = false,
            clickfinger_behavior = true,
            scroll_factor        = 0.25,
        },
    },

    cursor = {
        inactive_timeout = 3,
    },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", mods = "SUPER", action = "fullscreen" })
-- Keep Mission Control under the fingers for the full gesture. A compositor
-- event is cheap enough to emit for every update; QuickShell coalesces the
-- resulting progress into its display-synchronised animation transaction.
local mission_control_gesture = {
    start = function(event)
        hl.dispatch(hl.dsp.event("qs-mc-gesture|start|" .. tostring(event.time_ms)))
    end,
    update = function(event)
        hl.dispatch(hl.dsp.event("qs-mc-gesture|update|" .. tostring(event.delta.y)
            .. "|" .. tostring(event.time_ms)))
    end,
    finish = function(event)
        hl.dispatch(hl.dsp.event("qs-mc-gesture|finish|"
            .. (event.cancelled and "1" or "0") .. "|" .. tostring(event.time_ms)))
    end,
}

hl.gesture({ fingers = 3, direction = "vertical", action = mission_control_gesture })

-- Per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name           = "logitech-mx-master-3s",
    scroll_factor  = 1.0,    -- 방향 뒤집고 싶으면 -1.0
    natural_scroll = true,   -- 터치패드처럼 '자연 스크롤' 원하면 이걸 켜고 위는 1.0 유지
})

hl.device({
    name           = "logitech-usb-receiver-mouse",
    scroll_factor  = 1.0,
    natural_scroll = true,
})

hl.device({
    name        = "tpps/2-elan-trackpoint",
    sensitivity = -0.5,
})

hl.device({
    name        = "snsl002d:00-2c2f:002d-touchpad",
    sensitivity = 0.15,
})
