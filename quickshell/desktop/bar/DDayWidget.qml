import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root

    property var screen: null
    property bool suppressed: false
    readonly property var item: ClockService.pinnedDday
    readonly property bool hasItem: item !== null && item !== undefined
    readonly property bool shown: hasItem && !suppressed
    readonly property real targetWidth: hasItem ? row.implicitWidth + 20 : 0

    clickable: shown
    pressed: tap.pressed

    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    clip: true
    implicitHeight: 33
    implicitWidth: shown ? targetWidth : 0
    Behavior on opacity { AppleSpring { spring: 18 } }
    Behavior on implicitWidth { AppleSpring { spring: 18; epsilon: 0.1 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "󰃭"
            color: ThemeService.fg
            opacity: 0.84
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 120
            text: root.hasItem ? (root.item.label || "D-Day") : ""
            color: ThemeService.fgDim
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 0.08
            elide: Text.ElideRight
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.hasItem ? ClockService.ddayLabel(root.item) : ""
            color: ThemeService.fg
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.08
            font.features: { "tnum": 1 }
        }
    }

    TapHandler {
        id: tap
        enabled: root.shown
        onTapped: {
            ClockService.requestedPage = 5
            ClockService.popupAnchorX = 0
            ClockService.targetScreen = root.screen
            ClockService.popupSource = "clock"
            ClockService.popupVisible = true
        }
    }
}
