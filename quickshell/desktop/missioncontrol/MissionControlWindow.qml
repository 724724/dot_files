import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../dock" as Dock

// macOS Mission Control: full-screen overlay with a top workspace strip (names that
// expand to live thumbnails on hover) and, below, the active workspace's windows
// spread out as draggable previews. Drag a window onto another space to move it,
// onto another window to tile it (dwindle = split view), or onto the empty strip
// area to give it its own full-screen space.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    property bool show: false
    signal closeRequested

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    // ── Drag state (shared with WindowThumb / WorkspaceTile children) ─────────
    property bool dragActive: false
    property string dragAddress: ""
    property point dragPos: Qt.point(0, 0)
    property int dropWsId: -1            // hovering this workspace tile → move here
    property string dropWindowAddress: "" // hovering this window → tile beside it
    property bool dropNewFullscreen: false // held over the empty strip → new fullscreen space
    property bool dropNewWorkspace: false  // over the + zone → new workspace (plain move)
    property int dropSplitWsId: -1         // over a full-screen tile → split with it
    property string dropSplitSide: "right" // which half the dragged app takes

    readonly property bool dark: ThemeService.isDark

    // ── Workspace-tile reorder drag (separate from the window drag above) ─────
    property bool tileDragActive: false
    property int tileDragId: -1
    property point tileDragPos: Qt.point(0, 0)
    property point tileDragGrabOffset: Qt.point(0, 0)
    property point dragGrabOffset: Qt.point(0, 0)
    property int tileDropIndex: -1       // insertion slot among the other tiles
    property real tileDropX: 0           // scene x of the insertion indicator
    property int hoveredWorkspaceId: -1
    readonly property string monitorName: win.screen ? win.screen.name : ""
    readonly property var workspaceIds: MCService.workspaceIdsForMonitor(win.monitorName)
    readonly property bool workspaceDragTarget: MCService.workspaceDragActive
        && MCService.workspaceDragTargetMonitor === win.monitorName

    readonly property var monitorData: {
        let n = win.screen ? win.screen.name : ""
        return MCService.monitors.find(m => m.name === n) || null
    }
    readonly property int activeWorkspaceId: MCService.activeWorkspaceIdForMonitor(win.screen ? win.screen.name : "")
    readonly property real monLogW: monitorData ? monitorData.width / monitorData.scale : 1920
    readonly property real monLogH: monitorData ? monitorData.height / monitorData.scale : 1200

    // Stage model: a stable list of window *addresses*. hyprctl polls hand
    // MCService.windows a brand-new array every time anything changed (geometry,
    // title, …); binding the Repeater to that directly would destroy and recreate
    // every WindowThumb (and its ScreencopyView) on each poll — the main source of
    // stutter while the overview is open. Instead the Repeater keys off addresses,
    // which only change on real membership/order changes, and each delegate looks
    // its live data up by address so geometry/title updates flow through bindings.
    property var stageModel: []
    readonly property string _stageSig: MCService.windowsForWorkspaceSorted(win.currentStageWsId).map(w => w.address).join(",")
    on_StageSigChanged: stageModel = _stageSig === "" ? [] : _stageSig.split(",")
    Component.onCompleted: stageModel = _stageSig === "" ? [] : _stageSig.split(",")
    // Snapshot of the previous stage while the workspace-switch slide plays.
    property var outgoingModel: []

    property int currentStageWsId: activeWorkspaceId
    property int outgoingStageWsId: -1
    property int workspaceSlideDirection: 1
    property real workspaceSlide: 0
    property bool _workspaceSlideImmediate: false
    readonly property bool workspaceSliding: workspaceSlideMotion.running
    Behavior on workspaceSlide {
        enabled: !win._workspaceSlideImmediate
        AppleSpring {
            id: workspaceSlideMotion
            spring: 13
            epsilon: 0.25
            onRunningChanged: if (!running && Math.abs(win.workspaceSlide) <= 0.25)
                win.outgoingStageWsId = -1
        }
    }

    readonly property int stripHeight: 220
    readonly property int dockReserve: 92
    // Desktop wallpaper — tracks the live awww wallpaper via WallpaperService
    // (re-queried on every open; also follows Nautilus "Set as Background").
    readonly property string wallpaperPath: WallpaperService.current
    readonly property int wallpaperFillMode: WallpaperService.fillMode
    readonly property string wallpaperPaddingColor: WallpaperService.paddingColor
    // Wallpaper sources stay set while the overlay is hidden and are decoded at a
    // bounded sourceSize. Without this, huge originals (e.g. 24MP phone photos)
    // were synchronously re-decoded on the GUI thread at every map, freezing the
    // whole shell for ~300ms before the open animation could even start.
    readonly property string wallpaperUrl: wallpaperPath.length > 1 ? ("file://" + wallpaperPath) : ""
    // Full-screen copy: decode at the *largest* monitor's pixel size (crop/fit/
    // stretch scale correctly from this; Pad shows the original 1:1 so it keeps the
    // full decode). One shared size across screens means one cache entry and ONE
    // decode — Qt's async image reader is a single thread, so per-screen sizes
    // would decode the huge original once per monitor, back to back.
    readonly property size wallpaperSourceSize: {
        if (wallpaperFillMode === Image.Pad) return Qt.size(-1, -1)
        let w = 0, h = 0
        for (let m of MCService.monitors) {
            w = Math.max(w, m.width)
            h = Math.max(h, m.height)
        }
        return (w > 0 && h > 0) ? Qt.size(w, h) : Qt.size(3840, 2400)
    }
    // Thumbnail copies (strip tiles, drag ghosts): a small shared decode is plenty.
    readonly property size wallpaperThumbSourceSize: Qt.size(512, 512)

    // Cache keepers, parked OUTSIDE the visual tree (property objects, never
    // parented to an Item). When this window unmaps, Qt invalidates its scene
    // graph and every Image in it releases its pixmap; the giant wallpaper then
    // fell out of the pixmap cache and was fully re-decoded on the next open,
    // popping in ~0.3s late per monitor. These hold permanent references to the
    // exact url+sourceSize entries the visible Images use, so a remap re-attaches
    // instantly instead of re-decoding.
    property Image _wallpaperKeeper: Image {
        source: win.wallpaperUrl
        sourceSize: win.wallpaperSourceSize
        fillMode: win.wallpaperFillMode
        asynchronous: true
        cache: true
        visible: false
    }
    property Image _wallpaperThumbKeeper: Image {
        source: win.wallpaperUrl
        sourceSize: win.wallpaperThumbSourceSize
        fillMode: win.wallpaperFillMode
        asynchronous: true
        cache: true
        visible: false
    }

    // Stage spread: 0 = windows at their real (overlapping) positions, 1 = spread
    // out into the grid. Animated 0→1 on open and 1→0 on close (the previews then
    // collapse back onto the real windows as the wallpaper fades away).
    property real spread: 1
    property bool _spreadImmediate: false
    readonly property bool spreadAnimating: spreadMotion.running
    Behavior on spread {
        enabled: !win._spreadImmediate
        AppleSpring { id: spreadMotion; spring: 13 }
    }

    // Top workspace strip slide: tucked above the screen, drops down on open and
    // slides back up on close.
    property real stripSlide: 0
    readonly property real stripHiddenY: -(stripBg.height + 24)
    property bool _stripImmediate: false
    Behavior on stripSlide {
        enabled: !win._stripImmediate
        AppleSpring { spring: 13; epsilon: 0.25 }
    }

    onShowChanged: {
        if (show) {
            _resetDrag()
            _resetWorkspaceSlide()
            win._spreadImmediate = true
            win.spread = 0
            win._spreadImmediate = false
            _surfaceVisible = true
            Qt.callLater(() => keyCatcher.forceActiveFocus())
            win._stripImmediate = true
            win.stripSlide = win.stripHiddenY
            win._stripImmediate = false
            Qt.callLater(() => {
                if (!win.show) return
                win.spread = 1
                win.stripSlide = 0
            })
            Dock.DockService.overviewScreen = ""
            Dock.DockService.overviewOpen = true
            MCService.open = true
            WallpaperService.refresh()
        } else {
            Dock.DockService.overviewOpen = false
            MCService.open = false
            _resetDrag()
            win._workspaceSlideImmediate = true
            win.workspaceSlide = 0
            win._workspaceSlideImmediate = false
            win.outgoingStageWsId = -1
            win.stripSlide = win.stripHiddenY
        }
    }

    Connections {
        target: Dock.DockService
        function onLaunchpadCloseRequested() { if (win.show) win.closeRequested() }
    }

    WlrLayershell.namespace: "qs-missioncontrol"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: show ? null : closedRegion
    Region { id: closedRegion }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function iconUrlForClass(cls) {
        if (!cls) return "image://icon/application-x-executable"
        let de = DesktopEntries.heuristicLookup(cls)
        let icon = (de && de.icon) ? de.icon : "application-x-executable"
        return "image://icon/" + icon
    }
    function appNameForClass(cls) {
        if (!cls) return ""
        let de = DesktopEntries.heuristicLookup(cls)
        return (de && de.name) ? de.name : cls
    }
    // Friendly name of the window currently being dragged (for the new-space ghost).
    readonly property string dragAppName: {
        if (!win.dragActive || win.dragAddress === "") return ""
        let w = MCService.windows.find(x => x.address === win.dragAddress)
        return w ? appNameForClass(w.class) : ""
    }

    function _pointInItem(item, sx, sy) {
        if (!item) return false
        let p = item.mapToItem(null, 0, 0)
        return sx >= p.x && sx <= p.x + item.width && sy >= p.y && sy <= p.y + item.height
    }

    function rubberBand(value, lower, upper, dimension) {
        let overshoot = value < lower ? value - lower : (value > upper ? value - upper : 0)
        if (overshoot === 0) return value
        let resisted = (overshoot * dimension * 0.55) / (dimension + 0.55 * Math.abs(overshoot))
        return (value < lower ? lower : upper) + resisted
    }

    function rubberBandPoint(pt) {
        return Qt.point(
            rubberBand(pt.x, 32, win.width - 32, Math.max(1, win.width)),
            rubberBand(pt.y, 32, win.height - 32, Math.max(1, win.height))
        )
    }

    function _resetDrag() {
        win.dragActive = false
        win.dragAddress = ""
        win.dropWsId = -1
        win.dropWindowAddress = ""
        win.dropNewFullscreen = false
        win.dropNewWorkspace = false
        win.dropSplitWsId = -1
        stripHoldTimer.stop()
        win.tileDragActive = false
        win.tileDragId = -1
        win.tileDropIndex = -1
        win.hoveredWorkspaceId = -1
        if (MCService.workspaceDragActive) MCService.endWorkspaceDrag()
    }

    function _workspaceIndex(wsId) {
        let ids = win.workspaceIds
        let idx = ids.indexOf(wsId)
        return idx >= 0 ? idx : wsId
    }

    function _resetWorkspaceSlide() {
        win.currentStageWsId = win.activeWorkspaceId
        win.outgoingStageWsId = -1
        win._workspaceSlideImmediate = true
        win.workspaceSlide = 0
        win._workspaceSlideImmediate = false
    }

    function _slideToWorkspace(wsId) {
        if (wsId === win.currentStageWsId) return
        if (!win.show || !win._surfaceVisible) {
            win.currentStageWsId = wsId
            win.outgoingStageWsId = -1
            win.workspaceSlide = 0
            return
        }
        let oldIdx = _workspaceIndex(win.currentStageWsId)
        let newIdx = _workspaceIndex(wsId)
        win.workspaceSlideDirection = newIdx >= oldIdx ? 1 : -1
        win.outgoingModel = win.stageModel.slice()
        win.outgoingStageWsId = win.currentStageWsId
        win.currentStageWsId = wsId
        win._workspaceSlideImmediate = true
        win.workspaceSlide = win.workspaceSlideDirection * Math.max(1, stageArea.fitW)
        win._workspaceSlideImmediate = false
        Qt.callLater(() => {
            if (win.currentStageWsId === wsId) win.workspaceSlide = 0
        })
    }

    onActiveWorkspaceIdChanged: _slideToWorkspace(activeWorkspaceId)

    // ── Actions invoked by children ───────────────────────────────────────────
    function activateWindow(address) { MCService.focusWindow(address); win.closeRequested() }
    function activateWorkspace(wsId) {
        MCService.focusWorkspace(wsId)
        win.closeRequested()
    }
    // Exit-fullscreen button: turn off fullscreen AND bring that window to the
    // current workspace as a normal (restored) window.
    function requestExitFullscreen(wsId) {
        let fs = MCService.windowsForWorkspace(wsId).find(w => w.fullscreen === 2)
        if (!fs) return
        MCService.setFullscreen(fs.address, false)
        if (wsId !== win.activeWorkspaceId)
            MCService.moveWindowToWorkspace(fs.address, win.activeWorkspaceId, false)
    }
    function requestDeleteWorkspace(wsId) {
        let into = win.activeWorkspaceId
        if (into === wsId) {
            // Deleting the current space: pour its windows into another shown space
            // and switch focus there so the emptied space drops away immediately.
            let other = win.workspaceIds.find(id => id !== wsId)
            if (other === undefined) return
            into = other
            MCService.focusWorkspace(into)
        }
        MCService.deleteWorkspace(wsId, into)
    }

    // ── Workspace-tile reorder ────────────────────────────────────────────────
    function beginTileDrag(wsId, pointerPos, pressPos, tileCenter) {
        win.tileDragActive = true
        win.tileDragId = wsId
        win.tileDropIndex = -1
        win.tileDragGrabOffset = Qt.point(tileCenter.x - pressPos.x, tileCenter.y - pressPos.y)
        win.tileDragPos = win.rubberBandPoint(Qt.point(
            pointerPos.x + win.tileDragGrabOffset.x,
            pointerPos.y + win.tileDragGrabOffset.y
        ))
        MCService.beginWorkspaceDrag(wsId, win.monitorName,
            MCService.globalPointForMonitor(win.monitorName, pointerPos))
    }
    function updateTileDrag(scenePos) {
        win.tileDragPos = win.rubberBandPoint(Qt.point(
            scenePos.x + win.tileDragGrabOffset.x,
            scenePos.y + win.tileDragGrabOffset.y
        ))
        MCService.updateWorkspaceDrag(MCService.globalPointForMonitor(win.monitorName, scenePos))
        if (MCService.workspaceDragTargetMonitor !== win.monitorName) {
            win.tileDropIndex = -1
            return
        }
        // Insertion slot = how many *other* tiles have their centre left of the
        // cursor; also remember the x where the indicator should sit.
        let idx = 0
        let dropX = -1
        let lastRight = 0
        for (let i = 0; i < wsRepeater.count; i++) {
            let it = wsRepeater.itemAt(i)
            if (!it || it.wsId === win.tileDragId) continue
            let left = it.mapToItem(null, 0, 0).x
            let center = left + it.width / 2
            if (center < scenePos.x) { idx++; lastRight = left + it.width }
            else if (dropX < 0) { dropX = left - 10 }
        }
        win.tileDropIndex = idx
        win.tileDropX = dropX >= 0 ? dropX : (lastRight + 10)
    }
    function endTileDrag() {
        let targetMonitor = MCService.workspaceDragTargetMonitor
        if (win.tileDragId >= 1 && targetMonitor !== "") {
            if (targetMonitor === win.monitorName && win.tileDropIndex >= 0)
                MCService.moveWorkspaceOrder(win.tileDragId, win.tileDropIndex, win.monitorName)
            else if (targetMonitor !== win.monitorName)
                MCService.moveWorkspaceToMonitor(win.tileDragId, targetMonitor, -1)
        }
        MCService.endWorkspaceDrag()
        win.tileDragActive = false
        win.tileDragId = -1
        win.tileDropIndex = -1
    }

    // ── Drag coordination ─────────────────────────────────────────────────────
    function beginWindowDrag(address, pointerPos, pressPos, thumbCenter) {
        win.dragActive = true
        win.dragAddress = address
        win.dropWsId = -1
        win.dropWindowAddress = ""
        win.dropNewFullscreen = false
        win.dropNewWorkspace = false
        win.dropSplitWsId = -1
        win.dragGrabOffset = Qt.point(thumbCenter.x - pressPos.x, thumbCenter.y - pressPos.y)
        win.dragPos = win.rubberBandPoint(Qt.point(
            pointerPos.x + win.dragGrabOffset.x,
            pointerPos.y + win.dragGrabOffset.y
        ))
        stripHoldTimer.stop()
    }
    function updateWindowDrag(scenePos) {
        win.dragPos = win.rubberBandPoint(Qt.point(
            scenePos.x + win.dragGrabOffset.x,
            scenePos.y + win.dragGrabOffset.y
        ))
        win.dropWsId = -1
        win.dropWindowAddress = ""
        win.dropSplitWsId = -1

        if (_pointInItem(topBand, scenePos.x, scenePos.y)) {
            // Over the + zone → a plain new workspace the app is moved into.
            if (_pointInItem(addWsGhost, scenePos.x, scenePos.y)) {
                win.dropNewWorkspace = true
                win.dropNewFullscreen = false
                stripHoldTimer.stop()
                return
            }
            win.dropNewWorkspace = false
            // Over a workspace tile → move into it, or split with a full-screen one.
            for (let i = 0; i < wsRepeater.count; i++) {
                let it = wsRepeater.itemAt(i)
                if (it && _pointInItem(it, scenePos.x, scenePos.y)) {
                    stripHoldTimer.stop()
                    win.dropNewFullscreen = false
                    let dragged = MCService.windows.find(w => w.address === win.dragAddress)
                    let onOwnWs = dragged && dragged.workspace && dragged.workspace.id === it.wsId
                    if (MCService.workspaceHasFullscreen(it.wsId) && !onOwnWs) {
                        // Split with the full-screen app; side from the cursor half.
                        let cx = it.mapToItem(null, it.width / 2, 0).x
                        win.dropSplitSide = scenePos.x < cx ? "left" : "right"
                        win.dropSplitWsId = it.wsId
                        win.dropWsId = -1
                    } else {
                        win.dropWsId = it.wsId
                        win.dropSplitWsId = -1
                    }
                    return
                }
            }
            // Keep the fullscreen ghost alive while hovering it (once revealed).
            if (win.dropNewFullscreen && _pointInItem(newWsGhost, scenePos.x, scenePos.y)) return
            // Empty strip area → hold briefly, then reveal the "new full-screen
            // space" ghost (with the app's name).
            if (!win.dropNewFullscreen && !stripHoldTimer.running) stripHoldTimer.restart()
            return
        }

        // Off the strip → cancel the hold / strip drops.
        stripHoldTimer.stop()
        win.dropNewFullscreen = false
        win.dropNewWorkspace = false

        // Over another window in the stage → tile beside it (split view).
        for (let j = 0; j < stageRepeater.count; j++) {
            let w = stageRepeater.itemAt(j)
            if (w && w.address !== win.dragAddress && _pointInItem(w, scenePos.x, scenePos.y)) {
                win.dropWindowAddress = w.address
                return
            }
        }
    }
    // Dwell before the "new full-screen space" ghost appears (macOS-style).
    Timer { id: stripHoldTimer; interval: 336; onTriggered: win.dropNewFullscreen = true }

    function endWindowDrag() {
        stripHoldTimer.stop()
        let addr = win.dragAddress
        if (addr === "") { _resetDrag(); return }

        if (win.dropSplitWsId >= 1) {
            let fs = MCService.windowsForWorkspace(win.dropSplitWsId).find(w => w.fullscreen === 2)
            if (fs) MCService.splitInto(fs.address, addr, win.dropSplitWsId, win.dropSplitSide)
        } else if (win.dropNewFullscreen) {
            MCService.moveWindowToNewFullscreen(addr)
        } else if (win.dropNewWorkspace) {
            MCService.moveWindowToNewWorkspace(addr)
        } else if (win.dropWsId >= 1) {
            MCService.moveWindowToWorkspace(addr, win.dropWsId, false)
        } else if (win.dropWindowAddress !== "") {
            let t = MCService.windows.find(w => w.address === win.dropWindowAddress)
            if (t && t.workspace) MCService.moveWindowToWorkspace(addr, t.workspace.id, false)
        }
        _resetDrag()
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    // Wallpaper stays below the workspace strip so Hyprland can blur the strip
    // against the real compositor background instead of an in-layer image. Its
    // top edge tracks the strip's actual bottom edge (not the full stripHeight
    // hover zone) so real windows near the top can't peek through the gap.
    Item {
        id: wallpaper
        readonly property real stripBottom: Math.max(0, stripBg.height - 1 + win.stripSlide)
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: stripBottom
        }
        clip: true
        opacity: win.show ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 18 } }

        Rectangle {
            x: 0
            y: -wallpaper.stripBottom
            width: win.width
            height: win.height
            color: win.wallpaperPaddingColor
        }

        Image {
            x: 0
            y: -wallpaper.stripBottom
            width: win.width
            height: win.height
            source: win.wallpaperUrl
            sourceSize: win.wallpaperSourceSize
            fillMode: win.wallpaperFillMode
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            cache: true
            asynchronous: true
        }

        // Empty-area click dismisses.
        MouseArea { anchors.fill: parent; enabled: win.show; onPressed: win.closeRequested() }
    }

    Item {
        id: content
        anchors.fill: parent
        // Fade the whole overview in/out (open spread stays; close just dissolves).
        opacity: win.show ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 18 } }
        onOpacityChanged: if (!win.show && opacity <= 0.002) win._surfaceVisible = false

        // Escape to close (window takes keyboard focus on open).
        Item {
            id: keyCatcher
            focus: true
            Keys.onEscapePressed: win.closeRequested()
        }

        // ── Top workspace strip ───────────────────────────────────────────────
        Item {
            id: topBand
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: win.stripHeight        // generous hover zone at the top
            readonly property bool expanded: stripHover.hovered || win.dragActive
                || win.tileDragActive || win.workspaceDragTarget
            readonly property int workspaceCount: Math.max(1, win.workspaceIds.length)
            readonly property real stripSideMargin: 44
            readonly property real addReserve: 0
            readonly property real wsDefaultThumbW: 176
            readonly property real wsDefaultThumbH: wsDefaultThumbW * (win.monLogH / win.monLogW)
            readonly property real wsNameH: 24
            readonly property real wsAvailableW: Math.max(1, width - stripSideMargin * 2 - addReserve)
            readonly property real wsSpacing: workspaceCount <= 1 ? 0
                : Math.max(0, Math.min(20, (wsAvailableW - workspaceCount * 72) / Math.max(1, workspaceCount - 1)))
            readonly property real wsRowW: Math.min(wsAvailableW, workspaceCount * wsDefaultThumbW + wsSpacing * (workspaceCount - 1))
            readonly property real wsTileBudget: Math.max(0.1, wsRowW - wsSpacing * (workspaceCount - 1))
            readonly property real wsBaseThumbW: Math.max(0.1, Math.min(wsDefaultThumbW, wsTileBudget / workspaceCount))
            readonly property bool wsCompressed: wsBaseThumbW < wsDefaultThumbW - 0.5
            readonly property real wsMinCompressedThumbW: Math.max(0.1, Math.min(90, wsBaseThumbW * 0.72))
            readonly property real wsHoverThumbW: {
                if (!wsCompressed || workspaceCount <= 1) return wsBaseThumbW
                let desired = wsDefaultThumbW
                let fitMax = wsTileBudget - wsMinCompressedThumbW * (workspaceCount - 1)
                return Math.max(wsBaseThumbW, Math.min(desired, fitMax))
            }
            readonly property real wsCompressedThumbW: (!wsCompressed || workspaceCount <= 1) ? wsBaseThumbW
                : Math.max(0.1, (wsTileBudget - wsHoverThumbW) / (workspaceCount - 1))
            function workspaceThumbW(wsId) {
                if (!expanded || !wsCompressed || win.hoveredWorkspaceId < 1 || win.tileDragActive) return wsBaseThumbW
                return wsId === win.hoveredWorkspaceId ? wsHoverThumbW : wsCompressedThumbW
            }
            transform: Translate { y: win.stripSlide }

            HoverHandler { id: stripHover }

            // Translucent workspace strip. Overscans by 1px so there is no
            // visible edge gap on the top/left/right of the layer surface.
            Rectangle {
                id: stripBg
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: -1; leftMargin: -1; rightMargin: -1 }
                height: (topBand.expanded ? (topBand.wsDefaultThumbH + 6 + topBand.wsNameH + 28) : (topBand.wsNameH + 28)) + 1
                color: ThemeService.surface
                border.color: win.workspaceDragTarget && !win.tileDragActive
                    ? "#0A84FF" : ThemeService.surfaceStroke
                border.width: win.workspaceDragTarget && !win.tileDragActive ? 2 : 1
                Behavior on height { AppleSpring { spring: 13; epsilon: 0.25 } }
            }

            Row {
                id: wsRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 0
                anchors.top: parent.top
                anchors.topMargin: 14
                spacing: topBand.wsSpacing

                Repeater {
                    id: wsRepeater
                    model: win.workspaceIds
                    delegate: WorkspaceTile {
                        required property var modelData
                        wsId: modelData
                        monitorData: win.monitorData
                        activeWsId: win.activeWorkspaceId
                        expanded: topBand.expanded
                        layoutThumbW: topBand.workspaceThumbW(modelData)
                        overview: win
                    }
                }
            }

            readonly property bool windowDragging: win.dragActive && win.dragAddress !== ""

            // + add workspace — pinned to the far right, click to add an empty space.
            // While a window is dragged onto its zone it becomes the ghost below.
            Rectangle {
                id: addBtn
                visible: topBand.expanded && !win.dropNewWorkspace
                anchors.right: stripBg.right
                anchors.rightMargin: 44
                anchors.verticalCenter: stripBg.verticalCenter
                width: 46; height: 46; radius: 23
                color: addHover.hovered ? ThemeService.controlBg : "transparent"
                scale: addMa.pressed ? ThemeService.pressScale : 1.0
                Behavior on scale { AppleSpring { spring: 18 } }
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: win.dark ? "#d0d0d2" : "#3a3a3c"
                    font.family: "SF Pro Display"
                    font.pixelSize: 34
                    font.weight: Font.Light
                }
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    id: addMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: MCService.addWorkspace(win.monitorName)
                }
            }

            // + drop zone / ghost: a thumbnail-sized "new workspace" box at the far
            // right. Its geometry is the drop target (hit-tested in updateWindowDrag);
            // it only becomes visible once a dragged window is over it. Dropping here
            // makes a new workspace and moves the app into it (not full-screen).
            Item {
                id: addWsGhost
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.right: stripBg.right
                anchors.rightMargin: 20
                width: Math.max(44, Math.min(168, topBand.wsBaseThumbW))
                height: width * (win.monLogH / win.monLogW)
                z: 6
                visible: win.dropNewWorkspace

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    clip: true
                    color: ThemeService.surfaceStrong
                    border.color: "#0A84FF"
                    border.width: 3
                    Rectangle {
                        anchors.fill: parent
                        color: win.wallpaperPaddingColor
                        opacity: 0.45
                    }
                    Image {
                        anchors.fill: parent
                        source: win.wallpaperUrl
                        sourceSize: win.wallpaperThumbSourceSize
                        fillMode: win.wallpaperFillMode
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        opacity: 0.45
                        cache: true
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: "#0A84FF"
                        font.family: "SF Pro Display"
                        font.pixelSize: 44
                        font.weight: Font.Light
                    }
                }
            }

            // New-full-screen-space ghost: after a short dwell over the empty strip
            // area while dragging a window, a thumbnail-sized box with a + and the
            // app's name appears just after the last space. Dropping here puts the
            // app full-screen on a brand-new space.
            Item {
                id: newWsGhost
                visible: win.dropNewFullscreen
                x: Math.max(20, Math.min(wsRow.x + wsRow.implicitWidth + 20, topBand.width - width - 20))
                y: 14
                width: Math.max(44, Math.min(168, topBand.wsBaseThumbW))
                height: newWsBox.height + 22
                z: 6

                Rectangle {
                    id: newWsBox
                    width: parent.width
                    height: parent.width * (win.monLogH / win.monLogW)
                    radius: 8
                    clip: true
                    color: ThemeService.surfaceStrong
                    border.color: "#0A84FF"
                    border.width: 3
                    Rectangle {
                        anchors.fill: parent
                        color: win.wallpaperPaddingColor
                        opacity: 0.45
                    }
                    Image {
                        anchors.fill: parent
                        source: win.wallpaperUrl
                        sourceSize: win.wallpaperThumbSourceSize
                        fillMode: win.wallpaperFillMode
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        opacity: 0.45
                        cache: true
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: "#0A84FF"
                        font.family: "SF Pro Display"
                        font.pixelSize: 44
                        font.weight: Font.Light
                    }
                }
                Text {
                    anchors.top: newWsBox.bottom
                    anchors.topMargin: 4
                    anchors.horizontalCenter: newWsBox.horizontalCenter
                    width: newWsBox.width + 30
                    text: win.dragAppName
                    color: win.dark ? "#f0f0f2" : "#1c1c1e"
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            // Insertion indicator while reordering tiles (topBand sits at scene 0,0,
            // so the scene-space drop x maps straight to a local x here).
            Rectangle {
                visible: win.tileDragActive
                    && MCService.workspaceDragTargetMonitor === win.monitorName
                x: win.tileDropX
                y: 8
                width: 3
                height: stripBg.height - 16
                radius: 1.5
                color: "#0A84FF"
            }
        }

        // ── Stage: active workspace windows ───────────────────────────────────
        Item {
            id: stageArea
            anchors {
                top: topBand.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 24
                leftMargin: 80
                rightMargin: 80
                bottomMargin: win.dockReserve + 24
            }

            readonly property real fitW: Math.min(width, height * (win.monLogW / win.monLogH))
            readonly property real fitH: fitW * (win.monLogH / win.monLogW)
            readonly property real stageScale: win.monLogW > 0 ? fitW / win.monLogW : 1

            Item {
                id: stageViewport
                width: stageArea.fitW
                height: stageArea.fitH
                anchors.centerIn: parent
                clip: true

                Item {
                    id: outgoingStage
                    width: parent.width
                    height: parent.height
                    x: win.workspaceSlide - win.workspaceSlideDirection * width
                    visible: win.outgoingStageWsId >= 1
                    clip: false

                    Repeater {
                        id: outgoingStageRepeater
                        model: win.outgoingStageWsId >= 1 ? win.outgoingModel : []
                        delegate: WindowThumb {
                            required property var modelData
                            required property int index
                            windowData: MCService.windowByAddress(modelData)
                            draggable: false
                            live: false
                            overview: null
                            iconUrl: win.iconUrlForClass(windowData ? windowData.class : "")
                            monitorData: win.monitorData
                            mscale: stageArea.stageScale
                            spread: 1

                            readonly property int total: outgoingStageRepeater.count
                            readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(total)))
                            readonly property int rows: Math.max(1, Math.ceil(total / cols))
                            readonly property real pad: 18
                            readonly property real cellW: outgoingStage.width / cols
                            readonly property real cellH: outgoingStage.height / rows
                            slotX: (index % cols) * cellW + pad
                            slotY: Math.floor(index / cols) * cellH + pad
                            slotW: cellW - pad * 2
                            slotH: cellH - pad * 2
                        }
                    }
                }

                Item {
                    id: stage
                    width: parent.width
                    height: parent.height
                    x: win.workspaceSlide
                    clip: false

                    Repeater {
                        id: stageRepeater
                        model: win.stageModel
                        delegate: WindowThumb {
                            required property var modelData
                            required property int index
                            windowData: MCService.windowByAddress(modelData)
                            draggable: true
                            live: true
                            overview: win
                            iconUrl: win.iconUrlForClass(windowData ? windowData.class : "")
                            // Geometry inputs let the thumb start at the window's real
                            // position and fly out to its grid slot as `spread` animates.
                            monitorData: win.monitorData
                            mscale: stageArea.stageScale
                            spread: win.spread

                            // Spread windows into a grid so nothing overlaps; the cells
                            // (and previews) shrink as the window count grows so they all
                            // stay visible.
                            readonly property int total: stageRepeater.count
                            readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(total)))
                            readonly property int rows: Math.max(1, Math.ceil(total / cols))
                            readonly property real pad: 18
                            readonly property real cellW: stage.width / cols
                            readonly property real cellH: stage.height / rows
                            slotX: (index % cols) * cellW + pad
                            slotY: Math.floor(index / cols) * cellH + pad
                            slotW: cellW - pad * 2
                            slotH: cellH - pad * 2
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: stageRepeater.count === 0
                    width: noWinText.implicitWidth + 34
                    height: noWinText.implicitHeight + 18
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.9)
                    Text {
                        id: noWinText
                        anchors.centerIn: parent
                        text: "No Available Windows"
                        color: "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // ── Floating drag proxy ───────────────────────────────────────────────────
    Item {
        id: dragProxy
        visible: win.dragActive && dragData !== null
        z: 4000
        readonly property var dragData: win.dragActive
            ? MCService.windows.find(w => w.address === win.dragAddress) : null
        readonly property var dragToplevel: {
            if (!win.dragActive) return null
            let tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
            for (let i = 0; i < tops.length; i++) {
                let t = tops[i]
                let o = (t && t.lastIpcObject) ? t.lastIpcObject : null
                if (o && o.address === win.dragAddress && t.wayland) return t.wayland
            }
            return null
        }
        readonly property real dragAspect: (dragData && dragData.size[1] > 0)
            ? dragData.size[0] / dragData.size[1] : 1.5
        width: dragData ? 260 : 100
        height: dragData ? 260 / dragAspect : 100
        x: win.dragPos.x - width / 2
        y: win.dragPos.y - height / 2
        opacity: 0.9
        scale: 1.04

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.3)
            border.color: "#0A84FF"
            border.width: 2
            clip: true
            ScreencopyView {
                anchors.fill: parent
                captureSource: dragProxy.dragToplevel
                live: true
                paintCursor: false
            }
        }
    }

    // ── Floating proxy while reordering workspace tiles ───────────────────────
    Item {
        id: tileProxy
        visible: win.tileDragActive
        z: 4000
        readonly property real cardH: 150 * (win.monLogH / win.monLogW)
        width: 150
        height: cardH + 20
        x: win.tileDragPos.x - width / 2
        y: win.tileDragPos.y - height / 2
        opacity: 0.92

        Rectangle {
            width: parent.width
            height: tileProxy.cardH
            radius: 8
            clip: true
            color: ThemeService.surfaceStrong
            border.color: "#0A84FF"
            border.width: 2
            Rectangle {
                anchors.fill: parent
                color: win.wallpaperPaddingColor
            }
            Image {
                anchors.fill: parent
                source: win.wallpaperUrl
                sourceSize: win.wallpaperThumbSourceSize
                fillMode: win.wallpaperFillMode
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignVCenter
                cache: true
                asynchronous: true
            }
        }
        Text {
            anchors.top: parent.top
            anchors.topMargin: tileProxy.cardH + 3
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.tileDragId >= 1 ? MCService.workspaceLabel(win.tileDragId) : ""
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 12
            elide: Text.ElideRight
            width: tileProxy.width + 30
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
