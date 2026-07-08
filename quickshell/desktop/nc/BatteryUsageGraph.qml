import QtQuick

// macOS-style 24h battery-level chart. One bar per 15 minutes (96 bars, i.e. 12
// per 3-hour segment); height = battery %. The x-axis is gridded every 3 hours
// at clock-aligned times. Charging periods are shown as a green bar along the
// baseline (with a ⚡), plus a faint green highlight behind the bars — so you
// can see when, and for how long, it was charging. Reads BatteryService.samples
// (oldest → newest) and BatteryService.histStart (epoch-ms of bucket 0).
Item {
    id: graph
    readonly property bool dark: ThemeService.isDark
    readonly property var buckets: BatteryService.samples
    readonly property real histStart: BatteryService.histStart

    readonly property int plotH: 110
    readonly property int rightGutter: 36   // room for the % axis labels
    readonly property int xAxisH: 28        // charging strip + hour labels

    implicitHeight: plotH + xAxisH

    readonly property real plotW: width - rightGutter
    // 15-min buckets; count varies (24–27h, window snapped to a 3h boundary),
    // so derive it from the data.
    // 15-min buckets covering the last 24h snapped to a 3h boundary, plus the
    // in-progress 3h cell, so the count varies (96 and up). Derived from the data.
    readonly property int nSlots: (buckets && buckets.length) ? buckets.length : 96
    readonly property real slotW: plotW / nSlots
    readonly property real spanMs: nSlots * 15 * 60 * 1000
    readonly property color green: "#34C759"

    function _fmtHour(h) {
        if (h % 12 === 0) return h < 12 ? "12 A" : "12 P"
        return "" + (h % 12)
    }

    // Clock-aligned 3-hour tick marks falling inside [histStart, now].
    readonly property var ticks: {
        let out = []
        if (!histStart || plotW <= 0) return out
        let d = new Date(histStart)
        let t = new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), 0, 0, 0)
        while (t.getTime() < histStart || (t.getHours() % 3) !== 0)
            t = new Date(t.getTime() + 3600000)
        let endMs = histStart + spanMs
        while (t.getTime() <= endMs + 1000) {
            out.push({ x: (t.getTime() - histStart) / spanMs * plotW, hour: t.getHours() })
            t = new Date(t.getTime() + 3 * 3600000)
        }
        return out
    }

    // Contiguous charging runs → baseline bar + highlight.
    readonly property var runs: {
        let r = []
        let b = buckets
        if (!b || !b.length) return r
        let i = 0
        while (i < b.length) {
            if (b[i] && b[i].has && b[i].charging) {
                let j = i
                while (j < b.length && b[j] && b[j].has && b[j].charging) j++
                r.push({ x0: i * slotW, x1: j * slotW, mid: (i + j) / 2 * slotW })
                i = j
            } else { i++ }
        }
        return r
    }

    // ── Horizontal gridlines + % labels (100 / 50 / 0) ──
    Repeater {
        model: [100, 50, 0]
        delegate: Item {
            required property int modelData
            required property int index
            width: graph.width
            height: 1
            y: graph.plotH * index / 2
            Rectangle {
                width: graph.plotW; height: 1
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: modelData + "%"
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                font.family: "SF Pro Display"; font.pixelSize: 10
            }
        }
    }

    // ── Minor gridlines at 25% / 75% (no labels) ──
    Repeater {
        model: [75, 25]
        delegate: Rectangle {
            required property int modelData
            y: graph.plotH * (1 - modelData / 100)
            width: graph.plotW
            height: 1
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
        }
    }

    // ── Vertical 3-hour gridlines ──
    Repeater {
        model: graph.ticks
        delegate: Rectangle {
            required property var modelData
            x: modelData.x
            y: 0
            width: 1
            height: graph.plotH
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)
            visible: modelData.x > 0.5 && modelData.x < graph.plotW - 0.5
        }
    }

    // ── Charging highlight (behind the bars) ──
    Repeater {
        model: graph.runs
        delegate: Rectangle {
            required property var modelData
            x: modelData.x0
            y: 0
            width: Math.max(0, modelData.x1 - modelData.x0)
            height: graph.plotH
            color: Qt.rgba(52/255, 199/255, 89/255, graph.dark ? 0.16 : 0.12)
        }
    }

    // ── Battery-level bars ──
    Item {
        width: graph.plotW
        height: graph.plotH
        Repeater {
            model: graph.nSlots
            delegate: Item {
                required property int index
                readonly property var d: graph.buckets && graph.buckets[index]
                    ? graph.buckets[index]
                    : ({ level: 0, charging: false, has: false })
                x: index * graph.slotW
                width: graph.slotW
                height: graph.plotH
                Rectangle {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    width: Math.max(1.5, graph.slotW - 1.2)
                    height: parent.d.has ? Math.max(2, graph.plotH * parent.d.level / 100) : 0
                    radius: 1
                    color: graph.green
                }
            }
        }
    }

    // ── Charging baseline bar + ⚡ marker (when / how long it charged) ──
    // Lives in the strip below the 0% line, with padding from it.
    Repeater {
        model: graph.runs
        delegate: Item {
            required property var modelData
            Rectangle {
                x: modelData.x0
                y: graph.plotH + 8
                width: Math.max(0, modelData.x1 - modelData.x0)
                height: 3
                radius: 1.5
                color: graph.green
            }
            // ⚡ notch, only when the run is wide enough to read.
            Item {
                visible: (modelData.x1 - modelData.x0) > 18
                x: modelData.mid - 8
                y: graph.plotH + 1.5
                width: 16; height: 16
                Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6
                            color: ThemeService.bg }
                Text {
                    anchors.centerIn: parent
                    text: "󱐋"
                    color: graph.green
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 10
                }
            }
        }
    }

    // ── X-axis hour labels (clock-aligned, every 3h) ──
    Repeater {
        model: graph.ticks
        delegate: Text {
            required property var modelData
            x: modelData.x
            y: graph.plotH + 18
            text: graph._fmtHour(modelData.hour)
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
            font.family: "SF Pro Display"; font.pixelSize: 10
            // Drop the label for the boundary that opens the current (forming)
            // cell at the very right edge — it would just cram against the % axis.
            // It reappears on its own once that cell is wide enough to fit it.
            visible: modelData.x + implicitWidth <= graph.plotW
        }
    }
}
