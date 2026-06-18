import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property Notification notification
    property bool inControlCenter: false

    // Invoked by the × button. When null, dismisses just this notification.
    // The grouped stack overrides it so a collapsed group's × clears every
    // notification from that app at once.
    property var closeAction: null

    readonly property bool dark: ThemeService.isDark
    readonly property bool hasImage: notification.image && notification.image !== ""
    readonly property bool hasAppIcon: notification.appIcon && notification.appIcon !== ""

    // ── Control-center scroll fade ───────────────────────────────────────────
    // Darkens the card by its position in the scroll viewport, fading toward
    // whichever edge still hides content (bottom when more is below, top once
    // scrolled past the middle). The parent feeds the live scroll metrics; the
    // overlay is clipped to the card's rounded rect, so gaps between cards stay
    // fully transparent — only the cards darken.
    property bool fadeActive: false
    property real fadeViewportH: 1     // scroll viewport height
    property real fadeViewportY: 0     // this card's top within the viewport
    property real fadeScrollFrac: 0    // 0 at top of the list, 1 at the bottom
    property real fadeMax: 0.3         // peak darkness at the far edge
    property real fadeStart: 0.85      // fraction of the viewport kept fully clear;
                                       // the fade ramps in across the remaining tail

    // Darkness at a point `vpY` px down the viewport, keyed to a *fraction* of
    // the viewport height (not a card count): the first `fadeStart` of the area
    // stays fully clear and the fade ramps in across the remaining tail toward
    // the far edge. Crossfaded by scroll position so the clear region sits at
    // the top while there's content below, and at the bottom once past the
    // middle (the unfaded part always hugs the non-hidden end).
    function _fadeAt(vpY) {
        let f = vpY / Math.max(1, fadeViewportH)   // 0 at top → 1 at bottom
        let ramp = Math.max(0.0001, 1 - fadeStart)
        // down: clear over the top `fadeStart`, deepening toward the bottom.
        // up:   clear over the bottom `fadeStart`, deepening toward the top.
        let down = Math.max(0, Math.min(1, (f - fadeStart) / ramp))
        let up   = Math.max(0, Math.min(1, ((1 - f) - fadeStart) / ramp))
        down = down * down * (3 - 2 * down)    // smoothstep for a soft onset
        up   = up * up * (3 - 2 * up)
        return ((1 - fadeScrollFrac) * down + fadeScrollFrac * up) * fadeMax
    }

    implicitWidth: 380
    implicitHeight: cardContent.implicitHeight + 32
    radius: 14

    // Fully opaque so cards stacked behind never bleed through the front one.
    color: ThemeService.bg
    border.color: ThemeService.stroke
    border.width: 1

    Behavior on implicitHeight { NumberAnimation { duration: 150 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Top-right relative timestamp — always at the corner of the card,
    // even when an image preview is rendered.
    Text {
        id: timeText
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 16
            topMargin: 16
        }
        text: NcServer.relativeTime(card.notification.id)
        color: dark ? Qt.rgba(1,1,1,0.4) : Qt.rgba(0,0,0,0.40)
        font.family: "SF Pro Display"
        font.pixelSize: 10
        opacity: hoverArea.containsMouse || closeMa.containsMouse ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 100 } }
        z: 5
    }

    // × close — replaces the timestamp on hover.
    Rectangle {
        id: closeBtn
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 12
            topMargin: 12
        }
        width: 18; height: 18
        radius: 9
        color: dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.10)
        border.color: dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.10)
        border.width: 1
        opacity: hoverArea.containsMouse || closeMa.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
        z: 10

        Text {
            anchors.centerIn: parent
            text: "×"
            color: dark ? "#dcdce0" : "#3a3a3c"
            font.pixelSize: 14
            font.family: "SF Pro Display"
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.closeAction ? card.closeAction() : card.notification.dismiss()
        }
    }

    RowLayout {
        id: cardContent
        anchors {
            fill: parent
            leftMargin: 16
            rightMargin: 16
            topMargin: 16
            bottomMargin: 16
        }
        spacing: 14

        // Avatar — the app icon when set; otherwise the notification's own
        // image (e.g. a screenshot thumbnail) so it identifies the card the way
        // a letter never could; finally an initial. The old right-hand preview
        // is gone, so this single slot carries whatever visual the card has.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 8
            clip: true
            color: dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(0,0,0,0.05)

            // Themed app icon
            Image {
                anchors.fill: parent
                anchors.margins: 4
                source: card.hasAppIcon ? "image://icon/" + card.notification.appIcon : ""
                visible: card.hasAppIcon && status === Image.Ready
                sourceSize.width: 32; sourceSize.height: 32
                smooth: true
                asynchronous: true
            }

            // Notification image, used as the avatar when no app icon is set
            Image {
                anchors.fill: parent
                source: (!card.hasAppIcon && card.hasImage) ? card.notification.image : ""
                visible: !card.hasAppIcon && card.hasImage && status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 72; sourceSize.height: 72
                smooth: true
                asynchronous: true
            }

            // Letter fallback when there is neither an icon nor an image
            Text {
                anchors.centerIn: parent
                text: (card.notification.appName || "?").charAt(0).toUpperCase()
                color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                visible: !card.hasAppIcon && !card.hasImage
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                // Always reserve room for the absolute-positioned timestamp/close
                // in the top-right corner (no right-hand image pushes it in now).
                Layout.rightMargin: 36
                text: (card.notification.appName || "Notification").toUpperCase()
                color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.50)
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: card.notification.summary
                color: dark ? "#f5f6f8" : "#1c1c1e"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: text !== ""
            }

            Text {
                Layout.fillWidth: true
                text: card.notification.body
                color: dark ? Qt.rgba(1,1,1,0.65) : Qt.rgba(0,0,0,0.60)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                visible: text !== ""
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 6
                visible: card.notification.actions.length > 0

                Repeater {
                    model: card.notification.actions
                    delegate: Rectangle {
                        required property NotificationAction modelData
                        height: 26
                        width: actLabel.implicitWidth + 18
                        radius: 13
                        color: actMa.containsMouse
                            ? (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.10))
                            : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: modelData.text
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }
        }

    }

    // Scroll-fade overlay — clipped to the card's rounded rect (radius matches),
    // sampling the global fade at the card's top and bottom viewport positions.
    // Non-interactive, so buttons underneath stay clickable.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        z: 100
        visible: card.fadeActive
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, card._fadeAt(card.fadeViewportY)) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, card._fadeAt(card.fadeViewportY + card.height)) }
        }
    }
}
