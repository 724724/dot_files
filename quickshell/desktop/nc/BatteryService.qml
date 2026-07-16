pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "battery-history.js" as BatteryHistory

Singleton {
    id: root
    readonly property var device: UPower.displayDevice
    readonly property int level: device && device.isPresent
        ? Math.round(device.percentage * 100) : 0
    readonly property string status: root._batteryStateName(device ? device.state : UPowerDeviceState.Unknown)
    readonly property string mode: root._profileName(PowerProfiles.profile)
    readonly property real power: device ? Math.abs(device.changeRate || 0) : 0
    readonly property bool batteryPresent: !!(device && device.isPresent)
    readonly property bool onAcPower: batteryPresent && !UPower.onBattery
    property string _powerContext: ""

    readonly property bool charging: device && (
        device.state === UPowerDeviceState.Charging
        || device.state === UPowerDeviceState.FullyCharged
        || device.state === UPowerDeviceState.PendingCharge)

    function _batteryStateName(value) {
        if (value === UPowerDeviceState.Charging) return "Charging"
        if (value === UPowerDeviceState.Discharging) return "Discharging"
        if (value === UPowerDeviceState.FullyCharged) return "Full"
        if (value === UPowerDeviceState.PendingCharge
                || value === UPowerDeviceState.PendingDischarge) return "Not charging"
        if (value === UPowerDeviceState.Empty) return "Empty"
        return ""
    }

    function _profileName(value) {
        if (value === PowerProfile.Performance) return "performance"
        if (value === PowerProfile.PowerSaver) return "power-saver"
        return "balanced"
    }

    function _profileValue(value) {
        if (value === "performance") return PowerProfile.Performance
        if (value === "power-saver") return PowerProfile.PowerSaver
        return PowerProfile.Balanced
    }

    // ── Battery health ───────────────────────────────────────────────────────
    property int cycleCount: 0
    property int maxCapacity: 0     // energy_full / energy_full_design, percent
    property int chargeLimit: 100   // charge_control_end_threshold (100 = no cap)
    property int chargeStartLimit: 0
    property int chargeLimitPref: 80          // remembered cap for the slider (80–100)
    // The Optimized Battery Charging toggle. Kept separate from chargeLimit so the
    // slider can sit at 100% without the toggle flipping itself off.
    property bool optimizedEnabled: false
    property double optimizedSnoozeUntil: 0   // epoch-ms; while in the future, paused "until tomorrow"
    property bool _hasStoredOptimizationState: false
    property bool _restorePending: false
    property int _restoreTarget: 100

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
        root.chargeStartLimit = startv
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

    // Persist the slider preference + snooze deadline. Some EC drivers reset
    // their sysfs thresholds at reboot, so the saved state is also the source
    // used by the one-shot startup reconciliation below.
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
                    if (typeof p.enabled === "boolean") {
                        root.optimizedEnabled = p.enabled
                        root._hasStoredOptimizationState = true
                    }
                    if (p.pref) root.chargeLimitPref = Math.max(80, Math.min(100, Math.round(p.pref)))
                    if (p.snoozeUntil) root.optimizedSnoozeUntil = p.snoozeUntil
                }
            } catch (e) { /* start fresh */ }
        }

        // The EC/driver may reset its sysfs thresholds during reboot. Restore a
        // saved preference once per shell start, but only after reading the real
        // start/end values; matching values cause no sudo call or hardware write.
        if (root._hasStoredOptimizationState) {
            if (root.optimizedSnoozeUntil > 0 && Date.now() >= root.optimizedSnoozeUntil) {
                root.optimizedSnoozeUntil = 0
                root.optimizedEnabled = true
                root._persistOpt()
            } else if (root.optimizedSnoozeUntil > Date.now()) {
                root.optimizedEnabled = false
            }
            root._restoreTarget = root.optimizedEnabled ? root.chargeLimitPref : 100
            root._restorePending = true
            Qt.callLater(() => healthProc.running = true)
        }
        root._reconcilePowerContext()
    }

    // ── 24h battery-level history ────────────────────────────────────────────
    // 96 fifteen-minute buckets over the last 24h (oldest → newest), each:
    //   { level: 0-100, charging: bool, has: bool }
    // `histStart` is the epoch-ms of bucket 0 (now − 24h). Sourced from upower's
    // on-disk charge history, so it has real data immediately.
    property var samples: []
    property double histStart: 0

    function refresh() { histProc.running = true; healthProc.running = true }

    function _validMode(m) {
        return m === "performance" || m === "balanced" || m === "power-saver"
    }

    function _queueMode(m, notifyUser) {
        if (!_validMode(m)) return
        let wanted = root._profileValue(m)
        if (PowerProfiles.profile !== wanted) PowerProfiles.profile = wanted
        if (notifyUser === true)
            Quickshell.execDetached(["notify-send", "-a", "power", "Power Mode",
                m.charAt(0).toUpperCase() + m.slice(1)])
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

    // UPower and power-profiles-daemon are exposed as reactive QML services.
    // Property changes drive these handlers directly, replacing the old 3s
    // bash/sysfs poll and the 60s `powerprofilesctl get` subprocess.
    onLevelChanged: root._reconcilePowerContext()
    onOnAcPowerChanged: root._reconcilePowerContext()
    onBatteryPresentChanged: root._reconcilePowerContext()

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
            "startlim=$(cat \"$b/charge_control_start_threshold\" 2>/dev/null);" +
            "echo \"$cyc|$ef|$efd|$lim|$startlim\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim().split("|")
                root.cycleCount = parseInt(p[0]) || 0
                let ef = parseFloat(p[1]) || 0
                let efd = parseFloat(p[2]) || 0
                root.maxCapacity = (efd > 0) ? Math.round(ef / efd * 100) : 0
                root.chargeLimit = (p[3] && p[3] !== "") ? (parseInt(p[3]) || 100) : 100
                root.chargeStartLimit = (p[4] && p[4] !== "") ? (parseInt(p[4]) || 0) : 0
                // A hardware cap below 100 means optimization is on, and is the
                // source of truth only on first use, before a saved preference
                // exists. A saved state must win so reboot-reset EC values can be
                // restored instead of silently overwriting the user's choice.
                if (!root._hasStoredOptimizationState
                        && root.chargeLimit > 0 && root.chargeLimit < 100) {
                    root.chargeLimitPref = root.chargeLimit
                    root.optimizedEnabled = true
                }
                if (root._restorePending) {
                    let target = root._restoreTarget
                    let targetStart = Math.max(0, target - 5)
                    let needsWrite = root.chargeLimit !== target
                        || root.chargeStartLimit !== targetStart
                    root._restorePending = false
                    if (needsWrite) Qt.callLater(() => root.setChargeLimit(target))
                }
            }
        }
    }

    // Reconcile the health read after a charge-limit write settles.
    Process { id: limitProc; command: ["true"]
        onRunningChanged: if (!running) healthProc.running = true
    }

    // Query the real laptop battery through UPower's public D-Bus API.  The
    // daemon's files in /var/lib/upower are root:root 0640 on current Arch, so
    // reading them directly always produced an empty graph for normal users.
    Process {
        id: histProc
        command: ["bash", "-c",
            "d=$(upower -e 2>/dev/null | sed -n '/\\/battery_/ {p;q}'); " +
            "[ -n \"$d\" ] && exec busctl --system --json=short call " +
            "org.freedesktop.UPower \"$d\" org.freedesktop.UPower.Device " +
            "GetHistory suu charge 86400 96"]
        stdout: StdioCollector {
            onStreamFinished: root._parseHistory(text)
        }
    }

    function _parseHistory(text) {
        let result = BatteryHistory.buildBuckets(text, Date.now())
        root.histStart = result.histStart
        root.samples = result.samples
    }

    // Health + the whole UPower history parse only while the control center is
    // on screen. Level/status/profile are reactive services above, so this is
    // the only periodic battery work left. triggeredOnStart refreshes the
    // moment the CC opens.
    Timer {
        interval: 30000
        running: NcServer.controlCenterVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: refresh()
    }

}
