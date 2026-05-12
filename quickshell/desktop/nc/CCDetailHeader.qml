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
            ? (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
            : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: "󰅁"
            color: dark ? "#f0f3f6" : "#1c1c1e"
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
        color: dark ? "#f5f6f8" : "#1c1c1e"
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

        // Action button (refresh / scan)
        Rectangle {
            visible: root.actionIcon !== ""
            width: 28; height: 28; radius: 14
            color: actionMa.containsMouse
                ? (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                : (dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03))
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                id: actionGlyph
                anchors.centerIn: parent
                text: root.actionIcon
                color: dark ? "#f0f3f6" : "#1c1c1e"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14

                // Busy spin
                RotationAnimation on rotation {
                    running: root.actionBusy
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
                onRotationChanged: if (!root.actionBusy) rotation = 0
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
