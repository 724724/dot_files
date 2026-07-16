import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets

PillContainer {
    id: root
    clickable: true
    pressed: leftTap.pressed || rightTap.pressed || middleTap.pressed

    visible: MediaService.hasMedia
    implicitHeight: 33
    // 22 = leftMargin (11) + rightMargin (11). The pill's implicitWidth has
    // to budget for both inner margins so the RowLayout actually fits its
    // children — previously it added only 18 against a 23 px margin total,
    // squeezing the title 5 px on the right and making the padding look
    // smaller on that side.
    implicitWidth: visible ? content.implicitWidth + 22 : 0

    // Foreground album-art size: small while paused, full while playing.
    // Animated so the artwork eases between the two sizes. The layout slot it
    // sits in is fixed (see below), so this scaling never changes the pill
    // width — only the artwork inside grows/shrinks.
    readonly property int artSizePlaying: 22
    readonly property int artSizePaused: 13
    property real artSize: MediaService.isPlaying ? artSizePlaying : artSizePaused
    Behavior on artSize { AppleSpring {} }

    // Album art available → use it as the pill's surface + brightness-aware
    // text color. Latches true once a cover has loaded and *stays* true while
    // the next track's cover loads, so changing songs doesn't blink through the
    // placeholder / themed-glass fallback. Drops only when the track genuinely
    // has no art (empty URL).
    property bool artReady: false
    Connections {
        target: MediaService
        function onArtUrlChanged() {
            if (MediaService.artUrl === "") root.artReady = false
        }
    }
    // iOS-style: white text over dark covers, near-black text over bright ones.
    // The backdrop below is near-opaque + heavily blurred, so the pill's
    // brightness reliably tracks the cover's average — which is exactly what
    // MediaService.artDark measures — making this choice readable in practice.
    readonly property color contentColor: artReady
        ? (MediaService.artDark ? "#ffffff" : "#101012")
        : (ThemeService.isDark ? "#ffffff" : ThemeService.fg)

    // Theme-independent surface: when art is present the pill is an opaque
    // frosted base (identical in light & dark) — the near-opaque blurred art
    // below supplies the color, so the pill reads as the album cover rather
    // than the wallpaper behind it. Falls back to the themed glass pill only
    // when there's no art yet.
    color: artReady
        ? (hovered ? Qt.rgba(0.14, 0.14, 0.15, 1.0) : Qt.rgba(0.11, 0.11, 0.12, 1.0))
        : (hovered ? ThemeService.pillBgHover : ThemeService.pillBg)
    border.color: artReady
        ? (hovered ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.16))
        : (hovered ? ThemeService.pillBorderHover : ThemeService.pillBorder)

    // ── Frosted, blurred album-art backdrop (fills the whole pill) ────────────
    // Clipped to the pill's rounded shape; sits behind the content. Near-opaque
    // so the pill's brightness matches the cover; identical in light & dark.
    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: parent.radius
        color: "transparent"
        visible: root.artReady

        Image {
            id: bgArt
            anchors.fill: parent
            source: cover.source
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            cache: true
            asynchronous: true
            sourceSize.width: 256
            sourceSize.height: 256
            visible: false   // rendered once through the material blur below
        }
        MultiEffect {
            visible: true
            anchors.fill: parent
            source: bgArt
            autoPaddingEnabled: false
            // Frosted album-art material. The effect is confined to the tiny
            // media pill and changes only with cover art, so it preserves the
            // Apple-like material without reintroducing a full-screen cost.
            blurEnabled: true
            blur: 0.78
            blurMax: 32
            opacity: 0.90
        }
    }

    RowLayout {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // ── Album art ─────────────────────────────────────────────────────
        // Fixed-size layout slot so the pill width stays constant; the artwork
        // inside scales (and animates) within it, centred.
        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.artSizePlaying
            Layout.preferredHeight: root.artSizePlaying

            Item {
                id: artBox
                anchors.centerIn: parent
                width: root.artSize
                height: root.artSize

                Rectangle {
                    anchors.fill: parent
                    radius: Math.round(parent.width * 0.32)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    visible: !root.artReady
                    Text {
                        anchors.centerIn: parent
                        text: "󰎈"
                        color: root.contentColor
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: Math.round(parent.width * 0.55)
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
                    // Latch the backdrop/foreground on once a cover is ready;
                    // async loading keeps the previous frame painted meanwhile,
                    // so the swap is seamless instead of a placeholder blink.
                    onStatusChanged: if (status === Image.Ready) root.artReady = true
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Math.round(parent.width * 0.32)
                    color: "transparent"
                    visible: root.artReady
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
                    }
                }
            }
        }

        // ── Artist · Title (marquee when too long) ─────────────────────────
        Item {
            id: marquee
            // No title/artist → drop this item entirely (visible:false also
            // collapses the RowLayout spacing) so the album art stays centred.
            visible: marquee.fullText !== ""
            Layout.alignment: Qt.AlignVCenter
            // Cap the visible window at 360px; if title fits we shrink to it.
            readonly property int maxWidth: 360
            readonly property real windowWidth: Math.min(maxWidth, label.implicitWidth)
            Layout.preferredWidth: windowWidth
            Layout.preferredHeight: label.implicitHeight
            clip: true

            // Ease the text-window width between songs so the whole pill grows
            // and shrinks smoothly (and stays in sync) instead of snapping.
            Behavior on Layout.preferredWidth {
                AppleSpring {}
            }

            readonly property string fullText: {
                let a = MediaService.artist
                let t = MediaService.title
                if (a && t) return a + "  •  " + t
                return t || a || ""
            }
            // Measure the scroll against the settled target window width, not the
            // live (Behavior-animated) item width — otherwise the first scroll can
            // capture an oversized distance while the width is still easing in and
            // overshoot far past the end of the text.
            readonly property bool needsScroll: label.implicitWidth > windowWidth + 0.5
            readonly property int scrollDistance: needsScroll ? Math.ceil(label.implicitWidth - windowWidth) : 0

            // When the song changes, snap text back to the start so the next
            // marquee cycle reads the new title from the beginning.
            onFullTextChanged: label.x = 0

            Text {
                id: label
                text: marquee.fullText
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                // Color tracks the album-art brightness (iOS-style) so the text
                // stays legible over the frosted artwork.
                color: root.contentColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // Bounce-style marquee. Both directions share the same constant
            // (linear) speed so the motion feels uniform — no easing, no
            // snap-back. Slow enough to read comfortably.
            SequentialAnimation {
                // Continuous marquee motion prevents VFR from idling the
                // compositor. Long titles remain clipped inside the pill.
                running: false
                loops: Animation.Infinite

                PauseAnimation { duration: 1800 }
                SmoothedAnimation {
                    target: label; property: "x"
                    to: -marquee.scrollDistance
                    velocity: 23
                }
                PauseAnimation { duration: 1500 }
                SmoothedAnimation {
                    target: label; property: "x"
                    to: 0
                    velocity: 23
                }
            }
        }
    }

    TapHandler {
        id: leftTap
        acceptedButtons: Qt.LeftButton
        onTapped: MediaService.playPause()
    }
    TapHandler {
        id: rightTap
        acceptedButtons: Qt.RightButton
        onTapped: MediaService.next()
    }
    TapHandler {
        id: middleTap
        acceptedButtons: Qt.MiddleButton
        onTapped: MediaService.prev()
    }
}
