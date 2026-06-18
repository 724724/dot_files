import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24
    visible: hasMagic

    readonly property bool hasMagic: MagicService.hasMagic

    color: hovered
        ? Qt.rgba(180/255, 140/255, 255/255, 0.65)
        : hasMagic
            ? Qt.rgba(180/255, 140/255, 255/255, 0.45)
            : ThemeService.pillBg
    border.color: hasMagic || hovered
        ? Qt.rgba(180/255, 140/255, 255/255, 0.6)
        : ThemeService.pillBorder

    TapHandler {
        onTapped: Hyprland.dispatch('hl.dsp.workspace.toggle_special("magic")')
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        // Nudge right 1px: the nerd-font glyph's ink sits slightly left of its
        // advance box, so plain centering reads as shifted left.
        anchors.horizontalCenterOffset: 1

        Text {
            text: "󰘔"
            color: (ThemeService.isDark && root.hasMagic) ? "#ffffff" : ThemeService.fg
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
