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
    // ThinkPad's Fn+Space cycles tpacpi::kbd_backlight via firmware/ACPI;
    // userspace never sees a key event. sysfs emits no inotify events either,
    // so the brightness file still has to be polled — but with FileView reads
    // (in-process, no fork) instead of the old bash+cat pipeline that spawned
    // ~15 processes per second.
    property int _kbdLevel: -1   // -1 = uninitialized; first read just seeds
    property int _kbdMax:   2

    FileView {
        id: kbdMaxView
        path: "/sys/class/leds/tpacpi::kbd_backlight/max_brightness"
        blockLoading: true
        printErrors: false
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
        path: "/sys/class/leds/tpacpi::kbd_backlight/brightness"
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
                let pct = Math.round(cur * 100 / Math.max(1, root._kbdMax))
                root.showOsd("", "", pct, true)
            }
        }
    }

    Component.onCompleted: {
        let m = parseInt(kbdMaxView.text().trim())
        if (!isNaN(m) && m > 0) root._kbdMax = m
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { kbdSuppressView.reload(); kbdView.reload() }
    }
}
