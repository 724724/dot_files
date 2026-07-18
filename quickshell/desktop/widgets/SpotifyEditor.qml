import QtQuick

Item {
    id: editor
    property int index: -1
    property int layout: 3
    readonly property var layoutNames: ["Small", "Medium", "Large"]

    implicitWidth: 440
    implicitHeight: content.implicitHeight

    onIndexChanged: reload()

    function reload() {
        if (index < 0) return
        layout = WidgetsService.getData(index).layout || 3
    }

    function pickLayout(value) {
        WidgetsService.setSpotifyLayout(index, value)
        layout = value
    }

    Column {
        id: content
        width: parent.width
        spacing: 16

        Text {
            text: "Spotify Downloader"
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        // ── Size ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            Text {
                text: "Size"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        id: choice
                        required property int index
                        readonly property int value: index + 1
                        width: 92
                        height: 32
                        radius: 9
                        color: editor.layout === value ? Qt.rgba(0.11, 0.73, 0.33, 0.9)
                             : (choiceHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
                        scale: choiceArea.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 22 } }
                        Text {
                            anchors.centerIn: parent
                            text: editor.layoutNames[choice.index]
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                        HoverHandler { id: choiceHover }
                        MouseArea {
                            id: choiceArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: editor.pickLayout(choice.value)
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Spotify only exposes the first 100 tracks of a playlist to apps, so larger "
                + "playlists download up to 100. Already-downloaded tracks are skipped, so you can "
                + "split a big playlist into ≤100-track playlists and run each."
            color: Qt.rgba(1, 1, 1, 0.48)
            wrapMode: Text.WordWrap
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }

        Text {
            width: parent.width
            text: "The download folder is shared by all Spotify widgets. Click its path in any layout to change it."
            color: Qt.rgba(1, 1, 1, 0.48)
            wrapMode: Text.WordWrap
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }
}
