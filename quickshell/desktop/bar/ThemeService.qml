pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property bool isDark: true

    // ── Unified surface palette ──────────────────────────────────────────────
    // Shared light/dark surface colors for every panel/window across the shell.
    // Matched to macOS NSColor.windowBackgroundColor with ~10% separators.
    //   Light: #ECECEC  ·  Dark: #222222  ·  stroke: black/white @ 0.10
    readonly property color bg:     isDark ? "#222222" : "#ECECEC"
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

    // ── Bar foreground + pill surfaces ───────────────────────────────────────
    // The bar floats over the wallpaper (no panel behind it). Dark mode keeps
    // the mint-on-dark look; light mode switches to near-black text on subtle
    // light pills so everything stays legible over a light wallpaper.
    readonly property color fg:              isDark ? "#d4f1e8" : "#1c1c1e"
    readonly property color fgDim:           isDark ? "#b0b0b0" : Qt.rgba(0, 0, 0, 0.45)
    readonly property color pillBg:          isDark ? Qt.rgba(30/255, 40/255, 50/255, 0.25)    : Qt.rgba(1, 1, 1, 0.72)
    readonly property color pillBgHover:     isDark ? Qt.rgba(40/255, 50/255, 60/255, 0.40)    : Qt.rgba(1, 1, 1, 0.92)
    readonly property color pillBgMuted:     isDark ? Qt.rgba(150/255, 150/255, 150/255, 0.25) : Qt.rgba(1, 1, 1, 0.55)
    readonly property color pillBorder:      isDark ? Qt.rgba(100/255, 210/255, 180/255, 0.30) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color pillBorderHover: isDark ? Qt.rgba(100/255, 210/255, 180/255, 0.40) : Qt.rgba(0, 0, 0, 0.20)

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
