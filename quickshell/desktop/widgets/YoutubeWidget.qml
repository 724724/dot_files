import Quickshell
import Quickshell.Io
import QtQuick
import "youtube" as Youtube

Item {
    id: root

    property var frame
    readonly property var widgetData: frame ? frame.dataObj : ({})
    readonly property var service: YoutubeService
    readonly property int layout: widgetData.layout || 3
    property color cardColor: ThemeService.cardBg
    property bool lightCard: !ThemeService.isDark
    property string inputValue: widgetData.url || ""
    property string mediaKind: widgetData.mediaKind || "video"
    property string videoQuality: widgetData.videoQuality || "best"
    property string audioFormat: {
        let value = widgetData.audioFormat || widgetData.audioQuality || "m4a"
        return ["wav", "flac", "m4a", "mp3"].indexOf(value) >= 0 ? value : "m4a"
    }
    property string cookieBrowser: widgetData.cookieBrowser || "auto"
    readonly property color foreground: ThemeService.label
    readonly property color secondary: ThemeService.secondaryLabel
    readonly property color tertiary: ThemeService.tertiaryLabel
    readonly property color surface: ThemeService.isDark ? "#2c2c2e" : "#f2f2f7"
    readonly property color raised: ThemeService.isDark ? "#3a3a3c" : "#e5e5ea"
    readonly property color accent: ThemeService.isDark ? "#ff375f" : "#ff2d55"
    readonly property bool hasMetadata: service.inspectedInput === inputValue
                                        && service.metadata && service.metadata.ok === true
    readonly property bool musicInput: /^https?:\/\/(www\.)?music\.youtube\.com\//i.test(inputValue.trim())
    readonly property string selectedQuality: mediaKind === "video" ? videoQuality : audioFormat

    onMusicInputChanged: {
        if (musicInput && mediaKind === "video") {
            mediaKind = "audio"
            saveOptions()
        }
    }

    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity)
    }

    function optionIndex(options, id) {
        for (let i = 0; i < options.length; i++)
            if (options[i].id === id) return i
        return 0
    }

    function saveOptions() {
        if (frame) frame.save({
            layout: layout,
            url: inputValue,
            mediaKind: mediaKind,
            videoQuality: videoQuality,
            audioFormat: audioFormat,
            cookieBrowser: cookieBrowser
        })
    }

    function updateInput(value) {
        inputValue = (value || "").trim()
        saveOptions()
    }

    function setKind(kind) {
        if (service.busy || mediaKind === kind || (kind === "video" && musicInput)) return
        mediaKind = kind
        saveOptions()
    }

    function setQuality(id) {
        if (mediaKind === "video") videoQuality = id
        else audioFormat = id
        saveOptions()
    }

    function inspect(value) {
        updateInput(value)
        service.inspect(inputValue, cookieBrowser)
    }

    function download(value) {
        updateInput(value)
        if (musicInput && mediaKind !== "audio") {
            mediaKind = "audio"
            saveOptions()
        }
        service.start(inputValue, mediaKind, selectedQuality, cookieBrowser)
    }

    function metadataLine() {
        if (!hasMetadata) return service.inspectError || "Fetch info to view uploader and upload date."
        let uploader = service.metadata.uploader || service.metadata.channel || "YouTube"
        if (service.metadata.isPlaylist)
            return uploader + " · " + Number(service.metadata.entryCount || 0) + " videos"
        let date = service.formatUploadDate(service.metadata.uploadDate)
        return uploader + (date ? " · " + date : "")
    }

    function sourceLine() {
        if (!hasMetadata) return ""
        if (service.metadata.isPlaylist)
            return "Playlist · " + Number(service.metadata.entryCount || 0) + " items"
        if (mediaKind === "video")
            return Number(service.metadata.maxHeight) > 0 ? "Source up to " + service.metadata.maxHeight + "p" : ""
        return Number(service.metadata.maxAudioBitrate) > 0
            ? "Best source selected · up to " + service.metadata.maxAudioBitrate + " kbps"
            : "Best available audio source selected"
    }

    function resultLine() {
        let result = service.mediaSummary(mediaKind)
        return result || (service.busy ? service.phase : metadataLine())
    }

    function chooseOutput() {
        if (folderPicker.running) return
        folderPicker.selection = ""
        folderPicker.command = [
            "zenity", "--file-selection", "--directory",
            "--title=Choose Download Folder",
            "--filename=" + (service.outputDir || Quickshell.env("HOME")) + "/"
        ]
        if (frame && frame.winRef) frame.winRef.closeRequested()
        folderPicker.running = true
    }

    Component.onCompleted: service.refresh()

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: root.cardColor
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.layout === 1 ? smallLayout
                       : root.layout === 2 ? mediumLayout
                       : largeLayout
    }

    Component { id: smallLayout; Youtube.YoutubeSmall { widget: root } }
    Component { id: mediumLayout; Youtube.YoutubeMedium { widget: root } }
    Component { id: largeLayout; Youtube.YoutubeLarge { widget: root } }

    Process {
        id: folderPicker
        property string selection: ""
        stdout: StdioCollector { onStreamFinished: folderPicker.selection = text.trim() }
        onExited: {
            if (folderPicker.selection) root.service.setOutputDirectory(folderPicker.selection)
            if (root.frame && root.frame.winRef) root.frame.winRef.reopenRequested()
        }
    }
}
