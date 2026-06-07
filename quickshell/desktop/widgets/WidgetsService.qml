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

    function clockSize(layout) {
        switch (layout) {
        case 2:  return { nw: 470, nh: 150 }
        case 3:  return { nw: 240, nh: 240 }
        case 5:  return { nw: 200, nh: 200 }
        case 1:
        case 4:
        default: return { nw: 220, nh: 220 }
        }
    }

    function weatherSize(layout) {
        switch (layout) {
        case 2:  return { nw: 340, nh: 190 }   // medium (hourly)
        case 3:  return { nw: 184, nh: 170 }   // conditions (small)
        case 4:  return { nw: 210, nh: 158 }   // sun
        case 1:
        default: return { nw: 320, nh: 430 }   // large (hourly + daily)
        }
    }

    function remindersSize(layout) {
        switch (layout) {
        case 1:  return { nw: 232, nh: 196 }   // small
        case 3:  return { nw: 268, nh: 320 }   // large
        case 2:
        default: return { nw: 372, nh: 200 }   // medium
        }
    }

    property alias widgets: widgetsModel
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
        let raw = store.text()
        if (raw) { _loadFrom(raw); return }
        let old = legacy.text()
        if (old) _migrate(old)
    }

    function _loadFrom(raw) {
        try {
            let arr = JSON.parse(raw)
            if (!Array.isArray(arr)) return
            for (let i = 0; i < arr.length; i++) {
                let w = arr[i] || {}
                widgetsModel.append({
                    wid:  (w.wid !== undefined) ? w.wid : (Date.now() + i),
                    type: w.type || "note",
                    nx: (w.nx !== undefined) ? w.nx : 80,
                    ny: (w.ny !== undefined) ? w.ny : 80,
                    nw: (w.nw !== undefined) ? w.nw : 240,
                    nh: (w.nh !== undefined) ? w.nh : 240,
                    payload: (typeof w.payload === "string") ? w.payload : JSON.stringify(w.payload || {})
                })
            }
        } catch (e) { /* corrupt — start fresh */ }
    }

    // Convert the old notes.json (array of sticky notes) into note widgets.
    function _migrate(old) {
        try {
            let arr = JSON.parse(old)
            if (!Array.isArray(arr)) return
            for (let i = 0; i < arr.length; i++) {
                let n = arr[i] || {}
                widgetsModel.append({
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
            root.persist()
        } catch (e) { /* ignore */ }
    }

    function persist() {
        let arr = []
        for (let i = 0; i < widgetsModel.count; i++) {
            let w = widgetsModel.get(i)
            arr.push({ wid: w.wid, type: w.type, nx: w.nx, ny: w.ny, nw: w.nw, nh: w.nh, payload: w.payload })
        }
        store.setText(JSON.stringify(arr))
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
        case "weather":   return { nw: 320, nh: 430, data: { layout: 1 } }
        case "reminders": return { nw: 372, nh: 200, data: { layout: 2, title: "Reminders", accent: "blue", items: [] } }
        case "note":
        default:
            return { nw: 240, nh: 240, data: {
                content: "", swatch: root.palette[root._countOfType("note") % root.palette.length],
                fontSize: 15, fontFamily: "Pretendard Variable", collapsed: false } }
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
        }
        widgetsModel.append({
            wid: root._newId(), type: type,
            nx: (x !== undefined) ? x : 120,
            ny: (y !== undefined) ? y : 120,
            nw: nw, nh: nh, payload: JSON.stringify(data)
        })
        root.persist()
        return widgetsModel.count - 1
    }

    function removeAt(index) {
        if (index < 0 || index >= widgetsModel.count) return
        widgetsModel.remove(index)
        root.persist()
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
    }

    // Resize a weather widget to its layout's preferred size.
    function setWeatherLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.weatherSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
    }

    function setRemindersLayout(index, layout) {
        if (index < 0 || index >= widgetsModel.count) return
        let sz = root.remindersSize(layout)
        widgetsModel.setProperty(index, "nw", sz.nw)
        widgetsModel.setProperty(index, "nh", sz.nh)
        setData(index, { layout: layout })
    }
}
