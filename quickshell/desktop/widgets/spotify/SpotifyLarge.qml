import QtQuick
import ".."
import "../youtube" as Youtube

Item {
    id: view
    required property var widget

    Item {
        anchors.fill: parent
        anchors.margins: 20

        SpotifyHeader {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            widget: view.widget
        }
        SpotifyInput {
            id: linkInput
            anchors { left: parent.left; right: parent.right; top: header.bottom; topMargin: 12 }
            widget: view.widget
        }
        Row {
            id: content
            anchors { left: parent.left; right: parent.right; top: linkInput.bottom; topMargin: 14 }
            height: 222
            spacing: 18

            Rectangle {
                width: 274
                height: parent.height
                radius: 13
                color: widget.surface
                clip: true

                Image {
                    id: cover
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 154
                    source: widget.hasMetadata ? widget.service.metadata.thumbnail || "" : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 154
                    visible: !cover.visible
                    color: ThemeService.isDark ? "#18181a" : "#e5e5ea"
                    Text {
                        anchors.centerIn: parent
                        text: widget.service.inspecting ? ("Fetching " + widget.contentKind + "…") : "♫"
                        color: widget.service.inspecting ? widget.secondary : widget.alpha(widget.accent, 0.8)
                        font.family: "SF Pro Display"
                        font.pixelSize: widget.service.inspecting ? 13 : 40
                    }
                }
                Rectangle {
                    visible: widget.hasMetadata && !widget.service.metadata.isPlaylist
                             && Number(widget.service.metadata.duration) > 0
                    anchors { right: parent.right; bottom: metadataBlock.top; margins: 8 }
                    width: durationText.implicitWidth + 10
                    height: 21
                    radius: 6
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Text {
                        id: durationText
                        anchors.centerIn: parent
                        text: widget.service.formatDuration(widget.service.metadata.duration)
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
                Column {
                    id: metadataBlock
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                    spacing: 4
                    Text {
                        width: parent.width
                        text: widget.hasMetadata ? widget.service.metadata.title
                                                 : (widget.kindLabel(widget.contentKind) + " information")
                        color: widget.foreground
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: widget.metadataLine()
                        color: widget.service.inspectError ? ThemeService.accent("red") : widget.secondary
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                    }
                }
            }

            Column {
                width: parent.width - 292
                spacing: 14

                Text {
                    text: "AUDIO OUTPUT"
                    color: widget.secondary
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5
                }
                Row {
                    width: parent.width
                    spacing: 10
                    Column {
                        width: (parent.width - 20) / 3
                        spacing: 6
                        Text {
                            text: "FORMAT"
                            color: widget.secondary
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.45
                        }
                        Youtube.YoutubeCombo {
                            width: parent.width
                            widget: view.widget
                            model: widget.service.audioFormats
                            currentIndex: widget.optionIndex(model, widget.audioFormat)
                            onActivated: index => widget.setFormat(model[index].id)
                        }
                    }
                    Column {
                        width: (parent.width - 20) / 3
                        spacing: 6
                        Text {
                            text: "BITRATE"
                            color: widget.secondary
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.45
                        }
                        Youtube.YoutubeCombo {
                            width: parent.width
                            widget: view.widget
                            model: widget.service.bitrates
                            currentIndex: widget.optionIndex(model, widget.bitrate)
                            onActivated: index => widget.setBitrate(model[index].id)
                        }
                    }
                    Column {
                        width: (parent.width - 20) / 3
                        spacing: 6
                        Text {
                            text: "BROWSER COOKIES"
                            color: widget.secondary
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.45
                        }
                        Youtube.YoutubeCombo {
                            width: parent.width
                            widget: view.widget
                            model: widget.service.browserOptions()
                            currentIndex: widget.optionIndex(model, widget.cookieBrowser)
                            onActivated: index => widget.setCookieBrowser(model[index].id)
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 68
                    radius: 11
                    color: widget.surface
                    Row {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: widget.service.available ? ThemeService.accent("green") : ThemeService.accent("red")
                        }
                        Column {
                            width: parent.width - 18
                            spacing: 2
                            Text {
                                width: parent.width
                                text: widget.service.available
                                    ? "Ready · yt-dlp · " + widget.service.cookieStatus(widget.cookieBrowser)
                                    : "yt-dlp not found"
                                color: widget.foreground
                                elide: Text.ElideRight
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width
                                text: widget.service.available
                                    ? (widget.metadataLine() + (widget.sourceLine() ? " · " + widget.sourceLine() : ""))
                                    : "Install yt-dlp and ffmpeg to enable downloads."
                                color: widget.secondary
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.family: "SF Pro Display"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }

        Item {
            anchors { left: parent.left; right: parent.right; top: content.bottom; topMargin: 14; bottom: parent.bottom }
            Column {
                anchors { left: parent.left; right: action.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 7
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - detail.implicitWidth
                        text: widget.service.error || (widget.service.busy
                            ? (widget.service.title || widget.service.phase)
                            : (widget.service.mediaSummary() || widget.service.phase))
                        color: widget.service.error ? ThemeService.accent("red") : widget.foreground
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Text {
                        id: detail
                        text: Math.round(Math.max(0, Math.min(100, widget.service.progress))) + "%"
                        color: widget.secondary
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: widget.surface
                    clip: true
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, widget.service.progress / 100))
                        height: parent.height
                        radius: parent.radius
                        color: widget.accent
                        Behavior on width { AppleSpring { spring: 24; epsilon: 0.2 } }
                    }
                }
            }
            SpotifyAction {
                id: action
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 126
                widget: view.widget
                inputControl: linkInput
            }
        }
    }
}
