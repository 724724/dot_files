import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

PillContainer {
    id: root

    visible: MediaService.hasMedia
    implicitHeight: 33
    // 22 = leftMargin (11) + rightMargin (11). The pill's implicitWidth has
    // to budget for both inner margins so the RowLayout actually fits its
    // children — previously it added only 18 against a 23 px margin total,
    // squeezing the title 5 px on the right and making the padding look
    // smaller on that side.
    implicitWidth: visible ? content.implicitWidth + 22 : 0

    // Subtle warm tint when playing, neutral glass when paused
    color: hovered
        ? Qt.rgba(255/255, 180/255, 90/255, 0.35)
        : (MediaService.isPlaying
            ? Qt.rgba(255/255, 160/255, 70/255, 0.22)
            : Qt.rgba(30/255, 40/255, 50/255, 0.25))
    border.color: hovered
        ? Qt.rgba(255/255, 180/255, 90/255, 0.55)
        : (MediaService.isPlaying
            ? Qt.rgba(255/255, 170/255, 70/255, 0.45)
            : Qt.rgba(100/255, 210/255, 180/255, 0.3))

    RowLayout {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // ── Album art (rounded) ───────────────────────────────────────────
        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: Qt.rgba(0, 0, 0, 0.20)
                visible: cover.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: "󰎈"
                    color: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 12
                    opacity: 0.7
                }
            }

            // Hidden Image purely for status tracking (the visible art lives
            // inside the ClippingRectangle below — Rectangle.clip alone does
            // *not* clip children to its rounded corners).
            Image {
                id: cover
                anchors.fill: parent
                source: MediaService.artUrl
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                cache: true
                asynchronous: true
                sourceSize.width: 44
                sourceSize.height: 44
                visible: false
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: 7
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: cover.source
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    cache: true
                    asynchronous: true
                    sourceSize.width: 44
                    sourceSize.height: 44
                    visible: cover.status === Image.Ready
                }
            }
        }

        // ── Artist · Title (marquee when too long) ─────────────────────────
        Item {
            id: marquee
            // No title/artist → drop this item entirely (visible:false also
            // collapses the RowLayout spacing) so the album art stays centred.
            visible: marquee.fullText !== ""
            // Cap the visible window at 360px; if title fits we shrink to it.
            Layout.preferredWidth: Math.min(360, label.implicitWidth)
            Layout.preferredHeight: label.implicitHeight
            clip: true

            readonly property string fullText: {
                let a = MediaService.artist
                let t = MediaService.title
                if (a && t) return a + "  •  " + t
                return t || a || ""
            }
            readonly property bool needsScroll: label.implicitWidth > width + 0.5
            readonly property int scrollDistance: needsScroll ? Math.ceil(label.implicitWidth - width) : 0

            // When the song changes, snap text back to the start so the next
            // marquee cycle reads the new title from the beginning.
            onFullTextChanged: label.x = 0

            Text {
                id: label
                text: marquee.fullText
                x: 0
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // Bounce-style marquee. Both directions share the same constant
            // (linear) speed so the motion feels uniform — no easing, no
            // snap-back. Slow enough to read comfortably.
            readonly property int scrollSpeedMsPerPx: 55
            readonly property int scrollDuration:
                Math.max(3500, marquee.scrollDistance * marquee.scrollSpeedMsPerPx)

            SequentialAnimation {
                running: marquee.needsScroll && root.visible
                loops: Animation.Infinite

                PauseAnimation { duration: 1800 }
                NumberAnimation {
                    target: label; property: "x"
                    to: -marquee.scrollDistance
                    duration: marquee.scrollDuration
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 1500 }
                NumberAnimation {
                    target: label; property: "x"
                    to: 0
                    duration: marquee.scrollDuration
                    easing.type: Easing.Linear
                }
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: MediaService.playPause()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: MediaService.next()
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: MediaService.prev()
    }
}
