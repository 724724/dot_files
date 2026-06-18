import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PillContainer {
    id: root
    clickable: true
    implicitHeight: 33
    implicitWidth: row.implicitWidth + 24

    color: hovered
        ? ThemeService.pillBgHover
        : VolumeService.muted ? ThemeService.pillBgMuted : ThemeService.pillBg

    // Direct Process avoids the QML→Hyprland.dispatch IPC roundtrip; the
    // launch script handles workspace pinning and reuses an existing window
    // if one's already open (instant on subsequent clicks).
    Process {
        id: launchProc
        command: ["/home/sejunlee/.config/hypr/scripts/pavucontrol-launch.sh"]
    }

    TapHandler {
        onTapped: launchProc.running = true
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: {
                if (VolumeService.muted || VolumeService.vol <= 0) return "󰝟"
                if (VolumeService.vol <= 50) return "󰖀"
                return "󰕾"
            }
            color: VolumeService.muted ? ThemeService.fgDim : ThemeService.fg
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 12
        }

        Text {
            text: VolumeService.muted ? "Muted" : VolumeService.vol + "%"
            color: VolumeService.muted ? ThemeService.fgDim : ThemeService.fg
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }
}
