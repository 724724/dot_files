//@ pragma UseQApplication
// No `pragma IconTheme` on purpose: let Qt follow the system icon theme
// (gsettings/XDG, surfaced via QT_QPA_PLATFORMTHEME=gtk3). Hardcoding a theme
// here breaks every icon whenever that theme isn't installed.
// Unified shell — combines bar / dock / osd / nc / spotlight / launchpad /
// switcher into a single qs process so the Qt + QML + OpenGL runtime is
// loaded once instead of six times. Memory drop: ~1.4GB → ~300–400MB.
//
// Each subdirectory keeps its existing components and singletons unchanged.
// This file only orchestrates: instantiate the top-level Window/Controller
// pieces from each shell. IpcHandler `target` collisions (spotlight/launchpad/
// switcher all used "ctrl") are resolved by their *Controller wrappers.
//
// `pragma UseQApplication` switches qs from QGuiApplication to QApplication so
// QsMenuAnchor.open() can show the platform DBusMenu used by tray items
// (nm-applet, blueman, fcitx5, etc.).
import Quickshell

import "bar"
import "dock"
import "osd"
import "nc"
import "spotlight"
import "launchpad"
import "missioncontrol"
import "switcher"
import "widgets"
import "emoji"

Scope {
    id: root

    // ── Bar (self-contained Scope; owns IpcHandler target "bar") ────────
    Bar {}
    // Clock/calendar popup that drops from the bar clock pill (ClockService
    // singleton owns IpcHandler target "clock").
    ClockPopupWindow {}
    // Music Recognition (Shazam) popup that drops from the bar Shazam button
    // (ShazamService singleton owns IpcHandler target "shazam").
    ShazamPopupWindow {}

    // Launchpad is created *before* the dock so its layer surface sits below the
    // dock — the dock then rises above the open launchpad instead of being
    // hidden behind it (LaunchpadController owns IpcHandler target "launchpad").
    LaunchpadController {}

    // Mission Control overview (overview/MCService owns IpcHandler target "mc").
    // Created before the dock so the dock's layer rises above its backdrop.
    MissionControlController {}

    // ── Dock (per-screen, like OSD/NC) so it reveals on whichever monitor the
    //    cursor is at the bottom of — not just the primary one ──────────────
    Variants {
        model: Quickshell.screens
        DockWindow {}
    }

    // ── OSD (per-screen; OsdService singleton owns IpcHandler "osd") ────
    Variants {
        model: Quickshell.screens
        OsdWindow {}
    }

    // ── Notification Center (per-screen popups + global control center;
    //    NcServer singleton owns IpcHandler "nc") ─────────────────────────
    Variants {
        model: Quickshell.screens
        NotificationPopupWindow { barContentTop: BarState.contentTop }
    }
    ControlCenterWindow { barContentTop: BarState.contentTop }

    // ── Overlays (each Controller wraps its own IpcHandler + state) ─────
    SpotlightController {}
    SwitcherController {}
    WidgetsController {}
    EmojiController {}
}
