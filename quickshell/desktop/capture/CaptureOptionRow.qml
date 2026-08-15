pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property string label
    property string detail: ""
    property bool selected: false
    property bool showsDisclosure: false
    property bool dimmed: false
    signal triggered()

    implicitHeight: detail === "" ? 31 : 43
    enabled: !dimmed
    opacity: enabled ? 1 : 0.36

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: tap.pressed ? Qt.rgba(0.03, 0.49, 0.94, 0.24)
            : hover.hovered ? ThemeService.hoverBg : "transparent"

        Behavior on color { ColorAnimation { duration: 70 } }
    }

    Text {
        anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
        width: 18
        text: root.selected ? "✓" : ""
        color: ThemeService.textPrimary
        font.family: "SF Pro Display"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
    }

    Column {
        anchors {
            left: parent.left
            leftMargin: 34
            right: disclosure.left
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        spacing: -1

        Text {
            width: parent.width
            text: root.label
            color: ThemeService.textPrimary
            font.family: "SF Pro Display"
            font.pixelSize: 15
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
        }

        Text {
            visible: root.detail !== ""
            width: parent.width
            text: root.detail
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 10
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
        }
    }

    Text {
        id: disclosure
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: 14
        text: root.showsDisclosure ? "›" : ""
        color: ThemeService.textSecondary
        font.family: "SF Pro Display"
        font.pixelSize: 20
        horizontalAlignment: Text.AlignHCenter
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        enabled: root.enabled
        acceptedButtons: Qt.LeftButton
        onTapped: root.triggered()
    }
}
