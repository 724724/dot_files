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
        ? ThemeService.pillBgHover
        : critical ? Qt.rgba(255/255, 107/255, 107/255, 0.35)
        : warning  ? Qt.rgba(255/255, 200/255, 100/255, 0.35)
        : charging ? (ThemeService.isDark ? Qt.rgba(70/255, 170/255, 110/255, 0.38)
                                          : Qt.rgba(190/255, 232/255, 202/255, 0.92))
        : ThemeService.pillBg
    border.color: hovered
        ? ThemeService.pillBorderHover
        : critical ? Qt.rgba(255/255, 107/255, 107/255, 0.4)
        : warning  ? Qt.rgba(255/255, 200/255, 100/255, 0.4)
        : charging ? (ThemeService.isDark ? Qt.rgba(90/255, 200/255, 130/255, 0.50)
                                          : Qt.rgba(110/255, 190/255, 145/255, 0.60))
        : ThemeService.pillBorder

    // Dark mode keeps the soft light tints; light mode uses deep variants so the
    // % stays readable on the coloured pill. Charging in light mode is a genuinely
    // pale (opaque) green with dark-green text so it doesn't wash into the wallpaper.
    readonly property color textColor: ThemeService.isDark
        ? (critical ? "#ffd0d0" : warning ? "#ffe8c0" : charging ? "#d8f5e2" : "#d4f1e8")
        : (critical ? "#7a1414" : warning ? "#6e4400" : charging ? "#0d4a26" : "#1c1c1e")

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
            color: root.powerSaver ? (ThemeService.isDark ? "#FFD60A" : "#8a6d00") : root.textColor
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
