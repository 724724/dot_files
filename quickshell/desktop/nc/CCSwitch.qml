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
        Behavior on x { AppleSpring { spring: 13; epsilon: 0.25 } }
    }

    MouseArea {
        id: switchMa
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    scale: switchMa.pressed ? ThemeService.pressScale : 1
    Behavior on scale { AppleSpring { spring: 13 } }
}
