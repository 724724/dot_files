pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool isDark: true

    readonly property real materialAlpha: 0.75
    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, materialAlpha)
                                       : Qt.rgba(242 / 255, 242 / 255, 247 / 255, materialAlpha)
    readonly property color popupBg: bg
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color tileBg: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, materialAlpha)
                                           : Qt.rgba(1, 1, 1, materialAlpha)
    readonly property color tileBgHover: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, materialAlpha)
                                                : Qt.rgba(248 / 255, 248 / 255, 250 / 255, materialAlpha)
    readonly property color tileBgActive: isDark ? Qt.rgba(72 / 255, 72 / 255, 74 / 255, materialAlpha)
                                                 : Qt.rgba(1, 1, 1, materialAlpha)
    readonly property color notificationBg: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.84)
                                                   : Qt.rgba(1, 1, 1, 0.92)
    readonly property color notificationStackBg1: isDark ? Qt.rgba(38 / 255, 38 / 255, 40 / 255, 0.86)
                                                         : Qt.rgba(235 / 255, 235 / 255, 240 / 255, 0.94)
    readonly property color notificationStackBg2: isDark ? Qt.rgba(32 / 255, 32 / 255, 34 / 255, 0.88)
                                                         : Qt.rgba(218 / 255, 218 / 255, 224 / 255, 0.94)
    readonly property color tileStroke: "transparent"
    readonly property color notificationStroke: "transparent"
    readonly property color subtleTileBg: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, materialAlpha)
                                                 : Qt.rgba(242 / 255, 242 / 255, 247 / 255, materialAlpha)
    readonly property color subtleTileBgHover: isDark ? Qt.rgba(72 / 255, 72 / 255, 74 / 255, materialAlpha)
                                                      : Qt.rgba(229 / 255, 229 / 255, 234 / 255, materialAlpha)
    readonly property color subtleTileBgHoverClear: isDark ? Qt.rgba(72 / 255, 72 / 255, 74 / 255, 0)
                                                           : Qt.rgba(229 / 255, 229 / 255, 234 / 255, 0)
    readonly property color rowBg: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.64)
                                          : Qt.rgba(1, 1, 1, 0.64)
    readonly property color rowBgHover: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, 0.78)
                                               : Qt.rgba(229 / 255, 229 / 255, 234 / 255, 0.86)
    readonly property color rowBgHoverClear: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, 0)
                                                    : Qt.rgba(229 / 255, 229 / 255, 234 / 255, 0)
    readonly property color rowBgActive: isDark ? Qt.rgba(10 / 255, 132 / 255, 255 / 255, 0.24)
                                                : Qt.rgba(0, 122 / 255, 255 / 255, 0.18)
    readonly property color fieldBg: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, 0.72)
                                            : Qt.rgba(1, 1, 1, 0.72)
    readonly property color textPrimary: isDark ? "#f5f6f8" : "#1c1c1e"
    readonly property color textSecondary: isDark ? Qt.rgba(1, 1, 1, 0.68) : Qt.rgba(0, 0, 0, 0.62)
    readonly property color textTertiary: isDark ? Qt.rgba(1, 1, 1, 0.48) : Qt.rgba(0, 0, 0, 0.46)
    readonly property color separator: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)

    // Single source of truth for the GTK theme paired with each color scheme.
    // Stock Adwaita: GTK3/Qt follow the theme name, GTK4/libadwaita follow
    // color-scheme via the portal — so light/dark switches live everywhere,
    // including already-open windows (no static ~/.config/gtk-4.0 override).
    readonly property string lightTheme: "Adwaita"
    readonly property string darkTheme: "Adwaita-dark"

    // Theme switching lives here now (replaces scripts/toggle-theme.sh). Every
    // Quickshell component watches color-scheme via the monitor below and
    // re-themes itself automatically once it flips. GTK3/Qt apps follow
    // gtk-theme; libadwaita/GTK4 apps (Nautilus, …) follow color-scheme live via
    // the desktop portal — provided there's no static ~/.config/gtk-4.0/gtk.css
    // override pinning them to one theme.
    function setLight() {
        Quickshell.execDetached(["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme '" + root.lightTheme + "'; " +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'"])
    }
    function setDark() {
        Quickshell.execDetached(["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme '" + root.darkTheme + "'; " +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"])
    }
    function toggle() {
        if (root.isDark) root.setLight()
        else root.setDark()
    }

    Process {
        command: ["bash", "-c", "gsettings get org.gnome.desktop.interface color-scheme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.isDark = text.trim().includes("dark")
        }
    }

    Process {
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("color-scheme"))
                    root.isDark = data.includes("dark")
            }
        }
    }
}
