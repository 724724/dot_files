import QtQuick

Item {
    id: root
    property string title: ""
    property bool toggleVisible: false
    property bool toggleChecked: false

    // Optional left-of-toggle icon button (refresh / scan / etc.)
    property string actionIcon: ""
    property bool actionBusy: false

    signal back()
    signal toggled()
    signal actionClicked()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: 40

    // Back button (chevron-left)
    Rectangle {
        id: backBtn
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: 28; height: 28
        radius: 14
        color: backMa.containsMouse
            ? ThemeService.rowBgHover
            : ThemeService.rowBgHoverClear
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: "󰅁"
            color: ThemeService.textPrimary
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 16
        }

        MouseArea {
            id: backMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.back()
        }
    }

    Text {
        anchors {
            left: backBtn.right
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        text: root.title
        color: ThemeService.textPrimary
        font.family: "SF Pro Display"
        font.pixelSize: 15
        font.weight: Font.Bold
    }

    // Right-side cluster: optional action button + toggle switch
    Row {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 8

        // iOS-style "spokes" spinner shown to the LEFT of the action button
        // while busy (12 fading bars), instead of rotating the button's icon.
        Item {
            id: spinner
            visible: root.actionBusy
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14

            Repeater {
                model: 12
                delegate: Rectangle {
                    required property int index
                    width: 2
                    height: 4
                    radius: 1
                    color: ThemeService.textPrimary
                    // Fading trail: one bar leads at full opacity, the rest fade.
                    opacity: (index + 1) / 12
                    x: spinner.width / 2 - width / 2
                    y: 0
                    transform: Rotation {
                        origin.x: 1
                        origin.y: spinner.height / 2
                        angle: index * 30
                    }
                }
            }

            transformOrigin: Item.Center
            RotationAnimation on rotation {
                running: root.actionBusy
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }

        // Action button (refresh / scan)
        Rectangle {
            visible: root.actionIcon !== ""
            width: 28; height: 28; radius: 14
            color: actionMa.containsMouse
                ? ThemeService.rowBgHover
                : ThemeService.rowBg
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                id: actionGlyph
                anchors.centerIn: parent
                text: root.actionIcon
                color: ThemeService.textPrimary
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14
            }

            MouseArea {
                id: actionMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.actionClicked()
            }
        }

        CCSwitch {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.toggleVisible
            checked: root.toggleChecked
            onToggled: root.toggled()
        }
    }
}
