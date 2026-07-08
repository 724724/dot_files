pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property int vol: 0
    property bool muted: false

    // Output / input device pickers. `sinks`/`sources` are [{name, description}];
    // `defaultSink`/`defaultSource` name the active device used to mark the row.
    property var sinks: []
    property var sources: []
    property string defaultSink: ""
    property string defaultSource: ""

    // MAC → friendly name, harvested from bluetoothctl, since PipeWire reports
    // "(null)" descriptions for Bluetooth devices like AirPods.
    property var btNames: ({})

    function refresh() { if (!refreshProc.running) refreshProc.running = true }
    function refreshDevices() {
        sinksProc.running = true
        defaultProc.running = true
        sourcesProc.running = true
        defaultSourceProc.running = true
        btNamesProc.running = true
    }
    // Coalesce slider drags: at most one pactl in flight; the newest value is
    // applied when the previous write finishes. A drag used to spawn one pactl
    // per pointer move, and each write echoed back a pactl-subscribe event.
    property int _pendingVol: -1
    function setVolume(p) {
        let v = Math.round(p)
        root.vol = v   // optimistic, so the slider holds its dragged position
        if (setProc.running) { root._pendingVol = v; return }
        setProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", v + "%"]
        setProc.running = true
    }
    function toggleMute() { muteProc.running = true }
    function openMixer() { Quickshell.execDetached(["pavucontrol"]) }

    // Resolve a display name: prefer the PipeWire description, fall back to the
    // Bluetooth alias (matched by the MAC embedded in the node name, which uses
    // either '_' or ':' as the separator depending on sink vs. source).
    function deviceLabel(name, description) {
        if (description && description !== "(null)") return description
        let n = name || ""
        if (n.indexOf("bluez") !== -1) {
            let m = n.match(/([0-9A-Fa-f]{2}[:_]){5}[0-9A-Fa-f]{2}/)
            if (m) {
                let mac = m[0].replace(/_/g, ":").toUpperCase()
                if (root.btNames[mac]) return root.btNames[mac]
            }
            return "Bluetooth Device"
        }
        return n || "Unknown"
    }

    // Switch the default output and drag any playing streams over with it.
    function setSink(name) {
        setSinkProc.command = ["bash", "-c",
            "pactl set-default-sink '" + name + "'; " +
            "for s in $(pactl list short sink-inputs | cut -f1); do " +
            "pactl move-sink-input \"$s\" '" + name + "' 2>/dev/null; done"]
        setSinkProc.running = true
        root.defaultSink = name   // optimistic; confirmed on next refresh
    }

    // Switch the default input and drag any recording streams over with it.
    function setSource(name) {
        setSourceProc.command = ["bash", "-c",
            "pactl set-default-source '" + name + "'; " +
            "for s in $(pactl list short source-outputs | cut -f1); do " +
            "pactl move-source-output \"$s\" '" + name + "' 2>/dev/null; done"]
        setSourceProc.running = true
        root.defaultSource = name   // optimistic; confirmed on next refresh
    }

    // Debounced event handling: a volume drag fires dozens of sink-change
    // events per second, and each one used to spawn 6 processes (sinks,
    // sources, defaults, bluetoothctl, volume). Now sink changes only refresh
    // the volume (one process, debounced), and the heavier device
    // re-enumeration runs only for server/card/source topology changes.
    Timer { id: volDebounce; interval: 50; onTriggered: root.refresh() }
    Timer { id: devDebounce; interval: 300; onTriggered: root.refreshDevices() }

    Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("'change' on sink") || data.includes("'change' on server"))
                    volDebounce.restart()
                if (data.includes("'change' on server") || data.includes("'change' on card")
                    || data.includes("'change' on source"))
                    devDebounce.restart()
            }
        }
    }

    Process {
        id: sinksProc
        command: ["bash", "-c", "pactl -f json list sinks 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let arr = JSON.parse(text)
                    root.sinks = arr.map(s => ({ name: s.name, description: s.description }))
                } catch (e) {
                    root.sinks = []
                }
            }
        }
    }

    Process {
        id: defaultProc
        command: ["pactl", "get-default-sink"]
        stdout: StdioCollector {
            onStreamFinished: root.defaultSink = text.trim()
        }
    }

    Process {
        id: setSinkProc
        command: ["true"]
        // Re-read device lists *and* the volume/mute of the now-active sink, so
        // the slider jumps to the new output's level.
        onRunningChanged: if (!running) { root.refreshDevices(); root.refresh() }
    }

    // Input sources, minus the monitor (loopback) sources which aren't real mics.
    Process {
        id: sourcesProc
        command: ["bash", "-c", "pactl -f json list sources 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let arr = JSON.parse(text)
                    root.sources = arr
                        .filter(s => !(s.name || "").endsWith(".monitor")
                                  && (s.properties || {})["device.class"] !== "monitor")
                        .map(s => ({ name: s.name, description: s.description }))
                } catch (e) {
                    root.sources = []
                }
            }
        }
    }

    Process {
        id: defaultSourceProc
        command: ["pactl", "get-default-source"]
        stdout: StdioCollector {
            onStreamFinished: root.defaultSource = text.trim()
        }
    }

    Process {
        id: setSourceProc
        command: ["true"]
        onRunningChanged: if (!running) root.refreshDevices()
    }

    // Build MAC → name map from bluetoothctl ("Device AA:BB:.. <name>").
    Process {
        id: btNamesProc
        command: ["bash", "-c", "bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let map = ({})
                for (let line of text.split("\n")) {
                    let m = line.match(/^Device (\S+) (.+)$/)
                    if (m) map[m[1].toUpperCase()] = m[2]
                }
                root.btNames = map
            }
        }
    }

    Process {
        id: refreshProc
        command: ["bash", "-c",
            "vol=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '/Volume:/{gsub(/%/,\"\",$5); print $5}');" +
            "mute=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}');" +
            "echo \"$vol $mute\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.trim().split(" ")
                root.vol = parseInt(parts[0]) || 0
                root.muted = parts[1] === "yes"
            }
        }
    }

    Process {
        id: setProc
        command: ["true"]
        // Apply the newest coalesced slider value once the in-flight write ends.
        onRunningChanged: {
            if (!running && root._pendingVol >= 0) {
                let v = root._pendingVol
                root._pendingVol = -1
                setProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", v + "%"]
                setProc.running = true
            }
        }
    }
    Process {
        id: muteProc
        command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
    }

    Component.onCompleted: { refresh(); refreshDevices() }
}
