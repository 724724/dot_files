import Quickshell
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    pressed: tap.pressed
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    // Screen this pill lives on, so the popup opens on the right monitor.
    property var screen: null
    readonly property int barLeftMargin: 10

    active: ClockService.popupVisible
        && ClockService.popupSource === "clock"
        && ClockService.targetScreen === root.screen

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: {
            let p = root.mapToItem(null, root.width / 2, root.height)
            ClockService.popupAnchorX = p.x + root.barLeftMargin
            ClockService.targetScreen = root.screen
            ClockService.popupSource = "clock"
            ClockService.popupVisible = !ClockService.popupVisible
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: "󰥔"
            color: ThemeService.fg
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
            opacity: 0.84
        }

        Text {
            text: Time.time
            color: ThemeService.fg
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.08
            font.features: { "tnum": 1 }
        }

        Text {
            text: Time.dateText
            color: ThemeService.fgDim
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 0.12
        }
    }
}
