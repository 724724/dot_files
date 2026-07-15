import QtQuick
import ".."

Item {
    id: view
    required property var widget

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 5

        YoutubeHeader { width: parent.width; widget: view.widget; compact: true }
        YoutubeInput {
            id: linkInput
            width: parent.width
            height: 32
            radius: 9
            fieldSize: 11
            widget: view.widget
            showInspect: false
        }
        YoutubeModeSelector { width: parent.width; height: 28; widget: view.widget }
        YoutubeCombo {
            width: parent.width
            height: 32
            widget: view.widget
            model: widget.mediaKind === "video" ? widget.service.videoQualities : widget.service.audioFormats
            currentIndex: widget.optionIndex(model, widget.selectedQuality)
            onActivated: index => widget.setQuality(model[index].id)
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
        YoutubeAction {
            width: parent.width
            widget: view.widget
            inputControl: linkInput
            compact: true
        }
    }
}
