pragma Singleton

import Quickshell
import QtQuick
import "../nc" as Nc

Singleton {
    readonly property bool isDark: Nc.ThemeService.isDark

    readonly property color toolbarBg: isDark
        ? Qt.rgba(38 / 255, 38 / 255, 40 / 255, 0.97)
        : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.97)
    readonly property color popupBg: isDark
        ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.99)
        : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.99)
    readonly property color stroke: isDark
        ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color separator: isDark
        ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.10)

    readonly property color textPrimary: isDark ? "#f5f5f7" : "#29292c"
    readonly property color textSecondary: isDark ? "#b8b8bd" : "#646467"
    readonly property color textTertiary: isDark ? "#8e8e93" : "#858589"
    readonly property color icon: isDark ? "#d4d4d8" : "#747477"
    readonly property color iconSelected: isDark ? "#ffffff" : "#171719"

    readonly property color controlBg: isDark
        ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.38, 0.38, 0.40, 0.14)
    readonly property color controlHover: isDark
        ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0.38, 0.38, 0.40, 0.22)
    readonly property color selectionBg: isDark
        ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0.46, 0.46, 0.48, 0.18)
    readonly property color hoverBg: isDark
        ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.46, 0.46, 0.48, 0.09)
    readonly property color fieldBg: isDark
        ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color listBg: isDark
        ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.025)
    readonly property color rowHover: isDark
        ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color accent: "#0a84ff"
}
