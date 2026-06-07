import QtQuick

// Reusable analog clock face. Time is derived from a UTC offset `tz` (hours)
// so it can show any world-clock city. Set `fixedDate` for static previews.
Item {
    id: ac

    property real tz: 0
    property bool active: true          // tick while true
    property var fixedDate: null        // static time for gallery previews

    property color faceColor: "transparent"
    property color tickColor: "#1c1c1e"
    property bool  showNumbers: false
    property color numberColor: "#1c1c1e"
    property bool  minuteTicks: true
    property color handColor: "#1c1c1e"
    property color secondColor: "#ff9f0a"
    property real  handScale: 1.0

    property string label: ""
    property color labelColor: Qt.rgba(0.56, 0.56, 0.58, 1)

    // ~30 fps so the second hand sweeps smoothly instead of ticking once a sec.
    Timer {
        interval: 33; repeat: true
        running: ac.active && !ac.fixedDate
        onTriggered: face.requestPaint()
    }
    onTzChanged: face.requestPaint()
    onActiveChanged: if (active) face.requestPaint()

    function _hms() {
        if (fixedDate) return { h: fixedDate.getHours() % 12, m: fixedDate.getMinutes(), s: fixedDate.getSeconds() }
        let now = Date.now()
        let d = new Date(now + tz * 3600000)
        // Fractional seconds (ms part) drive the smooth sweep.
        return { h: d.getUTCHours() % 12, m: d.getUTCMinutes(), s: d.getUTCSeconds() + (now % 1000) / 1000 }
    }

    Canvas {
        id: face
        anchors.centerIn: parent
        width: Math.min(ac.width, ac.height)
        height: width
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let r = width / 2
            ctx.translate(r, r)

            if (Qt.colorEqual(ac.faceColor, "transparent") === false) {
                ctx.beginPath(); ctx.arc(0, 0, r - 1, 0, 2 * Math.PI)
                ctx.fillStyle = ac.faceColor; ctx.fill()
            }

            // ticks
            let tickCount = ac.minuteTicks ? 60 : 12
            for (let i = 0; i < tickCount; i++) {
                let ang = i * 2 * Math.PI / tickCount
                let major = ac.minuteTicks ? (i % 5 === 0) : true
                let outer = r - r * 0.06
                let inner = r - r * (major ? 0.16 : 0.10)
                ctx.beginPath()
                ctx.moveTo(Math.sin(ang) * inner, -Math.cos(ang) * inner)
                ctx.lineTo(Math.sin(ang) * outer, -Math.cos(ang) * outer)
                ctx.lineWidth = major ? Math.max(1.5, r * 0.03) : Math.max(0.8, r * 0.012)
                ctx.strokeStyle = ac.tickColor
                ctx.stroke()
            }

            // numbers
            if (ac.showNumbers) {
                ctx.fillStyle = ac.numberColor
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.font = "bold " + Math.round(r * 0.22) + "px 'SF Pro Display'"
                let nr = r - r * 0.30
                for (let n = 1; n <= 12; n++) {
                    let a = n * Math.PI / 6
                    ctx.fillText(n, Math.sin(a) * nr, -Math.cos(a) * nr)
                }
            }

            // label (e.g. CUP) — placed in the upper third
            if (ac.label !== "") {
                ctx.fillStyle = ac.labelColor
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.font = "bold " + Math.round(r * 0.13) + "px 'SF Pro Display'"
                ctx.fillText(ac.label, 0, -r * 0.42)
            }

            let t = ac._hms()
            function hand(angle, len, w, col) {
                ctx.beginPath(); ctx.lineCap = "round"
                ctx.moveTo(0, 0)
                ctx.lineTo(Math.sin(angle) * len, -Math.cos(angle) * len)
                ctx.lineWidth = w; ctx.strokeStyle = col; ctx.stroke()
            }
            hand((t.h + t.m / 60) * Math.PI / 6,  r * 0.50 * ac.handScale, Math.max(2.5, r * 0.045), ac.handColor)
            hand((t.m + t.s / 60) * Math.PI / 30, r * 0.72 * ac.handScale, Math.max(2.0, r * 0.032), ac.handColor)
            hand(t.s * Math.PI / 30,              r * 0.78 * ac.handScale, Math.max(1.0, r * 0.014), ac.secondColor)

            ctx.beginPath(); ctx.arc(0, 0, Math.max(2.5, r * 0.05), 0, 2 * Math.PI)
            ctx.fillStyle = ac.secondColor; ctx.fill()
        }
    }
}
