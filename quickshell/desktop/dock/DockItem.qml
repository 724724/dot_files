import Quickshell.Io
import QtQuick

Item {
    id: item

    property string name: ""
    property string wmClass: ""
    property string iconName: ""
    property var execCmd: []
    property bool dark: true
    // Direct reference to DockWindow — avoids signals with complex var types
    property var dockWin: null

    // Magnify on hover, macOS-style. hoverScale drives both the visual Scale
    // (below) and the layout width here, so the widened slot shoves neighbouring
    // icons aside in the Row instead of overlapping them. +16 keeps the icon's
    // 8px side padding constant at any zoom (42 + 16 = 58 when idle).
    readonly property real hoverScale: 1.75
    implicitWidth: 42 * (magnified ? hoverScale : 1) + 16
    implicitHeight: 66
    Behavior on implicitWidth { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }

    readonly property bool isRunning: DockService.runningClasses.indexOf(wmClass.toLowerCase()) >= 0
    readonly property bool isFocused: DockService.focusedClass === wmClass.toLowerCase()
    readonly property var windows: DockService.clientsByClass[wmClass.toLowerCase()] || []

    // While the window-picker preview is open, the clicked app's icon stays
    // magnified so the popup floats above a zoomed icon instead of the icon
    // collapsing the instant the pointer leaves it for the popup. Other icons
    // don't magnify (and no tooltips show) while a preview is open, so only the
    // selected app is highlighted — everything returns to normal on close.
    readonly property bool anyPreviewOpen: dockWin ? dockWin.previewOpen : false
    readonly property bool previewActive: anyPreviewOpen
        && dockWin.previewWmClass.toLowerCase() === wmClass.toLowerCase()
    // While its menu is open, the right-clicked icon STAYS magnified (the menu is
    // in its own window above the dock now, so there's no clipping). Other icons
    // drop their hover magnify + tooltip while any menu is open.
    readonly property bool anyMenuOpen: dockWin ? dockWin.menuOpen : false
    readonly property bool menuActive: anyMenuOpen
        && dockWin.menuClass === wmClass.toLowerCase()
    // Windows of this app that have been Hidden onto the special:minimized
    // workspace — a left click restores them instead of re-focusing in place.
    readonly property var hiddenWindows: (windows || []).filter(w => (w.ws || "") === "special:minimized")

    // ── Drag to reorder / pin / unpin ────────────────────────────────────────
    property int pinnedIndex: -1    // index in DockWindow.pinnedApps; -1 = a running (unpinned) app
    property real _pressX: 0         // press point in dockRow coords
    property bool _pressed: false
    property bool _dragging: false
    property bool _didDrag: false    // suppress the click that ends a drag
    readonly property bool anyDragActive: dockWin ? dockWin.dragActive : false
    // Identify the dragged icon by class (unique across the dock) so pinned AND
    // running icons can be the one being dragged.
    readonly property bool isDragged: anyDragActive
        && (dockWin.dragApp.wmClass || "").toLowerCase() === wmClass.toLowerCase()
    // Pinned icons slide aside to open the drop gap. src = dragged item's pinned
    // index (-1 if a running app is being dragged in); dp = drop slot (-1 = running side).
    readonly property real dragShift: {
        if (!anyDragActive || pinnedIndex < 0 || isDragged) return 0
        let src = dockWin.dragSourceIndex, dp = dockWin.dropIndex
        if (dp < 0) return 0                                           // heading to the running side
        if (src < 0) return pinnedIndex >= dp ? dockWin.pitch : 0      // inserting a new pin
        if (src < dp && pinnedIndex > src && pinnedIndex <= dp) return -dockWin.pitch
        if (src > dp && pinnedIndex >= dp && pinnedIndex < src) return dockWin.pitch
        return 0
    }
    readonly property real visualDragX: !anyDragActive ? 0
        : (isDragged ? dockWin.dragDeltaX : dragShift)

    // Also stays enlarged for the whole launch bounce, not just on hover. No
    // hover magnify while a preview / menu / drag is in progress.
    readonly property bool magnified: previewActive || menuActive || launching
        || (hover.hovered && !anyPreviewOpen && !anyMenuOpen && !anyDragActive)
    z: isDragged ? 1000 : 0

    // Launch feedback: a slow, gentle hop that repeats until the launched app's
    // window shows up (or a safety timeout fires), instead of a fixed bounce.
    property real bounceY: 0
    property bool launching: false

    // The window appearing (DockService polls ~every 500ms) ends the bounce.
    onIsRunningChanged: if (isRunning) launching = false

    Timer {
        id: launchTimeout
        interval: 15000   // give up if the launched window never registers
        onTriggered: item.launching = false
    }

    SequentialAnimation {
        id: bounceAnim
        running: item.launching
        loops: Animation.Infinite
        NumberAnimation { target: item; property: "bounceY"; to: -16; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "bounceY"; to: 0;   duration: 180; easing.type: Easing.InQuad }
        PauseAnimation { duration: 100 }
    }

    // Settle smoothly if the loop is cut mid-hop when the window appears.
    NumberAnimation {
        id: settleAnim
        target: item; property: "bounceY"; to: 0; duration: 160; easing.type: Easing.OutQuad
    }
    onLaunchingChanged: {
        if (launching) settleAnim.stop()
        else settleAnim.restart()
        // Keep the dock revealed for the whole bounce (DockWindow watches this).
        if (dockWin) dockWin.launchingCount += launching ? 1 : -1
    }

    // Safety: if this icon is torn down mid-launch, don't leave the count stuck.
    Component.onDestruction: if (launching && dockWin) dockWin.launchingCount--

    HoverHandler { id: hover }

    Image {
        id: iconImg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 12
        width: 42; height: 42
        source: "image://icon/" + item.iconName
        smooth: true; mipmap: true
        transform: [
            Translate {
                // The dragged icon tracks the cursor 1:1 (and lifts slightly); the
                // others ease as they slide aside to open the drop gap.
                // No Behavior on x: the dragged icon tracks the cursor and the
                // others snap aside / back. Animating it made dropped icons glide
                // sideways into place, which read as a glitch.
                x: item.visualDragX
                y: item.bounceY + (item.isDragged ? -8 : 0)
            },
            Scale {
                // Grow upward from the icon's base (not its center), macOS-style,
                // so the icon lifts out of the dock on hover instead of bloating
                // in place. The running dot below is anchored separately and stays.
                origin.x: iconImg.width / 2; origin.y: iconImg.height
                xScale: item.isDragged ? 1.15 : (item.magnified ? item.hoverScale : 1.0)
                yScale: item.isDragged ? 1.15 : (item.magnified ? item.hoverScale : 1.0)
                Behavior on xScale { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
                Behavior on yScale { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
            }
        ]
    }

    // App-name tooltip — small label that floats above the magnified icon on
    // hover, macOS-style. Anchored above parent.top so it sits in the dock
    // window's headroom (DockWindow's non-preview height was raised to make
    // room). z keeps it above neighbouring icons.
    Rectangle {
        id: tooltip
        z: 200
        visible: opacity > 0
        opacity: (hover.hovered && !item.anyPreviewOpen && !item.anyMenuOpen && !item.anyDragActive) ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 24
        width: tipLabel.implicitWidth + 16
        height: tipLabel.implicitHeight + 8
        radius: 7
        color: dark ? Qt.rgba(28/255, 28/255, 33/255, 0.96)
                    : Qt.rgba(250/255, 250/255, 250/255, 0.96)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.11)
        border.width: 1
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: item.name
            color: dark ? Qt.rgba(1,1,1,0.95) : Qt.rgba(0,0,0,0.85)
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    // Running indicator — macOS-style dot below icon
    // Blue for focused window, white (or dark in light mode) for other running apps
    Rectangle {
        visible: item.isRunning
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
        width:  item.isFocused ? 6 : 4
        height: width
        radius: 999
        color: item.isFocused
            ? "#0A84FF"
            : (dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.50))
        Behavior on width  { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color  { ColorAnimation  { duration: 140 } }
        // Travel with the icon while dragging / sliding aside (snap, no glide).
        transform: Translate {
            x: item.visualDragX
        }

        // Subtle glow when focused
        Rectangle {
            visible: item.isFocused
            anchors.centerIn: parent
            width: parent.width + 4; height: parent.height + 4
            radius: 999
            color: "transparent"
            border.color: Qt.rgba(10/255, 132/255, 255/255, 0.35)
            border.width: 1
            z: -1
        }
    }

    // Hyprland's new dispatcher API takes Lua, so the old
    // `dispatch focuswindow class:X` form errors with "')' expected near 'class'".
    // Focus the window, then raise it to the top of the z-order — otherwise a
    // focused floating window can stay buried under other floating windows.
    Process {
        id: focusProc
        command: ["hyprctl", "eval",
                  'hl.dispatch(hl.dsp.focus({ window = "class:' + item.wmClass + '" })); '
                  + 'hl.dispatch(hl.dsp.window.bring_to_top({}))']
    }
    Process { id: launchProc; command: item.execCmd.length > 0 ? item.execCmd : ["true"] }
    // Un-hide: move the app's Hidden windows back to the active workspace and
    // focus one. Built per-click (addresses vary), so no static command here.
    Process { id: restoreProc; command: ["true"] }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        // ── Drag-to-reorder (pinned icons) ──
        // Press a pinned icon and drag sideways past a small threshold to pick it
        // up and reorder; release to drop. No long-press needed (that was being
        // cancelled the instant the pointer moved). Coordinates are mapped into
        // the dock's content item — stable on Wayland, unlike global coords.
        onPressed: (mouse) => {
            item._didDrag = false
            if (mouse.button === Qt.LeftButton && item.dockWin) {
                item._pressed = true
                item._dragging = false
                item._pressX = item.mapToItem(item.dockWin.rowItem, mouse.x, mouse.y).x
            }
        }
        onPositionChanged: (mouse) => {
            if (!item._pressed || !item.dockWin) return
            let cx = item.mapToItem(item.dockWin.rowItem, mouse.x, mouse.y).x
            if (!item._dragging && Math.abs(cx - item._pressX) > 8) {
                item._dragging = true
                item._didDrag = true
                item.dockWin.beginDrag({
                    name: item.name, wmClass: item.wmClass,
                    iconName: item.iconName, execCmd: item.execCmd
                }, item.pinnedIndex)
            }
            if (item._dragging) item.dockWin.updateDrag(cx - item._pressX, cx)
        }
        onReleased: {
            item._pressed = false
            if (item._dragging) {
                item._dragging = false
                let w = item.dockWin
                if (w) w.endDrag()
            }
        }
        onCanceled: {
            item._pressed = false
            if (item._dragging) {
                item._dragging = false
                let w = item.dockWin
                if (w) w.endDrag()
            }
        }

        onClicked: (mouse) => {
            // A drag just finished — swallow the trailing click so it doesn't
            // also focus/launch the app.
            if (item._didDrag) { item._didDrag = false; return }

            // Right click anywhere on the icon → open the macOS-style context menu,
            // anchored to the icon's centre (same anchor maths as the preview).
            if (mouse.button === Qt.RightButton) {
                if (item.dockWin) {
                    let p = item.mapToItem(item.dockWin.contentItem, item.width / 2, 0)
                    item.dockWin.openMenu({
                        name: item.name, wmClass: item.wmClass,
                        iconName: item.iconName, execCmd: item.execCmd
                    }, p.x)
                }
                return
            }

            // If this app's windows are Hidden (special:minimized), a left click
            // brings them back to the current workspace instead of the normal
            // focus/launch path — mirroring "click a minimised Dock icon".
            let hidden = item.hiddenWindows
            if (hidden.length > 0) {
                if (item.dockWin) item.dockWin.previewOpen = false
                // Lua dispatch (this Hyprland uses the Lua plugin) — move each
                // hidden window back to the active workspace, then focus one.
                let stmts = hidden.map(w =>
                    'hl.dispatch(hl.dsp.window.move({ window = "address:' + w.address
                    + '", workspace = ' + DockService.activeWs + ', follow = false }))')
                stmts.push('hl.dispatch(hl.dsp.focus({ window = "address:' + hidden[0].address + '" }))')
                restoreProc.command = ["hyprctl", "eval", stmts.join("; ")]
                restoreProc.running = true
                return
            }

            let wins = item.windows
            // Guard on wins.length, not isRunning. DockService polls every 500ms
            // and sets clientsByClass + runningClasses sequentially, so isRunning
            // can lag while windows has already updated — leading to a spurious
            // bounce + relaunch when the user clicks a clearly-running icon.
            if (wins.length > 1) {
                // Multiple windows → toggle preview, anchored to this icon's center
                if (item.dockWin) {
                    let p = item.mapToItem(item.dockWin.contentItem, item.width / 2, 0)
                    item.dockWin.togglePreview(item.wmClass, item.iconName, p.x)
                }
            } else if (wins.length === 1 || item.isRunning) {
                if (item.dockWin) item.dockWin.previewOpen = false
                focusProc.running = true
            } else if (item.execCmd.length > 0) {
                item.launching = true
                launchTimeout.restart()
                launchProc.running = true
            }
        }
    }
}
