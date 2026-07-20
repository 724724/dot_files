import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: item

    property string name: ""
    property string wmClass: ""
    property string iconName: ""
    property var execCmd: []
    property bool dark: true
    readonly property string iconSource: iconName.includes("://") ? iconName
        : iconName.startsWith("/") ? "file://" + iconName
        : iconName ? "image://icon/" + iconName
        : "image://icon/application-x-executable"
    // Direct reference to DockWindow — avoids signals with complex var types
    property var dockWin: null
    property bool launchpadRightSide: false

    // Magnify on hover, macOS-style. hoverScale drives both the visual Scale
    // (below) and the layout width here, so the widened slot shoves neighbouring
    // icons aside in the Row instead of overlapping them. +16 keeps the icon's
    // 8px side padding constant at any zoom (42 + 16 = 58 when idle).
    readonly property real hoverScale: 1.75
    implicitWidth: 42 * (magnified ? hoverScale : 1) + 16
    implicitHeight: 66
    Behavior on implicitWidth { AppleSpring { spring: 13 } }

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
    readonly property bool anyLaunchpadDropActive: dockWin ? dockWin.launchpadDropActive : false
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
    readonly property real directDragX: isDragged ? dockWin.dragDeltaX : 0
    readonly property real reorderShift: anyDragActive && !isDragged ? dragShift : 0

    // Gap for a launchpad app being dragged over the dock: the icons spread apart
    // around the hovered insertion slot — those before it ease half a pitch left,
    // those at/after it ease half a pitch right — opening a full-pitch space
    // centred on the cursor. Unlike the dock's own snap-reorder this one animates
    // (Behavior below) so the icons glide apart, macOS-style.
    readonly property real launchpadShift: {
        if (!dockWin || !dockWin.launchpadDropActive) return 0
        let dp = dockWin.launchpadDropIndex
        if (dp < 0) return 0
        let half = dockWin.pitch / 2
        if (pinnedIndex < 0) return launchpadRightSide ? half : 0
        return pinnedIndex >= dp ? half : -half
    }

    // Also stays enlarged for the whole launch bounce, not just on hover. No
    // hover magnify while a preview / menu / drag is in progress.
    readonly property bool magnified: previewActive || menuActive || launching
        || (hover.hovered && !anyPreviewOpen && !anyMenuOpen && !anyDragActive && !anyLaunchpadDropActive)
    readonly property real iconScale: isDragged ? 1.15
        : (magnified ? hoverScale : 1) * (_pressed ? ThemeService.pressScale : 1)
    z: isDragged ? 1000 : 0

    // Launch feedback retargets a critically damped spring until the app appears.
    property real bounceY: 0
    property bool launching: false
    property bool launchLifted: false

    Behavior on bounceY { AppleSpring { spring: 11 } }

    // The event-driven window refresh ends launch feedback as soon as it appears.
    onIsRunningChanged: if (isRunning) launching = false

    Timer {
        id: launchTimeout
        interval: 15000   // give up if the launched window never registers
        onTriggered: item.launching = false
    }

    Timer {
        id: launchPulse
        running: item.launching
        repeat: true
        interval: 336
        onTriggered: item.launchLifted = !item.launchLifted
    }
    onLaunchLiftedChanged: bounceY = launchLifted ? -16 : 0
    onLaunchingChanged: {
        launchLifted = launching
        if (!launching) bounceY = 0
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
        source: item.iconSource
        smooth: true; mipmap: true
        onStatusChanged: {
            if (status === Image.Error
                    && source.toString() !== "image://icon/application-x-executable")
                source = "image://icon/application-x-executable"
        }
        transform: [
            Translate {
                // The dragged icon tracks the cursor 1:1 (and lifts slightly); the
                // release spring is disabled during the grab so tracking stays 1:1.
                x: item.directDragX
                y: item.bounceY + (item.isDragged ? -8 : 0)
                Behavior on x {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
            },
            Translate {
                x: item.reorderShift
                Behavior on x { AppleSpring {} }
            },
            Translate {
                // Animated "make room" gap for a launchpad app dragged over the dock.
                x: item.launchpadShift
                Behavior on x { AppleSpring {} }
            },
            Scale {
                // Grow upward from the icon's base (not its center), macOS-style,
                // so the icon lifts out of the dock on hover instead of bloating
                // in place. The running dot below is anchored separately and stays.
                origin.x: iconImg.width / 2; origin.y: iconImg.height
                xScale: item.iconScale
                yScale: item.iconScale
                Behavior on xScale { AppleSpring { spring: 13 } }
                Behavior on yScale { AppleSpring { spring: 13 } }
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
        opacity: (hover.hovered && !item.anyPreviewOpen && !item.anyMenuOpen && !item.anyDragActive && !item.anyLaunchpadDropActive) ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 24
        width: tipLabel.implicitWidth + 16
        height: tipLabel.implicitHeight + 8
        radius: 7
        color: ThemeService.popupBg
        border.color: ThemeService.stroke
        border.width: 1
        Behavior on opacity { AppleSpring { spring: 13 } }

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
        Behavior on width { AppleSpring { spring: 13 } }
        // Travel 1:1 during drag, then inherit the same release/spacing springs.
        transform: [
            Translate {
                x: item.directDragX
                Behavior on x {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
            },
            Translate {
                x: item.reorderShift
                Behavior on x { AppleSpring {} }
            },
            Translate {
                x: item.launchpadShift
                Behavior on x { AppleSpring {} }
            }
        ]

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
    Process { id: focusProc; command: ["true"] }
    // Un-hide: move the app's Hidden windows back to the active workspace and
    // focus one. Built per-click (addresses vary), so no static command here.
    Process { id: restoreProc; command: ["true"] }

    MouseArea {
        id: pointer
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
            item._pressed = true
            if (mouse.button === Qt.LeftButton && item.dockWin) {
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
            // Acting on a dock icon while the launchpad is open dismisses it, so
            // the app we focus/launch isn't left buried behind the launchpad.
            if (DockService.launchpadOpen) DockService.launchpadCloseRequested()

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
                let target = wins.length > 0 && wins[0].address
                    ? "address:" + wins[0].address : "class:" + item.wmClass
                focusProc.command = ["hyprctl", "eval",
                    'hl.dispatch(hl.dsp.focus({ window = "' + target + '" })); '
                    + 'hl.dispatch(hl.dsp.window.bring_to_top({}))']
                focusProc.running = true
            } else if (item.execCmd.length > 0) {
                item.launching = true
                launchTimeout.restart()
                Quickshell.execDetached(item.execCmd)
            }
        }
    }
}
