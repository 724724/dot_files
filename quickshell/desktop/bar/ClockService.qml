pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool popupVisible: false
    property var targetScreen: null
    property var alarms: []
    property var timers: []
    property var pomodoros: []
    property var customSounds: []
    property double stopwatchElapsedMs: 0
    property bool stopwatchRunning: false
    property var stopwatchLaps: []
    property double stopwatchStartedAt: 0
    property double stopwatchStartedFrom: 0
    readonly property int stopwatchSeconds: Math.floor(stopwatchElapsedMs / 1000)
    readonly property var now: clock.date
    readonly property string configDir: {
        let value = Quickshell.env("XDG_CONFIG_HOME")
        return value && value !== "" ? value : Quickshell.env("HOME") + "/.config"
    }
    readonly property string soundScript: configDir + "/quickshell/scripts/clock-sound.py"
    readonly property string soundDir: Quickshell.stateDir + "/alarm-sounds"

    SystemClock { id: clock; precision: SystemClock.Seconds }

    FileView {
        id: stateStore
        path: Quickshell.stateDir + "/clock-tools.json"
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 1000
        running: root.hasRunningTimer() || root.hasRunningPomodoro() || root.alarms.length > 0
        repeat: true
        onTriggered: root.tick()
    }

    Timer {
        interval: 16
        running: root.stopwatchRunning
        repeat: true
        onTriggered: root.updateStopwatch()
    }

    Timer {
        interval: 10000
        running: root.stopwatchRunning || root.hasRunningTimer() || root.hasRunningPomodoro()
        repeat: true
        onTriggered: root.persist()
    }

    Component.onCompleted: load()

    function load() {
        let raw = stateStore.text()
        if (!raw) {
            pomodoros = [{ id: nextId(), label: "Focus", focusMinutes: 25, breakMinutes: 5,
                rounds: 4, remaining: 1500, phase: "focus", currentRound: 1, running: false }]
            return
        }
        try {
            let state = JSON.parse(raw)
            alarms = Array.isArray(state.alarms) ? state.alarms : []
            timers = Array.isArray(state.timers) ? state.timers : []
            pomodoros = Array.isArray(state.pomodoros) ? state.pomodoros : []
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
        }
    }

    function persist() {
        stateStore.setText(JSON.stringify({
            alarms: alarms,
            timers: timers,
            pomodoros: pomodoros,
            customSounds: customSounds,
            stopwatchElapsedMs: stopwatchElapsedMs,
            stopwatchSeconds: stopwatchSeconds,
            stopwatchRunning: stopwatchRunning,
            stopwatchLaps: stopwatchLaps
        }))
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

    function replaceAt(source, index, value) {
        let next = source.slice()
        next[index] = value
        return next
    }

    function addAlarm(hour, minute, label, repeatMode, repeatDays, sound, snooze) {
        let next = alarms.slice()
        next.push({ id: nextId(), hour: Number(hour), minute: Number(minute),
            label: label || "Alarm", repeat: repeatMode || "Once", sound: sound || "Radial",
            repeatDays: Array.isArray(repeatDays) ? repeatDays.slice() : [],
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

    function addPomodoro(label, focusMinutes, breakMinutes, rounds) {
        let focus = Math.max(1, Math.floor(focusMinutes))
        let next = pomodoros.slice()
        next.push({ id: nextId(), label: label || "Focus", focusMinutes: focus,
            breakMinutes: Math.max(1, Math.floor(breakMinutes)), rounds: Math.max(1, Math.floor(rounds)),
            remaining: focus * 60, phase: "focus", currentRound: 1, running: false })
        pomodoros = next
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
        function toggle() { root.popupVisible = !root.popupVisible }
        function show() { root.popupVisible = true }
        function hide() { root.popupVisible = false }
    }
}
