import Quickshell.Io
import QtQuick

Rectangle {
    id: btn
    required property string icon
    required property string label
    required property string toggleCmd
    required property string stateCmd

    property bool active: false
    readonly property bool dark: ThemeService.isDark

    implicitWidth: 90
    implicitHeight: 72
    radius: 16

    color: active
        ? (dark ? Qt.rgba(10/255, 132/255, 255/255, 0.35) : Qt.rgba(0, 122/255, 255/255, 0.25))
        : (dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06))
    border.color: active
        ? (dark ? Qt.rgba(10/255, 132/255, 255/255, 0.5) : Qt.rgba(0, 122/255, 255/255, 0.4))
        : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }

    Process {
        id: toggleProc
        command: ["bash", "-c", "SWAYNC_TOGGLE_STATE=" + (!btn.active).toString() + " " + btn.toggleCmd]
        onRunningChanged: if (!running) stateProc.running = true
    }

    Process {
        id: stateProc
        command: ["bash", "-c", btn.stateCmd]
        running: true
        stdout: StdioCollector {
            onStreamFinished: btn.active = text.trim() === "true"
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: stateProc.running = true
    }

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.icon
            color: btn.active
                ? (dark ? "#60b8ff" : "#007AFF")
                : (dark ? "#c0ccd8" : "#555555")
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 20
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            color: btn.active
                ? (dark ? "#90d0ff" : "#0055cc")
                : (dark ? "#8899aa" : "#666666")
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggleProc.running = true
    }
}
