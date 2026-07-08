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
-- 3-finger swipe up opens Mission Control; swipe down closes it (down is a no-op
-- when it's already closed, since `mc hide` just clears the visible flag).
-- NOTE: the `--` separator is required — without it "show" is parsed as the
-- `qs ipc show` (list-handlers) subcommand instead of the function argument,
-- so the call silently does nothing.
hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd("qs ipc -c desktop call -- mc show") end })
hl.gesture({ fingers = 3, direction = "down", action = function() hl.exec_cmd("qs ipc -c desktop call -- mc hide") end })

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
