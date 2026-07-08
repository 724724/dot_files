import QtQuick
import QtQuick.Controls
import Quickshell.Io

// Editor body for a weather widget (right-click → Edit).
//   • Switch the layout.
//   • Manage locations: a saved-locations list (Current/IP at top), each row
//     styled by that place's live weather + local time, with a left checkmark
//     for the selected one and a right trash button. Search adds to the list.
Item {
    id: ed
    property int index: -1

    implicitWidth: 460
    implicitHeight: col.implicitHeight

    property int layout: 1
    property var place: null          // null = current location
    property var results: []
    readonly property var layoutNames: ["Large", "Hourly", "Conditions", "Sun"]

    // current (IP) + saved places, as render rows
    readonly property var rows: {
        let r = [{ current: true, name: WeatherService.currentName || "Current Location",
                   lat: WeatherService.currentLat, lon: WeatherService.currentLon, savedIndex: -1 }]
        let s = WeatherService.savedPlaces
        for (let i = 0; i < s.length; i++)
            r.push({ current: false, name: s[i].name, lat: s[i].lat, lon: s[i].lon, savedIndex: i })
        return r
    }

    onIndexChanged: ed.reload()
    function reload() {
        if (index < 0) return
        let d = WidgetsService.getData(index)
        layout = d.layout || 1
        place = d.place || null
        results = []
        searchField.text = ""
    }
    function pickLayout(n) { WidgetsService.setWeatherLayout(index, n); ed.layout = n }
    function pickCurrent() { WidgetsService.setData(index, { place: null }); ed.place = null }
    function pickPlace(p) {
        let q = { name: p.name, lat: p.lat, lon: p.lon }
        WidgetsService.setData(index, { place: q })
        ed.place = q
    }
    function isSelected(row) {
        if (row.current) return ed.place === null
        return ed.place !== null && ed.place.lat === row.lat && ed.place.lon === row.lon
    }

    // Geocoding search.
    function search(q) {
        if (!q || q.trim().length < 2) { ed.results = []; return }
        let url = "https://geocoding-api.open-meteo.com/v1/search?name="
                + encodeURIComponent(q.trim()) + "&count=6&language=en&format=json"
        searchProc.command = [WeatherService.fetchScript, url]
        searchProc.running = true
    }
    Timer { id: searchDebounce; interval: 320; onTriggered: ed.search(searchField.text) }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { let j = JSON.parse(text); ed.results = j.results || [] }
                catch (e) { ed.results = [] }
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 16

        Text { text: "Weather"; color: "#ffffff"; font.family: "SF Pro Display"
               font.pixelSize: 18; font.weight: Font.DemiBold }

        // ── Layout chooser ─────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Style"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        readonly property int n: index + 1
                        width: 92; height: 32; radius: 9
                        color: ed.layout === n ? Qt.rgba(0.30, 0.52, 0.95, 0.9)
                             : (lh.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                        Behavior on color { ColorAnimation { duration: 110 } }
                        Text { anchors.centerIn: parent; text: ed.layoutNames[parent.n - 1]
                               color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11 }
                        HoverHandler { id: lh }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.pickLayout(parent.n) }
                    }
                }
            }
        }

        // ── Location ───────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Location"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }

            // Search box
            Rectangle {
                width: parent.width; height: 36; radius: 9
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: searchField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1
                Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                       text: "\uf002"; color: Qt.rgba(1, 1, 1, 0.5); font.family: WeatherService.iconFont; font.pixelSize: 13 }
                TextField {
                    id: searchField
                    anchors.left: parent.left; anchors.leftMargin: 32; anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    background: null; color: "#ffffff"
                    placeholderText: "Search city to add…"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                    font.family: "SF Pro Display"; font.pixelSize: 13
                    onTextChanged: searchDebounce.restart()
                    onAccepted: ed.search(text)
                }
            }

            // Search results (tap to add → saved list + select)
            Column {
                width: parent.width
                spacing: 4
                visible: ed.results.length > 0
                Repeater {
                    model: ed.results
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 38; radius: 9
                        color: rHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: ""
                                   color: Qt.rgba(1, 1, 1, 0.55); font.family: WeatherService.iconFont; font.pixelSize: 12 }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData.name; color: "#ffffff"
                                       font.family: "SF Pro Display"; font.pixelSize: 13 }
                                Text { text: [modelData.admin1, modelData.country].filter(function (x) { return !!x }).join(", ")
                                       color: Qt.rgba(1, 1, 1, 0.55); font.family: "SF Pro Display"; font.pixelSize: 11 }
                            }
                        }
                        HoverHandler { id: rHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                let p = { name: modelData.name, lat: modelData.latitude, lon: modelData.longitude }
                                WeatherService.addPlace(p)
                                ed.pickPlace(p)
                                ed.results = []
                                searchField.text = ""
                            }
                        }
                    }
                }
            }

            // Saved-locations list (Current first), each styled by its weather.
            Column {
                width: parent.width
                spacing: 8
                Repeater {
                    model: ed.rows
                    delegate: PlaceRow {
                        required property var modelData
                        width: parent.width
                        rowName: modelData.name
                        lat: modelData.lat
                        lon: modelData.lon
                        isCurrent: modelData.current
                        savedIndex: modelData.savedIndex
                    }
                }
            }
        }
    }

    // ── A weather-styled location row (self-fetches its own conditions) ──────
    component PlaceRow: Rectangle {
        id: pr
        property string rowName: ""
        property real lat: NaN
        property real lon: NaN
        property bool isCurrent: false
        property int savedIndex: -1

        readonly property bool selected: ed.isSelected({ current: isCurrent, lat: lat, lon: lon })

        height: 64; radius: 14; clip: true
        color: "#3a4a63"
        border.color: selected ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.10)
        border.width: selected ? 2 : 1

        // fetched conditions
        property string temp: ""
        property string desc: ""
        property string timeStr: ""
        property string hi: ""
        property string lo: ""
        property color gradTop: "#3a4a63"
        property color gradBottom: "#4a5a73"

        onLatChanged: fetchT.restart()
        onLonChanged: fetchT.restart()
        Component.onCompleted: fetchT.restart()
        Timer { id: fetchT; interval: 60; onTriggered: pr._fetch() }
        Process { id: pfc; stdout: StdioCollector { onStreamFinished: pr._parse(text) } }
        function _fetch() {
            if (isNaN(lat) || isNaN(lon)) return
            let url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
                + "&current=temperature_2m,weather_code,is_day"
                + "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=1"
            pfc.command = [WeatherService.fetchScript, url]
            pfc.running = true
        }
        function _parse(t) {
            if (!t || !t.trim()) return
            try {
                let j = JSON.parse(t), cur = j.current, dl = j.daily, code = cur.weather_code, day = cur.is_day === 1
                pr.temp = WeatherService.roundDeg(cur.temperature_2m)
                pr.desc = WeatherService.descOf(code)
                pr.timeStr = WeatherService.clock12(cur.time)
                pr.hi = WeatherService.roundDeg(dl.temperature_2m_max[0])
                pr.lo = WeatherService.roundDeg(dl.temperature_2m_min[0])
                let nowMin = WeatherService.minsOf(cur.time)
                let srM = WeatherService.minsOf(dl.sunrise[0]), ssM = WeatherService.minsOf(dl.sunset[0])
                let phase = (Math.abs(nowMin - srM) <= 45) ? "dawn"
                          : (Math.abs(nowMin - ssM) <= 45) ? "dusk" : (day ? "day" : "night")
                let pair = WeatherService.gradient(WeatherService.categoryOf(code), phase)
                pr.gradTop = pair[0]; pr.gradBottom = pair[1]
            } catch (e) { /* keep */ }
        }

        gradient: Gradient {
            GradientStop { position: 0.0; color: pr.gradTop }
            GradientStop { position: 1.0; color: pr.gradBottom }
        }

        // selected checkmark (left)
        Text {
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
            visible: pr.selected
            text: "\uf00c"; color: "#ffffff"; font.family: WeatherService.iconFont; font.pixelSize: 15
        }

        Column {
            anchors.left: parent.left; anchors.leftMargin: pr.selected ? 34 : 14
            anchors.top: parent.top; anchors.topMargin: 9
            spacing: 0
            Text { text: pr.rowName + (pr.isCurrent ? "  ·  Current" : ""); color: "#ffffff"
                   font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: pr.timeStr; color: Qt.rgba(1, 1, 1, 0.75)
                   font.family: "SF Pro Display"; font.pixelSize: 11 }
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: pr.selected ? 34 : 14
            anchors.bottom: parent.bottom; anchors.bottomMargin: 9
            text: pr.desc; color: Qt.rgba(1, 1, 1, 0.9)
            font.family: "SF Pro Display"; font.pixelSize: 12
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.top: parent.top; anchors.topMargin: 6
            text: pr.temp; color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 30; font.weight: Font.Light
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 9
            text: pr.hi !== "" ? ("H:" + pr.hi + "  L:" + pr.lo) : ""
            color: Qt.rgba(1, 1, 1, 0.85); font.family: "SF Pro Display"; font.pixelSize: 11
        }

        HoverHandler { id: prHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pr.isCurrent) ed.pickCurrent(); else ed.pickPlace({ name: pr.rowName, lat: pr.lat, lon: pr.lon }) }
        }

        // trash (right, on hover; not for Current)
        Rectangle {
            visible: !pr.isCurrent && (prHover.hovered || trashHover.hovered)
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17
            color: trashHover.hovered ? "#ff4d4d" : Qt.rgba(0.9, 0.3, 0.3, 0.85)
            Text { anchors.centerIn: parent; text: "\uf1f8"; color: "#ffffff"
                   font.family: WeatherService.iconFont; font.pixelSize: 14 }
            HoverHandler { id: trashHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    let wasSel = pr.selected
                    WeatherService.removePlace(pr.savedIndex)
                    if (wasSel) ed.pickCurrent()
                }
            }
        }
    }
}
