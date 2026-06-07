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

    // Row-click connect. A bare `nmcli dev wifi connect` on a *secured* network
    // with no stored secret makes NetworkManager consult the system secret
    // agent (nm-applet), which pops its own GTK dialog *under* our overlay —
    // unreachable without first dismissing the panel. To keep everything in the
    // inline password row we never trigger that path: open networks connect
    // directly, secured networks activate an existing saved profile (stored
    // secret, no prompt) if one exists, otherwise exit 100 so the UI opens the
    // inline field and we reconnect with the typed password instead.
    function smartConnect(ssid, security, password) {
        root.pendingSsid = ssid
        let s = ssid.replace(/'/g, "'\\''")
        let cmd
        if (password && password.length > 0) {
            cmd = "nmcli dev wifi connect '" + s + "' password '"
                + password.replace(/'/g, "'\\''") + "'"
        } else if (security === "") {
            cmd = "nmcli dev wifi connect '" + s + "'"
        } else {
            cmd = "if nmcli -t -f NAME connection show | grep -Fxq '" + s + "'; then "
                + "nmcli con up id '" + s + "'; else exit 100; fi"
        }
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
                // Clear the pending marker before notifying so a failed attempt
                // doesn't leave the row stuck on "Connecting…".
                let ssid = root.pendingSsid
                root.pendingSsid = ""
                root.connectFinished(ssid, exitCode)
                // Refresh after a successful connect so the active flag updates
                if (exitCode === 0) scanProc.running = true
            }
        }
    }
}
