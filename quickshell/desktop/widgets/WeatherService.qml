pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Shared weather helpers + the device's "current location" (resolved once by
// IP). Per-widget forecast fetching lives in WeatherWidget so each weather
// widget can show a different city (set via right-click → Edit → search).
//
// Data: Open-Meteo (no key). Background gradient mimics iOS Weather — it varies
// by weather category × time-of-day (day/night/dawn/dusk).
Singleton {
    id: root

    // Monochrome Nerd Font "Weather Icons" (U+E300 block) ≈ macOS SF Symbols.
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"
    readonly property string sunsetGlyph: "\ue36b"
    readonly property string sunriseGlyph: "\ue34c"

    // curl wrapper with a fallback route for api.open-meteo.com \u2014 this ISP
    // can't reach its only A record, but the same API answers on open-meteo's
    // other hosts (wildcard cert). Real absolute path, matching the
    // SysUsageService/ShazamService convention (Qt.resolvedUrl breaks shells).
    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string fetchScript: _configDir + "/quickshell/scripts/openmeteo-fetch.sh"

    // Current (IP) location, shared by widgets left on "Current Location".
    property string currentName: ""
    property real currentLat: NaN
    property real currentLon: NaN
    property bool currentReady: false

    // Saved locations (shared across weather widgets, persisted). Each is
    // { name, lat, lon }. Managed from the weather editor (search to add,
    // trash to remove). The IP "Current Location" is always shown above these.
    property var savedPlaces: []
    FileView {
        id: placesStore
        path: Quickshell.stateDir + "/weather-places.json"
        blockLoading: true
        printErrors: false
    }
    function _loadPlaces() {
        try { let a = JSON.parse(placesStore.text() || "[]"); if (Array.isArray(a)) root.savedPlaces = a }
        catch (e) { /* start empty */ }
    }
    function _persistPlaces() { placesStore.setText(JSON.stringify(root.savedPlaces)) }
    function addPlace(p) {
        for (let i = 0; i < savedPlaces.length; i++)
            if (savedPlaces[i].lat === p.lat && savedPlaces[i].lon === p.lon) return
        let a = savedPlaces.slice()
        a.push({ name: p.name, lat: p.lat, lon: p.lon })
        root.savedPlaces = a
        root._persistPlaces()
    }
    function removePlace(i) {
        if (i < 0 || i >= savedPlaces.length) return
        let a = savedPlaces.slice()
        a.splice(i, 1)
        root.savedPlaces = a
        root._persistPlaces()
    }

    Component.onCompleted: { root.resolveCurrent(); root._loadPlaces() }
    function resolveCurrent() { geoProc.running = true }

    // The IP lookup used to be a single shot at startup: if the network wasn't
    // up yet (or the geo APIs hiccuped), every "Current Location" widget stayed
    // blank until a manual reload. Retry once a minute until it succeeds.
    Timer {
        interval: 60 * 1000
        running: !root.currentReady
        repeat: true
        onTriggered: root.resolveCurrent()
    }

    Process {
        id: geoProc
        command: ["bash", "-c",
            "curl -sf --max-time 8 https://ipapi.co/json || curl -sf --max-time 8 http://ip-api.com/json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text)
                    root.currentLat = (j.latitude !== undefined) ? j.latitude : j.lat
                    root.currentLon = (j.longitude !== undefined) ? j.longitude : j.lon
                    root.currentName = j.city || j.region || j.regionName || "Current Location"
                    root.currentReady = true
                } catch (e) { /* keep */ }
            }
        }
    }

    // ── Stateless helpers ───────────────────────────────────────────────────
    function tempColor(c) {
        if (c < 0)   return "#7d8ff0"
        if (c < 10)  return "#4ea3e8"
        if (c < 16)  return "#41c2d0"
        if (c < 20)  return "#5fc86a"
        if (c < 25)  return "#e8c84a"
        if (c < 30)  return "#ef9a3d"
        return "#e8533a"
    }

    function categoryOf(code) {
        if (code === 0) return "clear"
        if (code === 1 || code === 2) return "partly"
        if (code === 3) return "cloudy"
        if (code === 45 || code === 48) return "fog"
        if (code >= 51 && code <= 67) return "rain"
        if (code >= 80 && code <= 82) return "rain"
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow"
        if (code >= 95) return "thunder"
        return "cloudy"
    }
    // Nerd Font weather glyphs.
    function iconOf(code, day) {
        let c = categoryOf(code)
        if (c === "clear")   return day ? "\ue30d" : "\ue32b"   // day_sunny / night_clear
        if (c === "partly")  return day ? "\ue302" : "\ue37e"   // day_cloudy / night_alt_cloudy
        if (c === "cloudy")  return "\ue312"                     // cloudy
        if (c === "fog")     return "\ue313"                     // fog
        if (c === "rain")    return (code <= 57 || code === 80) ? (day ? "\ue308" : "\ue377") : "\ue318"
        if (c === "snow")    return "\ue31a"                     // snow
        if (c === "thunder") return "\ue31d"                     // thunderstorm
        return "\ue30d"
    }
    // Per-category tint so icons read like macOS multicolor symbols (sun
    // yellow, clouds white, rain blue, …) rather than flat white.
    function iconColorOf(code) {
        let c = categoryOf(code)
        if (c === "clear")   return "#ffd23e"   // sun — yellow
        if (c === "partly")  return "#ffe7a8"   // sun + cloud — warm white
        if (c === "cloudy")  return "#ffffff"   // cloud — white
        if (c === "fog")     return "#e3e7ec"
        if (c === "rain")    return "#bfe0fb"   // rain — light blue
        if (c === "snow")    return "#ffffff"
        if (c === "thunder") return "#ffd23e"   // lightning — yellow
        return "#ffffff"
    }
    function descOf(code) {
        let map = {
            0: "Clear", 1: "Mainly Clear", 2: "Partly Cloudy", 3: "Cloudy",
            45: "Fog", 48: "Rime Fog", 51: "Light Drizzle", 53: "Drizzle", 55: "Heavy Drizzle",
            56: "Freezing Drizzle", 57: "Freezing Drizzle", 61: "Light Rain", 63: "Rain", 65: "Heavy Rain",
            66: "Freezing Rain", 67: "Freezing Rain", 71: "Light Snow", 73: "Snow", 75: "Heavy Snow",
            77: "Snow Grains", 80: "Light Showers", 81: "Showers", 82: "Heavy Showers",
            85: "Snow Showers", 86: "Snow Showers", 95: "Thunderstorm", 96: "Thunderstorm", 99: "Thunderstorm"
        }
        return map[code] || "—"
    }

    readonly property var _grad: ({
        "clear":   { day: ["#1a74d4", "#73b7ef"], night: ["#0f1838", "#243056"], dawn: ["#3b4a7a", "#f0a868"], dusk: ["#2e3a6b", "#e8915b"] },
        "partly":  { day: ["#2f7bc0", "#7db0da"], night: ["#19223f", "#333e63"], dawn: ["#46527e", "#e8a06b"], dusk: ["#39406e", "#dd8a5b"] },
        "cloudy":  { day: ["#5a6b7d", "#90a0b0"], night: ["#2a323c", "#48525e"], dawn: ["#4a5260", "#9a8a86"], dusk: ["#434a5a", "#8a7a7e"] },
        "fog":     { day: ["#6b7079", "#9aa0aa"], night: ["#33373e", "#52575f"], dawn: ["#5a5d66", "#9a948f"], dusk: ["#4e515a", "#8a847e"] },
        "rain":    { day: ["#46566a", "#74859a"], night: ["#1f2733", "#3a4554"], dawn: ["#3a4458", "#6a6e7e"], dusk: ["#343c50", "#5e5a6a"] },
        "snow":    { day: ["#7e8a99", "#b4bec8"], night: ["#3a414c", "#5a626e"], dawn: ["#6a7080", "#aaa2a0"], dusk: ["#5e6472", "#9a9098"] },
        "thunder": { day: ["#3a3f55", "#5e5566"], night: ["#1a1c2e", "#352f45"], dawn: ["#33384e", "#6a5a66"], dusk: ["#2e3248", "#5a4e5e"] }
    })
    // Returns [topColor, bottomColor].
    function gradient(cat, phase) {
        let g = root._grad[cat] || root._grad["clear"]
        return g[phase] || g.day
    }

    function roundDeg(x) { return Math.round(x) + "°" }
    function minsOf(iso) {
        let t = iso.split("T")[1] || "0:0"
        let p = t.split(":")
        return parseInt(p[0]) * 60 + parseInt(p[1])
    }
    function hour12(h) {
        let ap = h < 12 ? "AM" : "PM"
        let hh = h % 12; if (hh === 0) hh = 12
        return hh + " " + ap
    }
    function clock12(iso) {
        let t = iso.split("T")[1] || "0:0"
        let p = t.split(":")
        let h = parseInt(p[0]), m = parseInt(p[1])
        let ap = h < 12 ? "AM" : "PM"
        let hh = h % 12; if (hh === 0) hh = 12
        return hh + ":" + (m < 10 ? "0" + m : m) + " " + ap
    }
}
