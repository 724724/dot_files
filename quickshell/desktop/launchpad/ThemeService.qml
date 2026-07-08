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
}
