import QtQuick
import QtQuick.Layouts
import "../capture" as Capture

PillContainer {
    id: root

    visible: Capture.CaptureService.recording
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 20
    clickable: true
    pressed: tap.pressed
    color: hovered ? Qt.rgba(1, 0.27, 0.23, 0.20)
                   : Qt.rgba(1, 0.27, 0.23, 0.13)
    border.color: hovered ? Qt.rgba(1, 0.27, 0.23, 0.52)
                          : Qt.rgba(1, 0.27, 0.23, 0.34)

    function clockText(seconds) {
        const total = Math.max(0, Number(seconds) || 0)
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const secs = total % 60
        const mm = String(minutes).padStart(2, "0")
        const ss = String(secs).padStart(2, "0")
        return hours > 0 ? String(hours) + ":" + mm + ":" + ss : mm + ":" + ss
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Rectangle {
            Layout.preferredWidth: 9
            Layout.preferredHeight: 9
            radius: 5
            color: "#ff453a"

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.46; duration: 760; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 760; easing.type: Easing.InOutSine }
            }
        }

        Text {
            text: root.clockText(Capture.CaptureService.elapsedSeconds)
            color: ThemeService.isDark ? "#ff6961" : "#d70015"
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    TapHandler {
        id: tap
        onTapped: Capture.CaptureService.stopRecording()
    }
}
