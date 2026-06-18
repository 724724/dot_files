import QtQuick

// Weekly screen-time bar chart (iOS Screen Time style). One bar per day over the
// trailing week; height ∝ that day's total active screen time. The selected day
// is highlighted in the accent colour and its column letter bolds; tapping a bar
// re-selects it. A green dashed line marks the daily average.
Item {
    id: graph
    readonly property bool dark: ThemeService.isDark

    // Non-selected days collapse to one flat grey bar. Heavier than the "Other"
    // category grey so the greyed-out week still reads clearly against the chart.
    readonly property color unselectedColor: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.30)

    property var week: []            // [{ key, date, seconds, isToday, dow }]
    property string selectedKey: ""
    property string maxKey: ""       // days after this are future: faded, not tappable
    property var catColors: ({})      // categoryKey → colour (selected day's ranking)
    property var catOrder: []         // categoryKeys in rank order (blue → … → grey)
    // When set (a window class), the chart isolates that app: each day's bar is
    // its total in grey with the app's slice painted blue at the base, instead of
    // the category stack. "" = normal category view.
    property string focusApp: ""
    // Week-average view: colour EVERY day by its category stack (using the shared
    // week colour scheme) instead of just the selected day. No single day is
    // highlighted in this mode.
    property bool colorAll: false
    signal daySelected(string key)

    // App-focus blue (iOS Screen Time accent); the rest of each day's total reuses
    // the same grey unselected days wear.
    readonly property color focusColor: graph.dark ? "#0A84FF" : "#007AFF"

    // App-focus stack for one day's bar, ordered top→bottom for the Column: the
    // rest of the day (grey) sits above the app's slice (blue) at the baseline.
    // Zero-height pieces are dropped so the rounded top lands on whatever shows.
    function focusStack(total, app) {
        let rest = Math.max(0, total - app)
        let out = []
        if (rest > 0) out.push({ seconds: rest, color: graph.unselectedColor })
        if (app > 0)  out.push({ seconds: app,  color: graph.focusColor })
        return out
    }

    readonly property int plotH: 120
    readonly property int rightGutter: 40   // room for the duration axis labels
    readonly property int xAxisH: 18

    implicitHeight: plotH + xAxisH

    readonly property real plotW: width - rightGutter
    readonly property int n: week.length
    readonly property real slotW: n > 0 ? plotW / n : plotW

    // Scale so the tallest day fills the plot, but always round the cap UP to a
    // whole hour (5.7h → 6h, 5.4h → 6h) so the top axis label is a clean 1h unit
    // and bars sit a touch shorter. Never below 1h — a near-empty week still
    // reads on a sensible axis.
    readonly property int maxSecs: {
        let m = 3600
        for (let i = 0; i < week.length; i++) m = Math.max(m, week[i].seconds)
        return Math.ceil(m / 3600) * 3600
    }
    // Average over the days that actually have usage, not all seven — so a week
    // with a single tracked day sits the line right at that day's bar, and it
    // re-settles as more days come in. Re-evaluates whenever `week` does.
    readonly property int avgSecs: {
        let t = 0, n = 0
        for (let i = 0; i < week.length; i++) {
            if (week[i].seconds > 0) { t += week[i].seconds; n++ }
        }
        return n > 0 ? Math.round(t / n) : 0
    }

    readonly property var dowLabels: ["S", "M", "T", "W", "T", "F", "S"]

    // Vertical position of the average line (and its "avg" tag).
    readonly property real avgY: graph.plotH - graph.plotH * graph.avgSecs / Math.max(1, graph.maxSecs)

    // Axis label for a fraction of the full scale.
    function axisLabel(frac) {
        let s = Math.round(graph.maxSecs * frac)
        if (s >= 3600) {
            let h = s / 3600
            return (Math.round(h * 10) / 10) + "h"
        }
        return Math.round(s / 60) + "m"
    }

    // Horizontal gridlines + axis labels (5 levels: top … 0).
    Repeater {
        model: [1.0, 0.75, 0.5, 0.25, 0.0]
        delegate: Item {
            id: gridLine
            required property real modelData
            width: graph.width
            height: 1
            y: graph.plotH * (1 - modelData)
            Rectangle {
                width: graph.plotW; height: 1
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
            }
            Text {
                // Only the top/middle/bottom lines carry a label (the 2nd & 4th
                // are bare lines); and any label is dropped where "avg" sits.
                visible: (gridLine.modelData === 1.0 || gridLine.modelData === 0.5 || gridLine.modelData === 0.0)
                    && !(graph.avgSecs > 0 && Math.abs(gridLine.y - graph.avgY) < 10)
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: modelData === 0 ? "0" : graph.axisLabel(modelData)
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }
    }

    // Average dashed line + "avg" tag in the right gutter.
    Item {
        visible: graph.avgSecs > 0
        width: graph.width
        height: 1
        y: graph.avgY

        Row {
            width: graph.plotW
            spacing: 4
            clip: true
            Repeater {
                model: Math.ceil(graph.plotW / 10)
                delegate: Rectangle { width: 6; height: 1; color: "#34C759"; opacity: 0.85 }
            }
        }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "avg"
            color: "#34C759"
            font.family: "SF Pro Display"
            font.pixelSize: 9
        }
    }

    // Bars
    Item {
        id: plot
        width: graph.plotW
        height: graph.plotH

        Repeater {
            model: graph.week
            delegate: Item {
                id: dayCol
                required property var modelData
                required property int index
                x: index * graph.slotW
                width: graph.slotW
                height: plot.height

                readonly property bool sel: modelData.key === graph.selectedKey
                readonly property bool future: graph.maxKey !== "" && modelData.key > graph.maxKey
                // This day's stacked segments. In app-focus mode: the app (blue)
                // over the rest of the day's total (grey) — the blue slice only on
                // the selected day, every other day fully grey (app passed as 0).
                // In normal mode: the selected day shows its category stack (rank 0
                // blue at the bottom); every other day is a single flat grey bar of
                // its total, with no category subdivisions. Re-reads `days` so today
                // grows live.
                readonly property var stack:
                    graph.focusApp !== ""
                        ? graph.focusStack(modelData.seconds,
                                           dayCol.sel ? ((ScreenTimeService.days[modelData.key] || {})[graph.focusApp] || 0) : 0)
                        : (dayCol.sel || graph.colorAll)
                            ? ScreenTimeService.orderedSegments(ScreenTimeService.days[modelData.key] || {},
                                                                graph.catOrder, graph.catColors).reverse()
                            : [{ seconds: modelData.seconds, color: graph.unselectedColor }]
                readonly property int barW: Math.min(28, graph.slotW - 8)

                // Stacked bar. Selection is carried by colour alone: the selected
                // day shows its category colours, every other day is a flat grey
                // bar. No transitions: navigating days snaps to the new week.
                Column {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    width: dayCol.barW
                    opacity: dayCol.future ? 0.4 : 1
                    Repeater {
                        model: dayCol.stack
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: graph.plotH * modelData.seconds / Math.max(1, graph.maxSecs)
                            // App-focus segments carry their own colour; otherwise
                            // only the selected day shows category colours, the
                            // rest collapse to grey.
                            color: (graph.focusApp !== "" || dayCol.sel || graph.colorAll)
                                 ? modelData.color : graph.unselectedColor
                            // Just the very top of the bar is softened (top segment
                            // is index 0); inner joins and the baseline stay square.
                            topLeftRadius: index === 0 ? 3 : 0
                            topRightRadius: index === 0 ? 3 : 0
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !dayCol.future
                    cursorShape: Qt.PointingHandCursor
                    onClicked: graph.daySelected(modelData.key)
                }
            }
        }
    }

    // X-axis day-of-week letters
    Item {
        width: graph.plotW
        y: graph.plotH + 3
        height: graph.xAxisH

        Repeater {
            model: graph.week
            delegate: Text {
                required property var modelData
                required property int index
                x: index * graph.slotW
                width: graph.slotW
                horizontalAlignment: Text.AlignHCenter
                text: graph.dowLabels[modelData.dow]
                opacity: (graph.maxKey !== "" && modelData.key > graph.maxKey) ? 0.4 : 1
                color: modelData.key === graph.selectedKey
                    ? (graph.dark ? "#0A84FF" : "#007AFF")
                    : (graph.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.40))
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: modelData.key === graph.selectedKey ? Font.DemiBold : Font.Normal
            }
        }
    }
}
