import Quickshell
import Quickshell.Io
import QtQuick
import "spotify" as Spotify

// Spotify downloader card. Exposes the same widget interface the shared combo
// (youtube/YoutubeCombo) and the spotify/ subcomponents bind to. Single large
// layout for now (708×464), matching the YouTube downloader's large card.
Item {
    id: root

    property var frame
    readonly property var widgetData: frame ? frame.dataObj : ({})
    readonly property var service: SpotifyService
    readonly property int layout: widgetData.layout || 3
    property color cardColor: ThemeService.cardBg
    property bool lightCard: !ThemeService.isDark
    property string inputValue: widgetData.url || ""
    property string audioFormat: {
        let value = widgetData.audioFormat || "mp3"
        return ["mp3", "m4a", "flac", "opus", "wav"].indexOf(value) >= 0 ? value : "mp3"
    }
    property string bitrate: widgetData.bitrate || "auto"
    property string cookieBrowser: widgetData.cookieBrowser || "auto"
    readonly property color foreground: ThemeService.label
    readonly property color secondary: ThemeService.secondaryLabel
    readonly property color tertiary: ThemeService.tertiaryLabel
    readonly property color surface: ThemeService.isDark ? "#2c2c2e" : "#f2f2f7"
    readonly property color raised: ThemeService.isDark ? "#3a3a3c" : "#e5e5ea"
    readonly property color accent: "#1DB954"   // Spotify green
    readonly property bool hasMetadata: service.inspectedInput === inputValue
                                        && service.metadata && service.metadata.ok === true
    // Entity kind derived straight from the pasted URL, so the card can label
    // itself (Track / Album / Playlist / Artist) even before Get Info returns.
    readonly property string contentKind: {
        let u = inputValue.toLowerCase()
        if (u.indexOf("/album/") >= 0 || u.indexOf(":album:") >= 0) return "album"
        if (u.indexOf("/playlist/") >= 0 || u.indexOf(":playlist:") >= 0) return "playlist"
        if (u.indexOf("/artist/") >= 0 || u.indexOf(":artist:") >= 0) return "artist"
        return "track"
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
            audioFormat: audioFormat,
            bitrate: bitrate,
            cookieBrowser: cookieBrowser
        })
    }

    function updateInput(value) {
        inputValue = (value || "").trim()
        saveOptions()
    }

    function setFormat(id) {
        audioFormat = id
        saveOptions()
    }

    function setBitrate(id) {
        bitrate = id
        saveOptions()
    }

    function setCookieBrowser(id) {
        cookieBrowser = id
        saveOptions()
    }

    function inspect(value) {
        updateInput(value)
        service.inspect(inputValue)
    }

    function download(value) {
        updateInput(value)
        service.start(inputValue, audioFormat, bitrate, cookieBrowser)
    }

    function kindLabel(kind) {
        kind = kind || "track"
        return kind.charAt(0).toUpperCase() + kind.slice(1)
    }

    function metadataLine() {
        if (!hasMetadata) return service.inspectError || "Fetch info to preview this Spotify link."
        let kind = service.metadata.kind || contentKind
        if (service.metadata.isPlaylist && Number(service.metadata.entryCount) > 0)
            return kindLabel(kind) + " · " + Number(service.metadata.entryCount) + " tracks"
        return kindLabel(kind)
    }

    function sourceLine() {
        if (!hasMetadata) return ""
        let kind = service.metadata.kind || contentKind
        return Number(service.metadata.duration) > 0
            ? kindLabel(kind) + " · " + service.formatDuration(service.metadata.duration)
            : kindLabel(kind)
    }

    function resultLine() {
        let result = service.mediaSummary()
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

    Component { id: smallLayout;  Spotify.SpotifySmall  { widget: root } }
    Component { id: mediumLayout; Spotify.SpotifyMedium { widget: root } }
    Component { id: largeLayout;  Spotify.SpotifyLarge  { widget: root } }

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
