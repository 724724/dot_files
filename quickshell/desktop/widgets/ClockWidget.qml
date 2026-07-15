import QtQuick

// macOS-style clock with 5 layouts (chosen in the Add-Widget gallery, edited
// via right-click → Edit):
//   1 digital + tick bezel (light)   2 world-clock row (dark)
//   3 world-clock 2x2 (dark)         4 single analog w/ numbers (light)
//   5 single analog, ticks only (dark)
Item {
    id: clockRoot
    property var frame
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int layout: (d && d.layout) ? d.layout : 4
    readonly property var faces: (d && d.faces && d.faces.length) ? d.faces
                                : [{ city: "Local", tz: WidgetsService.localOffset() }]
    readonly property bool active: frame && frame.winRef ? frame.winRef.show : true

    // Card appearance hints read by WidgetFrame.
    readonly property bool lightCard: layout === 1 || layout === 4
    readonly property color cardColor: layout === 1 ? "#ffffff"
                                     : layout === 4 ? Qt.rgba(0.84, 0.89, 0.96, 0.45)
                                     : "#1c1c1e"

    // Re-evaluate Today/+HRS labels periodically.
    property int tick: 0
    Timer { interval: 30000; repeat: true; running: clockRoot.active; onTriggered: clockRoot.tick++ }

    function abbrev(name) {
        if (!name || name === "Local") return "LOCAL"
        let parts = name.split(" ")
        if (parts.length >= 2) return (parts[0][0] + parts[1][0] + (parts[1][1] || "")).toUpperCase()
        return name.substring(0, 3).toUpperCase()
    }
    function dayLabel(tz) {
        clockRoot.tick // dependency
        let now = Date.now()
        let cityDay  = Math.floor((now + tz * 3600000) / 86400000)
        let localDay = Math.floor((now + WidgetsService.localOffset() * 3600000) / 86400000)
        let diff = cityDay - localDay
        return diff === 0 ? "Today" : (diff > 0 ? "Tomorrow" : "Yesterday")
    }
    function offLabel(tz) {
        clockRoot.tick
        let rel = tz - WidgetsService.localOffset()
        let sign = rel >= 0 ? "+" : "-"
        let a = Math.abs(rel)
        let txt = (a % 1 === 0) ? a : a.toFixed(1)
        return sign + txt + "HRS"
    }
    function digitalTime(tz) {
        clockRoot.tick
        let dd = new Date(Date.now() + tz * 3600000)
        let h = dd.getUTCHours() % 12; if (h === 0) h = 12
        let m = dd.getUTCMinutes()
        return h + ":" + (m < 10 ? "0" + m : m)
    }

    // ── Layout 1: digital + tick bezel ─────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: clockRoot.layout === 1

        Canvas {
            id: bezel
            anchors.fill: parent
            anchors.margins: 10
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                let a = width / 2, b = height / 2, cr = Math.min(a, b) * 0.42
                ctx.translate(a, b)
                a -= 2; b -= 2
                let arc = (Math.PI / 2) * cr          // quarter-corner arc length
                let topL = 2 * (a - cr)               // top/bottom straight length
                let sideL = 2 * (b - cr)              // left/right straight length
                let P = 2 * topL + 2 * sideL + 4 * arc

                // Point + outward normal at perimeter distance `dist`, walking
                // clockwise from top edge: top, tr-arc, right, br-arc, bottom,
                // bl-arc, left, tl-arc.
                function pointAt(dist) {
                    let dseq = [topL, arc, sideL, arc, topL, arc, sideL, arc]
                    let i = 0
                    while (dist > dseq[i]) { dist -= dseq[i]; i++ }
                    let f = dist / dseq[i]
                    switch (i) {
                    case 0: return { x: -(a - cr) + dist, y: -b, nx: 0, ny: -1 }
                    case 1: { let an = -Math.PI / 2 + f * (Math.PI / 2); return { x: (a - cr) + Math.cos(an) * cr, y: (-b + cr) + Math.sin(an) * cr, nx: Math.cos(an), ny: Math.sin(an) } }
                    case 2: return { x: a, y: -(b - cr) + dist, nx: 1, ny: 0 }
                    case 3: { let an = 0 + f * (Math.PI / 2); return { x: (a - cr) + Math.cos(an) * cr, y: (b - cr) + Math.sin(an) * cr, nx: Math.cos(an), ny: Math.sin(an) } }
                    case 4: return { x: (a - cr) - dist, y: b, nx: 0, ny: 1 }
                    case 5: { let an = Math.PI / 2 + f * (Math.PI / 2); return { x: (-a + cr) + Math.cos(an) * cr, y: (b - cr) + Math.sin(an) * cr, nx: Math.cos(an), ny: Math.sin(an) } }
                    case 6: return { x: -a, y: (b - cr) - dist, nx: -1, ny: 0 }
                    default: { let an = Math.PI + f * (Math.PI / 2); return { x: (-a + cr) + Math.cos(an) * cr, y: (-b + cr) + Math.sin(an) * cr, nx: Math.cos(an), ny: Math.sin(an) } }
                    }
                }

                // Second "hand" as a filling sweep: the border ticks turn black
                // from 12 o'clock (tick 0) clockwise up to the current second,
                // then reset each minute. The leading tick fades in over its
                // second so the fill is continuous, not stepped.
                let now = Date.now()
                let dd = new Date(now + clockRoot.faces[0].tz * 3600000)
                let secF = dd.getUTCSeconds() + (now % 1000) / 1000
                let lead = Math.floor(secF)
                let frac = secF - lead

                ctx.lineCap = "round"
                let N = 60
                // Offset so tick 0 sits at top-center (12 o'clock), where the
                // fill begins — not at the top-left corner of the top edge.
                function drawTick(k, col, lw) {
                    let pt = pointAt(((k / N) * P + topL / 2) % P)
                    let tl = (k % 5 === 0) ? 9 : 6
                    ctx.beginPath()
                    ctx.moveTo(pt.x, pt.y)
                    ctx.lineTo(pt.x - pt.nx * tl, pt.y - pt.ny * tl)
                    ctx.lineWidth = lw
                    ctx.strokeStyle = col
                    ctx.stroke()
                }
                // base gray ring
                for (let k = 0; k < N; k++)
                    drawTick(k, (k % 5 === 0) ? "#9a9a9f" : "#c4c4c9", (k % 5 === 0) ? 2.0 : 1.2)
                // black fill from 12 o'clock up to the current second
                for (let k = 0; k < lead; k++)
                    drawTick(k, "#101012", 2.4)
                // leading tick fades in over its second
                drawTick(lead % N, "rgba(16,16,18," + Math.max(0.12, frac).toFixed(3) + ")", 2.4)
            }
        }
        // Repaint the bezel ~30fps so the fill advances continuously, and
        // refresh the digital string the instant the minute rolls over (it
        // only changes once a minute, so we assign on change to avoid churn).
        property string digitalStr: clockRoot.digitalTime(clockRoot.faces[0].tz)
        Timer {
            interval: 33; repeat: true
            running: clockRoot.active && clockRoot.layout === 1
            onTriggered: {
                bezel.requestPaint()
                let s = clockRoot.digitalTime(clockRoot.faces[0].tz)
                if (s !== parent.digitalStr) parent.digitalStr = s
            }
        }
        Text {
            anchors.centerIn: parent
            text: parent.digitalStr
            color: "#101012"
            font.family: "SF Pro Display"
            font.weight: Font.Bold
            font.pixelSize: Math.max(34, Math.min(parent.width, parent.height) * 0.30)
            font.letterSpacing: -0.8
        }
    }

    // ── Layout 2: world-clock row ──────────────────────────────────────────
    Row {
        anchors.fill: parent
        anchors.margins: 12
        visible: clockRoot.layout === 2
        Repeater {
            model: clockRoot.layout === 2 ? clockRoot.faces : []
            delegate: Column {
                required property var modelData
                width: parent.width / Math.max(1, clockRoot.faces.length)
                spacing: 3
                AnalogClock {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 8, parent.parent.height - 56)
                    height: width
                    active: clockRoot.active
                    tz: modelData.tz
                    faceColor: "#ffffff"
                    tickColor: "#1c1c1e"
                    showNumbers: true
                    numberColor: "#1c1c1e"
                    handColor: "#1c1c1e"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.city === "Local" ? "Local" : modelData.city
                    color: "#ffffff"; font.family: "SF Pro Display"
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    elide: Text.ElideRight; width: parent.width - 6
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockRoot.dayLabel(modelData.tz)
                    color: Qt.rgba(1, 1, 1, 0.5); font.family: "SF Pro Display"; font.pixelSize: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockRoot.offLabel(modelData.tz)
                    color: Qt.rgba(1, 1, 1, 0.5); font.family: "SF Pro Display"; font.pixelSize: 10
                }
            }
        }
    }

    // ── Layout 3: world-clock 2x2 ──────────────────────────────────────────
    Grid {
        anchors.fill: parent
        anchors.margins: 10
        visible: clockRoot.layout === 3
        columns: 2; rows: 2
        rowSpacing: 8; columnSpacing: 8
        Repeater {
            model: clockRoot.layout === 3 ? clockRoot.faces : []
            delegate: AnalogClock {
                required property var modelData
                width: (parent.width - parent.columnSpacing) / 2
                height: (parent.height - parent.rowSpacing) / 2
                active: clockRoot.active
                tz: modelData.tz
                faceColor: "#ffffff"
                tickColor: "#1c1c1e"
                showNumbers: true
                numberColor: "#5a5a5e"
                handColor: "#1c1c1e"
                label: clockRoot.abbrev(modelData.city)
                labelColor: "#8e8e93"
            }
        }
    }

    // ── Layout 4: single analog with numbers — a white circle face on a
    //    translucent (frosted) card, not a solid fill. ────────────────────────
    AnalogClock {
        anchors.fill: parent
        anchors.margins: 12
        visible: clockRoot.layout === 4
        active: clockRoot.active
        tz: clockRoot.faces[0].tz
        faceColor: Qt.rgba(1, 1, 1, 0.92)
        tickColor: "#2a2a2e"
        showNumbers: true
        numberColor: "#1c1c1e"
        handColor: "#1c1c1e"
    }

    // ── Layout 5: single analog, ticks only (dark) ─────────────────────────
    AnalogClock {
        anchors.fill: parent
        anchors.margins: 16
        visible: clockRoot.layout === 5
        active: clockRoot.active
        tz: clockRoot.faces[0].tz
        faceColor: "transparent"
        tickColor: Qt.rgba(1, 1, 1, 0.55)
        showNumbers: false
        handColor: "#f2f2f7"
        label: clockRoot.abbrev(clockRoot.faces[0].city)
        labelColor: Qt.rgba(1, 1, 1, 0.6)
    }
}
