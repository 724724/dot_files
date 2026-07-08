pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Data + operations backing the Mission Control overview.
//
// Window geometry (at/size/fullscreen) isn't fully surfaced by Quickshell.Hyprland,
// so — like the quickshell-overview reference — we poll `hyprctl ... -j` and refresh
// on Hyprland events. All window/workspace operations go through the Hyprland *Lua*
// config (this machine runs hyprland.lua), so dispatchers must use the `hl.dsp.*`
// API rather than the classic string form (which Lua rejects).
Singleton {
    id: root

    // ── Raw state (filled from hyprctl) ───────────────────────────────────────
    property var windows: []            // hyprctl clients -j (normal windows only)
    property var workspaces: []         // hyprctl workspaces -j (id 1..100)
    property var monitors: []           // hyprctl monitors -j
    property int activeWorkspaceId: 1   // focused monitor's active workspace
    // Change-detection signatures so identical poll results don't churn the UI.
    property string _winSig: ""
    property string _wsSig: ""
    property string _monSig: ""

    // User-added empty workspaces. Hyprland drops empty workspaces, so to keep a
    // freshly-added (still empty) space visible until the user removes it with ×,
    // we track its id here and merge it into the displayed list.
    property var extraWorkspaces: []
    // Custom display order for the overview strip (drag-to-reorder). Ids not listed
    // here fall back to numeric order, after the ordered ones.
    property var workspaceOrder: []
    // Workspaces just deleted via ×: hidden immediately while their windows finish
    // moving out (cleared once empty), so the tile vanishes at once.
    property var deletedWorkspaces: []

    property bool open: false           // overview visibility (drives the poll timer)

    // ── Derived ───────────────────────────────────────────────────────────────
    // Union of real workspace ids and the user's extra (empty) ones, minus any
    // just-deleted ones, ordered by the custom strip order, then by id.
    readonly property var displayWorkspaceIds: {
        let set = {}
        for (let w of workspaces) if (w.id >= 1 && w.id <= 100) set[w.id] = true
        for (let e of extraWorkspaces) set[e] = true
        set[activeWorkspaceId] = true   // current space is always shown
        for (let d of deletedWorkspaces) delete set[d]
        let ids = Object.keys(set).map(n => parseInt(n))
        let order = root.workspaceOrder
        ids.sort((a, b) => {
            let ia = order.indexOf(a), ib = order.indexOf(b)
            if (ia === -1 && ib === -1) return a - b
            if (ia === -1) return 1
            if (ib === -1) return -1
            return ia - ib
        })
        return ids
    }

    // Drag-to-reorder: actually re-number the workspaces so the new strip order
    // becomes the real order (e.g. swapping 1↔2 makes what was 2 become 1). The
    // bar shows workspaces by id, so it reflects the new order too.
    function moveWorkspaceOrder(srcId, index) {
        let order = root.displayWorkspaceIds.slice()
        let cur = order.indexOf(srcId)
        if (cur === -1) return
        order.splice(cur, 1)
        index = Math.max(0, Math.min(index, order.length))
        order.splice(index, 0, srcId)
        root._applyOrder(order)
    }

    // Re-assign each space's *contents* (and persistence) to the canonical ids in
    // the new order: the thing shown at position i moves to the i-th smallest id.
    // Window moves are by address, so they don't collide; an optimistic local
    // rewrite updates the UI instantly while Hyprland catches up.
    function _applyOrder(order) {
        let canonical = order.slice().sort((a, b) => a - b)
        let targetOf = {}
        for (let i = 0; i < order.length; i++) targetOf[order[i]] = canonical[i]

        // Current persistence (empty spaces are only kept alive by it).
        let curPersist = {}
        for (let w of root.workspaces) curPersist[w.id] = !!w.ispersistent

        // Move windows to their workspace's target id.
        let newWindows = []
        for (let w of root.windows) {
            let src = (w.workspace && typeof w.workspace.id === "number") ? w.workspace.id : null
            let dst = (src !== null && targetOf[src] !== undefined) ? targetOf[src] : src
            if (src !== null && dst !== src)
                _dispatch("hl.dsp.window.move({workspace = '" + dst + "', follow = false, window = 'address:" + w.address + "'})")
            let nw = {}
            for (let k in w) nw[k] = w[k]
            nw.workspace = { id: (dst === null ? src : dst), name: String(dst) }
            newWindows.push(nw)
        }

        // Persistence follows its space to the new id.
        for (let i = 0; i < order.length; i++) {
            let src = order[i], dst = canonical[i]
            let want = curPersist[src] || false
            if (want !== (curPersist[dst] || false)) root._setPersistent(dst, want)
        }

        root.extraWorkspaces = root.extraWorkspaces.map(e => targetOf[e] !== undefined ? targetOf[e] : e)
        root.windows = newWindows          // instant UI; poll reconciles shortly
        root.workspaceOrder = []           // ids now match the order
        refreshSoon()
    }

    function windowsForWorkspace(wsId) {
        return windows.filter(w => w && w.workspace && w.workspace.id === wsId)
    }
    function _isDisplayWindow(w) {
        let cls = ((w && (w.class || w.initialClass)) || "").trim()
        let title = ((w && (w.title || w.initialTitle)) || "").trim()
        return w && w.mapped && w.workspace && w.workspace.id >= 1 && w.workspace.id <= 100
            && cls !== "" && title !== ""
    }
    function activeWorkspaceIdForMonitor(name) {
        let m = monitors.find(x => x && x.name === name)
        if (m && m.activeWorkspace && typeof m.activeWorkspace.id === "number")
            return m.activeWorkspace.id
        return activeWorkspaceId
    }
    // Same list, ordered to match the on-screen layout (reading order: upper rows
    // first, left-to-right within a row) so the overview grid mirrors reality
    // instead of hyprctl's stacking order.
    function windowsForWorkspaceSorted(wsId) {
        let arr = windowsForWorkspace(wsId).slice()
        arr.sort((a, b) => {
            let acy = a.at[1] + a.size[1] / 2, bcy = b.at[1] + b.size[1] / 2
            let tol = Math.min(a.size[1], b.size[1]) * 0.5
            if (Math.abs(acy - bcy) > tol) return acy - bcy                    // row
            return (a.at[0] + a.size[0] / 2) - (b.at[0] + b.size[0] / 2)        // column
        })
        return arr
    }
    // fullscreen field: 0 none, 1 maximized, 2 real fullscreen. We only treat real
    // fullscreen (2) specially — maximized stays a normal "Workspace N".
    function workspaceHasFullscreen(wsId) {
        return windowsForWorkspace(wsId).some(w => w.fullscreen === 2)
    }
    // Name shown on a workspace tile: the window title when something is fullscreen
    // (macOS shows the app name for full-screen / split spaces), else "Workspace N".
    function workspaceLabel(wsId) {
        let ws = windowsForWorkspace(wsId)
        // Real fullscreen → the app's *initial* title (the UI elides it if long).
        let fs = ws.find(w => w.fullscreen === 2)
        if (fs) return fs.initialTitle || fs.title || ("Workspace " + wsId)
        // A 2-window tiled space reads like macOS Split View → "A & B", left first.
        let tiled = ws.filter(w => !w.floating)
        if (tiled.length === 2) {
            let s = tiled.slice().sort((a, b) => a.at[0] - b.at[0])
            return root._shortTitle(s[0].initialTitle || s[0].title)
                + " & " + root._shortTitle(s[1].initialTitle || s[1].title)
        }
        return "Workspace " + wsId
    }
    function _shortTitle(t) {
        if (!t) return ""
        // Most titles are "Document — App"; keep the app/last segment, macOS-style.
        let parts = t.split(/ [–—-] /)
        return parts[parts.length - 1].trim() || t
    }

    function nextWorkspaceId() {
        let max = 0
        for (let i of displayWorkspaceIds) if (i > max) max = i
        return max + 1
    }

    // ── Operations (Hyprland Lua dispatchers) ─────────────────────────────────
    function _dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }
    // Config-level eval (workspace rules) — `hyprctl keyword` is rejected under
    // the Lua parser, so persistent-workspace rules go through `hyprctl eval`.
    function _eval(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]) }
    function _focusedMonitorName() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name) return Hyprland.focusedMonitor.name
        return root.monitors.length ? (root.monitors[0].name || "") : ""
    }
    function _setPersistent(wsId, on) {
        let lua = "hl.workspace_rule({workspace = " + wsId + ", persistent = " + (on ? "true" : "false")
        if (on) { let m = root._focusedMonitorName(); if (m) lua += ", monitor = '" + m + "'" }
        lua += "})"
        _eval(lua)
    }

    // Move a window to a workspace. follow=false keeps the user where they are
    // (silent); the workspace is created if it doesn't exist yet.
    function moveWindowToWorkspace(address, wsId, follow) {
        _dispatch("hl.dsp.window.move({workspace = '" + wsId + "', follow = "
            + (follow ? "true" : "false") + ", window = 'address:" + address + "'})")
        // If it landed on a tracked-empty space, that space is real now.
        root.extraWorkspaces = root.extraWorkspaces.filter(e => e !== wsId)
        refreshSoon()
    }

    // Clicking a window in the overview should both focus it (switching to its
    // space) and raise it to the very top of the stack.
    function focusWindow(address) {
        _dispatch("hl.dsp.focus({window = 'address:" + address + "'})")
        _dispatch("hl.dsp.window.bring_to_top('address:" + address + "')")
    }
    function focusWorkspace(wsId) {
        _dispatch("hl.dsp.focus({workspace = '" + wsId + "'})")
    }
    function closeWindow(address) {
        _dispatch("hl.dsp.window.close('address:" + address + "')")
        refreshSoon()
    }

    // fullscreen() is a *toggle*, so only fire it when the desired state differs
    // from the window's current one (read from the polled client list).
    function _isFullscreen(address) {
        let w = windows.find(x => x.address === address)
        return w ? w.fullscreen === 2 : false
    }
    function setFullscreen(address, on) {
        if (root._isFullscreen(address) === on) return
        _dispatch("hl.dsp.window.fullscreen({window = 'address:" + address + "', mode = 0})")
        refreshSoon()
    }

    // Drop an app on the "+" ghost tile → move it into a brand-new workspace (the
    // window keeps its normal tiled/floating state; the new space exists because it
    // now has a window in it). Does not switch to it.
    function moveWindowToNewWorkspace(address) {
        let wsId = root.nextWorkspaceId()
        moveWindowToWorkspace(address, wsId, false)
    }

    // Drop an app on the empty strip → it gets its own new space, full-screen.
    // follow=false: the overview stays on the CURRENT space (it does not jump to
    // the new one); the app is fullscreened in place by address.
    function moveWindowToNewFullscreen(address) {
        let wsId = root.nextWorkspaceId()
        _dispatch("hl.dsp.window.move({workspace = '" + wsId + "', follow = false, window = 'address:" + address + "'})")
        // Give the move a beat before fullscreening that specific window.
        fsTimer.address = address
        fsTimer.restart()
        refreshSoon()
    }
    Timer {
        id: fsTimer
        property string address: ""
        interval: 90
        onTriggered: root.setFullscreen(address, true)
    }

    // Drop an app onto a full-screen space → a real 1:1 dwindle split. In order:
    // exit the full-screen, turn *floating off* on BOTH windows (so dwindle actually
    // tiles them instead of leaving small floating windows), move the dragged app in
    // (dwindle splits 50/50), then nudge it to the requested side. Run as one ordered
    // shell sequence so the steps can't race.
    function splitInto(fsAddress, draggedAddress, wsId, side) {
        let dir = (side === "left") ? "l" : "r"
        let seq =
            "hyprctl dispatch \"hl.dsp.window.fullscreen({window = 'address:" + fsAddress + "', mode = 0})\"; " +
            "hyprctl dispatch \"hl.dsp.window.float({window = 'address:" + fsAddress + "', state = false})\"; " +
            "hyprctl dispatch \"hl.dsp.window.float({window = 'address:" + draggedAddress + "', state = false})\"; " +
            "hyprctl dispatch \"hl.dsp.window.move({workspace = '" + wsId + "', follow = false, window = 'address:" + draggedAddress + "'})\"; " +
            "sleep 0.12; " +
            "hyprctl dispatch \"hl.dsp.window.move({window = 'address:" + draggedAddress + "', direction = '" + dir + "'})\""
        Quickshell.execDetached(["bash", "-c", seq])
        refreshSoon()
    }

    // + button: add a new workspace. Make it a *persistent* Hyprland workspace so
    // it survives being empty — it then shows in the bar (Hyprland.workspaces) too,
    // not just here, and stays until removed with ×. Does NOT switch to it.
    function addWorkspace() {
        let id = root.nextWorkspaceId()
        root._setPersistent(id, true)
        if (root.extraWorkspaces.indexOf(id) === -1)
            root.extraWorkspaces = root.extraWorkspaces.concat([id])  // show instantly
        refreshSoon()
    }

    // × button: send every window in this space to `intoWsId`, drop its persistence
    // (so the now-empty space disappears), and forget it.
    function deleteWorkspace(wsId, intoWsId) {
        let wins = root.windowsForWorkspace(wsId)
        for (let w of wins)
            _dispatch("hl.dsp.window.move({workspace = '" + intoWsId + "', follow = false, window = 'address:" + w.address + "'})")
        root._setPersistent(wsId, false)
        root.extraWorkspaces = root.extraWorkspaces.filter(e => e !== wsId)
        root.workspaceOrder = root.workspaceOrder.filter(e => e !== wsId)
        if (root.deletedWorkspaces.indexOf(wsId) === -1)
            root.deletedWorkspaces = root.deletedWorkspaces.concat([wsId])  // hide now
        refreshSoon()
    }

    // ── Polling ───────────────────────────────────────────────────────────────
    // Refresh both our hyprctl geometry snapshot and Hyprland's toplevel list
    // (the latter supplies the Wayland capture handles used by ScreencopyView).
    function refresh() {
        if (!pollProc.running) pollProc.running = true
        Hyprland.refreshToplevels()
    }
    function refreshSoon() { debounce.restart() }
    Timer { id: debounce; interval: 60; onTriggered: root.refresh() }

    // Single shell call returns all four datasets as one JSON blob — fewer process
    // spawns than four separate hyprctl calls per refresh.
    Process {
        id: pollProc
        command: ["bash", "-c",
            "printf '{\"clients\":%s,\"workspaces\":%s,\"monitors\":%s,\"active\":%s}' " +
            "\"$(hyprctl clients -j)\" \"$(hyprctl workspaces -j)\" " +
            "\"$(hyprctl monitors -j)\" \"$(hyprctl activeworkspace -j)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(text) } catch (e) { return }
                let cl = (d.clients || []).filter(w => root._isDisplayWindow(w))
                // Only reassign when the data actually changed. Otherwise every poll
                // hands the Repeaters a brand-new array, so they destroy and recreate
                // ALL window previews (and their ScreencopyViews) — the main cause of
                // the heavy lag while the overview is open.
                let cs = JSON.stringify(cl.map(w => [w.address, w.workspace && w.workspace.id,
                    w.at, w.size, w.title, w.fullscreen, w.floating, w.class]))
                if (cs !== root._winSig) { root._winSig = cs; root.windows = cl }
                let wl = (d.workspaces || []).filter(w => w.id >= 1 && w.id <= 100)
                let ws = JSON.stringify(wl.map(w => [w.id, w.name, w.monitor, w.ispersistent]))
                if (ws !== root._wsSig) { root._wsSig = ws; root.workspaces = wl }
                let ml = d.monitors || []
                let ms = JSON.stringify(ml.map(m => [m.name, m.x, m.y, m.width, m.height, m.scale,
                    m.activeWorkspace && m.activeWorkspace.id]))
                if (ms !== root._monSig) { root._monSig = ms; root.monitors = ml }
                if (d.active && typeof d.active.id === "number") root.activeWorkspaceId = d.active.id
                // Stop hiding a just-deleted space once it's actually gone — i.e.
                // it no longer has windows and is no longer a (persistent) workspace.
                if (root.deletedWorkspaces.length > 0)
                    root.deletedWorkspaces = root.deletedWorkspaces.filter(id =>
                        cl.some(w => w.workspace && w.workspace.id === id)
                        || root.workspaces.some(w => w.id === id))
            }
        }
    }

    // React to Hyprland events so the overview tracks moves/closes live.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.open) return
            root.refreshSoon()
        }
    }

    // Light periodic refresh while open, so live geometry/titles stay current even
    // if an event is missed.
    Timer {
        interval: 600
        repeat: true
        running: root.open
        onTriggered: root.refresh()
    }

    onOpenChanged: if (open) refresh()
}
