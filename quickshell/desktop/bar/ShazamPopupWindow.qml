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
    readonly property color cardBg:        ThemeService.popupBg
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
    // Fully opaque menu surface: the dropdown draws over the history list
    // inside the same window, so a translucent bg would let rows show through.
    readonly property color menuBg:        dark ? "#262626" : "#f2f2f2"

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
            } else {
                card.srcMenuOpen = false
            }
        }
    }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShazamService.popupVisible = false

        // Click anywhere outside the card closes the popup.
        MouseArea { anchors.fill: parent; onPressed: ShazamService.popupVisible = false }

        Rectangle {
            id: card
            width: 320
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            clip: true

            // Whether the audio-source dropdown (Internal / External) is open.
            property bool srcMenuOpen: false

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
            Behavior on opacity { AppleSpring { spring: 11 } }
            Behavior on scale { AppleSpring { spring: 10 } }
            Behavior on y { AppleSpring {} }
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false

            // Swallow clicks on the card so they don't fall through to the
            // dismiss layer behind it; a stray click also closes the dropdown.
            MouseArea { anchors.fill: parent; onPressed: card.srcMenuOpen = false }

            // ── Header: tap to recognize ─────────────────────────────────
            Rectangle {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 54
                radius: 18
                color: (headerHover.hovered && !srcMa.containsMouse) ? win.hoverFill : "transparent"
                scale: headerTap.pressed ? 0.985 : 1
                Behavior on scale { AppleSpring { spring: 13 } }

                Row {
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 14; rightMargin: 14 + srcBtn.width + 8
                    }
                    spacing: 10

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        sourceSize.width: 64; sourceSize.height: 64
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: ShazamService.iconUrl
                        opacity: ShazamService.recognizing ? 0.58 : 1
                        Behavior on opacity { AppleSpring { spring: 7 } }
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
                TapHandler {
                    id: headerTap
                    onTapped: {
                        card.srcMenuOpen = false
                        ShazamService.recognize()
                    }
                }

                // Audio-source dropdown button: Internal (system audio) vs
                // External (microphone). Its MouseArea accepts the press, so
                // clicking it never triggers the header's recognize tap.
                Rectangle {
                    id: srcBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: srcBtnRow.width + 18
                    height: 24
                    radius: 12
                    scale: srcMa.pressed ? ThemeService.pressScale : 1
                    color: (srcMa.containsMouse || card.srcMenuOpen) ? win.hoverFill : win.thumbBg
                    Behavior on scale { AppleSpring { spring: 13 } }

                    Row {
                        id: srcBtnRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ShazamService.audioSource === "external" ? "External" : "Internal"
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""   // nf-fa-chevron_down
                            color: win.fadedText
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 8
                            rotation: card.srcMenuOpen ? 180 : 0
                            Behavior on rotation { AppleSpring { spring: 11 } }
                        }
                    }

                    MouseArea {
                        id: srcMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.srcMenuOpen = !card.srcMenuOpen
                    }
                }
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
                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                rebound: Transition {
                    SpringAnimation {
                        properties: "x,y"
                        spring: 8
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
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
                            Behavior on opacity { AppleSpring { spring: 13 } }
                        }

                        Row {
                            id: actions
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            spacing: 5
                            opacity: rowHover.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { AppleSpring { spring: 13 } }

                            // View on Shazam (left button).
                            Rectangle {
                                id: openButton
                                width: 28; height: 28; radius: 7
                                scale: openMa.pressed ? ThemeService.pressScale : 1
                                color: openMa.containsMouse
                                    ? Qt.rgba(win.linkColor.r, win.linkColor.g, win.linkColor.b, 0.18)
                                    : win.thumbBg
                                Behavior on scale { AppleSpring { spring: 13 } }
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
                                id: trashButton
                                width: 28; height: 28; radius: 7
                                scale: trashMa.pressed ? ThemeService.pressScale : 1
                                color: trashMa.containsMouse
                                    ? Qt.rgba(win.trashRed.r, win.trashRed.g, win.trashRed.b, 0.18)
                                    : win.thumbBg
                                Behavior on scale { AppleSpring { spring: 13 } }
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

            // ── Audio-source dropdown menu ───────────────────────────────
            // Drops from the header's Internal/External button, above the
            // history list. Sized to stay within the card even when empty.
            Rectangle {
                id: srcMenu
                anchors.top: header.bottom
                anchors.topMargin: 2
                anchors.right: parent.right
                anchors.rightMargin: 12
                width: 172
                height: srcMenuCol.height + 8
                radius: 10
                color: win.menuBg
                border.color: win.cardBorder
                border.width: 1
                z: 20

                // Soft elevation shadow so the opaque menu reads as a layer
                // floating above the list rather than a flat patch.
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    radius: 14; samples: 29
                    verticalOffset: 3
                    color: Qt.rgba(0, 0, 0, win.dark ? 0.45 : 0.22)
                }

                transformOrigin: Item.Top
                opacity: card.srcMenuOpen ? 1 : 0
                scale:   card.srcMenuOpen ? 1 : 0.95
                visible: opacity > 0
                Behavior on opacity { AppleSpring { spring: 11 } }
                Behavior on scale { AppleSpring { spring: 10 } }

                Column {
                    id: srcMenuCol
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 4 }

                    Repeater {
                        model: [
                            { key: "internal", label: "Internal", sub: "System audio" },
                            { key: "external", label: "External", sub: "Microphone" }
                        ]

                        delegate: Rectangle {
                            id: srcOpt
                            required property var modelData
                            width: srcMenuCol.width
                            height: 36
                            radius: 7
                            scale: optMa.pressed ? ThemeService.pressScale : 1
                            color: optMa.containsMouse ? win.hoverFill : "transparent"
                            Behavior on scale { AppleSpring { spring: 13 } }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                spacing: 0

                                Text {
                                    text: srcOpt.modelData.label
                                    color: win.primaryText
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: srcOpt.modelData.sub
                                    color: win.secondaryText
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 9
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                text: ""   // nf-fa-check
                                color: win.linkColor
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 10
                                visible: ShazamService.audioSource === srcOpt.modelData.key
                            }

                            MouseArea {
                                id: optMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    ShazamService.setAudioSource(srcOpt.modelData.key)
                                    card.srcMenuOpen = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
