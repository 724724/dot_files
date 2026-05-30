import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    color: hovered
        ? Qt.rgba(40/255, 50/255, 60/255, 0.4)
        : NetworkService.isConnected
            ? Qt.rgba(30/255, 40/255, 50/255, 0.25)
            : Qt.rgba(150/255, 150/255, 150/255, 0.25)

    Process {
        id: nmLauncher
        command: ["nm-connection-editor"]
    }

    TapHandler {
        onTapped: nmLauncher.running = true
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: {
                if (!NetworkService.isConnected) return "󰤭"
                return NetworkService.isWifi ? "󰤨" : "󰈀"
            }
            color: NetworkService.isConnected ? "#d4f1e8" : "#b0b0b0"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
        }

        Text {
            text: {
                if (!NetworkService.isConnected) return "Disconnected"
                if (NetworkService.isWifi && NetworkService.ssid)
                    return NetworkService.ssid
                return "Connected"
            }
            color: NetworkService.isConnected ? "#d4f1e8" : "#b0b0b0"
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }
}
