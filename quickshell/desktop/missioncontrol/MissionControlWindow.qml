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
    property int tileDropIndex: -1       // insertion slot among the other tiles
    property real tileDropX: 0           // scene x of the insertion indicator
    property int hoveredWorkspaceId: -1

    readonly property var monitorData: {
        let n = win.screen ? win.screen.name : ""
        return MCService.monitors.find(m => m.name === n) || null
    }
    readonly property int activeWorkspaceId: MCService.activeWorkspaceIdForMonitor(win.screen ? win.screen.name : "")
    readonly property real monLogW: monitorData ? monitorData.width / monitorData.scale : 1920
    readonly property real monLogH: monitorData ? monitorData.height / monitorData.scale : 1200

    property int currentStageWsId: activeWorkspaceId
    property int outgoingStageWsId: -1
    property int workspaceSlideDirection: 1
    property real workspaceSlide: 0
    readonly property bool workspaceSliding: workspaceSlideAnim.running
    NumberAnimation {
        id: workspaceSlideAnim
        target: win; property: "workspaceSlide"
        duration: 180; easing.type: Easing.OutCubic
        onFinished: {
            win.workspaceSlide = 0
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

    // Stage spread: 0 = windows at their real (overlapping) positions, 1 = spread
    // out into the grid. Animated 0→1 on open and 1→0 on close (the previews then
    // collapse back onto the real windows as the wallpaper fades away).
    property real spread: 1
    readonly property bool spreadAnimating: spreadAnim.running
    NumberAnimation {
        id: spreadAnim          // from = current value; `to` set by open/close paths
        target: win; property: "spread"
        duration: 180; easing.type: Easing.OutCubic
    }

    // Top workspace strip slide: tucked above the screen, drops down on open and
    // slides back up on close.
    property real stripSlide: 0
    readonly property real stripHiddenY: -(stripBg.height + 24)
    NumberAnimation {
        id: stripAnim
        target: win; property: "stripSlide"
        duration: 160; easing.type: Easing.OutCubic
    }

    onShowChanged: {
        if (show) {
            _resetDrag()
            _resetWorkspaceSlide()
            spreadAnim.stop()
            win.spread = 0
            _surfaceVisible = true
            unmapTimer.stop()
            keyCatcher.forceActiveFocus()
            stripAnim.stop()
            win.stripSlide = win.stripHiddenY
            spreadAnim.to = 1
            spreadAnim.restart()
            stripAnim.to = 0
            stripAnim.restart()
            Dock.DockService.overviewScreen = ""
            Dock.DockService.overviewOpen = true
            openRefreshTimer.restart()
        } else {
            openRefreshTimer.stop()
            Dock.DockService.overviewOpen = false
            MCService.open = false
            _resetDrag()
            workspaceActivateCloseTimer.stop()
            spreadAnim.stop()       // leave the previews spread; the content just fades
            workspaceSlideAnim.stop()
            win.workspaceSlide = 0
            win.outgoingStageWsId = -1
            stripAnim.stop()
            stripAnim.to = win.stripHiddenY     // strip slides back up
            stripAnim.restart()
            unmapTimer.restart()
        }
    }

    Connections {
        target: Dock.DockService
        function onLaunchpadCloseRequested() { if (win.show) win.closeRequested() }
    }

    Timer { id: unmapTimer; interval: 200; onTriggered: win._surfaceVisible = false }
    Timer { id: workspaceActivateCloseTimer; interval: 220; onTriggered: win.closeRequested() }
    Timer {
        id: openRefreshTimer
        interval: 16
        onTriggered: {
            MCService.open = true
            WallpaperService.refresh()
        }
    }

    WlrLayershell.namespace: "qs-missioncontrol"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

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
    }

    function _workspaceIndex(wsId) {
        let ids = MCService.displayWorkspaceIds
        let idx = ids.indexOf(wsId)
        return idx >= 0 ? idx : wsId
    }

    function _resetWorkspaceSlide() {
        workspaceSlideAnim.stop()
        win.currentStageWsId = win.activeWorkspaceId
        win.outgoingStageWsId = -1
        win.workspaceSlide = 0
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
        win.outgoingStageWsId = win.currentStageWsId
        win.currentStageWsId = wsId
        workspaceSlideAnim.stop()
        win.workspaceSlide = win.workspaceSlideDirection * Math.max(1, stageArea.fitW)
        workspaceSlideAnim.to = 0
        workspaceSlideAnim.restart()
    }

    onActiveWorkspaceIdChanged: _slideToWorkspace(activeWorkspaceId)

    // ── Actions invoked by children ───────────────────────────────────────────
    function activateWindow(address) { MCService.focusWindow(address); win.closeRequested() }
    function activateWorkspace(wsId) {
        MCService.focusWorkspace(wsId)
        if (wsId === win.activeWorkspaceId) win.closeRequested()
        else workspaceActivateCloseTimer.restart()
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
            let other = MCService.displayWorkspaceIds.find(id => id !== wsId)
            if (other === undefined) return
            into = other
            MCService.focusWorkspace(into)
        }
        MCService.deleteWorkspace(wsId, into)
    }

    // ── Workspace-tile reorder ────────────────────────────────────────────────
    function beginTileDrag(wsId) {
        win.tileDragActive = true
        win.tileDragId = wsId
        win.tileDropIndex = -1
    }
    function updateTileDrag(scenePos) {
        win.tileDragPos = scenePos
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
        if (win.tileDragId >= 1 && win.tileDropIndex >= 0)
            MCService.moveWorkspaceOrder(win.tileDragId, win.tileDropIndex)
        win.tileDragActive = false
        win.tileDragId = -1
        win.tileDropIndex = -1
    }

    // ── Drag coordination ─────────────────────────────────────────────────────
    function beginWindowDrag(address) {
        win.dragActive = true
        win.dragAddress = address
        win.dropWsId = -1
        win.dropWindowAddress = ""
        win.dropNewFullscreen = false
        win.dropNewWorkspace = false
        win.dropSplitWsId = -1
        stripHoldTimer.stop()
    }
    function updateWindowDrag(scenePos) {
        win.dragPos = scenePos
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
    Timer { id: stripHoldTimer; interval: 420; onTriggered: win.dropNewFullscreen = true }

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
    // against the real compositor background instead of an in-layer image.
    Item {
        id: wallpaper
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: win.stripHeight
        }
        clip: true
        opacity: win.show ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            x: 0
            y: -win.stripHeight
            width: win.width
            height: win.height
            color: win.wallpaperPaddingColor
        }

        Image {
            x: 0
            y: -win.stripHeight
            width: win.width
            height: win.height
            source: (win._surfaceVisible && win.wallpaperPath.length > 1) ? ("file://" + win.wallpaperPath) : ""
            fillMode: win.wallpaperFillMode
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            cache: true
            asynchronous: true
        }

        // Empty-area click dismisses.
        MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }
    }

    Item {
        id: content
        anchors.fill: parent
        // Fade the whole overview in/out (open spread stays; close just dissolves).
        opacity: win.show ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
            readonly property bool expanded: stripHover.hovered || win.dragActive || win.tileDragActive
            readonly property int workspaceCount: Math.max(1, MCService.displayWorkspaceIds.length)
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
                border.color: ThemeService.surfaceStroke
                border.width: 1
                Behavior on height { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 100 } }
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
                    model: MCService.displayWorkspaceIds
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
                color: addHover.hovered ? Qt.rgba(win.dark ? 1 : 0, win.dark ? 1 : 0, win.dark ? 1 : 0, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
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
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MCService.addWorkspace()
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
                        source: (win._surfaceVisible && win.wallpaperPath.length > 1) ? ("file://" + win.wallpaperPath) : ""
                        fillMode: win.wallpaperFillMode
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        opacity: 0.45
                        cache: true
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
                        source: (win._surfaceVisible && win.wallpaperPath.length > 1) ? ("file://" + win.wallpaperPath) : ""
                        fillMode: win.wallpaperFillMode
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        opacity: 0.45
                        cache: true
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
                        model: win.outgoingStageWsId >= 1 ? MCService.windowsForWorkspaceSorted(win.outgoingStageWsId) : []
                        delegate: WindowThumb {
                            required property var modelData
                            required property int index
                            windowData: modelData
                            draggable: false
                            live: false
                            overview: null
                            iconUrl: win.iconUrlForClass(modelData.class)
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
                        model: MCService.windowsForWorkspaceSorted(win.currentStageWsId)
                        delegate: WindowThumb {
                            required property var modelData
                            required property int index
                            windowData: modelData
                            draggable: !win.workspaceSliding
                            live: true
                            overview: win
                            iconUrl: win.iconUrlForClass(modelData.class)
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
                source: (win._surfaceVisible && win.wallpaperPath.length > 1) ? ("file://" + win.wallpaperPath) : ""
                fillMode: win.wallpaperFillMode
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignVCenter
                cache: true
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
