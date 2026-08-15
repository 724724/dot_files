import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../dock" as Dock
import "SpatialLayout.js" as SpatialLayout

// macOS Mission Control: full-screen overlay with a top workspace strip (names that
// expand to live thumbnails on hover) and, below, the active workspace's windows
// spread out as draggable previews. Drag a window onto another space to move it,
// onto another window to tile it (dwindle = split view), or onto the empty strip
// area to give it its own full-screen space.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    property bool active: false
    property real overviewProgress: 0
    property real spatialProgress: overviewProgress
    property bool transitionRunning: false
    property bool overviewInteractive: false
    property bool reducedMotion: false
    property string exitKind: ""
    property string selectedAddress: ""
    property bool holdBackdrop: false

    signal cancelRequested
    signal windowRequested(string address)
    signal workspaceRequested(int wsId)

    // Keep the transparent, input-empty layer surface mapped. shell.qml creates
    // this before DockWindow, so the Dock remains above it without an unmap/remap
    // transaction on every overview open. Rendering and capture stay gated below.
    visible: true
    readonly property bool captureEnabled: win.active

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
    property var outgoingLayout: ({})
    property var entryStack: ({})
    readonly property var stageLayout: SpatialLayout.pack(
        win.stageModel, MCService.windows, win.monitorData,
        Math.max(1, stageArea.width), Math.max(1, stageArea.height), 22)

    property int currentStageWsId: activeWorkspaceId
    property int outgoingStageWsId: -1
    property int workspaceSlideDirection: 1
    property real workspaceSlide: 0
    property bool _workspaceSlideImmediate: false
    readonly property bool workspaceSliding: workspaceSlideMotion.running
    Behavior on workspaceSlide {
        enabled: !win._workspaceSlideImmediate && !win.reducedMotion
        NumberAnimation {
            id: workspaceSlideMotion
            duration: 125
            easing.type: Easing.OutCubic
            onRunningChanged: if (!running && Math.abs(win.workspaceSlide) <= 0.25)
                win.outgoingStageWsId = -1
        }
    }

    readonly property int stripHeight: 220
    // Match DockWindow's per-monitor size mapping so overview content clears the
    // actual Dock thickness at every persisted size level and edge.
    readonly property real dockShortSide: Math.max(1, Math.min(width, height))
    readonly property real dockMinIcon: Math.max(24,
        Math.min(32, dockShortSide * 0.022))
    readonly property real dockMaxIcon: Math.max(48,
        Math.min(66, dockShortSide * 0.045))
    readonly property real dockCurrentIcon: dockMinIcon
        + Dock.DockService.dockSizeLevel * (dockMaxIcon - dockMinIcon)
    readonly property int dockReserve: Math.ceil(18 + 68 * dockCurrentIcon / 42)
    // Desktop wallpaper — tracks the live awww wallpaper via WallpaperService
    // (re-queried on every open; also follows Nautilus "Set as Background").
    readonly property string wallpaperPath: WallpaperService.current
    readonly property int wallpaperFillMode: WallpaperService.fillMode
    readonly property string wallpaperPaddingColor: WallpaperService.paddingColor
    // Fit/pad don't cover the full screen, so the uncovered margins need an
    // opaque plane behind them (see the backdrop below).
    readonly property bool wallpaperNeedsPadding:
        wallpaperFillMode === Image.PreserveAspectFit || wallpaperFillMode === Image.Pad
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

    // The strip and all window rects derive from the same progress transaction.
    // Reduced Motion keeps the overview geometry static and cross-fades instead.
    // A constant off-screen endpoint prevents the expanding strip's live height
    // from briefly moving the hidden target into view on the first frame.
    readonly property real stripHiddenY: -win.stripHeight
    readonly property real stripSlide: win.reducedMotion ? 0
        : win.stripHiddenY * (1 - win.spatialProgress)
    function _captureEntryStack() {
        let stack = ({})
        for (let windowData of MCService.windows)
            if (windowData && windowData.address)
                stack[windowData.address] = MCService.windowStackZ(windowData)
        win.entryStack = stack
    }

    onActiveChanged: {
        if (active) {
            // Refresh before mapping the overlay. The current cached wallpaper
            // remains available immediately while awww/gsettings reconcile.
            WallpaperService.refresh()
            _resetDrag()
            _resetWorkspaceSlide()
            _captureEntryStack()
            Qt.callLater(() => {
                if (!win.active) return
                keyCatcher.forceActiveFocus()
            })
        } else {
            _resetDrag()
            win._workspaceSlideImmediate = true
            win.workspaceSlide = 0
            win._workspaceSlideImmediate = false
            win.outgoingStageWsId = -1
        }
    }

    Connections {
        target: Dock.DockService
        function onLaunchpadCloseRequested() { if (win.active) win.cancelRequested() }
    }

    WlrLayershell.namespace: "qs-missioncontrol"
    // Overlay keeps Mission Control above fullscreen clients and the Top-layer
    // menu bar. Its compositor order is intentionally higher than the Dock's:
    // Hyprland draws that surface first, then the real Dock above it.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.active
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: active ? null : closedRegion
    Region { id: closedRegion }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function appNameForClass(cls) {
        if (!cls) return ""
        if (cls.toLowerCase() === "ida" || cls.toLowerCase() === "ida64") return "IDA"
        if (cls.toLowerCase() === "arduino ide") return "Arduino IDE"
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
        // Keep the already-captured stage intact through close. Replacing it after
        // the selected workspace becomes active creates fresh ScreencopyViews with
        // no frame yet and discards the final live thumbnail.
        if (!win.active) return
        let oldIdx = _workspaceIndex(win.currentStageWsId)
        let newIdx = _workspaceIndex(wsId)
        win.workspaceSlideDirection = newIdx >= oldIdx ? 1 : -1
        win.outgoingModel = win.stageModel.slice()
        win.outgoingLayout = win.stageLayout
        win.outgoingStageWsId = win.currentStageWsId
        win.currentStageWsId = wsId
        win._workspaceSlideImmediate = true
        win.workspaceSlide = win.workspaceSlideDirection * Math.max(1, win.width)
        win._workspaceSlideImmediate = false
        Qt.callLater(() => {
            if (win.currentStageWsId === wsId) win.workspaceSlide = 0
        })
    }

    // External workspace changes can still slide while the overview is open.
    // A tile selection commits immediately but keeps the captured source stage
    // stable during exit; replacing it mid-close causes a blank/new-frame flash.
    onActiveWorkspaceIdChanged: {
        if (win.active && win.exitKind === "")
            _slideToWorkspace(activeWorkspaceId)
    }
    onExitKindChanged: {
        if (win.active && win.exitKind === ""
                && win.currentStageWsId !== win.activeWorkspaceId)
            _slideToWorkspace(win.activeWorkspaceId)
    }

    // ── Actions invoked by children ───────────────────────────────────────────
    function activateWindow(address) { win.windowRequested(address) }
    function activateWorkspace(wsId) { win.workspaceRequested(wsId) }
    // Exit-fullscreen button: turn off fullscreen AND bring that window to the
    // current workspace as a normal (restored) window.
    function requestExitFullscreen(wsId) {
        let fs = MCService.windowsForWorkspace(wsId).find(
            w => MCService.isRealFullscreen(w.fullscreen))
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
            let fs = MCService.windowsForWorkspace(win.dropSplitWsId).find(
                w => MCService.isRealFullscreen(w.fullscreen))
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
        // Share the exact physical-pixel-snapped edge with the strip. Using a
        // separately rounded clip edge produced a broken half-pixel seam at
        // fractional output scales such as 1.5x.
        readonly property real stripBottom: Math.max(0,
            topBand.renderedStripExtent + topBand.renderedStripSlide)
        // Never paint the padding-color placeholder while the asynchronous
        // wallpaper image is still attaching to the remapped scene graph. Until
        // it is ready the transparent overlay leaves the identical live awww
        // desktop underneath visible, preserving frame-to-frame continuity.
        readonly property bool imageReady: wallpaperImage.status === Image.Ready
        readonly property bool colorOnly: win.wallpaperUrl === ""
            || wallpaperImage.status === Image.Error
        readonly property real coverOpacity: !win.active ? 0
            : (win.holdBackdrop ? 1 : win.overviewProgress)
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: stripBottom
        }
        clip: true
        // Entry keeps its capture-friendly progressive reveal. Once closing
        // starts, hold the background fully opaque so only the live proxies are
        // seen returning to their source rects; the real windows appear exactly
        // when the overlay reaches its endpoint.
        opacity: (imageReady || colorOnly || win.holdBackdrop)
            ? coverOpacity : 0

        Rectangle {
            x: 0
            y: -wallpaper.stripBottom
            width: win.width
            height: win.height
            color: win.wallpaperPaddingColor
            // Crop/stretch cover the whole screen, so no plane is needed and
            // leaving it out keeps a late texture frame transparent rather than
            // flashing blue. Fit/pad genuinely leave margins though, and the
            // overview sits ABOVE the live windows — without an opaque plane
            // those margins show the real windows through the overview.
            visible: wallpaper.colorOnly || win.wallpaperNeedsPadding
                || (win.holdBackdrop && !wallpaper.imageReady)
        }

        Image {
            id: wallpaperImage
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
            retainWhileLoading: true
        }

        // A cheap dim plane gives the live previews depth without a full-screen
        // shader blur. It follows the same progress as the spatial transition.
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.12 * win.overviewProgress
        }

        // Empty-area click dismisses.
        MouseArea {
            anchors.fill: parent
            enabled: win.active
            onPressed: win.cancelRequested()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        visible: win.active
        // Window previews remain fully opaque through the complete reverse
        // interpolation. They disappear only after reaching their source rects.
        opacity: 1

        // Escape to close (window takes keyboard focus on open).
        Item {
            id: keyCatcher
            focus: true
            Keys.onEscapePressed: win.cancelRequested()
        }

        // ── Top workspace strip ───────────────────────────────────────────────
        Item {
            id: topBand
            z: 3000
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: win.stripHeight        // generous hover zone at the top
            readonly property bool expanded: win.active
            readonly property int workspaceCount: Math.max(1, win.workspaceIds.length)
            readonly property real stripSideMargin: 44
            readonly property real addReserve: 0
            readonly property real wsDefaultThumbW: 176
            readonly property real wsDefaultThumbH: wsDefaultThumbW * (win.monLogH / win.monLogW)
            readonly property real wsNameH: 24
            readonly property real deviceScale: Math.max(1,
                Number(win.devicePixelRatio) || 1)
            readonly property real physicalPixel: 1 / deviceScale
            readonly property real expandedStripExtent:
                wsDefaultThumbH + 6 + wsNameH + 28
            readonly property real collapsedStripExtent: wsNameH + 28
            property real stripExtent: expanded
                ? expandedStripExtent : collapsedStripExtent
            readonly property real renderedStripExtent:
                Math.round(stripExtent * deviceScale) / deviceScale
            readonly property real renderedStripSlide:
                Math.round(win.stripSlide * deviceScale) / deviceScale
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
            Behavior on stripExtent {
                enabled: !win.reducedMotion
                AppleSpring { spring: 3.4; epsilon: 0.25 }
            }

            transform: Translate { y: topBand.renderedStripSlide }

            HoverHandler { id: stripHover }

            // Fully opaque workspace strip. Overscans by 1px so neither the
            // desktop nor its text can leak through at the top/side edges.
            Rectangle {
                id: stripBg
                x: -topBand.physicalPixel
                y: -topBand.physicalPixel
                width: parent.width + 2 * topBand.physicalPixel
                height: topBand.renderedStripExtent + topBand.physicalPixel
                color: ThemeService.surfaceOpaque
                border.width: 0
            }

            // One physical pixel, aligned to the same snapped boundary as the
            // wallpaper clip. A logical 1px Rectangle becomes 1.5 physical
            // pixels on this display and aliases across two rows.
            Rectangle {
                id: stripSeparator
                x: 0
                y: topBand.renderedStripExtent - height
                width: parent.width
                height: (win.workspaceDragTarget && !win.tileDragActive ? 2 : 1)
                    * topBand.physicalPixel
                color: win.workspaceDragTarget && !win.tileDragActive
                    ? "#0A84FF" : ThemeService.surfaceStroke
                antialiasing: false
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
                        // Defer one-shot Spaces captures until the primary live
                        // stage has settled, avoiding an Intel iGPU burst on open.
                        captureEnabled: win.captureEnabled && win.overviewInteractive
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
                Behavior on scale { AppleSpring { spring: 4.4 } }
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
                    enabled: win.overviewInteractive
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
                height: Math.max(0, topBand.renderedStripExtent - 16)
                radius: 1.5
                color: "#0A84FF"
            }
        }

        // ── Stage: active workspace windows ───────────────────────────────────
        // This is only the safe TARGET rectangle. Delegates live in the full-root
        // stage below, so progress=0 is the exact compositor-local source rect —
        // no inset scale, offset or clip can create a first/last-frame jump.
        Item {
            id: stageArea
            anchors {
                top: topBand.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 24
                leftMargin: 80 + (Dock.DockService.dockEdge === "left" ? win.dockReserve : 0)
                rightMargin: 80 + (Dock.DockService.dockEdge === "right" ? win.dockReserve : 0)
                bottomMargin: 24 + (Dock.DockService.dockEdge === "bottom" ? win.dockReserve : 0)
            }
        }

        Item {
            id: outgoingStage
            anchors.fill: parent
            x: win.workspaceSlide - win.workspaceSlideDirection * width
            visible: win.outgoingStageWsId >= 1

            Repeater {
                id: outgoingStageRepeater
                model: win.outgoingStageWsId >= 1 ? win.outgoingModel : []
                delegate: WindowThumb {
                    required property var modelData
                    windowData: MCService.windowByAddress(modelData)
                    readonly property var packedRect: win.outgoingLayout[modelData] || null
                    draggable: false
                    live: false
                    placeholderVisible: false
                    captureEnabled: win.captureEnabled
                    overview: null
                    monitorData: win.monitorData
                    mscale: 1
                    spread: 1
                    motionActive: win.workspaceSliding
                    stackZ: Number(win.entryStack[modelData]) || 0
                    slotX: stageArea.x + (packedRect ? packedRect.x : 0)
                    slotY: stageArea.y + (packedRect ? packedRect.y : 0)
                    slotW: packedRect ? packedRect.width : 1
                    slotH: packedRect ? packedRect.height : 1
                }
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            x: win.workspaceSlide

            Repeater {
                id: stageRepeater
                model: win.stageModel
                delegate: WindowThumb {
                    required property var modelData
                    windowData: MCService.windowByAddress(modelData)
                    readonly property var packedRect: win.stageLayout[modelData] || null
                    draggable: win.overviewInteractive
                    live: true
                    placeholderVisible: false
                    captureEnabled: win.captureEnabled
                    overview: win
                    monitorData: win.monitorData
                    mscale: 1
                    spread: win.spatialProgress
                    motionActive: win.transitionRunning || win.workspaceSliding
                    selectedForExit: win.exitKind === "window"
                        && win.selectedAddress === modelData
                    stackZ: Number(win.entryStack[modelData]) || 0
                    slotX: stageArea.x + (packedRect ? packedRect.x : 0)
                    slotY: stageArea.y + (packedRect ? packedRect.y : 0)
                    slotW: packedRect ? packedRect.width : 1
                    slotH: packedRect ? packedRect.height : 1
                }
            }
        }

        Rectangle {
            anchors.centerIn: stageArea
            visible: stageRepeater.count === 0
            opacity: win.overviewProgress
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
                captureSource: win.captureEnabled && win.dragActive ? dragProxy.dragToplevel : null
                live: win.captureEnabled && win.dragActive
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
