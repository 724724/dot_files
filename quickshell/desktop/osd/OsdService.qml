pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../nc" as Nc

Singleton {
    id: root

    property string icon: ""
    property string label: ""
    property int progress: 0
    property bool showProgress: false
    property bool visible: false

    function showOsd(ico, lbl, prog, hasProg) {
        icon = ico
        label = lbl
        progress = prog
        showProgress = hasProg
        visible = true
        hideTimer.restart()
    }

    function showKeyboardBacklight(level) {
        let pct = Math.round(level * 100 / Math.max(1, _kbdMax))
        showOsd("󰌌", "", pct, true)
    }

    Timer {
        id: hideTimer
        interval: 2000
        repeat: false
        onTriggered: root.visible = false
    }

    IpcHandler {
        target: "osd"

        function volume(pct: string) {
            let p = parseInt(pct) || 0
            let ico = p <= 0 ? "󰝟" : p <= 50 ? "󰖀" : "󰕾"
            root.showOsd(ico, p + "%", Math.min(p, 100), true)
        }

        function mute(state: string) {
            let muted = state === "1" || state === "true" || state === "yes"
            root.showOsd(muted ? "󰝟" : "󰕾", muted ? "Muted" : "Unmuted", 0, false)
        }

        function micmute(state: string) {
            let muted = state === "1" || state === "true" || state === "yes"
            root.showOsd(muted ? "󰍭" : "󰍬", muted ? "Mic Muted" : "Mic Active", 0, false)
        }

        function brightness(pct: string) {
            let p = parseInt(pct) || 0
            root.showOsd("󰃟", p + "%", p, true)
            // Keep the control-center slider in sync with keybind changes —
            // BrightnessService no longer polls while the CC is closed.
            Nc.BrightnessService.pct = p
        }

        function custom(icon: string, message: string) {
            // Allow caller to omit the icon entirely by passing "" — useful for
            // text-only OSDs ("재생 중인 미디어가 없습니다"). Don't fall back to a
            // default icon here; the window hides the icon Text when empty.
            root.showOsd(icon !== undefined ? icon : "", message || "", 0, false)
        }
    }

    // ── Keyboard backlight watcher ────────────────────────────────────────
    // Fn+Space changes the ThinkPad EC directly, without a userspace key or an
    // inotify event. Keep the confirmed machine path stable across hot reloads;
    // a one-shot Process probe could remain stopped after a Quickshell reload,
    // leaving the polling timer disabled until the next full shell restart.
    readonly property string _kbdPath: "/sys/class/leds/tpacpi::kbd_backlight"
    property int _kbdLevel: -1   // -1 = uninitialized; first read just seeds
    property int _kbdMax:   2

    FileView {
        id: kbdMaxView
        path: root._kbdPath === "" ? "" : root._kbdPath + "/max_brightness"
        printErrors: false
        onLoaded: {
            let m = parseInt(text().trim())
            if (!isNaN(m) && m > 0) root._kbdMax = m
        }
    }
    // Tracks /tmp/kbd-osd-suppress by existence (the flag file may be empty):
    // a successful load means it exists, a failed one means it's gone.
    property bool _kbdSuppressed: false
    FileView {
        id: kbdSuppressView
        path: "/tmp/kbd-osd-suppress"
        printErrors: false
        onLoaded: root._kbdSuppressed = true
        onLoadFailed: root._kbdSuppressed = false
    }
    FileView {
        id: kbdView
        path: root._kbdPath === "" ? "" : root._kbdPath + "/brightness"
        printErrors: false
        onLoaded: {
            let cur = parseInt(text().trim())
            if (isNaN(cur)) return
            if (root._kbdLevel === -1) {
                // First read: just remember; don't fire an OSD on startup.
                root._kbdLevel = cur
            } else if (cur !== root._kbdLevel) {
                root._kbdLevel = cur
                // Skip OSD when change came from hypridle (flag present);
                // reload() below refreshed the flag just before this read.
                if (root._kbdSuppressed) return
                root.showKeyboardBacklight(cur)
            }
        }
    }

    Timer {
        // Firmware-only changes have no reliable event, so the brightness file
        // is polled. The interval MUST stay under hypridle's suppress-flag grace
        // window: on idle-resume it restores the backlight and removes
        // /tmp/kbd-osd-suppress only 0.5s later (see hypridle.conf). A slower
        // poll (e.g. 1s) reads the 0→N restore *after* the flag is already gone
        // and fires a spurious OSD on every idle/resume cycle. 250ms reliably
        // catches the change while the flag is still present. These are
        // in-process FileView reads (no fork), so the cost is negligible.
        interval: 250
        running: root._kbdPath !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            kbdSuppressView.reload()
            kbdView.reload()
        }
    }
}
