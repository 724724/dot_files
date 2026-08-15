import Quickshell
import Quickshell.Io
import QtQuick
import "../icons" as Icons

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

    readonly property bool horizontalDock: !dockWin || dockWin.horizontalDock
    readonly property bool leftDock: dockWin && dockWin.leftDock
    readonly property bool rightDock: dockWin && dockWin.rightDock

    readonly property real densityScale: dockWin ? dockWin.dockScale : 1
    readonly property real baseIconSize: 42 * densityScale
    readonly property real iconInset: 12 * densityScale
    readonly property real slotPadding: 16 * densityScale
    readonly property real hoverScale: DockService.iconZoomScale
    property real hoverProgress: magnified ? 1 : 0
    Behavior on hoverProgress { AppleSpring { spring: 13 } }
    readonly property real expandedSlotSize: baseIconSize + slotPadding
        + baseIconSize * (hoverScale - 1) * hoverProgress
    implicitWidth: horizontalDock ? expandedSlotSize : 66 * densityScale
    implicitHeight: horizontalDock ? 66 * densityScale : expandedSlotSize

    readonly property bool isRunning: DockService.runningClasses.indexOf(wmClass.toLowerCase()) >= 0
    readonly property bool isFocused: DockService.focusedClass === wmClass.toLowerCase()
    // Blocked while a Pomodoro focus phase is active and this app isn't allowed.
    readonly property bool focusBlocked: DockService.focusActive
        && !DockService.isFocusAllowed(execCmd)
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
    property int transientIndex: -1 // index in DockWindow.extraApps
    property real _pressAxis: 0      // press point in dockRow's layout axis
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
        // Crossing the separator into the running side previews the committed
        // layout immediately: siblings after the dragged pin close its old gap.
        if (dp < 0) return src >= 0 && pinnedIndex > src ? -dockWin.pitch : 0
        if (src < 0) return pinnedIndex >= dp ? dockWin.pitch : 0      // inserting a new pin
        if (src < dp && pinnedIndex > src && pinnedIndex <= dp) return -dockWin.pitch
        if (src > dp && pinnedIndex >= dp && pinnedIndex < src) return dockWin.pitch
        return 0
    }
    readonly property real directDragAxis: isDragged ? dockWin.dragDeltaAxis : 0
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
    // When an unpinned app moves into the pinned section, only transient
    // siblings before its original position move with the separator. Siblings
    // after it and Trash stay still, so the source hole closes symmetrically.
    readonly property real transientPinShift: {
        if (!dockWin || !dockWin.nativePinDropActive || isDragged
                || transientIndex < 0) return 0
        return transientIndex < dockWin.dragSourceTransientIndex
            ? dockWin.pitch : 0
    }
    transform: Translate {
        x: item.horizontalDock ? item.transientPinShift : 0
        y: item.horizontalDock ? 0 : item.transientPinShift
        Behavior on x {
            enabled: item.anyDragActive
            AppleSpring { spring: 13; epsilon: 0.25 }
        }
        Behavior on y {
            enabled: item.anyDragActive
            AppleSpring { spring: 13; epsilon: 0.25 }
        }
    }

    // Also stays enlarged for the whole launch bounce, not just on hover. No
    // hover magnify while a preview / menu / drag is in progress.
    readonly property bool zoomInteractionAllowed: DockService.iconZoomEnabled
        && !(dockWin && dockWin.separatorInteractionActive)
    readonly property bool tooltipInteractionAllowed:
        !(dockWin && dockWin.separatorInteractionActive)
    // Keep the tooltip a fixed logical distance from the icon's *rendered*
    // edge. Using the live scale makes it follow both the zoom slider and the
    // hover spring instead of jumping between two precomputed offsets.
    readonly property real tooltipGap: 8
    readonly property bool magnified: launching
        || (zoomInteractionAllowed && (previewActive || menuActive
            || (hover.hovered && !anyPreviewOpen && !anyMenuOpen
                && !anyDragActive && !anyLaunchpadDropActive)))
    readonly property real iconScale: isDragged ? 1.15
        : (1 + (hoverScale - 1) * hoverProgress)
            * (_pressed ? ThemeService.pressScale : 1)
    z: isDragged ? 1000 : 0

    // Keep launch motion on a normalized, fixed-time track. Dock density only
    // changes the travel distance, never the bounce period; icon zoom is not
    // part of this clock either.
    property real launchProgress: 0
    readonly property real launchOffset: 16 * densityScale * launchProgress
    property bool launching: false

    // The event-driven window refresh ends launch feedback as soon as it appears.
    onIsRunningChanged: if (isRunning) launching = false

    Timer {
        id: launchTimeout
        interval: 15000   // give up if the launched window never registers
        onTriggered: item.launching = false
    }

    SequentialAnimation on launchProgress {
        id: launchBounce
        running: item.launching
        loops: Animation.Infinite
        onStopped: item.launchProgress = 0

        NumberAnimation {
            from: 0
            to: 1
            duration: 560
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            from: 1
            to: 0
            duration: 560
            easing.type: Easing.InQuad
        }
    }
    onLaunchingChanged: {
        // Keep the dock revealed for the whole bounce (DockWindow watches this).
        if (dockWin) dockWin.launchingCount += launching ? 1 : -1
    }

    // Safety: if this icon is torn down mid-launch, don't leave the count stuck.
    Component.onDestruction: if (launching && dockWin) dockWin.launchingCount--

    HoverHandler { id: hover }

    Icons.AppIcon {
        id: iconImg
        // Explicit square geometry avoids stale conditional anchors when the
        // Dock moves bottom -> left -> right (Qt can otherwise briefly keep an
        // old anchor while the size-drag changes the item's dimensions).
        x: item.horizontalDock ? (parent.width - width) / 2
            : item.leftDock ? item.iconInset
            : parent.width - width - item.iconInset
        y: item.horizontalDock ? item.iconInset : (parent.height - height) / 2
        width: item.baseIconSize
        height: item.baseIconSize
        iconName: item.iconName
        resolvePriority: 100
        appClass: item.wmClass
        desktopId: item.execCmd && item.execCmd.length >= 2 && item.execCmd[0] === "gtk-launch"
            ? item.execCmd[1] : ""
        smooth: true; mipmap: true

        // Dark-grey mask over apps that are blocked during a focus phase. A child
        // of the icon so it inherits the same hover/launch transforms below.
        Rectangle {
            anchors.fill: parent
            visible: item.focusBlocked
            radius: Math.max(3, 9 * item.densityScale)
            color: Qt.rgba(0.10, 0.10, 0.11, 0.62)
            Text {
                anchors.centerIn: parent
                text: "󰌾"
                color: Qt.rgba(1, 1, 1, 0.85)
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: Math.max(8, 18 * item.densityScale)
            }
        }

        transform: [
            Translate {
                // Apply launch feedback directly from its fixed-time phase. A
                // second spring here used to low-pass the motion and made larger
                // Dock sizes appear progressively slower.
                x: item.horizontalDock ? 0
                    : item.leftDock ? item.launchOffset : -item.launchOffset
                y: item.horizontalDock ? -item.launchOffset : 0
            },
            Translate {
                // The dragged icon tracks the cursor 1:1 (and lifts slightly); the
                // release spring is disabled during the grab so tracking stays 1:1.
                x: item.horizontalDock ? item.directDragAxis
                    : item.leftDock
                        ? (item.isDragged ? 8 * item.densityScale : 0)
                        : -(item.isDragged ? 8 * item.densityScale : 0)
                y: item.horizontalDock
                    ? -(item.isDragged ? 8 * item.densityScale : 0)
                    : item.directDragAxis
                Behavior on x {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
                Behavior on y {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
            },
            Translate {
                x: item.horizontalDock ? item.reorderShift : 0
                y: item.horizontalDock ? 0 : item.reorderShift
                Behavior on x {
                    enabled: item.anyDragActive
                    AppleSpring {}
                }
                Behavior on y {
                    enabled: item.anyDragActive
                    AppleSpring {}
                }
            },
            Translate {
                // Animated gap for a launchpad app dragged over the dock.
                x: item.horizontalDock ? item.launchpadShift : 0
                y: item.horizontalDock ? 0 : item.launchpadShift
                Behavior on x { AppleSpring {} }
                Behavior on y { AppleSpring {} }
            },
            Scale {
                // Grow upward from the icon's base (not its center), macOS-style,
                // so the icon lifts out of the dock on hover instead of bloating
                // in place. The running dot below is anchored separately and stays.
                origin.x: item.leftDock ? 0
                    : item.rightDock ? iconImg.width : iconImg.width / 2
                origin.y: item.horizontalDock ? iconImg.height : iconImg.height / 2
                xScale: item.iconScale
                yScale: item.iconScale
            }
        ]
    }

    // App-name tooltip — small label that follows the live transformed icon
    // boundary. Explicit geometry is also transactional across Dock edges.
    Rectangle {
        id: tooltip
        z: 200
        visible: opacity > 0
        opacity: (item.tooltipInteractionAllowed && hover.hovered
            && !item.anyPreviewOpen && !item.anyMenuOpen
            && !item.anyDragActive && !item.anyLaunchpadDropActive) ? 1 : 0
        x: item.horizontalDock ? (parent.width - width) / 2
            : item.leftDock
                ? item.iconInset + item.baseIconSize * item.iconScale
                    + item.tooltipGap
                : parent.width - item.iconInset
                    - item.baseIconSize * item.iconScale
                    - item.tooltipGap - width
        y: item.horizontalDock
            ? item.iconInset - item.baseIconSize * (item.iconScale - 1)
                - item.tooltipGap - height
            : (parent.height - height) / 2
        width: tipLabel.implicitWidth + 16 * item.densityScale
        height: tipLabel.implicitHeight + 8 * item.densityScale
        radius: Math.max(4, 7 * item.densityScale)
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
        id: runningIndicator

        visible: item.isRunning
        width: item.isFocused
            ? Math.max(3, 6 * item.densityScale)
            : Math.max(2, 4 * item.densityScale)
        height: width
        x: item.horizontalDock ? (parent.width - width) / 2
            : item.leftDock ? 3 * item.densityScale
            : parent.width - width - 3 * item.densityScale
        y: item.horizontalDock ? parent.height - height - 3 * item.densityScale
            : (parent.height - height) / 2
        radius: 999
        color: item.isFocused
            ? "#0A84FF"
            : (dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.50))
        Behavior on width { AppleSpring { spring: 13 } }
        // Travel 1:1 during drag, then inherit the same release/spacing springs.
        transform: [
            Translate {
                x: item.horizontalDock ? item.directDragAxis : 0
                y: item.horizontalDock ? 0 : item.directDragAxis
                Behavior on x {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
                Behavior on y {
                    enabled: !item.isDragged
                    SpringAnimation {
                        spring: ThemeService.spring
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
            },
            Translate {
                x: item.horizontalDock ? item.reorderShift : 0
                y: item.horizontalDock ? 0 : item.reorderShift
                Behavior on x {
                    enabled: item.anyDragActive
                    AppleSpring {}
                }
                Behavior on y {
                    enabled: item.anyDragActive
                    AppleSpring {}
                }
            },
            Translate {
                x: item.horizontalDock ? item.launchpadShift : 0
                y: item.horizontalDock ? 0 : item.launchpadShift
                Behavior on x { AppleSpring {} }
                Behavior on y { AppleSpring {} }
            }
        ]

        // Subtle glow when focused
        Rectangle {
            visible: item.isFocused
            anchors.centerIn: parent
            width: parent.width + 4 * item.densityScale
            height: parent.height + 4 * item.densityScale
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
                let p = item.mapToItem(item.dockWin.rowItem, mouse.x, mouse.y)
                item._pressAxis = item.horizontalDock ? p.x : p.y
            }
        }
        onPositionChanged: (mouse) => {
            if (!item._pressed || !item.dockWin) return
            let p = item.mapToItem(item.dockWin.rowItem, mouse.x, mouse.y)
            let axis = item.horizontalDock ? p.x : p.y
            if (!item._dragging && Math.abs(axis - item._pressAxis) > 8) {
                item._dragging = true
                item._didDrag = true
                item.dockWin.beginDrag({
                    name: item.name, wmClass: item.wmClass,
                    iconName: item.iconName, execCmd: item.execCmd
                }, item.pinnedIndex, item.transientIndex)
            }
            if (item._dragging)
                item.dockWin.updateDrag(axis - item._pressAxis, axis)
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
                    let p = item.mapToItem(item.dockWin.contentItem,
                        item.width / 2, item.height / 2)
                    item.dockWin.openMenu({
                        name: item.name, wmClass: item.wmClass,
                        iconName: item.iconName, execCmd: item.execCmd
                    }, p.x, p.y)
                }
                return
            }

            // Focus mode: a disallowed app can't be launched or focused. Fire the
            // "blocked" notification and stop before any activation happens.
            if (item.focusBlocked) {
                DockService.notifyFocusBlocked(item.name)
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
                    let p = item.mapToItem(item.dockWin.contentItem,
                        item.width / 2, item.height / 2)
                    item.dockWin.togglePreview(item.wmClass, item.iconName, p.x, p.y)
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
