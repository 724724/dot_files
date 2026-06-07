import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: win

    // Per-screen instance (shell.qml wraps this in Variants over Quickshell.screens),
    // so every monitor gets its own dock that reveals at its own bottom edge.
    required property var modelData
    screen: modelData

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
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Confine pointer input to the dock's own column (see triggerColumn): the
    // dock then reveals only when the cursor is over where it sits — not the
    // entire bottom edge — and the empty space to its left/right stays
    // click-through to the windows below. A preview grows the window and needs
    // its full surface (popup + click-outside-to-dismiss), so drop the mask
    // while one is open.
    mask: (win.previewOpen || win.dragActive) ? null : dockRegion
    Region { id: dockRegion; item: triggerColumn }

    readonly property bool dark: ThemeService.isDark

    // ── Preview state ──────────────────────────────────────────────────────

    property bool previewOpen: false
    property string previewWmClass: ""
    property string previewIconName: ""
    property var previewWindows: []  // [{address, title}]
    // Anchor X (in this PanelWindow's coordinate space) of the clicked icon's center
    property real previewAnchorX: 0

    // Toggle: same icon click closes, different icon click switches.
    // Opens INSTANTLY using DockService data — no screenshot/grim, no spawn delay.
    function togglePreview(wmClass, iconName, anchorX) {
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
        previewOpen = true
        showDock = true
        hideTimer.stop()
    }

    // Preview grid sizing: up to 4 columns, wrap to multiple rows
    readonly property int previewCols: Math.min(4, Math.max(1, previewWindows.length))
    readonly property int previewRows: Math.ceil(previewWindows.length / Math.max(1, previewCols))
    readonly property int cardW: 200
    readonly property int cardH: 96
    readonly property int cardSpacing: 8
    readonly property int previewPadding: 12

    // The clicked icon magnifies ~18px above the dock card's top edge while its
    // preview is open (see DockItem: hoverScale 1.75, 42px icon growing upward).
    // Lift the popup — and add matching headroom to the panel — so it sits just
    // above the enlarged icon, the tail meeting its top rather than overlapping.
    readonly property int previewIconLift: 20

    // FIXED tall surface. The dock card lives at the bottom; previews and the
    // right-click menu draw into the headroom above. Crucially the surface size
    // never changes when a popup opens — previously the panel grew from 128 to
    // ~400px, which reconfigured the Wayland layer every time and made the whole
    // dock visibly blink / stutter instead of the popup just appearing. A
    // constant height also gives the Move-to-Workspace flyout room so it no
    // longer gets clipped at the screen edge.
    readonly property int panelHeight: 480
    implicitHeight: panelHeight
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
    margins.bottom: (DockService.pinnedVisible || showDock || previewOpen || menuOpen || dragActive || launchingCount > 0)
        ? 8 : -(dockTriggerH - 4)
    Behavior on margins.bottom {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Invisible band at the BOTTOM matching the dock card's footprint. The mask
    // binds to this, so only the dock area takes pointer input — the tall
    // transparent headroom above (where popups draw) stays click-through, and the
    // reveal triggers only at the very bottom edge.
    readonly property int dockTriggerH: 88
    Item {
        id: triggerColumn
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dockCard.implicitWidth
        height: dockTriggerH
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

    // ── Pinned apps ────────────────────────────────────────────────────────

    // KakaoTalk runs under Wine, whose .desktop entry only declares its raw
    // hash icon (DDB7_KakaoTalk.0) — themes ship a clean "KakaoTalk" instead.
    // Prefer the themed name (follows the active icon theme); fall back to the
    // always-present Wine hash if the theme doesn't provide it.
    readonly property string kakaoIcon:
        Quickshell.iconPath("KakaoTalk", true) !== "" ? "KakaoTalk" : "DDB7_KakaoTalk.0"

    // Seed list, used only the first time (no store file yet). After that the
    // pinned set is user-managed through the right-click "Keep in Dock" toggle
    // and persisted to disk, so edits survive a reload/restart.
    readonly property var defaultPins: [
        { name: "Files",     wmClass: "org.gnome.Nautilus", iconName: "org.gnome.Nautilus", execCmd: ["gtk-launch", "org.gnome.Nautilus"] },
        { name: "Chrome",    wmClass: "google-chrome",      iconName: "google-chrome",      execCmd: ["gtk-launch", "google-chrome"] },
        { name: "KakaoTalk", wmClass: "kakaotalk.exe",      iconName: win.kakaoIcon,        execCmd: ["gtk-launch", "wine-Programs-KakaoTalk"] },
        { name: "Spotify",   wmClass: "spotify",            iconName: "spotify-client",     execCmd: ["gtk-launch", "spotify"] }
    ]

    // Live pinned set — populated from the store in onCompleted (briefly empty
    // before that). Reassign a fresh array on every change so bindings refresh.
    property var pinnedApps: []
    readonly property var pinnedClasses: pinnedApps.map(a => (a.wmClass || "").toLowerCase())

    // Same persistence convention as NcServer: a blockLoading FileView read
    // synchronously in onCompleted, written back via setText(JSON).
    FileView {
        id: pinStore
        path: Quickshell.stateDir + "/dock-pinned.json"
        blockLoading: true   // synchronous read so data is ready in onCompleted
        printErrors: false   // a missing file on first run is expected
    }

    Component.onCompleted: win._loadPins()

    function _loadPins() {
        let raw = pinStore.text()
        if (raw) {
            try {
                let parsed = JSON.parse(raw)
                if (Array.isArray(parsed)) { win.pinnedApps = parsed; return }
            } catch (e) { /* corrupt — fall through to defaults */ }
        }
        win.pinnedApps = win.defaultPins
        win._persistPins()
    }

    function _persistPins() {
        pinStore.setText(JSON.stringify(win.pinnedApps))
    }

    function isPinned(cls) {
        return win.pinnedClasses.includes((cls || "").toLowerCase())
    }

    // Resolve a runnable launch command for an app we only know by window class,
    // reusing the same desktop-entry heuristic the dock already uses for icons.
    function _guessExec(wmClass) {
        let m = win._remapClass(wmClass)
        let de = DesktopEntries.heuristicLookup(m.base)
        if (de && de.id) return ["gtk-launch", de.id]
        return []
    }

    function pinApp(app) {
        let cls = (app.wmClass || "").toLowerCase()
        if (!cls || win.isPinned(cls)) return
        let cmd = (app.execCmd && app.execCmd.length > 0) ? app.execCmd : win._guessExec(app.wmClass)
        win.pinnedApps = win.pinnedApps.concat([{
            name: app.name, wmClass: app.wmClass, iconName: app.iconName, execCmd: cmd
        }])
        win._persistPins()
    }

    function unpinApp(cls) {
        cls = (cls || "").toLowerCase()
        win.pinnedApps = win.pinnedApps.filter(a => (a.wmClass || "").toLowerCase() !== cls)
        win._persistPins()
    }

    // ── Drag to reorder / pin / unpin ────────────────────────────────────────
    // Press ANY dock icon and drag. Drop in the pinned section to pin/reorder;
    // drop past the separator (the running-apps side) to unpin. The model isn't
    // reassigned mid-drag (that would rebuild the Repeater and drop the grab) —
    // icons shift visually and the commit happens once, on release.
    property bool dragActive: false
    property var dragApp: ({})         // {name, wmClass, iconName, execCmd} being dragged
    property int dragSourceIndex: -1   // its pinned index, or -1 if it came from the running side
    property real dragDeltaX: 0        // horizontal travel from the press point
    property int dropIndex: -1         // target pinned slot, or -1 = running side (unpin / no-op)
    readonly property int pitch: 60    // 58px icon slot + 2px Row spacing
    readonly property var rowItem: dockRow   // pointer maths happen in this Row's coords

    function beginDrag(app, sourceIndex: int) {
        win.previewOpen = false
        win.closeMenu()
        win.dragApp = app
        win.dragSourceIndex = sourceIndex
        win.dragDeltaX = 0
        win.dropIndex = sourceIndex >= 0 ? sourceIndex : win.pinnedApps.length
        win.dragActive = true
        win.showDock = true
        hideTimer.stop()
        win.extraApps = win.extraApps   // break the binding → freeze the running list
    }
    // cursorRowX: pointer X within dockRow (0 = left edge of the first icon).
    function updateDrag(deltaX, cursorRowX) {
        if (!win.dragActive) return
        win.dragDeltaX = deltaX
        let n = win.pinnedApps.length
        if (cursorRowX < n * win.pitch + 7)        // left of the separator → pinned side
            win.dropIndex = Math.max(0, Math.min(n, Math.round(cursorRowX / win.pitch)))
        else                                       // right of the separator → running side
            win.dropIndex = -1
    }
    function endDrag() {
        let active = win.dragActive, src = win.dragSourceIndex, drop = win.dropIndex, app = win.dragApp
        // Clear state FIRST so every offset snaps to 0, then commit the change.
        win.dragActive = false
        win.dragSourceIndex = -1
        win.dropIndex = -1
        win.dragDeltaX = 0
        win.dragApp = ({})
        win.extraApps = Qt.binding(() => win._liveExtras)   // re-bind: track the live list again
        if (!active) return

        if (src >= 0) {                            // dragged a pinned app
            if (drop < 0) {
                win.unpinApp((app.wmClass || "").toLowerCase())          // → running side: unpin
            } else {
                let to = Math.min(drop, win.pinnedApps.length - 1)       // reorder within pinned
                if (to !== src) {
                    let arr = win.pinnedApps.slice()
                    arr.splice(to, 0, arr.splice(src, 1)[0])
                    win.pinnedApps = arr
                    win._persistPins()
                }
            }
        } else if (drop >= 0) {                    // dragged a running app onto the pinned side: pin
            win.pinAppAt(app, drop)
        }
    }

    function pinAppAt(app, idx) {
        let cls = (app.wmClass || "").toLowerCase()
        if (!cls || win.isPinned(cls)) return
        let cmd = (app.execCmd && app.execCmd.length > 0) ? app.execCmd : win._guessExec(app.wmClass)
        let arr = win.pinnedApps.slice()
        arr.splice(Math.max(0, Math.min(arr.length, idx)), 0,
                   { name: app.name, wmClass: app.wmClass, iconName: app.iconName, execCmd: cmd })
        win.pinnedApps = arr
        win._persistPins()
    }

    // ── Right-click menu state ───────────────────────────────────────────────

    property bool menuOpen: false
    property var menuApp: ({})          // {name, wmClass, iconName, execCmd}
    property real menuAnchorX: 0        // clicked icon centre, panel coords
    property bool submenuOpen: false    // Assign-To flyout

    readonly property int menuWidth: 240
    readonly property int menuRowH: 30
    readonly property int menuSepH: 11
    readonly property int menuPadV: 6
    readonly property int submenuWidth: 180
    readonly property int submenuRowH: 28
    readonly property int wsCount: 10

    readonly property string menuClass: (menuApp.wmClass || "").toLowerCase()
    readonly property var menuWindows: DockService.clientsByClass[menuClass] || []
    readonly property bool menuRunning: menuWindows.length > 0
    readonly property bool menuPinned: win.isPinned(menuClass)
    // A launch command for "New Window"/"Open": prefer the app's own, else guess.
    readonly property var menuExec: (menuApp.execCmd && menuApp.execCmd.length > 0)
        ? menuApp.execCmd : win._guessExec(menuApp.wmClass || "")
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
            rows.push({ id: "pin", label: "Keep in Dock", checked: menuPinned })
            rows.push({ id: "sep" })
            rows.push({ id: "quit", label: "Quit" })
        } else {
            if (menuExec.length > 0) rows.push({ id: "newwin", label: "Open" })
            if (rows.length > 0) rows.push({ id: "sep" })
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

    function openMenu(app, anchorX) {
        win.previewOpen = false
        win.menuApp = app
        win.menuAnchorX = anchorX
        win.submenuOpen = false
        win.menuOpen = true
        win.showDock = true
        hideTimer.stop()
    }
    function closeMenu() { win.menuOpen = false; win.submenuOpen = false }

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
                win.togglePreview(win.menuApp.wmClass, win.menuApp.iconName, win.menuAnchorX)
            else if (wins.length === 1)
                win._runHypr([ win._focusWin(wins[0].address) ])
        } else if (id === "newwin") {
            if (win.menuExec.length > 0) { menuLaunchProc.command = win.menuExec; menuLaunchProc.running = true }
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

    // Class → friendly name+icon. Handles:
    //  - Wine apps in virtual-desktop mode (class "explorer.exe" → Ableton)
    //  - KakaoTalk (Wine-extracted icon hash)
    //  - Qt apps that append _PID_RANDOM to the class on every launch
    //    (transmission, etc.) — strip the suffix so the icon theme finds it
    function _remapClass(cls) {
        let lc = cls.toLowerCase()
        // Wine apps report a generic class with no matching desktop entry, so
        // map them by hand and skip the heuristic icon lookup (exact: true).
        if (lc === "explorer.exe") return { name: "Ableton", iconName: "ableton", base: cls, exact: true }
        // KakaoTalk's .desktop icon is Wine's raw hash; use the themed kakaoIcon
        // directly (exact: true) rather than re-resolving to that hash.
        if (lc === "kakaotalk.exe") return { name: "KakaoTalk", iconName: win.kakaoIcon, base: cls, exact: true }
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        let base = m ? m[1] : cls
        let baseLc = base.toLowerCase()
        if (baseLc === "code") return { name: "VS Code", iconName: "visual-studio-code", base: base, exact: false }
        if (baseLc === "com.transmissionbt.transmission")
            return { name: "Transmission", iconName: "transmission", base: base, exact: false }
        return { name: base, iconName: base, base: base, exact: false }
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
            let m = _remapClass(cls)
            return { name: m.name, wmClass: cls, iconName: _iconForClass(m), execCmd: [] }
        })
    // The Repeater binds to this. Normally it tracks _liveExtras, but during a
    // drag the binding is broken (see beginDrag/endDrag) so the 500ms poll can't
    // reassign it, rebuild the Repeater, and tear the grabbed icon off the cursor.
    property var extraApps: _liveExtras

    // ── Dock card ──────────────────────────────────────────────────────────

    Rectangle {
        id: dockCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        implicitWidth: dockRow.implicitWidth + 20
        height: 68; radius: 22
        color: dark ? Qt.rgba(16/255, 16/255, 21/255, 0.72)
                    : Qt.rgba(1, 1, 1, 0.68)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.13)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 2

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

            // macOS-style separator between pinned apps and other running apps
            Item {
                visible: win.extraApps.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 52
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: 36
                    radius: 0.5
                    color: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
                }
            }

            Repeater {
                model: win.extraApps
                DockItem {
                    required property var modelData
                    name: modelData.name; wmClass: modelData.wmClass
                    iconName: modelData.iconName; execCmd: []
                    dark: win.dark; dockWin: win
                }
            }
        }
    }

    // ── Preview popup ──────────────────────────────────────────────────────

    // Dismiss overlay
    MouseArea {
        anchors.fill: parent
        visible: win.previewOpen
        z: 90
        onClicked: win.previewOpen = false
    }

    // Preview popup — instant, anchored to the clicked icon
    Rectangle {
        id: previewPopup
        visible: win.previewOpen && win.previewWindows.length > 0
        z: 100

        // Anchor horizontally to the clicked icon, clamped to panel edges
        x: {
            let target = win.previewAnchorX - width / 2
            let maxX = win.width - width - 8
            return Math.max(8, Math.min(maxX, target))
        }
        y: dockCard.y - height - 12 - previewIconLift

        width: cardGrid.implicitWidth + win.previewPadding * 2
        height: cardGrid.implicitHeight + win.previewPadding * 2
        radius: 18
        color: dark ? Qt.rgba(22/255, 23/255, 28/255, 0.94)
                    : Qt.rgba(248/255, 248/255, 248/255, 0.94)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.11)
        border.width: 1

        // No fade/scale: the popup just appears/disappears with `visible` so
        // opening and closing carry no animation (no bounce, no grow-in).

        // Tail pointer — tracks the icon center even when popup is clamped
        Canvas {
            id: pointer
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
                        ? (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        : (dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.03))
                    border.color: cardHover.hovered
                        ? Qt.rgba(10/255, 132/255, 255/255, 0.55)
                        : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                    border.width: 1

                    Behavior on color        { ColorAnimation { duration: 90 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: cardHover }
                    scale: cardHover.hovered ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 44
                            source: "image://icon/" + win.previewIconName
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
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.previewOpen = false
                            focusAddrProc.addr = card.modelData.address
                            focusAddrProc.running = true
                        }
                    }
                }
            }
        }
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
    Process { id: menuLaunchProc; command: ["true"] }
    // Brief grace period so the pointer can travel from the "Move to Workspace"
    // row onto the flyout without the submenu collapsing in the gap.
    Timer { id: submenuCloseTimer; interval: 140; onTriggered: win.submenuOpen = false }

    // The context menu lives in its OWN overlay surface, not the dock's tall
    // bottom-anchored one. On this scaled display the dock surface's full-window
    // input region didn't line up with the rendered menu (rows were clickable
    // only at a thin edge); a dedicated surface hit-tests correctly.
    PanelWindow {
        id: menuWin
        visible: win.menuOpen
        screen: win.screen
        WlrLayershell.namespace: "qs-dock-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        readonly property bool dark: win.dark
        // Dock card's top edge in this full-screen surface: the dock sits at the
        // screen bottom (8px margin) and its card is 68px tall.
        readonly property real dockTopY: height - 8 - 68
        // The right-clicked icon stays magnified (1.75×) while its menu is open,
        // lifting ~19px above the dock card top. Raise the menu by that much so it
        // sits just above the enlarged icon instead of overlapping it.
        readonly property int menuIconLift: 25

    // Click-outside to dismiss.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: win.closeMenu()
    }

    Rectangle {
        id: menuPopup
        // Plain fade only. A Scale transform here left the layer surface's input
        // region misaligned with the rendered menu — rows were only clickable at a
        // thin edge, dead in the middle — so the geometry is kept identity.
        visible: opacity > 0
        opacity: win.menuOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        z: 200
        width: win.menuWidth
        height: win.menuHeight
        radius: 12
        color: dark ? Qt.rgba(28/255, 28/255, 33/255, 0.97)
                    : Qt.rgba(250/255, 250/255, 250/255, 0.98)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.12)
        border.width: 1

        // Anchor horizontally to the clicked icon, clamped to the panel edges.
        x: {
            let target = win.menuAnchorX - width / 2
            let maxX = menuWin.width - width - 8
            return Math.max(8, Math.min(maxX, target))
        }
        // Sit flush on top of the dock — no gap below the bottom rows.
        y: menuWin.dockTopY - menuWin.menuIconLift - height

        // Flip the Assign-To flyout to the left when it would overflow the screen.
        readonly property bool submenuLeft: (x + width + win.submenuWidth - 6) > (menuWin.width - 8)

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

                    Rectangle {   // separator
                        visible: row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        height: 1
                        color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.10)
                    }

                    Rectangle {   // hover highlight — translucent, not a solid blue
                        visible: !row.isSep && row.active
                        anchors.fill: parent
                        anchors.leftMargin: 4; anchors.rightMargin: 4
                        radius: 6
                        color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.08)
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
        Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
        z: 210
        width: win.submenuWidth
        height: win.submenuHeight
        radius: 12
        color: menuPopup.color
        border.color: menuPopup.border.color
        border.width: 1
        x: menuPopup.submenuLeft ? (menuPopup.x - width + 6)
                                 : (menuPopup.x + menuPopup.width - 6)
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

                        Rectangle {
                            visible: wsMa.containsMouse
                            anchors.fill: parent
                            anchors.leftMargin: 4; anchors.rightMargin: 4
                            radius: 6
                            color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.08)
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
