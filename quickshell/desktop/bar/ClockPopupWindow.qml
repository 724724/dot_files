import Quickshell
import Quickshell.Wayland
import QtQuick

// Clock + calendar popup that drops from the bar clock pill. Two separate iOS
// cards (clock module, calendar module) in a Windows-11 flyout layout: big
// time/date block over a full month grid with ‹ › month navigation.
//
// Overlay/dismiss/animation plumbing mirrors ControlCenterWindow and
// SpotlightWindow so it behaves like the rest of the shell's surfaces.
PanelWindow {
    id: win

    // Full-screen transparent overlay: clicks on the empty area outside the
    // cards dismiss the popup.
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-clock"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand: take the keyboard only while open (for Esc) without stealing it
    // from regular apps the rest of the time.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ── Theme tokens (iOS palette, dark/light aware) ─────────────────────
    readonly property bool dark: ThemeService.isDark
    readonly property color accent:        dark ? "#0A84FF" : "#007AFF"
    readonly property color cardBg:        ThemeService.bg
    readonly property color cardBorder:    ThemeService.stroke
    readonly property color primaryText:   dark ? "#ffffff" : "#1a1a1a"
    readonly property color secondaryText: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color fadedText:     dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.28)
    readonly property color sundayText:    dark ? "#FF6961" : "#FF3B30"
    readonly property color saturdayText:  dark ? "#6AB7FF" : "#0A84FF"
    readonly property color hoverFill:     dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)

    readonly property bool shown: ClockService.popupVisible

    // Stay mapped briefly after hide so the close animation can finish.
    property bool _surfaceVisible: false
    visible: _surfaceVisible

    // ── Calendar view state ──────────────────────────────────────────────
    property int viewYear: 2026
    property int viewMonth: 0          // 0 = January
    property string selectedKey: ""    // "y-m-d" of a user-clicked day, "" = none

    // Live "today" key — recomputed each tick but its value only changes at
    // midnight, so the 42 day cells that depend on it don't churn per-second.
    readonly property string todayKey: {
        let n = ClockService.now
        return n.getFullYear() + "-" + n.getMonth() + "-" + n.getDate()
    }
    readonly property bool isViewingCurrentMonth: {
        let n = ClockService.now
        return win.viewYear === n.getFullYear() && win.viewMonth === n.getMonth()
    }

    // 6×7 = 42 cells; leading/trailing days spill from the adjacent months.
    readonly property var grid: {
        let cells = []
        let startDow = new Date(viewYear, viewMonth, 1).getDay()     // 0 = Sun
        let daysThis = new Date(viewYear, viewMonth + 1, 0).getDate()
        let daysPrev = new Date(viewYear, viewMonth, 0).getDate()

        let pm = viewMonth - 1, py = viewYear
        if (pm < 0) { pm = 11; py-- }
        for (let i = startDow - 1; i >= 0; i--)
            cells.push({ day: daysPrev - i, month: pm, year: py, cur: false })

        for (let d = 1; d <= daysThis; d++)
            cells.push({ day: d, month: viewMonth, year: viewYear, cur: true })

        let nm = viewMonth + 1, ny = viewYear
        if (nm > 11) { nm = 0; ny++ }
        let d2 = 1
        while (cells.length < 42)
            cells.push({ day: d2++, month: nm, year: ny, cur: false })
        return cells
    }

    function syncToToday() {
        let n = new Date()
        viewYear = n.getFullYear()
        viewMonth = n.getMonth()
        selectedKey = ""
    }
    function prevMonth() { if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth-- }
    function nextMonth() { if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++ }

    // ── Map / unmap + focus plumbing ─────────────────────────────────────
    Connections {
        target: ClockService
        function onPopupVisibleChanged() {
            if (ClockService.popupVisible) {
                if (ClockService.targetScreen) win.screen = ClockService.targetScreen
                win.syncToToday()
                win._surfaceVisible = true
                unmapTimer.stop()
            } else {
                unmapTimer.restart()
            }
        }
    }
    Timer { id: unmapTimer; interval: 200; onTriggered: win._surfaceVisible = false }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    // ── Small round icon button (month chevrons) ─────────────────────────
    component IconButton: Rectangle {
        id: ib
        property string glyph
        signal activated
        width: 30; height: 30; radius: 15
        color: ibHover.hovered ? win.hoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: ib.glyph
            color: win.primaryText
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 16
        }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.activated() }
    }

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ClockService.popupVisible = false

        // Click anywhere outside the cards closes the popup.
        MouseArea { anchors.fill: parent; onClicked: ClockService.popupVisible = false }

        // ── The two stacked modules ──────────────────────────────────────
        Column {
            id: stack
            x: 10
            width: 326
            spacing: 10

            // Entrance: fade + slight scale + drop, emanating from the top-left
            // corner under the clock pill — a Windows-11 flyout drop with an iOS
            // scale/fade.
            transformOrigin: Item.TopLeft
            opacity: win.shown ? 1 : 0
            scale:   win.shown ? 1 : 0.97
            // Rest at BarState.contentTop (gap centralized there); pre-open sits
            // 8px higher for the drop. Tracks the bar, rising when it's hidden.
            y:       win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on y       { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // ── CLOCK MODULE ──────────────────────────────────────────────
            Rectangle {
                id: clockCard
                width: stack.width
                radius: 22
                color: win.cardBg
                border.color: win.cardBorder
                border.width: 1
                implicitHeight: clockCol.implicitHeight + 40

                // Swallow empty-area clicks so they don't fall through to the
                // dismiss layer behind the card.
                MouseArea { anchors.fill: parent }

                Column {
                    id: clockCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Text {
                            id: bigTime
                            text: Qt.formatDateTime(ClockService.now, "HH:mm")
                            color: win.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 54
                            font.weight: Font.Light
                        }
                        Text {
                            text: Qt.formatDateTime(ClockService.now, "ss")
                            color: win.accent
                            font.family: "SF Pro Display"
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            anchors.baseline: bigTime.baseline
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(ClockService.now, "dddd, d MMMM yyyy")
                        color: win.secondaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                }
            }

            // ── CALENDAR MODULE ───────────────────────────────────────────
            Rectangle {
                id: calCard
                width: stack.width
                radius: 22
                color: win.cardBg
                border.color: win.cardBorder
                border.width: 1
                implicitHeight: calCol.implicitHeight + 32

                MouseArea { anchors.fill: parent }

                Column {
                    id: calCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 10

                    // Header: month-year + Today + chevrons
                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDate(new Date(win.viewYear, win.viewMonth, 1), "MMMM yyyy")
                            color: win.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !win.isViewingCurrentMonth
                                width: todayLabel.implicitWidth + 20
                                height: 26
                                radius: 13
                                color: todayHover.hovered
                                    ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.22)
                                    : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.14)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: todayLabel
                                    anchors.centerIn: parent
                                    text: "Today"
                                    color: win.accent
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.syncToToday() }
                            }

                            IconButton { glyph: "󰅁"; onActivated: win.prevMonth() }
                            IconButton { glyph: "󰅂"; onActivated: win.nextMonth() }
                        }
                    }

                    // Weekday header — Sun red, Sat blue (Korean calendar convention).
                    Row {
                        width: parent.width
                        Repeater {
                            model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                            delegate: Item {
                                required property int index
                                required property string modelData
                                width: calCol.width / 7
                                height: 22
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: index === 0 ? win.sundayText
                                         : index === 6 ? win.saturdayText
                                         : win.secondaryText
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    // Day grid
                    Grid {
                        width: parent.width
                        columns: 7
                        Repeater {
                            model: win.grid
                            delegate: Item {
                                id: dayCell
                                required property int index
                                required property var modelData
                                width: calCol.width / 7
                                height: 40

                                readonly property int dow: index % 7
                                readonly property string key:
                                    modelData.year + "-" + modelData.month + "-" + modelData.day
                                readonly property bool isToday: key === win.todayKey
                                readonly property bool isSelected: !isToday && key === win.selectedKey

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34; height: 34; radius: 17
                                    color: dayCell.isToday ? win.accent
                                         : dayCell.isSelected
                                            ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
                                         : cellHover.hovered ? win.hoverFill
                                         : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.day
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 14
                                    font.weight: dayCell.isToday ? Font.Bold : Font.Medium
                                    color: dayCell.isToday ? "#ffffff"
                                         : !modelData.cur ? win.fadedText
                                         : dayCell.dow === 0 ? win.sundayText
                                         : dayCell.dow === 6 ? win.saturdayText
                                         : win.primaryText
                                }

                                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        win.selectedKey = dayCell.key
                                        // Clicking a spill-over day jumps to that month.
                                        if (!modelData.cur) {
                                            win.viewYear = modelData.year
                                            win.viewMonth = modelData.month
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
