pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.88)
                                       : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.84)
    readonly property color popupBg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.94)
                                            : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.92)
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

    // ── Bar foreground + pill surfaces ───────────────────────────────────────
    // The bar floats over the wallpaper (no panel behind it). Dark mode keeps
    // the mint-on-dark look; light mode switches to near-black text on subtle
    // light pills so everything stays legible over a light wallpaper.
    readonly property color fg:              isDark ? "#d4f1e8" : "#1c1c1e"
    readonly property color fgDim:           isDark ? "#b0b0b0" : Qt.rgba(0, 0, 0, 0.45)
    readonly property color pillBg:          isDark ? Qt.rgba(28/255, 32/255, 38/255, 0.68)    : Qt.rgba(1, 1, 1, 0.78)
    readonly property color pillBgHover:     isDark ? Qt.rgba(48/255, 54/255, 62/255, 0.82)    : Qt.rgba(1, 1, 1, 0.92)
    readonly property color pillBgMuted:     isDark ? Qt.rgba(64/255, 66/255, 70/255, 0.68)    : Qt.rgba(242/255, 242/255, 244/255, 0.82)
    readonly property color pillBorder:      isDark ? Qt.rgba(1, 1, 1, 0.16)                  : Qt.rgba(0, 0, 0, 0.10)
    readonly property color pillBorderHover: isDark ? Qt.rgba(1, 1, 1, 0.24)                  : Qt.rgba(0, 0, 0, 0.16)

    readonly property real pressScale: 0.97
    readonly property real spring: 8
    readonly property real criticalDamping: 1
    readonly property real momentumDamping: 0.8
}
