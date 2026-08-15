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
    // Advances only after a complete hyprctl snapshot has been parsed.  The
    // controller waits for a revision requested at open time so a workspace
    // switch that is still animating cannot map Mission Control with the
    // previous workspace and then look like an in-overview workspace change.
    property int snapshotRevision: 0
    property bool _refreshQueued: false

    // User-added empty workspaces. Hyprland drops empty workspaces, so to keep a
    // freshly-added (still empty) space visible until the user removes it with ×,
    // we track its id here and merge it into the displayed list.
    property var extraWorkspaces: []
    property var extraWorkspaceMonitors: ({})
    // Custom display order for the overview strip (drag-to-reorder). Ids not listed
    // here fall back to numeric order, after the ordered ones.
    property var workspaceOrder: []
    // Workspaces just deleted via ×: hidden immediately while their windows finish
    // moving out (cleared once empty), so the tile vanishes at once.
    property var deletedWorkspaces: []

    property bool workspaceDragActive: false
    property int workspaceDragId: -1
    property string workspaceDragSourceMonitor: ""
    property string workspaceDragTargetMonitor: ""
    property point workspaceDragGlobalPos: Qt.point(0, 0)

    // Workspaces turned into a macOS-style Split View *via Mission Control* (drop
    // onto a fullscreen space → splitInto). Only these get the "A & B" strip label
    // and hide the bar/dock while active — a manual dwindle split never registers.
    // Persisted so a quickshell reload doesn't bring the bar/dock back mid-split.
    property var splitViewWorkspaces: []
    onSplitViewWorkspacesChanged: splitStore.setText(JSON.stringify(splitViewWorkspaces))
    // Creation grace deadlines (ws id → epoch ms): the splitInto dispatch sequence
    // passes through invalid states (1 window, floating) for a beat, so reconcile
    // tolerates those until the deadline.
    property var _splitGraceUntil: ({})
    // Ids observed with a valid 2-tiled layout this session. Survivor-fullscreen
    // enforcement only fires for these, so a stale persisted id can't fullscreen
    // an unrelated window right after startup.
    property var _splitSeenValid: ({})

    FileView {
        id: splitStore
        path: Quickshell.stateDir + "/mc-splitview.json"
        blockLoading: true
        printErrors: false
    }

    property bool open: false           // overview visibility (drives the poll timer)

    // ── Derived ───────────────────────────────────────────────────────────────
    // Union of real workspace ids and the user's extra (empty) ones, minus any
    // just-deleted ones, ordered by the custom strip order, then by id.
    readonly property var displayWorkspaceIds: {
        let set = {}
        for (let w of workspaces) if (w.id >= 1 && w.id <= 100) set[w.id] = true
        for (let e of extraWorkspaces) set[e] = true
        for (let m of monitors)
            if (m && m.activeWorkspace && m.activeWorkspace.id >= 1)
                set[m.activeWorkspace.id] = true
        set[activeWorkspaceId] = true
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

    function workspaceMonitorName(wsId) {
        let ws = root.workspaces.find(w => w && w.id === wsId)
        if (ws && ws.monitor) return ws.monitor
        let extraMonitor = root.extraWorkspaceMonitors[wsId]
        if (extraMonitor) return extraMonitor
        let monitor = root.monitors.find(m => m && m.activeWorkspace && m.activeWorkspace.id === wsId)
        return monitor ? monitor.name : ""
    }

    function workspaceIdsForMonitor(monitorName) {
        let ids = root.displayWorkspaceIds.filter(id => root.workspaceMonitorName(id) === monitorName)
        let active = root.activeWorkspaceIdForMonitor(monitorName)
        if (active >= 1 && ids.indexOf(active) === -1) ids.push(active)
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

    function moveWorkspaceOrder(srcId, index, monitorName) {
        let local = root.workspaceIdsForMonitor(monitorName)
        let cur = local.indexOf(srcId)
        if (cur === -1) return
        local.splice(cur, 1)
        index = Math.max(0, Math.min(index, local.length))
        local.splice(index, 0, srcId)
        root._applyWorkspaceOrder(local, monitorName)
    }

    function _applyWorkspaceOrder(order, monitorName) {
        let canonical = order.slice().sort((a, b) => a - b)
        let targetOf = {}
        let changed = false
        for (let i = 0; i < order.length; i++) {
            targetOf[order[i]] = canonical[i]
            if (order[i] !== canonical[i]) changed = true
        }
        if (!changed) return

        let persistent = {}
        for (let w of root.workspaces) persistent[w.id] = !!w.ispersistent
        let statements = []
        for (let id of canonical) statements.push(root._persistentRule(id, false, ""))

        root.windows = root.windows.map(w => {
            let src = w && w.workspace ? w.workspace.id : -1
            let dst = targetOf[src]
            if (dst === undefined || dst === src) return w
            statements.push("hl.dispatch(hl.dsp.window.move({workspace = '" + dst
                + "', follow = false, window = 'address:" + w.address + "'}))")
            let copy = {}
            for (let key in w) copy[key] = w[key]
            copy.workspace = { id: dst, name: String(dst) }
            return copy
        })
        for (let src of order)
            if (persistent[src] || root.extraWorkspaces.indexOf(src) !== -1)
                statements.push(root._persistentRule(targetOf[src], true, monitorName))
        root._eval(statements.join("; "))

        root.workspaces = root.workspaces.map(w => {
            if (!w || targetOf[w.id] === undefined) return w
            let copy = {}
            for (let key in w) copy[key] = w[key]
            copy.id = targetOf[w.id]
            copy.name = String(copy.id)
            return copy
        })

        root.extraWorkspaces = root.extraWorkspaces.map(id =>
            targetOf[id] === undefined ? id : targetOf[id])
        let extraMonitors = {}
        for (let key in root.extraWorkspaceMonitors) {
            let id = parseInt(key)
            let dst = targetOf[id] === undefined ? id : targetOf[id]
            extraMonitors[dst] = root.extraWorkspaceMonitors[key]
        }
        root.extraWorkspaceMonitors = extraMonitors
        root.splitViewWorkspaces = root.splitViewWorkspaces.map(id =>
            targetOf[id] === undefined ? id : targetOf[id])

        let grace = {}, seen = {}
        for (let key in root._splitGraceUntil) {
            let id = parseInt(key)
            grace[targetOf[id] === undefined ? id : targetOf[id]] = root._splitGraceUntil[key]
        }
        for (let key in root._splitSeenValid) {
            let id = parseInt(key)
            seen[targetOf[id] === undefined ? id : targetOf[id]] = root._splitSeenValid[key]
        }
        root._splitGraceUntil = grace
        root._splitSeenValid = seen

        let localSet = {}
        for (let id of canonical) localSet[id] = true
        root.workspaceOrder = root.workspaceOrder.filter(id => !localSet[id])
        root._winSig = ""
        root._wsSig = ""
        root.refreshSoon()
    }

    function monitorAtGlobalPoint(x, y) {
        let nearest = null
        let nearestDistance = Infinity
        for (let m of root.monitors) {
            if (!m) continue
            let scale = Math.max(0.1, m.scale || 1)
            let w = m.width / scale
            let h = m.height / scale
            if (x >= m.x && x < m.x + w && y >= m.y && y < m.y + h) return m
            let dx = Math.max(m.x - x, 0, x - (m.x + w))
            let dy = Math.max(m.y - y, 0, y - (m.y + h))
            let distance = dx * dx + dy * dy
            if (distance < nearestDistance) { nearestDistance = distance; nearest = m }
        }
        return nearest
    }

    function globalPointForMonitor(monitorName, point) {
        let m = root.monitors.find(mon => mon && mon.name === monitorName)
        return m ? Qt.point(m.x + point.x, m.y + point.y) : point
    }

    function beginWorkspaceDrag(wsId, sourceMonitor, globalPos) {
        root.workspaceDragId = wsId
        root.workspaceDragSourceMonitor = sourceMonitor
        root.workspaceDragTargetMonitor = sourceMonitor
        root.workspaceDragGlobalPos = globalPos
        root.workspaceDragActive = true
    }

    function updateWorkspaceDrag(globalPos) {
        root.workspaceDragGlobalPos = globalPos
        let monitor = root.monitorAtGlobalPoint(globalPos.x, globalPos.y)
        root.workspaceDragTargetMonitor = monitor ? monitor.name : root.workspaceDragSourceMonitor
    }

    function endWorkspaceDrag() {
        root.workspaceDragActive = false
        root.workspaceDragId = -1
        root.workspaceDragSourceMonitor = ""
        root.workspaceDragTargetMonitor = ""
    }

    function moveWorkspaceToMonitor(wsId, targetMonitor, targetIndex) {
        let sourceMonitor = root.workspaceMonitorName(wsId)
        if (!targetMonitor || !sourceMonitor) return
        if (targetMonitor === sourceMonitor) {
            root.moveWorkspaceOrder(wsId, targetIndex, sourceMonitor)
            return
        }

        if (root.workspaceIdsForMonitor(sourceMonitor).length <= 1)
            root.addWorkspace(sourceMonitor)

        let ws = root.workspaces.find(w => w && w.id === wsId)
        root._dispatch("hl.dsp.workspace.move({workspace = '" + wsId
            + "', monitor = '" + targetMonitor + "'})")
        if ((ws && ws.ispersistent) || root.extraWorkspaces.indexOf(wsId) !== -1)
            root._setPersistent(wsId, true, targetMonitor)

        let moved = root.workspaces.map(w => {
            if (!w || w.id !== wsId) return w
            let copy = {}
            for (let key in w) copy[key] = w[key]
            copy.monitor = targetMonitor
            return copy
        })
        let extraMonitors = {}
        for (let key in root.extraWorkspaceMonitors) extraMonitors[key] = root.extraWorkspaceMonitors[key]
        extraMonitors[wsId] = targetMonitor
        root.extraWorkspaceMonitors = extraMonitors
        root.workspaces = moved
        root._wsSig = ""

        let targetIds = root.workspaceIdsForMonitor(targetMonitor)
        let index = targetIndex < 0 ? targetIds.length - 1 : targetIndex
        root.moveWorkspaceOrder(wsId, index, targetMonitor)
        root.refreshSoon()
    }

    function windowsForWorkspace(wsId) {
        return windows.filter(w => w && w.workspace && w.workspace.id === wsId)
    }
    // Live data for one window; delegates keyed by address re-resolve this on every
    // poll so updates flow through bindings instead of delegate re-creation.
    function windowByAddress(address) {
        return windows.find(w => w && w.address === address) || null
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
    // Stable spatial order for address-keyed delegates. The old pair-dependent
    // row tolerance was not transitive, so differently-sized windows could swap
    // slots between polls even when their centres had barely moved.
    function windowsForWorkspaceSorted(wsId) {
        let arr = windowsForWorkspace(wsId).slice()
        arr.sort((a, b) => {
            let acy = a.at[1] + a.size[1] / 2
            let bcy = b.at[1] + b.size[1] / 2
            if (acy !== bcy) return acy - bcy
            let acx = a.at[0] + a.size[0] / 2
            let bcx = b.at[0] + b.size[0] / 2
            if (acx !== bcx) return acx - bcx
            return String(a.address).localeCompare(String(b.address))
        })
        return arr
    }
    // focusHistoryID=0 is the frontmost/focused client; larger values are older.
    // Keep this source stack during cancel, while a selected target explicitly
    // overrides it in WindowThumb for focus zoom-in.
    function windowStackZ(windowData) {
        if (!windowData) return 0
        let history = Number(windowData.focusHistoryID)
        return Number.isFinite(history) && history >= 0 ? 10000 - history : 0
    }
    // fullscreen field: 0 none, 1 maximized, 2 fullscreen, 3 maximized+fullscreen.
    // States 2 and 3 both cover the full output; maximize-only remains normal.
    function isRealFullscreen(value) { return value === 2 || value === 3 }
    function workspaceHasFullscreen(wsId) {
        return windowsForWorkspace(wsId).some(w => root.isRealFullscreen(w.fullscreen))
    }
    // Name shown on a workspace tile: the window title when something is fullscreen
    // (macOS shows the app name for full-screen / split spaces), else "Workspace N".
    function workspaceLabel(wsId) {
        let ws = windowsForWorkspace(wsId)
        // Real fullscreen → the app's *initial* title (the UI elides it if long).
        let fs = ws.find(w => root.isRealFullscreen(w.fullscreen))
        if (fs) return fs.initialTitle || fs.title || ("Workspace " + wsId)
        // A Split View space made through Mission Control reads like macOS →
        // "A & B", left first. Manual dwindle splits keep the plain name.
        let tiled = ws.filter(w => !w.floating)
        if (tiled.length === 2 && root.isSplitViewWorkspace(wsId)) {
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

    function isSplitViewWorkspace(wsId) { return splitViewWorkspaces.indexOf(wsId) !== -1 }

    // True when `screenName`'s active workspace is a Mission-Control Split View
    // space — the bar and dock bind to this to hide themselves there.
    function splitViewActiveOn(screenName) {
        if (splitViewWorkspaces.length === 0) return false
        let mons = Hyprland.monitors ? Hyprland.monitors.values : []
        for (let i = 0; i < mons.length; i++) {
            let m = mons[i]
            if (m && m.name === screenName)
                return m.activeWorkspace ? isSplitViewWorkspace(m.activeWorkspace.id) : false
        }
        return false
    }

    // Keep the registered Split View spaces honest against every polled snapshot:
    //  - still exactly two tiled windows → stays a split space
    //  - one window left (the other moved away or closed) → the survivor returns
    //    to fullscreen, macOS-style
    //  - a window floated again, a third joined, or the space emptied → back to a
    //    plain workspace (label and bar/dock return to normal)
    function _reconcileSplitViews() {
        let list = root.splitViewWorkspaces
        if (list.length === 0) return
        let keep = []
        for (let wsId of list) {
            let ws = root.windowsForWorkspace(wsId)
            let tiled = ws.filter(w => !w.floating)
            if (ws.length === 2 && tiled.length === 2) {
                root._splitSeenValid[wsId] = true
                keep.push(wsId)
                continue
            }
            if ((root._splitGraceUntil[wsId] || 0) > Date.now()) { keep.push(wsId); continue }
            if (ws.length === 1 && root._splitSeenValid[wsId] === true)
                root.setFullscreen(ws[0].address, true)
            delete root._splitSeenValid[wsId]
        }
        if (keep.length !== list.length) root.splitViewWorkspaces = keep
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
    function _persistentRule(wsId, on, monitorName) {
        let lua = "hl.workspace_rule({workspace = " + wsId + ", persistent = " + (on ? "true" : "false")
        if (on) {
            let m = monitorName || root._focusedMonitorName()
            if (m) lua += ", monitor = '" + m + "'"
        }
        lua += "})"
        return lua
    }
    function _setPersistent(wsId, on, monitorName) {
        _eval(root._persistentRule(wsId, on, monitorName))
    }

    // Move a window to a workspace. follow=false keeps the user where they are
    // (silent); the workspace is created if it doesn't exist yet.
    function moveWindowToWorkspace(address, wsId, follow) {
        _dispatch("hl.dsp.window.move({workspace = '" + wsId + "', follow = "
            + (follow ? "true" : "false") + ", window = 'address:" + address + "'})")
        // If it landed on a tracked-empty space, that space is real now.
        root.extraWorkspaces = root.extraWorkspaces.filter(e => e !== wsId)
        let extraMonitors = {}
        for (let key in root.extraWorkspaceMonitors)
            if (parseInt(key) !== wsId) extraMonitors[key] = root.extraWorkspaceMonitors[key]
        root.extraWorkspaceMonitors = extraMonitors
        refreshSoon()
    }

    // Clicking a window in the overview should both focus it (switching to its
    // space) and raise it to the very top of the stack.
    function focusWindow(address) {
        _eval("hl.dispatch(hl.dsp.focus({window = 'address:" + address
            + "'})); hl.dispatch(hl.dsp.window.bring_to_top({window = 'address:"
            + address + "'}))")
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
        return w ? root.isRealFullscreen(w.fullscreen) : false
    }
    function setFullscreen(address, on) {
        if (root._isFullscreen(address) === on) return
        _dispatch("hl.dsp.window.fullscreen({window = 'address:" + address + "', mode = 'fullscreen'})")
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
            "hyprctl dispatch \"hl.dsp.window.fullscreen({window = 'address:" + fsAddress + "', mode = 'fullscreen'})\"; " +
            "hyprctl dispatch \"hl.dsp.window.float({window = 'address:" + fsAddress + "', state = false})\"; " +
            "hyprctl dispatch \"hl.dsp.window.float({window = 'address:" + draggedAddress + "', state = false})\"; " +
            "hyprctl dispatch \"hl.dsp.window.move({workspace = '" + wsId + "', follow = false, window = 'address:" + draggedAddress + "'})\"; " +
            "sleep 0.12; " +
            "hyprctl dispatch \"hl.dsp.window.move({window = 'address:" + draggedAddress + "', direction = '" + dir + "'})\""
        Quickshell.execDetached(["bash", "-c", seq])
        // Register as a Mission-Control Split View space (see splitViewWorkspaces),
        // with a grace period so reconcile ignores the sequence's transient states.
        root._splitGraceUntil[wsId] = Date.now() + 1500
        if (root.splitViewWorkspaces.indexOf(wsId) === -1)
            root.splitViewWorkspaces = root.splitViewWorkspaces.concat([wsId])
        refreshSoon()
    }

    // + button: add a new workspace. Make it a *persistent* Hyprland workspace so
    // it survives being empty — it then shows in the bar (Hyprland.workspaces) too,
    // not just here, and stays until removed with ×. Does NOT switch to it.
    function addWorkspace(monitorName) {
        let id = root.nextWorkspaceId()
        let monitor = monitorName || root._focusedMonitorName()
        root._setPersistent(id, true, monitor)
        if (root.extraWorkspaces.indexOf(id) === -1)
            root.extraWorkspaces = root.extraWorkspaces.concat([id])  // show instantly
        let extraMonitors = {}
        for (let key in root.extraWorkspaceMonitors) extraMonitors[key] = root.extraWorkspaceMonitors[key]
        extraMonitors[id] = monitor
        root.extraWorkspaceMonitors = extraMonitors
        refreshSoon()
        return id
    }

    // × button: send every window in this space to `intoWsId`, drop its persistence
    // (so the now-empty space disappears), and forget it.
    function deleteWorkspace(wsId, intoWsId) {
        let wins = root.windowsForWorkspace(wsId)
        for (let w of wins)
            _dispatch("hl.dsp.window.move({workspace = '" + intoWsId + "', follow = false, window = 'address:" + w.address + "'})")
        root._setPersistent(wsId, false)
        root.extraWorkspaces = root.extraWorkspaces.filter(e => e !== wsId)
        let extraMonitors = {}
        for (let key in root.extraWorkspaceMonitors)
            if (parseInt(key) !== wsId) extraMonitors[key] = root.extraWorkspaceMonitors[key]
        root.extraWorkspaceMonitors = extraMonitors
        root.workspaceOrder = root.workspaceOrder.filter(e => e !== wsId)
        // Unregister BEFORE the moves land, so reconcile can't catch the space
        // mid-evacuation with one window left and fullscreen it on its way out.
        root.splitViewWorkspaces = root.splitViewWorkspaces.filter(e => e !== wsId)
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
    // Return the revision that is guaranteed to come from a poll started for
    // this open request. If another poll is already in flight, wait for one
    // additional queued poll rather than accepting its possibly stale result.
    function refreshForOpen() {
        let target = root.snapshotRevision + 1
        if (pollProc.running) {
            root._refreshQueued = true
            target += 1
        } else {
            pollProc.running = true
        }
        Hyprland.refreshToplevels()
        return target
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
                    w.at, w.size, w.title, w.fullscreen, w.floating, w.class,
                    w.focusHistoryID]))
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
                root._reconcileSplitViews()
                root.snapshotRevision += 1
            }
        }
        onRunningChanged: {
            if (!running && root._refreshQueued) {
                root._refreshQueued = false
                // Process cannot be restarted from its own completion edge on
                // every Qt version; defer one event-loop turn.
                Qt.callLater(() => pollProc.running = true)
            }
        }
    }

    // React to Hyprland events so the overview tracks moves/closes live. Split
    // View spaces need tracking even with the overview closed (their windows can
    // float / move / close at any time), so keep polling while any is registered.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.open && root.splitViewWorkspaces.length === 0) return
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

    Component.onCompleted: {
        // Restore persisted Split View spaces, then poll once to validate them
        // against reality (stale ids fall away in _reconcileSplitViews).
        let raw = splitStore.text()
        if (raw) {
            try {
                let p = JSON.parse(raw)
                if (Array.isArray(p))
                    root.splitViewWorkspaces = p.filter(n => typeof n === "number" && n >= 1)
            } catch (e) {}
        }
        // Warm the window/workspace snapshot once at startup so the very first
        // overview open has data (and previews) ready before the poll returns.
        root.refresh()
    }
}
