import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    color: hovered
        ? ThemeService.pillBgHover
        : NetworkService.isConnected ? ThemeService.pillBg : ThemeService.pillBgMuted

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
            color: NetworkService.isConnected ? ThemeService.fg : ThemeService.fgDim
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
            color: NetworkService.isConnected ? ThemeService.fg : ThemeService.fgDim
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }
}
