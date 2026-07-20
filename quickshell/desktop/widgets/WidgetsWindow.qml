import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import "kinetic.js" as Kinetic

// Full-screen macOS-style widget board. Mirrors the launchpad pattern: a
// WlrLayer.Overlay panel with a dark veil; Hyprland's `layerrule blur` on the
// qs-widgets namespace blurs the workspace windows behind it so they appear
// "covered" without being closed.
//
// reopenRequested is emitted after a GTK file dialog finishes — layer-shell
// overlays always paint above normal windows, so the YouTube/Spotify folder
// pickers can only be seen if we hide the board first and reopen it after.
// (Note export uses the in-board NoteExportPicker modal instead.)
PanelWindow {
    id: win

    property bool show: false
    signal closeRequested
    signal reopenRequested

    // Note "저장" → in-board save dialog (NoteExportPicker), called from
    // NoteWidget via frame.winRef.
    function openNoteExport(index, filename, content, closeAfter) {
        board.openExport(index, filename, content, closeAfter)
    }

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            WidgetsService.activateBoard(m && m.name ? m.name : (win.screen ? win.screen.name : "unknown-monitor"))
            _surfaceVisible = true
            Qt.callLater(() => board.forceActiveFocus())
        } else {
            board.showGallery = false
            board.editMode = false
            board.closeContext()
            board.closeEditor()
            board.closeView()
            board.closeExport()
        }
    }

    WlrLayershell.namespace: "qs-widgets"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: show ? null : closedRegion
    Region { id: closedRegion }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: win.show ? 1.0 : 0.0
        Behavior on opacity { AppleSpring { spring: 18 } }
    }

    FocusScope {
        id: board
        anchors.fill: parent
        focus: true

        property int topZ: WidgetsService.widgets.count + 10
        property int topNoteZ: 50000 + WidgetsService.widgets.count + 10
        property bool showGallery: false

        // Edit mode: entered via the pencil button that appears when hovering
        // the top of the screen. While on, non-note widgets show a delete
        // badge and the [+]/[✕] toolbar replaces the pencil.
        property bool editMode: false

        // ── Grid layout ────────────────────────────────────────────────────
        // Everything except sticky notes lives on an n×m grid sized to the
        // monitor (cells of WidgetsService.gridCell + gridGap). Widgets stay
        // where the user put them: relayout() only snaps each one to its
        // nearest cell (sizes always from the type+layout preset) and bumps a
        // widget to the closest free region when its spot is taken (overlap
        // after a monitor change, a fresh add, …).
        readonly property int gridMarginX: 40
        readonly property int gridMarginTop: 96
        readonly property int gridMarginBottom: 40
        // Centre the columns horizontally. `gridMarginX` is only the *minimum*
        // side margin used to decide how many whole columns fit; whatever width
        // is left over (board width minus those columns) is split evenly into
        // left/right margins instead of piling up as dead space on the right
        // edge — that leftover was almost a full column here, so the rightmost
        // widget looked stranded with a big empty strip beside it. Every X
        // placement calculation below uses this offset (Y stays top-anchored).
        readonly property int gridOffsetX: {
            let g = _gridDims()
            return Math.max(gridMarginX, Math.round((board.width - (g.cols * g.unit - g.gap)) / 2))
        }

        function _gridDims() {
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap
            return {
                unit: unit, gap: gap,
                cols: Math.max(1, Math.floor((board.width  - gridMarginX * 2 + gap) / unit)),
                rows: Math.max(1, Math.floor((board.height - gridMarginTop - gridMarginBottom + gap) / unit))
            }
        }
        // Cell spans of widget i, from its type+layout preset (not persisted
        // nw/nh — idempotent, and heals any size a past bug clamped down).
        function _spans(i) {
            let w = WidgetsService.widgets.get(i)
            let ps = WidgetsService.presetSize(w.type, WidgetsService.getData(i).layout)
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap
            return { sw: Math.max(1, Math.round(((ps ? ps.nw : w.nw) + gap) / unit)),
                     sh: Math.max(1, Math.round(((ps ? ps.nh : w.nh) + gap) / unit)) }
        }

        function relayout() {
            // The board can relayout before the surface reaches its real size;
            // snapping against a tiny grid would scramble positions, so wait
            // for a plausible geometry.
            if (board.width < 500 || board.height < 400) return
            let g = _gridDims()
            let occ = []
            for (let r = 0; r < g.rows; r++) occ.push(new Array(g.cols).fill(false))

            function fits(r, c, sw, sh) {
                if (c < 0 || r < 0 || c + sw > g.cols || r + sh > g.rows) return false
                for (let dr = 0; dr < sh; dr++)
                    for (let dc = 0; dc < sw; dc++)
                        if (occ[r + dr][c + dc]) return false
                return true
            }
            function mark(r, c, sw, sh) {
                for (let dr = 0; dr < sh; dr++)
                    for (let dc = 0; dc < sw; dc++)
                        occ[r + dr][c + dc] = true
            }

            for (let i = 0; i < WidgetsService.widgets.count; i++) {
                let w = WidgetsService.widgets.get(i)
                if (w.type === "note") continue
                let s = _spans(i)
                let sw = Math.min(g.cols, s.sw), sh = Math.min(g.rows, s.sh)
                // Nearest cell to where the widget already is.
                let c = Math.max(0, Math.min(g.cols - sw, Math.round((w.nx - gridOffsetX) / g.unit)))
                let r = Math.max(0, Math.min(g.rows - sh, Math.round((w.ny - gridMarginTop) / g.unit)))
                if (!fits(r, c, sw, sh)) {
                    let best = null, bestD = 1e9
                    for (let r2 = 0; r2 <= g.rows - sh; r2++)
                        for (let c2 = 0; c2 <= g.cols - sw; c2++)
                            if (fits(r2, c2, sw, sh)) {
                                let dd = Math.abs(r2 - r) + Math.abs(c2 - c)
                                if (dd < bestD) { bestD = dd; best = { r: r2, c: c2 } }
                            }
                    if (best) { r = best.r; c = best.c }   // else: board full — leave overlapped
                }
                mark(r, c, sw, sh)
                WidgetsService.setPosition(i, gridOffsetX + c * g.unit, gridMarginTop + r * g.unit, false)
                WidgetsService.setSize(i, sw * g.unit - g.gap, sh * g.unit - g.gap, false)
            }
            WidgetsService.persist()
        }

        // ── Edit-mode drag & drop (free placement) ─────────────────────────
        // While dragging, a translucent preview marks the snapped drop slot;
        // white = free, red-tinted = occupied. Dropping on a free slot places
        // the widget there; anywhere else it springs back to where it was.
        property bool dragActive: false
        property real dragPX: 0
        property real dragPY: 0
        property real dragPW: 0
        property real dragPH: 0
        property bool dragFree: true

        // Slot region under a widget center (cx, cy), snapped + clamped.
        function snapRegion(index, cx, cy) {
            let g = _gridDims()
            let s = _spans(index)
            let sw = Math.min(g.cols, s.sw), sh = Math.min(g.rows, s.sh)
            let c = Math.max(0, Math.min(g.cols - sw, Math.round((cx - gridOffsetX) / g.unit - sw / 2)))
            let r = Math.max(0, Math.min(g.rows - sh, Math.round((cy - gridMarginTop) / g.unit - sh / 2)))
            let free = true
            for (let i = 0; i < WidgetsService.widgets.count && free; i++) {
                if (i === index) continue
                let w = WidgetsService.widgets.get(i)
                if (w.type === "note") continue
                let s2 = _spans(i)
                let c2 = Math.round((w.nx - gridOffsetX) / g.unit)
                let r2 = Math.round((w.ny - gridMarginTop) / g.unit)
                if (c < c2 + s2.sw && c2 < c + sw && r < r2 + s2.sh && r2 < r + sh) free = false
            }
            return { x: gridOffsetX + c * g.unit, y: gridMarginTop + r * g.unit,
                     w: sw * g.unit - g.gap, h: sh * g.unit - g.gap, free: free }
        }
        function updateDragPreview(index, cx, cy) {
            let s = snapRegion(index, cx, cy)
            dragPX = s.x; dragPY = s.y; dragPW = s.w; dragPH = s.h
            dragFree = s.free
            dragActive = true
        }
        function endDragPreview() { dragActive = false }
        function dropWidgetAt(index, cx, cy, origX, origY) {
            dragActive = false
            let s = snapRegion(index, cx, cy)
            if (s.free) WidgetsService.setPosition(index, s.x, s.y, true)
            else WidgetsService.setPosition(index, origX, origY, true)
            WidgetsService.relayoutNeeded()   // snap-verify everything
        }

        property string placementError: ""

        function _newWidgetSpan(type, extra) {
            let layout = extra && extra.layout ? extra.layout : 0
            let preset = WidgetsService.presetSize(type, layout)
            if (!preset) return null
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap
            return {
                sw: Math.max(1, Math.round((preset.nw + gap) / unit)),
                sh: Math.max(1, Math.round((preset.nh + gap) / unit))
            }
        }

        function _freeSlot(type, x, y, extra) {
            let span = _newWidgetSpan(type, extra)
            if (!span) return { x: x, y: y }
            let g = _gridDims()
            if (span.sw > g.cols || span.sh > g.rows) return null
            let occupied = []
            for (let r = 0; r < g.rows; r++) occupied.push(new Array(g.cols).fill(false))
            for (let i = 0; i < WidgetsService.widgets.count; i++) {
                let widget = WidgetsService.widgets.get(i)
                if (widget.type === "note") continue
                let current = _spans(i)
                let column = Math.round((widget.nx - gridOffsetX) / g.unit)
                let row = Math.round((widget.ny - gridMarginTop) / g.unit)
                for (let dr = 0; dr < current.sh; dr++)
                    for (let dc = 0; dc < current.sw; dc++)
                        if (row + dr >= 0 && row + dr < g.rows && column + dc >= 0 && column + dc < g.cols)
                            occupied[row + dr][column + dc] = true
            }
            function fits(row, column) {
                if (column < 0 || row < 0 || column + span.sw > g.cols || row + span.sh > g.rows) return false
                for (let dr = 0; dr < span.sh; dr++)
                    for (let dc = 0; dc < span.sw; dc++)
                        if (occupied[row + dr][column + dc]) return false
                return true
            }
            let preferredColumn = Math.max(0, Math.min(g.cols - span.sw,
                Math.round((x - gridOffsetX) / g.unit)))
            let preferredRow = Math.max(0, Math.min(g.rows - span.sh,
                Math.round((y - gridMarginTop) / g.unit)))
            let best = null
            let bestDistance = Number.MAX_VALUE
            for (let row = 0; row <= g.rows - span.sh; row++)
                for (let column = 0; column <= g.cols - span.sw; column++) {
                    if (!fits(row, column)) continue
                    let distance = Math.abs(row - preferredRow) + Math.abs(column - preferredColumn)
                    if (distance < bestDistance) {
                        bestDistance = distance
                        best = { x: gridOffsetX + column * g.unit,
                                 y: gridMarginTop + row * g.unit }
                    }
                }
            return best
        }

        function tryAddWidget(type, x, y, extra) {
            let slot = _freeSlot(type, x, y, extra)
            if (!slot) {
                placementError = "There isn’t enough room for this widget. Remove or move a widget, then try again."
                return -1
            }
            return WidgetsService.addWidget(type, slot.x, slot.y, extra)
        }

        function closePlacementError() { placementError = "" }

        Timer { id: relayoutTimer; interval: 40; onTriggered: board.relayout() }
        onWidthChanged: relayoutTimer.restart()
        onHeightChanged: relayoutTimer.restart()
        Component.onCompleted: relayoutTimer.restart()
        Connections {
            target: WidgetsService
            function onRelayoutNeeded() { relayoutTimer.restart() }
        }

        // Right-click context menu + editor state.
        property int ctxIndex: -1
        property real ctxX: 0
        property real ctxY: 0
        property int editIndex: -1
        property int viewIndex: -1   // reminders "View All"

        function openContext(index, x, y) { ctxIndex = index; ctxX = x; ctxY = y }
        function closeContext() { ctxIndex = -1 }
        function openEditor(index) { ctxIndex = -1; editIndex = index }
        function closeEditor() { editIndex = -1 }
        function openView(index) { ctxIndex = -1; viewIndex = index }
        function closeView() { viewIndex = -1 }

        // Note export (in-board save dialog). `exportCloseAfter` is set when
        // the export comes from the note's close-confirm dialog: delete the
        // note only once the file has actually been written.
        property int exportIndex: -1
        property string exportFilename: ""
        property string exportContent: ""
        property bool exportCloseAfter: false
        function openExport(index, filename, content, closeAfter) {
            exportFilename = filename
            exportContent = content
            exportCloseAfter = !!closeAfter
            exportIndex = index
        }
        function closeExport() {
            if (exportIndex < 0) return
            exportIndex = -1
            exportContent = ""
            // Pull focus off the (now hidden) filename field so stray typing
            // and the Esc chain land on the board again.
            board.forceActiveFocus()
        }

        opacity: win.show ? 1.0 : 0.0
        scale: win.show ? 1.0 : 0.98
        transformOrigin: Item.Center
        Behavior on opacity { AppleSpring { spring: 18 } }
        Behavior on scale { AppleSpring { spring: 13 } }
        onOpacityChanged: if (!win.show && opacity <= 0.002) win._surfaceVisible = false

        Keys.onEscapePressed: {
            if (board.placementError !== "") board.closePlacementError()
            else if (board.exportIndex >= 0) board.closeExport()
            else if (board.ctxIndex >= 0) board.closeContext()
            else if (board.viewIndex >= 0) board.closeView()
            else if (board.editIndex >= 0) board.closeEditor()
            else if (board.showGallery) board.showGallery = false
            else if (board.editMode) board.editMode = false
            else win.closeRequested()
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: { board.forceActiveFocus(); board.showGallery = false }
        }

        // ── Drop preview (edit-mode drag) ─────────────────────────────────
        // Sits under the widgets (their z starts at 1): a faint translucent
        // slot marker that follows the drag, red-tinted when the slot is taken.
        Rectangle {
            visible: board.editMode && board.dragActive
            x: board.dragPX; y: board.dragPY
            width: board.dragPW; height: board.dragPH
            z: 0.5
            radius: 13
            color: board.dragFree ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 0.35, 0.3, 0.10)
            border.color: board.dragFree ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 0.45, 0.4, 0.55)
            border.width: 1.5
            Behavior on x { AppleSpring { spring: 18; epsilon: 0.15 } }
            Behavior on y { AppleSpring { spring: 18; epsilon: 0.15 } }
        }

        // ── Widgets ──────────────────────────────────────────────────────
        Repeater {
            model: WidgetsService.widgets
            delegate: WidgetFrame {
                boardItem: board
                winRef: win
            }
        }

        // ── Top edit controls ──────────────────────────────────────────────
        // Idle: nothing visible. Hovering the top strip of the screen fades in
        // a pencil button; clicking it enters edit mode, where the pencil is
        // replaced by [+] (open the widget gallery) and [✕] (leave edit mode).
        Item {
            id: topZone
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 72
            z: 100000
            HoverHandler { id: topHover }
        }

        // Pencil (enter edit mode) — icon only, shown on top-strip hover.
        Rectangle {
            id: editBtn
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40; height: 40; radius: 20
            color: ebHover.hovered ? ThemeService.controlBgHover : ThemeService.panelBg
            border.color: ThemeService.separator; border.width: 1
            z: 100001
            visible: opacity > 0
            opacity: (!board.editMode && (topHover.hovered || ebHover.hovered)) ? 1 : 0
            scale: editMa.pressed ? ThemeService.pressScale : 1.0
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }
            Text { anchors.centerIn: parent; text: ""   // nf-fa-pencil
                   color: ThemeService.label; font.family: ThemeService.iconFont; font.pixelSize: 15 }
            HoverHandler { id: ebHover }
            MouseArea { id: editMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: board.editMode = true }
        }

        // Edit-mode toolbar: [+] add widget, [✕] leave edit mode.
        Rectangle {
            id: toolbar
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            height: 46
            width: toolbarRow.width + 24
            radius: 23
            color: ThemeService.panelBg
            border.color: ThemeService.separator
            border.width: 1
            z: 100001
            visible: opacity > 0
            opacity: board.editMode ? 1 : 0
            scale: board.editMode ? 1 : 0.9
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 18 } }

            Row {
                id: toolbarRow
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 16
                    color: addHover.hovered || board.showGallery ? ThemeService.controlBgHover : ThemeService.controlBg
                    scale: addMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text { anchors.centerIn: parent; text: "+"; color: ThemeService.label
                           font.family: "SF Pro Display"; font.pixelSize: 19; font.weight: Font.Medium }
                    HoverHandler { id: addHover }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: board.showGallery = !board.showGallery
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 16
                    color: closeHover.hovered ? ThemeService.controlBgHover : ThemeService.controlBg
                    scale: closeMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text { anchors.centerIn: parent; text: "✕"; color: ThemeService.label
                           font.family: "SF Pro Display"; font.pixelSize: 14 }
                    HoverHandler { id: closeHover }
                    MouseArea { id: closeMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { board.editMode = false; board.showGallery = false } }
                }
            }
        }

        // ── Widget picker (add menu, macOS style) ──────────────────────────
        // Unfolds top-down from under the [+] button: search + type sidebar on
        // the left, that type's layout previews on the right. Clicking a card
        // adds the widget; the panel stays open until Done / Esc / outside.
        Rectangle {
            id: gallery
            anchors.top: toolbar.bottom
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            width: 780
            height: 470
            radius: 20
            color: ThemeService.panelBg
            border.color: ThemeService.separator
            border.width: 1
            z: 100000
            clip: true

            transformOrigin: Item.Top
            visible: opacity > 0
            opacity: board.showGallery ? 1 : 0
            scale: board.showGallery ? 1 : 0.95
            Behavior on opacity { AppleSpring { spring: 18 } }
            Behavior on scale { AppleSpring { spring: 13 } }

            property string selType: "all"
            readonly property color cardColor: ThemeService.isDark
                ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.045)
            readonly property color cardHoverColor: ThemeService.isDark
                ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.095)
            readonly property color subtleColor: ThemeService.isDark
                ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
            readonly property color selectedColor: ThemeService.isDark
                ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)
            readonly property var types: [
                { kind: "calendar",  label: "Calendar",  glyph: "\uf073" },
                { kind: "clock",     label: "Clock",     glyph: "\uf017" },
                { kind: "news",      label: "News",      glyph: "\uf1ea" },
                { kind: "note",      label: "Note",      glyph: "\uf249" },
                { kind: "reminders", label: "Reminders", glyph: "\uf046" },
                { kind: "stock",      label: "Stocks",     glyph: "\uf201" },
                { kind: "downloader", label: "Downloader", glyph: "\uf019" },
                { kind: "weather",    label: "Weather",    glyph: "\ue302" }
            ]
            function sectionVisible(kind, label) {
                let q = searchField.text.trim().toLowerCase()
                if (q !== "") return label.toLowerCase().indexOf(q) !== -1
                return gallery.selType === "all" || gallery.selType === kind
            }
            onVisibleChanged: if (visible) { selType = "all"; searchField.text = "" }

            MouseArea { anchors.fill: parent }   // swallow clicks inside the panel

            // ── Sidebar: search + widget types ─────────────────────────────
            Item {
                id: pickerSidebar
                width: 196
                anchors { left: parent.left; top: parent.top; bottom: pickerFooter.top }

                Rectangle {
                    id: pickerSearch
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 14
                    height: 32; radius: 9
                    color: gallery.subtleColor
                    border.color: searchField.activeFocus ? ThemeService.accent("blue") : ThemeService.separator
                    border.width: 1
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf002"; color: ThemeService.secondaryLabel
                        font.family: ThemeService.iconFont; font.pixelSize: 12
                    }
                    TextField {
                        id: searchField
                        anchors.fill: parent; anchors.leftMargin: 30; anchors.rightMargin: 8
                        background: null; color: ThemeService.label
                        placeholderText: "Search Widgets"
                        placeholderTextColor: ThemeService.tertiaryLabel
                        font.family: "SF Pro Display"; font.pixelSize: 12
                        verticalAlignment: TextInput.AlignVCenter
                    }
                }

                Column {
                    anchors { left: parent.left; right: parent.right; top: pickerSearch.bottom }
                    anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.topMargin: 12
                    spacing: 2
                    SidebarRow { kind: "all"; label: "All Widgets"; glyph: "\uf00a" }
                    Repeater {
                        model: gallery.types
                        delegate: SidebarRow {
                            required property var modelData
                            kind: modelData.kind
                            label: modelData.label
                            glyph: modelData.glyph
                        }
                    }
                }
            }
            Rectangle {
                anchors { left: pickerSidebar.right; top: parent.top; bottom: pickerFooter.top }
                width: 1
                color: ThemeService.separator
            }

            // ── Content: layout previews per type ──────────────────────────
            Flickable {
                id: pickerScroll
                anchors { left: pickerSidebar.right; leftMargin: 1; right: parent.right; top: parent.top; bottom: pickerFooter.top }
                clip: true
                contentWidth: width
                contentHeight: pickerCol.height + 36
                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                flickDeceleration: 6000
                maximumFlickVelocity: 6000
                rebound: Transition {
                    SpringAnimation {
                        properties: "x,y"
                        spring: 18
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                // Kinetic scroll (kinetic.js) — same feel as the emoji/nc lists.
                property var _ks: ({})
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        psGlide.stop()
                        if (Kinetic.onWheel(pickerScroll, ev, pickerScroll._ks, { gain: 90 }))
                            psEndTimer.restart()
                    }
                }
                Timer {
                    id: psEndTimer
                    interval: 48
                    onTriggered: {
                        let g = Kinetic.fling(pickerScroll, pickerScroll._ks, {})
                        if (g) { psGlide.from = g.from; psGlide.to = g.to; psGlide.restart() }
                    }
                }
                SpringAnimation {
                    id: psGlide
                    target: pickerScroll
                    property: "contentY"
                    spring: 18
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }

                Column {
                    id: pickerCol
                    x: 22; y: 18
                    width: pickerScroll.width - 44
                    spacing: 24

                    Column {
                        visible: gallery.sectionVisible("calendar", "Calendar")
                        width: parent.width
                        spacing: 10
                        Text { text: "Calendar"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            CalendarLayoutCard { layoutId: 1 }
                            CalendarLayoutCard { layoutId: 2 }
                            CalendarLayoutCard { layoutId: 3 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("clock", "Clock")
                        width: parent.width
                        spacing: 10
                        Text { text: "Clock"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            ClockLayoutCard { layoutId: 1 }
                            ClockLayoutCard { layoutId: 2 }
                            ClockLayoutCard { layoutId: 3 }
                            ClockLayoutCard { layoutId: 4 }
                            ClockLayoutCard { layoutId: 5 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("news", "News")
                        width: parent.width
                        spacing: 10
                        Text { text: "News"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            NewsLayoutCard { layoutId: 4 }
                            NewsLayoutCard { layoutId: 1 }
                            NewsLayoutCard { layoutId: 2 }
                            NewsLayoutCard { layoutId: 3 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("note", "Note")
                        width: parent.width
                        spacing: 10
                        Text { text: "Note"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            NoteAddCard { }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("reminders", "Reminders")
                        width: parent.width
                        spacing: 10
                        Text { text: "Reminders"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            RemindersLayoutCard { layoutId: 1 }
                            RemindersLayoutCard { layoutId: 2 }
                            RemindersLayoutCard { layoutId: 3 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("stock", "Stocks")
                        width: parent.width
                        spacing: 10
                        Text { text: "Stocks"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            StockAddCard { }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("downloader", "YouTube Downloader")
                        width: parent.width
                        spacing: 10
                        Text { text: "YouTube Downloader"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            YoutubeAddCard { layoutId: 1 }
                            YoutubeAddCard { layoutId: 2 }
                            YoutubeAddCard { layoutId: 3 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("downloader", "Spotify Downloader")
                        width: parent.width
                        spacing: 10
                        Text { text: "Spotify Downloader"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            SpotifyAddCard { layoutId: 1 }
                            SpotifyAddCard { layoutId: 2 }
                            SpotifyAddCard { layoutId: 3 }
                        }
                    }
                    Column {
                        visible: gallery.sectionVisible("weather", "Weather")
                        width: parent.width
                        spacing: 10
                        Text { text: "Weather"; color: ThemeService.label
                               font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Flow { width: parent.width; spacing: 12
                            WeatherLayoutCard { layoutId: 1 }
                            WeatherLayoutCard { layoutId: 2 }
                            WeatherLayoutCard { layoutId: 3 }
                            WeatherLayoutCard { layoutId: 4 }
                        }
                    }
                }
            }

            // ── Footer: hint + Done ─────────────────────────────────────────
            Rectangle {
                id: pickerFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 52
                color: gallery.subtleColor
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1; color: ThemeService.separator
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Click a widget to add it to the board"
                    color: ThemeService.secondaryLabel
                    font.family: "SF Pro Display"; font.pixelSize: 12
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76; height: 30; radius: 15
                    color: pDoneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                    scale: pDoneMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                    HoverHandler { id: pDoneHover }
                    MouseArea { id: pDoneMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: board.showGallery = false }
                }
            }
        }

        // ── Empty state hint ───────────────────────────────────────────────
        Text {
            anchors.centerIn: parent
            visible: WidgetsService.widgets.count === 0 && !board.showGallery
            text: "No widgets"
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: "SF Pro Display"; font.pixelSize: 16
        }

        // ── Right-click context menu ───────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.ctxIndex >= 0 || contextPanel.opacity > 0.002
            z: 100002
            MouseArea {
                anchors.fill: parent
                enabled: board.ctxIndex >= 0
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: board.closeContext()
            }
            Rectangle {
                id: contextPanel
                x: Math.max(8, Math.min(board.ctxX, board.width - width - 8))
                y: Math.max(8, Math.min(board.ctxY, board.height - height - 8))
                width: 156
                height: menuCol.implicitHeight + 10
                radius: 11
                color: Qt.rgba(0.14, 0.14, 0.16, 0.97)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                opacity: board.ctxIndex >= 0 ? 1 : 0
                scale: board.ctxIndex >= 0 ? 1 : 0.94
                transformOrigin: Item.TopLeft
                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 18 } }
                Column {
                    id: menuCol
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    CtxRow {
                        label: "View All"
                        visible: WidgetsService.typeAt(board.ctxIndex) === "reminders"
                        onTriggered: board.openView(board.ctxIndex)
                    }
                    CtxRow {
                        label: "Edit…"
                        enabled: WidgetsService.typeAt(board.ctxIndex) === "clock"
                              || WidgetsService.typeAt(board.ctxIndex) === "weather"
                              || WidgetsService.typeAt(board.ctxIndex) === "reminders"
                              || WidgetsService.typeAt(board.ctxIndex) === "news"
                              || WidgetsService.typeAt(board.ctxIndex) === "calendar"
                              || WidgetsService.typeAt(board.ctxIndex) === "stock"
                              || WidgetsService.typeAt(board.ctxIndex) === "youtube"
                              || WidgetsService.typeAt(board.ctxIndex) === "spotify"
                              || WidgetsService.typeAt(board.ctxIndex) === "note"
                        onTriggered: board.openEditor(board.ctxIndex)
                    }
                    CtxRow {
                        label: "Delete"
                        danger: true
                        onTriggered: { let i = board.ctxIndex; board.closeContext(); WidgetsService.removeAt(i) }
                    }
                }
            }
        }

        // ── Editor (modal) ─────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.editIndex >= 0 || editorPanel.opacity > 0.002
            z: 100003
            MouseArea { anchors.fill: parent; enabled: board.editIndex >= 0; onPressed: board.closeEditor() }
            Rectangle {
                id: editorPanel
                anchors.centerIn: parent
                width: Math.min(484, board.width - 48)
                height: Math.min(editLoader.implicitHeight + 84, board.height - 64)
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                opacity: board.editIndex >= 0 ? 1 : 0
                scale: board.editIndex >= 0 ? 1 : 0.95
                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 13 } }
                MouseArea { anchors.fill: parent }
                Flickable {
                    id: editorScroll
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: editorDone.top }
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    anchors.topMargin: 22
                    anchors.bottomMargin: 16
                    clip: true
                    contentWidth: width
                    contentHeight: editLoader.implicitHeight
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    boundsMovement: Flickable.FollowBoundsBehavior
                    flickDeceleration: 6000
                    maximumFlickVelocity: 6000
                    rebound: Transition {
                        SpringAnimation {
                            properties: "x,y"
                            spring: 18
                            damping: ThemeService.momentumDamping
                            epsilon: 0.25
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    property var _ks: ({})
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (ev) => {
                            editorGlide.stop()
                            if (Kinetic.onWheel(editorScroll, ev, editorScroll._ks, { gain: 90 }))
                                editorEndTimer.restart()
                        }
                    }
                    Timer {
                        id: editorEndTimer
                        interval: 48
                        onTriggered: {
                            let glide = Kinetic.fling(editorScroll, editorScroll._ks, {})
                            if (glide) {
                                editorGlide.from = glide.from
                                editorGlide.to = glide.to
                                editorGlide.restart()
                            }
                        }
                    }
                    SpringAnimation {
                        id: editorGlide
                        target: editorScroll
                        property: "contentY"
                        spring: 18
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                    }
                    Loader {
                        id: editLoader
                        width: parent.width
                        sourceComponent: {
                            if (board.editIndex < 0) return noOptionsComp
                            let t = WidgetsService.typeAt(board.editIndex)
                            if (t === "clock") return clockEditorComp
                            if (t === "weather") return weatherEditorComp
                            if (t === "reminders") return remindersEditorComp
                            if (t === "news") return newsEditorComp
                            if (t === "calendar") return calendarEditorComp
                            if (t === "stock") return stockEditorComp
                            if (t === "youtube") return youtubeEditorComp
                            if (t === "spotify") return spotifyEditorComp
                            if (t === "note") return noteEditorComp
                            return noOptionsComp
                        }
                    }
                }
                Rectangle {
                    id: editorDone
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 14
                    anchors.bottomMargin: 14
                    width: 78; height: 32; radius: 9
                    color: doneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                    scale: editorDoneMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                    HoverHandler { id: doneHover }
                    MouseArea { id: editorDoneMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: board.closeEditor() }
                }
                Component { id: clockEditorComp; ClockEditor { index: board.editIndex } }
                Component { id: weatherEditorComp; WeatherEditor { index: board.editIndex } }
                Component { id: remindersEditorComp; RemindersEditor { index: board.editIndex } }
                Component { id: newsEditorComp; NewsEditor { index: board.editIndex } }
                Component { id: calendarEditorComp; CalendarEditor { index: board.editIndex } }
                Component { id: stockEditorComp; StockEditor { index: board.editIndex } }
                Component { id: youtubeEditorComp; YoutubeEditor { index: board.editIndex } }
                Component { id: spotifyEditorComp; SpotifyEditor { index: board.editIndex } }
                Component { id: noteEditorComp; NoteEditor { index: board.editIndex } }
                Component {
                    id: noOptionsComp
                    Text { text: "No editable options for this widget."
                           color: Qt.rgba(1, 1, 1, 0.6); font.family: "SF Pro Display"; font.pixelSize: 14 }
                }
            }
        }

        // ── Note export "save as" dialog (modal) ───────────────────────────
        Item {
            anchors.fill: parent
            visible: board.exportIndex >= 0 || exportPanel.opacity > 0.002
            z: 100004
            MouseArea { anchors.fill: parent; enabled: board.exportIndex >= 0; onPressed: board.closeExport() }
            Rectangle {
                id: exportPanel
                anchors.centerIn: parent
                width: Math.min(514, board.width - 48)
                height: Math.min(exportPicker.implicitHeight + 44, board.height - 64)
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                opacity: board.exportIndex >= 0 ? 1 : 0
                scale: board.exportIndex >= 0 ? 1 : 0.95
                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 13 } }
                MouseArea { anchors.fill: parent }
                NoteExportPicker {
                    id: exportPicker
                    anchors.fill: parent
                    anchors.margins: 22
                    active: board.exportIndex >= 0
                    filename: board.exportFilename
                    content: board.exportContent
                    onCancelled: board.closeExport()
                    onSaved: {
                        let i = board.exportIndex
                        let del = board.exportCloseAfter
                        board.closeExport()
                        // Deferred so the removal doesn't tear down this
                        // picker inside its own signal handler.
                        if (del) Qt.callLater(function () { WidgetsService.removeAt(i) })
                    }
                }
            }
        }

        // ── Reminders "View All" (modal) ───────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.viewIndex >= 0 || viewerPanel.opacity > 0.002
            z: 100003
            MouseArea { anchors.fill: parent; enabled: board.viewIndex >= 0; onPressed: board.closeView() }
            Rectangle {
                id: viewerPanel
                anchors.centerIn: parent
                width: 452
                height: viewCol.implicitHeight + 28
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                opacity: board.viewIndex >= 0 ? 1 : 0
                scale: board.viewIndex >= 0 ? 1 : 0.95
                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 13 } }
                MouseArea { anchors.fill: parent }
                Column {
                    id: viewCol
                    anchors.centerIn: parent
                    width: parent.width - 44
                    spacing: 14
                    RemindersViewer {
                        width: parent.width
                        index: board.viewIndex
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 78; height: 32; radius: 9
                        color: vDoneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                        scale: viewerDoneMa.pressed ? ThemeService.pressScale : 1.0
                        Behavior on scale { AppleSpring { spring: 18 } }
                        Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"
                               font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                        HoverHandler { id: vDoneHover }
                        MouseArea { id: viewerDoneMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: board.closeView() }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: board.placementError !== "" || placementPanel.opacity > 0.002
            z: 100010

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.24)
                opacity: board.placementError !== "" ? 1 : 0
                Behavior on opacity { AppleSpring { spring: 18 } }
            }
            MouseArea {
                anchors.fill: parent
                enabled: board.placementError !== ""
                onPressed: board.closePlacementError()
            }
            Rectangle {
                anchors.centerIn: placementPanel
                anchors.verticalCenterOffset: 8
                width: placementPanel.width
                height: placementPanel.height
                radius: placementPanel.radius
                color: Qt.rgba(0, 0, 0, 0.36)
                opacity: placementPanel.opacity
                scale: placementPanel.scale
            }
            Rectangle {
                id: placementPanel
                anchors.centerIn: parent
                width: Math.min(380, board.width - 48)
                height: 190
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.98)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                opacity: board.placementError !== "" ? 1 : 0
                scale: board.placementError !== "" ? 1 : 0.94
                Behavior on opacity { AppleSpring { spring: 18 } }
                Behavior on scale { AppleSpring { spring: 18 } }
                MouseArea { anchors.fill: parent }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 22
                    spacing: 9
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 38
                        height: 38
                        radius: 19
                        color: ThemeService.accent("red")
                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 23
                            font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Not Enough Space"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.2
                    }
                    Text {
                        width: parent.width
                        text: board.placementError
                        color: Qt.rgba(1, 1, 1, 0.66)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                    }
                }
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                    width: 92
                    height: 32
                    radius: 10
                    color: placementOkHover.hovered ? Qt.lighter(ThemeService.accent("blue"), 1.08)
                                                    : ThemeService.accent("blue")
                    scale: placementOkArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: placementOkHover }
                    MouseArea {
                        id: placementOkArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: board.closePlacementError()
                    }
                }
            }
        }
    }

    // ── Inline components ────────────────────────────────────────────────
    // A clock-layout preview card (stage 2 of the gallery).
    component ClockLayoutCard: Rectangle {
        id: clc
        property int layoutId: 1
        readonly property var names: ["Digital", "World Row", "World 2×2", "Numbers", "Minimal"]
        readonly property var previewDate: new Date(2024, 0, 1, 10, 9, 36)
        width: layoutId === 2 ? 150 : 96
        height: 116
        radius: 14
        color: clcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: clcMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            // Mini preview
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: clc.layoutId === 2 ? 130 : 72
                height: 72
                radius: 12
                clip: true
                color: clc.layoutId === 1 ? "#ffffff"
                     : clc.layoutId === 4 ? Qt.rgba(0.84, 0.89, 0.96, 0.55) : ThemeService.cardBg
                border.color: Qt.rgba(0, 0, 0, 0.1); border.width: clc.layoutId === 1 || clc.layoutId === 4 ? 1 : 0

                // 1: digital text
                Text {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 1
                    text: "9:41"; color: "#101012"
                    font.family: "SF Pro Display"; font.weight: Font.Bold; font.pixelSize: 26
                }
                // 2: row of mini clocks
                Row {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 2
                    spacing: 6
                    Repeater {
                        model: 4
                        delegate: AnalogClock {
                            width: 26; height: 26
                            fixedDate: clc.previewDate; active: false
                            faceColor: "#ffffff"; tickColor: "#1c1c1e"; handColor: "#1c1c1e"
                        }
                    }
                }
                // 3: 2x2 mini clocks
                Grid {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 3
                    columns: 2; rows: 2; rowSpacing: 6; columnSpacing: 6
                    Repeater {
                        model: 4
                        delegate: AnalogClock {
                            width: 28; height: 28
                            fixedDate: clc.previewDate; active: false
                            faceColor: "#ffffff"; tickColor: "#1c1c1e"; handColor: "#1c1c1e"
                        }
                    }
                }
                // 4 & 5: single clock
                AnalogClock {
                    anchors.fill: parent; anchors.margins: 8
                    visible: clc.layoutId === 4
                    fixedDate: clc.previewDate; active: false
                    faceColor: Qt.rgba(1, 1, 1, 0.92)
                    tickColor: "#2a2a2e"; showNumbers: false; handColor: "#1c1c1e"
                }
                AnalogClock {
                    anchors.fill: parent; anchors.margins: 8
                    visible: clc.layoutId === 5
                    fixedDate: clc.previewDate; active: false
                    tickColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.48)
                    handColor: ThemeService.isDark ? "#f2f2f7" : "#1c1c1e"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: clc.names[clc.layoutId - 1]
                color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11
            }
        }

        HoverHandler { id: clcHover }
        MouseArea {
            id: clcMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                board.tryAddWidget("clock", board.width / 2 - 110, board.height / 2 - 110,
                    { layout: clc.layoutId, faces: WidgetsService.defaultClockFaces(clc.layoutId) })
            }
        }
    }

    // A weather-layout preview card (stage 2 of the gallery).
    component WeatherLayoutCard: Rectangle {
        id: wlc
        property int layoutId: 1
        readonly property var names: ["Large", "Hourly", "Conditions", "Sun"]
        width: 96
        height: 116
        radius: 14
        color: wlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: wlcMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72; radius: 12; clip: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a74d4" }
                    GradientStop { position: 1.0; color: "#73b7ef" }
                }
                // tiny representative content
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 6
                       text: "18°"; color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 16; font.weight: Font.Light }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6
                       text: wlc.layoutId === 4 ? "" : "\ue30d"; color: "#ffffff"
                       font.family: WeatherService.iconFont; font.pixelSize: 14 }
                // layout-specific hint
                Row {
                    visible: wlc.layoutId === 1 || wlc.layoutId === 2
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 8
                    spacing: 5
                    Repeater { model: 4; delegate: Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(1,1,1,0.8) } }
                }
                Canvas {
                    visible: wlc.layoutId === 4
                    anchors.fill: parent; anchors.margins: 10
                    onPaint: {
                        let ctx = getContext("2d"); ctx.reset()
                        let w = width, h = height, hz = h * 0.7
                        ctx.beginPath()
                        for (let i = 0; i <= 24; i++) { let t = i/24; let x=t*w; let y=hz-Math.sin(t*Math.PI)*h*0.5; i?ctx.lineTo(x,y):ctx.moveTo(x,y) }
                        ctx.strokeStyle = Qt.rgba(1,1,1,0.5); ctx.lineWidth = 1.2; ctx.stroke()
                        ctx.beginPath(); ctx.arc(w*0.6, hz-Math.sin(0.6*Math.PI)*h*0.5, 3, 0, 2*Math.PI); ctx.fillStyle="#ffd34d"; ctx.fill()
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: wlc.names[wlc.layoutId - 1]
                   color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: wlcHover }
        MouseArea {
            id: wlcMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                board.tryAddWidget("weather", board.width / 2 - 130, board.height / 2 - 120, { layout: wlc.layoutId })
            }
        }
    }

    // A news-layout preview card (stage 2 of the gallery).
    component NewsLayoutCard: Rectangle {
        id: nlc
        property int layoutId: 2
        readonly property string layoutName: layoutId === 4 ? "X-Small"
            : (layoutId === 1 ? "Small" : (layoutId === 2 ? "Medium" : "Large"))
        width: layoutId === 1 || layoutId === 4 ? 96 : 128
        height: 116
        radius: 14
        color: nlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: nlcMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            // mini mock: hero image block + headline lines (+ side column on
            // medium/large to hint at the wider layouts)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: nlc.layoutId === 1 || nlc.layoutId === 4 ? 60 : 100
                height: 72; radius: 12; clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator; border.width: 1
                Rectangle {
                    visible: nlc.layoutId === 4
                    anchors.fill: parent
                    color: ThemeService.secondaryLabel
                    opacity: 0.55
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 30
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.82) }
                        }
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.margins: 6
                        spacing: 3
                        Rectangle { width: parent.width; height: 3; radius: 1.5; color: "#ffffff" }
                        Rectangle { width: parent.width * 0.72; height: 3; radius: 1.5; color: "#ffffff" }
                    }
                }
                Row {
                    visible: nlc.layoutId !== 4
                    anchors.fill: parent; anchors.margins: 8
                    spacing: 7
                    Column {
                        width: nlc.layoutId === 1 ? parent.width : 48
                        spacing: 4
                        Rectangle { width: parent.width; height: 24; radius: 5
                                    color: ThemeService.secondaryLabel; opacity: 0.55 }
                        Rectangle { width: parent.width; height: 4; radius: 2; color: ThemeService.label; opacity: 0.85 }
                        Rectangle { width: parent.width * 0.7; height: 4; radius: 2; color: ThemeService.label; opacity: 0.85 }
                        Rectangle { width: parent.width * 0.85; height: 3; radius: 1.5; color: ThemeService.secondaryLabel }
                    }
                    Column {
                        visible: nlc.layoutId !== 1
                        width: 29
                        spacing: 4
                        Repeater {
                            model: nlc.layoutId === 3 ? 4 : 3
                            delegate: Column {
                                spacing: 2
                                Rectangle { width: 29; height: 3; radius: 1.5; color: ThemeService.label; opacity: 0.8 }
                                Rectangle { width: 20; height: 3; radius: 1.5; color: ThemeService.secondaryLabel }
                            }
                        }
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: nlc.layoutName
                   color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: nlcHover }
        MouseArea {
            id: nlcMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                let size = WidgetsService.newsSize(nlc.layoutId)
                board.tryAddWidget("news", board.width / 2 - size.nw / 2, board.height / 2 - size.nh / 2, { layout: nlc.layoutId })
            }
        }
    }

    // A reminders-layout preview card (stage 2 of the gallery).
    component RemindersLayoutCard: Rectangle {
        id: rlc
        property int layoutId: 2
        readonly property var names: ["Small", "Medium", "Large"]
        readonly property color accent: ThemeService.accent("blue")
        width: layoutId === 2 ? 128 : 96
        height: 116
        radius: 14
        color: rlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: rlcMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: rlc.layoutId === 1 ? 64 : (rlc.layoutId === 2 ? 100 : 46)
                height: rlc.layoutId === 1 ? 64 : (rlc.layoutId === 2 ? 52 : 72)
                radius: 10
                clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator; border.width: 1

                Column {
                    visible: rlc.layoutId === 1
                    anchors.fill: parent; anchors.margins: 7
                    spacing: 4
                    Row {
                        spacing: 4
                        Rectangle { width: 10; height: 10; radius: 5; color: rlc.accent }
                        Text { text: "3"; color: ThemeService.label; font.family: "SF Pro Display"
                               font.pixelSize: 10; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Repeater {
                        model: 3
                        delegate: Row {
                            spacing: 3
                            Rectangle { width: 6; height: 6; radius: 3; color: "transparent"
                                        border.color: rlc.accent; border.width: 1; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle { width: 32; height: 3; radius: 1.5; color: ThemeService.separator
                                        anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }

                Row {
                    visible: rlc.layoutId === 2
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 7
                    Column {
                        width: 25
                        spacing: 3
                        Rectangle {
                            width: 15; height: 15; radius: 7.5; color: rlc.accent
                            Text { anchors.centerIn: parent; text: "✓"; color: "#ffffff"; font.pixelSize: 8 }
                        }
                        Text { text: "3"; color: ThemeService.label; font.family: "SF Pro Display"
                               font.pixelSize: 14; font.weight: Font.Bold }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Repeater {
                            model: 3
                            delegate: Row {
                                spacing: 3
                                Rectangle { width: 6; height: 6; radius: 3; color: "transparent"
                                            border.color: rlc.accent; border.width: 1 }
                                Rectangle { width: 42; height: 3; radius: 1.5; color: ThemeService.separator
                                            anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }

                Column {
                    visible: rlc.layoutId === 3
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "3"; color: ThemeService.label; font.family: "SF Pro Display"
                               font.pixelSize: 12; font.weight: Font.Bold }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5
                                    color: rlc.accent }
                    }
                    Rectangle { width: parent.width; height: 2; color: ThemeService.separator }
                    Repeater {
                        model: 4
                        delegate: Row {
                            spacing: 3
                            Rectangle { width: 5; height: 5; radius: 2.5; color: "transparent"
                                        border.color: rlc.accent; border.width: 1 }
                            Rectangle { width: 23; height: 3; radius: 1.5; color: ThemeService.separator
                                        anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: rlc.names[rlc.layoutId - 1]
                   color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: rlcHover }
        MouseArea {
            id: rlcMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                board.tryAddWidget("reminders", board.width / 2 - 130, board.height / 2 - 100, { layout: rlc.layoutId })
            }
        }
    }

    // A tiny colored-bar "event" used by the calendar previews.
    component CalMiniEvent: Row {
        property color barColor: "#BF5AF2"
        spacing: 3
        Rectangle { width: 2; height: 10; radius: 1; color: parent.barColor }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Rectangle { width: 22; height: 3; radius: 1.5; color: ThemeService.label; opacity: 0.85 }
            Rectangle { width: 15; height: 3; radius: 1.5; color: ThemeService.secondaryLabel }
        }
    }
    // A dotted mini month grid with one highlighted "today".
    component CalMiniGrid: Grid {
        property color todayColor: ThemeService.accent("red")
        columns: 7; columnSpacing: 2; rowSpacing: 2
        Repeater {
            model: 28
            delegate: Rectangle {
                required property int index
                width: 3; height: 3; radius: 1.5
                color: index === 15 ? parent.todayColor : ThemeService.secondaryLabel
                scale: index === 15 ? 1.6 : 1
            }
        }
    }

    // A calendar-layout preview card (stage 2 of the gallery).
    component CalendarLayoutCard: Rectangle {
        id: clc2
        property int layoutId: 1
        readonly property var names: ["Small", "Medium", "Large"]
        readonly property color prevRed: ThemeService.accent("red")
        width: layoutId === 1 ? 96 : 128
        height: 116
        radius: 14
        color: clc2Hover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: clc2Ma.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: clc2.layoutId === 1 ? 60 : 100
                height: 72; radius: 12; clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator; border.width: 1

                // Small: day + big date + one event
                Column {
                    visible: clc2.layoutId === 1
                    anchors { left: parent.left; top: parent.top; margins: 8 }
                    spacing: 1
                    Text { text: "Mon"; color: clc2.prevRed
                           font.family: "SF Pro Display"; font.pixelSize: 7; font.weight: Font.Bold }
                    Text { text: "22"; color: ThemeService.label
                           font.family: "SF Pro Display"; font.pixelSize: 19; font.weight: Font.Light }
                    CalMiniEvent { barColor: ThemeService.accent("purple") }
                }
                // Medium: events left, grid right
                Column {
                    visible: clc2.layoutId === 2
                    anchors { left: parent.left; top: parent.top; margins: 9 }
                    spacing: 7
                    CalMiniEvent { barColor: ThemeService.accent("purple") }
                    CalMiniEvent { barColor: ThemeService.accent("green") }
                }
                CalMiniGrid {
                    todayColor: clc2.prevRed
                    visible: clc2.layoutId === 2
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 9 }
                }
                // Large: date + grid top, events below
                Item {
                    visible: clc2.layoutId === 3
                    anchors.fill: parent; anchors.margins: 9
                    Text { text: "22"; color: ThemeService.label
                           font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.Light }
                    CalMiniGrid { todayColor: clc2.prevRed; anchors.right: parent.right; anchors.top: parent.top }
                    Row {
                        anchors { left: parent.left; bottom: parent.bottom }
                        spacing: 9
                        CalMiniEvent { barColor: ThemeService.accent("purple") }
                        CalMiniEvent { barColor: ThemeService.accent("green") }
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: clc2.names[clc2.layoutId - 1]
                   color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: clc2Hover }
        MouseArea {
            id: clc2Ma
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                let sz = WidgetsService.calendarSize(clc2.layoutId)
                board.tryAddWidget("calendar", board.width / 2 - sz.nw / 2, board.height / 2 - sz.nh / 2,
                    { layout: clc2.layoutId })
            }
        }
    }

    component StockAddCard: Rectangle {
        id: stockCard
        width: 128
        height: 116
        radius: 14
        color: stockHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator
        border.width: 1
        scale: stockArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 100
                height: 72
                radius: 12
                clip: true
                color: ThemeService.cardBg
                Canvas {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 10
                    height: 34
                    onPaint: {
                        let ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        let values = [0.72, 0.58, 0.64, 0.45, 0.52, 0.31, 0.38, 0.22]
                        ctx.beginPath()
                        for (let i = 0; i < values.length; i++) {
                            let x = i * width / (values.length - 1)
                            let y = values[i] * height
                            if (i === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.strokeStyle = "#30d158"
                        ctx.lineWidth = 1.7
                        ctx.lineJoin = "round"
                        ctx.stroke()
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.verticalCenter }
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    height: 1
                    color: ThemeService.separator
                }
                Row {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.margins: 10
                    height: 14
                    spacing: 5
                    Rectangle { width: (parent.width - 5) / 2; height: 14; radius: 4; color: "#30d158" }
                    Rectangle { width: (parent.width - 5) / 2; height: 14; radius: 4; color: "#ff453a" }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Trade & Analyze"
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }

        HoverHandler { id: stockHover }
        MouseArea {
            id: stockArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                let size = WidgetsService.stockSize()
                board.tryAddWidget("stock", board.width / 2 - size.nw / 2,
                    board.height / 2 - size.nh / 2)
            }
        }
    }

    component YoutubeAddCard: Rectangle {
        id: youtubeCard
        property int layoutId: 3
        readonly property var layoutNames: ["Small", "Medium", "Large"]
        width: layoutId === 1 ? 96 : (layoutId === 2 ? 134 : 150)
        height: 116
        radius: 14
        color: youtubeHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator
        border.width: 1
        scale: youtubeArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: layoutId === 1 ? 68 : (layoutId === 2 ? 104 : 122)
                height: 72
                radius: 12
                clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        width: layoutId === 1 ? 26 : (layoutId === 2 ? 30 : 34)
                        height: layoutId === 1 ? 19 : (layoutId === 2 ? 22 : 24)
                        radius: 6
                        color: "#ff0033"
                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            color: "#ffffff"
                            font.pixelSize: 12
                        }
                    }
                    Column {
                        visible: layoutId > 1
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Rectangle { width: layoutId === 2 ? 46 : 54; height: 5; radius: 2.5; color: ThemeService.label; opacity: 0.82 }
                        Rectangle { width: layoutId === 2 ? 32 : 38; height: 4; radius: 2; color: ThemeService.secondaryLabel }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.margins: 10
                    height: 3
                    radius: 1.5
                    color: ThemeService.separator
                    Rectangle { width: parent.width * 0.68; height: parent.height; radius: parent.radius; color: "#ff375f" }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: youtubeCard.layoutNames[youtubeCard.layoutId - 1]
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }

        HoverHandler { id: youtubeHover }
        MouseArea {
            id: youtubeArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                let size = WidgetsService.youtubeSize(youtubeCard.layoutId)
                board.tryAddWidget("youtube", board.width / 2 - size.nw / 2,
                    board.height / 2 - size.nh / 2, { layout: youtubeCard.layoutId })
            }
        }
    }

    component SpotifyAddCard: Rectangle {
        id: spotifyCard
        property int layoutId: 3
        readonly property var layoutNames: ["Small", "Medium", "Large"]
        width: layoutId === 1 ? 96 : (layoutId === 2 ? 134 : 150)
        height: 116
        radius: 14
        color: spotifyHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator
        border.width: 1
        scale: spotifyArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: layoutId === 1 ? 68 : (layoutId === 2 ? 104 : 122)
                height: 72
                radius: 12
                clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        width: layoutId === 1 ? 24 : 26
                        height: layoutId === 1 ? 24 : 26
                        radius: width / 2
                        color: "#1DB954"
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: "#ffffff"
                            font.family: ThemeService.iconFont
                            font.pixelSize: 14
                        }
                    }
                    Column {
                        visible: layoutId > 1
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Rectangle { width: layoutId === 2 ? 46 : 54; height: 5; radius: 2.5; color: ThemeService.label; opacity: 0.82 }
                        Rectangle { width: layoutId === 2 ? 32 : 38; height: 4; radius: 2; color: ThemeService.secondaryLabel }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.margins: 10
                    height: 3
                    radius: 1.5
                    color: ThemeService.separator
                    Rectangle { width: parent.width * 0.68; height: parent.height; radius: parent.radius; color: "#1DB954" }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: spotifyCard.layoutNames[spotifyCard.layoutId - 1]
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }

        HoverHandler { id: spotifyHover }
        MouseArea {
            id: spotifyArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                let size = WidgetsService.spotifySize(spotifyCard.layoutId)
                board.tryAddWidget("spotify", board.width / 2 - size.nw / 2,
                    board.height / 2 - size.nh / 2, { layout: spotifyCard.layoutId })
            }
        }
    }

    // A row in the widget picker's type sidebar.
    component SidebarRow: Rectangle {
        id: sbr
        property string kind: "all"
        property string label: ""
        property string glyph: "\uf00a"
        width: parent ? parent.width : 176
        height: 34
        radius: 9
        color: gallery.selType === kind ? gallery.selectedColor
             : (sbrHover.hovered ? gallery.subtleColor : "transparent")
        scale: sbrMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Row {
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: sbr.glyph; color: ThemeService.secondaryLabel
                font.family: ThemeService.iconFont; font.pixelSize: 13
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: sbr.label; color: ThemeService.label
                font.family: "SF Pro Display"; font.pixelSize: 13
            }
        }
        HoverHandler { id: sbrHover }
        MouseArea {
            id: sbrMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { gallery.selType = sbr.kind; searchField.text = "" }
        }
    }

    // The note card in the picker (notes have no layouts — one sticky preview).
    component NoteAddCard: Rectangle {
        id: nac
        width: 96
        height: 116
        radius: 14
        color: nacHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        border.color: ThemeService.separator; border.width: 1
        scale: nacMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 60; height: 72; radius: 4
                color: WidgetsService.palette[0]
                Rectangle {   // Stickies title strip
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 10; radius: 4
                    color: Qt.darker(WidgetsService.palette[0], 1.10)
                }
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 8; anchors.topMargin: 16
                    spacing: 4
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: parent.width * (1 - index * 0.2); height: 3; radius: 1.5
                            color: Qt.rgba(0, 0, 0, 0.30)
                        }
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Sticky"
                   color: ThemeService.label; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }
        HoverHandler { id: nacHover }
        MouseArea {
            id: nacMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: board.tryAddWidget("note", board.width / 2 - 120, board.height / 2 + 60)
        }
    }

    // A row in the right-click context menu.
    component CtxRow: Rectangle {
        id: cr
        property string label: ""
        property bool danger: false
        signal triggered()
        width: parent ? parent.width : 150
        height: 34
        color: crHover.hovered && enabled ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        opacity: enabled ? 1.0 : 0.4
        scale: crMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 14
            text: cr.label
            color: cr.danger ? "#ff6b6b" : "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 13
        }
        HoverHandler { id: crHover; enabled: cr.enabled }
        MouseArea {
            id: crMa
            anchors.fill: parent
            enabled: cr.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: cr.triggered()
        }
    }
}
