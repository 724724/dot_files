import QtQuick
import ".."

Rectangle {
    id: selector
    required property var widget
    height: 38
    radius: 10
    color: widget.surface

    Row {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 4
        Repeater {
            model: [{ label: "Video", glyph: "", kind: "video" },
                    { label: "Audio", glyph: "", kind: "audio" }]
            delegate: Rectangle {
                id: button
                required property var modelData
                readonly property bool available: !widget.service.busy
                                                  && !(modelData.kind === "video" && widget.musicInput)
                width: (selector.width - 10) / 2
                height: parent.height
                radius: 8
                color: widget.mediaKind === modelData.kind
                    ? (ThemeService.isDark ? "#5a5a5e" : "#ffffff")
                    : (modeHover.hovered ? widget.alpha(widget.raised, 0.72) : "transparent")
                scale: modeArea.pressed ? ThemeService.pressScale : 1
                opacity: available ? 1 : 0.38
                Behavior on scale { AppleSpring { spring: 22 } }
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        text: button.modelData.glyph
                        color: widget.mediaKind === button.modelData.kind ? widget.accent : widget.secondary
                        font.family: ThemeService.iconFont
                        font.pixelSize: 11
                    }
                    Text {
                        text: button.modelData.label
                        color: widget.foreground
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
                HoverHandler { id: modeHover }
                MouseArea {
                    id: modeArea
                    anchors.fill: parent
                    enabled: button.available
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: widget.setKind(button.modelData.kind)
                }
            }
        }
    }
}
