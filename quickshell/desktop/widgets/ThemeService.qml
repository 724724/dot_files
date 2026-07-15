pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

// Light/Dark theme + Apple system colour palette for the widgets that follow
// macOS styling (reminders). isDark is bound to nc/ThemeService — the one
// gsettings watcher shared by the whole unified shell. Hex values are Apple's
// published system colours (light/dark). See sarunw.com/posts/dark-color-cheat-sheet.
Singleton {
    id: root
    readonly property bool isDark: Nc.ThemeService.isDark
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"

    // Apple system colours { light, dark }.
    readonly property var sys: ({
        red:    { l: "#FF3B30", d: "#FF453A" },
        orange: { l: "#FF9500", d: "#FF9F0A" },
        yellow: { l: "#FFCC00", d: "#FFD60A" },
        green:  { l: "#34C759", d: "#30D158" },
        mint:   { l: "#00C7BE", d: "#63E6E2" },
        teal:   { l: "#5AC8FA", d: "#64D2FF" },
        blue:   { l: "#007AFF", d: "#0A84FF" },
        indigo: { l: "#5856D6", d: "#5E5CE6" },
        purple: { l: "#AF52DE", d: "#BF5AF2" },
        pink:   { l: "#FF2D55", d: "#FF375F" },
        brown:  { l: "#A2845E", d: "#AC8E68" },
        gray:   { l: "#8E8E93", d: "#8E8E93" }
    })
    readonly property var accentNames: ["red", "orange", "yellow", "green", "mint",
                                        "teal", "blue", "indigo", "purple", "pink", "brown"]

    function accent(name) {
        let c = sys[name] || sys.blue
        return isDark ? c.d : c.l
    }

    // Calendar colors can be an accent *name* (tracks light/dark) or a raw
    // "#RRGGBB" the user typed in the palette — pass hex straight through.
    function resolveAccent(c) {
        if (c && c.charAt(0) === "#") return c
        return accent(c)
    }

    // Reminders list icons (Nerd Font glyphs) — pickable in the editor.
    readonly property var reminderIcons: [
        { name: "list",      glyph: "\uf03a" },
        { name: "check",     glyph: "\uf00c" },
        { name: "star",      glyph: "\uf005" },
        { name: "flag",      glyph: "\uf024" },
        { name: "heart",     glyph: "\uf004" },
        { name: "bell",      glyph: "\uf0f3" },
        { name: "bookmark",  glyph: "\uf02e" },
        { name: "cart",      glyph: "\uf07a" },
        { name: "gift",      glyph: "\uf06b" },
        { name: "leaf",      glyph: "\uf06c" },
        { name: "home",      glyph: "\uf015" },
        { name: "briefcase", glyph: "\uf0b1" },
        { name: "calendar",  glyph: "\uf073" },
        { name: "bolt",      glyph: "\uf0e7" }
    ]
    function reminderGlyph(name) {
        for (let i = 0; i < reminderIcons.length; i++)
            if (reminderIcons[i].name === name) return reminderIcons[i].glyph
        return reminderIcons[0].glyph
    }

    // Semantic colours (macOS secondarySystemGroupedBackground / label / …).
    readonly property color cardBg:    isDark ? "#1C1C1E" : "#FFFFFF"
    readonly property color label:     isDark ? "#FFFFFF" : "#000000"
    readonly property color secondaryLabel: isDark ? Qt.rgba(235/255, 235/255, 245/255, 0.6)
                                                   : Qt.rgba(60/255, 60/255, 67/255, 0.6)
    readonly property color tertiaryLabel: isDark ? Qt.rgba(235/255, 235/255, 245/255, 0.3)
                                                  : Qt.rgba(60/255, 60/255, 67/255, 0.3)
    readonly property color separator: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color checkRing: isDark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.22)
    readonly property color panelBg: isDark ? Qt.rgba(36 / 255, 36 / 255, 38 / 255, 0.94)
                                            : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.96)
    readonly property color controlBg: isDark ? "#48484a" : "#e5e5ea"
    readonly property color controlBgHover: isDark ? "#5a5a5e" : "#d1d1d6"

    readonly property real pressScale: 0.96
    readonly property real spring: 8
    readonly property real criticalDamping: 1.0
    readonly property real momentumDamping: 0.8
}
