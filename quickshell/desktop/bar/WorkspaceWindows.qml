pragma Singleton
import Quickshell
import QtQuick
import "../dock" as Dock

// Maps each Hyprland workspace to the icons of the apps open on it. Window
// geometry/class data comes from DockService's shared client snapshot so this
// singleton does not run a second Hyprland refresh loop.
Singleton {
    id: root

    property var appsByWorkspace: ({})

    function _baseClass(cls) {
        let lc = cls.toLowerCase()
        if (lc === "explorer.exe" || lc === "kakaotalk.exe") return cls
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        return m ? m[1] : cls
    }

    property var _iconCache: ({})
    function _iconName(cls) {
        let base = _baseClass(cls)
        let cached = _iconCache[base]
        if (cached !== undefined) return cached
        let lc = base.toLowerCase()
        let name
        if (lc === "explorer.exe") name = "ableton"
        else if (lc === "code") name = "visual-studio-code"
        else if (lc === "com.transmissionbt.transmission") name = "transmission"
        else {
            let de = DesktopEntries.heuristicLookup(base)
            name = (de && de.icon) ? de.icon : base
        }
        _iconCache[base] = name
        return name
    }

    readonly property var scanned: {
        let byClass = Dock.DockService.clientsByClass || {}
        let map = {}
        let seen = {}
        let classes = Object.keys(byClass)
        for (let i = 0; i < classes.length; i++) {
            let cls = classes[i]
            let clsLc = cls.toLowerCase()
            if (!cls || clsLc.startsWith("xembedsniproxy")
                    || clsLc.startsWith("xwaylandvideobridge")) continue
            let windows = byClass[cls] || []
            for (let j = 0; j < windows.length; j++) {
                let w = windows[j]
                let wid = Number(w.workspaceId)
                if (!Number.isFinite(wid) || wid < 0) continue
                let key = String(wid)
                let dedup = key + "|" + _baseClass(cls).toLowerCase()
                if (seen[dedup]) continue
                seen[dedup] = true
                ;(map[key] || (map[key] = [])).push(_iconName(cls))
            }
        }
        return map
    }

    onScannedChanged: {
        if (JSON.stringify(scanned) !== JSON.stringify(appsByWorkspace))
            appsByWorkspace = scanned
    }
}
