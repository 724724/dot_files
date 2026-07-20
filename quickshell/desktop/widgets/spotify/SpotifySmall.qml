import QtQuick
import ".."
import "../youtube" as Youtube

Item {
    id: view
    required property var widget

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 7

        SpotifyHeader { width: parent.width; widget: view.widget; compact: true }
        SpotifyInput {
            id: linkInput
            width: parent.width
            height: 32
            radius: 9
            fieldSize: 11
            widget: view.widget
            showInspect: false
        }
        Youtube.YoutubeCombo {
            width: parent.width
            height: 32
            widget: view.widget
            model: widget.service.audioFormats
            currentIndex: widget.optionIndex(model, widget.audioFormat)
            onActivated: index => widget.setFormat(model[index].id)
        }
        Row {
            width: parent.width
            height: 32
            spacing: 7
            Youtube.YoutubeCombo {
                width: (parent.width - 7) / 2
                height: parent.height
                widget: view.widget
                model: widget.service.bitrates
                currentIndex: widget.optionIndex(model, widget.bitrate)
                onActivated: index => widget.setBitrate(model[index].id)
            }
            Youtube.YoutubeCombo {
                width: (parent.width - 7) / 2
                height: parent.height
                widget: view.widget
                model: widget.service.browserOptions()
                currentIndex: widget.optionIndex(model, widget.cookieBrowser)
                onActivated: index => widget.setCookieBrowser(model[index].id)
            }
        }
        Text {
            width: parent.width
            height: 14
            text: widget.resultLine()
            color: widget.service.error ? ThemeService.accent("red") : widget.secondary
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            font.family: "SF Pro Display"
            font.pixelSize: 9
        }
        SpotifyAction {
            width: parent.width
            widget: view.widget
            inputControl: linkInput
            compact: true
        }
    }
}
