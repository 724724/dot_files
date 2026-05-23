pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

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
    // userspace never sees a key event. Poll the sysfs brightness file and
    // surface an OSD whenever the level changes (0 / 1 / 2 on this device).
    property int _kbdLevel: -1   // -1 = uninitialized; first read just seeds
    property int _kbdMax:   2

    Process {
        id: kbdReadProc
	command: ["bash", "-c",
	    "b=$(cat /sys/class/leds/tpacpi::kbd_backlight/brightness 2>/dev/null); " +
            "m=$(cat /sys/class/leds/tpacpi::kbd_backlight/max_brightness 2>/dev/null); " +
            "s=$([ -f /tmp/kbd-osd-suppress ] && echo 1 || echo 0); " +
            "echo \"$b $m $s\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.trim().split(" ")
                let cur = parseInt(parts[0])
		let max = parseInt(parts[1])
		let suppress = parseInt(parts[2]) === 1
                if (isNaN(cur) || isNaN(max) || max <= 0) return

                if (root._kbdLevel === -1) {
                    // First read: just remember; don't fire an OSD on startup.
                    root._kbdLevel = cur
                    root._kbdMax   = max
                } else if (cur !== root._kbdLevel) {
                    root._kbdLevel = cur
		    root._kbdMax   = max
		    // Skip OSD when change came from hypridle (flag present).
                    if (suppress) return
                    let pct = Math.round(cur * 100 / max)
                    root.showOsd("", "", pct, true)
                }
            }
        }
    }

    Timer {
        interval: 200
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: kbdReadProc.running = true
    }
}
