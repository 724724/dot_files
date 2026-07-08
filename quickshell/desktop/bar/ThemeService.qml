pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: isDark ? Qt.rgba(30 / 255, 30 / 255, 30 / 255, 0.74)
                                       : Qt.rgba(236 / 255, 236 / 255, 236 / 255, 0.62)
    readonly property color popupBg: isDark ? Qt.rgba(30 / 255, 30 / 255, 30 / 255, 0.86)
                                            : Qt.rgba(236 / 255, 236 / 255, 236 / 255, 0.76)
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.16)

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
}
