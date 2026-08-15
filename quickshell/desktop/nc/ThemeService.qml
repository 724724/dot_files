pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool isDark: true
    property bool animationsEnabled: true
    property int iconThemeRevision: 0

    readonly property real materialAlpha: 0.88
    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, materialAlpha)
                                       : Qt.rgba(242 / 255, 242 / 255, 247 / 255, materialAlpha)
    readonly property color popupBg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.95)
                                            : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.93)
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color tileBg: isDark ? "#2c2c2e" : "#ffffff"
    readonly property color tileBgHover: isDark ? "#3a3a3c" : "#f2f2f7"
    readonly property color tileBgActive: isDark ? "#48484a" : "#ffffff"
    readonly property color notificationBg: isDark ? "#2c2c2e" : "#ffffff"
    readonly property color notificationStackBg1: isDark ? "#262628" : "#ebebf0"
    readonly property color notificationStackBg2: isDark ? "#202022" : "#dadae0"
    readonly property color tileStroke: "transparent"
    readonly property color notificationStroke: "transparent"
    readonly property color subtleTileBg: isDark ? "#3a3a3c" : "#f2f2f7"
    readonly property color subtleTileBgHover: isDark ? "#48484a" : "#e5e5ea"
    readonly property color subtleTileBgHoverClear: isDark ? Qt.rgba(72 / 255, 72 / 255, 74 / 255, 0)
                                                           : Qt.rgba(229 / 255, 229 / 255, 234 / 255, 0)
    readonly property color rowBg: isDark ? "#2c2c2e" : "#ffffff"
    readonly property color rowBgHover: isDark ? "#3a3a3c" : "#e5e5ea"
    readonly property color rowBgHoverClear: isDark ? Qt.rgba(58 / 255, 58 / 255, 60 / 255, 0)
                                                    : Qt.rgba(229 / 255, 229 / 255, 234 / 255, 0)
    readonly property color rowBgActive: isDark ? Qt.rgba(10 / 255, 132 / 255, 255 / 255, 0.24)
                                                : Qt.rgba(0, 122 / 255, 255 / 255, 0.18)
    readonly property color fieldBg: isDark ? "#3a3a3c" : "#ffffff"
    readonly property color textPrimary: isDark ? "#f5f6f8" : "#1c1c1e"
    readonly property color textSecondary: isDark ? Qt.rgba(1, 1, 1, 0.68) : Qt.rgba(0, 0, 0, 0.62)
    readonly property color textTertiary: isDark ? Qt.rgba(1, 1, 1, 0.48) : Qt.rgba(0, 0, 0, 0.46)
    readonly property color separator: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)

    readonly property real pressScale: 0.97
    readonly property real spring: 8
    readonly property real criticalDamping: 1
    readonly property real momentumDamping: 0.8

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
        command: ["gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.animationsEnabled = !text.trim().includes("false")
        }
    }

    Process {
        command: ["setpriv", "--pdeathsig", "TERM", "--", "gsettings", "monitor",
                  "org.gnome.desktop.interface"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("color-scheme"))
                    root.isDark = data.includes("dark")
                if (data.includes("enable-animations"))
                    root.animationsEnabled = !data.includes("false")
                if (data.includes("icon-theme"))
                    root.iconThemeRevision++
            }
        }
    }
}
