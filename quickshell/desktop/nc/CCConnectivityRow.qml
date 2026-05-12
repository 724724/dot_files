import QtQuick

Item {
    id: root
    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property bool active: false
    signal iconClicked()
    signal bodyClicked()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: 48

    // Body hover background (shows on body hover only)
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: bodyMa.containsMouse
            ? (dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Icon hitbox = circle area + a small padding
    Rectangle {
        id: iconBg
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 2
        }
        width: 32; height: 32
        radius: 16
        color: root.active ? "#0A84FF"
                           : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.06))

        // Subtle pressed-state highlight
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: iconMa.pressed ? Qt.rgba(0,0,0,0.12) : "transparent"
        }

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.active ? "#ffffff" : (dark ? "#e0e8f0" : "#3a3a3c")
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: iconMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    // Body text + chevron — separate from icon, opens detail
    Column {
        anchors {
            left: iconBg.right
            leftMargin: 12
            right: chevron.left
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 0

        Text {
            text: root.label
            color: dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: root.sublabel
            color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.50)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            visible: text !== ""
            elide: Text.ElideRight
            width: parent.width
        }
    }

    // Right chevron — appears on body hover
    Text {
        id: chevron
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        text: "󰅂"
        color: dark ? Qt.rgba(1,1,1,0.4) : Qt.rgba(0,0,0,0.35)
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 12
        opacity: bodyMa.containsMouse ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Body MouseArea covers everything; we let the icon MouseArea take priority via z-order
    MouseArea {
        id: bodyMa
        anchors {
            left: iconBg.right
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.bodyClicked()
    }
}
