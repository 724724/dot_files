pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

// Tracks the GNOME colour-scheme so Mission Control can match light/dark like
// the rest of the shell. Bound to nc/ThemeService — the one gsettings watcher
// shared by the whole unified shell process.
Singleton {
    id: root
    readonly property bool isDark: Nc.ThemeService.isDark
    readonly property string reduceMotionOverride:
        String(Quickshell.env("QS_REDUCE_MOTION") || "").toLowerCase()
    readonly property bool reducedMotion: !Nc.ThemeService.animationsEnabled
        || reduceMotionOverride === "1" || reduceMotionOverride === "true"
        || reduceMotionOverride === "yes"
    readonly property color surface: isDark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.86)
                                            : Qt.rgba(242 / 255, 242 / 255, 247 / 255, 0.84)
    // Spaces is structural chrome over arbitrary windows. Unlike a small popover,
    // it must never leak text/images from the desktop behind it.
    readonly property color surfaceOpaque: isDark ? "#1c1c1e" : "#f2f2f7"
    readonly property color surfaceStrong: isDark ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.96)
                                                  : Qt.rgba(1, 1, 1, 0.94)
    readonly property color surfaceStroke: isDark ? Qt.rgba(1, 1, 1, 0.16)
                                                  : Qt.rgba(0, 0, 0, 0.10)
    readonly property color controlBg: isDark ? "#3a3a3c" : "#ffffff"
    readonly property color previewBg: isDark ? "#1c1c1e" : "#f2f2f7"

    readonly property real pressScale: 0.96
    // Qt Quick SpringAnimation documents 0–5 as its useful spring range.
    // The old 8/13/18 values made even small hover/reflow responses snap.
    readonly property real spring: 3.4
    readonly property real criticalDamping: 1.0
    readonly property real momentumDamping: 0.8
}
