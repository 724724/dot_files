import QtQuick
import ".."

Item {
    id: header
    required property var widget
    property bool compact: false
    height: compact ? 22 : 28

    Row {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: compact ? 7 : 10
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: compact ? 22 : 26
            height: compact ? 22 : 26
            radius: width / 2
            color: "#1DB954"
            Text {
                anchors.centerIn: parent
                text: ""
                color: "#ffffff"
                font.family: ThemeService.iconFont
                font.pixelSize: compact ? 12 : 15
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: compact ? "Spotify" : "Spotify Downloader"
            color: widget.foreground
            font.family: "SF Pro Display"
            font.pixelSize: compact ? 15 : 21
            font.weight: Font.DemiBold
            font.letterSpacing: compact ? -0.15 : -0.35
        }
    }

    Rectangle {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: compact ? Math.min(92, folderText.implicitWidth + 28) : Math.min(250, folderText.implicitWidth + 34)
        height: compact ? 22 : 28
        radius: compact ? 7 : 9
        color: folderHover.hovered ? widget.raised : widget.surface
        scale: folderArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: ""
                color: widget.secondary
                font.family: ThemeService.iconFont
                font.pixelSize: compact ? 10 : 12
            }
            Text {
                id: folderText
                width: Math.min(compact ? 62 : 190, implicitWidth)
                text: widget.service.outputDir || "Music/Spotify"
                color: widget.secondary
                elide: Text.ElideMiddle
                font.family: "SF Pro Display"
                font.pixelSize: compact ? 9 : 11
            }
        }
        HoverHandler { id: folderHover }
        MouseArea {
            id: folderArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: widget.chooseOutput()
        }
    }
}
