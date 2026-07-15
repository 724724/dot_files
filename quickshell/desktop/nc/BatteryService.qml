pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int level: 0           // 0-100
    property string status: ""      // Charging | Discharging | Full | Not charging
    property string mode: ""        // performance | balanced | power-saver
    property real power: 0          // instantaneous battery power, watts
    property bool onAcPower: false
    property bool batteryPresent: false
    property string _powerContext: ""
    property string _pendingMode: ""
    property bool _pendingModeNotification: false

    readonly property bool charging: status === "Charging" || status === "Full"

    // ── Battery health ───────────────────────────────────────────────────────
    property int cycleCount: 0
    property int maxCapacity: 0     // energy_full / energy_full_design, percent
    property int chargeLimit: 100   // charge_control_end_threshold (100 = no cap)
    property int chargeLimitPref: 80          // remembered cap for the slider (80–100)
    // The Optimized Battery Charging toggle. Kept separate from chargeLimit so the
    // slider can sit at 100% without the toggle flipping itself off.
    property bool optimizedEnabled: false
    property double optimizedSnoozeUntil: 0   // epoch-ms; while in the future, paused "until tomorrow"

    readonly property bool chargeLimited: chargeLimit > 0 && chargeLimit < 100
    // Apple-style condition: Normal unless capacity has degraded below 80% or
    // the pack is past typical Li-ion design cycle life (~1000 cycles).
    readonly property string healthCondition:
        ((maxCapacity > 0 && maxCapacity < 80) || cycleCount > 1000)
            ? "Service Recommended" : "Normal"

    // Optimized charging toggle. limited=true keeps the 80% cap; false allows a
    // full 100% charge. We write BOTH thresholds: the EC only *resumes* charging
    // when SOC drops below the start threshold, so leaving start at 75 means a
    // battery sitting at 80% never tops up even with end=100. Lifting start to
    // 95 makes it charge to 100 right away. Order matters (start must stay below
    // end), so we sequence the writes per direction. Needs the one-time sudoers
    // rule for `tee` on both threshold files.
    // Write the charge cap (end threshold) to `pct`, with the start threshold a
    // few points below so the EC actually tops back up to it. Order matters — the
    // start must stay below the end at every step — so we sequence by direction.
    function setChargeLimit(pct) {
        let endv   = Math.max(50, Math.min(100, Math.round(pct)))
        let startv = Math.max(0, endv - 5)
        let lowering = endv <= root.chargeLimit
        root.chargeLimit = endv   // optimistic; healthProc reconciles
        let endf   = "\"$b/charge_control_end_threshold\""
        let startf = "\"$b/charge_control_start_threshold\""
        let w = (v, f) => "echo " + v + " | sudo -n /usr/bin/tee " + f + " >/dev/null 2>&1"
        // Lowering: drop start first, then end. Raising: raise end first, then
        // start — keeping start < end throughout.
        let seq = lowering ? (w(startv, startf) + "; " + w(endv, endf))
                           : (w(endv, endf) + "; " + w(startv, startf))
        limitProc.command = ["bash", "-c",
            "b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1); " + seq]
        limitProc.running = true
    }

    // ── Optimized Battery Charging (the toggle + its charge-limit slider) ────
    // "On" = a cap below 100% is applied; the slider picks the cap (80–100).
    function enableOptimized() {
        root.optimizedEnabled = true
        root.optimizedSnoozeUntil = 0
        setChargeLimit(root.chargeLimitPref || 80)
        _persistOpt()
    }
    function disableOptimized() {
        root.optimizedEnabled = false
        root.optimizedSnoozeUntil = 0
        setChargeLimit(100)
        _persistOpt()
    }
    // "Turn Off Until Tomorrow": toggle off and lift the cap now, then re-enable
    // it at the start of the next day.
    function snoozeOptimized() {
        let d = new Date(); d.setHours(24, 0, 0, 0)
        root.optimizedSnoozeUntil = d.getTime()
        root.optimizedEnabled = false
        setChargeLimit(100)
        _persistOpt()
    }
    // Move the cap from the slider. Setting it to 100% keeps optimization on (the
    // toggle stays put); the cap just rises to a full charge.
    function setChargeTarget(pct) {
        root.chargeLimitPref = Math.max(80, Math.min(100, Math.round(pct)))
        if (root.optimizedEnabled) setChargeLimit(root.chargeLimitPref)
        _persistOpt()
    }

    // Re-apply the cap once the "until tomorrow" pause elapses.
    Timer {
        interval: 60000
        repeat: true
        running: root.optimizedSnoozeUntil > 0
        triggeredOnStart: true
        onTriggered: {
            if (root.optimizedSnoozeUntil > 0 && Date.now() >= root.optimizedSnoozeUntil)
                root.enableOptimized()
        }
    }

    // Persist the slider preference + snooze deadline (the hardware threshold
    // itself survives in sysfs, but these don't).
    FileView {
        id: optStore
        path: Quickshell.stateDir + "/battery-optimized.json"
        blockLoading: true
        printErrors: false
    }
    function _persistOpt() {
        optStore.setText(JSON.stringify({
            enabled: root.optimizedEnabled,
            pref: root.chargeLimitPref,
            snoozeUntil: root.optimizedSnoozeUntil
        }))
    }
    Component.onCompleted: {
        let raw = optStore.text()
        if (raw) {
            try {
                let p = JSON.parse(raw)
                if (p && typeof p === "object") {
                    if (typeof p.enabled === "boolean") root.optimizedEnabled = p.enabled
                    if (p.pref) root.chargeLimitPref = p.pref
                    if (p.snoozeUntil) root.optimizedSnoozeUntil = p.snoozeUntil
                }
            } catch (e) { /* start fresh */ }
        }
    }

    // ── 24h battery-level history ────────────────────────────────────────────
    // 96 fifteen-minute buckets over the last 24h (oldest → newest), each:
    //   { level: 0-100, charging: bool, has: bool }
    // `histStart` is the epoch-ms of bucket 0 (now − 24h). Sourced from upower's
    // on-disk charge history, so it has real data immediately.
    property var samples: []
    property double histStart: 0

    function refresh() { batProc.running = true; modeProc.running = true; histProc.running = true; healthProc.running = true }

    function _validMode(m) {
        return m === "performance" || m === "balanced" || m === "power-saver"
    }

    function _queueMode(m, notifyUser) {
        if (!_validMode(m)) return
        root.mode = m
        root._pendingMode = m
        root._pendingModeNotification = notifyUser === true
        if (!setProc.running) root._writePendingMode()
    }

    function _writePendingMode() {
        if (!root._pendingMode || setProc.running) return
        let m = root._pendingMode
        let notifyUser = root._pendingModeNotification
        root._pendingMode = ""
        root._pendingModeNotification = false
        let command = "powerprofilesctl set " + m + " >/dev/null 2>&1"
        if (notifyUser)
            command += " && notify-send -a power 'Power Mode' '" + m.charAt(0).toUpperCase() + m.slice(1) + "'"
        setProc.command = ["bash", "-c",
            command]
        setProc.running = true
    }

    function _reconcilePowerContext() {
        if (!root.batteryPresent && !root.onAcPower) return
        let context = root.onAcPower ? "ac"
            : (root.level <= 30 ? "battery-low" : "battery")
        if (context === root._powerContext) return
        root._powerContext = context
        root._queueMode(context === "ac" ? "performance"
            : (context === "battery-low" ? "power-saver" : "balanced"), false)
    }

    function setMode(m) {
        root._queueMode(m, true)
    }

    Process {
        id: batProc
        // power_now is in µW; if the kernel only exposes current/voltage,
        // derive it as current_now(µA) × voltage_now(µV) / 1e6 → µW.
        command: ["bash", "-c",
            "b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1);" +
            "lvl=$(cat \"$b/capacity\" 2>/dev/null);" +
            "st=$(cat \"$b/status\" 2>/dev/null);" +
            "pw=$(cat \"$b/power_now\" 2>/dev/null);" +
            "if [ -z \"$pw\" ]; then c=$(cat \"$b/current_now\" 2>/dev/null);" +
            "v=$(cat \"$b/voltage_now\" 2>/dev/null);" +
            "[ -n \"$c\" ] && [ -n \"$v\" ] && pw=$((c*v/1000000)); fi;" +
            "ac=0; for f in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do " +
            "[ -r \"$f\" ] && [ \"$(cat \"$f\" 2>/dev/null)\" = 1 ] && ac=1; done;" +
            "[ -n \"$b\" ] && has=1 || has=0;" +
            "echo \"$lvl|$st|$pw|$ac|$has\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim().split("|")
                root.level = parseInt(p[0]) || 0
                root.status = p[1] || ""
                root.power = (parseFloat(p[2]) || 0) / 1000000   // µW → W
                root.batteryPresent = p[4] === "1"
                root.onAcPower = p[3] === "1"
                    || root.status === "Charging" || root.status === "Full"
                    || root.status === "Not charging"
                root._reconcilePowerContext()
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
        onRunningChanged: if (!running) {
            if (root._pendingMode) Qt.callLater(() => root._writePendingMode())
            else modeProc.running = true
        }
    }

    // Battery health: cycle count, maximum capacity (full vs design), and the
    // current charge cap. All of these sysfs files are world-readable.
    Process {
        id: healthProc
        command: ["bash", "-c",
            "b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1);" +
            "cyc=$(cat \"$b/cycle_count\" 2>/dev/null);" +
            "ef=$(cat \"$b/energy_full\" 2>/dev/null);" +
            "efd=$(cat \"$b/energy_full_design\" 2>/dev/null);" +
            "[ -z \"$ef\" ]  && ef=$(cat \"$b/charge_full\" 2>/dev/null);" +
            "[ -z \"$efd\" ] && efd=$(cat \"$b/charge_full_design\" 2>/dev/null);" +
            "lim=$(cat \"$b/charge_control_end_threshold\" 2>/dev/null);" +
            "echo \"$cyc|$ef|$efd|$lim\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim().split("|")
                root.cycleCount = parseInt(p[0]) || 0
                let ef = parseFloat(p[1]) || 0
                let efd = parseFloat(p[2]) || 0
                root.maxCapacity = (efd > 0) ? Math.round(ef / efd * 100) : 0
                root.chargeLimit = (p[3] && p[3] !== "") ? (parseInt(p[3]) || 100) : 100
                // A hardware cap below 100 means optimization is on, and is the
                // source of truth for the slider position. (At exactly 100 we
                // leave `optimizedEnabled` alone so the toggle can stay on with a
                // 100% cap.)
                if (root.chargeLimit > 0 && root.chargeLimit < 100) {
                    root.chargeLimitPref = root.chargeLimit
                    root.optimizedEnabled = true
                }
            }
        }
    }

    // Reconcile the health read after a charge-limit write settles.
    Process { id: limitProc; command: ["true"]
        onRunningChanged: if (!running) healthProc.running = true
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
        let now = Date.now()
        let slotMs = 15 * 60 * 1000          // 15 minutes
        let cellMs = 3 * 3600 * 1000         // one 3-hour cell
        // Snap to fixed 3-hour cells. The right edge is the *next* 3-hour clock
        // boundary and the window is exactly the 24h (8 cells) before it. Buckets
        // from `now` onward stay empty, so the current cell shows up as an empty
        // cell that fills with data over the next 3 hours — and the whole chart
        // only shifts when the clock crosses a 3-hour mark, never continuously.
        let d = new Date(now)
        let cellStart = new Date(d.getFullYear(), d.getMonth(), d.getDate(),
                                 d.getHours() - (d.getHours() % 3), 0, 0, 0).getTime()
        let rightEdge = (cellStart >= now) ? cellStart : (cellStart + cellMs)
        let start = rightEdge - 24 * 3600 * 1000
        let nSlots = 96                      // exactly 24h of 15-min buckets
        root.histStart = start

        // Latest reading wins per slot (file is chronological).
        let lvl = new Array(nSlots).fill(-1)
        let chg = new Array(nSlots).fill(false)

        // Seed from the last reading *before* the window so the left edge isn't
        // blank until the first in-window sample.
        let seedLvl = -1, seedChg = false

        let lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            let p = lines[i].trim().split(/\s+/)
            if (p.length < 3) continue
            let ts = parseInt(p[0]) * 1000    // upower timestamps are seconds
            let pct = Math.round(parseFloat(p[1]))
            let state = p[2]
            // First-sample 0%/"unknown" rows are bogus; skip them.
            if (!ts || isNaN(pct) || pct <= 0 || state === "unknown") continue
            if (ts < start) { seedLvl = pct; seedChg = (state !== "discharging"); continue }
            if (ts > now) continue
            let s = Math.floor((ts - start) / slotMs)
            if (s < 0 || s >= nSlots) continue
            lvl[s] = pct
            chg[s] = (state !== "discharging")
        }

        // Carry the last known level/state forward through gaps (seeded from the
        // last sample before the window so the whole 24h fills in). Buckets at or
        // after `now` are left empty so the current 3-hour cell reads as an empty
        // cell that fills in over time.
        let out = []
        let lastLvl = seedLvl, lastChg = seedChg
        for (let s = 0; s < nSlots; s++) {
            if (start + s * slotMs >= now) {
                out.push({ level: 0, charging: false, has: false })
                continue
            }
            if (lvl[s] >= 0) { lastLvl = lvl[s]; lastChg = chg[s] }
            out.push({
                level:    lastLvl >= 0 ? lastLvl : 0,
                charging: lastLvl >= 0 ? lastChg : false,
                has:      lastLvl >= 0
            })
        }
        root.samples = out
    }

    // Full refresh (level/mode/health + the whole upower history parse) only
    // while the control center is on screen — nothing outside it consumes
    // these, and the always-on 30s cycle was reading and bucketing the entire
    // upower history file around the clock. triggeredOnStart refreshes the
    // moment the CC opens.
    Timer {
        interval: 30000
        running: NcServer.controlCenterVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: refresh()
    }

    // Lightweight always-on poll drives automatic profiles on AC/battery
    // transitions and at the 30% boundary. A manual NC choice remains active
    // until one of those contexts changes.
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batProc.running = true
    }

    // The bar's battery pill tints yellow in power-saver mode, so keep `mode`
    // loosely fresh even with the CC closed (setMode reconciles instantly).
    Timer {
        interval: 60000
        running: !NcServer.controlCenterVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: modeProc.running = true
    }
}
