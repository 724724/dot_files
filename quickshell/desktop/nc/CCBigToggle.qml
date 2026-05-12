import QtQuick

Rectangle {
    id: btn
    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property bool active: false
    signal clicked()

    readonly property bool dark: ThemeService.isDark
    implicitWidth: 140
    implicitHeight: 110
    radius: 14

    color: active
        ? (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.85))
        : (dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(1,1,1,0.62))
    border.color: dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.05)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }

    Column {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 14
            leftMargin: 14
        }
        spacing: 8

        Rectangle {
            width: 30; height: 30
            radius: 15
            color: btn.active
                ? "#0A84FF"
                : (dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.06))
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: btn.icon
                color: btn.active ? "#ffffff" : (dark ? "#e0e8f0" : "#3a3a3c")
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 16
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 14
            rightMargin: 14
            bottomMargin: 12
        }
        spacing: 1

        Text {
            text: btn.label
            color: dark ? "#f5f6f8" : "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width
        }

        Text {
            text: btn.sublabel
            color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.50)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            visible: text !== ""
            elide: Text.ElideRight
            width: parent.width
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
