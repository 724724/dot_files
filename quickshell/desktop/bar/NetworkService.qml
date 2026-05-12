pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool isConnected: false
    property bool isWifi: false
    property string ssid: ""
    property string ifname: ""

    Process {
        id: netProc
        command: ["bash", "-c",
            "nmcli -t -f TYPE,STATE,CONNECTION,DEVICE device 2>/dev/null | grep ':connected:' | head -1 || true"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                let line = text.trim()
                if (!line) {
                    root.isConnected = false
                    root.isWifi = false
                    root.ssid = ""
                    root.ifname = ""
                    return
                }
                let parts = line.split(":")
                root.isConnected = true
                root.isWifi = parts[0] === "wifi"
                root.ssid = parts[2] || ""
                root.ifname = parts[3] || ""
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: netProc.running = true
    }
}
