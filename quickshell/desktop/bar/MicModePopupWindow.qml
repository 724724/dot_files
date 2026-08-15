import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects
import "../nc" as Nc

// Mic Mode sheet — drops from the bar's orange mic indicator.
//
// The voice-isolation filter chain is a virtual PipeWire source, so switching
// "mode" is really just switching the default input between the real mic and
// the filter in front of it. Presenting it here (rather than as a device in the
// Control Center input list) keeps that list to actual hardware.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-micmode"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark
    readonly property color cardBg:        ThemeService.popupBg
    readonly property color cardBorder:    ThemeService.stroke
    readonly property color primaryText:   dark ? "#ffffff" : "#1a1a1a"
    readonly property color secondaryText: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color hoverFill:     dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color accent:        dark ? "#0A84FF" : "#007AFF"

    // Quickshell serves QML from a virtual qrc: filesystem, so relative image
    // URLs resolve to qrc: and fail — assets must be absolute file:// paths.
    readonly property string iconBase: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        let c = (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
        return "file://" + c + "/quickshell/assets/sf-symbols/"
    }

    readonly property bool shown: PrivacyService.micModeOpen && PrivacyService.micActive

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    Connections {
        target: PrivacyService
        function onMicModeOpenChanged() {
            if (PrivacyService.micModeOpen) {
                if (PrivacyService.micModeScreen) win.screen = PrivacyService.micModeScreen
                Nc.AudioService.refresh()
                win._surfaceVisible = true
            }
        }
        function onMicModeScreenChanged() {
            if (PrivacyService.micModeOpen && PrivacyService.micModeScreen)
                win.screen = PrivacyService.micModeScreen
        }
        // The indicator disappears when the mic is released — take the sheet with it.
        function onMicActiveChanged() {
            if (!PrivacyService.micActive) PrivacyService.micModeOpen = false
        }
    }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    // One selectable mode: round glyph badge + label, tinted while active.
    component ModeRow: Rectangle {
        id: row
        property string icon: ""
        property string label: ""
        property color badge: "#FF9F0A"
        property bool selected: false
        property bool enabled: true
        signal activated
        // The highlight extends 8px past the content column on each side so it
        // doesn't hug the badge and the tick; the content itself stays aligned
        // with the title above.
        x: -8
        width: parent ? parent.width + 16 : 0
        height: 48
        radius: 10
        opacity: enabled ? 1 : 0.4
        color: selected
            ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.20)
            : (rowHover.hovered ? win.hoverFill : "transparent")
        scale: rowTap.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }

        Rectangle {
            id: badgeCircle
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            radius: 13
            color: row.badge
            Image {
                anchors.centerIn: parent
                source: row.icon !== "" ? win.iconBase + row.icon : ""
                width: 15
                height: 15
                sourceSize.width: 30
                sourceSize.height: 30
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }
        Text {
            anchors.left: badgeCircle.right
            anchors.leftMargin: 10
            anchors.right: check.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: win.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: row.selected ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: check
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: row.selected
            text: "✓"
            color: win.accent
            font.family: "SF Pro Display"
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        HoverHandler { id: rowHover; enabled: row.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: rowTap
            enabled: row.enabled
            onTapped: row.activated()
        }
    }

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: PrivacyService.micModeOpen = false

        MouseArea {
            anchors.fill: parent
            onClicked: PrivacyService.micModeOpen = false
        }

        Rectangle {
            id: card
            width: 258
            height: col.implicitHeight + 32
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 10

            // Hangs under the mic pill, clamped so it never runs off-screen.
            x: Math.max(10, Math.min(PrivacyService.micModeAnchorX - width / 2,
                                     win.width - width - 10))
            y: win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.97
            transformOrigin: Item.Top
            visible: opacity > 0.002
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Behavior on y { AppleSpring { spring: 18 } }
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 18
                samples: 37
                verticalOffset: 6
                color: Qt.rgba(0, 0, 0, win.dark ? 0.44 : 0.22)
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 2

                Text {
                    text: "Mic Mode"
                    color: win.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    font.letterSpacing: -0.2
                }
                // Which app is holding the mic — a quiet subtitle under the
                // title, not a highlighted row of its own.
                Text {
                    visible: PrivacyService.micAppName !== ""
                    width: parent.width
                    text: PrivacyService.micAppName
                    color: win.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Item { width: 1; height: 8 }
                Rectangle { width: parent.width; height: 1; color: win.cardBorder }
                Item { width: 1; height: 4 }

                ModeRow {
                    icon: "mic.fill.png"
                    label: "Standard"
                    badge: "#FF9F0A"
                    selected: !Nc.AudioService.voiceIsolationActive
                    onActivated: {
                        Nc.AudioService.setMicMode("standard")
                        PrivacyService.micModeOpen = false
                    }
                }
                ModeRow {
                    icon: "dot.radiowaves.left.and.right.png"
                    label: "Voice Isolation"
                    badge: "#7D6BD8"
                    enabled: Nc.AudioService.voiceIsolationAvailable
                    selected: Nc.AudioService.voiceIsolationActive
                    onActivated: {
                        Nc.AudioService.setMicMode("isolation")
                        PrivacyService.micModeOpen = false
                    }
                }
            }
        }
    }
}
