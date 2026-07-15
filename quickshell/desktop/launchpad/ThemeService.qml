pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    id: root
    // Single gsettings watcher lives in nc/ThemeService; every other module's
    // ThemeService binds to it instead of running its own monitor process.
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color bg: Qt.rgba(24 / 255, 24 / 255, 26 / 255, 0.82)
    readonly property color popupBg: Qt.rgba(36 / 255, 36 / 255, 38 / 255, 0.94)
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.10)

    readonly property real pressScale: 0.96
    readonly property real spring: 8
    readonly property real criticalDamping: 1.0
    readonly property real momentumDamping: 0.8
}
