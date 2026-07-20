pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Placed-widget board model + disk persistence.
//
// Each row: { wid, type, nx, ny, nw, nh, payload } where `payload` is a JSON
// string of type-specific state (note html/colour, reminders items, clock
// layout + faces, …). Role names avoid Item built-ins (x/y/width/height/data)
// so the delegate can use required properties. See [[quickshell-hyprland-quirks]].
Singleton {
    id: root

    // ── Board grid ───────────────────────────────────────────────────────
    // Every widget except sticky notes snaps to an n×m grid sized to the
    // monitor: cells of gridCell px separated by gridGap. Preset sizes below
    // are exact cell multiples (220 / 464 / 708 = 1 / 2 / 3 cells). The board
    // (WidgetsWindow) auto-flows widgets into free slots; it re-runs when
    // relayoutNeeded fires.
    readonly property int gridCell: 220
    readonly property int gridGap: 24
    readonly property int gridUnit: gridCell + gridGap
    signal relayoutNeeded()

    // Sticky-note palette (macOS Stickies-ish). First entry is the default.
    readonly property var palette: [
        "#FEF49C", "#FFC4D6", "#C7F0BD", "#BFE3F7", "#E5D4F7", "#FFD9A8"
    ]
    readonly property int minFont: 9
    readonly property int maxFont: 40

    // World-clock city presets (standard-time UTC offsets; DST not tracked).
    readonly property var cityPresets: [
        { name: "Local",       tz: 0 },   // tz filled in live via localOffset()
        { name: "Honolulu",    tz: -10 },
        { name: "Los Angeles", tz: -8 },
        { name: "Cupertino",   tz: -8 },
        { name: "Denver",      tz: -7 },
        { name: "Chicago",     tz: -6 },
        { name: "New York",    tz: -5 },
        { name: "São Paulo",   tz: -3 },
        { name: "London",      tz: 0 },
        { name: "Paris",       tz: 1 },
        { name: "Berlin",      tz: 1 },
        { name: "Cairo",       tz: 2 },
        { name: "Cape Town",   tz: 2 },
        { name: "Moscow",      tz: 3 },
        { name: "Dubai",       tz: 4 },
        { name: "Karachi",     tz: 5 },
        { name: "Mumbai",      tz: 5.5 },
        { name: "Dhaka",       tz: 6 },
        { name: "Bangkok",     tz: 7 },
        { name: "Beijing",     tz: 8 },
        { name: "Singapore",   tz: 8 },
        { name: "Hong Kong",   tz: 8 },
        { name: "Tokyo",       tz: 9 },
        { name: "Seoul",       tz: 9 },
        { name: "Sydney",      tz: 10 },
        { name: "Auckland",    tz: 12 }
    ]

    function localOffset() { return -(new Date().getTimezoneOffset()) / 60 }

    function faceFromName(name) {
        if (name === "Local") return { city: "Local", tz: root.localOffset() }
        for (let i = 0; i < cityPresets.length; i++)
            if (cityPresets[i].name === name) return { city: name, tz: cityPresets[i].tz }
        return { city: "Local", tz: root.localOffset() }
    }

    function defaultClockFaces(layout) {
        if (layout === 2 || layout === 3)
            return [ faceFromName("Local"), faceFromName("New York"),
                     faceFromName("London"), faceFromName("Tokyo") ]
        return [ faceFromName("Local") ]
    }

    // All preset sizes are exact grid spans (220=1, 464=2, 708=3 cells).
    function clockSize(layout) {
        switch (layout) {
        case 2:  return { nw: 464, nh: 220 }   // world row
        case 1:
        case 3:
        case 4:
        case 5:
        default: return { nw: 220, nh: 220 }
        }
    }

    function weatherSize(layout) {
        switch (layout) {
        case 2:  return { nw: 464, nh: 220 }   // medium (hourly)
        case 3:  return { nw: 220, nh: 220 }   // conditions (small)
        case 4:  return { nw: 220, nh: 220 }   // sun
        case 1:
        default: return { nw: 464, nh: 464 }   // large (hourly + daily)
        }
    }

    function remindersSize(layout) {
        switch (layout) {
        case 1:  return { nw: 220, nh: 220 }   // small
        case 3:  return { nw: 220, nh: 464 }   // large
        case 2:
        default: return { nw: 464, nh: 220 }   // medium
        }
    }

    function calendarSize(layout) {
        switch (layout) {
        case 1:  return { nw: 220, nh: 220 }   // small
        case 3:  return { nw: 464, nh: 464 }   // large
        case 2:
        default: return { nw: 464, nh: 220 }   // medium
        }
    }

    function newsSize(layout) {
        switch (layout) {
        case 4:  return { nw: 220, nh: 220 }   // x-small
        case 1:  return { nw: 464, nh: 464 }   // small
        case 3:  return { nw: 708, nh: 708 }   // large
        case 2:
        default: return { nw: 708, nh: 464 }   // medium
        }
    }

    function stockSize() {
        return { nw: 708, nh: 708 }
    }

    function youtubeSize(layout) {
        switch (layout) {
        case 1:  return { nw: 220, nh: 220 }
        case 2:  return { nw: 464, nh: 220 }
        case 3:
        default: return { nw: 708, nh: 464 }
        }
    }

    function spotifySize(layout) {
        switch (layout) {
        case 1:  return { nw: 220, nh: 220 }
        case 2:  return { nw: 464, nh: 220 }
        case 3:
        default: return { nw: 708, nh: 464 }
        }
    }

    // Canonical size for a grid widget, derived from its type + layout. The
    // board relayout always sizes from this (never from persisted nw/nh, which
    // a mis-timed early relayout could otherwise shrink permanently). Notes
    // return null — they keep their free-form size.
    function presetSize(type, layout) {
        switch (type) {
        case "clock":     return clockSize(layout || 4)
        case "weather":   return weatherSize(layout || 1)
        case "reminders": return remindersSize(layout || 2)
        case "news":      return newsSize(layout || 2)
        case "calendar":  return calendarSize(layout || 2)
        case "stock":     return stockSize()
        case "youtube":   return youtubeSize(layout || 3)
        case "spotify":   return spotifySize(layout || 3)
        }
        return null
    }

    property alias widgets: widgetsModel
    property string activeBoardKey: ""
    property var _boards: ({})
    property var _legacyWidgets: []
    property bool _loaded: false
    signal boardChanged(string key)
    ListModel { id: widgetsModel }

    Component.onCompleted: root._load()

    FileView {
        id: store
        path: Quickshell.stateDir + "/widgets.json"
        blockLoading: true
        printErrors: false
    }
    // Legacy sticky-notes file from before the widgets refactor — migrated once.
    FileView {
        id: legacy
        path: Quickshell.stateDir + "/notes.json"
        blockLoading: true
        printErrors: false
    }

    function _load() {
        if (root._loaded) return
        let raw = store.text()
        if (raw) {
            try {
                let value = JSON.parse(raw)
                if (Array.isArray(value)) root._legacyWidgets = value
                else if (value && value.boards && typeof value.boards === "object")
                    root._boards = value.boards
            } catch (e) {}
        } else {
            let old = legacy.text()
            if (old) root._legacyWidgets = root._migrate(old)
        }
        root._loaded = true
    }

    function _normalizedWidget(w, fallbackId) {
        w = w || {}
        return {
            wid: (w.wid !== undefined) ? w.wid : fallbackId,
            type: w.type || "note",
            nx: (w.nx !== undefined) ? w.nx : 80,
            ny: (w.ny !== undefined) ? w.ny : 80,
            nw: (w.nw !== undefined) ? w.nw : 240,
            nh: (w.nh !== undefined) ? w.nh : 240,
            payload: (typeof w.payload === "string") ? w.payload : JSON.stringify(w.payload || {})
        }
    }

    function _captureActiveBoard() {
        if (!root.activeBoardKey) return
        let rows = []
        for (let i = 0; i < widgetsModel.count; i++) {
            let w = widgetsModel.get(i)
            rows.push({ wid: w.wid, type: w.type, nx: w.nx, ny: w.ny,
                        nw: w.nw, nh: w.nh, payload: w.payload })
        }
        let boards = Object.assign({}, root._boards)
        boards[root.activeBoardKey] = rows
        root._boards = boards
    }

    function activateBoard(key) {
        if (!root._loaded) root._load()
        let nextKey = (key || "unknown-monitor").toString().trim() || "unknown-monitor"
        if (root.activeBoardKey === nextKey) return
        root._captureActiveBoard()
        let boards = Object.assign({}, root._boards)
        if (!Array.isArray(boards[nextKey])) {
            boards[nextKey] = root._legacyWidgets.length > 0 ? root._legacyWidgets.slice() : []
            root._legacyWidgets = []
        }
        root._boards = boards
        root.activeBoardKey = nextKey
        widgetsModel.clear()
        let rows = boards[nextKey]
        for (let i = 0; i < rows.length; i++)
            widgetsModel.append(root._normalizedWidget(rows[i], Date.now() + i))
        root.persist()
        root.boardChanged(nextKey)
        root.relayoutNeeded()
    }

    // Convert the old notes.json (array of sticky notes) into note widgets.
    function _migrate(old) {
        let result = []
        try {
            let arr = JSON.parse(old)
            if (!Array.isArray(arr)) return result
            for (let i = 0; i < arr.length; i++) {
                let n = arr[i] || {}
                result.push({
                    wid: (n.noteId !== undefined) ? n.noteId : (Date.now() + i),
                    type: "note",
                    nx: (n.nx !== undefined) ? n.nx : 80,
                    ny: (n.ny !== undefined) ? n.ny : 80,
                    nw: (n.nw !== undefined) ? n.nw : 240,
                    nh: (n.nh !== undefined) ? n.nh : 240,
                    payload: JSON.stringify({
                        content: n.content || "",
                        swatch: n.swatch || root.palette[0],
                        fontSize: (n.fontSize !== undefined) ? n.fontSize : 15,
                        collapsed: (n.collapsed !== undefined) ? n.collapsed : false
                    })
                })
            }
        } catch (e) { /* ignore */ }
        return result
    }

    function persist() {
        if (!root.activeBoardKey) return
        root._captureActiveBoard()
        store.setText(JSON.stringify({ version: 2, boards: root._boards }))
    }

    function _newId() {
        let max = 0
        for (let i = 0; i < widgetsModel.count; i++)
            max = Math.max(max, widgetsModel.get(i).wid)
        return max + 1
    }

    function _countOfType(type) {
        let n = 0
        for (let i = 0; i < widgetsModel.count; i++)
            if (widgetsModel.get(i).type === type) n++
        return n
    }

    // 1-based position of a note among all notes, in board (open) order. Used
    // for the user-facing export filename (notes-1, notes-2, …) instead of the
    // internal `wid`, which is a stable key that can be large/stale after
    // creating + deleting notes.
    function noteOrdinal(index) {
        let n = 0
        for (let i = 0; i <= index && i < widgetsModel.count; i++)
            if (widgetsModel.get(i).type === "note") n++
        return n
    }

    // Default size + initial data per widget type.
    function _defaults(type) {
        switch (type) {
        case "clock":     return { nw: 220, nh: 220, data: { layout: 4, faces: root.defaultClockFaces(4) } }
        case "weather":   return { nw: 464, nh: 464, data: { layout: 1 } }
        case "reminders": return { nw: 464, nh: 220, data: { layout: 2, title: "Reminders", accent: "blue", items: [] } }
        case "news":      return { nw: 708, nh: 464, data: { layout: 2, sources: NewsService.defaultSources(), categories: NewsService.defaultCategories(), model: NewsService.defaultModel } }
        case "calendar":  return { nw: 464, nh: 220, data: { layout: 2 } }
        case "stock":     return { nw: 708, nh: 708, data: { language: "ko", symbol: "005930", market: "KRX", range: "1D", aiProvider: "none", analysisProfile: "balanced", dataMode: "demo", kisEnvironment: "paper", productionTradingEnabled: false, watchlist: [{ symbol: "005930", market: "KRX" }, { symbol: "000660", market: "KRX" }, { symbol: "035420", market: "KRX" }], priceAlerts: [] } }
        case "youtube":   return { nw: 708, nh: 464, data: { layout: 3, url: "", mediaKind: "video", videoQuality: "best", audioFormat: "m4a", cookieBrowser: "auto" } }
        case "spotify":   return { nw: 708, nh: 464, data: { layout: 3, url: "", audioFormat: "opus", bitrate: "auto", cookieBrowser: "auto" } }
        case "note":
        default:
            return { nw: 240, nh: 240, data: {
                content: "", swatch: root.palette[root._countOfType("note") % root.palette.length],
                fontSize: 15, fontFamily: "Apple SD Gothic Neo", collapsed: false } }
        }
    }

    // `extra` (optional) is merged into the default data (e.g. clock layout/faces).
    function addWidget(type, x, y, extra) {
        let d = _defaults(type)
        let data = d.data
        if (extra) for (let k in extra) data[k] = extra[k]
        let nw = d.nw, nh = d.nh
        if (type === "clock") {
            let sz = root.clockSize(data.layout || 4)
            nw = sz.nw; nh = sz.nh
        } else if (type === "weather") {
            let sz = root.weatherSize(data.layout || 1)
            nw = sz.nw; nh = sz.nh
        } else if (type === "reminders") {
            let sz = root.remindersSize(data.layout || 2)
            nw = sz.nw; nh = sz.nh
        } else if (type === "news") {
            let sz = root.newsSize(data.layout || 2)
            nw = sz.nw; nh = sz.nh
        } else if (type === "calendar") {
            let sz = root.calendarSize(data.layout || 2)
            nw = sz.nw; nh = sz.nh
        } else if (type === "stock") {
            let sz = root.stockSize()
            nw = sz.nw; nh = sz.nh
        } else if (type === "youtube") {
            let sz = root.youtubeSize(data.layout || 3)
            nw = sz.nw; nh = sz.nh
        } else if (type === "spotify") {
            let sz = root.spotifySize(data.layout || 3)
            nw = sz.nw; nh = sz.nh
        }
        widgetsModel.append({
            wid: root._newId(), type: type,
            nx: (x !== undefined) ? x : 120,
            ny: (y !== undefined) ? y : 120,
            nw: nw, nh: nh, payload: JSON.stringify(data)
        })
        root.persist()
        if (type !== "note") root.relayoutNeeded()
        return widgetsModel.count - 1
    }

    function removeAt(index) {
        if (index < 0 || index >= widgetsModel.count) return
        let wasNote = widgetsModel.get(index).type === "note"
        widgetsModel.remove(index)
        root.persist()
        if (!wasNote) root.relayoutNeeded()
    }

    function typeAt(index) {
        if (index < 0 || index >= widgetsModel.count) return ""
        return widgetsModel.get(index).type
    }

    function setPosition(index, x, y, save) {
        if (index < 0 || index >= widgetsModel.count) return
        widgetsModel.setProperty(index, "nx", x)
        widgetsModel.setProperty(index, "ny", y)
        if (save) root.persist()
    }

    function setSize(index, w, h, save) {
        if (index < 0 || index >= widgetsModel.count) return
        widgetsModel.setProperty(index, "nw", w)
        widgetsModel.setProperty(index, "nh", h)
        if (save) root.persist()
    }

    function getData(index) {
        if (index < 0 || index >= widgetsModel.count) return ({})
        try { return JSON.parse(widgetsModel.get(index).payload || "{}") } catch (e) { return ({}) }
    }

    // Merge `patch` into the widget's data object and persist.
    function setData(index, patch) {
        if (index < 0 || index >= widgetsModel.count) return
        let cur = getData(index)
        for (let k in patch) cur[k] = patch[k]
        let str = JSON.stringify(cur)
        if (str === widgetsModel.get(index).payload) return
        widgetsModel.setProperty(index, "payload", str)
        root.persist()
    }

    // Resize a clock to its layout's preferred size + ensure face count.
    function setClockLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let cur = getData(index)
        let faces = cur.faces || []
        let needMulti = (layout === 2 || layout === 3)
        if (needMulti) {
            let defs = root.defaultClockFaces(layout)
            while (faces.length < 4) faces.push(defs[faces.length])
            faces = faces.slice(0, 4)
        } else {
            faces = faces.slice(0, 1)
            if (faces.length === 0) faces = root.defaultClockFaces(layout)
        }
        let sz = root.clockSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout, faces: faces })
        root.relayoutNeeded()
    }

    // Resize a weather widget to its layout's preferred size.
    function setWeatherLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.weatherSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }

    function setRemindersLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.remindersSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }

    function setCalendarLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.calendarSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }

    function setNewsLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.newsSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }

    function setYoutubeLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.youtubeSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }

    function setSpotifyLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.spotifySize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
        root.relayoutNeeded()
    }
}
