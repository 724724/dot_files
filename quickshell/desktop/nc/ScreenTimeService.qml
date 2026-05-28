pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Per-app "screen time" tracker. Linux has no per-app battery accounting like
// iOS, so we approximate usage by sampling the focused Hyprland window every
// `tickSeconds` and crediting that interval to the app's class. Totals are for
// the current local day and persist to disk so a quickshell restart doesn't
// wipe the running tally. Suspended/asleep time isn't counted because the poll
// timer doesn't fire while the machine is asleep.
Singleton {
    id: root

    // Normalized class → seconds focused today.
    property var apps: ({})
    property string day: ""        // YYYY-MM-DD currently being accumulated
    property int totalSeconds: 0   // Σ apps (active screen time today)

    readonly property string dataDir:  "/home/sejunlee/.local/share/quickshell"
    readonly property string dataFile: dataDir + "/screentime.json"
    readonly property int tickSeconds: 20

    // [{ cls, seconds }] sorted descending — what the UI renders.
    readonly property var ranked: {
        let arr = []
        let m = root.apps
        for (let k in m) arr.push({ cls: k, seconds: m[k] })
        arr.sort((a, b) => b.seconds - a.seconds)
        return arr
    }

    function fmt(secs) {
        let h = Math.floor(secs / 3600)
        let m = Math.floor((secs % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return secs > 0 ? "<1m" : "0m"
    }

    // Class → icon-theme name (mirrors the switcher's mapping for the few apps
    // whose wmClass doesn't match their themed icon name).
    function iconNameFor(cls) {
        if (!cls) return "application-x-executable"
        let lc = cls.toLowerCase()
        if (lc === "code")    return "visual-studio-code"
        if (lc === "spotify") return "spotify-client"
        if (lc === "kakaotalk.exe") {
            // Wine app: themed icon name (a hash) lives in its .desktop entry.
            let de = DesktopEntries.heuristicLookup("kakaotalk.exe")
            return de && de.icon ? de.icon : "DDB7_KakaoTalk.0"
        }
        return cls
    }

    // Pretty label: reverse-DNS → last segment, dashes/underscores → spaces,
    // Title-Cased. "google-chrome" → "Google Chrome", "org.gnome.Nautilus" →
    // "Nautilus", "code" → "Code".
    function displayName(cls) {
        if (!cls) return ""
        let parts = cls.split(".")
        let base = parts.length >= 3 ? parts[parts.length - 1] : cls
        base = base.replace(/[-_]/g, " ")
        return base.replace(/\b\w/g, c => c.toUpperCase())
    }

    function _today() {
        let d = new Date()
        let mm = String(d.getMonth() + 1).padStart(2, "0")
        let dd = String(d.getDate()).padStart(2, "0")
        return d.getFullYear() + "-" + mm + "-" + dd
    }

    // Merge per-launch Qt instance suffixes ("foo_1234_5678" → "foo") so the
    // same app doesn't fragment into multiple rows across relaunches.
    function _norm(cls) {
        if (!cls) return ""
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        return m ? m[1] : cls
    }

    function _recompute() {
        let t = 0, m = root.apps
        for (let k in m) t += m[k]
        root.totalSeconds = t
    }

    Component.onCompleted: loadProc.running = true

    // ── Load persisted tally on startup ─────────────────────────────────────
    Process {
        id: loadProc
        command: ["bash", "-c", "cat '" + root.dataFile + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let obj = JSON.parse(text)
                    if (obj && obj.apps && obj.day === root._today()) {
                        root.day  = obj.day
                        root.apps = obj.apps
                    } else {
                        // Stale (different day) or absent → start fresh.
                        root.day  = root._today()
                        root.apps = ({})
                    }
                } catch (e) {
                    root.day  = root._today()
                    root.apps = ({})
                }
                root._recompute()
                pollTimer.start()
            }
        }
    }

    // ── Sample the focused window ────────────────────────────────────────────
    Process {
        id: activeProc
        command: ["bash", "-c",
            "hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty'"]
        stdout: StdioCollector {
            onStreamFinished: root._accumulate(text.trim())
        }
    }

    Timer {
        id: pollTimer
        interval: root.tickSeconds * 1000
        repeat: true
        running: false
        onTriggered: activeProc.running = true
    }

    function _accumulate(rawClass) {
        let today = root._today()
        if (today !== root.day) {     // crossed midnight → reset to today
            root.day  = today
            root.apps = ({})
        }
        let cls = root._norm(rawClass)
        if (cls.length > 0) {
            // Reassign a fresh object so `ranked`/bindings re-evaluate.
            let m = Object.assign({}, root.apps)
            m[cls] = (m[cls] || 0) + root.tickSeconds
            root.apps = m
        }
        root._recompute()
        root._persist()
    }

    // ── Persist ──────────────────────────────────────────────────────────────
    // base64 round-trips the JSON through the shell without quoting hazards.
    Process { id: saveProc; command: ["true"] }
    function _persist() {
        let b64 = Qt.btoa(JSON.stringify({ day: root.day, apps: root.apps }))
        saveProc.command = ["bash", "-c",
            "mkdir -p '" + root.dataDir + "'; " +
            "echo '" + b64 + "' | base64 -d > '" + root.dataFile + "'"]
        saveProc.running = true
    }
}
