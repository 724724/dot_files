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
    readonly property int cacheTtlMs: 60 * 60 * 1000
    readonly property string sharedStateRoot: {
        const xdg = String(Quickshell.env("XDG_STATE_HOME") || "").trim()
        if (xdg !== "")
            return xdg + "/quickshell"
        const home = String(Quickshell.env("HOME") || "").trim()
        return home !== "" ? home + "/.local/state/quickshell" : ""
    }
    property var _forecastCache: ({})
    property var _locationCache: null

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

    Component.onCompleted: {
        root._loadPlaces()
        root._loadDataCache()
        root._applyCachedLocation()
        // Both desktop and lock processes share this cache. Resolve only when
        // the cached location is absent or older than the one-hour TTL.
        if (!root.locationFresh())
            root.resolveCurrent()
    }
    function resolveCurrent() { geoProc.running = true }

    function _coordinateKey(lat, lon) {
        const latitude = Number(lat)
        const longitude = Number(lon)
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude))
            return ""
        return latitude.toFixed(4) + "," + longitude.toFixed(4)
    }
    function cachedForecast(lat, lon) {
        const key = root._coordinateKey(lat, lon)
        const entry = key !== "" ? root._forecastCache[key] : null
        if (!entry || typeof entry !== "object" || typeof entry.text !== "string")
            return null
        return entry
    }
    function forecastFresh(lat, lon) {
        const entry = root.cachedForecast(lat, lon)
        const savedAt = Number(entry && entry.savedAt)
        return Number.isFinite(savedAt) && savedAt > 0 && Date.now() - savedAt < root.cacheTtlMs
    }
    function storeForecast(lat, lon, text) {
        const key = root._coordinateKey(lat, lon)
        if (key === "" || typeof text !== "string" || text.trim() === "")
            return
        let next = Object.assign({}, root._forecastCache)
        next[key] = { "savedAt": Date.now(), "text": text }
        const keys = Object.keys(next).sort((a, b) => Number(next[b].savedAt || 0) - Number(next[a].savedAt || 0))
        for (let i = 24; i < keys.length; i++)
            delete next[keys[i]]
        root._forecastCache = next
        root._persistDataCache()
    }
    function locationFresh() {
        const savedAt = Number(root._locationCache && root._locationCache.savedAt)
        return Number.isFinite(savedAt) && savedAt > 0 && Date.now() - savedAt < root.cacheTtlMs
    }
    function _applyCachedLocation() {
        const entry = root._locationCache
        if (!entry || !Number.isFinite(Number(entry.lat)) || !Number.isFinite(Number(entry.lon)))
            return false
        root.currentLat = Number(entry.lat)
        root.currentLon = Number(entry.lon)
        root.currentName = String(entry.name || "Current Location")
        root.currentReady = true
        return true
    }
    function _storeLocation(name, lat, lon) {
        root._locationCache = {
            "savedAt": Date.now(),
            "name": String(name || "Current Location"),
            "lat": Number(lat),
            "lon": Number(lon)
        }
        root._persistDataCache()
    }
    function _loadDataCache() {
        try {
            const parsed = JSON.parse(dataCacheStore.text() || "{}")
            root._forecastCache = parsed && parsed.forecasts && typeof parsed.forecasts === "object" ? parsed.forecasts : ({})
            root._locationCache = parsed && parsed.location && typeof parsed.location === "object" ? parsed.location : null
        } catch (error) {
            root._forecastCache = ({})
            root._locationCache = null
        }
    }
    function _persistDataCache() {
        dataCacheStore.setText(JSON.stringify({
            "version": 1,
            "location": root._locationCache,
            "forecasts": root._forecastCache
        }))
    }

    // The IP lookup used to be a single shot at startup: if the network wasn't
    // up yet (or the geo APIs hiccuped), every "Current Location" widget stayed
    // blank until a manual reload. Retry once a minute until it succeeds.
    Timer {
        interval: 60 * 1000
        running: !root.currentReady || !root.locationFresh()
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
                    root._storeLocation(root.currentName, root.currentLat, root.currentLon)
                } catch (e) { /* keep */ }
            }
        }
    }

    FileView {
        id: dataCacheStore

        blockLoading: true
        path: root.sharedStateRoot !== "" ? root.sharedStateRoot + "/weather-widget-cache.json" : ""
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoaded: {
            root._loadDataCache()
            root._applyCachedLocation()
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
