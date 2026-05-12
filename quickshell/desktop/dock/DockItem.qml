import Quickshell.Io
import QtQuick

Item {
    id: item

    property string name: ""
    property string wmClass: ""
    property string iconName: ""
    property var execCmd: []
    property bool dark: true
    // Direct reference to DockWindow — avoids signals with complex var types
    property var dockWin: null

    implicitWidth: 58
    implicitHeight: 66

    readonly property bool isRunning: DockService.runningClasses.indexOf(wmClass.toLowerCase()) >= 0
    readonly property bool isFocused: DockService.focusedClass === wmClass.toLowerCase()
    readonly property var windows: DockService.clientsByClass[wmClass.toLowerCase()] || []

    // Bounce animation (launch feedback)
    property real bounceY: 0
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: item; property: "bounceY"; to: -14; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounceY"; to: 0;   duration: 80;  easing.type: Easing.InQuad }
        NumberAnimation { target: item; property: "bounceY"; to: -9;  duration: 85;  easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounceY"; to: 0;   duration: 70;  easing.type: Easing.InQuad }
        NumberAnimation { target: item; property: "bounceY"; to: -5;  duration: 70;  easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounceY"; to: 0;   duration: 60;  easing.type: Easing.InQuad }
    }

    HoverHandler { id: hover }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 6
        width: 52; height: 52; radius: 13
        color: hover.hovered
            ? (dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.08))
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Image {
        id: iconImg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 12
        width: 42; height: 42
        source: "image://icon/" + item.iconName
        smooth: true; mipmap: true
        transform: [
            Translate { y: item.bounceY },
            Scale {
                origin.x: iconImg.width / 2; origin.y: iconImg.height / 2
                xScale: hover.hovered ? 1.12 : 1.0
                yScale: hover.hovered ? 1.12 : 1.0
                Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            }
        ]
    }

    // Running indicator — macOS-style dot below icon
    // Blue for focused window, white (or dark in light mode) for other running apps
    Rectangle {
        visible: item.isRunning
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
        width:  item.isFocused ? 6 : 4
        height: width
        radius: 999
        color: item.isFocused
            ? "#0A84FF"
            : (dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.50))
        Behavior on width  { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color  { ColorAnimation  { duration: 140 } }

        // Subtle glow when focused
        Rectangle {
            visible: item.isFocused
            anchors.centerIn: parent
            width: parent.width + 4; height: parent.height + 4
            radius: 999
            color: "transparent"
            border.color: Qt.rgba(10/255, 132/255, 255/255, 0.35)
            border.width: 1
            z: -1
        }
    }

    Process { id: focusProc;  command: ["hyprctl", "dispatch", "focuswindow", "class:" + item.wmClass] }
    Process { id: launchProc; command: item.execCmd.length > 0 ? item.execCmd : ["true"] }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            let wins = item.windows
            if (wins.length > 1 && item.isRunning) {
                // Multiple windows → toggle preview, anchored to this icon's center
                if (item.dockWin) {
                    let p = item.mapToItem(item.dockWin.contentItem, item.width / 2, 0)
                    item.dockWin.togglePreview(item.wmClass, item.iconName, p.x)
                }
            } else if (item.isRunning) {
                if (item.dockWin) item.dockWin.previewOpen = false
                focusProc.running = true
            } else if (item.execCmd.length > 0) {
                bounceAnim.restart()
                launchProc.running = true
            }
        }
    }
}
