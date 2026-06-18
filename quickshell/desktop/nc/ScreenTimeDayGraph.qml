import QtQuick

// Hourly screen-time breakdown for one day (iOS Screen Time "day" view). 24
// bars, one per hour, each a stack of that hour's app categories in Apple's
// category colours; height ∝ minutes used that hour on a fixed 60-minute scale.
// The x-axis is split into the four 6-hour blocks: 12 AM · 6 AM · 12 PM · 6 PM.
// Hourly data only exists from when per-hour tracking began, so older days read
// empty.
Item {
    id: graph
    readonly property bool dark: ThemeService.isDark

    property var hours: []          // [{ hour, total, segments:[{cls,seconds}] }] ×24
    property var catColors: ({})      // categoryKey → colour (selected day's ranking)
    property var catOrder: []         // categoryKeys in rank order (blue → … → grey)
    // When set (a window class), each hour bar isolates that app: its slice in
    // blue over the rest of the hour in grey. "" = normal category view.
    property string focusApp: ""

    // App-focus palette: the isolated app's blue, and the grey for the rest of
    // each hour's total (matches the week chart's unselected grey).
    readonly property color focusColor: graph.dark ? "#0A84FF" : "#007AFF"
    readonly property color focusRest:  graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.30)

    readonly property int plotH: 96
    readonly property int rightGutter: 40   // matches the week chart so plots align
    readonly property int xAxisH: 16
    readonly property int hourSecs: 3600    // fixed full-hour (60m) scale

    implicitHeight: plotH + xAxisH

    readonly property real plotW: width - rightGutter
    readonly property real slotW: plotW / 24

    // Total hourly seconds — drives the "no detail" placeholder for old days.
    readonly property int hourTotal: {
        let t = 0
        for (let i = 0; i < graph.hours.length; i++) t += graph.hours[i].total
        return t
    }

    readonly property var blocks: [
        { hour: 0,  text: "12 AM" },
        { hour: 6,  text: "6 AM"  },
        { hour: 12, text: "12 PM" },
        { hour: 18, text: "6 PM"  }
    ]

    // Horizontal gridlines (5 levels) + minute-axis labels. Only the top/middle/
    // bottom lines are labelled — the 2nd & 4th are bare lines, matching the
    // weekly chart above.
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
                visible: gridLine.modelData === 1.0 || gridLine.modelData === 0.5 || gridLine.modelData === 0.0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: modelData === 0 ? "0" : Math.round(60 * modelData) + "m"
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }
    }

    // Faint vertical separators at each 6-hour block boundary.
    Repeater {
        model: graph.blocks
        delegate: Rectangle {
            required property var modelData
            visible: modelData.hour > 0
            x: modelData.hour * graph.slotW
            width: 1
            height: graph.plotH
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
        }
    }

    // Bars — one stacked column per hour.
    Item {
        width: graph.plotW
        height: graph.plotH

        Repeater {
            model: graph.hours
            delegate: Item {
                id: bar
                required property var modelData
                required property int index
                x: index * graph.slotW
                width: graph.slotW
                height: graph.plotH

                // This hour's segments. In app-focus mode: the app's slice (blue)
                // over the rest of the hour (grey). Otherwise this hour's apps
                // rolled up into category segments, coloured by the selected day's
                // ranking and reversed for the Column so rank 0 (blue) lands at
                // the bottom with the colour bands lined up across every bar.
                readonly property var stack: {
                    if (graph.focusApp !== "") {
                        let app = 0
                        let segs = modelData.segments
                        for (let i = 0; i < segs.length; i++)
                            if (segs[i].cls === graph.focusApp) { app = segs[i].seconds; break }
                        let rest = Math.max(0, modelData.total - app)
                        let out = []
                        if (rest > 0) out.push({ seconds: rest, color: graph.focusRest })
                        if (app > 0)  out.push({ seconds: app,  color: graph.focusColor })
                        return out
                    }
                    let m = ({})
                    let segs = modelData.segments
                    for (let i = 0; i < segs.length; i++) m[segs[i].cls] = segs[i].seconds
                    return ScreenTimeService.orderedSegments(m, graph.catOrder, graph.catColors).reverse()
                }

                Column {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    width: Math.max(2, graph.slotW - 4)
                    Repeater {
                        model: bar.stack
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: Math.round(graph.plotH * modelData.seconds / graph.hourSecs)
                            color: modelData.color
                        }
                    }
                }
            }
        }

        // Placeholder for days tracked before hourly data existed.
        Text {
            visible: graph.hourTotal === 0
            anchors.centerIn: parent
            text: "No hourly detail for this day"
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }

    // X-axis block labels (left-aligned at each 6-hour boundary).
    Item {
        width: graph.plotW
        y: graph.plotH + 2
        height: graph.xAxisH

        Repeater {
            model: graph.blocks
            delegate: Text {
                required property var modelData
                x: modelData.hour * graph.slotW
                text: modelData.text
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.40)
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }
    }
}
