import Quickshell

// One capture surface per output. The selected output embeds its toolbar in the
// same surface, so buttons, empty-chrome dragging and selection gestures share
// one deterministic pointer hierarchy.
Scope {
    Variants {
        model: Quickshell.screens
        CaptureOverlayWindow {}
    }
}
