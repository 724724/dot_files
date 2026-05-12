import QtQuick

Item {
    id: root
    property bool checked: false
    signal toggled()

    readonly property bool dark: ThemeService.isDark
    implicitWidth: 42
    implicitHeight: 24

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked
            ? "#34C759"
            : (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.18))
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        width: parent.height - 4
        height: parent.height - 4
        radius: height / 2
        y: 2
        x: root.checked ? (parent.width - width - 2) : 2
        color: "#ffffff"
        border.color: Qt.rgba(0,0,0,0.10)
        border.width: 1
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
