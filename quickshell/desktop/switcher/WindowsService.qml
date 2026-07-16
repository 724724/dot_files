pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../dock" as Dock

// MRU view over DockService's shared Hyprland snapshot. Previously this service
// ran its own hyprctl+jq command on every raw event plus a periodic backstop.
Singleton {
    id: root

    readonly property var windows: {
        let result = []
        let byClass = Dock.DockService.clientsByClass || {}
        let classes = Object.keys(byClass)
        for (let i = 0; i < classes.length; i++) {
            let fallbackClass = classes[i]
            let clsLc = fallbackClass.toLowerCase()
            if (!fallbackClass || clsLc.startsWith("xwaylandvideobridge")
                    || clsLc.startsWith("xembedsniproxy")) continue
            let entries = byClass[fallbackClass] || []
            for (let j = 0; j < entries.length; j++) {
                let w = entries[j]
                result.push({
                    address: w.address || "",
                    class: w.class || fallbackClass,
                    title: w.title || "",
                    workspaceId: Number(w.workspaceId),
                    workspaceName: w.ws || "",
                    focusHistoryID: Number(w.focusHistoryID)
                })
            }
        }
        result.sort((a, b) => a.focusHistoryID - b.focusHistoryID)
        return result
    }

    // Callers still request a refresh before opening; delegate that request to
    // the one snapshot owner instead of launching a second query pipeline.
    function refresh() { Dock.DockService.refresh() }

    function focusByAddress(addr) {
        if (!addr) return
        focusProc.command = [Quickshell.shellDir + "/../scripts/switcher-focus-window.sh", addr]
        focusProc.running = true
    }

    Process { id: focusProc; command: ["true"] }
}
