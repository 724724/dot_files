import QtQuick

// A single output-device row in the Sound dropdown: round icon + name, with the
// active device shown as a filled blue circle (macOS Control Center style).
Item {
    id: root
    property string icon: ""
    property string label: ""
    property bool active: false
    signal clicked()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: 40

    // Hover highlight spanning the row.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -6
        anchors.rightMargin: -6
        radius: 8
        color: ma.containsMouse
            ? (dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Rectangle {
        id: circle
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 32; height: 32; radius: 16
        color: root.active
            ? "#0A84FF"
            : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.08))
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.active ? "#ffffff" : (dark ? "#e0e8f0" : "#3a3a3c")
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 15
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Text {
        anchors {
            left: circle.right
            leftMargin: 12
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        text: root.label
        color: dark ? "#f5f6f8" : "#1c1c1e"
        font.family: "SF Pro Display"
        font.pixelSize: 14
        font.weight: root.active ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
