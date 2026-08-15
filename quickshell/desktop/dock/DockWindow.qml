import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects
import "../missioncontrol" as MC
import "../icons" as Icons
import "../capture" as Capture

PanelWindow {
    id: win

    // Per-screen instance (shell.qml wraps this in Variants over Quickshell.screens),
    // so every monitor gets its own dock that reveals at its own bottom edge.
    required property var modelData
    screen: modelData

    readonly property string dockEdge: DockService.dockEdge
    readonly property bool horizontalDock: dockEdge === "bottom"
    readonly property bool leftDock: dockEdge === "left"
    readonly property bool rightDock: dockEdge === "right"
    readonly property bool verticalDock: !horizontalDock

    // Dedicated layer namespace so Hyprland layerrules can target the dock alone.
    // Without this, the dock shares "quickshell" with the bar/osd/nc, and the
    // global `animation slide top` rule re-runs every time the dock's height
    // changes (preview open/close).
    WlrLayershell.namespace: "qs-dock"
    // Overlay layer so the dock stays visible over fullscreen windows.
    WlrLayershell.layer: WlrLayer.Overlay

    // Anchor to the full bottom strip so the layer surface always spans the
    // screen width. With only `bottom: true` the surface auto-sized to
    // implicitWidth and re-centered when the preview opened — that shifted
    // the dock card and made the cached previewAnchorX point at the icon's
    // OLD position, so the arrow rendered under the wrong icon.
    anchors.top: verticalDock
    anchors.bottom: true
    anchors.left: horizontalDock || leftDock
    anchors.right: horizontalDock || rightDock
    exclusiveZone: pinnedEffective ? dockReservedThickness : 0
    color: "transparent"

    // Confine pointer input to the dock's own column (see triggerColumn): the
    // dock then reveals only when the cursor is over where it sits — not the
    // entire bottom edge — and the empty space to its left/right stays
    // click-through to the windows below. A preview grows the window and needs
    // its full surface (popup + click-outside-to-dismiss), so drop the mask
    // while one is open.
    mask: Capture.CaptureService.overlayActive ? captureInputRegion
        : (win.previewOpen || win.dragActive || win.sizeDragActive) ? null : dockRegion
    Region { id: dockRegion; item: triggerColumn }
    Region { id: captureInputRegion }

    readonly property bool dark: ThemeService.isDark
    // Contextual surfaces acknowledge dismissal on pointer-down, then finish a
    // short non-bouncy fade. The old spring's long epsilon tail kept an
    // apparently closed menu mapped for roughly 700ms.
    readonly property int popupEnterDuration: 135
    readonly property int popupExitDuration: 90

    // ── Preview state ──────────────────────────────────────────────────────

    property bool previewOpen: false
    property string previewWmClass: ""
    property string previewIconName: ""
    property var previewWindows: []  // [{address, title}]
    property bool previewInstantClose: false
    // Anchor X (in this PanelWindow's coordinate space) of the clicked icon's center
    property real previewAnchorX: 0
    property real previewAnchorY: 0

    function selectPreviewWindow(address) {
        previewInstantClose = true
        previewOpen = false
        focusAddrProc.addr = address
        focusAddrProc.running = true
        Qt.callLater(() => previewInstantClose = false)
    }

    // Toggle: same icon click closes, different icon click switches.
    // Opens INSTANTLY using DockService data — no screenshot/grim, no spawn delay.
    function togglePreview(wmClass, iconName, anchorX, anchorY) {
        win.closeUtilityMenu()
        if (previewOpen && previewWmClass === wmClass) {
            previewOpen = false
            return
        }
        let cached = DockService.clientsByClass[wmClass.toLowerCase()] || []
        let cleaned = cached
            .filter(c => c && c.size && c.size[0] > 0 && c.size[1] > 0)
            .map(c => ({ address: c.address, title: c.title || wmClass }))
        if (cleaned.length === 0) return

        previewWmClass = wmClass
        previewIconName = iconName
        previewWindows = cleaned
        previewAnchorX = anchorX
        previewAnchorY = anchorY
        previewOpen = true
        showDock = true
        hideTimer.stop()
    }

    // Preview grid sizing: up to 4 columns, wrap to multiple rows
    readonly property int previewCols: verticalDock ? 1
        : Math.min(4, Math.max(1, previewWindows.length))
    readonly property int previewRows: Math.ceil(previewWindows.length / Math.max(1, previewCols))
    readonly property int cardW: 200
    readonly property int cardH: 96
    readonly property int cardSpacing: 8
    readonly property int previewPadding: 12

    // The clicked icon magnifies ~18px above the dock card's top edge while its
    // preview is open (see DockItem: hoverScale 1.75, 42px icon growing upward).
    // Lift the popup — and add matching headroom to the panel — so it sits just
    // above the enlarged icon, the tail meeting its top rather than overlapping.
    readonly property real previewIconLift: 20 * dockScale

    // FIXED tall surface. The dock card lives at the bottom; previews and the
    // right-click menu draw into the headroom above. Crucially the surface size
    // never changes when a popup opens — previously the panel grew from 128 to
    // ~400px, which reconfigured the Wayland layer every time and made the whole
    // dock visibly blink / stutter instead of the popup just appearing. A
    // constant height also gives the Move-to-Workspace flyout room so it no
    // longer gets clipped at the screen edge.
    readonly property int panelDepth: 480
    implicitHeight: horizontalDock ? panelDepth : 1
    implicitWidth: verticalDock ? panelDepth : 1
    // Full width comes from the left+right anchors, so implicitWidth is moot —
    // popups are positioned in absolute (screen-width) coordinates below.

    // ── Auto-hide ──────────────────────────────────────────────────────────

    property bool showDock: false
    // Icons currently mid-launch-bounce. Keeps the dock revealed for the whole
    // bounce so a launching app never animates against a hidden/retracting dock.
    property int launchingCount: 0
    // DockService.pinnedVisible (toggled by Super+V) keeps the dock down for good,
    // macOS "Turn Hiding Off" style — otherwise it auto-hides as before.
    // Hide by sliding the dock card off the bottom, leaving a ~4px trigger sliver.
    // Offset is tied to the trigger band height (not the full surface) so the now
    // much taller surface still tucks away with a short, natural slide.
    // While the launchpad is open on THIS screen the dock rises and stays put —
    // it's the one real dock, floating above the launchpad backdrop (no replica).
    readonly property bool launchpadSurfaceHere:
        DockService.launchpadOpen
        && DockService.launchpadScreen === (win.modelData ? win.modelData.name : "")
    readonly property bool overviewHere:
        DockService.overviewOpen
        && (DockService.overviewScreen === ""
            || DockService.overviewScreen === (win.modelData ? win.modelData.name : ""))
    // True while THIS screen's active workspace has a real fullscreen window
    // (game, video player, etc.) — see poll-clients.sh. Even with "Turn Hiding
    // Off" pinned on, the dock should still tuck away here so it doesn't sit
    // over fullscreen content; it still reveals on hover like the normal
    // auto-hide dock.
    readonly property bool fullscreenHere:
        DockService.fullscreenMonitors.includes(win.modelData ? win.modelData.name : "")
    // True while THIS screen's active workspace is a Mission-Control Split View
    // space — treated like fullscreen: the dock tucks away (still hover-
    // revealable) and its reserved zone is released so the split tiles get the
    // full screen.
    readonly property bool splitViewHere:
        MC.MCService.splitViewActiveOn(win.modelData ? win.modelData.name : "")
    // The pinned/always-visible toggle (Super+V), minus fullscreen/split-view —
    // so those always win over "pinned".
    readonly property bool pinnedEffective:
        DockService.pinnedVisible && !fullscreenHere && !splitViewHere
    readonly property int dockVisibleMargin: 10
    readonly property real dockHiddenMargin: -(dockTriggerH - 4)
    readonly property real dockCardThickness: 68 * dockScale
    readonly property int dockReservedThickness: Math.ceil(dockCardThickness)

    // Keep independent Dock interactions on their existing spring. Mission
    // Control is intentionally excluded: its continuous progress is composed
    // below without another animation filtering or delaying it.
    readonly property bool dockHeldRaised:
        pinnedEffective
        || (overviewHere && DockService.pinnedVisible)
        || launchpadSurfaceHere || showDock || previewOpen
        || menuOpen || utilityMenuOpen || dragActive || sizeDragActive
        || externalDragActive || launchingCount > 0
    property real autoHideMargin: dockHeldRaised
        ? dockVisibleMargin : dockHiddenMargin
    Behavior on autoHideMargin {
        AppleSpring {
            spring: win.dockHeldRaised ? 22 : 13
            epsilon: 0.25
        }
    }

    readonly property real overviewRevealProgress:
        Math.max(0, Math.min(1, DockService.overviewProgress))
    readonly property real overviewMargin:
        overviewHere && !DockService.pinnedVisible
        ? dockHiddenMargin
          + (dockVisibleMargin - dockHiddenMargin) * overviewRevealProgress
        : dockHiddenMargin
    // Whichever system currently asks for more visibility wins. With no hover
    // or menu hold, an unpinned Dock now reaches its hidden endpoint on the
    // exact same frame as Mission Control reaches progress zero.
    readonly property real edgeMargin: Math.max(autoHideMargin, overviewMargin)
    margins.bottom: horizontalDock ? edgeMargin : 0
    margins.left: leftDock ? edgeMargin : 0
    margins.right: rightDock ? edgeMargin : 0

    // Launchpad can map a new Overlay surface after this one, so an auto-hidden
    // Dock may still need the re-map below. Mission Control's transparent surface
    // is persistent and was created before this Dock, so it never needs one.
    function remapAboveOverlay() {
        win.visible = false
        remapTimer.restart()
    }
    onLaunchpadSurfaceHereChanged: if (launchpadSurfaceHere && !pinnedEffective)
        win.remapAboveOverlay()
    Timer {
        id: remapTimer
        interval: 48   // let the unmap + overlay map settle, then re-map on top
        onTriggered: win.visible = true
    }

    Connections {
        target: Capture.CaptureService
        function onOverlayActiveChanged() {
            if (!Capture.CaptureService.overlayActive) return
            win.previewOpen = false
            win.closeMenu()
            win.closeUtilityMenu()
        }
    }

    // Edge trigger matching the Dock card's footprint. It follows the selected
    // side and leaves the rest of the large popup surface click-through.
    readonly property int dockTriggerH: 88
    Item {
        id: triggerColumn
        width: win.horizontalDock
            ? Math.min(win.availableDockLength, dockCard.width) : dockTriggerH
        height: win.horizontalDock
            ? dockTriggerH : Math.min(win.availableDockLength, dockCard.height)
        x: win.horizontalDock ? (parent.width - width) / 2
            : win.leftDock ? 0 : parent.width - width
        y: win.horizontalDock ? parent.height - height
            : (parent.height - height) / 2

        // An external file drag first reaches the four-pixel reveal strip while
        // the Dock is hidden. Accept it here only long enough to raise the Dock;
        // the TrashItem is the actual drop target once it slides into view.
        DropArea {
            id: dockRevealDrop
            anchors.fill: parent
            z: -1
            onEntered: (drag) => {
                if (!drag.hasUrls) {
                    drag.accepted = false
                    return
                }
                drag.accepted = true
                win.beginExternalDrag()
            }
            onExited: win.endExternalDragSoon()
            onDropped: (drop) => {
                drop.accepted = false
                win.endExternalDragSoon()
            }
        }
    }

    // Reveal / keep-open hover. Lives at the window level so it's an ancestor of
    // the dock card: ancestor handlers stay hovered while the cursor is over any
    // descendant, so the dock no longer retracts when you move onto the icons —
    // and the per-icon HoverHandlers beneath still fire, driving the hover zoom.
    // The mask already limits hover delivery to the dock column, so targeting the
    // whole window doesn't re-introduce the "reveal anywhere on the edge" bug.
    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop()
                win.showDock = true
            } else if (!win.previewOpen && !win.menuOpen && !win.dragActive) {
                hideTimer.restart()
            }
        }
    }

    Timer { id: hideTimer; interval: 400; onTriggered: win.showDock = false }

    property bool externalDragActive: false
    function beginExternalDrag() {
        externalDragEndTimer.stop()
        externalDragActive = true
        showDock = true
        hideTimer.stop()
    }
    function endExternalDragSoon() { externalDragEndTimer.restart() }
    Timer {
        id: externalDragEndTimer
        interval: 180
        onTriggered: {
            win.externalDragActive = false
            if (!hoverHandler.hovered && !win.previewOpen && !win.menuOpen)
                hideTimer.restart()
        }
    }

    // ── Pinned apps ────────────────────────────────────────────────────────

    // Pinned state lives in DockService — the single source of truth shared with
    // the launchpad — so a pin made in either place shows up here instantly. This
    // window is just a view + thin delegates over it.
    readonly property var pinnedApps: DockService.pinnedApps
    readonly property var pinnedClasses: DockService.pinnedClasses

    function isPinned(cls)        { return DockService.isPinned(cls) }
    function pinApp(app)          { DockService.pinApp(app) }
    function unpinApp(cls)        { DockService.unpinApp(cls) }
    function pinAppAt(app, idx)   { DockService.pinAppAt(app, idx) }

    // ── Drag to reorder / pin / unpin ────────────────────────────────────────
    // Press ANY dock icon and drag. Drop in the pinned section to pin/reorder;
    // drop past the separator (the running-apps side) to unpin. The model isn't
    // reassigned mid-drag (that would rebuild the Repeater and drop the grab) —
    // icons shift visually and the commit happens once, on release.
    property bool dragActive: false
    property var dragApp: ({})         // {name, wmClass, iconName, execCmd} being dragged
    property int dragSourceIndex: -1   // its pinned index, or -1 if it came from the running side
    property int dragSourceTransientIndex: -1
    property real dragDeltaAxis: 0     // travel along the Dock's current layout axis
    property int dropIndex: -1         // target pinned slot, or -1 = running side (unpin / no-op)
    readonly property real pitch: 60 * dockScale
    readonly property var rowItem: dockRow   // pointer maths happen in this Grid's coords
    readonly property bool nativePinDropActive:
        dragActive && dragSourceIndex < 0 && dropIndex >= 0
    readonly property real pinSeparatorShift: nativePinDropActive ? pitch : 0
    // Reverse of pinSeparatorShift: when a pinned app crosses into the transient
    // side, collapse its old pinned slot and move only the separator toward it.
    // The unpinned icons stay put, leaving a real one-icon landing space between
    // them and the animated divider.
    readonly property bool pinnedUnpinDropActive: dragActive
        && dragSourceIndex >= 0 && dropIndex < 0
        && !DockService.isPermanent(dragApp.wmClass || "")
    readonly property real unpinSeparatorShift: pinnedUnpinDropActive ? -pitch : 0

    // ── Launchpad drag-to-pin: open a gap under the cursor ───────────────────
    // While the launchpad drags an app over this screen's dock, work out which
    // slot it would drop into from the cursor's screen X (DockService.launchpadDragX)
    // mapped into dockRow. Pinned icons at/after that slot slide aside (DockItem),
    // and the slot is published back so the launchpad pins exactly there on drop.
    readonly property bool launchpadDropActive: DockService.launchpadDragActive
        && DockService.launchpadScreen === (win.screen ? win.screen.name : "")
    readonly property int launchpadDropIndex: {
        if (!launchpadDropActive) return -1
        let local = dockRow.mapFromItem(null,
            DockService.launchpadDragX, DockService.launchpadDragY)
        let rowAxis = win.horizontalDock ? local.x : local.y
        let n = win.pinnedApps.length
        return Math.max(0, Math.min(n, Math.round(rowAxis / pitch)))
    }
    readonly property real launchpadRightSideShift: launchpadDropActive ? pitch / 2 : 0
    onLaunchpadDropIndexChanged: if (launchpadDropActive) DockService.launchpadDropIndex = launchpadDropIndex

    function beginDrag(app, sourceIndex: int, sourceTransientIndex: int) {
        win.previewOpen = false
        win.closeMenu()
        win.dragApp = app
        win.dragSourceIndex = sourceIndex
        win.dragSourceTransientIndex = sourceTransientIndex
        win.dragDeltaAxis = 0
        win.dropIndex = sourceIndex >= 0 ? sourceIndex : -1
        win.dragActive = true
        win.showDock = true
        hideTimer.stop()
        win.extraApps = win.extraApps   // break the binding → freeze the running list
    }
    // cursorAxis: pointer coordinate within dockRow's current layout axis.
    function updateDrag(deltaAxis, cursorAxis) {
        if (!win.dragActive) return
        win.dragDeltaAxis = deltaAxis
        let n = win.pinnedApps.length
        // Use the rendered separator itself as the source of truth. The old
        // n*pitch approximation drifted as the separator hit slot and Dock
        // scale changed, so a drop visibly past the line could still resolve
        // to a pinned slot.
        let separatorCenter = utilitySeparator.mapToItem(dockRow,
            utilitySeparator.width / 2, utilitySeparator.height / 2)
        let separatorAxis = win.horizontalDock
            ? separatorCenter.x : separatorCenter.y
        if (cursorAxis < separatorAxis)
            win.dropIndex = Math.max(0, Math.min(n, Math.round(cursorAxis / win.pitch)))
        else if (DockService.isPermanent(win.dragApp.wmClass))
            // Files may be reordered within the app side, but never dragged
            // across the structural separator and removed.
            win.dropIndex = Math.max(0, n - 1)
        else                                       // right of the app side → unpin
            win.dropIndex = -1
    }
    function endDrag() {
        let active = win.dragActive, src = win.dragSourceIndex, drop = win.dropIndex, app = win.dragApp
        // Clear state FIRST so every offset snaps to 0, then commit the change.
        win.dragActive = false
        win.dragSourceIndex = -1
        win.dragSourceTransientIndex = -1
        win.dropIndex = -1
        win.dragDeltaAxis = 0
        win.dragApp = ({})
        win.extraApps = Qt.binding(() => win._liveExtras)   // re-bind: track the live list again
        if (!active) return

        if (src >= 0) {                            // dragged a pinned app
            if (drop < 0) win.unpinApp((app.wmClass || "").toLowerCase())  // → running side: unpin
            else          DockService.reorderPins(src, drop)              // reorder within pinned
        } else if (drop >= 0) {                    // dragged a running app onto the pinned side: pin
            win.pinAppAt(app, drop)
        }
    }

    // ── Right-click menu state ───────────────────────────────────────────────

    property bool menuOpen: false
    property bool menuSurfaceVisible: false
    property var menuApp: ({})          // {name, wmClass, iconName, execCmd}
    property real menuAnchorX: 0        // clicked icon centre, panel coords
    property real menuAnchorY: 0
    property bool submenuOpen: false    // Assign-To flyout

    readonly property int menuWidth: 240
    readonly property int menuRowH: 30
    readonly property int menuSepH: 11
    readonly property int menuPadV: 6
    readonly property int submenuWidth: 180
    readonly property int submenuRowH: 28
    readonly property int submenuGap: 8
    readonly property int wsCount: 10

    readonly property string menuClass: (menuApp.wmClass || "").toLowerCase()
    readonly property var menuWindows: DockService.clientsByClass[menuClass] || []
    readonly property bool menuRunning: menuWindows.length > 0
    readonly property bool menuPinned: win.isPinned(menuClass)
    readonly property bool menuPermanent: DockService.isPermanent(menuClass)
    // A launch command for "New Window"/"Open": prefer the app's own, else guess.
    readonly property var menuExec: (menuApp.execCmd && menuApp.execCmd.length > 0)
        ? menuApp.execCmd : DockService._guessExec(menuApp.wmClass || "")
    // Set of workspace names this app currently has windows on — the Move-to-
    // Workspace flyout checks the workspace(s) where the app actually lives.
    readonly property var menuAppWorkspaces: {
        let s = ({})
        for (let i = 0; i < menuWindows.length; i++) s[String(menuWindows[i].ws || "")] = true
        return s
    }

    // Rows are rebuilt from app state; the menu adapts to running vs. pinned-idle.
    readonly property var menuRows: {
        let rows = []
        if (menuRunning) {
            rows.push({ id: "showall", label: menuWindows.length > 1 ? "Show All Windows" : "Show Window" })
            if (menuExec.length > 0) rows.push({ id: "newwin", label: "New Window" })
            let anyHidden = menuWindows.some(w => (w.ws || "") === "special:minimized")
            rows.push({ id: "hide", label: anyHidden ? "Unhide" : "Hide" })
            rows.push({ id: "assign", label: "Move to Workspace", arrow: true })
            rows.push({ id: "sep" })
            if (!menuPermanent) {
                rows.push({ id: "pin", label: "Keep in Dock", checked: menuPinned })
                rows.push({ id: "sep" })
            }
            rows.push({ id: "quit", label: "Quit" })
        } else {
            if (menuExec.length > 0) rows.push({ id: "newwin", label: "Open" })
            if (rows.length > 0) rows.push({ id: "sep" })
            if (!menuPermanent)
                rows.push({ id: "pin", label: "Keep in Dock", checked: menuPinned })
        }
        return rows
    }

    function _sumRowsH(rows) {
        let h = menuPadV * 2
        for (let i = 0; i < rows.length; i++) h += (rows[i].id === "sep" ? menuSepH : menuRowH)
        return h
    }
    readonly property int menuHeight: _sumRowsH(menuRows)
    readonly property int submenuHeight: wsCount * submenuRowH + menuPadV * 2

    // Vertical offset of the "Move to Workspace" row inside the menu — the flyout
    // top-aligns to it.
    function _assignRowOffset() {
        let h = 0
        for (let i = 0; i < menuRows.length; i++) {
            if (menuRows[i].id === "assign") break
            h += (menuRows[i].id === "sep" ? menuSepH : menuRowH)
        }
        return h
    }

    function openMenu(app, anchorX, anchorY) {
        win.previewOpen = false
        win.closeUtilityMenu()
        win.menuApp = app
        win.menuAnchorX = anchorX
        win.menuAnchorY = anchorY
        win.submenuOpen = false
        win.menuSurfaceVisible = true
        win.menuOpen = true
        win.showDock = true
        hideTimer.stop()
    }
    function closeMenu() { win.menuOpen = false; win.submenuOpen = false }

    // ── Separator / Trash context menu ─────────────────────────────────────
    property bool utilityMenuOpen: false
    property bool utilityMenuSurfaceVisible: false
    property string utilityMenuKind: ""
    property real utilityAnchorX: 0
    property real utilityAnchorY: 0
    readonly property int utilityMenuWidth: 236
    readonly property int utilityRowH: 34
    readonly property int utilitySepH: 11
    readonly property int utilitySliderH: 58
    readonly property int utilityPadV: 6
    readonly property var utilityMenuRows: {
        if (utilityMenuKind === "position") {
            let rows = [
                { id: "edge-bottom", label: "Position on Bottom", checked: win.horizontalDock },
                { id: "edge-left", label: "Position on Left", checked: win.leftDock },
                { id: "edge-right", label: "Position on Right", checked: win.rightDock },
                { id: "sep" },
                { id: "zoom-toggle", label: "Icon Zoom", toggle: true,
                    checked: DockService.iconZoomEnabled }
            ]
            if (DockService.iconZoomEnabled)
                rows.push({ id: "zoom-slider", label: "Zoom Amount", slider: true })
            return rows
        }
        if (utilityMenuKind === "trash-confirm") return [
            { id: "confirm-label", label: "Empty all items?", disabled: true },
            { id: "confirm-empty", label: "Empty Trash", destructive: true },
            { id: "confirm-cancel", label: "Cancel" }
        ]
        return [
            { id: "trash-open", label: "Open Trash" },
            { id: "sep" },
            { id: "trash-empty", label: "Empty Trash…", destructive: true,
                disabled: !trashItem.trashFull }
        ]
    }
    readonly property int utilityMenuHeight: {
        let h = utilityPadV * 2
        for (let i = 0; i < utilityMenuRows.length; i++)
            h += utilityRowHeight(utilityMenuRows[i])
        return h
    }

    function utilityRowHeight(row) {
        if (row.id === "sep") return utilitySepH
        if (row.slider === true) return utilitySliderH
        return utilityRowH
    }

    function previewZoomFromSlider(localX) {
        let trackLeft = 14
        let trackWidth = utilityMenuWidth - 28
        let t = Math.max(0, Math.min(1, (localX - trackLeft) / trackWidth))
        DockService.previewIconZoomScale(DockService.iconZoomMinimum
            + t * (DockService.iconZoomMaximum - DockService.iconZoomMinimum))
    }

    function openUtilityMenu(kind, anchorX, anchorY) {
        win.previewOpen = false
        win.closeMenu()
        win.utilityMenuKind = kind
        win.utilityAnchorX = anchorX
        win.utilityAnchorY = anchorY
        win.utilityMenuSurfaceVisible = true
        win.utilityMenuOpen = true
        win.showDock = true
        hideTimer.stop()
    }

    function closeUtilityMenu() { win.utilityMenuOpen = false }

    function utilityAction(id) {
        if (id === "edge-bottom" || id === "edge-left" || id === "edge-right") {
            DockService.setDockEdge(id.slice(5))
            win.closeUtilityMenu()
        } else if (id === "trash-open") {
            trashItem.openTrash()
            win.closeUtilityMenu()
        } else if (id === "trash-empty") {
            win.utilityMenuKind = "trash-confirm"
        } else if (id === "confirm-empty") {
            trashItem.emptyTrash()
            win.closeUtilityMenu()
        } else if (id === "confirm-cancel") {
            win.utilityMenuKind = "trash"
        } else if (id === "zoom-toggle") {
            DockService.setIconZoomEnabled(!DockService.iconZoomEnabled)
        }
    }

    // This Hyprland runs the Lua config/dispatch plugin, so classic
    // `hyprctl dispatch closewindow ...` is parsed as Lua and fails (the same
    // reason DockItem focuses via `hyprctl eval`). Everything below builds Lua
    // `hl.dispatch(hl.dsp.*)` statements and runs them through `hyprctl eval`.
    function _runHypr(stmts) {
        if (!stmts || stmts.length === 0) return
        menuActionProc.command = ["hyprctl", "eval", stmts.join("; ")]
        menuActionProc.running = true
    }
    function _focusWin(addr) {
        return 'hl.dispatch(hl.dsp.focus({ window = "address:' + addr + '" })); '
             + 'hl.dispatch(hl.dsp.window.bring_to_top({ window = "address:' + addr + '" }))'
    }
    function _closeWin(addr) {
        return 'hl.dispatch(hl.dsp.window.close({ window = "address:' + addr + '" }))'
    }
    // ws is a number (workspace id) or a string like "special:minimized".
    function _moveWin(addr, ws, follow) {
        let wsv = (typeof ws === "number") ? ws : '"' + ws + '"'
        return 'hl.dispatch(hl.dsp.window.move({ window = "address:' + addr
             + '", workspace = ' + wsv + ', follow = ' + (follow ? 'true' : 'false') + ' }))'
    }

    function _menuAction(id) {
        let cls = win.menuClass
        let wins = DockService.clientsByClass[cls] || []
        if (id === "showall") {
            if (wins.length > 1)
                win.togglePreview(win.menuApp.wmClass, win.menuApp.iconName,
                    win.menuAnchorX, win.menuAnchorY)
            else if (wins.length === 1)
                win._runHypr([ win._focusWin(wins[0].address) ])
        } else if (id === "newwin") {
            // Focus mode: don't let the context-menu Open/New Window bypass the
            // block (pin/unpin/quit stay available).
            if (DockService.focusActive && !DockService.isFocusAllowed(win.menuExec)) {
                DockService.notifyFocusBlocked(win.menuApp.name)
            } else if (win.menuExec.length > 0) {
                Quickshell.execDetached(win.menuExec)
            }
        } else if (id === "hide") {
            let hidden = wins.filter(w => (w.ws || "") === "special:minimized")
            if (hidden.length > 0) {
                let stmts = hidden.map(w => win._moveWin(w.address, DockService.activeWs, false))
                stmts.push(win._focusWin(hidden[0].address))
                win._runHypr(stmts)
            } else {
                win._runHypr(wins.map(w => win._moveWin(w.address, "special:minimized", false)))
            }
        } else if (id === "pin") {
            if (win.menuPinned) win.unpinApp(cls)
            else win.pinApp(win.menuApp)
        } else if (id === "quit") {
            win._runHypr(wins.map(w => win._closeWin(w.address)))
        }
        win.closeMenu()
    }

    function doMoveTo(ws) {
        let wins = DockService.clientsByClass[win.menuClass] || []
        if (wins.length > 0) {
            let stmts = wins.map(w => win._moveWin(w.address, ws, false))
            stmts.push('hl.dispatch(hl.dsp.focus({ workspace = ' + ws + ' }))')   // follow over
            win._runHypr(stmts)
        }
        win.closeMenu()
    }

    // Resolve a window class to a real icon-theme name. The dock only knows the
    // Hyprland window class, which often differs from the icon the .desktop
    // entry declares (e.g. class "code" → icon "visual-studio-code", not
    // "vscode"). heuristicLookup matches the class against desktop entries — the
    // same source the launchpad/spotlight icons come from — so the dock picks up
    // whatever icon those use. Falls back to the hand-mapped guess.
    function _iconForClass(m) {
        if (!m.exact) {
            let de = DesktopEntries.heuristicLookup(m.base)
            if (de && de.icon) return de.icon
        }
        return m.iconName
    }

    readonly property var _liveExtras: DockService.runningClasses
        .filter(cls => !pinnedClasses.includes(cls))
        .map(cls => {
            let m = DockService._remapClass(cls)
            return { name: m.name, wmClass: cls, iconName: _iconForClass(m), execCmd: [] }
        })
    // The Repeater binds to this. Normally it tracks _liveExtras, but during a
    // drag the binding is broken (see beginDrag/endDrag) so the 500ms poll can't
    // reassign it, rebuild the Repeater, and tear the grabbed icon off the cursor.
    property var extraApps: _liveExtras

    // ── User sizing ────────────────────────────────────────────────────────
    // Store a normalized preference, then map it to monitor-relative logical
    // pixels. This keeps a 4K/HiDPI Dock proportional without blindly scaling
    // physical pixels, and prevents either a toy-sized or screen-filling Dock.
    readonly property real screenShortSide: Math.max(1, Math.min(
        win.modelData ? win.modelData.width : 1200,
        win.modelData ? win.modelData.height : 1200))
    // Compact floor, still bounded so targets remain usable on small displays.
    readonly property real minimumIconSize: Math.max(24,
        Math.min(32, screenShortSide * 0.022))
    // 25% below the previous 64–88px / 6%-of-short-edge ceiling.
    readonly property real maximumIconSize: Math.max(48,
        Math.min(66, screenShortSide * 0.045))
    property bool sizeDragActive: false
    property bool separatorHoverActive: false
    readonly property bool separatorInteractionActive:
        separatorHoverActive || sizeDragActive
    property real sizeDragIconSize: 42
    property real sizeDragStartIconSize: 42
    property point sizeDragStartPoint: Qt.point(0, 0)

    function beginSizeDrag(point) {
        utilityMenuOpen = false
        sizeDragStartPoint = point
        sizeDragStartIconSize = 42 * dockScale
        sizeDragIconSize = sizeDragStartIconSize
        sizeDragActive = true
        showDock = true
        hideTimer.stop()
    }

    function updateSizeDrag(point) {
        if (!sizeDragActive) return
        let inward = horizontalDock ? sizeDragStartPoint.y - point.y
            : leftDock ? point.x - sizeDragStartPoint.x
            : sizeDragStartPoint.x - point.x
        // The user explicitly wants a hard physical stop at both limits: keep
        // following the pointer until the bound, then do not overshoot at all.
        sizeDragIconSize = Math.max(minimumIconSize,
            Math.min(maximumIconSize, sizeDragStartIconSize + inward * 0.58))
    }

    function endSizeDrag() {
        if (!sizeDragActive) return
        let committed = Math.max(minimumIconSize,
            Math.min(maximumIconSize, sizeDragIconSize))
        let level = (committed - minimumIconSize)
            / Math.max(1, maximumIconSize - minimumIconSize)
        DockService.setDockSizeLevel(level)
        sizeDragActive = false
    }

    readonly property int dockAppIconCount:
        pinnedApps.length + extraApps.length
    // Trash is a permanent utility item after the permanent divider.
    readonly property int dockIconCount: dockAppIconCount + 1
    readonly property int dockRowChildCount:
        dockIconCount + 1
    readonly property int magnifiedSlotReserve: dockIconCount > 0
        ? Math.min(dockIconCount, Math.max(1, launchingCount + 1)) : 0
    readonly property real nominalRowLength:
        dockIconCount * 58
        + 26
        + Math.max(0, dockRowChildCount - 1) * 2
    readonly property real nominalMagnifyExtra:
        magnifiedSlotReserve * 42
            * Math.max(0, DockService.iconZoomScale - 1)
    readonly property real nominalDropExtra:
        (launchpadDropActive || nativePinDropActive) ? 60 : 0
    readonly property real nominalMaximumLength:
        nominalRowLength + 20
        + Math.max(nominalMagnifyExtra, nominalDropExtra)
    readonly property real safeEdgeMargin: 12
    readonly property real availableDockLength: Math.max(1,
        (horizontalDock ? width : height) - safeEdgeMargin * 2)
    readonly property real requestedIconSize: sizeDragActive
        ? sizeDragIconSize
        : minimumIconSize + DockService.dockSizeLevel
            * (maximumIconSize - minimumIconSize)
    readonly property real requestedDockScale: requestedIconSize / 42
    readonly property real targetDockScale: nominalMaximumLength > 0
        ? Math.min(requestedDockScale,
            availableDockLength / nominalMaximumLength)
        : requestedDockScale
    property real dockScale: targetDockScale
    Behavior on dockScale {
        enabled: !win.sizeDragActive
        AppleSpring { spring: 13; epsilon: 0.01 }
    }

    // ── Dock card ──────────────────────────────────────────────────────────

    Rectangle {
        id: dockCard
        // Grow by one slot while a launchpad app is dragged over the dock so the
        // opened gap fits inside the card instead of the icons poking out. The card
        // grows symmetrically about the window centre and dockRow stays centred in
        // it, so dockRow's position — the slot-calc reference — doesn't move.
        // Only the external launchpad gap (a discrete 0 → pitch jump) needs its
        // own spring. Moving an existing Dock item never changes total length.
        // rest of the width tracks dockRow directly — the icons spring their own
        // width on hover, so the card grows
        // *with* them instead of chasing the moving total a beat behind, which is
        // what made the hover-grow look laggy/wobbly.
        property real launchpadGap: win.launchpadDropActive ? win.pitch : 0
        Behavior on launchpadGap { AppleSpring { spring: 13; epsilon: 0.25 } }
        readonly property real dropGap: launchpadGap
        // Use concrete dimensions, not only implicit ones. QML anchors write the
        // item's actual width/height; after changing edge, clearing an anchor can
        // otherwise leave the old horizontal/vertical dimension behind.
        width: win.horizontalDock
            ? Math.min(win.availableDockLength,
                dockRow.implicitWidth + 20 * win.dockScale + dropGap)
            : win.dockCardThickness
        height: win.horizontalDock
            ? win.dockCardThickness
            : Math.min(win.availableDockLength,
                dockRow.implicitHeight + 20 * win.dockScale + dropGap)
        // Explicit coordinates make switching between vertical and horizontal
        // layouts transactional. Conditional anchors can retain an old
        // anchor-owned dimension for a frame (or indefinitely on Qt 6.11),
        // leaving the 480px popup surface painted as a giant Dock card.
        x: win.horizontalDock
            ? (parent.width - width) / 2
            : win.leftDock ? 0 : parent.width - width
        y: win.horizontalDock
            ? parent.height - height
            : (parent.height - height) / 2
        radius: Math.max(10, 22 * win.dockScale)
        color: ThemeService.bg
        border.color: ThemeService.stroke
        border.width: 1

        Grid {
            id: dockRow
            anchors.centerIn: parent
            columns: win.horizontalDock ? win.dockRowChildCount : 1
            rows: win.horizontalDock ? 1 : win.dockRowChildCount
            flow: win.horizontalDock ? Grid.LeftToRight : Grid.TopToBottom
            spacing: 2 * win.dockScale

            Repeater {
                model: win.pinnedApps
                DockItem {
                    required property var modelData
                    required property int index
                    pinnedIndex: index
                    name: modelData.name; wmClass: modelData.wmClass
                    iconName: modelData.iconName; execCmd: modelData.execCmd
                    dark: win.dark; dockWin: win
                }
            }

            // Permanent macOS-style boundary between pinned applications and
            // the transient running-app area. Trash remains the final item.
            Item {
                id: utilitySeparator
                z: 500
                // Keep the visible hairline centered in an intentionally larger
                // hit slot. This creates real separation from adjacent app hover
                // regions instead of relying on an invisible overlapping target.
                width: win.horizontalDock
                    ? Math.max(28, 24 * win.dockScale) : 66 * win.dockScale
                height: win.horizontalDock
                    ? 66 * win.dockScale : Math.max(28, 24 * win.dockScale)
                transform: [
                    Translate {
                        x: win.horizontalDock ? win.launchpadRightSideShift : 0
                        y: win.verticalDock ? win.launchpadRightSideShift : 0
                        Behavior on x { AppleSpring {} }
                        Behavior on y { AppleSpring {} }
                    },
                    Translate {
                        x: win.horizontalDock
                            ? win.pinSeparatorShift + win.unpinSeparatorShift : 0
                        y: win.verticalDock
                            ? win.pinSeparatorShift + win.unpinSeparatorShift : 0
                        // During the gesture this is spring-driven and fully
                        // reversible. On release, disable the tail so the
                        // transform hands off exactly to the new model layout.
                        Behavior on x {
                            enabled: win.dragActive
                            AppleSpring { spring: 13; epsilon: 0.25 }
                        }
                        Behavior on y {
                            enabled: win.dragActive
                            AppleSpring { spring: 13; epsilon: 0.25 }
                        }
                    }
                ]
                Rectangle {
                    anchors.centerIn: parent
                    width: win.horizontalDock
                        ? Math.max(0.5, win.dockScale) : 36 * win.dockScale
                    height: win.horizontalDock
                        ? 36 * win.dockScale : Math.max(0.5, win.dockScale)
                    radius: 0.5
                    color: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
                }

                MouseArea {
                    id: separatorMouse

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: win.horizontalDock ? Qt.SizeVerCursor : Qt.SizeHorCursor
                    onContainsMouseChanged:
                        win.separatorHoverActive = separatorMouse.containsMouse
                    onPressed: (mouse) => {
                        if (mouse.button !== Qt.LeftButton) return
                        let p = utilitySeparator.mapToItem(win.contentItem, mouse.x, mouse.y)
                        win.beginSizeDrag(p)
                    }
                    onPositionChanged: (mouse) => {
                        if (!(separatorMouse.pressedButtons & Qt.LeftButton) || !win.sizeDragActive) return
                        let p = utilitySeparator.mapToItem(win.contentItem, mouse.x, mouse.y)
                        win.updateSizeDrag(p)
                    }
                    onReleased: (mouse) => {
                        if (mouse.button === Qt.LeftButton) win.endSizeDrag()
                    }
                    onCanceled: win.endSizeDrag()
                    onClicked: (mouse) => {
                        if (mouse.button !== Qt.RightButton) return
                        let p = utilitySeparator.mapToItem(win.contentItem,
                            utilitySeparator.width / 2, utilitySeparator.height / 2)
                        win.openUtilityMenu("position", p.x, p.y)
                    }
                }
            }

            // Running applications that are not kept in the Dock live on the
            // far side of the separator. Menu unpin and drag-across-separator
            // both update the same DockService model, so they land here at once.
            Repeater {
                model: win.extraApps
                DockItem {
                    required property var modelData
                    required property int index
                    transientIndex: index
                    name: modelData.name; wmClass: modelData.wmClass
                    iconName: modelData.iconName; execCmd: []
                    launchpadRightSide: true
                    dark: win.dark; dockWin: win
                }
            }

            TrashItem {
                id: trashItem
                dark: win.dark
                dockWin: win
                transform: Translate {
                    x: win.horizontalDock ? win.launchpadRightSideShift : 0
                    y: win.verticalDock ? win.launchpadRightSideShift : 0
                    Behavior on x { AppleSpring {} }
                    Behavior on y { AppleSpring {} }
                }
            }
        }

        // The Dock lives on the Overlay layer so it can stay over fullscreen
        // apps. That also puts it above Capture's selection scrim after a Dock
        // re-map, so mirror the same dim locally while leaving input disabled.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            z: 10000
            enabled: false
            visible: opacity > 0.001
            color: "black"
            opacity: Capture.CaptureService.overlayActive ? 0.34 : 0
            Behavior on opacity {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
        }
    }

    DropShadow {
        anchors.fill: dockCard
        source: dockCard
        z: -1
        transparentBorder: true
        radius: Math.max(8, 18 * win.dockScale)
        samples: 37
        horizontalOffset: win.leftDock ? 6 * win.dockScale
            : win.rightDock ? -6 * win.dockScale : 0
        verticalOffset: win.horizontalDock ? 6 * win.dockScale : 0
        color: Qt.rgba(0, 0, 0, dark ? 0.42 : 0.20)
    }

    PanelWindow {
        id: utilityMenuWin
        visible: win.utilityMenuSurfaceVisible
        screen: win.screen
        WlrLayershell.namespace: "qs-dock-utility-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: win.utilityMenuOpen ? null : closedUtilityRegion
        Region { id: closedUtilityRegion }

        MouseArea {
            anchors.fill: parent
            enabled: win.utilityMenuOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: win.closeUtilityMenu()
        }

        Rectangle {
            id: utilityPopup
            visible: opacity > 0
            opacity: win.utilityMenuOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: win.utilityMenuOpen
                        ? win.popupEnterDuration : win.popupExitDuration
                    easing.type: Easing.OutCubic
                }
            }
            onOpacityChanged: if (!win.utilityMenuOpen && opacity <= 0.002)
                win.utilityMenuSurfaceVisible = false
            width: win.utilityMenuWidth
            height: win.utilityMenuHeight
            radius: 12
            color: ThemeService.popupBg
            border.color: ThemeService.stroke
            border.width: 1

            x: {
                if (win.leftDock)
                    return win.dockVisibleMargin + win.dockCardThickness + 12
                if (win.rightDock)
                    return utilityMenuWin.width - win.dockVisibleMargin
                        - win.dockCardThickness - width - 12
                return Math.max(8, Math.min(utilityMenuWin.width - width - 8,
                    win.utilityAnchorX - width / 2))
            }
            y: {
                if (win.horizontalDock)
                    return utilityMenuWin.height - win.dockVisibleMargin
                        - win.dockCardThickness - height - 12
                return Math.max(8, Math.min(utilityMenuWin.height - height - 8,
                    win.utilityAnchorY - height / 2))
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
            }

            Column {
                anchors.fill: parent
                anchors.topMargin: win.utilityPadV
                anchors.bottomMargin: win.utilityPadV

                Repeater {
                    model: win.utilityMenuRows
                    delegate: Item {
                        id: utilityRow
                        required property var modelData
                        width: utilityPopup.width
                        height: win.utilityRowHeight(modelData)
                        readonly property bool separator: modelData.id === "sep"
                        readonly property bool disabled: modelData.disabled === true
                        readonly property bool slider: modelData.slider === true
                        readonly property bool toggle: modelData.toggle === true

                        Rectangle {
                            visible: utilityRow.separator
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            height: 1
                            color: win.dark ? Qt.rgba(1, 1, 1, 0.10)
                                : Qt.rgba(0, 0, 0, 0.10)
                        }

                        Rectangle {
                            visible: !utilityRow.separator && !utilityRow.slider
                                && utilityMa.containsMouse
                                && !utilityRow.disabled
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            radius: 6
                            color: win.dark ? Qt.rgba(1, 1, 1, 0.13)
                                : Qt.rgba(0, 0, 0, 0.08)
                        }

                        Text {
                            visible: utilityRow.modelData.checked === true
                                && !utilityRow.toggle
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            text: "✓"
                            color: win.dark ? Qt.rgba(1, 1, 1, 0.92)
                                : Qt.rgba(0, 0, 0, 0.85)
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Text {
                            visible: !utilityRow.separator && !utilityRow.slider
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            text: utilityRow.modelData.label || ""
                            color: utilityRow.disabled
                                ? (win.dark ? Qt.rgba(1, 1, 1, 0.48) : Qt.rgba(0, 0, 0, 0.42))
                                : utilityRow.modelData.destructive === true
                                    ? "#ff453a"
                                    : (win.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.85))
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: utilityRow.modelData.destructive === true
                                ? Font.DemiBold : Font.Normal
                        }

                        // Native-looking compact switch. It reacts on pointer-up,
                        // while the row highlight responds immediately on press.
                        Rectangle {
                            visible: utilityRow.toggle
                            anchors.right: parent.right
                            anchors.rightMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 20
                            radius: 10
                            color: utilityRow.modelData.checked === true
                                ? "#0A84FF"
                                : (win.dark ? Qt.rgba(1, 1, 1, 0.18)
                                    : Qt.rgba(0, 0, 0, 0.14))

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                y: 2
                                x: utilityRow.modelData.checked === true ? 16 : 2
                                color: "#ffffff"
                                Behavior on x { AppleSpring { spring: 18; epsilon: 0.05 } }
                            }
                        }

                        Item {
                            visible: utilityRow.slider
                            anchors.fill: parent

                            readonly property real zoomRange:
                                DockService.iconZoomMaximum - DockService.iconZoomMinimum
                            readonly property real zoomT: Math.max(0, Math.min(1,
                                (DockService.iconZoomScale - DockService.iconZoomMinimum)
                                    / Math.max(0.01, zoomRange)))

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.top: parent.top
                                anchors.topMargin: 5
                                text: "Zoom Amount"
                                color: win.dark ? Qt.rgba(1, 1, 1, 0.92)
                                    : Qt.rgba(0, 0, 0, 0.85)
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.top: parent.top
                                anchors.topMargin: 5
                                text: Math.round((DockService.iconZoomScale - 1) * 100) + "%"
                                color: win.dark ? Qt.rgba(1, 1, 1, 0.58)
                                    : Qt.rgba(0, 0, 0, 0.50)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                            }

                            Rectangle {
                                id: zoomTrack
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 11
                                height: 4
                                radius: 2
                                color: win.dark ? Qt.rgba(1, 1, 1, 0.18)
                                    : Qt.rgba(0, 0, 0, 0.14)

                                Rectangle {
                                    width: parent.width * parent.parent.zoomT
                                    height: parent.height
                                    radius: parent.radius
                                    color: "#0A84FF"
                                }

                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    x: parent.width * parent.parent.zoomT - width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#ffffff"
                                    border.color: Qt.rgba(0, 0, 0, 0.16)
                                    border.width: 1
                                    Behavior on x {
                                        enabled: !zoomSliderMouse.pressed
                                        AppleSpring { spring: 18; epsilon: 0.05 }
                                    }
                                }
                            }

                            MouseArea {
                                id: zoomSliderMouse
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 30
                                cursorShape: Qt.SizeHorCursor
                                onPressed: (mouse) => win.previewZoomFromSlider(mouse.x)
                                onPositionChanged: (mouse) => {
                                    if (zoomSliderMouse.pressed)
                                        win.previewZoomFromSlider(mouse.x)
                                }
                                onReleased: DockService.commitIconZoomScale(
                                    DockService.iconZoomScale)
                                onCanceled: DockService.commitIconZoomScale(
                                    DockService.iconZoomScale)
                            }
                        }

                        MouseArea {
                            id: utilityMa
                            anchors.fill: parent
                            enabled: !utilityRow.separator && !utilityRow.slider
                                && !utilityRow.disabled
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: win.utilityAction(utilityRow.modelData.id)
                        }
                    }
                }
            }
        }

        DropShadow {
            anchors.fill: utilityPopup
            source: utilityPopup
            visible: utilityPopup.visible
            z: -1
            transparentBorder: true
            radius: 22
            samples: 45
            verticalOffset: 8
            color: Qt.rgba(0, 0, 0, win.dark ? 0.48 : 0.24)
        }
    }

    // ── Preview popup ──────────────────────────────────────────────────────

    PanelWindow {
        id: previewDismissWin
        screen: win.screen
        visible: true
        WlrLayershell.namespace: "qs-dock-preview-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: win.previewOpen ? null : closedPreviewRegion
        Region { id: closedPreviewRegion }

        MouseArea {
            anchors.fill: parent
            enabled: win.previewOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: win.previewOpen = false
        }
    }

    // Dismiss overlay
    MouseArea {
        anchors.fill: parent
        visible: win.previewOpen
        z: 90
        onPressed: win.previewOpen = false
    }

    // Preview popup — instant, anchored to the clicked icon
    Rectangle {
        id: previewPopup
        visible: opacity > 0.002
        opacity: win.previewOpen && win.previewWindows.length > 0 ? 1 : 0
        scale: win.previewOpen && win.previewWindows.length > 0 ? 1 : 0.97
        transformOrigin: Item.Bottom
        Behavior on opacity {
            enabled: !win.previewInstantClose
            NumberAnimation {
                duration: win.previewOpen
                    ? win.popupEnterDuration : win.popupExitDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            enabled: !win.previewInstantClose
            NumberAnimation {
                duration: win.previewOpen
                    ? win.popupEnterDuration : win.popupExitDuration
                easing.type: Easing.OutCubic
            }
        }
        z: 100

        // Anchor horizontally to the clicked icon, clamped to panel edges
        x: {
            if (win.leftDock)
                return dockCard.x + dockCard.width + 12 + previewIconLift
            if (win.rightDock)
                return dockCard.x - width - 12 - previewIconLift
            let target = win.previewAnchorX - width / 2
            let maxX = win.width - width - 8
            return Math.max(8, Math.min(maxX, target))
        }
        y: {
            if (win.verticalDock)
                return Math.max(8, Math.min(win.height - height - 8,
                    win.previewAnchorY - height / 2))
            return dockCard.y - height - 12 - previewIconLift
        }

        width: cardGrid.implicitWidth + win.previewPadding * 2
        height: cardGrid.implicitHeight + win.previewPadding * 2
        radius: 18
        color: ThemeService.popupBg
        border.color: ThemeService.stroke
        border.width: 1

        // Materializes from its dock anchor with a critically damped fade/scale.

        // Tail pointer — tracks the icon center even when popup is clamped
        Canvas {
            id: pointer
            visible: win.horizontalDock
            width: 18; height: 9
            // X within popup so the tip sits at previewAnchorX absolute
            x: Math.max(12,
                  Math.min(parent.width - width - 12,
                    win.previewAnchorX - parent.x - width / 2))
            anchors.top: parent.bottom
            anchors.topMargin: -1
            antialiasing: true
            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(width / 2, height)
                ctx.lineTo(width, 0)
                ctx.closePath()
                ctx.fillStyle = win.dark ? "rgba(22,23,28,0.94)" : "rgba(248,248,248,0.94)"
                ctx.fill()
                ctx.strokeStyle = win.dark ? "rgba(255,255,255,0.13)" : "rgba(0,0,0,0.11)"
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(width / 2, height)
                ctx.lineTo(width, 0)
                ctx.stroke()
            }
            // Re-paint on theme change
            Connections {
                target: win
                function onDarkChanged() { pointer.requestPaint() }
            }
        }

        Grid {
            id: cardGrid
            anchors.centerIn: parent
            columns: win.previewCols
            rowSpacing: win.cardSpacing
            columnSpacing: win.cardSpacing

            Repeater {
                model: win.previewWindows
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: win.cardW; height: win.cardH; radius: 12
                    color: cardHover.hovered
                        ? (dark ? "#3a3a3c" : "#ffffff")
                        : (dark ? "#303033" : "#f5f5f7")
                    border.color: cardHover.hovered
                        ? Qt.rgba(10/255, 132/255, 255/255, 0.55)
                        : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                    border.width: 1

                    HoverHandler { id: cardHover }
                    scale: cardMa.pressed ? ThemeService.pressScale
                        : cardHover.hovered ? 1.03 : 1
                    Behavior on scale { AppleSpring { spring: 13 } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Icons.AppIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 44
                            iconName: win.previewIconName
                            appClass: win.previewWmClass
                            smooth: true; mipmap: true
                            sourceSize.width: 44; sourceSize.height: 44
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            // Pin to the card width (not the enclosing Row, whose
                            // anchors.fill width feeds back into this binding and
                            // leaves the width unstable) so the title has a hard
                            // bound to wrap/elide against: card − margins − icon −
                            // spacing = 200 − 24 − 44 − 10.
                            width: card.width - 24 - 44 - 10
                            height: appName.implicitHeight + winTitle.implicitHeight + 4

                            Text {
                                id: appName
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                text: win.previewWmClass
                                color: dark ? Qt.rgba(1,1,1,0.95) : Qt.rgba(0,0,0,0.85)
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                id: winTitle
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: appName.bottom
                                anchors.topMargin: 2
                                text: card.modelData.title
                                color: dark ? Qt.rgba(1,1,1,0.62) : Qt.rgba(0,0,0,0.55)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                // Wrap at word boundaries but also mid-word when
                                // needed — long unbroken titles (e.g. a hashed
                                // filename) otherwise overflow the card instead
                                // of wrapping/eliding.
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.selectPreviewWindow(card.modelData.address)
                    }
                }
            }
        }
    }

    DropShadow {
        anchors.fill: previewPopup
        source: previewPopup
        visible: previewPopup.visible
        z: 99
        transparentBorder: true
        radius: 24
        samples: 49
        verticalOffset: 9
        color: Qt.rgba(0, 0, 0, dark ? 0.50 : 0.26)
    }

    Process {
        id: focusAddrProc
        property string addr: ""
        // Focus the window then raise it above other (floating) windows so it
        // isn't left buried under whatever was stacked higher.
        command: ["hyprctl", "eval",
                  'hl.dispatch(hl.dsp.focus({ window = "address:' + addr + '" })); '
                  + 'hl.dispatch(hl.dsp.window.bring_to_top({ window = "address:' + addr + '" }))']
    }

    // ── Right-click context menu ─────────────────────────────────────────────

    Process { id: menuActionProc; command: ["true"] }
    // Brief grace period so the pointer can travel from the "Move to Workspace"
    // row onto the flyout without the submenu collapsing in the gap.
    Timer { id: submenuCloseTimer; interval: 140; onTriggered: win.submenuOpen = false }

    // The context menu lives in its OWN overlay surface, not the dock's tall
    // bottom-anchored one. On this scaled display the dock surface's full-window
    // input region didn't line up with the rendered menu (rows were clickable
    // only at a thin edge); a dedicated surface hit-tests correctly.
    PanelWindow {
        id: menuWin
        visible: win.menuSurfaceVisible
        screen: win.screen
        WlrLayershell.namespace: "qs-dock-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: win.menuOpen ? null : closedMenuRegion
        Region { id: closedMenuRegion }

        readonly property bool dark: win.dark
        // The right-clicked icon stays magnified (1.75×) while its menu is open,
        // lifting ~19px above the dock card top. Raise the menu by that much so it
        // sits just above the enlarged icon instead of overlapping it.
        readonly property real menuIconLift: 25 * win.dockScale

    // Click-outside to dismiss.
    MouseArea {
        anchors.fill: parent
        enabled: win.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: win.closeMenu()
    }

    Rectangle {
        id: menuPopup
        // Critically damped fade only. A Scale transform here left the layer surface's input
        // region misaligned with the rendered menu — rows were only clickable at a
        // thin edge, dead in the middle — so the geometry is kept identity.
        visible: opacity > 0
        opacity: win.menuOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: win.menuOpen
                    ? win.popupEnterDuration : win.popupExitDuration
                easing.type: Easing.OutCubic
            }
        }
        onOpacityChanged: if (!win.menuOpen && opacity <= 0.002) win.menuSurfaceVisible = false
        z: 200
        width: win.menuWidth
        height: win.menuHeight
        radius: 12
        color: ThemeService.popupBg
        border.color: ThemeService.stroke
        border.width: 1

        // Anchor horizontally to the clicked icon, clamped to the panel edges.
        x: {
            if (win.leftDock)
                return win.dockVisibleMargin + win.dockCardThickness
                    + menuWin.menuIconLift
            if (win.rightDock)
                return menuWin.width - win.dockVisibleMargin
                    - win.dockCardThickness - menuWin.menuIconLift - width
            let target = win.menuAnchorX - width / 2
            let maxX = menuWin.width - width - 8
            return Math.max(8, Math.min(maxX, target))
        }
        y: {
            if (win.verticalDock)
                return Math.max(8, Math.min(menuWin.height - height - 8,
                    win.menuAnchorY - height / 2))
            return menuWin.height - win.dockVisibleMargin
                - win.dockCardThickness - menuWin.menuIconLift - height
        }

        // Flip the Assign-To flyout to the left when it would overflow the screen.
        readonly property bool submenuLeft:
            (x + width + win.submenuGap + win.submenuWidth) > (menuWin.width - 8)

        // Swallow clicks that land on the menu's own padding / separators so they
        // don't fall through to the dismiss overlay behind it — previously a
        // slight miss near the bottom rows (Quit / Keep in Dock) just closed it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: false
        }

        Column {
            anchors.fill: parent
            anchors.topMargin: win.menuPadV
            anchors.bottomMargin: win.menuPadV

            Repeater {
                model: win.menuRows
                delegate: Item {
                    id: row
                    required property var modelData
                    width: menuPopup.width
                    height: modelData.id === "sep" ? win.menuSepH : win.menuRowH

                    readonly property bool isSep: modelData.id === "sep"
                    readonly property bool active: rowMa.containsMouse
                        || (modelData.id === "assign" && win.submenuOpen)
                    scale: rowMa.pressed ? 0.985 : 1
                    Behavior on scale { AppleSpring { spring: 13 } }

                    Rectangle {   // separator
                        visible: row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        height: 1
                        color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.10)
                    }

                    Rectangle {   // hover highlight — translucent, not a solid blue
                        visible: opacity > 0
                        opacity: !row.isSep && row.active ? 1 : 0
                        anchors.fill: parent
                        anchors.leftMargin: 4; anchors.rightMargin: 4
                        radius: 6
                        color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.08)
                        Behavior on opacity { AppleSpring { spring: 13 } }
                    }

                    Text {   // checkmark — shown for "Keep in Dock" when pinned
                        visible: row.modelData.checked === true
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 13
                        text: "✓"
                        font.family: "SF Pro Display"; font.pixelSize: 12; font.bold: true
                        color: dark ? Qt.rgba(1,1,1,0.92) : Qt.rgba(0,0,0,0.85)
                    }

                    Text {   // label
                        visible: !row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 30
                        text: row.modelData.label || ""
                        font.family: "SF Pro Display"; font.pixelSize: 13
                        color: dark ? Qt.rgba(1,1,1,0.92) : Qt.rgba(0,0,0,0.85)
                    }

                    Text {   // submenu arrow
                        visible: row.modelData.arrow === true
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 12
                        text: "›"
                        font.family: "SF Pro Display"; font.pixelSize: 16
                        color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.45)
                    }

                    MouseArea {
                        id: rowMa
                        enabled: !row.isSep
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (row.modelData.id === "assign") {
                                submenuCloseTimer.stop(); win.submenuOpen = true
                            } else {
                                submenuCloseTimer.restart()
                            }
                        }
                        onClicked: {
                            if (row.modelData.id === "assign") return  // flyout only
                            win._menuAction(row.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // Assign-To flyout — pick a workspace to move (and follow) the app's windows.
    Rectangle {
        id: submenuFlyout
        visible: opacity > 0
        opacity: (win.menuOpen && win.submenuOpen) ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: win.menuOpen && win.submenuOpen
                    ? win.popupEnterDuration : win.popupExitDuration
                easing.type: Easing.OutCubic
            }
        }
        z: 210
        width: win.submenuWidth
        height: win.submenuHeight
        radius: 12
        color: ThemeService.menuBg
        border.color: menuPopup.border.color
        border.width: 1
        x: menuPopup.submenuLeft ? (menuPopup.x - width - win.submenuGap)
                                 : (menuPopup.x + menuPopup.width + win.submenuGap)
        // Top-align to the "Move to Workspace" row, but never let the bottom run
        // past the dock card — shift it up so all workspaces stay on screen
        // (this is what was getting clipped before).
        y: {
            let top = menuPopup.y + win.menuPadV + win._assignRowOffset()
            let maxBottom = menuWin.dockTopY - menuWin.menuIconLift - 6
            if (top + height > maxBottom) top = maxBottom - height
            return Math.max(8, top)
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: submenuCloseTimer.stop()
            onExited: submenuCloseTimer.restart()

            Column {
                anchors.fill: parent
                anchors.topMargin: win.menuPadV
                anchors.bottomMargin: win.menuPadV

                Repeater {
                    model: win.wsCount
                    delegate: Item {
                        id: wsRow
                        required property int index
                        width: submenuFlyout.width
                        height: win.submenuRowH
                        readonly property int ws: index + 1
                        scale: wsMa.pressed ? 0.985 : 1
                        Behavior on scale { AppleSpring { spring: 13 } }

                        Rectangle {
                            visible: opacity > 0
                            opacity: wsMa.containsMouse ? 1 : 0
                            anchors.fill: parent
                            anchors.leftMargin: 4; anchors.rightMargin: 4
                            radius: 6
                            color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.08)
                            Behavior on opacity { AppleSpring { spring: 13 } }
                        }
                        Text {   // check on the workspace(s) this app's windows are on
                            visible: win.menuAppWorkspaces[String(wsRow.ws)] === true
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 13
                            text: "✓"
                            font.family: "SF Pro Display"; font.pixelSize: 12; font.bold: true
                            color: dark ? Qt.rgba(1,1,1,0.92) : Qt.rgba(0,0,0,0.85)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 30
                            text: "Workspace " + wsRow.ws
                            font.family: "SF Pro Display"; font.pixelSize: 13
                            color: dark ? Qt.rgba(1,1,1,0.92) : Qt.rgba(0,0,0,0.85)
                        }
                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.doMoveTo(wsRow.ws)
                        }
                    }
                }
            }
        }
    }
    }
}
