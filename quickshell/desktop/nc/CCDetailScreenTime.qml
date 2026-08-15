import Quickshell
import QtQuick
import QtQuick.Controls
import "kinetic.js" as Kinetic
import "../icons" as Icons

// Screen Time detail panel. Mirrors the iOS Screen Time layout: a "Usage" header
// with the selected day's total, a tappable weekly bar chart, and a per-app
// breakdown of that day below. Data comes from ScreenTimeService, which samples
// the focused window — so this is screen-on time per app, not battery drain.
Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    // Day currently being inspected; defaults to today.
    property string selectedDay: ScreenTimeService.day !== ""
        ? ScreenTimeService.day : ScreenTimeService._today()

    // App isolated in the charts (window class) — set by tapping an Apps Usage
    // row, cleared by tapping it again. "" = whole-day category view. Cleared
    // whenever the day changes (see goToDay), so each day opens on its full view.
    property string selectedApp: ""

    // Week-average view: picking a week from the dropdown shows that week's daily
    // average instead of a single day — header reads "<range> Average", the chart
    // colours every day by category, and the legend/app list aggregate the week.
    // `selectedDay` still points at a day inside the week so labels/nav resolve.
    // Any day-level navigation (tapping a bar, ‹ › or Today) drops back to days.
    property bool weekMode: false

    // The calendar week (Sun→Sat) containing the selected day, so navigating into
    // a past day flips the chart to that week. The `ScreenTimeService.days` read
    // makes these bindings re-evaluate as today's tally grows while open.
    readonly property var week: {
        let _ = ScreenTimeService.days
        return ScreenTimeService.weekOf(root.selectedDay)
    }
    // Selected day's app breakdown + total — or the whole week's aggregate while
    // in week-average mode.
    readonly property var dayApps: {
        let _ = ScreenTimeService.days
        return root.weekMode
            ? ScreenTimeService.rankedWeekApps(root.selectedDay)
            : ScreenTimeService.rankedFor(root.selectedDay)
    }
    // Selected day's per-hour breakdown (re-evaluates as `hours` grows).
    readonly property var dayHours: {
        let _ = ScreenTimeService.hours
        return ScreenTimeService.hoursFor(root.selectedDay)
    }
    // Selected day's category ranking — drives every colour on this panel: the
    // charts, the per-app bars, and the top-3 legend. Top category = blue, 2nd =
    // orange, 3rd = teal, rest grey (iOS Screen Time rule). The whole week chart
    // is coloured from the *selected* day's ranking, so colours stay stable as
    // you scrub days.
    readonly property var catBreakdown: {
        let _ = ScreenTimeService.days
        return ScreenTimeService.categoryBreakdown(root.weekMode
            ? ScreenTimeService.weekAppMap(root.selectedDay)
            : (ScreenTimeService.days[root.selectedDay] || {}))
    }
    readonly property var catColors: {
        let m = ({})
        for (let i = 0; i < root.catBreakdown.length; i++) m[root.catBreakdown[i].key] = root.catBreakdown[i].color
        return m
    }
    // Category keys in rank order — fixes the stack order so the same colour band
    // sits at the same height on every bar (blue at the bottom).
    readonly property var catOrder: {
        let o = []
        for (let i = 0; i < root.catBreakdown.length; i++) o.push(root.catBreakdown[i].key)
        return o
    }
    readonly property int selectedTotal: {
        let _ = ScreenTimeService.days
        return ScreenTimeService.totalFor(root.selectedDay)
    }
    // Daily average across the selected week (week-average mode headline).
    readonly property int weekAvgSecs: {
        let _ = ScreenTimeService.days
        return ScreenTimeService.weekAverage(root.selectedDay)
    }
    // Focused app's time on the selected day, and its average across the selected
    // week. Both touch `days` so they re-settle live as today's tally grows.
    readonly property int selectedAppSecs: {
        let _ = ScreenTimeService.days
        return root.selectedApp !== ""
            ? ScreenTimeService.appSecondsFor(root.selectedDay, root.selectedApp) : 0
    }
    readonly property int selectedAppWeekAvg: {
        let _ = ScreenTimeService.days
        return root.selectedApp !== ""
            ? ScreenTimeService.appWeekAverage(root.selectedDay, root.selectedApp) : 0
    }
    // Weeks available in the picker dropdown (those with usage, plus this week).
    readonly property var weekList: {
        let _ = ScreenTimeService.days
        return ScreenTimeService.availableWeeks()
    }
    // Sunday key of the selected day's week — highlights the matching picker row.
    readonly property string selectedWeekKey: ScreenTimeService._sundayKey(root.selectedDay)

    // Navigation bounds: can't step past today; oldest reachable day is capped to
    // the service's retention window so the arrows don't march off into nothing.
    readonly property bool isToday: root.selectedDay === ScreenTimeService.day
    readonly property string minDay:
        ScreenTimeService.addDays(ScreenTimeService.day, -(ScreenTimeService.keepDays - 1))
    readonly property bool canPrev: root.selectedDay > root.minDay
    readonly property bool canNext: root.selectedDay < ScreenTimeService.day

    // Jump to `key`, clamped to [minDay, today]. Any day jump leaves week mode
    // and clears the focused app, so moving to another day shows that whole day.
    function goToDay(key) {
        if (key > ScreenTimeService.day) key = ScreenTimeService.day
        if (key < root.minDay) key = root.minDay
        if (key !== root.selectedDay) root.selectedApp = ""
        root.selectedDay = key
        root.weekMode = false
    }
    function step(n) { root.goToDay(ScreenTimeService.addDays(root.selectedDay, n)) }

    // Enter week-average mode for the week (by its Sunday key). Anchor selectedDay
    // on the week's most recent day with usage (else its latest non-future day) so
    // labels and day-navigation still resolve, then flip to the average view.
    function enterWeek(weekKey) {
        let w = ScreenTimeService.weekOf(weekKey)
        let today = ScreenTimeService.day
        let pick = "", fallback = ""
        for (let i = w.length - 1; i >= 0; i--) {
            if (w[i].key > today) continue
            if (fallback === "") fallback = w[i].key
            if (w[i].seconds > 0) { pick = w[i].key; break }
        }
        root.selectedApp = ""
        root.selectedDay = pick !== "" ? pick : (fallback !== "" ? fallback : weekKey)
        root.weekMode = true
    }

    // "May 11-17" (or "May 28 – Jun 3" across a month boundary) for the week
    // containing `dayKey`.
    function weekLabel(dayKey) {
        let d = ScreenTimeService._parse(dayKey)
        let sun = new Date(d.getFullYear(), d.getMonth(), d.getDate() - d.getDay())
        let sat = new Date(sun.getFullYear(), sun.getMonth(), sun.getDate() + 6)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        if (sun.getMonth() === sat.getMonth())
            return months[sun.getMonth()] + " " + sun.getDate() + "-" + sat.getDate()
        return months[sun.getMonth()] + " " + sun.getDate() + " – "
             + months[sat.getMonth()] + " " + sat.getDate()
    }

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10

        CCDetailHeader {
            width: parent.width
            title: "Screen Time"
            onBack: root.back()
        }

        // ── Usage header + weekly chart ──────────────────────────────────────
        Rectangle {
            width: parent.width
            radius: 12
            color: ThemeService.tileBg
            height: chartCol.implicitHeight + 28

            Column {
                id: chartCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 14

                // "Usage  ·  10h 19m" on the left, the day label on the right.
                Item {
                    width: parent.width
                    height: usageCol.implicitHeight

                    Column {
                        id: usageCol
                        anchors { left: parent.left; top: parent.top }
                        spacing: 1
                        Text {
                            // Week mode: "<range> Average". Else "Usage", or
                            // "<App> Usage" while an app is focused.
                            text: root.weekMode
                                ? root.weekLabel(root.selectedDay) + " Average"
                                : (root.selectedApp !== ""
                                    ? ScreenTimeService.displayName(root.selectedApp) + " Usage"
                                    : "Usage")
                            color: ThemeService.textSecondary
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            // Week mode: the daily average. Else the focused app's
                            // time on the selected day, or the whole-day total.
                            text: ScreenTimeService.fmt(root.weekMode
                                ? root.weekAvgSecs
                                : (root.selectedApp !== "" ? root.selectedAppSecs : root.selectedTotal))
                            color: ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 26
                            font.weight: Font.Bold
                            font.letterSpacing: -0.55
                        }
                    }

                    // Date navigation: [picker dropdown] [‹] [Today] [›]
                    Row {
                        anchors { right: parent.right; verticalCenter: usageCol.verticalCenter }
                        spacing: 6

                        // Picker — opens a list of recorded days.
                        Rectangle {
                            id: ddBtn
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            width: ddRow.implicitWidth + 18
                            radius: 8
                            color: (ddMa.containsMouse || dateListPopup.opened)
                                ? ThemeService.rowBgHover
                                : ThemeService.rowBg
                            border.width: 0
                            scale: ddMa.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 13 } }

                            Row {
                                id: ddRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.weekLabel(root.selectedDay)
                                    color: ThemeService.textPrimary
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅀"
                                    color: ThemeService.textTertiary
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: ddMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dateListPopup.opened ? dateListPopup.close()
                                                                : dateListPopup.open()
                            }

                            Popup {
                                id: dateListPopup
                                y: ddBtn.height + 6
                                x: ddBtn.width - width            // right-aligned under the button
                                width: 210
                                padding: 6
                                closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

                                background: Rectangle {
                                    radius: 12
                                    color: ThemeService.popupBg
                                    border.color: ThemeService.stroke
                                    border.width: 1
                                }

                                contentItem: ListView {
                                    implicitHeight: Math.min(contentHeight, 244)
                                    clip: true
                                    model: root.weekList
                                    spacing: 2
                                    boundsBehavior: Flickable.DragAndOvershootBounds
                                    boundsMovement: Flickable.FollowBoundsBehavior
                                    rebound: Transition {
                                        SpringAnimation {
                                            properties: "x,y"
                                            spring: 13
                                            damping: ThemeService.momentumDamping
                                            epsilon: 0.25
                                        }
                                    }
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: Rectangle {
                                        required property var modelData
                                        width: ListView.view.width
                                        height: 34
                                        radius: 8
                                        readonly property bool sel: modelData.weekKey === root.selectedWeekKey
                                        scale: rowMa.pressed ? 0.985 : 1
                                        Behavior on scale { AppleSpring { spring: 13 } }
                                        color: sel
                                            ? ThemeService.rowBgActive
                                            : (rowMa.containsMouse ? ThemeService.rowBgHover
                                                                   : "transparent")

                                        Text {
                                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                            text: root.weekLabel(modelData.weekKey)
                                            color: parent.sel ? "#0A84FF" : ThemeService.textPrimary
                                            font.family: "SF Pro Display"
                                            font.pixelSize: 12
                                            font.weight: parent.sel ? Font.DemiBold : Font.Normal
                                        }
                                        Text {
                                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            text: ScreenTimeService.fmt(modelData.seconds)
                                            color: ThemeService.textTertiary
                                            font.family: "SF Pro Display"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: rowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { root.enterWeek(modelData.weekKey); dateListPopup.close() }
                                        }
                                    }
                                }
                            }
                        }

                        // ‹ previous day
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 8
                            enabled: root.canPrev
                            opacity: enabled ? 1 : 0.35
                            color: prevMa.containsMouse ? ThemeService.rowBgHover : ThemeService.rowBg
                            border.width: 0
                            scale: prevMa.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 13 } }
                            Text {
                                anchors.centerIn: parent
                                text: "󰅁"
                                color: ThemeService.textPrimary
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.step(-1)
                            }
                        }

                        // Today — jump back to today (disabled when already there).
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            width: todayText.implicitWidth + 22
                            radius: 8
                            enabled: !root.isToday
                            opacity: enabled ? 1 : 0.5
                            color: (todayMa.containsMouse && enabled)
                                ? ThemeService.rowBgHover
                                : ThemeService.rowBg
                            border.width: 0
                            scale: todayMa.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 13 } }
                            Text {
                                id: todayText
                                anchors.centerIn: parent
                                text: "Today"
                                color: ThemeService.textPrimary
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: todayMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.goToDay(ScreenTimeService.day)
                            }
                        }

                        // › next day
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28; radius: 8
                            enabled: root.canNext
                            opacity: enabled ? 1 : 0.35
                            color: nextMa.containsMouse ? ThemeService.rowBgHover : ThemeService.rowBg
                            border.width: 0
                            scale: nextMa.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 13 } }
                            Text {
                                anchors.centerIn: parent
                                text: "󰅂"
                                color: ThemeService.textPrimary
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.step(1)
                            }
                        }
                    }
                }

                ScreenTimeWeekGraph {
                    width: parent.width
                    week: root.week
                    // No single-day highlight while showing the week average.
                    selectedKey: root.weekMode ? "" : root.selectedDay
                    maxKey: ScreenTimeService.day
                    catColors: root.catColors
                    catOrder: root.catOrder
                    focusApp: root.selectedApp
                    colorAll: root.weekMode
                    // Tapping a bar drills into that day (and leaves week mode).
                    onDaySelected: (key) => root.goToDay(key)
                }

                // Extra breathing room separates the two charts — no divider line,
                // padding only (chartCol's 14px spacing plus this spacer).
                Item { width: parent.width; height: 4; visible: !root.weekMode }

                // Hourly detail for the selected day (12 AM · 6 AM · 12 PM · 6 PM).
                // Hidden in week mode — there's no single day to break down.
                ScreenTimeDayGraph {
                    width: parent.width
                    visible: !root.weekMode
                    hours: root.dayHours
                    catColors: root.catColors
                    catOrder: root.catOrder
                    focusApp: root.selectedApp
                }

                // Top-3 category legend (swatch + name, time below) — the same
                // ranking/colours the charts use. Hidden when the day has no usage
                // or while an app is focused (the app legend takes its place).
                Row {
                    id: catLegendRow
                    width: parent.width
                    // Content-sized items packed from the left with a steady gap —
                    // the first sits under 12 AM, the rest follow at a comfortable
                    // distance (not crammed, not flung to the edges).
                    spacing: 70
                    visible: root.catBreakdown.length > 0 && root.selectedApp === ""
                    Repeater {
                        model: Math.min(3, root.catBreakdown.length)
                        delegate: Item {
                            id: legendItem
                            required property int index
                            readonly property var cat: root.catBreakdown[index]
                            // Hug the content so the row's spacing sets the gaps.
                            width: Math.max(nameRow.width, timeText.width)
                            height: timeText.y + timeText.height

                            // Swatch + name, left-aligned within the item.
                            Row {
                                id: nameRow
                                anchors.left: parent.left
                                spacing: 5
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 9; height: 9; radius: 2
                                    color: legendItem.cat.color
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    // Snug for short names; guard against a single
                                    // runaway label eating the whole row.
                                    width: Math.min(implicitWidth, catLegendRow.width * 0.55)
                                    text: legendItem.cat.label
                                    elide: Text.ElideRight
                                    color: ThemeService.textSecondary
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                }
                            }
                            // Time, left-aligned to the swatch's left edge (the
                            // start of the name row), not centred under the name.
                            Text {
                                id: timeText
                                anchors { top: nameRow.bottom; topMargin: 2; left: nameRow.left }
                                text: ScreenTimeService.fmt(legendItem.cat.seconds)
                                color: ThemeService.textPrimary
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // App-focus legend (replaces the category legend while an app is
                // focused): blue = the app + its time on the selected day; grey =
                // "Total Screen Time Average" + the app's average use this week.
                Item {
                    id: appLeg
                    width: parent.width
                    visible: root.selectedApp !== ""
                    height: Math.max(appLegCol.height, avgLegCol.height)

                    // Left: the focused app, blue swatch.
                    Column {
                        id: appLegCol
                        anchors.left: parent.left
                        spacing: 2
                        Row {
                            spacing: 5
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 9; height: 9; radius: 2
                                color: dark ? "#0A84FF" : "#007AFF"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, appLeg.width / 2 - 14)
                                text: ScreenTimeService.displayName(root.selectedApp)
                                elide: Text.ElideRight
                                color: ThemeService.textSecondary
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            // Left edge aligned to the swatch above (column start).
                            text: ScreenTimeService.fmt(root.selectedAppSecs)
                            color: ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    // Right: this app's weekly average, grey swatch (starts mid-
                    // panel and runs to the right edge, like the screenshot).
                    Column {
                        id: avgLegCol
                        anchors.left: parent.horizontalCenter
                        anchors.right: parent.right
                        spacing: 2
                        Row {
                            spacing: 5
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 9; height: 9; radius: 2
                                color: ThemeService.textTertiary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, avgLegCol.width - 14)
                                text: "Total Screen Time Average"
                                elide: Text.ElideRight
                                color: ThemeService.textSecondary
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            // Left edge aligned to the swatch above (column start).
                            text: ScreenTimeService.fmt(root.selectedAppWeekAvg)
                            color: ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        // Breathing room between the chart and the per-app list.
        Item { width: parent.width; height: 6 }

        // ── Apps usage (moved out of the Battery detail) ─────────────────────
        Item {
            width: parent.width
            height: 16
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Apps Usage"
                color: ThemeService.textSecondary
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.weekMode
                    ? "Week total " + ScreenTimeService.fmt(ScreenTimeService.weekTotalFor(root.selectedDay))
                    : (root.selectedTotal > 0
                        ? "Screen time " + ScreenTimeService.fmt(root.selectedTotal)
                        : "")
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }

        Rectangle {
            id: appsCard
            width: parent.width
            radius: 12
            color: ThemeService.tileBg

            readonly property int rowH: 44
            readonly property int maxVisibleRows: 6
            readonly property int appCount: root.dayApps.length

            // Cap the card at 6 rows; past that the list scrolls internally so
            // the control-center window height stays fixed.
            height: (appCount === 0
                ? emptyLabel.implicitHeight
                : Math.min(appCount, maxVisibleRows) * rowH) + 12

            // Snug, right-aligned time column sized to the widest label (the top
            // app's, with the longest duration) so the bar↔time gap stays small
            // while the time sits flush to a right margin matching the left —
            // the whole row reads centered rather than hugging the left edge.
            TextMetrics {
                id: timeMetrics
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                text: appsCard.appCount > 0
                    ? ScreenTimeService.fmt(root.dayApps[0].seconds)
                    : "00m"
            }
            readonly property int timeColW: Math.ceil(timeMetrics.advanceWidth) + 2

            Text {
                id: emptyLabel
                visible: appsCard.appCount === 0
                anchors {
                    top: parent.top; left: parent.left; right: parent.right
                    leftMargin: 12; rightMargin: 12; topMargin: 6
                }
                horizontalAlignment: Text.AlignHCenter
                topPadding: 10; bottomPadding: 10
                text: root.weekMode
                    ? "No usage tracked this week"
                    : (root.selectedDay === ScreenTimeService.day
                        ? "No usage tracked yet — collecting…"
                        : "No usage tracked on this day")
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }

            ListView {
                id: appsList
                visible: appsCard.appCount > 0
                // Full card width so the selection highlight can run edge to edge;
                // the 12px content inset lives on each row's icon/time instead.
                anchors {
                    top: parent.top; left: parent.left; right: parent.right
                    leftMargin: 0; rightMargin: 0; topMargin: 6
                }
                // Viewport caps at 6 rows; the rest scrolls.
                height: Math.min(count, appsCard.maxVisibleRows) * appsCard.rowH
                clip: true
                model: root.dayApps
                spacing: 0
                // Only grab scroll/flick gestures when there's overflow.
                interactive: count > appsCard.maxVisibleRows
                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                flickableDirection: Flickable.VerticalFlick
                rebound: Transition {
                    SpringAnimation {
                        properties: "x,y"
                        spring: 13
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }

                // Thin overlay scrollbar — fades in while scrolling the overflow.
                ScrollBar.vertical: ScrollBar {
                    id: appsScroll
                    policy: ScrollBar.AsNeeded
                    implicitWidth: 6
                    background: Item {}
                    contentItem: Rectangle {
                        implicitWidth: 3
                        radius: 1.5
                        color: ThemeService.textTertiary
                        opacity: appsScroll.active ? 1 : 0
                        Behavior on opacity { AppleSpring { spring: 13 } }
                    }
                }

                // Kinetic scroll: touchpad momentum + crisp mouse notches, via
                // the shared kinetic.js (same feel as the rest of the shell).
                property var _ks: ({})
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        appsGlide.stop()
                        if (Kinetic.onWheel(appsList, ev, appsList._ks, { gain: appsCard.rowH }))
                            appsEnd.restart()
                    }
                }
                Timer {
                    id: appsEnd
                    interval: 70
                    onTriggered: {
                        let g = Kinetic.fling(appsList, appsList._ks, {})
                        if (g) { appsGlide.to = g.to; appsGlide.restart() }
                    }
                }
                SpringAnimation {
                    id: appsGlide
                    target: appsList
                    property: "contentY"
                    spring: 13
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }

                delegate: Item {
                        id: appRow
                        required property var modelData
                        required property int index
                        width: appsList.width
                        height: appsCard.rowH
                        // This row is the focused app → blue pill + white text.
                        readonly property bool appSel: root.selectedApp === modelData.cls

                        // Selection highlight — a blue pill behind the row, inset
                        // vertically so consecutive rows stay distinct.
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 3; anchors.bottomMargin: 3
                            radius: 8
                            visible: appRow.appSel
                            color: dark ? "#0A84FF" : "#007AFF"
                        }

                        // Icon on the left, vertically centered in the row.
                        Icons.AppIcon {
                            id: appIcon
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28
                            sourceSize.width: 56; sourceSize.height: 56
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true; asynchronous: true
                            iconName: ScreenTimeService.iconNameFor(modelData.cls)
                            appClass: modelData.cls
                        }

                        // Time, right-aligned and flush to the right margin (which
                        // matches the icon's left margin → the row reads centered).
                        Text {
                            id: timeLabel
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            width: appsCard.timeColW
                            horizontalAlignment: Text.AlignRight
                            text: ScreenTimeService.fmt(modelData.seconds)
                            color: appRow.appSel ? "#ffffff" : ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        // App name — left-aligned between the icon and the time.
                        Text {
                            anchors {
                                left: appIcon.right; leftMargin: 12
                                right: timeLabel.left; rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: ScreenTimeService.displayName(modelData.cls)
                            elide: Text.ElideRight
                            color: appRow.appSel ? "#ffffff" : ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        // Hairline divider between rows (skipped after the last and
                        // under the highlighted row).
                        Rectangle {
                            visible: index < appsList.count - 1 && !appRow.appSel
                            anchors {
                                left: parent.left; leftMargin: 12
                                right: parent.right; rightMargin: 12
                                bottom: parent.bottom
                            }
                            height: 1
                            color: ThemeService.separator
                        }

                        // Tap to focus this app across the charts; tap again to
                        // clear and return to the whole-day category view.
                        // App focus is a day-view feature; in week mode the list is
                        // a read-only weekly aggregate.
                        MouseArea {
                            id: appRowMa
                            anchors.fill: parent
                            enabled: !root.weekMode
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedApp =
                                (root.selectedApp === modelData.cls ? "" : modelData.cls)
                        }
                        scale: appRowMa.pressed ? 0.985 : 1
                        Behavior on scale { AppleSpring { spring: 13 } }
                    }
            }
        }
    }
}
