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

    property bool _surfaceVisible: false
    property bool show: false

    signal closeRequested
    signal reopenRequested

    // Note "저장" → in-board save dialog (NoteExportPicker), called from
    // NoteWidget via frame.winRef.
    function openNoteExport(index, filename, content, closeAfter) {
        board.openExport(index, filename, content, closeAfter);
    }

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-widgets"
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: show ? null : closedRegion
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            let m = Hyprland.focusedMonitor;
            if (m && m.screen)
                win.screen = m.screen;
            WidgetsService.activateBoard(m && m.name ? m.name : (win.screen ? win.screen.name : "unknown-monitor"));
            _surfaceVisible = true;
            Qt.callLater(() => board.forceActiveFocus());
        } else {
            board.endDragPreview();
        }
    }

    anchors {
        bottom: true
        left: true
        right: true
        top: true
    }
    Region {
        id: closedRegion
    }
    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: win.show ? 1.0 : 0.0

        Behavior on opacity {
            AppleSpring {
                spring: 18
            }
        }
    }
    FocusScope {
        id: board

        // Right-click context menu + editor state.
        property int ctxIndex: -1
        property real ctxX: 0
        property real ctxY: 0

        // ── Edit-mode drag & drop (free placement) ─────────────────────────
        // While dragging, a translucent preview marks the snapped drop slot;
        // white = free, red-tinted = occupied. Dropping on a free slot places
        // the widget there; anywhere else it springs back to where it was.
        property bool dragActive: false
        property bool dragFree: true
        property real dragPH: 0
        property real dragPW: 0
        property real dragPX: 0
        property real dragPY: 0
        property int editIndex: -1

        // Edit mode: entered via the pencil button that appears when hovering
        // the top of the screen. While on, non-note widgets show a delete
        // badge and the [+]/[✕] toolbar replaces the pencil.
        property bool editMode: false
        property bool exportCloseAfter: false
        property string exportContent: ""
        property string exportFilename: ""

        // Note export (in-board save dialog). `exportCloseAfter` is set when
        // the export comes from the note's close-confirm dialog: delete the
        // note only once the file has actually been written.
        property int exportIndex: -1
        readonly property int gridMarginBottom: 40
        readonly property int gridMarginTop: 96

        // ── Grid layout ────────────────────────────────────────────────────
        // Everything except sticky notes lives on an n×m grid sized to the
        // monitor (cells of WidgetsService.gridCell + gridGap). Widgets stay
        // where the user put them: relayout() only snaps each one to its
        // nearest cell (sizes always from the type+layout preset) and bumps a
        // widget to the closest free region when its spot is taken (overlap
        // after a monitor change, a fresh add, …).
        readonly property int gridMarginX: 40
        // Centre the columns horizontally. `gridMarginX` is only the *minimum*
        // side margin used to decide how many whole columns fit; whatever width
        // is left over (board width minus those columns) is split evenly into
        // left/right margins instead of piling up as dead space on the right
        // edge — that leftover was almost a full column here, so the rightmost
        // widget looked stranded with a big empty strip beside it. Every X
        // placement calculation below uses this offset (Y stays top-anchored).
        readonly property int gridOffsetX: {
            let g = _gridDims();
            return Math.max(gridMarginX, Math.round((board.width - (g.cols * g.unit - g.gap)) / 2));
        }
        // A second editing canvas for the independent session-lock process.
        // The gallery is shared; only the add target and bounded layout differ.
        property int lockCtxIndex: -1
        property real lockCtxX: 0
        property real lockCtxY: 0
        property bool lockLayoutMode: false
        property int lockReminderEditIndex: -1
        property int lockSettingsIndex: -1
        property var lockReminderSources: []
        property string placementError: ""
        readonly property bool editorOpen: editIndex >= 0 || lockSettingsIndex >= 0
        readonly property int editorDataIndex: lockSettingsIndex >= 0
            ? WidgetsService.lockEditorIndex(lockSettingsIndex) : editIndex
        readonly property string editorType: lockSettingsIndex >= 0
            ? WidgetsService.lockTypeAt(lockSettingsIndex) : WidgetsService.typeAt(editIndex)
        property bool showGallery: false
        property int topNoteZ: 50000 + WidgetsService.widgets.count + 10
        property int topZ: WidgetsService.widgets.count + 10
        property int viewIndex: -1   // reminders "View All"

        function _freeSlot(type, x, y, extra) {
            let span = _newWidgetSpan(type, extra);
            if (!span)
                return {
                    x: x,
                    y: y
                };
            let g = _gridDims();
            if (span.sw > g.cols || span.sh > g.rows)
                return null;
            let occupied = [];
            for (let r = 0; r < g.rows; r++)
                occupied.push(new Array(g.cols).fill(false));
            for (let i = 0; i < WidgetsService.widgets.count; i++) {
                let widget = WidgetsService.widgets.get(i);
                if (widget.type === "note")
                    continue;
                let current = _spans(i);
                let column = Math.round((widget.nx - gridOffsetX) / g.unit);
                let row = Math.round((widget.ny - gridMarginTop) / g.unit);
                for (let dr = 0; dr < current.sh; dr++)
                    for (let dc = 0; dc < current.sw; dc++)
                        if (row + dr >= 0 && row + dr < g.rows && column + dc >= 0 && column + dc < g.cols)
                            occupied[row + dr][column + dc] = true;
            }
            function fits(row, column) {
                if (column < 0 || row < 0 || column + span.sw > g.cols || row + span.sh > g.rows)
                    return false;
                for (let dr = 0; dr < span.sh; dr++)
                    for (let dc = 0; dc < span.sw; dc++)
                        if (occupied[row + dr][column + dc])
                            return false;
                return true;
            }
            let preferredColumn = Math.max(0, Math.min(g.cols - span.sw, Math.round((x - gridOffsetX) / g.unit)));
            let preferredRow = Math.max(0, Math.min(g.rows - span.sh, Math.round((y - gridMarginTop) / g.unit)));
            let best = null;
            let bestDistance = Number.MAX_VALUE;
            for (let row = 0; row <= g.rows - span.sh; row++)
                for (let column = 0; column <= g.cols - span.sw; column++) {
                    if (!fits(row, column))
                        continue;
                    let distance = Math.abs(row - preferredRow) + Math.abs(column - preferredColumn);
                    if (distance < bestDistance) {
                        bestDistance = distance;
                        best = {
                            x: gridOffsetX + column * g.unit,
                            y: gridMarginTop + row * g.unit
                        };
                    }
                }
            return best;
        }
        function _gridDims() {
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap;
            return {
                unit: unit,
                gap: gap,
                cols: Math.max(1, Math.floor((board.width - gridMarginX * 2 + gap) / unit)),
                rows: Math.max(1, Math.floor((board.height - gridMarginTop - gridMarginBottom + gap) / unit))
            };
        }
        function _newWidgetSpan(type, extra) {
            let layout = extra && extra.layout ? extra.layout : 0;
            let preset = WidgetsService.presetSize(type, layout);
            if (!preset)
                return null;
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap;
            return {
                sw: Math.max(1, Math.round((preset.nw + gap) / unit)),
                sh: Math.max(1, Math.round((preset.nh + gap) / unit))
            };
        }
        // Cell spans of widget i, from its type+layout preset (not persisted
        // nw/nh — idempotent, and heals any size a past bug clamped down).
        function _spans(i) {
            let w = WidgetsService.widgets.get(i);
            let ps = WidgetsService.presetSize(w.type, WidgetsService.getData(i).layout);
            let unit = WidgetsService.gridUnit, gap = WidgetsService.gridGap;
            return {
                sw: Math.max(1, Math.round(((ps ? ps.nw : w.nw) + gap) / unit)),
                sh: Math.max(1, Math.round(((ps ? ps.nh : w.nh) + gap) / unit))
            };
        }
        function closeContext() {
            ctxIndex = -1;
        }
        function closeLockContext() {
            lockCtxIndex = -1;
        }
        function closeLockReminderEditor() {
            lockReminderEditIndex = -1;
            lockReminderSources = [];
        }
        function closeEditor() {
            editIndex = -1;
            lockSettingsIndex = -1;
        }
        function closeExport() {
            if (exportIndex < 0)
                return;
            exportIndex = -1;
            exportContent = "";
            // Pull focus off the (now hidden) filename field so stray typing
            // and the Esc chain land on the board again.
            board.forceActiveFocus();
        }
        function closePlacementError() {
            placementError = "";
        }
        function closeView() {
            viewIndex = -1;
        }
        function dropWidgetAt(index, cx, cy, origX, origY) {
            dragActive = false;
            let s = snapRegion(index, cx, cy);
            if (s.free)
                WidgetsService.setPosition(index, s.x, s.y, true);
            else
                WidgetsService.setPosition(index, origX, origY, true);
            WidgetsService.relayoutNeeded();   // snap-verify everything
        }
        function endDragPreview() {
            dragActive = false;
        }
        function openContext(index, x, y) {
            ctxIndex = index;
            ctxX = x;
            ctxY = y;
        }
        function openLockContext(index, x, y) {
            lockCtxIndex = index;
            lockCtxX = x;
            lockCtxY = y;
        }
        function openLockReminderEditor(index) {
            lockCtxIndex = -1;
            lockReminderSources = WidgetsService.reminderSources();
            lockReminderEditIndex = index;
        }
        function openEditor(index) {
            ctxIndex = -1;
            lockSettingsIndex = -1;
            editIndex = index;
        }
        function openLockSettings(index) {
            lockCtxIndex = -1;
            editIndex = -1;
            lockSettingsIndex = index;
        }
        function openExport(index, filename, content, closeAfter) {
            exportFilename = filename;
            exportContent = content;
            exportCloseAfter = !!closeAfter;
            exportIndex = index;
        }
        function openView(index) {
            ctxIndex = -1;
            viewIndex = index;
        }
        function relayout() {
            // The board can relayout before the surface reaches its real size;
            // snapping against a tiny grid would scramble positions, so wait
            // for a plausible geometry.
            if (board.width < 500 || board.height < 400)
                return;
            let g = _gridDims();
            let occ = [];
            for (let r = 0; r < g.rows; r++)
                occ.push(new Array(g.cols).fill(false));

            function fits(r, c, sw, sh) {
                if (c < 0 || r < 0 || c + sw > g.cols || r + sh > g.rows)
                    return false;
                for (let dr = 0; dr < sh; dr++)
                    for (let dc = 0; dc < sw; dc++)
                        if (occ[r + dr][c + dc])
                            return false;
                return true;
            }
            function mark(r, c, sw, sh) {
                for (let dr = 0; dr < sh; dr++)
                    for (let dc = 0; dc < sw; dc++)
                        occ[r + dr][c + dc] = true;
            }

            for (let i = 0; i < WidgetsService.widgets.count; i++) {
                let w = WidgetsService.widgets.get(i);
                if (w.type === "note")
                    continue;
                let s = _spans(i);
                let sw = Math.min(g.cols, s.sw), sh = Math.min(g.rows, s.sh);
                // Nearest cell to where the widget already is.
                let c = Math.max(0, Math.min(g.cols - sw, Math.round((w.nx - gridOffsetX) / g.unit)));
                let r = Math.max(0, Math.min(g.rows - sh, Math.round((w.ny - gridMarginTop) / g.unit)));
                if (!fits(r, c, sw, sh)) {
                    let best = null, bestD = 1e9;
                    for (let r2 = 0; r2 <= g.rows - sh; r2++)
                        for (let c2 = 0; c2 <= g.cols - sw; c2++)
                            if (fits(r2, c2, sw, sh)) {
                                let dd = Math.abs(r2 - r) + Math.abs(c2 - c);
                                if (dd < bestD) {
                                    bestD = dd;
                                    best = {
                                        r: r2,
                                        c: c2
                                    };
                                }
                            }
                    if (best) {
                        r = best.r;
                        c = best.c;
                    }   // else: board full — leave overlapped
                }
                mark(r, c, sw, sh);
                WidgetsService.setPosition(i, gridOffsetX + c * g.unit, gridMarginTop + r * g.unit, false);
                WidgetsService.setSize(i, sw * g.unit - g.gap, sh * g.unit - g.gap, false);
            }
            WidgetsService.persist();
        }

        // Slot region under a widget center (cx, cy), snapped + clamped.
        function snapRegion(index, cx, cy) {
            let g = _gridDims();
            let s = _spans(index);
            let sw = Math.min(g.cols, s.sw), sh = Math.min(g.rows, s.sh);
            let c = Math.max(0, Math.min(g.cols - sw, Math.round((cx - gridOffsetX) / g.unit - sw / 2)));
            let r = Math.max(0, Math.min(g.rows - sh, Math.round((cy - gridMarginTop) / g.unit - sh / 2)));
            let free = true;
            for (let i = 0; i < WidgetsService.widgets.count && free; i++) {
                if (i === index)
                    continue;
                let w = WidgetsService.widgets.get(i);
                if (w.type === "note")
                    continue;
                let s2 = _spans(i);
                let c2 = Math.round((w.nx - gridOffsetX) / g.unit);
                let r2 = Math.round((w.ny - gridMarginTop) / g.unit);
                if (c < c2 + s2.sw && c2 < c + sw && r < r2 + s2.sh && r2 < r + sh)
                    free = false;
            }
            return {
                x: gridOffsetX + c * g.unit,
                y: gridMarginTop + r * g.unit,
                w: sw * g.unit - g.gap,
                h: sh * g.unit - g.gap,
                free: free
            };
        }
        function tryAddWidget(type, x, y, extra) {
            if (board.lockLayoutMode) {
                const span = WidgetsService._lockSpan(type, extra || ({}));
                const added = WidgetsService.addLockWidget(type, extra);
                if (added < 0) {
                    placementError = span.columns > WidgetsService.lockGridColumns || span.rows > WidgetsService.lockGridRows ? "This widget is larger than the Lock Screen grid. Choose a smaller layout." : "There isn’t enough room on the Lock Screen. Remove or move a widget, then try again.";
                }
                return added;
            }
            let slot = _freeSlot(type, x, y, extra);
            if (!slot) {
                placementError = "There isn’t enough room for this widget. Remove or move a widget, then try again.";
                return -1;
            }
            return WidgetsService.addWidget(type, slot.x, slot.y, extra);
        }
        function updateDragPreview(index, cx, cy) {
            let s = snapRegion(index, cx, cy);
            dragPX = s.x;
            dragPY = s.y;
            dragPW = s.w;
            dragPH = s.h;
            dragFree = s.free;
            dragActive = true;
        }

        anchors.fill: parent
        focus: true
        opacity: win.show ? 1.0 : 0.0
        scale: win.show ? 1.0 : 0.98
        transformOrigin: Item.Center

        Behavior on opacity {
            AppleSpring {
                spring: 18
            }
        }
        Behavior on scale {
            AppleSpring {
                spring: 13
            }
        }

        Component.onCompleted: relayoutTimer.restart()
        Keys.onEscapePressed: {
            if (board.placementError !== "")
                board.closePlacementError();
            else if (board.lockReminderEditIndex >= 0)
                board.closeLockReminderEditor();
            else if (board.lockCtxIndex >= 0)
                board.closeLockContext();
            else if (board.exportIndex >= 0)
                board.closeExport();
            else if (board.ctxIndex >= 0)
                board.closeContext();
            else if (board.viewIndex >= 0)
                board.closeView();
            else if (board.editorOpen)
                board.closeEditor();
            else if (board.showGallery)
                board.showGallery = false;
            else if (board.lockLayoutMode)
                board.lockLayoutMode = false;
            else if (board.editMode)
                board.editMode = false;
            else
                win.closeRequested();
        }
        onHeightChanged: relayoutTimer.restart()
        onOpacityChanged: if (!win.show && opacity <= 0.002)
            win._surfaceVisible = false
        onWidthChanged: relayoutTimer.restart()

        Timer {
            id: relayoutTimer

            interval: 40

            onTriggered: board.relayout()
        }
        Connections {
            function onRelayoutNeeded() {
                relayoutTimer.restart();
            }

            target: WidgetsService

            function onLockPlacementRejected(message) {
                board.placementError = message;
            }
        }
        MouseArea {
            acceptedButtons: Qt.LeftButton
            anchors.fill: parent

            onClicked: {
                board.forceActiveFocus();
                board.showGallery = false;
            }
        }

        // ── Drop preview (edit-mode drag) ─────────────────────────────────
        // Sits under the widgets (their z starts at 1): a faint translucent
        // slot marker that follows the drag, red-tinted when the slot is taken.
        Rectangle {
            border.color: board.dragFree ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 0.45, 0.4, 0.55)
            border.width: 1.5
            color: board.dragFree ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 0.35, 0.3, 0.10)
            height: board.dragPH
            radius: 13
            visible: board.editMode && !board.lockLayoutMode && board.dragActive
            width: board.dragPW
            x: board.dragPX
            y: board.dragPY
            z: 0.5

            Behavior on x {
                AppleSpring {
                    epsilon: 0.15
                    spring: 18
                }
            }
            Behavior on y {
                AppleSpring {
                    epsilon: 0.15
                    spring: 18
                }
            }
        }

        // ── Widgets ──────────────────────────────────────────────────────
        Repeater {
            model: WidgetsService.widgets
            visible: !board.lockLayoutMode

            delegate: WidgetFrame {
                boardItem: board
                winRef: win
            }
        }
        LockLayoutEditor {
            id: lockLayoutEditor

            active: board.editMode && board.lockLayoutMode
            anchors.fill: parent
            contentActive: win.show && active
            z: 90000

            onWidgetSettingsRequested: (index, x, y) => board.openLockContext(index, x, y)
        }

        // ── Top edit controls ──────────────────────────────────────────────
        // Idle: nothing visible. Hovering the top strip of the screen fades in
        // a pencil button; clicking it enters edit mode, where the pencil is
        // replaced by [+] (open the widget gallery) and [✕] (leave edit mode).
        Item {
            id: topZone

            height: 72
            z: 100000

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            HoverHandler {
                id: topHover
            }
        }

        // Pencil (enter edit mode) — icon only, shown on top-strip hover.
        Rectangle {
            id: editBtn

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            border.color: ThemeService.separator
            border.width: 1
            color: ebHover.hovered ? ThemeService.controlBgHover : ThemeService.panelBg
            height: 40
            opacity: (!board.editMode && (topHover.hovered || ebHover.hovered)) ? 1 : 0
            radius: 20
            scale: editMa.pressed ? ThemeService.pressScale : 1.0
            visible: opacity > 0
            width: 40
            z: 100001

            Behavior on opacity {
                AppleSpring {
                    spring: 18
                }
            }
            Behavior on scale {
                AppleSpring {
                    spring: 18
                }
            }

            Text {
                anchors.centerIn: parent
                color: ThemeService.label
                font.family: ThemeService.iconFont
                font.pixelSize: 15
                text: ""   // nf-fa-pencil
            }
            HoverHandler {
                id: ebHover
            }
            MouseArea {
                id: editMa

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                onClicked: board.editMode = true
            }
        }

        // Edit-mode toolbar: [+] add widget, [✕] leave edit mode.
        Rectangle {
            id: toolbar

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            border.color: ThemeService.separator
            border.width: 1
            color: ThemeService.panelBg
            height: 46
            opacity: board.editMode ? 1 : 0
            radius: 23
            scale: board.editMode ? 1 : 0.9
            visible: opacity > 0
            width: toolbarRow.width + 24
            z: 100001

            Behavior on opacity {
                AppleSpring {
                    spring: 18
                }
            }
            Behavior on scale {
                AppleSpring {
                    spring: 18
                }
            }

            Row {
                id: toolbarRow

                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: addHover.hovered || board.showGallery ? ThemeService.controlBgHover : ThemeService.controlBg
                    height: 32
                    radius: 16
                    scale: addMa.pressed ? ThemeService.pressScale : 1.0
                    width: 32

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        color: ThemeService.label
                        font.family: "SF Pro Display"
                        font.pixelSize: 19
                        font.weight: Font.Medium
                        text: "+"
                    }
                    HoverHandler {
                        id: addHover
                    }
                    MouseArea {
                        id: addMa

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: board.showGallery = !board.showGallery
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: closeHover.hovered ? ThemeService.controlBgHover : ThemeService.controlBg
                    height: 32
                    radius: 16
                    scale: closeMa.pressed ? ThemeService.pressScale : 1.0
                    width: 32

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        color: ThemeService.label
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        text: "✕"
                    }
                    HoverHandler {
                        id: closeHover
                    }
                    MouseArea {
                        id: closeMa

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            board.editMode = false;
                            board.lockLayoutMode = false;
                            board.showGallery = false;
                            board.closeLockContext();
                            board.closeLockReminderEditor();
                        }
                    }
                }
            }
        }

        // Available only while editing. It sits at the actual screen corner,
        // separate from the central toolbar, so switching canvases is a clear
        // spatial action rather than another gallery mode.
        Rectangle {
            id: lockLayoutButton

            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.top: parent.top
            anchors.topMargin: 24
            border.color: board.lockLayoutMode ? ThemeService.accent("blue") : ThemeService.separator
            border.width: 1
            color: board.lockLayoutMode || lockLayoutHover.hovered ? ThemeService.controlBgHover : ThemeService.panelBg
            height: 42
            opacity: board.editMode ? 1 : 0
            radius: 21
            scale: lockLayoutTap.pressed ? ThemeService.pressScale : 1
            visible: opacity > 0
            width: 42
            z: 100001

            Behavior on opacity {
                AppleSpring {
                    spring: 18
                }
            }
            Behavior on scale {
                AppleSpring {
                    spring: 22
                }
            }

            Text {
                anchors.centerIn: parent
                color: board.lockLayoutMode ? ThemeService.accent("blue") : ThemeService.label
                font.family: ThemeService.iconFont
                font.pixelSize: 15
                text: "\uf023"
            }
            HoverHandler {
                id: lockLayoutHover
            }
            TapHandler {
                id: lockLayoutTap

                onTapped: {
                    board.lockLayoutMode = !board.lockLayoutMode;
                    board.showGallery = false;
                    board.closeContext();
                    board.closeEditor();
                    board.closeLockContext();
                    board.closeLockReminderEditor();
                }
            }
        }

        // ── Widget picker (add menu, macOS style) ──────────────────────────
        // Unfolds top-down from under the [+] button: search + type sidebar on
        // the left, that type's layout previews on the right. Clicking a card
        // adds the widget; the panel stays open until Done / Esc / outside.
        Rectangle {
            id: gallery

            readonly property color cardColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.045)
            readonly property color cardHoverColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.095)
            property string selType: "all"
            readonly property color selectedColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)
            readonly property color subtleColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
            readonly property var types: [
                {
                    kind: "calendar",
                    label: "Calendar",
                    glyph: "\uf073"
                },
                {
                    kind: "clock",
                    label: "Clock",
                    glyph: "\uf017"
                },
                {
                    kind: "news",
                    label: "News",
                    glyph: "\uf1ea"
                },
                {
                    kind: "note",
                    label: "Note",
                    glyph: "\uf249"
                },
                {
                    kind: "reminders",
                    label: "Reminders",
                    glyph: "\uf046"
                },
                {
                    kind: "stock",
                    label: "Stocks",
                    glyph: "\uf201"
                },
                {
                    kind: "downloader",
                    label: "Downloader",
                    glyph: "\uf019"
                },
                {
                    kind: "weather",
                    label: "Weather",
                    glyph: "\ue302"
                }
            ]

            function sectionVisible(kind, label) {
                let q = searchField.text.trim().toLowerCase();
                if (q !== "")
                    return label.toLowerCase().indexOf(q) !== -1;
                return gallery.selType === "all" || gallery.selType === kind;
            }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: toolbar.bottom
            anchors.topMargin: 14
            border.color: ThemeService.separator
            border.width: 1
            clip: true
            color: ThemeService.panelBg
            height: 470
            opacity: board.showGallery ? 1 : 0
            radius: 20
            scale: board.showGallery ? 1 : 0.95
            transformOrigin: Item.Top
            visible: opacity > 0
            width: 780
            z: 100000

            Behavior on opacity {
                AppleSpring {
                    spring: 18
                }
            }
            Behavior on scale {
                AppleSpring {
                    spring: 13
                }
            }

            onVisibleChanged: if (visible) {
                selType = "all";
                searchField.text = "";
            }

            MouseArea {
                anchors.fill: parent
            }   // swallow clicks inside the panel

            // ── Sidebar: search + widget types ─────────────────────────────
            Item {
                id: pickerSidebar

                width: 196

                anchors {
                    bottom: pickerFooter.top
                    left: parent.left
                    top: parent.top
                }
                Rectangle {
                    id: pickerSearch

                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    border.color: searchField.activeFocus ? ThemeService.accent("blue") : ThemeService.separator
                    border.width: 1
                    color: gallery.subtleColor
                    height: 32
                    radius: 9

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: ThemeService.secondaryLabel
                        font.family: ThemeService.iconFont
                        font.pixelSize: 12
                        text: "\uf002"
                    }
                    TextField {
                        id: searchField

                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 8
                        background: null
                        color: ThemeService.label
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        placeholderText: "Search Widgets"
                        placeholderTextColor: ThemeService.tertiaryLabel
                        verticalAlignment: TextInput.AlignVCenter
                    }
                }
                Column {
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 12
                    spacing: 2

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: pickerSearch.bottom
                    }
                    SidebarRow {
                        glyph: "\uf00a"
                        kind: "all"
                        label: "All Widgets"
                    }
                    Repeater {
                        model: gallery.types

                        delegate: SidebarRow {
                            required property var modelData

                            glyph: modelData.glyph
                            kind: modelData.kind
                            label: modelData.label
                        }
                    }
                }
            }
            Rectangle {
                color: ThemeService.separator
                width: 1

                anchors {
                    bottom: pickerFooter.top
                    left: pickerSidebar.right
                    top: parent.top
                }
            }

            // ── Content: layout previews per type ──────────────────────────
            Flickable {
                id: pickerScroll

                // Kinetic scroll (kinetic.js) — same feel as the emoji/nc lists.
                property var _ks: ({})

                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                clip: true
                contentHeight: pickerCol.height + 36
                contentWidth: width
                flickDeceleration: 6000
                maximumFlickVelocity: 6000

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
                rebound: Transition {
                    SpringAnimation {
                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                        properties: "x,y"
                        spring: 18
                    }
                }

                anchors {
                    bottom: pickerFooter.top
                    left: pickerSidebar.right
                    leftMargin: 1
                    right: parent.right
                    top: parent.top
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                    onWheel: ev => {
                        psGlide.stop();
                        if (Kinetic.onWheel(pickerScroll, ev, pickerScroll._ks, {
                            gain: 90
                        }))
                            psEndTimer.restart();
                    }
                }
                Timer {
                    id: psEndTimer

                    interval: 48

                    onTriggered: {
                        let g = Kinetic.fling(pickerScroll, pickerScroll._ks, {});
                        if (g) {
                            psGlide.from = g.from;
                            psGlide.to = g.to;
                            psGlide.restart();
                        }
                    }
                }
                SpringAnimation {
                    id: psGlide

                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                    property: "contentY"
                    spring: 18
                    target: pickerScroll
                }
                Column {
                    id: pickerCol

                    spacing: 24
                    width: pickerScroll.width - 44
                    x: 22
                    y: 18

                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("calendar", "Calendar")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Calendar"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            CalendarLayoutCard {
                                layoutId: 1
                            }
                            CalendarLayoutCard {
                                layoutId: 2
                            }
                            CalendarLayoutCard {
                                layoutId: 3
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("clock", "Clock")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Clock"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            ClockLayoutCard {
                                layoutId: 1
                            }
                            ClockLayoutCard {
                                layoutId: 2
                            }
                            ClockLayoutCard {
                                layoutId: 3
                            }
                            ClockLayoutCard {
                                layoutId: 4
                            }
                            ClockLayoutCard {
                                layoutId: 5
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("news", "News")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "News"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            NewsLayoutCard {
                                layoutId: 4
                            }
                            NewsLayoutCard {
                                layoutId: 1
                            }
                            NewsLayoutCard {
                                layoutId: 2
                            }
                            NewsLayoutCard {
                                layoutId: 3
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("note", "Note")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Note"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            NoteAddCard {}
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("reminders", "Reminders")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Reminders"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            RemindersLayoutCard {
                                layoutId: 1
                            }
                            RemindersLayoutCard {
                                layoutId: 2
                            }
                            RemindersLayoutCard {
                                layoutId: 3
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("stock", "Stocks")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Stocks"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            StockAddCard {
                                layoutId: 1
                            }
                            StockAddCard {
                                layoutId: 2
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("downloader", "YouTube Downloader")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "YouTube Downloader"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            YoutubeAddCard {
                                layoutId: 1
                            }
                            YoutubeAddCard {
                                layoutId: 2
                            }
                            YoutubeAddCard {
                                layoutId: 3
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("downloader", "Spotify Downloader")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Spotify Downloader"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            SpotifyAddCard {
                                layoutId: 1
                            }
                            SpotifyAddCard {
                                layoutId: 2
                            }
                            SpotifyAddCard {
                                layoutId: 3
                            }
                        }
                    }
                    Column {
                        spacing: 10
                        visible: gallery.sectionVisible("weather", "Weather")
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: "Weather"
                        }
                        Flow {
                            spacing: 12
                            width: parent.width

                            WeatherLayoutCard {
                                layoutId: 1
                            }
                            WeatherLayoutCard {
                                layoutId: 2
                            }
                            WeatherLayoutCard {
                                layoutId: 3
                            }
                            WeatherLayoutCard {
                                layoutId: 4
                            }
                        }
                    }
                }
            }

            // ── Footer: hint + Done ─────────────────────────────────────────
            Rectangle {
                id: pickerFooter

                color: gallery.subtleColor
                height: 52

                anchors {
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                Rectangle {
                    color: ThemeService.separator
                    height: 1

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: ThemeService.secondaryLabel
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    text: board.lockLayoutMode ? "Click a widget to add it to the Lock Screen" : "Click a widget to add it to the board"
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: pDoneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                    height: 30
                    radius: 15
                    scale: pDoneMa.pressed ? ThemeService.pressScale : 1.0
                    width: 76

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        text: "Done"
                    }
                    HoverHandler {
                        id: pDoneHover
                    }
                    MouseArea {
                        id: pDoneMa

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: board.showGallery = false
                    }
                }
            }
        }

        // ── Empty state hint ───────────────────────────────────────────────
        Text {
            anchors.centerIn: parent
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: "SF Pro Display"
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            text: "No widgets"
            visible: WidgetsService.widgets.count === 0 && !board.showGallery
        }

        // ── Lock widget context menu ─────────────────────────────────────
        // Every widget exposes the same anchored Settings affordance as the
        // desktop board. Reminder additionally keeps its stable-list picker.
        Item {
            anchors.fill: parent
            visible: board.lockCtxIndex >= 0 || lockContextPanel.opacity > 0.002
            z: 100002

            MouseArea {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                anchors.fill: parent
                enabled: board.lockCtxIndex >= 0

                onPressed: board.closeLockContext()
            }
            Rectangle {
                id: lockContextPanel

                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.14, 0.14, 0.16, 0.97)
                height: lockMenuColumn.implicitHeight + 10
                opacity: board.lockCtxIndex >= 0 ? 1 : 0
                radius: 11
                scale: board.lockCtxIndex >= 0 ? 1 : 0.94
                transformOrigin: Item.TopLeft
                width: 156
                x: Math.max(8, Math.min(board.lockCtxX, board.width - width - 8))
                y: Math.max(8, Math.min(board.lockCtxY, board.height - height - 8))

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 18
                    }
                }

                Column {
                    id: lockMenuColumn

                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width

                    CtxRow {
                        label: "Edit List"
                        visible: WidgetsService.lockTypeAt(board.lockCtxIndex) === "reminders"

                        onTriggered: board.openLockReminderEditor(board.lockCtxIndex)
                    }
                    CtxRow {
                        label: "Settings"
                        visible: WidgetsService.lockTypeAt(board.lockCtxIndex) !== "reminders"

                        onTriggered: board.openLockSettings(board.lockCtxIndex)
                    }
                }
            }
        }

        // The picker lists ordinary desktop Reminder widgets across monitors.
        // Clicking one commits immediately and returns to the spatial canvas.
        Item {
            anchors.fill: parent
            visible: board.lockReminderEditIndex >= 0 || lockReminderEditorPanel.opacity > 0.002
            z: 100003

            MouseArea {
                anchors.fill: parent
                enabled: board.lockReminderEditIndex >= 0

                onPressed: board.closeLockReminderEditor()
            }
            Rectangle {
                id: lockReminderEditorPanel

                readonly property var sources: board.lockReminderSources

                anchors.centerIn: parent
                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.10, 0.10, 0.12, 0.98)
                height: Math.min(560, Math.max(250, 146 + sources.length * 66))
                opacity: board.lockReminderEditIndex >= 0 ? 1 : 0
                radius: 18
                scale: board.lockReminderEditIndex >= 0 ? 1 : 0.96
                width: Math.min(500, board.width - 48)

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.top: parent.top
                    anchors.topMargin: 20
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    text: "Follow a Reminder List"
                }
                Text {
                    id: lockReminderEditorSubtitle

                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.top: parent.top
                    anchors.topMargin: 52
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    text: "Choose an existing Widgets list. Lock Screen changes sync back to that list."
                    wrapMode: Text.Wrap
                }
                ListView {
                    id: lockReminderSourceList

                    anchors.bottom: lockReminderEditorDone.top
                    anchors.bottomMargin: 12
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.top: lockReminderEditorSubtitle.bottom
                    anchors.topMargin: 16
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    model: lockReminderEditorPanel.sources
                    spacing: 6

                    delegate: Rectangle {
                        id: sourceRow

                        required property var modelData
                        readonly property bool selected: WidgetsService.lockReminderFollows(board.lockReminderEditIndex, modelData.listId)

                        border.color: selected ? ThemeService.accent("blue") : (sourceHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10))
                        border.width: selected ? 2 : 1
                        color: sourceHover.hovered || selected ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.055)
                        height: 60
                        radius: 12
                        scale: sourceTap.pressed ? 0.985 : 1
                        width: lockReminderSourceList.width

                        Behavior on scale {
                            AppleSpring {
                                spring: 20
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: ThemeService.accent(sourceRow.modelData.accent)
                            height: 34
                            radius: 17
                            width: 34

                            Text {
                                anchors.centerIn: parent
                                color: "white"
                                font.family: ThemeService.iconFont
                                font.pixelSize: 14
                                text: ThemeService.reminderGlyph(sourceRow.modelData.icon)
                            }
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 58
                            anchors.right: sourceCheck.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                color: "white"
                                elide: Text.ElideRight
                                font.family: "SF Pro Display"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                text: sourceRow.modelData.title
                                textFormat: Text.PlainText
                                width: parent.width
                            }
                            Text {
                                color: Qt.rgba(1, 1, 1, 0.48)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                text: sourceRow.modelData.board + "  ·  " + sourceRow.modelData.incomplete + " remaining"
                                textFormat: Text.PlainText
                            }
                        }
                        Text {
                            id: sourceCheck

                            anchors.right: parent.right
                            anchors.rightMargin: 15
                            anchors.verticalCenter: parent.verticalCenter
                            color: ThemeService.accent("blue")
                            font.family: "SF Pro Display"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            text: "✓"
                            visible: sourceRow.selected
                        }
                        HoverHandler {
                            id: sourceHover

                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: sourceTap

                            onTapped: {
                                if (WidgetsService.linkLockReminder(board.lockReminderEditIndex, sourceRow.modelData.listId))
                                    board.closeLockReminderEditor();
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: lockReminderSourceList
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: "No Reminder widgets found\nAdd one to the desktop Widgets board first."
                    visible: lockReminderEditorPanel.sources.length === 0
                }
                Rectangle {
                    id: lockReminderEditorDone

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: lockReminderDoneHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)
                    height: 34
                    radius: 10
                    scale: lockReminderDoneTap.pressed ? ThemeService.pressScale : 1
                    width: 92

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        color: "white"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        text: "Done"
                    }
                    HoverHandler {
                        id: lockReminderDoneHover

                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        id: lockReminderDoneTap

                        onTapped: board.closeLockReminderEditor()
                    }
                }
            }
        }

        // ── Right-click context menu ───────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.ctxIndex >= 0 || contextPanel.opacity > 0.002
            z: 100002

            MouseArea {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                anchors.fill: parent
                enabled: board.ctxIndex >= 0

                onPressed: board.closeContext()
            }
            Rectangle {
                id: contextPanel

                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.14, 0.14, 0.16, 0.97)
                height: menuCol.implicitHeight + 10
                opacity: board.ctxIndex >= 0 ? 1 : 0
                radius: 11
                scale: board.ctxIndex >= 0 ? 1 : 0.94
                transformOrigin: Item.TopLeft
                width: 156
                x: Math.max(8, Math.min(board.ctxX, board.width - width - 8))
                y: Math.max(8, Math.min(board.ctxY, board.height - height - 8))

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 18
                    }
                }

                Column {
                    id: menuCol

                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width

                    CtxRow {
                        label: "View All"
                        visible: WidgetsService.typeAt(board.ctxIndex) === "reminders"

                        onTriggered: board.openView(board.ctxIndex)
                    }
                    CtxRow {
                        enabled: WidgetsService.typeAt(board.ctxIndex) === "clock" || WidgetsService.typeAt(board.ctxIndex) === "weather" || WidgetsService.typeAt(board.ctxIndex) === "reminders" || WidgetsService.typeAt(board.ctxIndex) === "news" || WidgetsService.typeAt(board.ctxIndex) === "calendar" || WidgetsService.typeAt(board.ctxIndex) === "stock" || WidgetsService.typeAt(board.ctxIndex) === "youtube" || WidgetsService.typeAt(board.ctxIndex) === "spotify" || WidgetsService.typeAt(board.ctxIndex) === "note"
                        label: "Settings"

                        onTriggered: board.openEditor(board.ctxIndex)
                    }
                }
            }
        }

        // ── Editor (modal) ─────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.editorOpen || editorPanel.opacity > 0.002
            z: 100003

            MouseArea {
                anchors.fill: parent
                enabled: board.editorOpen

                onPressed: board.closeEditor()
            }
            Rectangle {
                id: editorPanel

                readonly property real maximumHeight: Math.min(760, board.height - 80)

                anchors.centerIn: parent
                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                height: Math.min(editLoader.implicitHeight + 84, maximumHeight)
                opacity: board.editorOpen ? 1 : 0
                radius: 18
                scale: board.editorOpen ? 1 : 0.95
                width: Math.min(484, board.width - 48)

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                }
                Flickable {
                    id: editorScroll

                    property var _ks: ({})

                    anchors.bottomMargin: 16
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    anchors.topMargin: 22
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    boundsMovement: Flickable.FollowBoundsBehavior
                    clip: true
                    contentHeight: editLoader.implicitHeight
                    contentWidth: width
                    flickDeceleration: 6000
                    interactive: contentHeight > height
                    maximumFlickVelocity: 6000

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                    rebound: Transition {
                        SpringAnimation {
                            damping: ThemeService.momentumDamping
                            epsilon: 0.25
                            properties: "x,y"
                            spring: 18
                        }
                    }

                    anchors {
                        bottom: editorDone.top
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                        onWheel: ev => {
                            editorGlide.stop();
                            if (Kinetic.onWheel(editorScroll, ev, editorScroll._ks, {
                                gain: 90
                            }))
                                editorEndTimer.restart();
                        }
                    }
                    Timer {
                        id: editorEndTimer

                        interval: 48

                        onTriggered: {
                            let glide = Kinetic.fling(editorScroll, editorScroll._ks, {});
                            if (glide) {
                                editorGlide.from = glide.from;
                                editorGlide.to = glide.to;
                                editorGlide.restart();
                            }
                        }
                    }
                    SpringAnimation {
                        id: editorGlide

                        damping: ThemeService.momentumDamping
                        epsilon: 0.25
                        property: "contentY"
                        spring: 18
                        target: editorScroll
                    }
                    Loader {
                        id: editLoader

                        sourceComponent: {
                            if (!board.editorOpen)
                                return noOptionsComp;
                            let t = board.editorType;
                            if (t === "clock")
                                return clockEditorComp;
                            if (t === "weather")
                                return weatherEditorComp;
                            if (t === "reminders")
                                return remindersEditorComp;
                            if (t === "news")
                                return newsEditorComp;
                            if (t === "calendar")
                                return calendarEditorComp;
                            if (t === "stock")
                                return stockEditorComp;
                            if (t === "youtube")
                                return youtubeEditorComp;
                            if (t === "spotify")
                                return spotifyEditorComp;
                            if (t === "note")
                                return noteEditorComp;
                            return noOptionsComp;
                        }
                        width: parent.width
                    }
                }
                Rectangle {
                    id: editorDone

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    color: doneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                    height: 32
                    radius: 9
                    scale: editorDoneMa.pressed ? ThemeService.pressScale : 1.0
                    width: 78

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        text: "Done"
                    }
                    HoverHandler {
                        id: doneHover
                    }
                    MouseArea {
                        id: editorDoneMa

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: board.closeEditor()
                    }
                }
                Component {
                    id: clockEditorComp

                    ClockEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: weatherEditorComp

                    WeatherEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: remindersEditorComp

                    RemindersEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: newsEditorComp

                    NewsEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: calendarEditorComp

                    CalendarEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: stockEditorComp

                    StockEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: youtubeEditorComp

                    YoutubeEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: spotifyEditorComp

                    SpotifyEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: noteEditorComp

                    NoteEditor {
                        index: board.editorDataIndex
                    }
                }
                Component {
                    id: noOptionsComp

                    Text {
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        text: "No editable options for this widget."
                    }
                }
            }
        }

        // ── Note export "save as" dialog (modal) ───────────────────────────
        Item {
            anchors.fill: parent
            visible: board.exportIndex >= 0 || exportPanel.opacity > 0.002
            z: 100004

            MouseArea {
                anchors.fill: parent
                enabled: board.exportIndex >= 0

                onPressed: board.closeExport()
            }
            Rectangle {
                id: exportPanel

                anchors.centerIn: parent
                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                height: Math.min(exportPicker.implicitHeight + 44, board.height - 64)
                opacity: board.exportIndex >= 0 ? 1 : 0
                radius: 18
                scale: board.exportIndex >= 0 ? 1 : 0.95
                width: Math.min(514, board.width - 48)

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                }
                NoteExportPicker {
                    id: exportPicker

                    active: board.exportIndex >= 0
                    anchors.fill: parent
                    anchors.margins: 22
                    content: board.exportContent
                    filename: board.exportFilename

                    onCancelled: board.closeExport()
                    onSaved: {
                        let i = board.exportIndex;
                        let del = board.exportCloseAfter;
                        board.closeExport();
                        // Deferred so the removal doesn't tear down this
                        // picker inside its own signal handler.
                        if (del)
                            Qt.callLater(function () {
                                WidgetsService.removeAt(i);
                            });
                    }
                }
            }
        }

        // ── Reminders "View All" (modal) ───────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.viewIndex >= 0 || viewerPanel.opacity > 0.002
            z: 100003

            MouseArea {
                anchors.fill: parent
                enabled: board.viewIndex >= 0

                onPressed: board.closeView()
            }
            Rectangle {
                id: viewerPanel

                anchors.centerIn: parent
                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                height: viewCol.implicitHeight + 28
                opacity: board.viewIndex >= 0 ? 1 : 0
                radius: 18
                scale: board.viewIndex >= 0 ? 1 : 0.95
                width: 452

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                }
                Column {
                    id: viewCol

                    anchors.centerIn: parent
                    spacing: 14
                    width: parent.width - 44

                    RemindersViewer {
                        index: board.viewIndex
                        width: parent.width
                    }
                    Rectangle {
                        anchors.right: parent.right
                        color: vDoneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                        height: 32
                        radius: 9
                        scale: viewerDoneMa.pressed ? ThemeService.pressScale : 1.0
                        width: 78

                        Behavior on scale {
                            AppleSpring {
                                spring: 18
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            text: "Done"
                        }
                        HoverHandler {
                            id: vDoneHover
                        }
                        MouseArea {
                            id: viewerDoneMa

                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: board.closeView()
                        }
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

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: board.placementError !== ""

                onPressed: board.closePlacementError()
            }
            Rectangle {
                anchors.centerIn: placementPanel
                anchors.verticalCenterOffset: 8
                color: Qt.rgba(0, 0, 0, 0.36)
                height: placementPanel.height
                opacity: placementPanel.opacity
                radius: placementPanel.radius
                scale: placementPanel.scale
                width: placementPanel.width
            }
            Rectangle {
                id: placementPanel

                anchors.centerIn: parent
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                color: Qt.rgba(0.10, 0.10, 0.12, 0.98)
                height: 190
                opacity: board.placementError !== "" ? 1 : 0
                radius: 18
                scale: board.placementError !== "" ? 1 : 0.94
                width: Math.min(380, board.width - 48)

                Behavior on opacity {
                    AppleSpring {
                        spring: 18
                    }
                }
                Behavior on scale {
                    AppleSpring {
                        spring: 18
                    }
                }

                MouseArea {
                    anchors.fill: parent
                }
                Column {
                    anchors.margins: 22
                    spacing: 9

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: ThemeService.accent("red")
                        height: 38
                        radius: 19
                        width: 38

                        Text {
                            anchors.centerIn: parent
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 23
                            font.weight: Font.DemiBold
                            text: "!"
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.letterSpacing: -0.2
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        text: "Not Enough Space"
                    }
                    Text {
                        color: Qt.rgba(1, 1, 1, 0.66)
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        text: board.placementError
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }
                Rectangle {
                    color: placementOkHover.hovered ? Qt.lighter(ThemeService.accent("blue"), 1.08) : ThemeService.accent("blue")
                    height: 32
                    radius: 10
                    scale: placementOkArea.pressed ? ThemeService.pressScale : 1
                    width: 92

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 16
                        horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        text: "OK"
                    }
                    HoverHandler {
                        id: placementOkHover
                    }
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

    // A tiny colored-bar "event" used by the calendar previews.
    component CalMiniEvent: Row {
        property color barColor: "#BF5AF2"

        spacing: 3

        Rectangle {
            color: parent.barColor
            height: 10
            radius: 1
            width: 2
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Rectangle {
                color: ThemeService.label
                height: 3
                opacity: 0.85
                radius: 1.5
                width: 22
            }
            Rectangle {
                color: ThemeService.secondaryLabel
                height: 3
                radius: 1.5
                width: 15
            }
        }
    }
    // A dotted mini month grid with one highlighted "today".
    component CalMiniGrid: Grid {
        property color todayColor: ThemeService.accent("red")

        columnSpacing: 2
        columns: 7
        rowSpacing: 2

        Repeater {
            model: 28

            delegate: Rectangle {
                required property int index

                color: index === 15 ? parent.todayColor : ThemeService.secondaryLabel
                height: 3
                radius: 1.5
                scale: index === 15 ? 1.6 : 1
                width: 3
            }
        }
    }

    // A calendar-layout preview card (stage 2 of the gallery).
    component CalendarLayoutCard: Rectangle {
        id: clc2

        property int layoutId: 1
        readonly property var names: ["Small", "Medium", "Large"]
        readonly property color prevRed: ThemeService.accent("red")

        border.color: ThemeService.separator
        border.width: 1
        color: clc2Hover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: clc2Ma.pressed ? ThemeService.pressScale : 1.0
        width: layoutId === 1 ? 96 : 128

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: ThemeService.separator
                border.width: 1
                clip: true
                color: ThemeService.cardBg
                height: 72
                radius: 12
                width: clc2.layoutId === 1 ? 60 : 100

                // Small: day + big date + one event
                Column {
                    spacing: 1
                    visible: clc2.layoutId === 1

                    anchors {
                        left: parent.left
                        margins: 8
                        top: parent.top
                    }
                    Text {
                        color: clc2.prevRed
                        font.family: "SF Pro Display"
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        text: "Mon"
                    }
                    Text {
                        color: ThemeService.label
                        font.family: "SF Pro Display"
                        font.pixelSize: 19
                        font.weight: Font.Light
                        text: "22"
                    }
                    CalMiniEvent {
                        barColor: ThemeService.accent("purple")
                    }
                }
                // Medium: events left, grid right
                Column {
                    spacing: 7
                    visible: clc2.layoutId === 2

                    anchors {
                        left: parent.left
                        margins: 9
                        top: parent.top
                    }
                    CalMiniEvent {
                        barColor: ThemeService.accent("purple")
                    }
                    CalMiniEvent {
                        barColor: ThemeService.accent("green")
                    }
                }
                CalMiniGrid {
                    todayColor: clc2.prevRed
                    visible: clc2.layoutId === 2

                    anchors {
                        right: parent.right
                        rightMargin: 9
                        verticalCenter: parent.verticalCenter
                    }
                }
                // Large: date + grid top, events below
                Item {
                    anchors.fill: parent
                    anchors.margins: 9
                    visible: clc2.layoutId === 3

                    Text {
                        color: ThemeService.label
                        font.family: "SF Pro Display"
                        font.pixelSize: 15
                        font.weight: Font.Light
                        text: "22"
                    }
                    CalMiniGrid {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        todayColor: clc2.prevRed
                    }
                    Row {
                        spacing: 9

                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                        }
                        CalMiniEvent {
                            barColor: ThemeService.accent("purple")
                        }
                        CalMiniEvent {
                            barColor: ThemeService.accent("green")
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: clc2.names[clc2.layoutId - 1]
            }
        }
        HoverHandler {
            id: clc2Hover
        }
        MouseArea {
            id: clc2Ma

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                let sz = WidgetsService.calendarSize(clc2.layoutId);
                board.tryAddWidget("calendar", board.width / 2 - sz.nw / 2, board.height / 2 - sz.nh / 2, {
                    layout: clc2.layoutId
                });
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

        border.color: ThemeService.separator
        border.width: 1
        color: clcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: clcMa.pressed ? ThemeService.pressScale : 1.0
        width: layoutId === 2 ? 150 : 96

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            // Mini preview
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: Qt.rgba(0, 0, 0, 0.1)
                border.width: clc.layoutId === 1 || clc.layoutId === 4 ? 1 : 0
                clip: true
                color: clc.layoutId === 1 ? "#ffffff" : clc.layoutId === 4 ? Qt.rgba(0.84, 0.89, 0.96, 0.55) : ThemeService.cardBg
                height: 72
                radius: 12
                width: clc.layoutId === 2 ? 130 : 72

                // 1: digital text
                Text {
                    anchors.centerIn: parent
                    color: "#101012"
                    font.family: "SF Pro Display"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    text: "9:41"
                    visible: clc.layoutId === 1
                }
                // 2: row of mini clocks
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: clc.layoutId === 2

                    Repeater {
                        model: 4

                        delegate: AnalogClock {
                            active: false
                            faceColor: "#ffffff"
                            fixedDate: clc.previewDate
                            handColor: "#1c1c1e"
                            height: 26
                            tickColor: "#1c1c1e"
                            width: 26
                        }
                    }
                }
                // 3: 2x2 mini clocks
                Grid {
                    anchors.centerIn: parent
                    columnSpacing: 6
                    columns: 2
                    rowSpacing: 6
                    rows: 2
                    visible: clc.layoutId === 3

                    Repeater {
                        model: 4

                        delegate: AnalogClock {
                            active: false
                            faceColor: "#ffffff"
                            fixedDate: clc.previewDate
                            handColor: "#1c1c1e"
                            height: 28
                            tickColor: "#1c1c1e"
                            width: 28
                        }
                    }
                }
                // 4 & 5: single clock
                AnalogClock {
                    active: false
                    anchors.fill: parent
                    anchors.margins: 8
                    faceColor: Qt.rgba(1, 1, 1, 0.92)
                    fixedDate: clc.previewDate
                    handColor: "#1c1c1e"
                    showNumbers: false
                    tickColor: "#2a2a2e"
                    visible: clc.layoutId === 4
                }
                AnalogClock {
                    active: false
                    anchors.fill: parent
                    anchors.margins: 8
                    fixedDate: clc.previewDate
                    handColor: ThemeService.isDark ? "#f2f2f7" : "#1c1c1e"
                    tickColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.48)
                    visible: clc.layoutId === 5
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: clc.names[clc.layoutId - 1]
            }
        }
        HoverHandler {
            id: clcHover
        }
        MouseArea {
            id: clcMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                board.tryAddWidget("clock", board.width / 2 - 110, board.height / 2 - 110, {
                    layout: clc.layoutId,
                    faces: WidgetsService.defaultClockFaces(clc.layoutId)
                });
            }
        }
    }

    // A row in the right-click context menu.
    component CtxRow: Rectangle {
        id: cr

        property bool danger: false
        property string label: ""

        signal triggered

        color: crHover.hovered && enabled ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        height: 34
        opacity: enabled ? 1.0 : 0.4
        scale: crMa.pressed ? ThemeService.pressScale : 1.0
        width: parent ? parent.width : 150

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: cr.danger ? "#ff6b6b" : "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            text: cr.label
        }
        HoverHandler {
            id: crHover

            enabled: cr.enabled
        }
        MouseArea {
            id: crMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: cr.enabled

            onPressed: cr.triggered()
        }
    }

    // A news-layout preview card (stage 2 of the gallery).
    component NewsLayoutCard: Rectangle {
        id: nlc

        property int layoutId: 2
        readonly property string layoutName: layoutId === 4 ? "X-Small" : (layoutId === 1 ? "Small" : (layoutId === 2 ? "Medium" : "Large"))

        border.color: ThemeService.separator
        border.width: 1
        color: nlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: nlcMa.pressed ? ThemeService.pressScale : 1.0
        width: layoutId === 1 || layoutId === 4 ? 96 : 128

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            // mini mock: hero image block + headline lines (+ side column on
            // medium/large to hint at the wider layouts)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: ThemeService.separator
                border.width: 1
                clip: true
                color: ThemeService.cardBg
                height: 72
                radius: 12
                width: nlc.layoutId === 1 || nlc.layoutId === 4 ? 60 : 100

                Rectangle {
                    anchors.fill: parent
                    color: ThemeService.secondaryLabel
                    opacity: 0.55
                    visible: nlc.layoutId === 4

                    Rectangle {
                        height: 30

                        gradient: Gradient {
                            orientation: Gradient.Vertical

                            GradientStop {
                                color: "transparent"
                                position: 0
                            }
                            GradientStop {
                                color: Qt.rgba(0, 0, 0, 0.82)
                                position: 1
                            }
                        }

                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                    }
                    Column {
                        anchors.margins: 6
                        spacing: 3

                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        Rectangle {
                            color: "#ffffff"
                            height: 3
                            radius: 1.5
                            width: parent.width
                        }
                        Rectangle {
                            color: "#ffffff"
                            height: 3
                            radius: 1.5
                            width: parent.width * 0.72
                        }
                    }
                }
                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 7
                    visible: nlc.layoutId !== 4

                    Column {
                        spacing: 4
                        width: nlc.layoutId === 1 ? parent.width : 48

                        Rectangle {
                            color: ThemeService.secondaryLabel
                            height: 24
                            opacity: 0.55
                            radius: 5
                            width: parent.width
                        }
                        Rectangle {
                            color: ThemeService.label
                            height: 4
                            opacity: 0.85
                            radius: 2
                            width: parent.width
                        }
                        Rectangle {
                            color: ThemeService.label
                            height: 4
                            opacity: 0.85
                            radius: 2
                            width: parent.width * 0.7
                        }
                        Rectangle {
                            color: ThemeService.secondaryLabel
                            height: 3
                            radius: 1.5
                            width: parent.width * 0.85
                        }
                    }
                    Column {
                        spacing: 4
                        visible: nlc.layoutId !== 1
                        width: 29

                        Repeater {
                            model: nlc.layoutId === 3 ? 4 : 3

                            delegate: Column {
                                spacing: 2

                                Rectangle {
                                    color: ThemeService.label
                                    height: 3
                                    opacity: 0.8
                                    radius: 1.5
                                    width: 29
                                }
                                Rectangle {
                                    color: ThemeService.secondaryLabel
                                    height: 3
                                    radius: 1.5
                                    width: 20
                                }
                            }
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: nlc.layoutName
            }
        }
        HoverHandler {
            id: nlcHover
        }
        MouseArea {
            id: nlcMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                let size = WidgetsService.newsSize(nlc.layoutId);
                board.tryAddWidget("news", board.width / 2 - size.nw / 2, board.height / 2 - size.nh / 2, {
                    layout: nlc.layoutId
                });
            }
        }
    }

    // The note card in the picker (notes have no layouts — one sticky preview).
    component NoteAddCard: Rectangle {
        id: nac

        border.color: ThemeService.separator
        border.width: 1
        color: nacHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: nacMa.pressed ? ThemeService.pressScale : 1.0
        width: 96

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                color: WidgetsService.palette[0]
                height: 72
                radius: 4
                width: 60

                Rectangle {   // Stickies title strip
                    color: Qt.darker(WidgetsService.palette[0], 1.10)
                    height: 10
                    radius: 4

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                }
                Column {
                    anchors.margins: 8
                    anchors.topMargin: 16
                    spacing: 4

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    Repeater {
                        model: 3

                        delegate: Rectangle {
                            required property int index

                            color: Qt.rgba(0, 0, 0, 0.30)
                            height: 3
                            radius: 1.5
                            width: parent.width * (1 - index * 0.2)
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: "Sticky"
            }
        }
        HoverHandler {
            id: nacHover
        }
        MouseArea {
            id: nacMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: board.tryAddWidget("note", board.width / 2 - 120, board.height / 2 + 60)
        }
    }

    // A reminders-layout preview card (stage 2 of the gallery).
    component RemindersLayoutCard: Rectangle {
        id: rlc

        readonly property color accent: ThemeService.accent("blue")
        property int layoutId: 2
        readonly property var names: ["Small", "Medium", "Large"]

        border.color: ThemeService.separator
        border.width: 1
        color: rlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: rlcMa.pressed ? ThemeService.pressScale : 1.0
        width: layoutId === 1 ? 96 : 128

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: ThemeService.separator
                border.width: 1
                clip: true
                color: ThemeService.cardBg
                height: rlc.layoutId === 1 ? 64 : (rlc.layoutId === 2 ? 52 : 72)
                radius: 10
                width: rlc.layoutId === 1 ? 64 : (rlc.layoutId === 2 ? 100 : 72)

                Column {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 4
                    visible: rlc.layoutId === 1

                    Row {
                        spacing: 4

                        Rectangle {
                            color: rlc.accent
                            height: 10
                            radius: 5
                            width: 10
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            text: "3"
                        }
                    }
                    Repeater {
                        model: 3

                        delegate: Row {
                            spacing: 3

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                border.color: rlc.accent
                                border.width: 1
                                color: "transparent"
                                height: 6
                                radius: 3
                                width: 6
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                color: ThemeService.separator
                                height: 3
                                radius: 1.5
                                width: 32
                            }
                        }
                    }
                }
                Row {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 7
                    visible: rlc.layoutId === 2

                    Column {
                        spacing: 3
                        width: 25

                        Rectangle {
                            color: rlc.accent
                            height: 15
                            radius: 7.5
                            width: 15

                            Text {
                                anchors.centerIn: parent
                                color: "#ffffff"
                                font.pixelSize: 8
                                text: "✓"
                            }
                        }
                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            text: "3"
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Repeater {
                            model: 3

                            delegate: Row {
                                spacing: 3

                                Rectangle {
                                    border.color: rlc.accent
                                    border.width: 1
                                    color: "transparent"
                                    height: 6
                                    radius: 3
                                    width: 6
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: ThemeService.separator
                                    height: 3
                                    radius: 1.5
                                    width: 42
                                }
                            }
                        }
                    }
                }
                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    visible: rlc.layoutId === 3

                    Row {
                        width: parent.width

                        Text {
                            color: ThemeService.label
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            text: "3"
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            color: rlc.accent
                            height: 10
                            radius: 5
                            width: 10
                        }
                    }
                    Rectangle {
                        color: ThemeService.separator
                        height: 2
                        width: parent.width
                    }
                    Repeater {
                        model: 4

                        delegate: Row {
                            spacing: 3

                            Rectangle {
                                border.color: rlc.accent
                                border.width: 1
                                color: "transparent"
                                height: 5
                                radius: 2.5
                                width: 5
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                color: ThemeService.separator
                                height: 3
                                radius: 1.5
                                width: 46
                            }
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: rlc.names[rlc.layoutId - 1]
            }
        }
        HoverHandler {
            id: rlcHover
        }
        MouseArea {
            id: rlcMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                board.tryAddWidget("reminders", board.width / 2 - 130, board.height / 2 - 100, {
                    layout: rlc.layoutId
                });
            }
        }
    }

    // A row in the widget picker's type sidebar.
    component SidebarRow: Rectangle {
        id: sbr

        property string glyph: "\uf00a"
        property string kind: "all"
        property string label: ""

        color: gallery.selType === kind ? gallery.selectedColor : (sbrHover.hovered ? gallery.subtleColor : "transparent")
        height: 34
        radius: 9
        scale: sbrMa.pressed ? ThemeService.pressScale : 1.0
        width: parent ? parent.width : 176

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeService.secondaryLabel
                font.family: ThemeService.iconFont
                font.pixelSize: 13
                text: sbr.glyph
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 13
                text: sbr.label
            }
        }
        HoverHandler {
            id: sbrHover
        }
        MouseArea {
            id: sbrMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                gallery.selType = sbr.kind;
                searchField.text = "";
            }
        }
    }
    component SpotifyAddCard: Rectangle {
        id: spotifyCard

        property int layoutId: 3
        readonly property var layoutNames: ["Small", "Medium", "Large"]

        border.color: ThemeService.separator
        border.width: 1
        color: spotifyHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: spotifyArea.pressed ? ThemeService.pressScale : 1
        width: layoutId === 1 ? 96 : (layoutId === 2 ? 134 : 150)

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: ThemeService.separator
                clip: true
                color: ThemeService.cardBg
                height: 72
                radius: 12
                width: layoutId === 1 ? 68 : (layoutId === 2 ? 104 : 122)

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        color: "#1DB954"
                        height: layoutId === 1 ? 24 : 26
                        radius: width / 2
                        width: layoutId === 1 ? 24 : 26

                        Text {
                            anchors.centerIn: parent
                            color: "#ffffff"
                            font.family: ThemeService.iconFont
                            font.pixelSize: 14
                            text: ""
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        visible: layoutId > 1

                        Rectangle {
                            color: ThemeService.label
                            height: 5
                            opacity: 0.82
                            radius: 2.5
                            width: layoutId === 2 ? 46 : 54
                        }
                        Rectangle {
                            color: ThemeService.secondaryLabel
                            height: 4
                            radius: 2
                            width: layoutId === 2 ? 32 : 38
                        }
                    }
                }
                Rectangle {
                    anchors.margins: 10
                    color: ThemeService.separator
                    height: 3
                    radius: 1.5

                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    Rectangle {
                        color: "#1DB954"
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * 0.68
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: spotifyCard.layoutNames[spotifyCard.layoutId - 1]
            }
        }
        HoverHandler {
            id: spotifyHover
        }
        MouseArea {
            id: spotifyArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onPressed: {
                let size = WidgetsService.spotifySize(spotifyCard.layoutId);
                board.tryAddWidget("spotify", board.width / 2 - size.nw / 2, board.height / 2 - size.nh / 2, {
                    layout: spotifyCard.layoutId
                });
            }
        }
    }
    component StockAddCard: Rectangle {
        id: stockCard

        property int layoutId: 1
        readonly property bool xxl: layoutId === 2

        border.color: ThemeService.separator
        border.width: 1
        color: stockHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: stockArea.pressed ? ThemeService.pressScale : 1
        width: xxl ? 176 : 128

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                clip: true
                color: ThemeService.cardBg
                height: 72
                radius: 12
                width: stockCard.xxl ? 148 : 100

                Canvas {
                    anchors.leftMargin: 10
                    anchors.rightMargin: stockCard.xxl ? 50 : 10
                    anchors.topMargin: 10
                    height: 34

                    onPaint: {
                        let ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        let values = [0.72, 0.58, 0.64, 0.45, 0.52, 0.31, 0.38, 0.22];
                        ctx.beginPath();
                        for (let i = 0; i < values.length; i++) {
                            let x = i * width / (values.length - 1);
                            let y = values[i] * height;
                            if (i === 0)
                                ctx.moveTo(x, y);
                            else
                                ctx.lineTo(x, y);
                        }
                        ctx.strokeStyle = "#30d158";
                        ctx.lineWidth = 1.7;
                        ctx.lineJoin = "round";
                        ctx.stroke();
                    }

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                }
                Rectangle {
                    anchors.leftMargin: 10
                    anchors.rightMargin: stockCard.xxl ? 50 : 10
                    color: ThemeService.separator
                    height: 1

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.verticalCenter
                    }
                }
                Row {
                    anchors.bottomMargin: 10
                    anchors.leftMargin: 10
                    anchors.rightMargin: stockCard.xxl ? 50 : 10
                    height: 14
                    spacing: 5

                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    Rectangle {
                        color: "#30d158"
                        height: 14
                        radius: 4
                        width: (parent.width - 5) / 2
                    }
                    Rectangle {
                        color: "#ff453a"
                        height: 14
                        radius: 4
                        width: (parent.width - 5) / 2
                    }
                }
                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    visible: stockCard.xxl
                    width: 34

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index

                            color: index === 0 ? "#0a84ff" : ThemeService.separator
                            height: 9
                            radius: 3
                            width: 34
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: stockCard.xxl ? "XXL" : "Large"
            }
        }
        HoverHandler {
            id: stockHover
        }
        MouseArea {
            id: stockArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onPressed: {
                let size = WidgetsService.stockSize(stockCard.layoutId);
                board.tryAddWidget("stock", board.width / 2 - size.nw / 2, board.height / 2 - size.nh / 2, {
                    layout: stockCard.layoutId
                });
            }
        }
    }

    // A weather-layout preview card (stage 2 of the gallery).
    component WeatherLayoutCard: Rectangle {
        id: wlc

        property int layoutId: 1
        readonly property var names: ["Large", "Hourly", "Conditions", "Sun"]

        border.color: ThemeService.separator
        border.width: 1
        color: wlcHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: wlcMa.pressed ? ThemeService.pressScale : 1.0
        width: 96

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                clip: true
                height: 72
                radius: 12
                width: 72

                gradient: Gradient {
                    GradientStop {
                        color: "#1a74d4"
                        position: 0.0
                    }
                    GradientStop {
                        color: "#73b7ef"
                        position: 1.0
                    }
                }

                // tiny representative content
                Text {
                    anchors.left: parent.left
                    anchors.margins: 6
                    anchors.top: parent.top
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.Light
                    text: "18°"
                }
                Text {
                    anchors.margins: 6
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: "#ffffff"
                    font.family: WeatherService.iconFont
                    font.pixelSize: 14
                    text: wlc.layoutId === 4 ? "" : "\ue30d"
                }
                // layout-specific hint
                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 5
                    visible: wlc.layoutId === 1 || wlc.layoutId === 2

                    Repeater {
                        model: 4

                        delegate: Rectangle {
                            color: Qt.rgba(1, 1, 1, 0.8)
                            height: 4
                            radius: 2
                            width: 4
                        }
                    }
                }
                Canvas {
                    anchors.fill: parent
                    anchors.margins: 10
                    visible: wlc.layoutId === 4

                    onPaint: {
                        let ctx = getContext("2d");
                        ctx.reset();
                        let w = width, h = height, hz = h * 0.7;
                        ctx.beginPath();
                        for (let i = 0; i <= 24; i++) {
                            let t = i / 24;
                            let x = t * w;
                            let y = hz - Math.sin(t * Math.PI) * h * 0.5;
                            i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
                        }
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.5);
                        ctx.lineWidth = 1.2;
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(w * 0.6, hz - Math.sin(0.6 * Math.PI) * h * 0.5, 3, 0, 2 * Math.PI);
                        ctx.fillStyle = "#ffd34d";
                        ctx.fill();
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: wlc.names[wlc.layoutId - 1]
            }
        }
        HoverHandler {
            id: wlcHover
        }
        MouseArea {
            id: wlcMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                board.tryAddWidget("weather", board.width / 2 - 130, board.height / 2 - 120, {
                    layout: wlc.layoutId
                });
            }
        }
    }
    component YoutubeAddCard: Rectangle {
        id: youtubeCard

        property int layoutId: 3
        readonly property var layoutNames: ["Small", "Medium", "Large"]

        border.color: ThemeService.separator
        border.width: 1
        color: youtubeHover.hovered ? gallery.cardHoverColor : gallery.cardColor
        height: 116
        radius: 14
        scale: youtubeArea.pressed ? ThemeService.pressScale : 1
        width: layoutId === 1 ? 96 : (layoutId === 2 ? 134 : 150)

        Behavior on scale {
            AppleSpring {
                spring: 18
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: ThemeService.separator
                clip: true
                color: ThemeService.cardBg
                height: 72
                radius: 12
                width: layoutId === 1 ? 68 : (layoutId === 2 ? 104 : 122)

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        color: "#ff0033"
                        height: layoutId === 1 ? 19 : (layoutId === 2 ? 22 : 24)
                        radius: 6
                        width: layoutId === 1 ? 26 : (layoutId === 2 ? 30 : 34)

                        Text {
                            anchors.centerIn: parent
                            color: "#ffffff"
                            font.pixelSize: 12
                            text: "▶"
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        visible: layoutId > 1

                        Rectangle {
                            color: ThemeService.label
                            height: 5
                            opacity: 0.82
                            radius: 2.5
                            width: layoutId === 2 ? 46 : 54
                        }
                        Rectangle {
                            color: ThemeService.secondaryLabel
                            height: 4
                            radius: 2
                            width: layoutId === 2 ? 32 : 38
                        }
                    }
                }
                Rectangle {
                    anchors.margins: 10
                    color: ThemeService.separator
                    height: 3
                    radius: 1.5

                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                    Rectangle {
                        color: "#ff375f"
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * 0.68
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 11
                text: youtubeCard.layoutNames[youtubeCard.layoutId - 1]
            }
        }
        HoverHandler {
            id: youtubeHover
        }
        MouseArea {
            id: youtubeArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onPressed: {
                let size = WidgetsService.youtubeSize(youtubeCard.layoutId);
                board.tryAddWidget("youtube", board.width / 2 - size.nw / 2, board.height / 2 - size.nh / 2, {
                    layout: youtubeCard.layoutId
                });
            }
        }
    }
}
