pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.94)
                                       : Qt.rgba(242 / 255, 242 / 255, 247 / 255, 0.92)
    readonly property color popupBg: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.97)
                                            : Qt.rgba(1, 1, 1, 0.96)
    readonly property color controlBg: isDark ? "#3a3a3c" : "#ffffff"
    readonly property color barBg: isDark ? "#242426" : "#f2f2f7"
    readonly property color selectionBg: isDark ? "#48484a" : "#ffffff"
    readonly property color cellHover: isDark ? "#3a3a3c" : "#e5e5ea"
    readonly property color stroke: isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.14)

    readonly property real pressScale: 0.94
    readonly property real spring: 8
    readonly property real criticalDamping: 1.0
    readonly property real momentumDamping: 0.8
}
