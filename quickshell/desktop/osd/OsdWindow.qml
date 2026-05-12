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
    // Panel grows with the card so the OSD never gets clipped by a too-small
    // surface, but stays clamped to a reasonable fraction of screen width.
    implicitWidth: Math.min(maxOsdWidth + 40, Math.max(320, osdCard.width + 40))
    implicitHeight: 56

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

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
        Behavior on width { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

        height: 52
        radius: 26

        color: dark ? Qt.rgba(20/255, 25/255, 30/255, 0.90)
                    : Qt.rgba(1, 1, 1, 0.90)
        border.color: dark ? Qt.rgba(100/255, 100/255, 120/255, 0.30)
                           : Qt.rgba(0, 0, 0, 0.12)
        border.width: 1

        Behavior on color { ColorAnimation { duration: 200 } }

        opacity: OsdService.visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

        RowLayout {
            // Center in card; width matches card minus horizontal padding
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 10

            Text {
                id: iconText
                text: OsdService.icon
                color: dark ? "#e0e8f0" : "#222222"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 18
                visible: OsdService.icon !== ""
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Text {
                id: labelText
                text: OsdService.label
                color: dark ? "#c0ccd8" : "#444444"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                visible: OsdService.label !== ""
                // When there's no progress bar (e.g. media title), claim the
                // remaining row width and elide with "..." if too long. With a
                // progress bar present (volume/brightness), the label is short
                // ("50%") and the bar wants the fill space instead.
                Layout.fillWidth: !OsdService.showProgress
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Rectangle {
                Layout.fillWidth: true
                // Invisible items are ignored by RowLayout, so no extra space when hidden
                visible: OsdService.showProgress
                height: 6
                radius: 3
                color: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.10)

                Rectangle {
                    width: parent.width * OsdService.progress / 100
                    height: parent.height
                    radius: parent.radius
                    color: dark ? "#0A84FF" : "#007AFF"
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }
        }
    }
}
