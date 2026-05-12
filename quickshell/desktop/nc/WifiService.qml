pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Cached scan results — survive across detail panel mount/unmount so the
    // user sees the previous list immediately when re-entering the Wi-Fi panel.
    property var networks: []
    property bool scanning: false
    property double lastScanTime: 0  // ms epoch; 0 means never scanned

    // Connection state surfaced to the UI for inline progress / error display.
    property string pendingSsid: ""
    signal connectFinished(string ssid, int exitCode)

    // Manual nmcli-style colon split that respects \\: escapes.
    function _splitNmcli(line) {
        let out = []
        let cur = ""
        for (let i = 0; i < line.length; ++i) {
            let c = line[i]
            if (c === '\\' && i + 1 < line.length) { cur += line[i+1]; i++ }
            else if (c === ':') { out.push(cur); cur = "" }
            else cur += c
        }
        out.push(cur)
        return out
    }

    function refresh() {
        scanning = true
        scanProc.running = true
    }

    // Re-scan only when the cache is older than maxAgeMs. Used by the detail
    // panel on entry so cached results show instantly but auto-update if stale.
    function refreshIfStale(maxAgeMs) {
        if (!lastScanTime || (Date.now() - lastScanTime) > maxAgeMs) {
            refresh()
        }
    }

    function tryConnect(ssid, password) {
        root.pendingSsid = ssid
        let cmd = "nmcli dev wifi connect '" + ssid.replace(/'/g, "'\\''") + "'"
        if (password && password.length > 0)
            cmd += " password '" + password.replace(/'/g, "'\\''") + "'"
        connectProc.command = ["bash", "-c", cmd]
        connectProc.running = true
    }

    Process {
        id: scanProc
        command: ["bash", "-c",
            "nmcli -t -f active,ssid,signal,security dev wifi list --rescan yes 2>/dev/null"]
        onRunningChanged: if (!running) root.scanning = false
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                let seen = {}
                for (let l of text.trim().split("\n")) {
                    if (!l) continue
                    let parts = root._splitNmcli(l)
                    let active = parts[0] === "yes"
                    let ssid = parts[1] || ""
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    arr.push({
                        ssid: ssid,
                        signal: parseInt(parts[2]) || 0,
                        security: parts[3] || "",
                        active: active
                    })
                }
                arr.sort((a,b) => (b.active - a.active) || (b.signal - a.signal))
                root.networks = arr
                root.lastScanTime = Date.now()
            }
        }
    }

    Process {
        id: connectProc
        command: ["true"]
        onRunningChanged: {
            if (!running) {
                root.connectFinished(root.pendingSsid, exitCode)
                if (exitCode === 0) {
                    root.pendingSsid = ""
                    // Refresh after a successful connect so the active flag updates
                    scanProc.running = true
                }
            }
        }
    }
}
