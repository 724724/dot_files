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
import Quickshell.Io
import QtQuick

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
import "capture"

Scope {
    id: root

    readonly property string lockCaptureOutputHint: {
        const runtime = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
        return runtime !== "" ? runtime + "/quickshell-desktop-outputs.json" : ""
    }

    function currentOutputNames(): var {
        const names = []
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++) {
            const name = String(screens[i].name || "")
            if (/^[A-Za-z0-9._-]{1,64}$/.test(name))
                names.push(name)
        }
        return names
    }

    function publishLockCaptureOutputs() {
        if (root.lockCaptureOutputHint !== "")
            lockCaptureOutputs.setText(JSON.stringify(root.currentOutputNames()))
    }

    // Read-only handoff used immediately before the independent lock process
    // starts. Quickshell already owns the live QScreen wrappers, so this is
    // more reliable than rediscovering the compositor instance from a user
    // systemd service. No geometry, window title, or application data leaves
    // the desktop process.
    IpcHandler {
        target: "lockCapture"

        function outputs(): string {
            return JSON.stringify(root.currentOutputNames())
        }
    }

    FileView {
        id: lockCaptureOutputs

        path: root.lockCaptureOutputHint
        printErrors: false
    }

    Component.onCompleted: root.publishLockCaptureOutputs()

    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.publishLockCaptureOutputs()
        }
    }

    function ncContentTop(targetScreen) {
        let screenName = targetScreen ? targetScreen.name : ""
        let fullscreen = screenName !== ""
            && DockService.fullscreenMonitors.includes(screenName)
        return BarState.visible && !fullscreen ? BarState.contentTop : BarState.gap
    }

    // ── Bar (self-contained Scope; owns IpcHandler target "bar") ────────
    Bar {}
    // Clock/calendar popup that drops from the bar clock pill (ClockService
    // singleton owns IpcHandler target "clock").
    ClockPopupWindow {}
    // Music Recognition (Shazam) popup that drops from the bar Shazam button
    // (ShazamService singleton owns IpcHandler target "shazam").
    ShazamPopupWindow {}
    // Mic Mode sheet under the bar's mic indicator (PrivacyService owns its state).
    MicModePopupWindow {}
    // Camera-use status sheet under the bar's camera indicator.
    CameraStatusPopupWindow {}
    // Stem filter sheet under the media pill's EQ (StemService owns its state).
    StemPopupWindow {}
    // Dynamic Island-style player sheet under the media pill.
    MediaPopupWindow {}
    // Five-column overflow sheet for system-tray items.
    TrayPopupWindow {}

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
        NotificationPopupWindow { barContentTop: root.ncContentTop(modelData) }
    }
    ControlCenterWindow {
        barContentTop: root.ncContentTop(screen)
        mediaService: MediaService
    }

    // ── Overlays (each Controller wraps its own IpcHandler + state) ─────
    SpotlightController {}
    SwitcherController {}
    WidgetsController {}
    EmojiController {}
    // Shift+Super+3/4/5 capture service, toolbar and per-output selection surfaces.
    CaptureController {}
}
