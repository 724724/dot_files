import QtQuick

Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property color iconBg: "transparent"
    property color iconColor: "#ffffff"
    property bool active: false
    signal clicked()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: 76
    radius: 12

    color: active
        ? (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.85))
        : (dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(1,1,1,0.62))
    border.color: dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.05)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        id: iconCircle
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 12
            leftMargin: 12
        }
        width: 26; height: 26; radius: 13
        color: tile.iconBg !== "transparent" ? tile.iconBg
            : (tile.active ? "#0A84FF"
                           : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.06)))
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: tile.icon
            color: tile.iconColor !== "#ffffff" ? tile.iconColor
                : (tile.active || tile.iconBg !== "transparent" ? "#ffffff"
                                                                : (dark ? "#e0e8f0" : "#3a3a3c"))
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 12
            rightMargin: 10
            bottomMargin: 10
        }
        spacing: 1

        Text {
            text: tile.label
            color: dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: tile.sublabel
            color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.50)
            font.family: "SF Pro Display"
            font.pixelSize: 10
            visible: text !== ""
            elide: Text.ElideRight
            width: parent.width
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.clicked()
    }
}
