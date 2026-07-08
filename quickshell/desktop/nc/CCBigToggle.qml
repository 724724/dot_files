import QtQuick

Rectangle {
    id: btn
    property string icon: ""
    property string label: ""
    property bool active: false
    signal clicked()       // body / chevron → drill into the detail menu
    signal iconClicked()   // icon circle → instant on/off toggle

    readonly property bool dark: ThemeService.isDark
    implicitWidth: 140
    implicitHeight: 110
    radius: 14

    // Tile stays neutral whether DND is on or off — only the icon lights up.
    color: ThemeService.tileBg
    border.color: ThemeService.tileStroke
    border.width: 1

    // Body click target — fills the whole tile and sits *beneath* the icon's
    // own hitbox, so clicking the icon toggles while clicking anywhere else
    // opens the detail menu.
    MouseArea {
        id: bodyMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    // Icon circle — vertically centered on the left, independently clickable to
    // flip DND instantly. This is the *only* element that lights up when active.
    Rectangle {
        id: iconBg
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 14
        }
        width: 32; height: 32
        radius: 16
        color: btn.active
            ? "#0A84FF"
            : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.06))
        Behavior on color { ColorAnimation { duration: 150 } }

        // Hover / pressed feedback so the icon reads as its own button.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: iconMa.pressed ? Qt.rgba(0,0,0,0.18)
                 : iconMa.containsMouse ? Qt.rgba(1,1,1,0.12) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.active ? "#ffffff" : (dark ? "#e0e8f0" : "#3a3a3c")
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: iconMa
            anchors.fill: parent
            anchors.margins: -3   // slightly larger, more forgiving hitbox
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.iconClicked()
        }
    }

    // Label to the right of the icon, vertically centered. Renders the caller's
    // newline (e.g. "Do Not\nDisturb") across two lines.
    Text {
        anchors {
            left: iconBg.right
            leftMargin: 12
            right: chevron.left
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        text: btn.label
        color: dark ? "#f5f6f8" : "#1c1c1e"
        font.family: "SF Pro Display"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    // Chevron — signals that the tile drills into a detail menu. Always faintly
    // visible for discoverability, full strength on body hover.
    Text {
        id: chevron
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
            rightMargin: 14
        }
        text: "󰅂"
        color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.35)
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 12
        opacity: bodyMa.containsMouse ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
