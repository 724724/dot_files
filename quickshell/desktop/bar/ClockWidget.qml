import Quickshell
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    // Screen this pill lives on, so the popup opens on the right monitor.
    property var screen: null

    // Light the pill up while its clock/calendar popup is open.
    active: ClockService.popupVisible

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            ClockService.targetScreen = root.screen
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
        }

        Text {
            text: Time.time
            color: ThemeService.fg
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            // Tabular (fixed-width) figures so ticking digits keep a constant
            // width — otherwise the proportional glyphs resize the pill each second.
            font.features: { "tnum": 1 }
        }
    }
}
