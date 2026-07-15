import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects
import "../widgets" as Widgets
import "clock" as ClockViews

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
    readonly property color cardBg:        ThemeService.popupBg
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
    property var selectedDayEvents: []
    property bool eventPopoverOpen: false
    property int toolPage: 0
    property string toolEditorMode: ""
    property string toolDetailMode: ""
    property var waveformSound: ({})
    property bool waveformEditorOpen: false
    property bool soundFilePickerOpen: false

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
        closeEventPopover()
    }
    function prevMonth() {
        closeEventPopover()
        if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth--
    }
    function nextMonth() {
        closeEventPopover()
        if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++
    }
    function toggleDayPopover(events, key) {
        if (eventPopoverOpen && selectedKey === key) {
            closeEventPopover()
            return
        }
        selectedKey = key
        if (!events || events.length === 0) {
            closeEventPopover()
            return
        }
        selectedDayEvents = events
        eventPopoverOpen = true
    }
    function closeEventPopover() { eventPopoverOpen = false }
    function closeToolDetail() {
        soundFilePickerOpen = false
        waveformEditorOpen = false
        waveformSound = ({})
        toolDetailMode = ""
    }
    function closeToolEditor() {
        closeToolDetail()
        toolEditorMode = ""
    }
    function selectToolPage(value) {
        toolPage = value
        closeEventPopover()
        closeToolEditor()
    }
    function eventColor(ev) {
        return Widgets.ThemeService.resolveAccent(ev ? ev.color : "blue")
    }
    function selectedDayLabel() {
        let parts = selectedKey.split("-")
        if (parts.length !== 3) return ""
        return Qt.formatDate(new Date(parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])),
            "dddd, d MMMM yyyy")
    }

    // ── Map / unmap + focus plumbing ─────────────────────────────────────
    Connections {
        target: ClockService
        function onPopupVisibleChanged() {
            if (ClockService.popupVisible) {
                if (ClockService.targetScreen) win.screen = ClockService.targetScreen
                win.syncToToday()
                win.closeToolEditor()
                win._surfaceVisible = true
            } else {
                win.closeEventPopover()
                win.closeToolEditor()
            }
        }
    }
    onVisibleChanged: if (visible) escScope.forceActiveFocus()

    // ── Small round icon button (month chevrons) ─────────────────────────
    component IconButton: Rectangle {
        id: ib
        property string glyph
        signal activated
        width: 30; height: 30; radius: 15
        color: ibHover.hovered ? win.hoverFill : "transparent"
        scale: ibTap.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 13 } }
        Text {
            anchors.centerIn: parent
            text: ib.glyph
            color: win.primaryText
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 16
        }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: ibTap; onTapped: ib.activated() }
    }

    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (win.soundFilePickerOpen) win.soundFilePickerOpen = false
            else if (win.waveformEditorOpen) win.waveformEditorOpen = false
            else if (win.toolDetailMode !== "") win.closeToolDetail()
            else if (win.toolEditorMode !== "") win.closeToolEditor()
            else if (win.eventPopoverOpen) win.closeEventPopover()
            else ClockService.popupVisible = false
        }

        // Click anywhere outside the cards closes the popup.
        MouseArea {
            anchors.fill: parent
            onPressed: ClockService.popupVisible = false
        }

        // ── The two stacked modules ──────────────────────────────────────
        Item {
            id: stack
            x: 10
            width: 326
            height: Math.max(clockCard.height, calCard.y + calCard.height)

            // Entrance: fade + slight scale + drop, emanating from the top-left
            // corner under the clock pill — a Windows-11 flyout drop with an iOS
            // scale/fade.
            transformOrigin: Item.TopLeft
            opacity: win.shown ? 1 : 0
            scale:   win.shown ? 1 : 0.97
            // Rest at BarState.contentTop (gap centralized there); pre-open sits
            // 8px higher for the drop. Tracks the bar, rising when it's hidden.
            y:       win.shown ? BarState.contentTop : (BarState.contentTop - 8)
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Behavior on y { AppleSpring { spring: 18 } }
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false

            // ── CLOCK MODULE ──────────────────────────────────────────────
            Rectangle {
                id: clockCard
                y: 0
                width: stack.width
                radius: 22
                color: win.cardBg
                border.color: win.cardBorder
                border.width: 1
                implicitHeight: clockTools.implicitHeight + 32
                height: implicitHeight
                clip: true
                Behavior on height { AppleSpring { spring: 30; epsilon: 0.1 } }
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    radius: 22
                    samples: 45
                    verticalOffset: 8
                    color: Qt.rgba(0, 0, 0, win.dark ? 0.46 : 0.24)
                }

                // Swallow empty-area clicks so they don't fall through to the
                // dismiss layer behind the card.
                MouseArea { anchors.fill: parent }

                ClockViews.ClockToolsView {
                    id: clockTools
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    height: implicitHeight
                    page: win.toolPage
                    dark: win.dark
                    accent: win.accent
                    primaryText: win.primaryText
                    secondaryText: win.secondaryText
                    hoverFill: win.hoverFill
                    lineColor: win.cardBorder
                    onPageRequested: value => win.selectToolPage(value)
                    onEditorRequested: mode => {
                        if (win.toolEditorMode === mode) win.closeToolEditor()
                        else {
                            win.closeToolDetail()
                            win.toolEditorMode = mode
                        }
                    }
                }
            }

            // ── CALENDAR MODULE ───────────────────────────────────────────
            Rectangle {
                id: calCard
                readonly property bool expanded: win.toolPage === 0
                readonly property real expandedHeight: calCol.implicitHeight + 32
                x: 0
                y: clockCard.height + 10
                width: expanded ? stack.width : 42
                height: expanded ? expandedHeight : 42
                radius: expanded ? 22 : 21
                color: win.cardBg
                border.color: win.cardBorder
                border.width: 1
                clip: true
                z: expanded ? 0 : 20
                Behavior on width { AppleSpring { spring: 26; epsilon: 0.1 } }
                Behavior on height { AppleSpring { spring: 26; epsilon: 0.1 } }
                Behavior on radius { AppleSpring { spring: 26; epsilon: 0.1 } }
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    radius: calCard.expanded ? 22 : 12
                    samples: 45
                    verticalOffset: calCard.expanded ? 8 : 4
                    color: Qt.rgba(0, 0, 0, win.dark ? 0.40 : 0.20)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: calCard.expanded ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onPressed: if (!calCard.expanded) win.selectToolPage(0)
                }

                Column {
                    id: calCol
                    visible: opacity > 0.002
                    enabled: calCard.expanded
                    opacity: calCard.expanded ? 1 : 0
                    scale: calCard.expanded ? 1 : 0.96
                    Behavior on opacity { AppleSpring { spring: 26 } }
                    Behavior on scale { AppleSpring { spring: 26 } }
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
                            font.letterSpacing: -0.2
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
                                scale: todayTap.pressed ? ThemeService.pressScale : 1
                                color: todayHover.hovered
                                    ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.22)
                                    : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.14)
                                Behavior on scale { AppleSpring { spring: 13 } }
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
                                TapHandler { id: todayTap; onTapped: win.syncToToday() }
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
                                readonly property var events: Widgets.CalendarService.eventsForDay(
                                    modelData.year, modelData.month, modelData.day)
                                scale: dayTap.pressed ? ThemeService.pressScale : 1
                                Behavior on scale { AppleSpring { spring: 13 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34; height: 34; radius: 17
                                    color: dayCell.isToday ? win.accent
                                         : dayCell.isSelected
                                            ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
                                         : cellHover.hovered ? win.hoverFill
                                         : "transparent"
                                }

                                Text {
                                    id: dayNumber
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

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: dayNumber.verticalCenter
                                    anchors.topMargin: 9
                                    spacing: 2
                                    z: 5

                                    Repeater {
                                        model: Math.min(3, dayCell.events.length)
                                        delegate: Rectangle {
                                            id: eventDot
                                            required property int index
                                            readonly property var eventData: dayCell.events[index]
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: win.eventColor(eventData)
                                        }
                                    }
                                }

                                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    id: dayTap
                                    onTapped: {
                                        // Clicking a spill-over day jumps to that month.
                                        if (!modelData.cur) {
                                            win.viewYear = modelData.year
                                            win.viewMonth = modelData.month
                                        }
                                        win.toggleDayPopover(dayCell.events, dayCell.key)
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: opacity > 0.002
                    opacity: calCard.expanded ? 0 : 1
                    scale: calCard.expanded ? 0.7 : 1
                    text: "󰃭"
                    color: win.accent
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 18
                    Behavior on opacity { AppleSpring { spring: 26 } }
                    Behavior on scale { AppleSpring { spring: 26 } }
                }
            }
        }

        Rectangle {
            id: eventPopover
            visible: opacity > 0.002
            opacity: win.shown && win.toolPage === 0 && win.eventPopoverOpen && win.selectedDayEvents.length > 0 ? 1 : 0
            scale: win.eventPopoverOpen ? 1 : 0.97
            transformOrigin: Item.TopLeft
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            onOpacityChanged: {
                if (!win.eventPopoverOpen && opacity <= 0.002)
                    win.selectedDayEvents = []
            }

            x: stack.x + stack.width + 10
            y: stack.y + calCard.y
            width: 282
            height: eventInfo.implicitHeight + 32
            radius: 18
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 200
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 18
                samples: 37
                verticalOffset: 6
                color: Qt.rgba(0, 0, 0, win.dark ? 0.42 : 0.20)
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: eventInfo
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                anchors.leftMargin: 16
                anchors.rightMargin: 42
                spacing: 9

                Text {
                    width: parent.width
                    text: win.selectedDayLabel()
                    color: win.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    text: win.selectedDayEvents.length + (win.selectedDayEvents.length === 1
                        ? " event" : " events")
                    color: win.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: win.cardBorder
                }

                Repeater {
                    model: win.selectedDayEvents
                    delegate: Column {
                        id: eventItem
                        required property int index
                        required property var modelData
                        width: eventInfo.width
                        spacing: 4

                        Rectangle {
                            visible: eventItem.index > 0
                            width: parent.width
                            height: 1
                            color: win.cardBorder
                        }

                        Item {
                            width: parent.width
                            height: 16
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                radius: 3.5
                                color: win.eventColor(eventItem.modelData)
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.right: eventTime.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: eventItem.modelData.cal || "Calendar"
                                color: win.eventColor(eventItem.modelData)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                id: eventTime
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Widgets.CalendarService.timeLabel(eventItem.modelData)
                                color: win.secondaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            width: parent.width
                            text: eventItem.modelData.title || "Untitled Event"
                            color: win.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: !!eventItem.modelData.location
                            width: parent.width
                            text: eventItem.modelData.location || ""
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 10
                width: 24
                height: 24
                radius: 12
                color: closeEventHover.hovered ? win.hoverFill : "transparent"
                scale: closeEventTap.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 18 } }
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: win.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                }
                HoverHandler { id: closeEventHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: closeEventTap
                    onPressedChanged: if (pressed) win.closeEventPopover()
                }
            }
        }

        Rectangle {
            id: toolPopover
            visible: opacity > 0.002
            opacity: win.shown && win.toolEditorMode !== "" ? 1 : 0
            scale: win.toolEditorMode !== "" ? 1 : 0.97
            transformOrigin: Item.TopLeft
            Behavior on opacity { AppleSpring { spring: 20 } }
            Behavior on scale { AppleSpring { spring: 20 } }

            x: stack.x + stack.width + 10
            y: stack.y
            width: 342
            height: toolEditor.implicitHeight + 32
            radius: 20
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 210
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 20
                samples: 41
                verticalOffset: 7
                color: Qt.rgba(0, 0, 0, win.dark ? 0.44 : 0.22)
            }

            MouseArea { anchors.fill: parent }

            ClockViews.ClockToolEditor {
                id: toolEditor
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: implicitHeight
                mode: win.toolEditorMode
                dark: win.dark
                accent: win.accent
                primaryText: win.primaryText
                secondaryText: win.secondaryText
                surface: win.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                lineColor: win.cardBorder
                onCancelled: win.closeToolEditor()
                onSaved: win.closeToolEditor()
                onDetailRequested: mode => {
                    win.waveformEditorOpen = false
                    win.toolDetailMode = win.toolDetailMode === mode ? "" : mode
                }
            }
        }

        Rectangle {
            id: detailPopover
            visible: opacity > 0.002
            opacity: win.shown && win.toolEditorMode !== "" && win.toolDetailMode !== "" ? 1 : 0
            scale: win.toolDetailMode !== "" ? 1 : 0.97
            transformOrigin: Item.TopLeft
            Behavior on opacity { AppleSpring { spring: 20 } }
            Behavior on scale { AppleSpring { spring: 20 } }

            x: toolPopover.x + toolPopover.width + 10
            y: toolPopover.y
            width: 310
            height: toolDetail.implicitHeight + 32
            radius: 20
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 220
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 20
                samples: 41
                verticalOffset: 7
                color: Qt.rgba(0, 0, 0, win.dark ? 0.44 : 0.22)
            }

            MouseArea { anchors.fill: parent }

            ClockViews.ClockToolDetail {
                id: toolDetail
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: implicitHeight
                mode: win.toolDetailMode
                currentRepeatDays: toolEditor.repeatDays
                currentSound: toolEditor.selectedSound
                accent: win.accent
                primaryText: win.primaryText
                secondaryText: win.secondaryText
                hoverFill: win.hoverFill
                lineColor: win.cardBorder
                onCancelled: win.closeToolDetail()
                onRepeatSelectionChanged: days => toolEditor.repeatDays = days
                onSoundSelected: soundId => {
                    toolEditor.selectedSound = soundId
                    win.closeToolDetail()
                }
                onWaveformRequested: sound => {
                    win.soundFilePickerOpen = false
                    win.waveformSound = sound
                    win.waveformEditorOpen = true
                    Qt.callLater(() => waveformEditor.resetSelection())
                }
                onFilePickerRequested: {
                    win.waveformEditorOpen = false
                    win.soundFilePickerOpen = true
                }
            }
        }

        Rectangle {
            id: waveformPopover
            visible: opacity > 0.002
            opacity: win.shown && win.waveformEditorOpen ? 1 : 0
            scale: win.waveformEditorOpen ? 1 : 0.97
            transformOrigin: Item.TopLeft
            Behavior on opacity { AppleSpring { spring: 20 } }
            Behavior on scale { AppleSpring { spring: 20 } }

            x: Math.min(win.width - width - 10, detailPopover.x + detailPopover.width + 10)
            y: detailPopover.y
            width: 442
            height: waveformEditor.implicitHeight + 32
            radius: 20
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 230
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 22
                samples: 45
                verticalOffset: 8
                color: Qt.rgba(0, 0, 0, win.dark ? 0.46 : 0.24)
            }

            MouseArea { anchors.fill: parent }

            ClockViews.ClockWaveformEditor {
                id: waveformEditor
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: implicitHeight
                soundInfo: win.waveformSound
                active: win.shown && win.waveformEditorOpen
                accent: win.accent
                primaryText: win.primaryText
                secondaryText: win.secondaryText
                surface: win.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                lineColor: win.cardBorder
                onCancelled: win.waveformEditorOpen = false
                onCreated: sound => {
                    toolDetail.pendingSound = sound.id
                    win.waveformEditorOpen = false
                }
            }
        }

        Rectangle {
            id: filePickerPopover
            visible: opacity > 0.002
            opacity: win.shown && win.soundFilePickerOpen ? 1 : 0
            scale: win.soundFilePickerOpen ? 1 : 0.97
            transformOrigin: Item.TopLeft
            Behavior on opacity { AppleSpring { spring: 20 } }
            Behavior on scale { AppleSpring { spring: 20 } }

            x: Math.min(win.width - width - 10, detailPopover.x + detailPopover.width + 10)
            y: detailPopover.y
            width: 502
            height: filePicker.implicitHeight + 32
            radius: 20
            color: win.cardBg
            border.color: win.cardBorder
            border.width: 1
            z: 240
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 22
                samples: 45
                verticalOffset: 8
                color: Qt.rgba(0, 0, 0, win.dark ? 0.46 : 0.24)
            }

            MouseArea { anchors.fill: parent }

            ClockViews.ClockFilePicker {
                id: filePicker
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: implicitHeight
                active: win.soundFilePickerOpen
                accent: win.accent
                primaryText: win.primaryText
                secondaryText: win.secondaryText
                hoverFill: win.hoverFill
                lineColor: win.cardBorder
                onCancelled: win.soundFilePickerOpen = false
                onFileSelected: path => {
                    win.soundFilePickerOpen = false
                    toolDetail.acceptPickedFile(path)
                }
            }
        }
    }
}
