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

    // Magnify on hover, macOS-style. hoverScale drives both the visual Scale
    // (below) and the layout width here, so the widened slot shoves neighbouring
    // icons aside in the Row instead of overlapping them. +16 keeps the icon's
    // 8px side padding constant at any zoom (42 + 16 = 58 when idle).
    readonly property real hoverScale: 1.75
    implicitWidth: 42 * (hover.hovered ? hoverScale : 1) + 16
    implicitHeight: 66
    Behavior on implicitWidth { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }

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
                // Grow upward from the icon's base (not its center), macOS-style,
                // so the icon lifts out of the dock on hover instead of bloating
                // in place. The running dot below is anchored separately and stays.
                origin.x: iconImg.width / 2; origin.y: iconImg.height
                xScale: hover.hovered ? item.hoverScale : 1.0
                yScale: hover.hovered ? item.hoverScale : 1.0
                Behavior on xScale { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
                Behavior on yScale { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
            }
        ]
    }

    // App-name tooltip — small label that floats above the magnified icon on
    // hover, macOS-style. Anchored above parent.top so it sits in the dock
    // window's headroom (DockWindow's non-preview height was raised to make
    // room). z keeps it above neighbouring icons.
    Rectangle {
        id: tooltip
        z: 200
        visible: opacity > 0
        opacity: hover.hovered ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 24
        width: tipLabel.implicitWidth + 16
        height: tipLabel.implicitHeight + 8
        radius: 7
        color: dark ? Qt.rgba(28/255, 28/255, 33/255, 0.96)
                    : Qt.rgba(250/255, 250/255, 250/255, 0.96)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.11)
        border.width: 1
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: item.name
            color: dark ? Qt.rgba(1,1,1,0.95) : Qt.rgba(0,0,0,0.85)
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
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

    // Hyprland's new dispatcher API takes Lua, so the old
    // `dispatch focuswindow class:X` form errors with "')' expected near 'class'".
    Process {
        id: focusProc
        command: ["hyprctl", "dispatch",
                  'hl.dsp.focus({ window = "class:' + item.wmClass + '" })']
    }
    Process { id: launchProc; command: item.execCmd.length > 0 ? item.execCmd : ["true"] }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            let wins = item.windows
            // Guard on wins.length, not isRunning. DockService polls every 500ms
            // and sets clientsByClass + runningClasses sequentially, so isRunning
            // can lag while windows has already updated — leading to a spurious
            // bounce + relaunch when the user clicks a clearly-running icon.
            if (wins.length > 1) {
                // Multiple windows → toggle preview, anchored to this icon's center
                if (item.dockWin) {
                    let p = item.mapToItem(item.dockWin.contentItem, item.width / 2, 0)
                    item.dockWin.togglePreview(item.wmClass, item.iconName, p.x)
                }
            } else if (wins.length === 1 || item.isRunning) {
                if (item.dockWin) item.dockWin.previewOpen = false
                focusProc.running = true
            } else if (item.execCmd.length > 0) {
                bounceAnim.restart()
                launchProc.running = true
            }
        }
    }
}
