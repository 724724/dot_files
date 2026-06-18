import QtQuick

Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property string sublabel: ""        // optional second line (e.g. a value)
    property color iconBg: "transparent"     // unset = auto (active→blue, else faint)
    property color iconColor: "transparent"  // unset = auto (white on a bg, else dim)
    property bool active: false
    property bool showChevron: false    // hint that the tile drills into a detail
    property bool iconToggle: false     // icon circle is its own on/off button
    signal clicked()
    signal iconClicked()                // only fired when iconToggle is true

    readonly property bool dark: ThemeService.isDark
    implicitHeight: 76
    radius: 12

    // A custom icon background / colour counts as "set" only when it isn't fully
    // transparent. Comparing a `color` value to the string "transparent" never
    // matches (different types), so test the alpha channel instead.
    readonly property bool hasIconBg: tile.iconBg.a > 0
    readonly property bool hasIconColor: tile.iconColor.a > 0

    color: active
        ? (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.85))
        : (dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(1,1,1,0.62))
    border.color: dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.05)
    border.width: 1
    Behavior on color { ColorAnimation { duration: 150 } }

    // Body click target — fills the tile and sits beneath the icon's own hitbox,
    // so (when iconToggle is on) clicking the icon toggles while clicking
    // elsewhere drills in. Without iconToggle the whole tile just drills in.
    MouseArea {
        id: bodyMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.clicked()
    }

    Rectangle {
        id: iconCircle
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 10
            leftMargin: 12
        }
        width: 32; height: 32; radius: 16
        color: tile.hasIconBg ? tile.iconBg
            : (tile.active ? "#0A84FF"
                           : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.06)))
        // A subtle ring keeps the circle reading as a button when it has no solid
        // fill of its own (inactive auto tiles); solid blue / coloured fills omit it.
        border.width: (!tile.hasIconBg && !tile.active) ? 1 : 0
        border.color: dark ? Qt.rgba(1,1,1,0.22) : Qt.rgba(0,0,0,0.16)
        Behavior on color { ColorAnimation { duration: 150 } }

        // Hover / pressed feedback so the icon reads as its own button.
        Rectangle {
            visible: tile.iconToggle
            anchors.fill: parent
            radius: parent.radius
            color: iconMa.pressed ? Qt.rgba(0,0,0,0.18)
                 : iconMa.containsMouse ? Qt.rgba(1,1,1,0.12) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text: tile.icon
            color: tile.hasIconColor ? tile.iconColor
                : (tile.active || tile.hasIconBg ? "#ffffff"
                                                 : (dark ? "#e0e8f0" : "#3a3a3c"))
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: iconMa
            visible: tile.iconToggle
            enabled: tile.iconToggle
            anchors.fill: parent
            anchors.margins: -3   // slightly larger, more forgiving hitbox
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.iconClicked()
        }
    }

    // Chevron — faintly visible drill-in affordance, full strength on hover.
    Text {
        visible: tile.showChevron
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 14
            rightMargin: 12
        }
        text: "󰅂"
        color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.35)
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 12
        opacity: bodyMa.containsMouse ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 12
            rightMargin: 10
            bottomMargin: 9
        }
        spacing: 1

        Text {
            text: tile.label
            color: dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            visible: tile.sublabel !== ""
            text: tile.sublabel
            color: dark ? Qt.rgba(1,1,1,0.50) : Qt.rgba(0,0,0,0.50)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            elide: Text.ElideRight
            width: parent.width
        }
    }
}
