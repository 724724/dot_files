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

    // ── 24h battery-level history ────────────────────────────────────────────
    // 24 hourly buckets for today (local midnight → now), each:
    //   { level: 0-100, charging: bool, has: bool }
    // Sourced from upower's on-disk charge history, so it has real data
    // immediately — no logging of our own required.
    property var hourly: []

    function refresh() { batProc.running = true; modeProc.running = true; histProc.running = true }
    function setMode(m) {
        // Updates immediately so UI reflects the choice; the daemon reconciles.
        // power-profiles-daemon's profile names (performance | balanced |
        // power-saver) match our mode values exactly, and powerprofilesctl
        // talks to it over D-Bus/polkit so no sudo is needed.
        root.mode = m
        setProc.command = ["bash", "-c",
            "powerprofilesctl set " + m + " >/dev/null 2>&1 && " +
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
        // powerprofilesctl get prints just the active profile name, which
        // already matches our mode values (performance | balanced | power-saver).
        command: ["powerprofilesctl", "get"]
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

    // Pick the laptop battery's charge-history file (largest, excluding
    // peripherals like the MX Master mouse) and dump it. Lines are
    //   <unix_ts>\t<percent>\t<state>
    Process {
        id: histProc
        command: ["bash", "-c",
            "f=$(ls -S /var/lib/upower/history-charge-*.dat 2>/dev/null " +
            "| grep -vEi 'MX_Master|generic_id|mouse|keyboard|trackpad' | head -1); " +
            "[ -n \"$f\" ] && cat \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: root._parseHistory(text)
        }
    }

    function _parseHistory(text) {
        let now = new Date()
        let midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        let mts = Math.floor(midnight.getTime() / 1000)
        let curHour = now.getHours()

        // Latest reading wins per hour (file is chronological).
        let lvl = new Array(24).fill(-1)
        let chg = new Array(24).fill(false)

        let lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            let p = lines[i].trim().split(/\s+/)
            if (p.length < 3) continue
            let ts = parseInt(p[0])
            let pct = Math.round(parseFloat(p[1]))
            let state = p[2]
            // First-sample 0%/"unknown" rows are bogus; skip them.
            if (!ts || isNaN(pct) || pct <= 0 || state === "unknown") continue
            let h = Math.floor((ts - mts) / 3600)
            if (h < 0 || h > 23) continue
            lvl[h] = pct
            chg[h] = (state !== "discharging")
        }

        // Carry the last known level/state forward through gaps up to the
        // current hour; leave future hours empty so the axis matches iOS.
        let out = []
        let lastLvl = -1, lastChg = false
        for (let h = 0; h < 24; h++) {
            if (lvl[h] >= 0) { lastLvl = lvl[h]; lastChg = chg[h] }
            let filled = (h <= curHour && lastLvl >= 0)
            out.push({
                level:    filled ? lastLvl : 0,
                charging: filled ? lastChg : false,
                has:      filled
            })
        }
        root.hourly = out
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: refresh()
    }
}
