import QtQuick

// Vertical three-dot (kebab) button. Emits clicked(); the parent maps its
// position into the panel root and opens the CCContextMenu there.
Item {
    id: dots
    signal clicked()

    readonly property bool dark: ThemeService.isDark
    implicitWidth: 24
    implicitHeight: 24
    scale: ma.pressed ? ThemeService.pressScale : 1
    Behavior on scale { AppleSpring { spring: 13 } }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: ma.containsMouse
            ? (dots.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
            : "transparent"
    }

    Column {
        anchors.centerIn: parent
        spacing: 2.5
        Repeater {
            model: 3
            Rectangle {
                width: 3.2
                height: 3.2
                radius: 1.6
                color: ma.containsMouse
                    ? (dots.dark ? "#f0f3f6" : "#1c1c1e")
                    : (dots.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.45))
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: dots.clicked()
    }
}
