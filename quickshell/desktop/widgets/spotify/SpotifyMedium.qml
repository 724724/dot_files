import QtQuick
import ".."
import "../youtube" as Youtube

Item {
    id: view
    required property var widget

    Item {
        anchors.fill: parent
        anchors.margins: 14

        SpotifyHeader {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            widget: view.widget
            compact: true
        }
        SpotifyInput {
            id: linkInput
            anchors { left: parent.left; right: parent.right; top: header.bottom; topMargin: 7 }
            height: 34
            radius: 9
            fieldSize: 12
            widget: view.widget
        }
        Row {
            id: body
            anchors { left: parent.left; right: parent.right; top: linkInput.bottom; bottom: parent.bottom; topMargin: 8 }
            spacing: 10
            clip: true

            Rectangle {
                id: previewCard
                width: Math.min(132, Math.floor(body.width * 0.32))
                height: parent.height
                radius: 10
                color: widget.surface
                clip: true
                Image {
                    id: cover
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 73
                    source: widget.hasMetadata ? widget.service.metadata.thumbnail || "" : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 73
                    visible: !cover.visible
                    color: ThemeService.isDark ? "#18181a" : "#e5e5ea"
                    Text {
                        anchors.centerIn: parent
                        text: widget.service.inspecting ? "Loading…" : "♫"
                        color: widget.service.inspecting ? widget.secondary : widget.alpha(widget.accent, 0.8)
                        font.family: "SF Pro Display"
                        font.pixelSize: widget.service.inspecting ? 10 : 26
                    }
                }
                Column {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                    spacing: 2
                    Text {
                        width: parent.width
                        text: widget.hasMetadata ? widget.service.metadata.title
                                                 : (widget.kindLabel(widget.contentKind) + " information")
                        color: widget.foreground
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: widget.metadataLine()
                        color: widget.service.inspectError ? ThemeService.accent("red") : widget.secondary
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: 8
                    }
                }
            }

            Column {
                width: Math.max(0, body.width - previewCard.width - body.spacing)
                spacing: 6
                Youtube.YoutubeCombo {
                    width: parent.width
                    height: 30
                    widget: view.widget
                    model: widget.service.bitrates
                    currentIndex: widget.optionIndex(model, widget.bitrate)
                    onActivated: index => widget.setBitrate(model[index].id)
                }
                Row {
                    width: parent.width
                    spacing: 7
                    Youtube.YoutubeCombo {
                        width: parent.width - action.width - 7
                        height: 32
                        widget: view.widget
                        model: widget.service.audioFormats
                        currentIndex: widget.optionIndex(model, widget.audioFormat)
                        onActivated: index => widget.setFormat(model[index].id)
                    }
                    SpotifyAction {
                        id: action
                        width: 96
                        height: 32
                        widget: view.widget
                        inputControl: linkInput
                        compact: true
                    }
                }
                Text {
                    width: parent.width
                    text: widget.service.error || widget.resultLine()
                    color: widget.service.error ? ThemeService.accent("red") : widget.secondary
                    elide: Text.ElideRight
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                }
                Text {
                    width: parent.width
                    text: widget.service.busy
                        ? ((widget.service.speed || widget.service.phase) + (widget.service.eta ? " · " + widget.service.eta + " left" : ""))
                        : (widget.sourceLine() || (widget.service.available ? "Ready" : "yt-dlp not found"))
                    color: widget.tertiary
                    elide: Text.ElideRight
                    font.family: "SF Pro Display"
                    font.pixelSize: 8
                }
            }
        }
    }
}
