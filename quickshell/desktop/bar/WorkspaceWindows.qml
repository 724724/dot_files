pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Maps each Hyprland workspace to the icons of the apps open on it, so the bar
// can show small app glyphs next to the workspace number.
Singleton {
    id: root

    // workspace id (as string) → [iconName, ...], one per distinct app class.
    property var appsByWorkspace: ({})

    // Strip the _PID_RANDOM suffix some Qt apps append to their class so the
    // lookup matches a stable name; leave hand-mapped Wine classes alone.
    function _baseClass(cls) {
        let lc = cls.toLowerCase()
        if (lc === "explorer.exe" || lc === "kakaotalk.exe") return cls
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        return m ? m[1] : cls
    }

    // Resolve a window class to a real icon-theme name. The class often differs
    // from the icon the .desktop entry declares (e.g. "code" → "visual-studio-
    // code"), so map the known mismatches by hand first (matching the dock),
    // then fall back to heuristicLookup against desktop entries — the same
    // source the launchpad/spotlight icons use — then the bare class name.
    function _iconName(cls) {
        let base = _baseClass(cls)
        let lc = base.toLowerCase()
        if (lc === "explorer.exe") return "ableton"
        if (lc === "kakaotalk.exe") return "KakaoTalk"
        if (lc === "code") return "visual-studio-code"
        if (lc === "com.transmissionbt.transmission") return "transmission"
        let de = DesktopEntries.heuristicLookup(base)
        if (de && de.icon) return de.icon
        return base
    }

    // Reactive scan of the live toplevel list. Re-runs whenever a window opens,
    // closes, or changes workspace/class.
    readonly property var scanned: {
        let tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        let map = {}
        let seen = {}
        for (let i = 0; i < tops.length; i++) {
            let t = tops[i]
            if (!t || !t.workspace) continue
            let wid = t.workspace.id
            if (wid === undefined || wid === null) continue
            let obj = t.lastIpcObject || {}
            let cls = obj.class || obj.initialClass || ""
            if (!cls && t.wayland) cls = t.wayland.appId || ""
            if (!cls) continue
            let key = String(wid)
            let dedup = key + "|" + _baseClass(cls).toLowerCase()
            if (seen[dedup]) continue
            seen[dedup] = true
            ;(map[key] || (map[key] = [])).push(_iconName(cls))
        }
        return map
    }

    // Publish only on real change so workspace buttons don't rebuild their icon
    // rows (and reload images) on every refresh tick.
    onScannedChanged: {
        if (JSON.stringify(scanned) !== JSON.stringify(appsByWorkspace))
            appsByWorkspace = scanned
    }

    // Hyprland's toplevel model doesn't self-populate and window moves between
    // workspaces don't always carry class info on the event alone, so re-query
    // periodically. refreshToplevels() is a cheap control-socket query.
    Component.onCompleted: Hyprland.refreshToplevels()
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: Hyprland.refreshToplevels()
    }
}
