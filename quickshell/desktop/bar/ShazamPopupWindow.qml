import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

// Music Recognition popup that drops from the bar's Shazam button. A single
// iOS-style card: a clickable "Music Recognition" header that kicks off a
// recognition, over a scrollable list of past matches. Each row shows when it
// was found, swapping to View-on-Shazam / delete buttons on hover.
//
// Overlay / dismiss / animation plumbing mirrors ClockPopupWindow so it behaves
// like the rest of the shell's flyouts.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-shazam"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ── Theme tokens (dark/light aware) ──────────────────────────────────
    readonly property bool dark: ThemeService.isDark
    readonly property color cardBg:        ThemeService.bg
    readonly property color cardBorder:    ThemeService.stroke
    readonly property color primaryText:   dark ? "#ffffff" : "#1a1a1a"
    readonly property color secondaryText: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color fadedText:     dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.32)
    readonly property color hoverFill:     dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color rowHoverFill:  dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.035)
    readonly property color dividerCol:    dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color thumbBg:       dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color linkColor:     "#3AA0FF"
    readonly property color trashRed:      dark ? "#FF6961" : "#FF3B30"

    readonly property bool shown: ShazamService.popupVisible

    // Stay mapped briefly after hide so the close animation can finish.
    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: ShazamService
        function onPopupVisibleChanged() {
            if (ShazamService.popupVisible) {
                if (ShazamService.targetScreen) win.screen = ShazamService.targetScreen
                win._surfaceVisible = true
                unmapTimer.stop()
            } else {
                unmapTimer.restart()
            }
        }
    }
    Timer { id: unmapTimer; interval: 200; onTriggered: win._surfaceVisible = false }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShazamService.popupVisible = false

        // Click anywhere outside the card closes the popup.
        MouseArea { anchors.fill: parent; onClicked: ShazamService.popupVisible = false }

        Rectangle {
            id: card
            width: 320
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            clip: true

            readonly property int listMax: 400
            readonly property real listH: ShazamService.count > 0
                ? Math.min(listView.contentHeight, listMax)
                : 84
            implicitHeight: header.height + 1 + listH

            // Drop down centred under the Shazam button, clamped to the screen.
            x: Math.max(8, Math.min(escScope.width - width - 8, ShazamService.anchorX - width / 2))

            // Entrance: fade + slight scale + drop from just under the button.
            transformOrigin: Item.Top
            opacity: win.shown ? 1 : 0
            scale:   win.shown ? 1 : 0.97
            y:       win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on y       { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // Swallow clicks on the card so they don't fall through to the
            // dismiss layer behind it.
            MouseArea { anchors.fill: parent }

            // ── Header: tap to recognize ─────────────────────────────────
            Rectangle {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 54
                radius: 18
                color: headerHover.hovered ? win.hoverFill : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 14; rightMargin: 14
                    }
                    spacing: 10

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        sourceSize.width: 64; sourceSize.height: 64
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: ShazamService.iconUrl
                        // Gentle pulse while listening.
                        opacity: ShazamService.recognizing ? headerPulse : 1
                        property real headerPulse: 1
                        SequentialAnimation on headerPulse {
                            running: ShazamService.recognizing
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.45; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 42
                        spacing: 1

                        Text {
                            text: "Music Recognition"
                            color: win.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: ShazamService.statusMsg !== ""
                                ? ShazamService.statusMsg
                                : ShazamService.count + (ShazamService.count === 1 ? " Song" : " Songs")
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                HoverHandler { id: headerHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: ShazamService.recognize() }
            }

            // ── Divider ──────────────────────────────────────────────────
            Rectangle {
                id: headerDivider
                anchors { top: header.bottom; left: parent.left; right: parent.right }
                anchors.leftMargin: 14; anchors.rightMargin: 14
                height: 1
                color: win.dividerCol
            }

            // ── Empty state ──────────────────────────────────────────────
            Text {
                visible: ShazamService.count === 0
                anchors {
                    top: headerDivider.bottom; left: parent.left; right: parent.right
                    bottom: parent.bottom
                }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: ShazamService.recognizing ? "Listening…" : "No songs recognized yet.\nTap above to identify what's playing."
                color: win.fadedText
                font.family: "SF Pro Display"
                font.pixelSize: 11
                lineHeight: 1.3
            }

            // ── History list ─────────────────────────────────────────────
            ListView {
                id: listView
                visible: ShazamService.count > 0
                anchors {
                    top: headerDivider.bottom; left: parent.left; right: parent.right
                }
                height: card.listH
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ShazamService.history

                delegate: Item {
                    id: rowItem
                    required property int index
                    required property var modelData
                    width: listView.width
                    height: 54

                    readonly property bool isLast: index === ShazamService.count - 1

                    Rectangle {
                        anchors.fill: parent
                        color: rowHover.hovered ? win.rowHoverFill : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    // Album art (rounded).
                    Rectangle {
                        id: thumb
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        width: 38; height: 38; radius: 7
                        color: win.thumbBg

                        Image {
                            id: art
                            anchors.fill: parent
                            source: rowItem.modelData.coverart || ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 76; sourceSize.height: 76
                            smooth: true; asynchronous: true
                            visible: false
                        }
                        Rectangle { id: artMask; anchors.fill: parent; radius: 7; visible: false }
                        OpacityMask {
                            anchors.fill: art
                            source: art
                            maskSource: artMask
                            visible: art.status === Image.Ready
                        }
                    }

                    // Title + artist.
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: thumb.right
                        anchors.leftMargin: 12
                        anchors.right: rightSlot.left
                        anchors.rightMargin: 8
                        spacing: 1

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: rowItem.modelData.title || "Unknown track"
                            color: win.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: rowItem.modelData.artist || ""
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            visible: text !== ""
                        }
                    }

                    // Right slot: relative date, or the action buttons on hover.
                    Item {
                        id: rightSlot
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        width: rowHover.hovered ? actions.width : dateLabel.width
                        height: 28

                        Text {
                            id: dateLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            text: ShazamService.timeLabel(rowItem.modelData.ts)
                            color: win.fadedText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            opacity: rowHover.hovered ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }

                        Row {
                            id: actions
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            spacing: 5
                            opacity: rowHover.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }

                            // View on Shazam (left button).
                            Rectangle {
                                width: 28; height: 28; radius: 7
                                color: openMa.containsMouse
                                    ? Qt.rgba(win.linkColor.r, win.linkColor.g, win.linkColor.b, 0.18)
                                    : win.thumbBg
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: ""   // nf-fa-external-link
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 13
                                    color: openMa.containsMouse ? win.linkColor : win.secondaryText
                                }
                                MouseArea {
                                    id: openMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShazamService.openLink(rowItem.index)
                                }
                            }

                            // Delete (right button).
                            Rectangle {
                                width: 28; height: 28; radius: 7
                                color: trashMa.containsMouse
                                    ? Qt.rgba(win.trashRed.r, win.trashRed.g, win.trashRed.b, 0.18)
                                    : win.thumbBg
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: ""   // nf-fa-trash
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 13
                                    color: trashMa.containsMouse ? win.trashRed : win.secondaryText
                                }
                                MouseArea {
                                    id: trashMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShazamService.remove(rowItem.index)
                                }
                            }
                        }
                    }

                    // Inset separator between rows.
                    Rectangle {
                        visible: !rowItem.isLast
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        height: 1
                        color: win.dividerCol
                    }

                    HoverHandler { id: rowHover }
                }
            }
        }
    }
}
