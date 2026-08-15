import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

// Stem filter sheet — drops from the media pill's EQ meter.
//
// Uncheck a stem and it disappears from the audio in real time. Motion matches
// the Shazam popup (same spring set) so every pill-anchored sheet in the bar
// falls the same way.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-stems"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark
    readonly property color cardBg:        ThemeService.popupBg
    readonly property color cardBorder:    ThemeService.stroke
    readonly property color primaryText:   dark ? "#ffffff" : "#1a1a1a"
    readonly property color secondaryText: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color dividerCol:    dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color rowHoverFill:  dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
    readonly property color accent:        dark ? "#0A84FF" : "#007AFF"

    // Quickshell serves QML from a virtual qrc: filesystem, so relative image
    // URLs resolve to qrc: and fail — assets must be absolute file:// paths.
    readonly property string iconBase: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        let c = (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
        return "file://" + c + "/quickshell/assets/sf-symbols/"
    }

    readonly property bool shown: StemService.popupOpen

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: StemService
        function onPopupOpenChanged() {
            if (StemService.popupOpen) {
                if (StemService.popupScreen) win.screen = StemService.popupScreen
                win._surfaceVisible = true
            }
        }
    }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    // One stem: coloured glyph tile + name + checkbox, mirroring the reference.
    component StemRow: Rectangle {
        id: row
        // SF Symbol PNG under assets/sf-symbols (pre-tinted white).
        property string icon: ""
        property string label: ""
        property string hint: ""
        property color tile: "#4A57C4"
        property bool checked: true
        signal toggled
        // Highlight bleeds 8px into the card padding on each side (matches the
        // Mic Mode sheet) so it never hugs the tile or the checkbox.
        x: -8
        width: parent ? parent.width + 16 : 0
        height: 48
        radius: 10
        color: rowHover.hovered ? win.rowHoverFill : "transparent"
        scale: rowTap.pressed ? 0.985 : 1
        Behavior on scale { AppleSpring { spring: 13 } }

        Rectangle {
            id: tileBox
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 8
            color: row.tile
            opacity: row.checked ? 1 : 0.45
            Behavior on opacity { AppleSpring { spring: 13 } }
            Image {
                anchors.centerIn: parent
                source: row.icon !== "" ? win.iconBase + row.icon : ""
                // Native art is ~40px; cap the drawn box and let it fit inside.
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        Column {
            anchors.left: tileBox.right
            anchors.leftMargin: 11
            anchors.right: box.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: row.label
                color: win.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: row.hint !== ""
                text: row.hint
                color: win.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        // iOS-style checkbox.
        Rectangle {
            id: box
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 5
            color: row.checked ? win.accent : "transparent"
            border.color: row.checked ? win.accent : Qt.rgba(0.5, 0.5, 0.5, 0.7)
            border.width: row.checked ? 0 : 1.5
            Behavior on color { ColorAnimation { duration: 110 } }
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Bold
                opacity: row.checked ? 1 : 0
                Behavior on opacity { AppleSpring { spring: 18 } }
            }
        }

        // Individual stems only mean anything while the filter is on.
        opacity: StemService.enabled ? 1 : 0.45
        Behavior on opacity { AppleSpring { spring: 13 } }
        HoverHandler { id: rowHover; enabled: StemService.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: rowTap; enabled: StemService.enabled; onTapped: row.toggled() }
    }

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: StemService.popupOpen = false

        MouseArea {
            anchors.fill: parent
            onClicked: StemService.popupOpen = false
        }

        Rectangle {
            id: card
            width: 292
            height: col.implicitHeight + 32
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 10

            x: Math.max(10, Math.min(StemService.popupAnchorX - width / 2,
                                     win.width - width - 10))
            // Same drop as the Shazam sheet.
            transformOrigin: Item.Top
            opacity: win.shown ? 1 : 0
            scale:   win.shown ? 1 : 0.97
            y:       win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            Behavior on opacity { AppleSpring { spring: 11 } }
            Behavior on scale { AppleSpring { spring: 10 } }
            Behavior on y { AppleSpring {} }
            visible: opacity > 0.002
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 20
                samples: 41
                verticalOffset: 7
                color: Qt.rgba(0, 0, 0, win.dark ? 0.46 : 0.24)
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 2

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        id: stemsTitle
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Stems"
                        color: win.primaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.letterSpacing: -0.2
                    }

                    // Same iOS spokes spinner the Wi-Fi/Bluetooth panels use
                    // while scanning. Shown until the active model reports ready.
                    Item {
                        id: prepSpinner
                        visible: StemService.preparing
                        anchors.left: stemsTitle.right
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        Repeater {
                            model: 12
                            delegate: Rectangle {
                                required property int index
                                width: 2
                                height: 4
                                radius: 1
                                color: win.primaryText
                                opacity: (index + 1) / 12
                                x: prepSpinner.width / 2 - width / 2
                                y: 0
                                transform: Rotation {
                                    origin.x: 1
                                    origin.y: prepSpinner.height / 2
                                    angle: index * 30
                                }
                            }
                        }
                        transformOrigin: Item.Center
                        RotationAnimation on rotation {
                            running: prepSpinner.visible
                            from: 0; to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    // Off | Speed | Quality in one control. "Off" is the master
                    // switch; Speed/Quality both run on the GPU and trade window
                    // length (latency) for separation quality.
                    Rectangle {
                        id: modeSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 138
                        height: 24
                        radius: 12
                        color: win.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)

                        readonly property var segs: [{ id: "off", label: "Off" },
                            { id: "speed", label: "Speed" }, { id: "quality", label: "Quality" }]
                        readonly property int segIndex: StemService.segment === "quality" ? 2
                            : (StemService.segment === "speed" ? 1 : 0)
                        readonly property real seg: width / 3

                        Rectangle {
                            width: modeSwitch.seg - 4
                            height: parent.height - 4
                            radius: height / 2
                            y: 2
                            x: 2 + modeSwitch.segIndex * modeSwitch.seg
                            // Neutral pill for Off so it doesn't look "engaged".
                            color: modeSwitch.segIndex === 0
                                ? (win.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.20))
                                : win.accent
                            Behavior on x { AppleSpring { spring: 13 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: modeSwitch.segs
                                delegate: Item {
                                    required property var modelData
                                    width: modeSwitch.seg
                                    height: modeSwitch.height
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: StemService.segment === modelData.id
                                            ? "#ffffff" : win.secondaryText
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: StemService.setSegment(modelData.id) }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: 5 }
                Rectangle { width: parent.width; height: 1; color: win.dividerCol }
                Item { width: 1; height: 3 }

                StemRow {
                    icon: "music.mic.png"
                    label: "Vocals"
                    tile: "#1FA39A"
                    checked: StemService.vocals
                    onToggled: StemService.toggle("vocals")
                }
                Rectangle { width: parent.width; height: 1; color: win.dividerCol }
                StemRow {
                    icon: "metronome.png"
                    label: "Drums"
                    tile: "#2E7CB8"
                    checked: StemService.drums
                    onToggled: StemService.toggle("drums")
                }
                Rectangle { width: parent.width; height: 1; color: win.dividerCol }
                StemRow {
                    icon: "hifispeaker.fill.png"
                    label: "Bass"
                    tile: "#4A57C4"
                    checked: StemService.bass
                    onToggled: StemService.toggle("bass")
                }
                Rectangle { width: parent.width; height: 1; color: win.dividerCol }
                StemRow {
                    icon: "waveform.png"
                    label: "Other"
                    hint: "Piano, synths, guitars"
                    tile: "#5B3FBF"
                    checked: StemService.other
                    onToggled: StemService.toggle("other")
                }

                Item { width: 1; height: 6 }
                Text {
                    width: parent.width
                    text: StemService.mode === "quality"
                        ? "Quality · ~3s delay · deeper, cleaner separation"
                        : "Speed · ~1s delay · responsive separation"
                    color: win.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: StemService.processorState === "starting"
                    width: parent.width
                    text: "Preparing Stem Filter…"
                    color: win.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    opacity: 0.8
                    wrapMode: Text.Wrap
                }
                Text {
                    visible: StemService.processorState === "error"
                    width: parent.width
                    text: StemService.processorError
                    color: win.dark ? "#FF6961" : "#D70015"
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
