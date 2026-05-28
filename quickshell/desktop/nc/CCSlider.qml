import QtQuick

Item {
    id: root
    property string label: ""
    property string icon: ""
    property real value: 50
    property real minimum: 0
    property real maximum: 100
    signal moved(real newValue)

    readonly property bool dark: ThemeService.isDark
    implicitHeight: titleText.implicitHeight + 12 + 28

    Text {
        id: titleText
        text: root.label
        color: dark ? "#e8eaed" : "#1c1c1e"
        font.family: "SF Pro Display"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        anchors { left: parent.left; top: parent.top }
    }

    // Track
    Rectangle {
        id: track
        anchors {
            left: parent.left
            right: parent.right
            top: titleText.bottom
            topMargin: 10
        }
        height: 28
        radius: 14
        // Light mode: a clearer gray so the track doesn't disappear into the
        // near-white panel behind it (iOS/macOS slider look).
        color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.14)

        // Fill — grows from left edge based on value, but always at least
        // 28px wide so the icon thumb area stays solid even at value=0.
        Rectangle {
            id: fill
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.max(parent.height,
                  parent.width * (root.value - root.minimum) / (root.maximum - root.minimum))
            radius: parent.radius
            color: dark ? "#f4f5f7" : "#ffffff"
            // Outline the fill in both modes so its level edge reads clearly
            // against the track and the panel behind it.
            border.width: 1
            border.color: dark ? Qt.rgba(0,0,0,0.13) : Qt.rgba(0,0,0,0.07)
            Behavior on width { NumberAnimation { duration: 60 } }
        }

        // Icon thumb — fixed at the left edge, perfectly centered in a 28×28
        // box so glyph metric quirks never push the icon off-axis.
        Item {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.height

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: "#1c1c1e"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            function emitFromX(x) {
                let ratio = Math.max(0, Math.min(1, x / width))
                let v = root.minimum + ratio * (root.maximum - root.minimum)
                root.value = v
                root.moved(v)
            }

            onPressed: emitFromX(mouseX)
            onPositionChanged: if (pressed) emitFromX(mouseX)
        }
    }
}
