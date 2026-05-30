import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Power profile lives in nc/'s BatteryService singleton; reuse it (qualified to
// avoid colliding with bar/'s own ThemeService when the dir is imported).
import "../nc" as Nc

PillContainer {
    id: root
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    readonly property var device: UPower.displayDevice
    readonly property int pct: device && device.isPresent ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device && (
        device.state === UPowerDeviceState.Charging ||
        device.state === UPowerDeviceState.FullyCharged ||
        device.state === UPowerDeviceState.PendingCharge)
    readonly property bool warning: !charging && pct <= 30 && pct > 15
    readonly property bool critical: !charging && pct <= 15
    // Low-power profile → iOS/macOS-style yellow battery glyph.
    readonly property bool powerSaver: Nc.BatteryService.mode === "power-saver"

    color: hovered
        ? Qt.rgba(40/255, 50/255, 60/255, 0.4)
        : critical ? Qt.rgba(255/255, 107/255, 107/255, 0.35)
        : warning  ? Qt.rgba(255/255, 200/255, 100/255, 0.35)
        : charging ? Qt.rgba(100/255, 210/255, 180/255, 0.35)
        : Qt.rgba(30/255, 40/255, 50/255, 0.25)
    border.color: hovered
        ? Qt.rgba(100/255, 210/255, 180/255, 0.4)
        : critical ? Qt.rgba(255/255, 107/255, 107/255, 0.4)
        : warning  ? Qt.rgba(255/255, 200/255, 100/255, 0.4)
        : charging ? Qt.rgba(120/255, 230/255, 190/255, 0.4)
        : Qt.rgba(100/255, 210/255, 180/255, 0.3)

    readonly property color textColor:
        critical ? "#ffd0d0"
        : warning  ? "#ffe8c0"
        : charging ? "#d0f8e8"
        : "#d4f1e8"

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: {
                if (root.charging) return "󰂄"
                let p = root.pct
                if (p > 90) return "󰁹"
                if (p > 80) return "󰂂"
                if (p > 70) return "󰂁"
                if (p > 60) return "󰂀"
                if (p > 50) return "󰁿"
                if (p > 40) return "󰁾"
                if (p > 30) return "󰁽"
                if (p > 20) return "󰁼"
                if (p > 10) return "󰁻"
                if (p > 5)  return "󰁺"
                return "󰂃"
            }
            color: root.powerSaver ? "#FFD60A" : root.textColor
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
        }

        Text {
            text: root.pct + "%"
            color: root.textColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }
}
