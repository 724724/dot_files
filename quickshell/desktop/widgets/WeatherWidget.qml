import QtQuick
import Quickshell.Io

// macOS-style weather with 4 layouts. Each widget fetches its OWN location's
// forecast (Open-Meteo), so different widgets can show different cities. The
// place is set via right-click → Edit (Current Location at top + city search).
// The card background gradient changes with weather category × time of day.
//   1 Large (hourly + daily)   2 Medium (hourly)
//   3 Conditions (small)       4 Sun (sunrise/sunset)
Item {
    id: wRoot
    property var frame
    readonly property var svc: WeatherService
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int layout: (d && d.layout) ? d.layout : 1
    readonly property var place: (d && d.place) ? d.place : null
    readonly property bool active: frame && frame.winRef ? frame.winRef.show : true

    // Effective coordinates: the widget's pinned place, else the shared IP one.
    readonly property real effLat: place ? place.lat : svc.currentLat
    readonly property real effLon: place ? place.lon : svc.currentLon
    readonly property string locName: place ? place.name : (svc.currentName || "Weather")

    // WidgetFrame hints.
    property color cardColor: "transparent"
    property bool lightCard: false

    // Display state (per widget).
    property bool loaded: false
    property string temp: "—"
    property string feels: ""
    property string desc: ""
    property string icon: ""
    property color iconColor: "#ffffff"
    property string hi: ""
    property string lo: ""
    property var hourly: []
    property var daily: []
    property real weekMin: 0
    property real weekMax: 1
    property string sunrise: ""
    property string sunset: ""
    property real dayProgress: -1
    property color gradTop: "#1a74d4"
    property color gradBottom: "#73b7ef"

    onEffLatChanged: fetchDebounce.restart()
    onEffLonChanged: fetchDebounce.restart()
    Component.onCompleted: fetchDebounce.restart()

    Timer { id: fetchDebounce; interval: 80; onTriggered: wRoot._fetch() }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: true; onTriggered: wRoot._fetch() }
    // Failed fetch (offline, API unreachable) → retry in 1 min instead of
    // waiting for the 15-min tick. Restarted, not accumulated, so at most one
    // retry is ever pending.
    Timer { id: retryTimer; interval: 60 * 1000; onTriggered: wRoot._fetch() }

    Process {
        id: fcProc
        stdout: StdioCollector { onStreamFinished: wRoot._parse(text) }
        onExited: (code, status) => { if (code !== 0) retryTimer.restart() }
    }

    function _fetch() {
        if (isNaN(effLat) || isNaN(effLon)) return
        let url = "https://api.open-meteo.com/v1/forecast?latitude=" + effLat + "&longitude=" + effLon
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
            + "&timezone=auto&forecast_days=7&wind_speed_unit=ms"
        // openmeteo-fetch.sh = curl with a fallback route for api.open-meteo.com
        // (unreachable from some ISPs; see the script header).
        fcProc.command = [WeatherService.fetchScript, url]
        fcProc.running = true
    }

    function _parse(t) {
        if (!t || !t.trim()) return
        try {
            let j = JSON.parse(t)
            let cur = j.current
            let code = cur.weather_code
            let day = cur.is_day === 1

            wRoot.temp = svc.roundDeg(cur.temperature_2m)
            wRoot.feels = svc.roundDeg(cur.apparent_temperature)
            wRoot.desc = svc.descOf(code)
            wRoot.icon = svc.iconOf(code, day)
            wRoot.iconColor = svc.iconColorOf(code)

            let dl = j.daily
            wRoot.hi = svc.roundDeg(dl.temperature_2m_max[0])
            wRoot.lo = svc.roundDeg(dl.temperature_2m_min[0])
            wRoot.sunrise = svc.clock12(dl.sunrise[0])
            wRoot.sunset = svc.clock12(dl.sunset[0])

            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let days = [], wmin = 999, wmax = -999
            let n = Math.min(6, dl.time.length)
            for (let i = 0; i < n; i++) {
                let hiN = dl.temperature_2m_max[i], loN = dl.temperature_2m_min[i]
                wmin = Math.min(wmin, loN); wmax = Math.max(wmax, hiN)
                let dt = new Date(dl.time[i] + "T00:00:00")
                days.push({ day: (i === 0) ? "Today" : dayNames[dt.getDay()],
                            hi: svc.roundDeg(hiN), lo: svc.roundDeg(loN),
                            hiNum: hiN, loNum: loN, icon: svc.iconOf(dl.weather_code[i], true),
                            iconColor: svc.iconColorOf(dl.weather_code[i]) })
            }
            wRoot.daily = days; wRoot.weekMin = wmin; wRoot.weekMax = wmax

            let h = j.hourly
            let nowMin = svc.minsOf(cur.time), nowDate = cur.time.split("T")[0], start = 0
            for (let k = 0; k < h.time.length; k++) {
                let dd = h.time[k].split("T")[0]
                if (dd > nowDate || (dd === nowDate && svc.minsOf(h.time[k]) >= nowMin)) { start = k; break }
            }
            let hrs = []
            for (let k = start; k < Math.min(start + 10, h.time.length); k++) {
                let hh = parseInt(h.time[k].split("T")[1].split(":")[0])
                hrs.push({ label: svc.hour12(hh), temp: svc.roundDeg(h.temperature_2m[k]),
                           icon: svc.iconOf(h.weather_code[k], hh >= 6 && hh < 19),
                           iconColor: svc.iconColorOf(h.weather_code[k]) })
            }
            wRoot.hourly = hrs

            let srM = svc.minsOf(dl.sunrise[0]), ssM = svc.minsOf(dl.sunset[0])
            wRoot.dayProgress = (nowMin >= srM && nowMin <= ssM && ssM > srM) ? (nowMin - srM) / (ssM - srM) : -1
            let phase = (Math.abs(nowMin - srM) <= 45) ? "dawn"
                      : (Math.abs(nowMin - ssM) <= 45) ? "dusk" : (day ? "day" : "night")
            let pair = svc.gradient(svc.categoryOf(code), phase)
            wRoot.gradTop = pair[0]; wRoot.gradBottom = pair[1]

            wRoot.loaded = true
        } catch (e) { /* keep previous */ }
    }

    // ── Gradient background ────────────────────────────────────────────────
    // Rounded to match the frame card (the card's clip is rectangular, so the
    // gradient needs its own radius or the corners look square).
    Rectangle {
        anchors.fill: parent
        radius: 13
        gradient: Gradient {
            GradientStop { position: 0.0; color: wRoot.gradTop; Behavior on color { ColorAnimation { duration: 500 } } }
            GradientStop { position: 1.0; color: wRoot.gradBottom; Behavior on color { ColorAnimation { duration: 500 } } }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────
    component CurrentHeader: Item {
        implicitHeight: 78
        Column {
            anchors.left: parent.left; anchors.top: parent.top
            spacing: -2
            Text { text: wRoot.locName; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { text: wRoot.temp; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 46; font.weight: Font.Light }
        }
        Column {
            anchors.right: parent.right; anchors.top: parent.top
            anchors.topMargin: 2
            spacing: 1
            Text { anchors.right: parent.right; text: wRoot.icon; color: wRoot.iconColor
                   font.family: wRoot.svc.iconFont; font.pixelSize: 24 }
            Text { anchors.right: parent.right; text: wRoot.desc; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 12 }
            Text { anchors.right: parent.right
                   text: wRoot.hi !== "" ? ("H:" + wRoot.hi + "  L:" + wRoot.lo) : ""
                   color: Qt.rgba(1, 1, 1, 0.85); font.family: "SF Pro Display"; font.pixelSize: 12 }
        }
    }

    component HourlyRow: Row {
        property int count: 6
        Repeater {
            model: wRoot.hourly.slice(0, parent.count)
            delegate: Column {
                required property var modelData
                width: parent.width / parent.count
                spacing: 5
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label
                       color: Qt.rgba(1, 1, 1, 0.8); font.family: "SF Pro Display"; font.pixelSize: 12 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: modelData.iconColor
                       font.family: wRoot.svc.iconFont; font.pixelSize: 17 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp
                       color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
            }
        }
    }

    component Divider: Rectangle { height: 1; color: Qt.rgba(1, 1, 1, 0.18) }

    // ── Layout 1: Large ────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        visible: wRoot.layout === 1

        CurrentHeader { width: parent.width }
        Divider { width: parent.width }
        HourlyRow { width: parent.width; count: 6 }
        Divider { width: parent.width }

        Column {
            width: parent.width
            spacing: 7
            Repeater {
                model: wRoot.daily
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    height: 20
                    spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 42
                           text: modelData.day; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 16; text: modelData.icon
                           color: modelData.iconColor; font.family: wRoot.svc.iconFont; font.pixelSize: 14 }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 34; horizontalAlignment: Text.AlignRight
                           text: modelData.lo; color: Qt.rgba(1, 1, 1, 0.65)
                           font.family: "SF Pro Display"; font.pixelSize: 14 }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 42 - 16 - 34 - 34 - 4 * 8
                        height: 5
                        Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(1, 1, 1, 0.18) }
                        Rectangle {
                            readonly property real span: Math.max(1, wRoot.weekMax - wRoot.weekMin)
                            x: ((modelData.loNum - wRoot.weekMin) / span) * parent.width
                            width: Math.max(6, ((modelData.hiNum - modelData.loNum) / span) * parent.width)
                            height: parent.height; radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: wRoot.svc.tempColor(modelData.loNum) }
                                GradientStop { position: 1.0; color: wRoot.svc.tempColor(modelData.hiNum) }
                            }
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 34
                           text: modelData.hi; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 14 }
                }
            }
        }
    }

    // ── Layout 2: Medium (hourly only) ─────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        visible: wRoot.layout === 2
        CurrentHeader { width: parent.width }
        Divider { width: parent.width }
        HourlyRow { width: parent.width; count: 6 }
    }

    // ── Layout 3: Conditions (small) ───────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 14
        visible: wRoot.layout === 3
        Column {
            anchors.left: parent.left; anchors.top: parent.top
            spacing: -2
            Text { text: wRoot.locName; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: wRoot.temp; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 40; font.weight: Font.Light }
        }
        Text { anchors.right: parent.right; anchors.top: parent.top; text: wRoot.icon; color: wRoot.iconColor
               font.family: wRoot.svc.iconFont; font.pixelSize: 28 }
        Column {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            spacing: 1
            Text { text: wRoot.desc; color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium }
            Text { text: wRoot.hi !== "" ? ("H:" + wRoot.hi + "  L:" + wRoot.lo) : ""
                   color: Qt.rgba(1, 1, 1, 0.8); font.family: "SF Pro Display"; font.pixelSize: 12 }
        }
    }

    // ── Layout 4: Sun (sunrise / sunset) ───────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16
        visible: wRoot.layout === 4
        Row {
            id: sunHead
            anchors.left: parent.left; anchors.top: parent.top
            spacing: 6
            Text { text: wRoot.svc.sunsetGlyph; color: "#ffd86b"
                   font.family: wRoot.svc.iconFont; font.pixelSize: 16 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "SUNSET"
                   color: Qt.rgba(1, 1, 1, 0.85); font.family: "SF Pro Display"
                   font.pixelSize: 12; font.weight: Font.Bold }
        }
        Text {
            id: sunsetBig
            anchors.left: parent.left; anchors.top: sunHead.bottom; anchors.topMargin: 2
            text: wRoot.sunset || "—"; color: "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 28; font.weight: Font.Medium
        }
        Canvas {
            id: arc
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: sunsetBig.bottom; anchors.bottom: sunFoot.top
            anchors.topMargin: 6; anchors.bottomMargin: 6
            property real prog: wRoot.dayProgress
            onProgChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d"); ctx.reset()
                let w = width, h = height, horizon = h * 0.72, amp = h * 0.6
                ctx.beginPath()
                for (let i = 0; i <= 40; i++) {
                    let t = i / 40, x = t * w, y = horizon - Math.sin(t * Math.PI) * amp
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.4); ctx.lineWidth = 1.5
                ctx.setLineDash([3, 3]); ctx.stroke(); ctx.setLineDash([])
                ctx.beginPath(); ctx.moveTo(0, horizon); ctx.lineTo(w, horizon)
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25); ctx.lineWidth = 1; ctx.stroke()
                let p = arc.prog
                if (p >= 0 && p <= 1) {
                    let x = p * w, y = horizon - Math.sin(p * Math.PI) * amp
                    ctx.beginPath(); ctx.arc(x, y, 5, 0, 2 * Math.PI); ctx.fillStyle = "#ffd34d"; ctx.fill()
                }
            }
        }
        Text {
            id: sunFoot
            anchors.left: parent.left; anchors.bottom: parent.bottom
            text: "Sunrise: " + (wRoot.sunrise || "—")
            color: Qt.rgba(1, 1, 1, 0.85); font.family: "SF Pro Display"; font.pixelSize: 12
        }
    }

    // ── Loading state ──────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: !wRoot.loaded
        text: "Loading…"; color: Qt.rgba(1, 1, 1, 0.7)
        font.family: "SF Pro Display"; font.pixelSize: 14
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onDoubleClicked: wRoot._fetch() }
}

