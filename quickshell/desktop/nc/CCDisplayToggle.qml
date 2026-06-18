import QtQuick

// A large round icon button with a label underneath — the building block of the
// Display dropdown (Dark Mode / Night Shift), styled after macOS Control Center.
Item {
    id: root
    property string icon: ""
    property string label: ""
    property bool active: false
    signal clicked()

    readonly property bool dark: ThemeService.isDark
    implicitWidth: 96
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            width: 54; height: 54; radius: 27
            color: root.active
                ? "#0A84FF"
                : (root.dark ? Qt.rgba(1,1,1,0.16) : Qt.rgba(0,0,0,0.10))
            Behavior on color { ColorAnimation { duration: 150 } }

            // Hover / pressed feedback.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ma.pressed ? Qt.rgba(0,0,0,0.18)
                     : ma.containsMouse ? Qt.rgba(1,1,1,0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.active ? "#ffffff" : (root.dark ? "#e6ebf2" : "#3a3a3c")
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 22
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
