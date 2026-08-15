pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: win

    required property bool selectedScreen
    property bool presented: false
    readonly property real cardWidth: Math.min(660, Math.max(1, width - 20))
    readonly property real cardHeight: 60

    // The toolbar now lives inside the selected capture overlay. Sharing one
    // Wayland surface gives QML a single, deterministic pointer hierarchy:
    // toolbar controls first, then the selection canvas underneath.
    visible: selectedScreen && CaptureService.overlayActive
        && CaptureService.toolbarOpen
        && CaptureService.toolbarVisible
    enabled: visible

    function beginPresent() {
        syncToolbarPosition()
        presented = false
        reveal.restart()
    }

    function syncToolbarPosition() {
        if (toolbarDragHandler.active || width <= 0 || height <= 0) return
        const centerX = CaptureService.toolbarPositionStored
            ? CaptureService.toolbarAnchorX * width : width / 2
        const centerY = CaptureService.toolbarPositionStored
            ? CaptureService.toolbarAnchorY * height : height - 34 - cardHeight / 2
        toolbarCard.x = Math.max(8, Math.min(width - cardWidth - 8,
            centerX - cardWidth / 2))
        toolbarCard.y = Math.max(8, Math.min(height - cardHeight - 8,
            centerY - cardHeight / 2))
    }

    function publishToolbarHover() {
        CaptureService.toolbarHovered = win.visible
            && (toolbarHover.hovered || toolbarCard.controlHovered
                || toolbarHitSlop.hovered || optionsInput.containsMouse
                || optionsHitSlop.hovered || folderInput.containsMouse
                || folderHitSlop.hovered)
    }

    onWidthChanged: syncToolbarPosition()
    onHeightChanged: syncToolbarPosition()
    onVisibleChanged: {
        if (visible) beginPresent()
        else {
            reveal.stop()
            presented = false
            CaptureService.toolbarHovered = false
        }
    }

    Component.onCompleted: {
        syncToolbarPosition()
        if (visible) beginPresent()
    }

    Connections {
        target: CaptureService
        function onToolbarPositionStoredChanged() { win.syncToolbarPosition() }
        function onToolbarAnchorXChanged() { win.syncToolbarPosition() }
        function onToolbarAnchorYChanged() { win.syncToolbarPosition() }
    }

    Timer {
        id: reveal
        interval: 1
        onTriggered: if (win.visible) {
            win.presented = true
        }
    }

    CaptureHitSlop {
        id: toolbarHitSlop
        targetItem: toolbarCard
        extent: 5
        cursorShape: Qt.OpenHandCursor
        z: 0
        onHoveredChanged: win.publishToolbarHover()
    }

    Rectangle {
        id: toolbarCard
        readonly property bool controlHovered: closeHover.hovered
            || screenButton.hovered || windowButton.hovered || portionButton.hovered
            || recordScreenButton.hovered || recordWindowButton.hovered
            || recordPortionButton.hovered || optionsHover.hovered
            || primaryHover.hovered
        onControlHoveredChanged: win.publishToolbarHover()
        width: win.cardWidth
        height: win.cardHeight
        z: 1
        radius: 16
        color: ThemeService.toolbarBg
        border.width: 1
        border.color: ThemeService.stroke
        opacity: CaptureService.toolbarVisible && win.presented ? 1 : 0
        scale: CaptureService.toolbarVisible && win.presented ? 1 : 0.975
        transformOrigin: Item.Center

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale {
            SpringAnimation { spring: 18; damping: 1; epsilon: 0.002 }
        }

        HoverHandler {
            id: toolbarHover
            onHoveredChanged: win.publishToolbarHover()
        }

        // A DragHandler stays passive until the pointer crosses its threshold,
        // unlike the old full-card MouseArea which grabbed button taps first.
        // Hovering any real control disables it, so only empty chrome can move.
        DragHandler {
            id: toolbarDragHandler
            property bool dragStarted: false
            target: toolbarCard
            enabled: CaptureService.toolbarVisible
                && !CaptureService.optionsOpen
                && !CaptureService.folderPickerOpen
                && !CaptureService.countingDown
                && !toolbarCard.controlHovered
            acceptedButtons: Qt.LeftButton
            dragThreshold: 8
            xAxis.minimum: 8
            xAxis.maximum: Math.max(8, win.width - toolbarCard.width - 8)
            yAxis.minimum: 8
            yAxis.maximum: Math.max(8, win.height - toolbarCard.height - 8)
            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onActiveChanged: {
                if (active) {
                    dragStarted = true
                } else if (dragStarted) {
                    dragStarted = false
                    CaptureService.setToolbarPosition(toolbarCard.x, toolbarCard.y,
                        win.width, win.height, toolbarCard.width, toolbarCard.height)
                }
            }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 3
            z: 1

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 15
                color: closeHover.hovered ? ThemeService.controlHover
                                          : ThemeService.controlBg
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: ThemeService.textSecondary
                    font.family: "SF Pro Display"
                    font.pixelSize: 21
                    font.weight: Font.Medium
                    anchors.verticalCenterOffset: -1
                }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: CaptureService.hide() }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                color: ThemeService.separator
            }

            CaptureToolButton { id: screenButton; modeValue: "screen"; label: "Entire Screen" }
            CaptureToolButton { id: windowButton; modeValue: "window"; label: "Window" }
            CaptureToolButton { id: portionButton; modeValue: "portion"; label: "Selected Portion" }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                color: ThemeService.separator
            }

            CaptureToolButton {
                id: recordScreenButton
                modeValue: "record-screen"
                label: "Record Screen"
                recordVariant: true
            }
            CaptureToolButton {
                id: recordWindowButton
                modeValue: "record-window"
                label: "Record Window"
                recordVariant: true
            }
            CaptureToolButton {
                id: recordPortionButton
                modeValue: "record-portion"
                label: "Record Portion"
                recordVariant: true
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                Layout.leftMargin: 2
                Layout.rightMargin: 3
                color: ThemeService.separator
            }

            Rectangle {
                id: optionsButton
                Layout.preferredWidth: 82
                Layout.preferredHeight: 34
                radius: 9
                color: CaptureService.optionsOpen ? ThemeService.selectionBg
                    : optionsHover.hovered ? ThemeService.hoverBg : "transparent"
                opacity: CaptureService.recording ? 0.42 : 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "Options"
                        color: ThemeService.textSecondary
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    Text {
                        text: CaptureService.optionsOpen ? "⌃" : "⌄"
                        color: ThemeService.textSecondary
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                    }
                }
                HoverHandler { id: optionsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: !CaptureService.recording && !CaptureService.countingDown
                    onTapped: {
                        if (CaptureService.folderPickerOpen) {
                            CaptureService.folderPickerOpen = false
                            CaptureService.optionsOpen = true
                        } else {
                            CaptureService.optionsOpen = !CaptureService.optionsOpen
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                Layout.maximumWidth: 116
                Layout.preferredHeight: 36
                radius: 10
                color: CaptureService.recording ? "#ff453a"
                    : CaptureService.recordMode && !CaptureService.recorderAvailable
                        ? "#79797d" : "#087cf0"
                opacity: CaptureService.countingDown ? 0.78 : 1
                scale: primaryTap.pressed ? 0.97 : 1
                Behavior on scale {
                    SpringAnimation { spring: 20; damping: 1; epsilon: 0.002 }
                }
                Text {
                    anchors.centerIn: parent
                    text: CaptureService.primaryButtonText
                    color: "white"
                    font.family: "SF Pro Display"
                    font.pixelSize: CaptureService.countingDown ? 18 : 14
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: primaryHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: primaryTap
                    enabled: !CaptureService.countingDown
                    onTapped: CaptureService.trigger()
                }
            }
        }
    }

    CaptureHitSlop {
        id: optionsHitSlop
        targetItem: optionsCard
        extent: 5
        cursorShape: Qt.ArrowCursor
        z: 2
        onHoveredChanged: win.publishToolbarHover()
    }

    // The menu grows from Options, then returns to that same anchor on close.
    // It uses opacity/scale only, so the surface remains immediately responsive.
    Rectangle {
        id: optionsCard
        readonly property real desiredX: toolbarCard.x + optionsButton.parent.x + optionsButton.x
        x: Math.max(8, Math.min(win.width - width - 8, desiredX))
        y: toolbarCard.y >= height + 18
            ? toolbarCard.y - height - 10
            : Math.min(win.height - height - 8, toolbarCard.y + toolbarCard.height + 10)
        width: 304
        height: optionsColumn.implicitHeight + 20
        z: 3
        radius: 14
        color: ThemeService.popupBg
        border.width: 1
        border.color: ThemeService.stroke
        visible: CaptureService.toolbarOpen && CaptureService.toolbarVisible
            && (CaptureService.optionsOpen || opacity > 0.001)
        enabled: visible
        opacity: CaptureService.optionsOpen && !CaptureService.recording ? 1 : 0
        scale: CaptureService.optionsOpen && !CaptureService.recording ? 1 : 0.965
        transformOrigin: Item.BottomLeft

        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on scale {
            SpringAnimation { spring: 20; damping: 1; epsilon: 0.002 }
        }

        // Own the whole popup, including headers, separators and padding. This
        // keeps the selection canvas and its camera cursor behind the menu even
        // where there is no actionable row.
        MouseArea {
            id: optionsInput
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            cursorShape: Qt.ArrowCursor
            onContainsMouseChanged: win.publishToolbarHover()
            onPressed: function(mouse) { mouse.accepted = true }
        }

        Column {
            id: optionsColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            enabled: CaptureService.optionsOpen && !CaptureService.recording
            spacing: 0
            z: 1

            Text {
                width: parent.width
                height: 25
                leftPadding: 34
                text: "Save To"
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
            CaptureOptionRow {
                width: parent.width
                label: "Desktop"
                selected: CaptureService.saveMode === "desktop"
                onTriggered: CaptureService.setSaveMode("desktop")
            }
            CaptureOptionRow {
                width: parent.width
                label: "Documents"
                selected: CaptureService.saveMode === "documents"
                onTriggered: CaptureService.setSaveMode("documents")
            }
            CaptureOptionRow {
                width: parent.width
                label: "Clipboard"
                selected: CaptureService.saveMode === "clipboard"
                dimmed: CaptureService.recordMode
                onTriggered: CaptureService.setSaveMode("clipboard")
            }
            CaptureOptionRow {
                visible: CaptureService.customDirectory !== ""
                width: parent.width
                height: visible ? implicitHeight : 0
                label: CaptureService.directoryLabel(CaptureService.customDirectory)
                detail: CaptureService.customDirectory
                selected: CaptureService.saveMode === "custom"
                onTriggered: CaptureService.setSaveMode("custom")
            }
            CaptureOptionRow {
                width: parent.width
                label: "Other Locations…"
                showsDisclosure: true
                onTriggered: {
                    folderBrowser.openAt(CaptureService.directoryFileUrl(
                        CaptureService.customDirectory))
                    CaptureService.optionsOpen = false
                    CaptureService.folderPickerOpen = true
                }
            }

            Item {
                width: parent.width; height: 10
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    color: ThemeService.separator; height: 1
                }
            }

            Text {
                width: parent.width
                height: 25
                leftPadding: 34
                text: "Timer"
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
            CaptureOptionRow {
                width: parent.width
                label: "None"
                selected: CaptureService.timerSeconds === 0
                onTriggered: CaptureService.setTimerSeconds(0)
            }
            CaptureOptionRow {
                width: parent.width
                label: "5 Seconds"
                selected: CaptureService.timerSeconds === 5
                onTriggered: CaptureService.setTimerSeconds(5)
            }
            CaptureOptionRow {
                width: parent.width
                label: "10 Seconds"
                selected: CaptureService.timerSeconds === 10
                onTriggered: CaptureService.setTimerSeconds(10)
            }

            Item {
                visible: CaptureService.recordMode
                width: parent.width; height: visible ? 10 : 0
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    color: ThemeService.separator; height: 1
                }
            }
            Text {
                visible: CaptureService.recordMode
                width: parent.width
                height: visible ? 25 : 0
                leftPadding: 34
                text: "Audio"
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
            CaptureOptionRow {
                visible: CaptureService.recordMode
                width: parent.width
                height: visible ? implicitHeight : 0
                label: "System Audio"
                selected: CaptureService.desktopAudio
                onTriggered: {
                    CaptureService.desktopAudio = !CaptureService.desktopAudio
                    CaptureService._persist()
                }
            }
            CaptureOptionRow {
                visible: CaptureService.recordMode
                width: parent.width
                height: visible ? implicitHeight : 0
                label: "Built-in Microphone"
                selected: CaptureService.microphone
                onTriggered: {
                    CaptureService.microphone = !CaptureService.microphone
                    CaptureService._persist()
                }
            }

            Item {
                width: parent.width; height: 10
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    color: ThemeService.separator; height: 1
                }
            }
            Text {
                width: parent.width
                height: 25
                leftPadding: 34
                text: "Options"
                color: ThemeService.textTertiary
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
            CaptureOptionRow {
                width: parent.width
                label: "Show Mouse Pointer"
                selected: CaptureService.showPointer
                onTriggered: {
                    CaptureService.showPointer = !CaptureService.showPointer
                    CaptureService._persist()
                }
            }
            CaptureOptionRow {
                width: parent.width
                label: "Remember Last Selection"
                selected: CaptureService.rememberSelection
                onTriggered: {
                    CaptureService.setRememberSelection(!CaptureService.rememberSelection)
                }
            }

            Text {
                visible: CaptureService.recordMode && !CaptureService.recorderAvailable
                width: parent.width
                height: visible ? implicitHeight + 8 : 0
                leftPadding: 34
                rightPadding: 8
                topPadding: 5
                text: "Recording requires gpu-screen-recorder."
                color: "#ff453a"
                font.family: "SF Pro Display"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    CaptureHitSlop {
        id: folderHitSlop
        targetItem: folderCard
        extent: 5
        cursorShape: Qt.ArrowCursor
        z: 4
        onHoveredChanged: win.publishToolbarHover()
    }

    Rectangle {
        id: folderCard
        x: Math.max(8, Math.min(win.width - width - 8,
            toolbarCard.x + optionsButton.parent.x + optionsButton.x - 82))
        y: toolbarCard.y >= height + 18
            ? toolbarCard.y - height - 10
            : Math.min(win.height - height - 8, toolbarCard.y + toolbarCard.height + 10)
        width: 470
        height: 430
        z: 5
        radius: 16
        color: ThemeService.popupBg
        border.width: 1
        border.color: ThemeService.stroke
        visible: CaptureService.toolbarOpen && CaptureService.toolbarVisible
            && (CaptureService.folderPickerOpen || opacity > 0.001)
        enabled: visible
        opacity: CaptureService.folderPickerOpen ? 1 : 0
        scale: CaptureService.folderPickerOpen ? 1 : 0.975
        transformOrigin: Item.Bottom

        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on scale {
            SpringAnimation { spring: 20; damping: 1; epsilon: 0.002 }
        }

        MouseArea {
            id: folderInput
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            cursorShape: Qt.ArrowCursor
            onContainsMouseChanged: win.publishToolbarHover()
            onPressed: function(mouse) { mouse.accepted = true }
        }

        CaptureFolderPicker {
            id: folderBrowser
            anchors { fill: parent; margins: 18 }
            enabled: CaptureService.folderPickerOpen
            z: 1
            onCancelled: {
                CaptureService.folderPickerOpen = false
                CaptureService.optionsOpen = true
            }
            onFolderSelected: function(path) {
                if (CaptureService.setCustomDirectory(path)) {
                    CaptureService.folderPickerOpen = false
                    CaptureService.optionsOpen = true
                } else {
                    Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                        "Location not changed", "Choose a local folder."])
                }
            }
        }
    }
}
