pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.90)
                                       : Qt.rgba(242 / 255, 242 / 255, 247 / 255, 0.88)
    readonly property color popupBg: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.96)
                                            : Qt.rgba(1, 1, 1, 0.95)
    readonly property color selectionBg: isDark ? "#48484a" : "#ffffff"
    readonly property color selectionStroke: isDark ? Qt.rgba(1, 1, 1, 0.14)
                                                     : Qt.rgba(0, 0, 0, 0.18)
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.14)

    readonly property real pressScale: 0.94
    readonly property real spring: 8
    readonly property real criticalDamping: 1.0
    readonly property real momentumDamping: 0.8
}
