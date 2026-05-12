pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int level: 0           // 0-100
    property string status: ""      // Charging | Discharging | Full | Not charging
    property string mode: ""        // performance | balanced | power-saver

    readonly property bool charging: status === "Charging" || status === "Full"

    function refresh() { batProc.running = true; modeProc.running = true }
    function setMode(m) {
        // Updates immediately so UI reflects the choice; tlp run reconciles
        root.mode = m
        setProc.command = ["bash", "-c",
            "sudo -n /usr/bin/tlp " + m + " >/dev/null 2>&1 && " +
            "notify-send -a power 'Power Mode' '" + m.charAt(0).toUpperCase() + m.slice(1) + "'"]
        setProc.running = true
    }

    Process {
        id: batProc
        command: ["bash", "-c",
            "lvl=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1);" +
            "st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1);" +
            "echo \"$lvl|$st\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim().split("|")
                root.level = parseInt(p[0]) || 0
                root.status = p[1] || ""
            }
        }
    }

    Process {
        id: modeProc
        // tlp-stat -s shows: "TLP profile    = balanced/BAT"
        command: ["bash", "-c",
            "tlp-stat -s 2>/dev/null | awk -F'=' '/TLP profile/{gsub(/ /,\"\",$2); split($2,a,\"/\"); print a[1]}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = text.trim()
                if (m) root.mode = m
            }
        }
    }

    Process { id: setProc; command: ["true"]
        onRunningChanged: if (!running) modeProc.running = true
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: refresh()
    }
}
