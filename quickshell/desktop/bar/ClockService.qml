pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../dock" as Dock

Singleton {
    id: root

    property bool popupVisible: false
    // Set by ClockStatusWidget so the popup opens straight on the running
    // tool's page; -1 = leave the page as-is. Consumed on open.
    property int requestedPage: -1
    property var targetScreen: null
    property string popupSource: ""
    property real popupAnchorX: 173
    property var alarms: []
    property var timers: []
    property var pomodoros: []
    property var ddays: []
    property var customSounds: []
    property double stopwatchElapsedMs: 0
    property bool stopwatchRunning: false
    property var stopwatchLaps: []
    property double stopwatchStartedAt: 0
    property double stopwatchStartedFrom: 0
    readonly property int stopwatchSeconds: Math.floor(stopwatchElapsedMs / 1000)
    readonly property var pinnedDday: {
        let items = ddays
        for (let i = 0; i < items.length; i++)
            if (items[i] && items[i].pinned) return items[i]
        return null
    }
    // Reuse the bar's seconds clock instead of keeping a second 1Hz SystemClock.
    readonly property var now: Time.now
    readonly property string configDir: {
        let value = Quickshell.env("XDG_CONFIG_HOME")
        return value && value !== "" ? value : Quickshell.env("HOME") + "/.config"
    }
    readonly property string soundScript: configDir + "/quickshell/scripts/clock-sound.py"
    readonly property string soundDir: Quickshell.stateDir + "/alarm-sounds"

    FileView {
        id: stateStore
        path: Quickshell.stateDir + "/clock-tools.json"
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 1000
        running: root.stopwatchRunning || root.hasRunningTimer()
            || root.hasRunningPomodoro() || root.hasEnabledAlarm()
        repeat: true
        onTriggered: {
            if (root.stopwatchRunning && !root.popupVisible) root.updateStopwatch()
            root.tick()
        }
    }

    Timer {
        interval: 16
        // Hundredths are only rendered inside the open clock popup. While it is
        // hidden, Date.now() remains the source of truth and the 10s persistence
        // tick below is sufficient; no reason to wake QML at ~60Hz off-screen.
        running: root.stopwatchRunning && root.popupVisible
        repeat: true
        onTriggered: root.updateStopwatch()
    }

    Timer {
        interval: 10000
        running: root.stopwatchRunning || root.hasRunningTimer() || root.hasRunningPomodoro()
        repeat: true
        onTriggered: {
            if (root.stopwatchRunning) root.updateStopwatch()
            root.persist()
        }
    }

    Component.onCompleted: { load(); _recomputeFocus() }
    onPopupVisibleChanged: if (popupVisible && stopwatchRunning) updateStopwatch()

    // ── Focus mode (Pomodoro app-blocking) ───────────────────────────────
    // Focus is "active" only while a Pomodoro is running AND in its focus phase
    // — breaks are unrestricted. While active, only the union of every active
    // session's Allowed Apps may be launched; everything else is masked and
    // blocked in the launchpad, dock and spotlight, and via the app-launch
    // keybindings (Hyprland routes those through scripts/focus-guard.sh, which
    // reads the guard file written below).
    property bool focusActive: false
    property var focusAllowedIds: ({})      // desktop-id → true
    property var focusAllowedExecs: ({})    // exec basename → true
    property string _focusKey: ""

    readonly property string focusGuardPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-focus-guard.json"

    FileView {
        id: focusGuardStore
        path: root.focusGuardPath
        printErrors: false
    }

    // desktop-id → live DesktopEntry, rebuilt when the installed apps change.
    readonly property var appsById: {
        let m = ({})
        let apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            let a = apps[i]
            if (a && a.id) m[a.id] = a
        }
        return m
    }

    onPomodorosChanged: _recomputeFocus()
    // Entries populate slightly after startup; re-derive exec basenames then.
    onAppsByIdChanged: if (focusActive) _recomputeFocus(true)

    // ── Browser detection (drives the "Allowed Sites" editor section) ─────
    // Desktop ids that are browsers but whose entry might not carry the
    // WebBrowser category; the category check below is the primary signal.
    readonly property var knownBrowserIds: ["firefox", "firefox-esr", "librewolf", "waterfox",
        "zen", "google-chrome", "google-chrome-stable", "chromium", "brave-browser",
        "vivaldi-stable", "opera", "microsoft-edge"]

    function isBrowserId(id) {
        if (!id) return false
        let e = appsById[id]
        if (e) {
            let cats = e.categories
            if (Array.isArray(cats) && cats.indexOf("WebBrowser") >= 0) return true
        }
        let lc = String(id).toLowerCase()
        if (knownBrowserIds.indexOf(lc) >= 0) return true
        return lc.indexOf("firefox") >= 0 || lc.indexOf("chrom") >= 0 || lc.indexOf("brave") >= 0
    }

    function hasAllowedBrowser(idsIn) {
        let ids = toArray(idsIn)
        for (let i = 0; i < ids.length; i++) if (isBrowserId(ids[i])) return true
        return false
    }

    // Running windows belonging to an allowed browser, when the session carries a
    // site allowlist. Browsers only read their policy at startup, so these have to
    // be closed for the limits to take effect.
    // Site list the running browsers have already been restarted for. A browser
    // reads its policy once at startup and keeps enforcing it in memory, so while
    // the list is unchanged it is still correct — pausing and resuming must not
    // demand another restart. Cleared only at real session boundaries (reset /
    // edit / completion), where the browser may since have come up unrestricted.
    property string sitesSatisfiedKey: ""

    function sitesKey(sites) {
        return toArray(sites).slice().sort().join("\u0001")
    }

    function runningBrowsersToRestart(allowedIds, allowedSites) {
        let wanted = toArray(allowedSites)
        if (wanted.length === 0) return []
        if (sitesKey(wanted) === sitesSatisfiedKey) return []
        let ids = toArray(allowedIds)
        let tokens = ({})
        for (let i = 0; i < ids.length; i++) {
            let id = ids[i]
            if (!isBrowserId(id)) continue
            tokens[String(id).toLowerCase()] = true
            let e = appsById[id]
            if (e) {
                if (e.startupClass) tokens[String(e.startupClass).toLowerCase()] = true
                let b = _execBasename(e)
                if (b) tokens[String(b).toLowerCase()] = true
            }
        }
        if (Object.keys(tokens).length === 0) return []
        let out = []
        let byClass = Dock.DockService.clientsByClass || ({})
        for (let cls in byClass) {
            let wins = byClass[cls] || []
            if (!wins || wins.length === 0) continue
            let match = tokens[String(cls).toLowerCase()] === true
            if (!match) {
                let execCmd = Dock.DockService.execForClass(cls)
                if (execCmd && execCmd.length >= 2 && execCmd[0] === "gtk-launch"
                        && tokens[String(execCmd[1]).toLowerCase()]) match = true
            }
            if (!match) continue
            let addrs = []
            for (let k = 0; k < wins.length; k++)
                if (wins[k] && wins[k].address) addrs.push(wins[k].address)
            if (addrs.length === 0) continue
            out.push({ cls: cls, addresses: addrs, name: Dock.DockService.nameForClass(cls) })
        }
        return out
    }

    // Push the site allowlist into the browsers' policy files (or clear it).
    function _applySiteRules(active, sites) {
        let script = configDir + "/quickshell/scripts/focus-sites.sh"
        if (active && sites.length > 0)
            Quickshell.execDetached([script, "apply"].concat(sites))
        else
            Quickshell.execDetached([script, "clear"])
    }

    function _execBasename(entry) {
        if (!entry || !entry.command) return ""
        let cmd = entry.command
        for (let i = 0; i < cmd.length; i++) {
            let t = cmd[i]
            if (t && t.charAt(0) !== "%") {
                let slash = t.lastIndexOf("/")
                return slash >= 0 ? t.slice(slash + 1) : t
            }
        }
        return ""
    }

    function _recomputeFocus(force) {
        let ps = pomodoros
        let active = false
        let ids = ({})
        let siteSet = ({})
        for (let i = 0; i < ps.length; i++) {
            let p = ps[i]
            if (!p || !p.running || p.phase !== "focus" || p.restrictionsEnabled === false) continue
            active = true
            let allow = toArray(p.allowedApps)
            for (let j = 0; j < allow.length; j++) if (allow[j]) ids[allow[j]] = true
            let sites = toArray(p.allowedSites)
            for (let k = 0; k < sites.length; k++) if (sites[k]) siteSet[sites[k]] = true
        }
        let siteList = Object.keys(siteSet).sort()
        let key = (active ? "1|" : "0|") + Object.keys(ids).sort().join(",")
            + "|" + siteList.join(",")
        if (key === _focusKey && force !== true) return
        _focusKey = key
        let execs = ({})
        let byId = appsById
        for (let id in ids) {
            let base = _execBasename(byId[id])
            if (base) execs[base] = true
        }
        focusActive = active
        focusAllowedIds = ids
        focusAllowedExecs = execs
        _writeFocusGuard()
        // Push into the dock (same process, no import cycle: bar → dock is fine).
        Dock.DockService.applyFocusState(active, Object.keys(ids), Object.keys(execs))
        _applySiteRules(active, siteList)
    }

    function _writeFocusGuard() {
        focusGuardStore.setText(JSON.stringify({
            active: focusActive,
            allowedIds: Object.keys(focusAllowedIds),
            allowedExecs: Object.keys(focusAllowedExecs)
        }))
    }

    // Public helpers used by the launchpad / spotlight (via Bar.ClockService).
    function isAppAllowed(id) {
        return !focusActive || (id && focusAllowedIds[id] === true)
    }
    function isExecAllowed(execCmd) {
        if (!focusActive) return true
        if (!execCmd || execCmd.length === 0) return true
        if (execCmd[0] === "gtk-launch" && execCmd.length >= 2)
            return focusAllowedIds[execCmd[1]] === true
        let t = execCmd[0] || ""
        let slash = t.lastIndexOf("/")
        let base = slash >= 0 ? t.slice(slash + 1) : t
        return focusAllowedExecs[base] === true
    }
    function focusAppName(id) {
        let a = appsById[id]
        return a && a.name ? a.name : (id || "This app")
    }
    function focusAppIcon(id) {
        let a = appsById[id]
        return a && a.icon ? a.icon : "application-x-executable"
    }
    function notifyBlocked(name) {
        Quickshell.execDetached(["notify-send", "-a", "Focus", "-u", "normal",
            "-i", "changes-prevent-symbolic",
            "Focus Mode", "\"" + (name || "This app") + "\" is blocked during focus time"])
    }

    function load() {
        let raw = stateStore.text()
        if (!raw) {
            pomodoros = [{ id: nextId(), label: "Focus", focusMinutes: 25, breakMinutes: 5,
                rounds: 4, remaining: 1500, phase: "focus", currentRound: 1, running: false,
                restrictionsEnabled: true, allowedApps: [], allowedSites: [], pauseCount: 0 }]
            return
        }
        try {
            let state = JSON.parse(raw)
            alarms = Array.isArray(state.alarms) ? state.alarms : []
            timers = Array.isArray(state.timers) ? state.timers : []
            pomodoros = (Array.isArray(state.pomodoros) ? state.pomodoros : []).map(p => {
                // Backfill fields added after the session was first saved.
                if (typeof p.restrictionsEnabled !== "boolean") p.restrictionsEnabled = true
                if (!Array.isArray(p.allowedApps)) p.allowedApps = []
                if (!Array.isArray(p.allowedSites)) p.allowedSites = []
                if (typeof p.pauseCount !== "number") p.pauseCount = 0
                // A reboot or a shell restart never resumes a focus session: the
                // wall-clock time that passed while we were gone makes `remaining`
                // meaningless, and silently resuming would re-arm the app block
                // with nobody having asked for it. Sessions always come back
                // stopped — _recomputeFocus() then clears the focus guard too.
                p.running = false
                return p
            })
            let pinTaken = false
            ddays = (Array.isArray(state.ddays) ? state.ddays : []).map(source => {
                let item = source || ({})
                let date = normalizedDdayDate(item.year, item.month, item.day)
                let pinned = item.pinned === true && !pinTaken
                if (pinned) pinTaken = true
                return {
                    id: item.id || nextId(),
                    label: item.label || "D-Day",
                    year: date.year,
                    month: date.month,
                    day: date.day,
                    countType: item.countType === "plus" ? "plus" : "minus",
                    pinned: pinned
                }
            })
            customSounds = Array.isArray(state.customSounds) ? state.customSounds : []
            let hasMilliseconds = state.stopwatchElapsedMs !== undefined
            stopwatchElapsedMs = Math.max(0, Number(hasMilliseconds
                ? state.stopwatchElapsedMs : Number(state.stopwatchSeconds || 0) * 1000))
            stopwatchLaps = Array.isArray(state.stopwatchLaps) ? state.stopwatchLaps.map(value =>
                Math.max(0, Number(value || 0)) * (hasMilliseconds ? 1 : 1000)) : []
            stopwatchStartedFrom = stopwatchElapsedMs
            stopwatchStartedAt = Date.now()
            stopwatchRunning = state.stopwatchRunning === true
        } catch (e) {
            alarms = []
            timers = []
            pomodoros = []
            ddays = []
        }
    }

    function persist() {
        stateStore.setText(JSON.stringify({
            alarms: alarms,
            timers: timers,
            pomodoros: pomodoros,
            ddays: ddays,
            customSounds: customSounds,
            stopwatchElapsedMs: stopwatchElapsedMs,
            stopwatchSeconds: stopwatchSeconds,
            stopwatchRunning: stopwatchRunning,
            stopwatchLaps: stopwatchLaps
        }))
    }

    // A JS array that has round-tripped through a QML `var` model — e.g. a
    // ListView delegate's `modelData` — comes back as a *sequence proxy*: it
    // indexes and has .length, but `Array.isArray()` on it is false. Guarding
    // with Array.isArray() therefore silently discarded Allowed Apps / Sites /
    // repeat days whenever the item came from a delegate. Always normalize
    // anything array-like into a real array instead.
    function toArray(value) {
        if (Array.isArray(value)) return value.slice()
        if (value === null || value === undefined) return []
        if (typeof value === "string" || typeof value.length !== "number") return []
        let out = []
        for (let i = 0; i < value.length; i++) out.push(value[i])
        return out
    }

    function nextId() {
        return Date.now() * 1000 + Math.floor(Math.random() * 1000)
    }

    function two(value) {
        return String(Math.max(0, Math.floor(value))).padStart(2, "0")
    }

    function durationLabel(total) {
        total = Math.max(0, Math.floor(total || 0))
        let hours = Math.floor(total / 3600)
        let minutes = Math.floor((total % 3600) / 60)
        let seconds = total % 60
        return hours > 0 ? two(hours) + ":" + two(minutes) + ":" + two(seconds)
                         : two(minutes) + ":" + two(seconds)
    }

    function durationLabelMs(totalMs) {
        totalMs = Math.max(0, Math.floor(totalMs || 0))
        let totalSeconds = Math.floor(totalMs / 1000)
        let hours = Math.floor(totalSeconds / 3600)
        let minutes = Math.floor((totalSeconds % 3600) / 60)
        let seconds = totalSeconds % 60
        let hundredths = String(Math.floor((totalMs % 1000) / 10)).padStart(2, "0")
        return hours > 0 ? two(hours) + ":" + two(minutes) + ":" + two(seconds) + "." + hundredths
                         : two(minutes) + ":" + two(seconds) + "." + hundredths
    }

    function alarmTimeLabel(alarm) {
        let hour = Number(alarm.hour || 0)
        let suffix = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12
        if (displayHour === 0) displayHour = 12
        return displayHour + ":" + two(alarm.minute) + " " + suffix
    }

    function normalizedDdayDate(year, month, day) {
        let y = Math.max(1970, Math.min(2200, Math.floor(Number(year) || new Date().getFullYear())))
        let m = Math.max(1, Math.min(12, Math.floor(Number(month) || 1)))
        let last = new Date(y, m, 0).getDate()
        let d = Math.max(1, Math.min(last, Math.floor(Number(day) || 1)))
        return { year: y, month: m, day: d }
    }

    function ddayDayNumber(year, month, day) {
        let date = normalizedDdayDate(year, month, day)
        return Math.floor(Date.UTC(date.year, date.month - 1, date.day) / 86400000)
    }

    function ddayValue(item) {
        if (!item) return 0
        let today = now
        let todayNumber = Math.floor(Date.UTC(
            today.getFullYear(), today.getMonth(), today.getDate()) / 86400000)
        let target = ddayDayNumber(item.year, item.month, item.day)
        return Math.max(0, item.countType === "plus"
            ? todayNumber - target : target - todayNumber)
    }

    function ddayLabel(item) {
        if (!item) return ""
        let value = ddayValue(item)
        if (value === 0) return "D-Day"
        return (item.countType === "plus" ? "D+" : "D-") + value
    }

    function ddayDateLabel(item) {
        if (!item) return ""
        let date = normalizedDdayDate(item.year, item.month, item.day)
        return date.year + ". " + two(date.month) + ". " + two(date.day) + "."
    }

    function hasEnabledAlarm() {
        for (let i = 0; i < alarms.length; i++)
            if (alarms[i] && alarms[i].enabled) return true
        return false
    }

    function replaceAt(source, index, value) {
        let next = source.slice()
        next[index] = value
        return next
    }

    function addAlarm(hour, minute, label, repeatMode, repeatDays, sound, snooze) {
        let next = alarms.slice()
        next.push({ id: nextId(), hour: Number(hour), minute: Number(minute),
            label: label || "Alarm", repeat: repeatMode || "Once", sound: sound || "Radial",
            repeatDays: toArray(repeatDays),
            snooze: snooze !== false,
            enabled: true, lastTriggered: "" })
        alarms = next
        persist()
    }

    function addCustomSound(sound) {
        if (!sound || !sound.id || !sound.path) return
        let next = customSounds.slice()
        for (let i = 0; i < next.length; i++) {
            if (next[i].id === sound.id || next[i].path === sound.path) {
                next[i] = sound
                customSounds = next
                persist()
                return
            }
        }
        next.unshift(sound)
        customSounds = next
        persist()
    }

    function removeCustomSound(index) {
        if (index < 0 || index >= customSounds.length) return
        let next = customSounds.slice()
        next.splice(index, 1)
        customSounds = next
        persist()
    }

    function soundLabel(id) {
        for (let i = 0; i < customSounds.length; i++) {
            if (customSounds[i].id === id) return customSounds[i].label || "Custom Sound"
        }
        return id || "Radial"
    }

    function customSoundPath(id) {
        for (let i = 0; i < customSounds.length; i++) {
            if (customSounds[i].id === id) return customSounds[i].path || ""
        }
        return ""
    }

    function toggleAlarm(index) {
        if (index < 0 || index >= alarms.length) return
        let alarm = Object.assign({}, alarms[index])
        alarm.enabled = !alarm.enabled
        alarms = replaceAt(alarms, index, alarm)
        persist()
    }

    function removeAlarm(index) {
        if (index < 0 || index >= alarms.length) return
        let next = alarms.slice()
        next.splice(index, 1)
        alarms = next
        persist()
    }

    // Edit an existing alarm in place (keeps id/enabled; re-arms the trigger).
    function updateAlarm(id, hour, minute, label, repeatMode, repeatDays, sound, snooze) {
        let index = alarms.findIndex(a => a && a.id === id)
        if (index < 0) return
        let alarm = Object.assign({}, alarms[index])
        alarm.hour = Number(hour)
        alarm.minute = Number(minute)
        alarm.label = label || "Alarm"
        alarm.repeat = repeatMode || "Once"
        alarm.repeatDays = toArray(repeatDays)
        alarm.sound = sound || "Radial"
        alarm.snooze = snooze !== false
        alarm.lastTriggered = ""
        alarms = replaceAt(alarms, index, alarm)
        persist()
    }

    function indexOfAlarm(id) { return alarms.findIndex(a => a && a.id === id) }

    function addTimer(totalSeconds, label, sound) {
        let total = Math.max(1, Math.floor(totalSeconds))
        let next = timers.slice()
        next.push({ id: nextId(), label: label || "Timer", sound: sound || "Radial", duration: total,
            remaining: total, running: false, finished: false })
        timers = next
        persist()
    }

    function toggleTimer(index) {
        if (index < 0 || index >= timers.length) return
        let timer = Object.assign({}, timers[index])
        if (timer.remaining <= 0) {
            timer.remaining = timer.duration
            timer.finished = false
        }
        timer.running = !timer.running
        timers = replaceAt(timers, index, timer)
        persist()
    }

    function resetTimer(index) {
        if (index < 0 || index >= timers.length) return
        let timer = Object.assign({}, timers[index])
        timer.remaining = timer.duration
        timer.running = false
        timer.finished = false
        timers = replaceAt(timers, index, timer)
        persist()
    }

    function removeTimer(index) {
        if (index < 0 || index >= timers.length) return
        let next = timers.slice()
        next.splice(index, 1)
        timers = next
        persist()
    }

    // Edit an existing timer in place (resets it to the new duration, stopped).
    function updateTimer(id, totalSeconds, label, sound) {
        let index = timers.findIndex(t => t && t.id === id)
        if (index < 0) return
        let total = Math.max(1, Math.floor(totalSeconds))
        let timer = Object.assign({}, timers[index])
        timer.duration = total
        timer.remaining = total
        timer.label = label || "Timer"
        timer.sound = sound || "Radial"
        timer.running = false
        timer.finished = false
        timers = replaceAt(timers, index, timer)
        persist()
    }

    function indexOfTimer(id) { return timers.findIndex(t => t && t.id === id) }

    function toggleStopwatch() {
        if (stopwatchRunning) {
            updateStopwatch()
            stopwatchRunning = false
        } else {
            stopwatchStartedFrom = stopwatchElapsedMs
            stopwatchStartedAt = Date.now()
            stopwatchRunning = true
        }
        persist()
    }

    function updateStopwatch() {
        if (!stopwatchRunning) return
        stopwatchElapsedMs = stopwatchStartedFrom + Math.max(0, Date.now() - stopwatchStartedAt)
    }

    function resetStopwatch() {
        stopwatchRunning = false
        stopwatchElapsedMs = 0
        stopwatchStartedAt = 0
        stopwatchStartedFrom = 0
        stopwatchLaps = []
        persist()
    }

    function addLap() {
        if (!stopwatchRunning || stopwatchElapsedMs <= 0) return
        updateStopwatch()
        let next = stopwatchLaps.slice()
        next.unshift(stopwatchElapsedMs)
        stopwatchLaps = next
        persist()
    }

    function addPomodoro(label, focusMinutes, breakMinutes, rounds, restrictionsEnabled,
            allowedApps, allowedSites) {
        let focus = Math.max(1, Math.floor(focusMinutes))
        let next = pomodoros.slice()
        next.push({ id: nextId(), label: label || "Focus", focusMinutes: focus,
            breakMinutes: Math.max(1, Math.floor(breakMinutes)), rounds: Math.max(1, Math.floor(rounds)),
            remaining: focus * 60, phase: "focus", currentRound: 1, running: false,
            restrictionsEnabled: restrictionsEnabled !== false,
            allowedApps: toArray(allowedApps),
            allowedSites: toArray(allowedSites), pauseCount: 0 })
        pomodoros = next
        persist()
    }

    // ── Pomodoro focus: pause budget (max 3 pauses / session) ─────────────
    readonly property int maxPomodoroPauses: 3

    // Start (or resume) a session. The disallowed-app check + confirmation lives
    // in ClockPopupWindow; by the time this runs the user has agreed.
    function startPomodoro(index) {
        if (index < 0 || index >= pomodoros.length) return
        let item = Object.assign({}, pomodoros[index])
        item.running = true
        pomodoros = replaceAt(pomodoros, index, item)
        persist()
    }

    // Pause a running session, spending one of its 3 pauses. Beyond the budget
    // the pause is refused so the session keeps running.
    function pausePomodoro(index) {
        if (index < 0 || index >= pomodoros.length) return
        let item = pomodoros[index]
        if (!item.running) return
        if ((item.pauseCount || 0) >= maxPomodoroPauses) {
            notify(item.label || "Pomodoro",
                "No pauses left in this session (" + maxPomodoroPauses + "/" + maxPomodoroPauses + ")", "")
            return
        }
        let next = Object.assign({}, item)
        next.running = false
        next.pauseCount = (next.pauseCount || 0) + 1
        pomodoros = replaceAt(pomodoros, index, next)
        persist()
    }

    // Apps currently running that are NOT in `allowedIds` (a session's Allowed
    // Apps). Lenient by design: only windows we can positively identify as a
    // disallowed app are returned, so we never close unidentifiable/system ones.
    function runningDisallowedApps(allowedIds) {
        let ids = toArray(allowedIds)
        let allow = ({})   // lowercase tokens that mean "allowed"
        for (let i = 0; i < ids.length; i++) {
            let id = ids[i]
            if (!id) continue
            allow[String(id).toLowerCase()] = true
            let e = appsById[id]
            if (e) {
                if (e.startupClass) allow[String(e.startupClass).toLowerCase()] = true
                let b = _execBasename(e)
                if (b) allow[String(b).toLowerCase()] = true
            }
        }
        let out = []
        let byClass = Dock.DockService.clientsByClass || ({})
        for (let cls in byClass) {
            let wins = byClass[cls] || []
            if (!wins || wins.length === 0) continue
            if (allow[String(cls).toLowerCase()]) continue
            let execCmd = Dock.DockService.execForClass(cls)
            if (execCmd && execCmd.length >= 2 && execCmd[0] === "gtk-launch"
                    && allow[String(execCmd[1]).toLowerCase()]) continue
            if (!execCmd || execCmd.length === 0) continue   // unidentifiable → leave it
            let addrs = []
            for (let k = 0; k < wins.length; k++)
                if (wins[k] && wins[k].address) addrs.push(wins[k].address)
            if (addrs.length === 0) continue
            out.push({ cls: cls, addresses: addrs, name: Dock.DockService.nameForClass(cls) })
        }
        return out
    }

    // Close every window of the given apps (as returned by runningDisallowedApps).
    function quitApps(list) {
        if (!Array.isArray(list)) return
        let stmts = []
        for (let i = 0; i < list.length; i++) {
            let addrs = (list[i] && list[i].addresses) || []
            for (let j = 0; j < addrs.length; j++)
                stmts.push('hl.dispatch(hl.dsp.window.close({ window = "address:' + addrs[j] + '" }))')
        }
        if (stmts.length > 0) Quickshell.execDetached(["hyprctl", "eval", stmts.join("; ")])
    }

    // Replace the Allowed Apps of an existing session (used when editing).
    function setPomodoroAllowedApps(index, allowedApps) {
        if (index < 0 || index >= pomodoros.length) return
        let item = Object.assign({}, pomodoros[index])
        item.allowedApps = Array.isArray(allowedApps) ? allowedApps.slice() : []
        pomodoros = replaceAt(pomodoros, index, item)
        persist()
    }

    function togglePomodoro(index) {
        if (index < 0 || index >= pomodoros.length) return
        let item = Object.assign({}, pomodoros[index])
        item.running = !item.running
        pomodoros = replaceAt(pomodoros, index, item)
        persist()
    }

    function resetPomodoro(index) {
        if (index < 0 || index >= pomodoros.length) return
        let item = Object.assign({}, pomodoros[index])
        item.phase = "focus"
        item.currentRound = 1
        item.remaining = item.focusMinutes * 60
        item.running = false
        item.pauseCount = 0
        sitesSatisfiedKey = ""
        pomodoros = replaceAt(pomodoros, index, item)
        persist()
    }

    function removePomodoro(index) {
        if (index < 0 || index >= pomodoros.length) return
        let next = pomodoros.slice()
        next.splice(index, 1)
        pomodoros = next
        persist()
    }

    // Edit an existing focus session in place. Editing only the label / rounds /
    // Allowed Apps keeps the session exactly where it is — so adding an app to a
    // *running* session takes effect immediately without wiping its progress.
    // Only a change to the focus/break lengths forces a reset, since `remaining`
    // would otherwise refer to a duration that no longer exists.
    function updatePomodoro(id, label, focusMinutes, breakMinutes, rounds, restrictionsEnabled,
            allowedApps, allowedSites) {
        let index = pomodoros.findIndex(p => p && p.id === id)
        if (index < 0) return
        let prev = pomodoros[index]
        let focus = Math.max(1, Math.floor(focusMinutes))
        let brk = Math.max(1, Math.floor(breakMinutes))
        let rnds = Math.max(1, Math.floor(rounds))
        let item = Object.assign({}, prev)
        item.label = label || "Focus"
        item.focusMinutes = focus
        item.breakMinutes = brk
        item.rounds = rnds
        item.restrictionsEnabled = restrictionsEnabled !== false
        item.allowedApps = toArray(allowedApps)
        item.allowedSites = toArray(allowedSites)
        // The list may have changed, so any earlier restart no longer counts.
        sitesSatisfiedKey = ""
        if (prev.focusMinutes !== focus || prev.breakMinutes !== brk) {
            item.phase = "focus"
            item.currentRound = 1
            item.remaining = focus * 60
            item.running = false
            item.pauseCount = 0
        } else {
            // Rounds may have shrunk below the round we're on.
            item.currentRound = Math.max(1, Math.min(item.currentRound || 1, rnds))
        }
        pomodoros = replaceAt(pomodoros, index, item)
        persist()
    }

    function indexOfPomodoro(id) { return pomodoros.findIndex(p => p && p.id === id) }

    function addDday(label, year, month, day, countType) {
        let date = normalizedDdayDate(year, month, day)
        let next = ddays.slice()
        next.push({
            id: nextId(),
            label: label || "D-Day",
            year: date.year,
            month: date.month,
            day: date.day,
            countType: countType === "plus" ? "plus" : "minus",
            pinned: false
        })
        ddays = next
        persist()
    }

    function updateDday(id, label, year, month, day, countType) {
        let index = ddays.findIndex(item => item && item.id === id)
        if (index < 0) return
        let date = normalizedDdayDate(year, month, day)
        let item = Object.assign({}, ddays[index])
        item.label = label || "D-Day"
        item.year = date.year
        item.month = date.month
        item.day = date.day
        item.countType = countType === "plus" ? "plus" : "minus"
        ddays = replaceAt(ddays, index, item)
        persist()
    }

    function removeDday(index) {
        if (index < 0 || index >= ddays.length) return
        let next = ddays.slice()
        next.splice(index, 1)
        ddays = next
        persist()
    }

    function togglePinnedDday(index) {
        if (index < 0 || index >= ddays.length) return
        let selectedId = ddays[index].id
        let unpin = ddays[index].pinned === true
        ddays = ddays.map(item => {
            let next = Object.assign({}, item)
            next.pinned = !unpin && next.id === selectedId
            return next
        })
        persist()
    }

    function indexOfDday(id) { return ddays.findIndex(item => item && item.id === id) }

    function hasRunningTimer() {
        for (let i = 0; i < timers.length; i++) if (timers[i].running) return true
        return false
    }

    function hasRunningPomodoro() {
        for (let i = 0; i < pomodoros.length; i++) if (pomodoros[i].running) return true
        return false
    }

    function alarmMatchesRepeat(alarm, date) {
        let day = date.getDay()
        if (Array.isArray(alarm.repeatDays) && alarm.repeatDays.length > 0)
            return alarm.repeatDays.indexOf(day) >= 0
        if (alarm.repeat === "Weekdays") return day >= 1 && day <= 5
        if (alarm.repeat === "Weekends") return day === 0 || day === 6
        return true
    }

    function notify(title, body, soundEvent) {
        Quickshell.execDetached(["notify-send", "-a", "Clock", title, body])
        if (soundEvent) Quickshell.execDetached(["canberra-gtk-play", "-i", soundEvent])
    }

    function alarmSoundEvent(sound) {
        if (sound === "Beacon") return "bell"
        if (sound === "Chimes") return "message-new-instant"
        if (sound === "Signal") return "dialog-warning"
        return "alarm-clock-elapsed"
    }

    function playAlarmSound(sound) {
        let path = customSoundPath(sound)
        if (path) Quickshell.execDetached(["pw-play", path])
        else Quickshell.execDetached(["canberra-gtk-play", "-i", alarmSoundEvent(sound)])
    }

    function soundCommand(sound) {
        let path = customSoundPath(sound)
        return path ? ["pw-play", path]
                    : ["canberra-gtk-play", "-i", alarmSoundEvent(sound)]
    }

    function tick() {
        let timerNext = timers.slice()
        let timersChanged = false
        for (let i = 0; i < timerNext.length; i++) {
            if (!timerNext[i].running) continue
            let item = Object.assign({}, timerNext[i])
            item.remaining = Math.max(0, item.remaining - 1)
            if (item.remaining === 0) {
                item.running = false
                item.finished = true
                notify(item.label || "Timer", "Time is up", "")
                playAlarmSound(item.sound || "Radial")
            }
            timerNext[i] = item
            timersChanged = true
        }
        if (timersChanged) timers = timerNext

        let pomoNext = pomodoros.slice()
        let pomosChanged = false
        for (let j = 0; j < pomoNext.length; j++) {
            if (!pomoNext[j].running) continue
            let pomo = Object.assign({}, pomoNext[j])
            pomo.remaining = Math.max(0, pomo.remaining - 1)
            if (pomo.remaining === 0) {
                if (pomo.phase === "focus") {
                    pomo.phase = "break"
                    pomo.remaining = pomo.breakMinutes * 60
                    notify(pomo.label || "Pomodoro", "Focus complete — take a break", "complete")
                } else if (pomo.currentRound < pomo.rounds) {
                    pomo.phase = "focus"
                    pomo.currentRound += 1
                    pomo.remaining = pomo.focusMinutes * 60
                    notify(pomo.label || "Pomodoro", "Break complete — focus", "message-new-instant")
                } else {
                    pomo.phase = "focus"
                    pomo.currentRound = 1
                    pomo.remaining = pomo.focusMinutes * 60
                    pomo.running = false
                    pomo.pauseCount = 0
                    sitesSatisfiedKey = ""
                    notify(pomo.label || "Pomodoro", "Session complete", "complete")
                }
            }
            pomoNext[j] = pomo
            pomosChanged = true
        }
        if (pomosChanged) pomodoros = pomoNext

        let current = new Date()
        let key = current.getFullYear() + "-" + current.getMonth() + "-" + current.getDate()
            + "-" + current.getHours() + "-" + current.getMinutes()
        let alarmNext = alarms.slice()
        let alarmsChanged = false
        for (let k = 0; k < alarmNext.length; k++) {
            let alarm = alarmNext[k]
            if (!alarm.enabled || alarm.hour !== current.getHours() || alarm.minute !== current.getMinutes()
                    || alarm.lastTriggered === key || !alarmMatchesRepeat(alarm, current)) continue
            let fired = Object.assign({}, alarm)
            fired.lastTriggered = key
            if ((!Array.isArray(fired.repeatDays) || fired.repeatDays.length === 0)
                    && fired.repeat === "Once") fired.enabled = false
            alarmNext[k] = fired
            alarmsChanged = true
            notify(fired.label || "Alarm", alarmTimeLabel(fired), "")
            playAlarmSound(fired.sound)
        }
        if (alarmsChanged) {
            alarms = alarmNext
            persist()
        }
    }

    IpcHandler {
        target: "clock"
        function toggle() {
            if (!root.popupVisible) root.popupSource = "external"
            root.popupVisible = !root.popupVisible
        }
        function show() {
            root.popupSource = "external"
            root.popupVisible = true
        }
        function hide() { root.popupVisible = false }
    }
}
