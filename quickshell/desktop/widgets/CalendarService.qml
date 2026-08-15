pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Calendar widget backend. Owns the ICS subscription list (shared by every
// calendar widget, persisted) and the merged upcoming-events model, fetched by
// scripts/calendar-fetch.py (Google "secret iCal address", iCloud public
// share / webcal, any ICS URL). Colors are Apple accent *names* resolved via
// ThemeService.accent() at render time so they track light/dark.
Singleton {
    id: root

    readonly property bool sessionLockPassive: Quickshell.env("QS_LOCK_MODE") === "1"

    // ── Sources ──────────────────────────────────────────────────────────
    // Each: { name, url, color }. Managed from CalendarEditor.
    property var sources: []

    readonly property var colorRotation: ["purple", "green", "blue", "orange", "pink", "teal", "indigo", "red"]

    FileView {
        id: store
        path: Quickshell.stateDir + "/calendar-sources.json"
        blockLoading: true
        printErrors: false   // missing on first run is expected
    }
    Component.onCompleted: {
        root._load()
        if (!root.sessionLockPassive)
            root.refresh()
    }
    function _load() {
        try {
            let a = JSON.parse(store.text() || "[]")
            if (Array.isArray(a)) root.sources = a
        } catch (e) { /* start empty */ }
    }
    function _persist() { store.setText(JSON.stringify(root.sources)) }

    function addSource(name, url) {
        if (!url || !url.trim()) return
        let a = root.sources.slice()
        a.push({
            name: (name && name.trim()) ? name.trim() : ("Calendar " + (a.length + 1)),
            url: url.trim(),
            color: root.colorRotation[a.length % root.colorRotation.length]
        })
        root.sources = a
        root._persist()
        root.refresh()
    }
    function removeSource(i) {
        if (i < 0 || i >= root.sources.length) return
        let a = root.sources.slice()
        a.splice(i, 1)
        root.sources = a
        root._persist()
        // Hide the removed calendar's rows immediately; refresh() re-indexes.
        root.events = root.events.filter(function (e) { return e.src !== i })
        root.refresh()
    }
    // Recolor without a refetch: rewrite the loaded events of that source.
    function setSourceColor(i, color) {
        if (i < 0 || i >= root.sources.length) return
        let a = root.sources.slice()
        a[i] = { name: a[i].name, url: a[i].url, color: color }
        root.sources = a
        root._persist()
        root.events = root.events.map(function (e) {
            if (e.src !== i) return e
            let c = Object.assign({}, e); c.color = color; return c
        })
    }

    // ── Events ───────────────────────────────────────────────────────────
    // Sorted by start. Each: { src, cal, color, title, location, allDay,
    // startMs, endMs }.
    property var events: []
    property bool refreshing: false
    property string statusMsg: ""
    property var lastSync: null

    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string fetchScript: _configDir + "/quickshell/scripts/calendar-fetch.py"

    function refresh() {
        if (root.sessionLockPassive) return
        if (root.refreshing) return
        if (root.sources.length === 0) { root.events = []; root.statusMsg = ""; return }
        root.refreshing = true
        fetchProc.command = ["python3", root.fetchScript, JSON.stringify(root.sources), "42"]
        fetchProc.running = true
    }
    Process {
        id: fetchProc
        stdout: StdioCollector { onStreamFinished: root._onResult(text) }
        onExited: root.refreshing = false
    }
    function _onResult(text) {
        root.refreshing = false
        let r
        try { r = JSON.parse((text || "").trim()) }
        catch (e) { root.statusMsg = "Sync failed"; return }
        if (!r || r.status !== "ok") {
            root.statusMsg = (r && r.message) ? r.message : "Sync failed"
            return
        }
        root.events = r.events || []
        root.lastSync = new Date()
        let fails = (r.failed || []).map(function (f) { return f.name })
        root.statusMsg = fails.length > 0 ? ("Couldn't reach: " + fails.join(", ")) : ""
    }

    Timer {   // periodic re-sync
        interval: 15 * 60 * 1000
        running: !root.sessionLockPassive && root.sources.length > 0
        repeat: true
        onTriggered: root.refresh()
    }

    // ── Clock (today marker, upcoming filter) ────────────────────────────
    property var now: new Date()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // Events that haven't ended yet, soonest first.
    readonly property var upcoming: {
        let t = now.getTime()
        let out = []
        for (let i = 0; i < events.length; i++)
            if (events[i].endMs > t) out.push(events[i])
        return out
    }

    // Apple-style 12h range: "8 – 9PM", "9:30 – 10PM", "11AM – 1PM".
    // The meridiem is dropped from the start time when both ends share it.
    function _h12(d, withMeridiem) {
        let h = d.getHours(), m = d.getMinutes()
        let hh = h % 12; if (hh === 0) hh = 12
        let s = "" + hh + (m > 0 ? ":" + (m < 10 ? "0" : "") + m : "")
        return withMeridiem ? s + (h >= 12 ? "PM" : "AM") : s
    }
    function timeLabel(ev) {
        if (ev.allDay) return "All-day"
        let s = new Date(ev.startMs), e = new Date(ev.endMs)
        let same = (s.getHours() >= 12) === (e.getHours() >= 12)
        return _h12(s, !same) + " – " + _h12(e, true)
    }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }
    function eventsForDay(year, month, day) {
        let start = new Date(year, month, day).getTime()
        let end = new Date(year, month, day + 1).getTime()
        return root.events.filter(function (ev) {
            return ev.startMs < end && ev.endMs > start
        })
    }
    // "Today" / "Tomorrow" / weekday of the first upcoming event.
    readonly property string sectionLabel: {
        if (upcoming.length === 0) return "Today"
        let s = new Date(upcoming[0].startMs)
        if (sameDay(s, now)) return "Today"
        if (sameDay(s, new Date(now.getTime() + 86400000))) return "Tomorrow"
        return Qt.locale("en_US").dayName(s.getDay(), Locale.LongFormat)
    }
}
