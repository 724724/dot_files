pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.84)
                                       : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.80)
    readonly property color popupBg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.95)
                                            : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.93)
    readonly property color menuBg: isDark ? "#2c2c2e" : "#f5f5f7"
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

    readonly property real pressScale: 0.96
    readonly property real spring: 8
    readonly property real criticalDamping: 1
    readonly property real momentumDamping: 0.8
}
