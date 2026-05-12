import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: btn
    required property var workspace

    implicitWidth: Math.max(label.implicitWidth + 24, 36)
    implicitHeight: 33

    color: workspace.focused
        ? Qt.rgba(255/255, 140/255, 130/255, 0.4)
        : workspace.urgent
            ? Qt.rgba(255/255, 100/255, 100/255, 0.5)
            : hover.hovered
                ? Qt.rgba(255/255, 255/255, 255/255, 0.08)
                : "transparent"
    border.color: workspace.focused
        ? Qt.rgba(255/255, 140/255, 130/255, 0.5)
        : "transparent"
    border.width: workspace.focused ? 1 : 0
    radius: 999

    Behavior on color { ColorAnimation { duration: 200 } }

    HoverHandler { id: hover }

    Text {
        id: label
        anchors.centerIn: parent
        text: workspace.name
        color: workspace.focused ? "#ffd4d0" : workspace.urgent ? "#ffffff" : "#8ba3b8"
        font.family: "SF Pro Display"
        font.pixelSize: 11

        Behavior on color { ColorAnimation { duration: 200 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: workspace.activate()
    }
}
