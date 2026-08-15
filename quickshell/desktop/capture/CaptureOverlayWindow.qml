pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: overlay

    required property var modelData
    screen: modelData

    property real localSelectionX: Math.round(width * 0.2)
    property real localSelectionY: Math.round(height * 0.2)
    property real localSelectionWidth: Math.round(width * 0.6)
    property real localSelectionHeight: Math.round(height * 0.6)
    property var hoveredWindow: null
    property string portionGesture: ""
    property real gestureStartPointerX: 0
    property real gestureStartPointerY: 0
    property real gestureStartX: 0
    property real gestureStartY: 0
    property real gestureStartWidth: 0
    property real gestureStartHeight: 0
    property real pointerX: width / 2
    property real pointerY: height / 2

    readonly property real portionHandleRadius: 28
    readonly property real minimumSelectionSize: 32

    readonly property bool active: CaptureService.overlayActive
    readonly property bool selectedScreen: CaptureService.targetScreenName === String(modelData ? modelData.name : "")
    readonly property bool portionMode: CaptureService.baseMode === "portion"
    readonly property bool quickPortionMode: CaptureService.quickPortionMode
    readonly property bool windowMode: CaptureService.baseMode === "window"
    readonly property bool screenMode: CaptureService.baseMode === "screen"
    readonly property var displayWindow: {
        if (!windowMode) return null
        if (hoveredWindow) return hoveredWindow
        const address = CaptureService.selectedWindowAddress
        if (address === "") return null
        const clients = CaptureService.windowClients || []
        for (let i = 0; i < clients.length; i++)
            if (String(clients[i].address || "") === address) return clients[i]
        return null
    }
    readonly property real focusX: screenMode ? 2
        : portionMode ? localSelectionX
        : displayWindow && Array.isArray(displayWindow.at)
            ? Number(displayWindow.at[0]) - Number(modelData.x) : width * 0.35
    readonly property real focusY: screenMode ? 2
        : portionMode ? localSelectionY
        : displayWindow && Array.isArray(displayWindow.at)
            ? Number(displayWindow.at[1]) - Number(modelData.y) : height * 0.35
    readonly property real focusWidth: screenMode ? Math.max(0, width - 4)
        : portionMode ? localSelectionWidth
        : displayWindow && Array.isArray(displayWindow.size)
            ? Number(displayWindow.size[0]) : width * 0.3
    readonly property real focusHeight: screenMode ? Math.max(0, height - 4)
        : portionMode ? localSelectionHeight
        : displayWindow && Array.isArray(displayWindow.size)
            ? Number(displayWindow.size[1]) : height * 0.3
    readonly property bool focusVisible: selectedScreen && (screenMode
        || (portionMode && localSelectionWidth >= 8 && localSelectionHeight >= 8)
        || (windowMode && displayWindow !== null))
    readonly property bool cameraCursorVisible: active && !CaptureService.toolbarHovered
        && !CaptureService.countingDown && (
        (windowMode && hoveredWindow !== null)
        || (quickPortionMode && _insideSelection(pointerX, pointerY)
            && _portionCornerAt(pointerX, pointerY) === ""))

    // Keep one transparent, input-empty surface mapped per output. Remapping a
    // layer surface only after the toolbar appears can lose the first pointer
    // enter/grab; changing the input region is immediate and deterministic.
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-capture-overlay"
    // The selection canvas and toolbar share this surface. Their QML z-order now
    // decides pointer ownership instead of compositor surface creation order.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active && selectedScreen
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Do not switch from an explicit empty mask back to `null` on an already
    // mapped surface: that transition is not reliably committed by this Qt/QS
    // combination. An explicit full-surface region makes pointer delivery
    // deterministic for hover, clicks and corner grabs.
    mask: active ? activeRegion : emptyRegion
    Region {
        id: activeRegion
        x: 0
        y: 0
        width: overlay.width
        height: overlay.height
    }
    Region { id: emptyRegion }

    HyprlandFocusGrab {
        windows: [overlay]
        active: overlay.active && overlay.selectedScreen
    }

    Shortcut {
        sequence: "Escape"
        enabled: overlay.active && overlay.selectedScreen
        onActivated: CaptureService.hide()
    }

    function _clientAt(localX, localY) {
        const gx = Number(modelData.x) + Number(localX)
        const gy = Number(modelData.y) + Number(localY)
        const clients = CaptureService.windowClients || []
        let best = null
        let bestFocus = Number.MAX_SAFE_INTEGER
        for (let i = 0; i < clients.length; i++) {
            const win = clients[i]
            if (String(win.monitorName || "") !== String(modelData.name || "")) continue
            if (!Array.isArray(win.at) || !Array.isArray(win.size)) continue
            const x = Number(win.at[0]), y = Number(win.at[1])
            const w = Number(win.size[0]), h = Number(win.size[1])
            if (w < 8 || h < 8 || gx < x || gy < y || gx >= x + w || gy >= y + h) continue
            const focus = Number(win.focusHistoryID)
            if (!best || (!isNaN(focus) && focus < bestFocus)) {
                best = win
                bestFocus = isNaN(focus) ? bestFocus : focus
            }
        }
        return best
    }

    function _defaultSelection() {
        const saved = CaptureService.portionSelectionForScreen(
            String(modelData.name || ""))
        if (saved !== null) {
            localSelectionX = Math.max(0, Math.min(width - 8,
                saved.x - Number(modelData.x)))
            localSelectionY = Math.max(0, Math.min(height - 8,
                saved.y - Number(modelData.y)))
            localSelectionWidth = Math.max(8,
                Math.min(width - localSelectionX, saved.width))
            localSelectionHeight = Math.max(8,
                Math.min(height - localSelectionY, saved.height))
        } else {
            localSelectionWidth = Math.max(160, Math.round(width * 0.6))
            localSelectionHeight = Math.max(100, Math.round(height * 0.6))
            localSelectionX = Math.round((width - localSelectionWidth) / 2)
            localSelectionY = Math.round((height - localSelectionHeight) / 2)
        }
        if (selectedScreen)
            CaptureService.updateSelection(modelData, localSelectionX, localSelectionY,
                localSelectionWidth, localSelectionHeight)
    }

    function _commitSelection() {
        CaptureService.updateSelection(modelData, localSelectionX, localSelectionY,
            localSelectionWidth, localSelectionHeight)
    }

    function _portionCornerAt(x, y) {
        if (!portionMode || !selectedScreen || localSelectionWidth < 8
                || localSelectionHeight < 8) return ""
        const radius = portionHandleRadius
        const left = localSelectionX
        const right = localSelectionX + localSelectionWidth
        const top = localSelectionY
        const bottom = localSelectionY + localSelectionHeight
        if (Math.abs(x - left) <= radius && Math.abs(y - top) <= radius) return "tl"
        if (Math.abs(x - right) <= radius && Math.abs(y - top) <= radius) return "tr"
        if (Math.abs(x - left) <= radius && Math.abs(y - bottom) <= radius) return "bl"
        if (Math.abs(x - right) <= radius && Math.abs(y - bottom) <= radius) return "br"
        return ""
    }

    function _insideSelection(x, y) {
        return selectedScreen && localSelectionWidth >= 8 && localSelectionHeight >= 8
            && x >= localSelectionX && x <= localSelectionX + localSelectionWidth
            && y >= localSelectionY && y <= localSelectionY + localSelectionHeight
    }

    function _portionCursor(x, y) {
        const corner = _portionCornerAt(x, y)
        if (corner === "tl" || corner === "br") return Qt.SizeFDiagCursor
        if (corner === "tr" || corner === "bl") return Qt.SizeBDiagCursor
        if (_insideSelection(x, y))
            return quickPortionMode ? Qt.BlankCursor : Qt.SizeAllCursor
        return Qt.CrossCursor
    }

    function _beginPortionGesture(x, y) {
        gestureStartPointerX = x
        gestureStartPointerY = y
        gestureStartX = localSelectionX
        gestureStartY = localSelectionY
        gestureStartWidth = localSelectionWidth
        gestureStartHeight = localSelectionHeight

        const corner = _portionCornerAt(x, y)
        if (corner !== "") portionGesture = "resize-" + corner
        else if (_insideSelection(x, y))
            portionGesture = quickPortionMode ? "capture" : "move"
        else {
            portionGesture = "create"
            localSelectionX = x
            localSelectionY = y
            localSelectionWidth = 0
            localSelectionHeight = 0
        }
    }

    function _updatePortionGesture(x, y) {
        if (portionGesture === "") return
        if (portionGesture === "capture") return
        const px = Math.max(0, Math.min(width, x))
        const py = Math.max(0, Math.min(height, y))
        const dx = px - gestureStartPointerX
        const dy = py - gestureStartPointerY

        if (portionGesture === "create") {
            const startX = Math.max(0, Math.min(width, gestureStartPointerX))
            const startY = Math.max(0, Math.min(height, gestureStartPointerY))
            localSelectionX = Math.min(startX, px)
            localSelectionY = Math.min(startY, py)
            localSelectionWidth = Math.abs(px - startX)
            localSelectionHeight = Math.abs(py - startY)
            return
        }

        if (portionGesture === "move") {
            localSelectionX = Math.max(0, Math.min(width - gestureStartWidth,
                gestureStartX + dx))
            localSelectionY = Math.max(0, Math.min(height - gestureStartHeight,
                gestureStartY + dy))
            return
        }

        const startRight = gestureStartX + gestureStartWidth
        const startBottom = gestureStartY + gestureStartHeight
        const movesLeft = portionGesture === "resize-tl" || portionGesture === "resize-bl"
        const movesTop = portionGesture === "resize-tl" || portionGesture === "resize-tr"
        let left = movesLeft
            ? Math.max(0, Math.min(startRight - minimumSelectionSize, gestureStartX + dx))
            : gestureStartX
        let right = movesLeft ? startRight
            : Math.max(gestureStartX + minimumSelectionSize,
                Math.min(width, startRight + dx))
        let top = movesTop
            ? Math.max(0, Math.min(startBottom - minimumSelectionSize, gestureStartY + dy))
            : gestureStartY
        let bottom = movesTop ? startBottom
            : Math.max(gestureStartY + minimumSelectionSize,
                Math.min(height, startBottom + dy))
        localSelectionX = left
        localSelectionY = top
        localSelectionWidth = right - left
        localSelectionHeight = bottom - top
    }

    function _finishPortionGesture(commit, releaseX, releaseY) {
        if (portionGesture === "") return
        if (portionGesture === "capture") {
            const shouldCapture = commit && _insideSelection(releaseX, releaseY)
                && _portionCornerAt(releaseX, releaseY) === ""
            portionGesture = ""
            if (shouldCapture) {
                _commitSelection()
                CaptureService.trigger()
            }
            return
        }
        if (!commit || localSelectionWidth < 8 || localSelectionHeight < 8) {
            localSelectionX = gestureStartX
            localSelectionY = gestureStartY
            localSelectionWidth = gestureStartWidth
            localSelectionHeight = gestureStartHeight
        } else {
            _commitSelection()
        }
        portionGesture = ""
    }

    onActiveChanged: {
        hoveredWindow = null
        portionGesture = ""
        if (active && portionMode && selectedScreen) _defaultSelection()
    }

    Connections {
        target: CaptureService

        function onSelectionResetRequested(screenName) {
            if (screenName === String(overlay.modelData ? overlay.modelData.name : "")
                    && CaptureService.baseMode === "portion")
                overlay._defaultSelection()
        }
    }

    MouseArea {
        id: targetArea
        anchors.fill: parent
        z: 100
        enabled: overlay.active && !CaptureService.countingDown
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: overlay.windowMode && overlay.hoveredWindow !== null
            ? Qt.BlankCursor : overlay.windowMode ? Qt.ArrowCursor
            : overlay.portionMode ? overlay._portionCursor(overlay.pointerX, overlay.pointerY)
            : Qt.CrossCursor

        onPositionChanged: function(mouse) {
            overlay.pointerX = mouse.x
            overlay.pointerY = mouse.y
            if (overlay.windowMode) {
                overlay.hoveredWindow = overlay._clientAt(mouse.x, mouse.y)
                CaptureService.reportWindowHover(overlay.hoveredWindow)
                if (overlay.hoveredWindow !== null)
                    CaptureService.setTargetScreen(overlay.modelData)
            } else if (overlay.portionMode && targetArea.pressed)
                overlay._updatePortionGesture(mouse.x, mouse.y)
        }

        onExited: if (overlay.windowMode) {
            overlay.hoveredWindow = null
            CaptureService.reportWindowHover(null)
        }

        onPressed: function(mouse) {
            if (CaptureService.optionsOpen) {
                CaptureService.optionsOpen = false
                mouse.accepted = true
                return
            }
            if (CaptureService.folderPickerOpen) {
                CaptureService.folderPickerOpen = false
                CaptureService.optionsOpen = true
                mouse.accepted = true
                return
            }
            CaptureService.setTargetScreen(overlay.modelData)
            if (overlay.screenMode) {
                CaptureService.updateSelection(overlay.modelData, 0, 0,
                    overlay.width, overlay.height)
            } else if (overlay.windowMode) {
                const win = overlay._clientAt(mouse.x, mouse.y)
                if (win) {
                    CaptureService.selectWindow(overlay.modelData, win)
                    CaptureService.trigger()
                }
            } else if (overlay.portionMode) {
                overlay._beginPortionGesture(mouse.x, mouse.y)
            }
        }

        onReleased: function(mouse) {
            if (overlay.portionMode)
                overlay._finishPortionGesture(true, mouse.x, mouse.y)
        }
        onCanceled: if (overlay.portionMode)
            overlay._finishPortionGesture(false, overlay.pointerX, overlay.pointerY)
    }

    // Four rectangles produce a real transparent hole without a shader. This
    // keeps the overlay nearly idle on the GPU while still matching Screenshot's
    // dimmed-selection treatment.
    Rectangle {
        visible: overlay.active
        x: 0; y: 0; width: parent.width
        height: overlay.focusVisible ? Math.max(0, overlay.focusY) : parent.height
        color: Qt.rgba(0, 0, 0, overlay.focusVisible ? 0.34 : 0.46)
    }
    Rectangle {
        visible: overlay.active && overlay.focusVisible
        x: 0; y: overlay.focusY
        width: Math.max(0, overlay.focusX); height: Math.max(0, overlay.focusHeight)
        color: Qt.rgba(0, 0, 0, 0.34)
    }
    Rectangle {
        visible: overlay.active && overlay.focusVisible
        x: overlay.focusX + overlay.focusWidth; y: overlay.focusY
        width: Math.max(0, parent.width - x); height: Math.max(0, overlay.focusHeight)
        color: Qt.rgba(0, 0, 0, 0.34)
    }
    Rectangle {
        visible: overlay.active && overlay.focusVisible
        x: 0; y: overlay.focusY + overlay.focusHeight; width: parent.width
        height: Math.max(0, parent.height - y)
        color: Qt.rgba(0, 0, 0, 0.34)
    }

    Rectangle {
        id: selectionFrame
        visible: overlay.active && overlay.focusVisible
        x: overlay.focusX
        y: overlay.focusY
        width: Math.max(1, overlay.focusWidth)
        height: Math.max(1, overlay.focusHeight)
        color: overlay.windowMode && overlay.hoveredWindow !== null
            ? Qt.rgba(0.03, 0.49, 0.94, 0.24) : "transparent"
        border.width: 2
        border.color: overlay.windowMode && overlay.hoveredWindow !== null
            ? "#2997ff" : "#f5f5f7"
        radius: overlay.windowMode ? 10 : 2

        Behavior on color { ColorAnimation { duration: 65 } }
        Behavior on border.color { ColorAnimation { duration: 65 } }

        Repeater {
            model: overlay.portionMode ? 4 : 0
            delegate: Item {
                id: handle
                required property int index
                width: 36; height: 36
                x: (index % 2 === 0 ? -width / 2 : selectionFrame.width - width / 2)
                y: (index < 2 ? -height / 2 : selectionFrame.height - height / 2)
                z: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    readonly property string gestureName: ["resize-tl", "resize-tr",
                        "resize-bl", "resize-br"][handle.index]
                    readonly property bool grabbed: overlay.portionGesture === gestureName
                    color: grabbed ? "#2997ff" : "#f5f5f7"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                    scale: grabbed ? 1.18 : 1
                    Behavior on scale {
                        SpringAnimation { spring: 22; damping: 1; epsilon: 0.002 }
                    }
                }
            }
        }

        Rectangle {
            visible: overlay.portionMode
            anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
            width: sizeLabel.implicitWidth + 14
            height: 24
            radius: 12
            color: Qt.rgba(0.08, 0.08, 0.09, 0.74)
            Text {
                id: sizeLabel
                anchors.centerIn: parent
                text: Math.round(overlay.localSelectionWidth) + " × "
                    + Math.round(overlay.localSelectionHeight)
                color: "white"
                font.family: "SF Pro Display"
                font.pixelSize: 12
            }
        }
    }

    // Wayland cursor-shape protocols only expose generic cursor names. Hide the
    // system cursor over a directly capturable target and draw a tiny camera in
    // the same overlay instead; it disappears before grim runs with the overlay.
    Item {
        visible: overlay.cameraCursorVisible
        enabled: false
        z: 200
        x: Math.max(2, Math.min(overlay.width - width - 2, overlay.pointerX + 7))
        y: Math.max(2, Math.min(overlay.height - height - 2, overlay.pointerY + 7))
        width: 17
        height: 14
        scale: overlay.portionGesture === "capture" ? 0.92 : 1

        Behavior on scale {
            SpringAnimation { spring: 24; damping: 1; epsilon: 0.002 }
        }

        Rectangle {
            anchors { left: parent.left; bottom: parent.bottom }
            width: 15.5; height: 10.5; radius: 2.5
            color: "#f5f5f7"
            border.width: 0.5
            border.color: Qt.rgba(0, 0, 0, 0.46)
        }
        Rectangle {
            x: 2.5; y: 1
            width: 5.5; height: 3.5; radius: 1
            color: "#f5f5f7"
            border.width: 0.5
            border.color: Qt.rgba(0, 0, 0, 0.46)
        }
        Rectangle {
            x: 5.5; y: 5.5
            width: 5; height: 5; radius: 2.5
            color: "#707074"
            border.width: 1
            border.color: "#d9d9dc"
        }
    }

    CaptureToolbarWindow {
        id: captureToolbar
        anchors.fill: parent
        selectedScreen: overlay.selectedScreen
        z: 1000
    }
}
