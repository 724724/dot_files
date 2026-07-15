import QtQuick

// Apple Calendar-style widget with 3 layouts, themed with the exact iOS/macOS
// system colors (ThemeService). Events come from CalendarService (shared ICS
// subscriptions — Google secret iCal address, iCloud public share, any ICS).
//
// Small/medium mirror the real iOS widget: today's events as tinted cards
// under the big date, later days grouped under TOMORROW / "MONDAY, JUL 13"
// headers, collapsing to "N Events" / "N more events" summaries when there
// isn't room. Large keeps the month grid + Today section.
Item {
    id: calRoot
    property var frame
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int layout: (d && d.layout) ? d.layout : 2

    property color cardColor: ThemeService.cardBg
    property bool lightCard: !ThemeService.isDark

    readonly property color sysRed: ThemeService.accent("red")
    readonly property var today: CalendarService.now
    readonly property string dayName: Qt.locale("en_US").dayName(today.getDay(), Locale.LongFormat)
    readonly property var upcoming: CalendarService.upcoming

    // ── Day grouping (the iOS widget structure) ─────────────────────────────
    // Upcoming events bucketed by *effective* local day — an ongoing multi-day
    // event counts as today. [{ date, events }], soonest first, max 4 groups.
    readonly property var dayGroups: {
        let groups = [], curKey = "", cur = null
        let t = today.getTime()
        for (let i = 0; i < upcoming.length; i++) {
            let ev = upcoming[i]
            let d0 = new Date(Math.max(ev.startMs, t))
            let k = d0.getFullYear() + "-" + d0.getMonth() + "-" + d0.getDate()
            if (k !== curKey) {
                if (groups.length >= 4) break
                cur = { date: d0, events: [] }
                groups.push(cur)
                curKey = k
            }
            cur.events.push(ev)
        }
        return groups
    }
    readonly property var todayGroup:
        (dayGroups.length > 0 && CalendarService.sameDay(dayGroups[0].date, today)) ? dayGroups[0] : null
    readonly property var futureGroups: todayGroup ? dayGroups.slice(1) : dayGroups
    readonly property var nextGroup: futureGroups.length > 0 ? futureGroups[0] : null
    readonly property var secondGroup: futureGroups.length > 1 ? futureGroups[1] : null

    function groupLabel(dt) {
        if (CalendarService.sameDay(dt, today)) return "TODAY"
        if (CalendarService.sameDay(dt, new Date(today.getTime() + 86400000))) return "TOMORROW"
        let loc = Qt.locale("en_US")
        return loc.dayName(dt.getDay(), Locale.LongFormat).toUpperCase() + ", "
             + loc.monthName(dt.getMonth(), Locale.ShortFormat).toUpperCase() + " " + dt.getDate()
    }
    function eventDateLabel(ev) {
        if (!ev) return ""
        let dt = new Date(Math.max(Number(ev.startMs) || 0, today.getTime()))
        if (CalendarService.sameDay(dt, today)) return "TODAY"
        if (CalendarService.sameDay(dt, new Date(today.getTime() + 86400000))) return "TOMORROW"
        let day = Qt.locale("en_US").dayName(dt.getDay(), Locale.LongFormat).toUpperCase()
        let weekEnd = new Date(today.getFullYear(), today.getMonth(),
                               today.getDate() + ((7 - today.getDay()) % 7))
        weekEnd.setHours(23, 59, 59, 999)
        if (dt <= weekEnd) return day
        let month = Qt.locale("en_US").monthName(dt.getMonth(), Locale.ShortFormat).toUpperCase()
        return day + ", " + month + " " + dt.getDate()
             + (dt.getFullYear() !== today.getFullYear() ? ", " + dt.getFullYear() : "")
    }
    function moreLabel(n) { return n + (n === 1 ? " more event" : " more events") }

    readonly property string noEventsMsg: CalendarService.sources.length === 0
        ? "No calendars\nRight-click to set up" : "No more events today"
    readonly property string emptyMsg: CalendarService.sources.length === 0
        ? "No calendars\nRight-click → Edit to subscribe"
        : "No upcoming events"

    // ── An event as a tinted rounded card (bar + title + time) ──────────────
    component TintedCard: Rectangle {
        id: tc
        property var ev
        property real cardWidth: 180
        readonly property color ac: ThemeService.resolveAccent(ev ? ev.color : "blue")
        width: cardWidth
        height: 46
        radius: 10
        color: Qt.rgba(ac.r, ac.g, ac.b, ThemeService.isDark ? 0.20 : 0.12)
        Rectangle {
            id: tcBar
            anchors.left: parent.left; anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: parent.height - 16; radius: 1.5
            color: tc.ac
        }
        Column {
            anchors.left: tcBar.right; anchors.leftMargin: 7
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                width: parent.width; elide: Text.ElideRight
                text: tc.ev ? tc.ev.title : ""
                color: ThemeService.isDark ? "#FFFFFF" : Qt.darker(tc.ac, 1.75)
                font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Bold
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: tc.ev ? CalendarService.timeLabel(tc.ev) : ""
                color: ThemeService.isDark ? Qt.lighter(tc.ac, 1.12) : tc.ac
                font.family: "SF Pro Display"; font.pixelSize: 12
            }
        }
    }

    // ── "TOMORROW" / "MONDAY, JUL 13" section header ────────────────────────
    component DayHeader: Text {
        color: ThemeService.secondaryLabel
        font.family: "SF Pro Display"; font.pixelSize: 11; font.weight: Font.Bold
        font.letterSpacing: 0.4
        elide: Text.ElideRight
    }

    // ── Compact multi-event group: bar + "N Events" + names + time ──────────
    component GroupBlock: Row {
        id: gb
        property var evs: []
        property real blockWidth: 180
        readonly property color ac: ThemeService.resolveAccent(evs.length > 0 ? evs[0].color : "blue")
        width: blockWidth
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: gbCol.height - 4; radius: 1.5
            color: gb.ac
        }
        Column {
            id: gbCol
            width: gb.width - 11
            spacing: 0
            Text {
                text: gb.evs.length + " Events"
                color: ThemeService.label
                font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Bold
            }
            Repeater {
                model: Math.min(2, gb.evs.length)
                delegate: Text {
                    required property int index
                    width: gbCol.width; elide: Text.ElideRight
                    text: gb.evs[index].title
                    color: ThemeService.isDark ? Qt.lighter(gb.ac, 1.12) : gb.ac
                    font.family: "SF Pro Display"; font.pixelSize: 13
                }
            }
            Text {
                text: gb.evs.length > 0 ? CalendarService.timeLabel(gb.evs[0]) : ""
                color: ThemeService.secondaryLabel
                font.family: "SF Pro Display"; font.pixelSize: 12
            }
        }
    }

    // ── "N more events" summary line ────────────────────────────────────────
    component MoreLine: Row {
        id: ml
        property int n: 0
        property color ac: ThemeService.accent("blue")
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: 15; radius: 1.5
            color: ml.ac
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: calRoot.moreLabel(ml.n)
            color: ThemeService.secondaryLabel
            font.family: "SF Pro Display"; font.pixelSize: 13
        }
    }

    // ── One event row (large layout): colored bar + title/location/time ─────
    component EventRow: Row {
        id: er
        property var ev
        property real rowWidth: 180
        width: rowWidth
        spacing: 8
        Rectangle {
            width: 3; height: erCol.height; radius: 1.5
            color: ThemeService.resolveAccent(er.ev ? er.ev.color : "blue")
        }
        Column {
            id: erCol
            width: er.width - 11
            spacing: 1
            Text {
                width: parent.width; elide: Text.ElideRight
                text: er.ev ? er.ev.title : ""
                color: ThemeService.label
                font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                visible: !!(er.ev && er.ev.location)
                text: (er.ev && er.ev.location) ? er.ev.location : ""
                color: ThemeService.secondaryLabel
                font.family: "SF Pro Display"; font.pixelSize: 11
            }
            Text {
                text: er.ev ? CalendarService.timeLabel(er.ev) : ""
                color: ThemeService.secondaryLabel
                font.family: "SF Pro Display"; font.pixelSize: 11
            }
        }
    }

    component DatedEvent: Column {
        id: datedEvent
        property var ev
        property real itemWidth: 180
        width: itemWidth
        spacing: 6
        DayHeader {
            width: parent.width
            text: calRoot.eventDateLabel(datedEvent.ev)
        }
        EventRow {
            ev: datedEvent.ev
            rowWidth: datedEvent.width
        }
    }

    // ── Month grid: JUNE / S M T W T F S / day numbers, today circled red ───
    component MonthGrid: Column {
        id: mg
        spacing: 3
        readonly property int year: calRoot.today.getFullYear()
        readonly property int month: calRoot.today.getMonth()
        readonly property int daysIn: new Date(year, month + 1, 0).getDate()
        readonly property int lead: new Date(year, month, 1).getDay()   // 0 = Sunday
        readonly property real cw: width / 7
        property real ch: 20

        Text {
            text: Qt.locale("en_US").monthName(mg.month, Locale.LongFormat).toUpperCase()
            color: calRoot.sysRed
            font.family: "SF Pro Display"; font.pixelSize: 11; font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Grid {
            columns: 7
            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                delegate: Item {
                    required property string modelData
                    width: mg.cw; height: 14
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: ThemeService.tertiaryLabel
                        font.family: "SF Pro Display"; font.pixelSize: 9; font.weight: Font.DemiBold
                    }
                }
            }
        }
        Grid {
            columns: 7
            Repeater {
                model: mg.lead + mg.daysIn
                delegate: Item {
                    required property int index
                    readonly property int dayN: index - mg.lead + 1
                    readonly property bool valid: index >= mg.lead
                    readonly property bool isToday: valid && dayN === calRoot.today.getDate()
                    readonly property bool weekend: (index % 7) === 0 || (index % 7) === 6
                    width: mg.cw; height: mg.ch
                    Rectangle {
                        visible: parent.isToday
                        anchors.centerIn: parent
                        width: Math.min(mg.cw, mg.ch) - 1
                        height: width; radius: width / 2
                        color: calRoot.sysRed
                    }
                    Text {
                        visible: parent.valid
                        anchors.centerIn: parent
                        text: parent.valid ? parent.dayN : ""
                        color: parent.isToday ? "#FFFFFF"
                             : parent.weekend ? ThemeService.secondaryLabel : ThemeService.label
                        font.family: "SF Pro Display"; font.pixelSize: 11
                        font.weight: parent.isToday ? Font.Bold : Font.DemiBold
                    }
                }
            }
        }
    }

    component EmptyHint: Text {
        text: calRoot.emptyMsg
        color: ThemeService.secondaryLabel
        font.family: "SF Pro Display"; font.pixelSize: 11; lineHeight: 1.3
    }

    // ── Layout 1: small ─────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16
        visible: calRoot.layout === 1

        Text {
            id: sDay
            width: parent.width; elide: Text.ElideRight
            text: calRoot.dayName.toUpperCase()
            color: calRoot.sysRed
            font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Text {
            id: sDate
            anchors.top: sDay.bottom; anchors.topMargin: -3
            text: calRoot.today.getDate()
            color: ThemeService.label
            font.family: "SF Pro Display"; font.pixelSize: 36; font.weight: Font.Light; font.letterSpacing: -0.7
        }

        Column {
            anchors { top: sDate.bottom; topMargin: 8; left: parent.left; right: parent.right }
            spacing: 6

            // Today's first event as a tinted card…
            TintedCard {
                visible: calRoot.todayGroup !== null
                ev: calRoot.todayGroup ? calRoot.todayGroup.events[0] : null
                cardWidth: parent.width
            }
            // …then the next day as a header + "N more events" teaser.
            Column {
                visible: calRoot.todayGroup !== null && calRoot.nextGroup !== null
                width: parent.width
                spacing: 4
                DayHeader {
                    width: parent.width
                    text: calRoot.nextGroup ? calRoot.groupLabel(calRoot.nextGroup.date) : ""
                }
                MoreLine {
                    n: calRoot.nextGroup ? calRoot.nextGroup.events.length : 0
                    ac: ThemeService.resolveAccent(
                        (calRoot.nextGroup && calRoot.nextGroup.events.length > 0)
                            ? calRoot.nextGroup.events[0].color : "blue")
                }
            }

            // No events left today → show the next day's group in full.
            Column {
                visible: calRoot.todayGroup === null && calRoot.nextGroup !== null
                width: parent.width
                spacing: 4
                DayHeader {
                    width: parent.width
                    text: calRoot.nextGroup ? calRoot.groupLabel(calRoot.nextGroup.date) : ""
                }
                TintedCard {
                    visible: calRoot.nextGroup !== null && calRoot.nextGroup.events.length === 1
                    ev: calRoot.nextGroup ? calRoot.nextGroup.events[0] : null
                    cardWidth: parent.width
                }
                GroupBlock {
                    visible: calRoot.nextGroup !== null && calRoot.nextGroup.events.length > 1
                    evs: calRoot.nextGroup ? calRoot.nextGroup.events : []
                    blockWidth: parent.width
                }
            }
        }

        // Nothing upcoming at all.
        Text {
            visible: calRoot.dayGroups.length === 0
            anchors { top: sDate.bottom; topMargin: 18; left: parent.left; right: parent.right }
            text: calRoot.noEventsMsg
            wrapMode: Text.WordWrap
            color: ThemeService.secondaryLabel
            font.family: "SF Pro Display"; font.pixelSize: 17; lineHeight: 1.15
        }
    }

    // ── Layout 2: medium ────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16
        visible: calRoot.layout === 2

        Row {
            anchors.fill: parent
            spacing: 18

            Item {
                id: mLeft
                width: (parent.width - parent.spacing) / 2
                height: parent.height

                Text {
                    id: mDay
                    width: parent.width; elide: Text.ElideRight
                    text: calRoot.dayName.toUpperCase()
                    color: calRoot.sysRed
                    font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Bold
                    font.letterSpacing: 0.5
                }
                Text {
                    id: mDate
                    anchors.top: mDay.bottom; anchors.topMargin: -3
                    text: calRoot.today.getDate()
                    color: ThemeService.label
                    font.family: "SF Pro Display"; font.pixelSize: 36; font.weight: Font.Light; font.letterSpacing: -0.7
                }
                Column {
                    anchors { top: mDate.bottom; topMargin: 8; left: parent.left; right: parent.right }
                    spacing: 6
                    Repeater {
                        model: calRoot.todayGroup ? Math.min(2, calRoot.todayGroup.events.length) : 0
                        delegate: TintedCard {
                            required property int index
                            ev: calRoot.todayGroup ? calRoot.todayGroup.events[index] : null
                            cardWidth: parent.width
                        }
                    }
                }
                Text {
                    visible: calRoot.todayGroup === null
                    anchors { top: mDate.bottom; topMargin: 18; left: parent.left; right: parent.right }
                    text: calRoot.noEventsMsg
                    wrapMode: Text.WordWrap
                    color: ThemeService.secondaryLabel
                    font.family: "SF Pro Display"; font.pixelSize: 17; lineHeight: 1.15
                }
            }

            Column {
                width: (parent.width - parent.spacing) / 2
                height: parent.height
                spacing: 8

                Column {
                    visible: calRoot.nextGroup !== null
                    width: parent.width
                    spacing: 4
                    DayHeader {
                        width: parent.width
                        text: calRoot.nextGroup ? calRoot.groupLabel(calRoot.nextGroup.date) : ""
                    }
                    TintedCard {
                        visible: calRoot.nextGroup !== null && calRoot.nextGroup.events.length === 1
                        ev: calRoot.nextGroup ? calRoot.nextGroup.events[0] : null
                        cardWidth: parent.width
                    }
                    GroupBlock {
                        visible: calRoot.nextGroup !== null && calRoot.nextGroup.events.length > 1
                        evs: calRoot.nextGroup ? calRoot.nextGroup.events : []
                        blockWidth: parent.width
                    }
                }

                Column {
                    visible: calRoot.secondGroup !== null
                    width: parent.width
                    spacing: 4
                    DayHeader {
                        width: parent.width
                        text: calRoot.secondGroup ? calRoot.groupLabel(calRoot.secondGroup.date) : ""
                    }
                    TintedCard {
                        visible: calRoot.secondGroup !== null && calRoot.secondGroup.events.length === 1
                              && calRoot.nextGroup !== null && calRoot.nextGroup.events.length === 1
                        ev: calRoot.secondGroup ? calRoot.secondGroup.events[0] : null
                        cardWidth: parent.width
                    }
                    MoreLine {
                        visible: calRoot.secondGroup !== null
                              && !(calRoot.secondGroup.events.length === 1
                                   && calRoot.nextGroup !== null && calRoot.nextGroup.events.length === 1)
                        n: calRoot.secondGroup ? calRoot.secondGroup.events.length : 0
                        ac: ThemeService.resolveAccent(
                            (calRoot.secondGroup && calRoot.secondGroup.events.length > 0)
                                ? calRoot.secondGroup.events[0].color : "blue")
                    }
                }
            }
        }
    }

    // ── Layout 3: large ─────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 20
        visible: calRoot.layout === 3

        Text {
            id: lDay
            text: calRoot.dayName
            color: calRoot.sysRed
            font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold
        }
        Text {
            anchors.top: lDay.bottom; anchors.topMargin: -3
            text: calRoot.today.getDate()
            color: ThemeService.label
            font.family: "SF Pro Display"; font.pixelSize: 44; font.weight: Font.Light; font.letterSpacing: -0.9
        }
        MonthGrid {
            id: lGrid
            anchors { right: parent.right; top: parent.top }
            width: 200
            ch: 22
        }
        Text {
            id: lSection
            anchors { left: parent.left; top: lGrid.bottom; topMargin: 18 }
            text: "UP NEXT"
            color: ThemeService.secondaryLabel
            font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Grid {
            anchors { left: parent.left; right: parent.right; top: lSection.bottom; topMargin: 10 }
            columns: 2
            columnSpacing: 18
            rowSpacing: 14
            Repeater {
                model: Math.min(4, calRoot.upcoming.length)
                delegate: DatedEvent {
                    required property int index
                    ev: calRoot.upcoming[index]
                    itemWidth: (parent.width - 18) / 2
                }
            }
        }
        EmptyHint {
            visible: calRoot.upcoming.length === 0
            anchors { left: parent.left; top: lSection.bottom; topMargin: 10 }
        }
    }
}
