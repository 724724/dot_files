import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import "../dock" as Dock
import "../bar" as Bar
import "../missioncontrol" as MC
import "../icons" as Icons

PanelWindow {
    id: win

    // ── Public state ─────────────────────────────────────────────────────
    property bool show: false
    signal closeRequested

    // Stay mapped during the close animation so it can fade out before unmap.
    property bool _surfaceVisible: false
    property bool _presented: false
    visible: _surfaceVisible

    Timer {
        id: presentTimer
        interval: 16
        onTriggered: if (win.show) win._presented = true
    }

    onShowChanged: {
        if (show) {
            _presented = false
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            _surfaceVisible = true
            // Raise the one real dock above the launchpad backdrop (it's mapped
            // after the launchpad, so it stacks on top) — no in-launchpad replica.
            Dock.DockService.launchpadScreen = win.screen ? win.screen.name : ""
            Dock.DockService.launchpadOpen = true
            queryField.text = ""
            _resetToFirstPage()
            currentCellIndex = 0
            inputMode = "mouse"
            editing = false
            openFolder = -1
            _endDrag(true)
            _endFolderDrag(true)
            Qt.callLater(() => {
                if (!win.show) return
                queryField.forceActiveFocus()
                presentTimer.restart()
            })
        } else {
            presentTimer.stop()
            _presented = false
            Dock.DockService.launchpadOpen = false
            Dock.DockService.launchpadDragActive = false
            editing = false
            openFolder = -1
        }
    }

    // The dock (above this surface) asks us to close when an app is launched /
    // focused from it, so it isn't left buried behind the launchpad.
    Connections {
        target: Dock.DockService
        function onLaunchpadCloseRequested() { if (win.show) win.closeRequested() }
    }

    // ── Layer / placement ───────────────────────────────────────────────
    WlrLayershell.namespace: "qs-launchpad"
    // A pinned dock stays continuously mapped on Overlay, so place Launchpad on
    // Top beneath it. Otherwise use Overlay to cover fullscreen windows.
    readonly property string activeScreenName: win.screen ? win.screen.name : ""
    readonly property bool dockPinnedHere: Dock.DockService.pinnedVisible
        && !Dock.DockService.fullscreenMonitors.includes(activeScreenName)
        && !MC.MCService.splitViewActiveOn(activeScreenName)
    WlrLayershell.layer: dockPinnedHere ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: show ? null : closedRegion
    Region { id: closedRegion }

    // ── Icon / launch helpers ───────────────────────────────────────────
    function _iconNameFor(app) {
        if (!app || !app.icon) return "application-x-executable"
        if (app.icon === "DDB7_KakaoTalk.0" && Quickshell.iconPath("KakaoTalk", true) !== "")
            return "KakaoTalk"
        return app.icon
    }
    function launchApp(app) {
        if (!app) return
        if (app.runInTerminal) {
            let argv = ["kitty"]
            for (let i = 0; i < app.command.length; ++i)
                if (app.command[i] && app.command[i].charAt(0) !== "%")
                    argv.push(app.command[i])
            Quickshell.execDetached(argv)
        } else {
            Quickshell.execDetached(["gtk-launch", app.id])
        }
    }
    function launchById(id) {
        // Focus mode: block disallowed apps. Keep the launchpad open so the mask
        // stays visible and the user sees why nothing launched.
        if (!Bar.ClockService.isAppAllowed(id)) {
            let a = LaunchpadModel.appById(id)
            Bar.ClockService.notifyBlocked(a ? a.name : id)
            return
        }
        launchApp(LaunchpadModel.appById(id))
        win.closeRequested()
    }

    // ── Entries (model items, or flat search results) ────────────────────
    readonly property string query: queryField.text
    readonly property bool searching: query.trim() !== ""

    function _appName(id) { let a = LaunchpadModel.appById(id); return a ? (a.name || "") : "" }

    readonly property var searchEntries: {
        let q = query.trim().toLowerCase()
        if (!q) return []
        let apps = DesktopEntries.applications.values
        let arr = []
        for (let i = 0; i < apps.length; i++) {
            let a = apps[i]
            if (!a || a.noDisplay || !a.name) continue
            let n = a.name.toLowerCase()
            let g = (a.genericName || "").toLowerCase()
            let kw = (a.keywords || []).join(" ").toLowerCase()
            let c = (a.comment || "").toLowerCase()
            if (n.includes(q) || g.includes(q) || kw.includes(q) || c.includes(q))
                arr.push({ type: "app", id: a.id })
        }
        arr.sort((x, y) => win._appName(x.id).toLowerCase().localeCompare(win._appName(y.id).toLowerCase()))
        return arr
    }

    readonly property var entries: searching ? searchEntries : LaunchpadModel.items
    readonly property int entryCount: entries.length

    // ── Pagination ──────────────────────────────────────────────────────
    readonly property int gridCols: 9
    readonly property int gridRows: 6
    readonly property int perPage: gridCols * gridRows   // 54
    readonly property int pageCount: Math.max(1, Math.ceil(entryCount / perPage))

    // Programmatic resets (open, search swaps, folder open) must not slide —
    // only user-driven page changes animate. Binding write-through is synchronous,
    // so flipping the flag around the assignment is enough to gate the Behaviors.
    property bool _pageSnap: false
    function _resetToFirstPage() {
        _pageSnap = true
        pages.currentIndex = 0
        _pageSnap = false
    }

    component HorizontalPagerWheel: MouseArea {
        id: gesture

        required property var pager
        required property int pagesTotal
        property real accumulatedX: 0
        property bool committed: false

        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        enabled: pagesTotal > 1
        z: 1000

        Timer {
            id: gestureEnd
            interval: 180
            onTriggered: {
                gesture.accumulatedX = 0
                gesture.committed = false
            }
        }

        onWheel: wheel => {
            let hasPixelDelta = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
            let dx = hasPixelDelta ? wheel.pixelDelta.x : wheel.angleDelta.x
            let dy = hasPixelDelta ? wheel.pixelDelta.y : wheel.angleDelta.y
            if (dx === 0 || Math.abs(dx) <= Math.abs(dy)) {
                wheel.accepted = false
                return
            }

            wheel.accepted = true
            gestureEnd.restart()
            if (gesture.committed) return
            if (gesture.accumulatedX !== 0 && Math.sign(dx) !== Math.sign(gesture.accumulatedX))
                gesture.accumulatedX = 0
            gesture.accumulatedX += dx

            let threshold = hasPixelDelta ? 45 : 120
            if (Math.abs(gesture.accumulatedX) < threshold) return

            let next = gesture.accumulatedX < 0
                ? Math.min(gesture.pagesTotal - 1, gesture.pager.currentIndex + 1)
                : Math.max(0, gesture.pager.currentIndex - 1)
            gesture.pager.currentIndex = next
            gesture.committed = true
            gesture.accumulatedX = 0
        }
    }

    // Space kept clear on the selected edge for the Dock. Derive it from the
    // same monitor-relative icon limits as DockWindow so a user-enlarged Dock
    // never overlaps Launchpad content, while a compact Dock wastes less room.
    readonly property real dockShortSide: Math.max(1, Math.min(width, height))
    readonly property real dockMinIcon: Math.max(24,
        Math.min(32, dockShortSide * 0.022))
    readonly property real dockMaxIcon: Math.max(48,
        Math.min(66, dockShortSide * 0.045))
    readonly property real dockCurrentIcon: dockMinIcon
        + Dock.DockService.dockSizeLevel * (dockMaxIcon - dockMinIcon)
    readonly property int dockReserve: Math.ceil(18 + 68 * dockCurrentIcon / 42)

    // ── Keyboard vs mouse selection ──────────────────────────────────────
    // The selection box behind an app only shows while navigating with the
    // keyboard; using the mouse hides it (per request).
    property string inputMode: "mouse"   // "kb" | "mouse"
    readonly property bool kbHighlight: inputMode === "kb"

    property int currentCellIndex: 0
    onEntriesChanged: { currentCellIndex = 0; _resetToFirstPage() }
    onQueryChanged: if (searching) inputMode = "kb"

    function activateIndex(i) {
        let e = entries[i]
        if (!e) return
        if (e.type === "folder") { win.openFolderAt(i) }
        else { win.launchById(e.id) }
    }

    function pageOfIndex(idx) { return Math.floor(idx / perPage) }
    function moveSelection(dx, dy) {
        if (entryCount === 0) return
        inputMode = "kb"
        let idx = currentCellIndex
        let onPage = idx % perPage
        let row = Math.floor(onPage / gridCols)
        let col = onPage % gridCols
        let newCol = col + dx
        let newRow = row + dy
        let newIdx = idx
        if (newCol < 0 && pages.currentIndex > 0) {
            pages.currentIndex -= 1
            newIdx = pages.currentIndex * perPage + row * gridCols + (gridCols - 1)
        } else if (newCol >= gridCols && pages.currentIndex < pageCount - 1) {
            pages.currentIndex += 1
            newIdx = pages.currentIndex * perPage + row * gridCols + 0
        } else {
            newCol = Math.max(0, Math.min(gridCols - 1, newCol))
            newRow = Math.max(0, Math.min(gridRows - 1, newRow))
            newIdx = pages.currentIndex * perPage + newRow * gridCols + newCol
        }
        if (newIdx >= 0 && newIdx < entryCount) currentCellIndex = newIdx
    }

    // ── Edit mode (folder management) + folder view ──────────────────────
    property bool editing: false
    property int openFolder: -1          // index into LaunchpadModel.items, -1 = none

    function openFolderAt(idx) {
        let e = LaunchpadModel.items[idx]
        if (e && e.type === "folder") openFolder = idx
    }

    property bool folderDragActive: false
    property int folderDragIndex: -1
    property int folderDragHoverIndex: -1
    property point folderDragPos: Qt.point(0, 0)
    property point folderDragGrabOffset: Qt.point(0, 0)
    property bool folderDragOutside: false
    property bool folderDragEscaped: false
    property int folderEscapeHoverIndex: -1
    property bool folderEscapeMergeEligible: false
    property string folderDragAppId: ""
    property point folderDragPointerPos: Qt.point(0, 0)

    Timer {
        id: folderEscapeTimer
        interval: 420
        onTriggered: win._escapeFolderDrag()
    }

    function _beginFolderDrag(idx, pointerPos, pressPos, bodyCenter) {
        if (!folderView.folder || idx < 0 || idx >= folderView.appCount) return
        folderDragActive = true
        folderDragIndex = idx
        folderDragHoverIndex = idx
        folderDragOutside = false
        folderDragEscaped = false
        folderEscapeHoverIndex = -1
        folderEscapeMergeEligible = false
        folderDragAppId = folderView.folder.apps[idx]
        folderDragPointerPos = pointerPos
        folderDragGrabOffset = Qt.point(bodyCenter.x - pressPos.x, bodyCenter.y - pressPos.y)
        folderDragPos = rubberBandPoint(Qt.point(
            pointerPos.x + folderDragGrabOffset.x,
            pointerPos.y + folderDragGrabOffset.y
        ))
    }

    function _updateFolderDrag(scenePos) {
        folderDragPointerPos = scenePos
        folderDragPos = rubberBandPoint(Qt.point(
            scenePos.x + folderDragGrabOffset.x,
            scenePos.y + folderDragGrabOffset.y
        ))
        if (folderDragEscaped) {
            folderEscapeHoverIndex = cellIndexAtScene(scenePos)
            folderEscapeMergeEligible = cursorInCellCenter(scenePos, folderEscapeHoverIndex)
            return
        }
        let outside = !pointInsideFolderPanel(scenePos)
        if (outside !== folderDragOutside) {
            folderDragOutside = outside
            if (outside) folderEscapeTimer.restart()
            else folderEscapeTimer.stop()
        }
        folderDragHoverIndex = outside ? -1 : folderCellIndexAtScene(scenePos)
    }

    function _escapeFolderDrag() {
        if (!folderDragActive || !folderDragOutside || folderDragEscaped) return
        folderDragEscaped = true
        folderEscapeHoverIndex = cellIndexAtScene(folderDragPointerPos)
        folderEscapeMergeEligible = cursorInCellCenter(
            folderDragPointerPos, folderEscapeHoverIndex)
    }

    function _endFolderDrag(silent) {
        let folderIdx = openFolder
        let from = folderDragIndex
        let to = folderDragHoverIndex
        let outside = folderDragOutside
        let escaped = folderDragEscaped
        let escapeTo = folderEscapeHoverIndex
        let escapeMerge = folderEscapeMergeEligible
        let appId = folderDragAppId
        folderEscapeTimer.stop()
        folderDragActive = false
        folderDragIndex = -1
        folderDragHoverIndex = -1
        folderDragOutside = false
        folderDragEscaped = false
        folderEscapeHoverIndex = -1
        folderEscapeMergeEligible = false
        folderDragAppId = ""
        if (silent || folderIdx < 0 || from < 0) return
        if (escaped && appId !== "") {
            LaunchpadModel.dropExtractedFolderApp(
                folderIdx, appId, escapeTo, escapeMerge)
            openFolder = -1
        } else if (outside && appId !== "") {
            LaunchpadModel.extractFromFolderToEnd(folderIdx, appId)
            let current = LaunchpadModel.items[folderIdx]
            if (!current || current.type !== "folder") openFolder = -1
        } else if (to >= 0 && from !== to) {
            LaunchpadModel.reorderInFolder(folderIdx, from, to)
        }
    }

    function pointInsideFolderPanel(pt) {
        let p = folderPanel.mapFromItem(null, pt.x, pt.y)
        return p.x >= 0 && p.x <= folderPanel.width
            && p.y >= 0 && p.y <= folderPanel.height
    }

    function folderCellIndexAtScene(pt) {
        if (!folderView.folder) return -1
        let p = folderSwipe.mapFromItem(null, pt.x, pt.y)
        if (p.y < 0 || p.y >= folderSwipe.height) return -1
        let pageStart = folderSwipe.currentIndex * folderView.perPage
        let count = Math.min(folderView.perPage, folderView.appCount - pageStart)
        if (count <= 0) return -1
        let columns = Math.min(7, count)
        let gridLeft = (folderSwipe.width - columns * folderPanel.cellW) / 2
        let col = Math.floor((p.x - gridLeft) / folderPanel.cellW)
        let row = Math.floor(p.y / folderPanel.cellH)
        if (col < 0 || col >= 7 || row < 0 || row >= 5) return -1
        let local = row * 7 + col
        return local < count ? pageStart + local : -1
    }

    function folderDragDisplaySlot(appIndex, pageStart) {
        let slot = appIndex - pageStart
        if (!folderDragActive) return slot
        let from = folderDragIndex
        let to = folderDragHoverIndex
        let pageEnd = pageStart + folderView.perPage
        if (from < pageStart || from >= pageEnd || to < pageStart || to >= pageEnd || from === to)
            return slot
        if (appIndex === from) return slot
        if (from < to && appIndex > from && appIndex <= to) return slot - 1
        if (from > to && appIndex >= to && appIndex < from) return slot + 1
        return slot
    }

    // ── Drag state ───────────────────────────────────────────────────────
    property bool dragActive: false
    property int dragIndex: -1           // index into LaunchpadModel.items being dragged
    property int dragHoverIndex: -1      // cell currently under the cursor
    property int folderCandidate: -1     // target that will become a folder on drop
    property bool _folderEligible: false // cursor is over the centre of the hovered cell
    property bool _animatePos: false      // animate cell positions (only while dragging)
    property point dragPos: Qt.point(0, 0)
    property point dragGrabOffset: Qt.point(0, 0)

    function rubberBand(value, lower, upper, dimension) {
        let overshoot = value < lower ? value - lower : (value > upper ? value - upper : 0)
        if (overshoot === 0) return value
        let resisted = (overshoot * dimension * 0.55) / (dimension + 0.55 * Math.abs(overshoot))
        return (value < lower ? lower : upper) + resisted
    }

    function rubberBandPoint(pt) {
        return Qt.point(
            rubberBand(pt.x, 28, win.width - 28, Math.max(1, win.width)),
            rubberBand(pt.y, 28, win.height - 28, Math.max(1, win.height))
        )
    }

    // Slot a cell renders at while dragging: items between the drag source and the
    // hovered target slide by one to open a gap at the drop spot (live reorder).
    // Only on edge hover — a centre hover means "make a folder", so no shift.
    function dragDisplaySlot(absIndex, pageStart) {
        let slot = absIndex - pageStart
        if (!win.dragActive || win.searching || win._folderEligible) return slot
        let from = win.dragIndex, to = win.dragHoverIndex
        if (from < 0 || to < 0 || from === to) return slot
        let pageEndExcl = pageStart + win.perPage
        if (from < pageStart || from >= pageEndExcl || to < pageStart || to >= pageEndExcl) return slot
        if (absIndex === from) return slot                            // the dragged item (hidden)
        if (from < to && absIndex > from && absIndex <= to) return slot - 1
        if (from > to && absIndex >= to && absIndex < from) return slot + 1
        return slot
    }

    property bool _dragOverDock: false   // cursor over the dock (bottom strip) → drop pins
    // Tell the real dock the drag state + cursor X so it opens a gap at the slot.
    function _setDragOverDock(over, scenePos) {
        win._dragOverDock = over
        Dock.DockService.launchpadDragActive = over
        if (over) {
            Dock.DockService.launchpadDragX = scenePos.x
            Dock.DockService.launchpadDragY = scenePos.y
        }
    }

    function _beginDrag(idx, pointerPos, pressPos, bodyCenter) {
        win.dragActive = true
        win._animatePos = true           // cells slide to make room while dragging
        win.dragIndex = idx
        win.dragHoverIndex = idx
        win.folderCandidate = -1
        win.dragGrabOffset = Qt.point(bodyCenter.x - pressPos.x, bodyCenter.y - pressPos.y)
        win.dragPos = win.rubberBandPoint(Qt.point(
            pointerPos.x + win.dragGrabOffset.x,
            pointerPos.y + win.dragGrabOffset.y
        ))
        win._setDragOverDock(false, Qt.point(0, 0))
    }
    function _updateDrag(scenePos) {
        win.dragPos = win.rubberBandPoint(Qt.point(
            scenePos.x + win.dragGrabOffset.x,
            scenePos.y + win.dragGrabOffset.y
        ))
        win._setDragOverDock(win._dragPosOverDock(scenePos), scenePos)
        // Over the dock → it's a pin, not a grid move; stop any reorder/folder preview.
        if (win._dragOverDock) {
            win.dragHoverIndex = -1
            win._folderEligible = false
            win.folderCandidate = -1
            folderTimer.stop()
            return
        }
        let h = win.cellIndexAtScene(scenePos)
        let elig = win.cursorInCellCenter(scenePos, h)
        if (h !== win.dragHoverIndex) {
            win.dragHoverIndex = h
            win._folderEligible = elig
            win.folderCandidate = -1
            folderTimer.restart()
        } else if (elig !== win._folderEligible) {
            // Same cell, but moved between its centre (folder) and edge (reorder).
            win._folderEligible = elig
            if (!elig) win.folderCandidate = -1
            folderTimer.restart()
        }
    }
    function _endDrag(silent) {
        win._animatePos = false          // snap to final positions, no settle
        folderTimer.stop()
        let src = win.dragIndex
        let cand = win.folderCandidate
        let hov = win.dragHoverIndex
        let onDock = win._dragOverDock
        let dropIdx = Dock.DockService.launchpadDropIndex   // slot the dock opened a gap at
        win.dragActive = false
        win.dragIndex = -1
        win.folderCandidate = -1
        win.dragHoverIndex = -1
        win._setDragOverDock(false, Qt.point(0, 0))
        if (silent || src < 0 || win.searching) return
        let item = LaunchpadModel.items[src]
        // Dropped on the dock → pin it at the opened gap (stays in the launchpad too).
        if (onDock && item && item.type === "app") {
            let a = LaunchpadModel.appById(item.id)
            if (a) {
                Dock.DockService.pinAppAt({
                    name: a.name,
                    wmClass: (a.startupClass && a.startupClass !== "") ? a.startupClass : a.id,
                    iconName: a.icon,
                    execCmd: ["gtk-launch", a.id]
                }, dropIdx >= 0 ? dropIdx : Dock.DockService.pinnedApps.length)
            }
            return
        }
        if (cand >= 0 && cand !== src) {
            let s = LaunchpadModel.items[src], t = LaunchpadModel.items[cand]
            if (s && t && s.type === "app" && t.type === "folder") LaunchpadModel.addToFolder(cand, src)
            else if (s && t && s.type === "app" && t.type === "app") LaunchpadModel.makeFolder(src, cand)
            else LaunchpadModel.reorderTo(src, cand)
        } else if (hov >= 0 && hov !== src) {
            LaunchpadModel.reorderTo(src, hov)
        }
    }
    // The real dock floats along the bottom edge while the launchpad is open
    // (same screen, so launchpad scene coords == screen coords). Treat the bottom
    // strip — the band kept clear for it (dockReserve) — as the pin drop zone.
    function _dragPosOverDock(pt) {
        if (Dock.DockService.dockEdge === "left") return pt.x <= win.dockReserve
        if (Dock.DockService.dockEdge === "right") return pt.x >= win.width - win.dockReserve
        return pt.y >= win.height - win.dockReserve
    }

    // Hit-test the cursor (scene coords) to a top-level cell index.
    function cellIndexAtScene(pt) {
        let lp = pageWrapper.mapFromItem(null, pt.x, pt.y)
        if (lp.x < 0 || lp.y < 0 || lp.x > pageWrapper.width || lp.y > pageWrapper.height) return -1
        let cw = pageWrapper.width / gridCols
        let ch = pageWrapper.height / gridRows
        let col = Math.floor(lp.x / cw)
        let row = Math.floor(lp.y / ch)
        if (col < 0 || col >= gridCols || row < 0 || row >= gridRows) return -1
        let idx = pages.currentIndex * perPage + row * gridCols + col
        if (idx < 0 || idx >= entryCount) return -1
        return idx
    }

    // True when the cursor is over the central part of cell `idx` — only there is
    // a drop a folder-merge; nearer the edges it's a reorder, so dragging an app
    // *beside* another moves it instead of merging.
    function cursorInCellCenter(pt, idx) {
        if (idx < 0) return false
        let lp = pageWrapper.mapFromItem(null, pt.x, pt.y)
        let cw = pageWrapper.width / gridCols
        let ch = pageWrapper.height / gridRows
        let onPage = idx % perPage
        let cx = (onPage % gridCols) * cw + cw / 2
        let cy = Math.floor(onPage / gridCols) * ch + ch / 2
        // Generous central zone so dropping onto an app reliably makes a folder;
        // only the outer band counts as a between-apps reorder.
        return Math.abs(lp.x - cx) < cw * 0.42 && Math.abs(lp.y - cy) < ch * 0.44
    }

    Timer {
        id: folderTimer
        interval: 256
        onTriggered: {
            let h = win.dragHoverIndex
            // Only an *app* being dragged can form or join a folder. A dragged
            // folder never merges — it only reorders — so folders are never
            // combined with each other (nor swallowed by an app).
            let src = LaunchpadModel.items[win.dragIndex]
            if (win.dragActive && win._folderEligible && h >= 0 && h !== win.dragIndex
                    && !win.searching && src && src.type === "app") {
                let t = LaunchpadModel.items[h]
                if (t && (t.type === "folder" || t.type === "app")) win.folderCandidate = h
            }
        }
    }

    // ── Backdrop ────────────────────────────────────────────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: win._presented ? 1.0 : 0.0
        Behavior on opacity { AppleSpring { spring: 18 } }
        onOpacityChanged: if (!win.show && opacity <= 0.002) win._surfaceVisible = false

        MouseArea {
            anchors.fill: parent
            enabled: win.show
            // Empty-area clicks: close a folder, else leave edit mode, else dismiss.
            onPressed: {
                if (win.openFolder >= 0) win.openFolder = -1
                else if (win.editing) win.editing = false
                else win.closeRequested()
            }
        }
    }

    // ── Content ──────────────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent
        // Hidden while a folder is open so the folder view reads as full-screen
        // with nothing of the grid showing behind it.
        opacity: (win._presented && (win.openFolder < 0 || win.folderDragEscaped)) ? 1.0 : 0.0
        scale: win._presented ? 1.0 : 0.92
        transformOrigin: Item.Center
        Behavior on opacity { AppleSpring { spring: 13 } }
        Behavior on scale { AppleSpring { spring: 13 } }

        // ── Search input ─────────────────────────────────────────────────
        Item {
            id: searchBar
            anchors.top: parent.top
            anchors.topMargin: 32
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 44

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: ThemeService.bg
                border.color: ThemeService.stroke
                border.width: 1
            }

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: Qt.rgba(1, 1, 1, 0.65)
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 18
            }

            TextField {
                id: queryField
                anchors.left: searchIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: "#ffffff"
                placeholderText: "Search"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 14
                selectByMouse: true

                Keys.onEscapePressed: {
                    if (win.openFolder >= 0) win.openFolder = -1
                    else if (win.editing) win.editing = false
                    else win.closeRequested()
                }
                Keys.onLeftPressed:  win.moveSelection(-1, 0)
                Keys.onRightPressed: win.moveSelection(+1, 0)
                Keys.onUpPressed:    win.moveSelection(0, -1)
                Keys.onDownPressed:  win.moveSelection(0, +1)
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_PageDown) {
                        if (pages.currentIndex < win.pageCount - 1) pages.currentIndex += 1
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        if (pages.currentIndex > 0) pages.currentIndex -= 1
                        event.accepted = true
                    }
                }
                Keys.onReturnPressed: win.activateIndex(win.currentCellIndex)
                Keys.onEnterPressed:  win.activateIndex(win.currentCellIndex)
            }
        }

        // ── Done button (edit mode) ──────────────────────────────────────
        Rectangle {
            id: doneBtn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 36
            anchors.rightMargin: 36
            visible: win.editing && win.openFolder < 0
            width: doneLabel.implicitWidth + 28
            height: 36
            radius: 18
            color: ThemeService.popupBg
            border.color: ThemeService.stroke
            border.width: 1
            scale: doneMa.pressed ? ThemeService.pressScale : 1.0
            Behavior on scale { AppleSpring { spring: 13 } }
            Text {
                id: doneLabel
                anchors.centerIn: parent
                text: "Done"
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: doneMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                    onClicked: win.editing = false
            }
        }

        // ── Paged grid ───────────────────────────────────────────────────
        Item {
            id: pageWrapper
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: searchBar.bottom
            anchors.bottom: pageDots.top
            anchors.topMargin: 24
            anchors.bottomMargin: 16

            HorizontalPagerWheel {
                anchors.fill: parent
                pager: pages
                pagesTotal: win.pageCount
            }

            SwipeView {
                id: pages
                anchors.fill: parent
                clip: false
                interactive: false
                orientation: Qt.Horizontal

                contentItem: ListView {
                    id: pagesFlick
                    model: pages.contentModel
                    interactive: pages.interactive
                    focus: pages.focus
                    orientation: pages.orientation
                    // No currentIndex binding or highlight range: ListView reacts to
                    // those by writing contentX directly (bypassing the Behavior), which
                    // snapped pages instantly. The binding below is the sole driver, so
                    // every page change goes through the spring; drags sync back on settle.
                    contentX: pages.currentIndex * width
                    onMovementEnded: pages.currentIndex =
                        Math.max(0, Math.min(pages.count - 1, Math.round(contentX / width)))
                    snapMode: ListView.SnapOneItem
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    boundsMovement: Flickable.FollowBoundsBehavior
                    cacheBuffer: width   // keep the neighbouring page alive for the slide
                    maximumFlickVelocity: 4 * width
                    rebound: Transition {
                        SpringAnimation {
                            properties: "x,y"
                            spring: 18
                            damping: ThemeService.momentumDamping
                            epsilon: 0.25
                        }
                    }
                    Behavior on contentX {
                        enabled: !win._pageSnap && !pagesFlick.dragging && !pagesFlick.flicking
                        AppleSpring { spring: 18; epsilon: 0.1 }
                    }
                }

                Repeater {
                    model: win.pageCount

                    delegate: Item {
                        id: pageItem
                        required property int index
                        width: pages.width
                        height: pages.height

                        readonly property int pageStart: index * win.perPage
                        readonly property int cellW: pageItem.width / win.gridCols
                        readonly property int cellH: pageItem.height / win.gridRows

                        // Absolute-positioned cells (not a Grid) so they can slide
                        // aside to open a gap while an app is dragged (live reorder).
                        Item {
                            anchors.fill: parent

                            Repeater {
                                model: win.perPage

                                delegate: Item {
                                    id: cell
                                    required property int index   // natural slot within page
                                    width: pageItem.cellW
                                    height: pageItem.cellH

                                    readonly property int absIndex: pageItem.pageStart + index
                                    // Display slot — shifts so a gap opens at the drop spot
                                    // while dragging; otherwise the natural slot.
                                    readonly property int dslot: win.dragDisplaySlot(cell.absIndex, pageItem.pageStart)
                                    x: (dslot % win.gridCols) * pageItem.cellW
                                    y: Math.floor(dslot / win.gridCols) * pageItem.cellH
                                    Behavior on x { enabled: win._animatePos; AppleSpring { spring: 13; epsilon: 0.15 } }
                                    Behavior on y { enabled: win._animatePos; AppleSpring { spring: 13; epsilon: 0.15 } }

                                    readonly property var entry: absIndex < win.entryCount ? win.entries[absIndex] : null
                                    readonly property bool isApp: entry && entry.type === "app"
                                    readonly property bool isFolder: entry && entry.type === "folder"
                                    readonly property var app: isApp ? LaunchpadModel.appById(entry.id) : null
                                    readonly property bool selected: win.currentCellIndex === absIndex
                                    readonly property bool isDragSrc: win.dragActive && win.dragIndex === absIndex && !win.searching
                                    readonly property bool isFolderCand: win.folderCandidate === absIndex && !win.searching
                                    readonly property bool isEscapeMergeTarget:
                                        win.folderDragEscaped && win.folderEscapeMergeEligible
                                        && win.folderEscapeHoverIndex === absIndex

                                    // Keyboard selection box (mouse never shows it).
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width - 14
                                        height: parent.height - 14
                                        radius: 18
                                        visible: cell.entry && win.kbHighlight && cell.selected
                                        color: Qt.rgba(1, 1, 1, 0.18)
                                    }

                                    // Body — the app/folder tile (icon + label). Sized to the
                                    // icon, not the whole cell, so only the tile is clickable.
                                    // All input handlers live here for that reason. Jiggles in
                                    // edit mode.
                                    Item {
                                        id: body
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - 16, 104)
                                        height: Math.min(parent.height - 12, 96)
                                        opacity: cell.isDragSrc ? 0 : 1
                                        scale: (cell.isFolderCand || cell.isEscapeMergeTarget) ? 1.12
                                            : ((tileTap.pressed || tileDrag.active) ? ThemeService.pressScale : 1.0)
                                        Behavior on scale { AppleSpring { spring: 13 } }

                                        readonly property bool jigEnabled: win.editing && win.openFolder < 0
                                            && !win.searching
                                            && cell.entry !== null && !cell.isDragSrc && !tileDrag.active
                                        readonly property real jigAmp: 1.35 + (cell.index % 5) * 0.08
                                        property real jigTarget: 0
                                        rotation: jigEnabled ? jigTarget : 0
                                        onJigEnabledChanged: jigTarget = jigEnabled
                                            ? ((cell.index % 2 === 0) ? jigAmp : -jigAmp) : 0
                                        Behavior on rotation {
                                            AppleSpring {
                                                id: jigMotion
                                                spring: 22
                                                damping: ThemeService.momentumDamping
                                                epsilon: 0.04
                                                onRunningChanged: if (!running && body.jigEnabled)
                                                    Qt.callLater(() => body.jigTarget = body.jigTarget > 0
                                                        ? -body.jigAmp : body.jigAmp)
                                            }
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 5
                                            width: parent.width
                                            visible: cell.entry !== null

                                            // App icon, or folder mini-grid.
                                            Item {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 56; height: 56

                                                Icons.AppIcon {
                                                    anchors.fill: parent
                                                    visible: cell.isApp
                                                    sourceSize.width: 56; sourceSize.height: 56
                                                    iconName: cell.isApp ? win._iconNameFor(cell.app) : ""
                                                    desktopId: cell.isApp && cell.entry ? cell.entry.id : ""
                                                    smooth: true; mipmap: true
                                                    fillMode: Image.PreserveAspectFit

                                                    // Dark-grey mask over apps blocked during a focus phase.
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: cell.isApp && cell.entry
                                                            && !Bar.ClockService.isAppAllowed(cell.entry.id)
                                                        radius: 13
                                                        color: Qt.rgba(0.10, 0.10, 0.11, 0.60)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰌾"
                                                            color: Qt.rgba(1, 1, 1, 0.85)
                                                            font.family: "JetBrainsMono Nerd Font Propo"
                                                            font.pixelSize: 22
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: cell.isFolder
                                                    radius: 14
                                                    color: Qt.rgba(1, 1, 1, 0.13)
                                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                                    border.width: 1
                                                    Grid {
                                                        anchors.centerIn: parent
                                                        columns: 3
                                                        rowSpacing: 3; columnSpacing: 3
                                                        Repeater {
                                                            model: cell.isFolder ? Math.min(9, cell.entry.apps.length) : 0
                                                            delegate: Icons.AppIcon {
                                                                required property int index
                                                                readonly property var miniApp:
                                                                    LaunchpadModel.appById(cell.entry.apps[index])
                                                                width: 13; height: 13
                                                                sourceSize.width: 26; sourceSize.height: 26
                                                                iconName: win._iconNameFor(miniApp)
                                                                desktopId: miniApp ? miniApp.id : ""
                                                                smooth: true; mipmap: true
                                                                fillMode: Image.PreserveAspectFit
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: parent.width
                                                text: cell.isApp ? (cell.app ? cell.app.name : "")
                                                    : (cell.isFolder ? cell.entry.name : "")
                                                color: "#ffffff"
                                                font.family: "SF Pro Display"
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                            }
                                        }

                                        // Pointing-hand cursor over the tile only (NoButton so
                                        // taps/drags still reach the handlers). Also marks mouse mode.
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: cell.entry !== null
                                            acceptedButtons: Qt.NoButton
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onContainsMouseChanged: if (containsMouse) win.inputMode = "mouse"
                                        }

                                        // Tap: launch / open folder; long-press: enter edit mode.
                                        TapHandler {
                                            id: tileTap
                                            enabled: cell.entry !== null
                                            longPressThreshold: 0.4
                                            onTapped: {
                                                if (win.editing && !win.searching) {
                                                    if (cell.isFolder) win.openFolderAt(cell.absIndex)
                                                } else {
                                                    win.activateIndex(cell.absIndex)
                                                }
                                            }
                                            onLongPressed: if (!win.editing && !win.searching) win.editing = true
                                        }

                                        // Drag to reorder / make folders. Available
                                        // immediately — no need to enter edit mode
                                        // first; grabbing an icon and moving it past
                                        // the threshold starts the drag right away.
                                        DragHandler {
                                            id: tileDrag
                                            target: null
                                            dragThreshold: 8
                                            enabled: !win.searching && cell.entry !== null
                                            onActiveChanged: {
                                                if (active) {
                                                    let centre = body.mapToItem(null, body.width / 2, body.height / 2)
                                                    win._beginDrag(cell.absIndex, centroid.scenePosition,
                                                        centroid.scenePressPosition, centre)
                                                }
                                                else win._endDrag(false)
                                            }
                                            onCentroidChanged: if (active) win._updateDrag(centroid.scenePosition)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } // pageWrapper

        // ── Page indicator dots ──────────────────────────────────────────
        Row {
            id: pageDots
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36
                + (Dock.DockService.dockEdge === "bottom" ? win.dockReserve : 0)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: Dock.DockService.dockEdge === "left"
                ? win.dockReserve / 2
                : Dock.DockService.dockEdge === "right" ? -win.dockReserve / 2 : 0
            spacing: 8
            visible: win.pageCount > 1

            Repeater {
                model: win.pageCount
                delegate: Rectangle {
                    required property int index
                    width: 7; height: 7; radius: 999
                    color: index === pages.currentIndex ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.30)
                    scale: dotMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 13 } }
                    MouseArea {
                        id: dotMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pages.currentIndex = index
                    }
                }
            }
        }

        // The dock itself is the one real DockWindow, raised above this backdrop
        // while the launchpad is open (see onShowChanged). The bottom strip is kept
        // clear for it (dockReserve) and acts as the drag-to-pin drop zone.

        // ── Empty state ──────────────────────────────────────────────────
        Text {
            visible: win.entryCount === 0
            anchors.centerIn: parent
            text: win.query !== "" ? "No results" : "Loading…"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: "SF Pro Display"
            font.pixelSize: 16
        }
    }

    // ── Floating drag proxy ──────────────────────────────────────────────
    Item {
        id: dragProxy
        visible: win.dragActive && win.dragIndex >= 0 && !win.searching
        z: 2000
        width: 56; height: 56
        x: win.dragPos.x - width / 2
        y: win.dragPos.y - height / 2
        scale: 1.15
        opacity: 0.92
        readonly property var ent: (win.dragIndex >= 0 && win.dragIndex < LaunchpadModel.items.length)
            ? LaunchpadModel.items[win.dragIndex] : null

        Icons.AppIcon {
            anchors.fill: parent
            visible: dragProxy.ent && dragProxy.ent.type === "app"
            sourceSize.width: 56; sourceSize.height: 56
            readonly property var dragApp: (dragProxy.ent && dragProxy.ent.type === "app")
                ? LaunchpadModel.appById(dragProxy.ent.id) : null
            iconName: dragApp ? win._iconNameFor(dragApp) : ""
            desktopId: dragApp ? dragApp.id : ""
            smooth: true; mipmap: true
            fillMode: Image.PreserveAspectFit
        }
        Rectangle {
            anchors.fill: parent
            visible: dragProxy.ent && dragProxy.ent.type === "folder"
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.18)
            Grid {
                anchors.centerIn: parent
                columns: 3; rowSpacing: 3; columnSpacing: 3
                Repeater {
                    model: (dragProxy.ent && dragProxy.ent.type === "folder")
                        ? Math.min(9, dragProxy.ent.apps.length) : 0
                    delegate: Icons.AppIcon {
                        required property int index
                        readonly property var miniApp:
                            LaunchpadModel.appById(dragProxy.ent.apps[index])
                        width: 13; height: 13
                        iconName: win._iconNameFor(miniApp)
                        desktopId: miniApp ? miniApp.id : ""
                        smooth: true; mipmap: true; fillMode: Image.PreserveAspectFit
                    }
                }
            }
        }
    }

    // ── Folder open view (almost full-screen; the grid is hidden behind) ──
    Item {
        id: folderView
        anchors.fill: parent
        visible: win.openFolder >= 0 || folderStack.opacity > 0.002
        z: 1500

        readonly property var folder: (win.openFolder >= 0 && win.openFolder < LaunchpadModel.items.length
            && LaunchpadModel.items[win.openFolder] && LaunchpadModel.items[win.openFolder].type === "folder")
            ? LaunchpadModel.items[win.openFolder] : null
        readonly property int appCount: (folder && folder.apps) ? folder.apps.length : 0
        readonly property int perPage: 35           // 7 columns × 5 rows
        readonly property int pageCount: Math.max(1, Math.ceil((appCount || 0) / perPage))
        readonly property int rowsShown: Math.min(5, Math.max(1, Math.ceil(Math.min(appCount || 0, perPage) / 7)))
        // Reset to the first page each time a folder opens (runtime only, so the
        // SwipeView already exists — avoids a construction-time reference error).
        Connections {
            target: win
            function onOpenFolderChanged() {
                if (win.openFolder < 0) {
                    win._endFolderDrag(true)
                    return
                }
                win._pageSnap = true
                folderSwipe.currentIndex = 0
                win._pageSnap = false
            }
        }

        // Click anywhere outside the panel closes the folder.
        MouseArea { anchors.fill: parent; enabled: win.openFolder >= 0; onPressed: win.openFolder = -1 }

        Column {
            id: folderStack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenterOffset: Dock.DockService.dockEdge === "left"
                ? win.dockReserve / 2
                : Dock.DockService.dockEdge === "right" ? -win.dockReserve / 2 : 0
            anchors.verticalCenterOffset: Dock.DockService.dockEdge === "bottom"
                ? -win.dockReserve / 2 : 0
            width: parent.width
            spacing: 20
            opacity: win.openFolder >= 0 && !win.folderDragEscaped ? 1 : 0
            scale: win.openFolder >= 0 && !win.folderDragEscaped ? 1 : 0.96
            transformOrigin: Item.Center
            Behavior on opacity { AppleSpring { spring: 13 } }
            Behavior on scale { AppleSpring { spring: 13 } }

            // Editable folder title (above the panel, like macOS/iOS).
            TextField {
                id: folderName
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(440, Math.max(160, implicitWidth + 24))
                horizontalAlignment: TextInput.AlignHCenter
                background: null
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 24
                font.weight: Font.DemiBold
                font.letterSpacing: -0.35
                text: folderView.folder ? folderView.folder.name : ""
                onEditingFinished: if (win.openFolder >= 0) LaunchpadModel.renameFolder(win.openFolder, text)
                Keys.onEscapePressed: win.openFolder = -1
            }

            // Large translucent panel holding the folder's apps — nearly full
            // width, a 7×5 grid per page that pages sideways when it overflows.
            Rectangle {
                id: folderPanel
                anchors.horizontalCenter: parent.horizontalCenter
                width: win.width * 0.92
                readonly property int pad: 30
                readonly property real innerW: width - pad * 2
                readonly property real cellW: innerW / 7      // spreads icons across the width
                readonly property int cellH: 132
                height: folderView.rowsShown * cellH + pad * 2 + (folderView.pageCount > 1 ? 26 : 0)
                radius: 34
                color: ThemeService.bg
                border.color: win.folderDragOutside
                    ? Qt.rgba(1, 1, 1, 0.44) : ThemeService.stroke
                border.width: 1

                MouseArea { anchors.fill: parent }   // swallow clicks inside the panel

                HorizontalPagerWheel {
                    anchors.fill: parent
                    pager: folderSwipe
                    pagesTotal: folderView.pageCount
                }

                SwipeView {
                    id: folderSwipe
                    anchors {
                        top: parent.top; left: parent.left; right: parent.right
                        topMargin: folderPanel.pad; leftMargin: folderPanel.pad; rightMargin: folderPanel.pad
                    }
                    height: folderView.rowsShown * folderPanel.cellH
                    clip: false
                    interactive: !win.folderDragActive

                    contentItem: ListView {
                        id: folderFlick
                        model: folderSwipe.contentModel
                        interactive: folderSwipe.interactive
                        focus: folderSwipe.focus
                        orientation: Qt.Horizontal
                        // Same treatment as the main pager: the contentX binding is the
                        // sole programmatic driver (highlight-range scrolling bypassed the
                        // Behavior and jumped); real drags sync the index back on settle.
                        contentX: folderSwipe.currentIndex * width
                        onMovementEnded: folderSwipe.currentIndex =
                            Math.max(0, Math.min(folderSwipe.count - 1, Math.round(contentX / width)))
                        snapMode: ListView.SnapOneItem
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        boundsMovement: Flickable.FollowBoundsBehavior
                        cacheBuffer: width
                        maximumFlickVelocity: 4 * width
                        rebound: Transition {
                            SpringAnimation {
                                properties: "x,y"
                                spring: 18
                                damping: ThemeService.momentumDamping
                                epsilon: 0.25
                            }
                        }
                        Behavior on contentX {
                            enabled: !win._pageSnap && !folderFlick.dragging && !folderFlick.flicking
                            AppleSpring { spring: 18; epsilon: 0.25 }
                        }
                    }

                    Repeater {
                        model: folderView.pageCount
                        delegate: Item {
                            id: fpage
                            required property int index   // page index
                            width: folderSwipe.width
                            height: folderSwipe.height
                            readonly property int pageStart: index * folderView.perPage
                            readonly property int pageEnd: Math.min(pageStart + folderView.perPage, folderView.appCount)

                            Grid {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                columns: 7
                                Repeater {
                                    model: Math.max(0, fpage.pageEnd - fpage.pageStart)
                                    delegate: Item {
                                        id: fcell
                                        required property int index   // within page
                                        width: folderPanel.cellW
                                        height: folderPanel.cellH
                                        readonly property int appIndex: fpage.pageStart + index
                                        readonly property string appId: folderView.folder ? folderView.folder.apps[appIndex] : ""
                                        readonly property var fapp: LaunchpadModel.appById(fcell.appId)
                                        readonly property int displaySlot:
                                            win.folderDragDisplaySlot(appIndex, fpage.pageStart)
                                        opacity: win.folderDragActive && win.folderDragIndex === appIndex ? 0 : 1
                                        transform: Translate {
                                            x: ((fcell.displaySlot % 7) - (fcell.index % 7)) * folderPanel.cellW
                                            y: (Math.floor(fcell.displaySlot / 7)
                                                - Math.floor(fcell.index / 7)) * folderPanel.cellH
                                            Behavior on x { AppleSpring { spring: 16; epsilon: 0.15 } }
                                            Behavior on y { AppleSpring { spring: 16; epsilon: 0.15 } }
                                        }

                                        Item {
                                            id: ftile
                                            anchors.centerIn: parent
                                            width: 104; height: 112
                                            scale: (folderTap.pressed || folderDragHandler.active)
                                                ? ThemeService.pressScale : 1.0
                                            Behavior on scale { AppleSpring { spring: 13 } }

                                            readonly property bool jigEnabled: win.editing && win.openFolder >= 0
                                                && !(win.folderDragActive
                                                    && win.folderDragIndex === fcell.appIndex)
                                                && !folderDragHandler.active
                                            readonly property real jigAmp: 1.35 + (fcell.index % 5) * 0.08
                                            property real jigTarget: 0
                                            rotation: jigEnabled ? jigTarget : 0
                                            onJigEnabledChanged: jigTarget = jigEnabled
                                                ? ((fcell.index % 2 === 0) ? jigAmp : -jigAmp) : 0
                                            Behavior on rotation {
                                                AppleSpring {
                                                    spring: 22
                                                    damping: ThemeService.momentumDamping
                                                    epsilon: 0.04
                                                    onRunningChanged: if (!running && ftile.jigEnabled)
                                                        Qt.callLater(() => ftile.jigTarget = ftile.jigTarget > 0
                                                            ? -ftile.jigAmp : ftile.jigAmp)
                                                }
                                            }

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 7
                                                width: parent.width
                                                Icons.AppIcon {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 72; height: 72
                                                    sourceSize.width: 72; sourceSize.height: 72
                                                    iconName: win._iconNameFor(fcell.fapp)
                                                    desktopId: fcell.appId
                                                    smooth: true; mipmap: true; fillMode: Image.PreserveAspectFit

                                                    // Dark-grey mask over apps blocked during a focus phase.
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: fcell.fapp && fcell.appId
                                                            && !Bar.ClockService.isAppAllowed(fcell.appId)
                                                        radius: 16
                                                        color: Qt.rgba(0.10, 0.10, 0.11, 0.60)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰌾"
                                                            color: Qt.rgba(1, 1, 1, 0.85)
                                                            font.family: "JetBrainsMono Nerd Font Propo"
                                                            font.pixelSize: 28
                                                        }
                                                    }
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: parent.width
                                                    text: fcell.fapp ? fcell.fapp.name : ""
                                                    color: "#ffffff"
                                                    font.family: "SF Pro Display"
                                                    font.pixelSize: 12
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 2
                                                    wrapMode: Text.Wrap
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: fcell.fapp !== null
                                                acceptedButtons: Qt.NoButton
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }

                                            TapHandler {
                                                id: folderTap
                                                enabled: fcell.fapp !== null
                                                longPressThreshold: 0.4
                                                onTapped: if (!win.editing && fcell.fapp)
                                                    win.launchById(fcell.appId)
                                                onLongPressed: if (!win.editing) win.editing = true
                                            }

                                            DragHandler {
                                                id: folderDragHandler
                                                target: null
                                                dragThreshold: 8
                                                enabled: fcell.fapp !== null
                                                onActiveChanged: {
                                                    if (active) {
                                                        let centre = ftile.mapToItem(null,
                                                            ftile.width / 2, ftile.height / 2)
                                                        win._beginFolderDrag(fcell.appIndex,
                                                            centroid.scenePosition,
                                                            centroid.scenePressPosition, centre)
                                                    } else if (win.folderDragActive
                                                            && win.folderDragIndex === fcell.appIndex) {
                                                        win._endFolderDrag(false)
                                                    }
                                                }
                                                onCentroidChanged: if (active)
                                                    win._updateFolderDrag(centroid.scenePosition)
                                            }

                                            // Remove-from-folder badge (edit mode).
                                            Rectangle {
                                                anchors { top: parent.top; left: parent.left; leftMargin: 8 }
                                                width: 24; height: 24; radius: 12
                                                visible: win.editing
                                                color: rmMa.containsMouse ? "#ff5b54" : Qt.rgba(0, 0, 0, 0.72)
                                                border.color: Qt.rgba(1, 1, 1, 0.7); border.width: 1
                                                scale: rmMa.pressed ? ThemeService.pressScale : 1.0
                                                Behavior on scale { AppleSpring { spring: 13 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "×"; color: "#ffffff"
                                                    font.family: "SF Pro Display"; font.pixelSize: 16
                                                }
                                                MouseArea {
                                                    id: rmMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let fi = win.openFolder
                                                        let id = fcell.appId
                                                        if (folderView.folder && folderView.folder.apps.length <= 2) win.openFolder = -1
                                                        LaunchpadModel.removeFromFolder(fi, id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Folder page dots.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 13
                    spacing: 7
                    visible: folderView.pageCount > 1
                    Repeater {
                        model: folderView.pageCount
                        delegate: Rectangle {
                            required property int index
                            width: 7; height: 7; radius: 999
                            color: index === folderSwipe.currentIndex ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.35)
                            scale: folderDotMa.pressed ? ThemeService.pressScale : 1.0
                            Behavior on scale { AppleSpring { spring: 13 } }
                            MouseArea {
                                id: folderDotMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: folderSwipe.currentIndex = index
                            }
                        }
                    }
                }
            }

        }

        Item {
            id: folderDragProxy
            visible: win.folderDragActive && folderView.folder && win.folderDragIndex >= 0
            z: 3000
            width: 72
            height: 72
            x: win.folderDragPos.x - width / 2
            y: win.folderDragPos.y - height / 2
            scale: win.folderDragOutside ? 1.18 : 1.12
            opacity: 0.94
            Behavior on scale { AppleSpring { spring: 18 } }
            readonly property string appId: win.folderDragAppId

            Icons.AppIcon {
                anchors.fill: parent
                sourceSize.width: 72
                sourceSize.height: 72
                readonly property var dragApp: folderDragProxy.appId !== ""
                    ? LaunchpadModel.appById(folderDragProxy.appId) : null
                iconName: dragApp ? win._iconNameFor(dragApp) : ""
                desktopId: dragApp ? dragApp.id : ""
                smooth: true
                mipmap: true
                fillMode: Image.PreserveAspectFit
            }
        }
    }
}
