import QtQuick
import ".."

Rectangle {
    id: action
    required property var widget
    required property var inputControl
    property bool compact: false
    height: compact ? 34 : 42
    radius: compact ? 10 : 12
    color: widget.service.busy
        ? (actionHover.hovered ? ThemeService.accent("red") : widget.alpha(ThemeService.accent("red"), 0.86))
        : (actionHover.hovered ? Qt.lighter(widget.accent, 1.08) : widget.accent)
    opacity: widget.service.busy || (widget.service.available && inputControl.value().trim() !== "") ? 1 : 0.42
    scale: actionArea.pressed ? ThemeService.pressScale : 1
    Behavior on scale { AppleSpring { spring: 22 } }

    Text {
        anchors.centerIn: parent
        text: widget.service.busy ? "Cancel" : (widget.service.available ? "Download" : "yt-dlp missing")
        color: "#ffffff"
        font.family: "SF Pro Display"
        font.pixelSize: compact ? 12 : 13
        font.weight: Font.DemiBold
    }
    Rectangle {
        visible: widget.service.busy || widget.service.progress > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 3
        radius: 1.5
        color: Qt.rgba(1, 1, 1, 0.24)
        clip: true
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, widget.service.progress / 100))
            height: parent.height
            radius: parent.radius
            color: "#ffffff"
            Behavior on width { AppleSpring { spring: 24; epsilon: 0.2 } }
        }
    }
    HoverHandler { id: actionHover }
    MouseArea {
        id: actionArea
        anchors.fill: parent
        enabled: widget.service.busy || (widget.service.available && inputControl.value().trim() !== "")
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: widget.service.busy ? widget.service.cancel() : widget.download(inputControl.value())
    }
}
