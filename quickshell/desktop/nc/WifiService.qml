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

    // Secure connect: hand the PSK to nmcli's own secret agent via stdin using
    // `--ask`. The password never appears in argv (so `ps` / /proc can't leak it
    // to other local users) and never passes through a shell string (no command
    // injection). nmcli saves the profile, so later connects reuse it silently.
    function _connectSecure(ssid, password) {
        root.pendingSsid = ssid
        connectProc._pw = password || ""
        connectProc.command = ["nmcli", "--ask", "device", "wifi", "connect", ssid]
        connectProc.running = true
    }

    function tryConnect(ssid, password) {
        _connectSecure(ssid, password)
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
        if (password && password.length > 0) { _connectSecure(ssid, password); return }
        root.pendingSsid = ssid
        connectProc._pw = ""
        if (security === "") {
            connectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        } else {
            // Secured, no typed password: silently reuse a saved profile if one
            // exists, otherwise exit 100 so the UI opens the inline password row
            // (instead of NetworkManager waking nm-applet under our overlay).
            // SSID is passed as $1 — never interpolated into the script — so even
            // exotic SSIDs can't inject shell.
            connectProc.command = ["bash", "-c",
                "if nmcli -t -f NAME connection show | grep -Fxq -- \"$1\"; then " +
                "nmcli connection up id \"$1\"; else exit 100; fi", "bash", ssid]
        }
        connectProc.running = true
    }

    // ── Per-network management (context menu) ─────────────────────────────────
    // Delete the saved profile for this SSID ("Forget"). No-ops harmlessly if
    // the network was never saved.
    function forget(ssid) {
        let s = ssid.replace(/'/g, "'\\''")
        actionProc.command = ["bash", "-c",
            "nmcli connection delete id '" + s + "' 2>/dev/null"]
        actionProc.running = true
    }

    // Drop the current connection without forgetting the saved profile.
    function disconnectSsid(ssid) {
        let s = ssid.replace(/'/g, "'\\''")
        actionProc.command = ["bash", "-c",
            "nmcli connection down id '" + s + "' 2>/dev/null"]
        actionProc.running = true
    }

    // Open nm-connection-editor focused on this network's saved profile when one
    // exists, otherwise the editor's connection list.
    function editConnection(ssid) {
        let s = ssid.replace(/'/g, "'\\''")
        Quickshell.execDetached(["bash", "-c",
            "uuid=$(nmcli -t -f UUID,NAME connection show | awk -F: -v n='" + s + "' '$2==n{print $1; exit}'); " +
            "if [ -n \"$uuid\" ]; then nm-connection-editor --edit=\"$uuid\"; else nm-connection-editor; fi"])
    }

    Process {
        id: actionProc
        command: ["true"]
        onRunningChanged: if (!running) root.refresh()
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
        stdinEnabled: true
        // Plaintext PSK held only between launch and the first stdin write, then
        // wiped. Lives in-process only; never reaches argv or a shell.
        property string _pw: ""
        onStarted: {
            connectTimeout.restart()
            if (_pw.length > 0) { write(_pw + "\n"); _pw = "" }
        }
        // exitCode is a parameter of exited() — not a Process property — so the
        // completion logic must run here, not in onRunningChanged (where
        // referencing exitCode throws ReferenceError and skips connectFinished,
        // which is what opens the inline password row on the exit-100 sentinel).
        onExited: function(exitCode, exitStatus) {
            connectTimeout.stop()
            _pw = ""
            // Clear the pending marker before notifying so a failed attempt
            // doesn't leave the row stuck on "Connecting…".
            let ssid = root.pendingSsid
            root.pendingSsid = ""
            root.connectFinished(ssid, exitCode)
            // Refresh after a successful connect so the active flag updates
            if (exitCode === 0) scanProc.running = true
        }
    }

    // Backstop: if nmcli --ask ever blocks waiting for an unexpected extra secret
    // (e.g. enterprise 802.1x), don't leave the row stuck on "Connecting…"
    // forever — terminate it so the failure surfaces.
    Timer {
        id: connectTimeout
        interval: 40000
        onTriggered: if (connectProc.running) connectProc.signal(15)
    }
}
