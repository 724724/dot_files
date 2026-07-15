import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    // Overlay layer so OSD stays visible over fullscreen windows.
    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors.bottom: true
    margins.bottom: 90
    // Keep the layer surface stable while the card width springs between modes.
    implicitWidth: maxOsdWidth + 40
    implicitHeight: 72

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: noInputRegion
    Region { id: noInputRegion }

    // Map the surface only while an OSD is showing (plus a grace period so the
    // fade-out finishes) — previously this stayed mapped on every screen
    // forever, compositing an invisible card and swallowing clicks in its area.
    property bool _surfaceVisible: false
    visible: _surfaceVisible
    Connections {
        target: OsdService
        function onVisibleChanged() {
            if (OsdService.visible) {
                win._surfaceVisible = true
            }
        }
    }

    readonly property bool dark: ThemeService.isDark
    // Hard cap for the card; long media titles get truncated past this.
    readonly property int maxOsdWidth: Math.min(720,
        (modelData && modelData.width ? modelData.width : 1920) - 80)

    Rectangle {
        id: osdCard
        anchors.centerIn: parent

        // Width = icon column + label + horizontal padding, capped at maxOsdWidth.
        // Math.ceil + 4px buffer guarantees short labels ("Muted", "Mic Muted")
        // get exact-fit row width so ElideRight doesn't trip on sub-pixel
        // rounding. Truncation only kicks in for genuinely long media titles
        // that hit the maxOsdWidth cap.
        readonly property int iconCol:  OsdService.icon  !== "" ? Math.ceil(iconText.implicitWidth)  + 10 : 0
        readonly property int labelCol: OsdService.label !== "" ? Math.ceil(labelText.implicitWidth) + 4  : 0
        width: OsdService.showProgress
            ? 300
            : Math.min(maxOsdWidth, iconCol + labelCol + 48)
        Behavior on width { AppleSpring { spring: 13; epsilon: 0.25 } }

        height: 52
        radius: 26

        color: ThemeService.bg
        border.color: ThemeService.stroke
        border.width: 1

        opacity: OsdService.visible ? 1.0 : 0.0
        scale: OsdService.visible ? 1 : 0.96
        transformOrigin: Item.Bottom
        transform: Translate {
            y: OsdService.visible ? 0 : 8
            Behavior on y { AppleSpring { spring: 13; epsilon: 0.25 } }
        }
        Behavior on opacity { AppleSpring { spring: 13 } }
        Behavior on scale { AppleSpring { spring: 13 } }
        onOpacityChanged: if (!OsdService.visible && opacity <= 0.002) win._surfaceVisible = false

        RowLayout {
            anchors.centerIn: parent
            // Progress mode: fill the fixed-width card so the bar can stretch.
            // Otherwise hug the content (capped at maxOsdWidth) and let
            // anchors.centerIn split the leftover evenly — that keeps the
            // icon's left padding and the label's right padding equal so the
            // group sits dead-center instead of being pushed left.
            width: OsdService.showProgress
                ? parent.width - 48
                : Math.min(maxOsdWidth - 48, implicitWidth)
            spacing: 10

            Text {
                id: iconText
                text: OsdService.icon
                color: dark ? "#e0e8f0" : "#222222"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 18
                visible: OsdService.icon !== ""
            }

            // Progress bar sits between the icon and the label so
            // volume/brightness read icon → bar → percentage. Invisible items
            // are ignored by RowLayout, so it adds no space in non-progress OSDs.
            Rectangle {
                Layout.fillWidth: true
                visible: OsdService.showProgress
                height: 6
                radius: 3
                color: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, OsdService.progress)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: dark ? "#0A84FF" : "#007AFF"
                    Behavior on width { AppleSpring { spring: 18; epsilon: 0.25 } }
                }
            }

            Text {
                id: labelText
                text: OsdService.label
                color: dark ? "#c0ccd8" : "#444444"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                visible: OsdService.label !== ""
                // No progress bar (e.g. media title): claim the remaining row
                // width and elide with "..." if too long. With a progress bar
                // (volume/brightness) the label is the short trailing "50%" and
                // the bar takes the fill space instead.
                Layout.fillWidth: !OsdService.showProgress
                elide: Text.ElideRight
            }
        }
    }
}
