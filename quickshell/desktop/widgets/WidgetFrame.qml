import QtQuick

// Generic chrome for one placed widget.
//   • Notes get a macOS Stickies title bar (close left; zoom + collapse right)
//     that's hidden until you hover the note — or always shown when collapsed.
//   • Other widgets are chromeless; hovering reveals a translucent top strip
//     (drag handle + delete) so the content (clock face, etc.) stays clean.
//   • Right-click anywhere opens the board context menu (Edit / Delete).
//     For notes, Edit opens the colour + font editor (NoteEditor).
// Geometry binds to the model roles so it survives middle-of-list deletes.
// See [[quickshell-hyprland-quirks]].
Item {
    id: wf

    property Item boardItem
    readonly property real cardRadius: isNote ? 0 : (isXSmallNews ? 26 : 13)
    readonly property bool collapsed: isNote && dataObj.collapsed === true

    // Content-provided appearance (clocks set these).
    readonly property var contentItem: content.item
    readonly property var dataObj: {
        try {
            return JSON.parse(payload || "{}");
        } catch (e) {
            return ({});
        }
    }
    readonly property int headerH: 24

    // ── Edit mode (grid widgets only) ───────────────────────────────────
    // iOS jiggle: a gentle rotation wobble, phase-varied per widget so the
    // board doesn't oscillate in lockstep. The amplitude shrinks with widget
    // size — the wobble is a rotation, so on a big card the same angle throws
    // the corners (and the delete badge) much further.
    readonly property bool inEditMode: !isNote && boardItem && boardItem.editMode === true
    required property int index
    readonly property bool isNote: type === "note"
    readonly property bool isXSmallNews: type === "news" && Number(dataObj.layout || 0) === 4
    readonly property real jigAmp: 1.1 * Math.min(1, 260 / Math.max(nw, nh))
    readonly property bool jigEnabled: inEditMode && !editDrag.pressed
    property real jigTarget: 0
    readonly property bool lightCard: !!(contentItem && contentItem.lightCard === true)
    readonly property color neutralCard: Qt.rgba(0.17, 0.19, 0.24, 0.64)
    required property real nh
    required property real nw
    required property real nx
    required property real ny
    required property string payload
    readonly property bool positionTracking: noteDrag.pressed || editDrag.pressed
    readonly property bool sizeTracking: resizer.pressed
    readonly property color swatch: dataObj.swatch || WidgetsService.palette[0]
    required property string type
    required property int wid
    property var winRef

    // macOS-style zoom: toggle between the note's normal size and a larger
    // "full" size. We stash the pre-zoom geometry so it restores exactly.
    readonly property bool zoomed: isNote && dataObj.zoomed === true

    function bringToFront() {
        if (isNote) {
            z = boardItem.topNoteZ;
            boardItem.topNoteZ += 1;
        } else {
            z = Math.min(boardItem.topZ, 49999);
            boardItem.topZ += 1;
        }
    }
    function requestClose() {
        if (isNote && contentItem && contentItem.requestClose)
            contentItem.requestClose();
        else
            WidgetsService.removeAt(index);
    }
    function rubberBand(value, lower, upper, dimension) {
        let overshoot = value < lower ? value - lower : (value > upper ? value - upper : 0);
        if (overshoot === 0)
            return value;
        let resisted = (overshoot * dimension * 0.55) / (dimension + 0.55 * Math.abs(overshoot));
        return (value < lower ? lower : upper) + resisted;
    }
    function save(patch) {
        WidgetsService.setData(index, patch);
    }
    function toggleZoom() {
        if (zoomed) {
            let rw = dataObj.restoreW || nw, rh = dataObj.restoreH || nh;
            save({
                zoomed: false
            });
            WidgetsService.setSize(index, rw, rh, true);
        } else {
            let bw = boardItem ? boardItem.width : 1000;
            let bh = boardItem ? boardItem.height : 800;
            let zw = Math.min(560, Math.max(nw, bw * 0.5));
            let zh = Math.min(680, Math.max(nh, bh * 0.7));
            save({
                zoomed: true,
                restoreW: nw,
                restoreH: nh
            });
            WidgetsService.setSize(index, zw, zh, true);
        }
    }

    height: collapsed ? headerH : nh
    rotation: jigEnabled ? jigTarget : 0
    width: nw
    x: nx
    y: ny
    // Two z bands: grid widgets live in [1, 50000), sticky notes in
    // [50000, …) — notes always float above every widget (board overlays
    // like the toolbar/gallery sit at 100000+).
    z: isNote ? 50000 + index : index + 1

    Behavior on height {
        enabled: !wf.sizeTracking

        AppleSpring {
            epsilon: 0.15
            spring: 18
        }
    }
    Behavior on rotation {
        AppleSpring {
            id: jigMotion

            damping: ThemeService.momentumDamping
            epsilon: 0.035
            spring: 22

            onRunningChanged: if (!running && wf.jigEnabled)
                Qt.callLater(() => wf.jigTarget = wf.jigTarget > 0 ? -wf.jigAmp : wf.jigAmp)
        }
    }
    Behavior on width {
        enabled: !wf.sizeTracking

        AppleSpring {
            epsilon: 0.15
            spring: 18
        }
    }
    Behavior on x {
        enabled: !wf.positionTracking

        AppleSpring {
            epsilon: 0.15
            spring: 18
        }
    }
    Behavior on y {
        enabled: !wf.positionTracking

        AppleSpring {
            epsilon: 0.15
            spring: 18
        }
    }

    onJigEnabledChanged: jigTarget = jigEnabled ? ((wid % 2 === 0) ? jigAmp : -jigAmp) : 0

    HoverHandler {
        id: frameHover
    }
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.28)
        height: wf.height
        radius: wf.cardRadius
        width: wf.width
        x: 1
        y: 5
        z: -1
    }
    Rectangle {
        id: card

        anchors.fill: parent
        border.color: wf.isXSmallNews ? "transparent" : wf.lightCard ? Qt.rgba(0, 0, 0, 0.10) : (wf.isNote ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.10))
        border.width: wf.isXSmallNews ? 0 : 1
        clip: true
        color: wf.isNote ? wf.swatch : (wf.contentItem && wf.contentItem.cardColor) ? wf.contentItem.cardColor : wf.neutralCard
        radius: wf.cardRadius

        // ── Content ────────────────────────────────────────────────────────
        Loader {
            id: content

            visible: !wf.collapsed

            // Supply the compatibility frame before component bindings first
            // evaluate. A post-load assignment makes downloader properties
            // briefly bind to an empty payload and can produce a binding loop.
            Component.onCompleted: content.setSource(
                WidgetsService.componentSource(wf.type), { "frame": wf })

            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                top: parent.top
            }
        }

        // ── Note title bar (macOS Stickies: close left, zoom + collapse
        //    right). Hover-only — the strip is hidden until you point at the
        //    note, except when collapsed (then it's the whole note) or while
        //    dragging. The first line of text shows in the bar when collapsed.
        Rectangle {
            id: header

            color: Qt.darker(wf.swatch, 1.10)
            height: wf.isNote ? wf.headerH : 0
            visible: wf.isNote && (frameHover.hovered || noteDrag.pressed || wf.collapsed)

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            MouseArea {
                id: noteDrag

                property real grabX: 0
                property real grabY: 0

                anchors.fill: parent
                cursorShape: Qt.OpenHandCursor

                onPositionChanged: m => {
                    let p = noteDrag.mapToItem(wf.boardItem, m.x, m.y);
                    let nxx = wf.rubberBand(p.x - grabX, 0, Math.max(0, wf.boardItem.width - wf.width), wf.boardItem.width);
                    let nyy = wf.rubberBand(p.y - grabY, 0, Math.max(0, wf.boardItem.height - wf.height), wf.boardItem.height);
                    WidgetsService.setPosition(wf.index, nxx, nyy, false);
                }
                onPressed: m => {
                    wf.bringToFront();
                    let p = noteDrag.mapToItem(wf.boardItem, m.x, m.y);
                    grabX = p.x - wf.x;
                    grabY = p.y - wf.y;
                }
                onReleased: {
                    WidgetsService.setPosition(wf.index, Math.max(0, Math.min(wf.boardItem.width - wf.width, wf.x)), Math.max(0, Math.min(wf.boardItem.height - wf.height, wf.y)), false);
                    WidgetsService.persist();
                }
            }

            // Left: close box
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: closeHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                scale: noteCloseMa.pressed ? ThemeService.pressScale : 1.0
                text: "✕"

                Behavior on scale {
                    AppleSpring {
                        spring: 18
                    }
                }

                HoverHandler {
                    id: closeHover
                }
                MouseArea {
                    id: noteCloseMa

                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: Qt.PointingHandCursor

                    onClicked: wf.requestClose()
                }
            }

            // Collapsed: show the note's first line as the title.
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.right: parent.right
                anchors.rightMargin: 48
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(0, 0, 0, 0.6)
                elide: Text.ElideRight
                font.family: "SF Pro Display"
                font.pixelSize: 12
                text: (wf.contentItem && wf.contentItem.firstLine) ? wf.contentItem.firstLine : ""
                visible: wf.collapsed
            }

            // Right: zoom (full size) + collapse (roll up to title line).
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    color: zoomHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    scale: zoomMa.pressed ? ThemeService.pressScale : 1.0
                    text: wf.zoomed ? "⤡" : "⤢"

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    HoverHandler {
                        id: zoomHover
                    }
                    MouseArea {
                        id: zoomMa

                        anchors.fill: parent
                        anchors.margins: -5
                        cursorShape: Qt.PointingHandCursor

                        onClicked: wf.toggleZoom()
                    }
                }
                Text {
                    color: collapseHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    scale: collapseMa.pressed ? ThemeService.pressScale : 1.0
                    text: wf.collapsed ? "▾" : "▴"

                    Behavior on scale {
                        AppleSpring {
                            spring: 18
                        }
                    }

                    HoverHandler {
                        id: collapseHover
                    }
                    MouseArea {
                        id: collapseMa

                        anchors.fill: parent
                        anchors.margins: -5
                        cursorShape: Qt.PointingHandCursor

                        onClicked: wf.save({
                            collapsed: !wf.dataObj.collapsed
                        })
                    }
                }
            }
        }

        // ── Resize grip (hover) — sticky notes only; everything else is
        //    fixed to the board grid ─────────────────────────────────────────
        MouseArea {
            id: resizer

            property real startH: 0
            property real startMX: 0
            property real startMY: 0
            property real startW: 0

            anchors.bottom: parent.bottom
            anchors.right: parent.right
            cursorShape: Qt.SizeFDiagCursor
            height: 18
            visible: wf.isNote && !wf.collapsed && (frameHover.hovered || resizer.pressed)
            width: 18

            onPositionChanged: m => {
                let p = resizer.mapToItem(wf.boardItem, m.x, m.y);
                let dw = p.x - startMX, dh = p.y - startMY;
                let nww = wf.rubberBand(startW + dw, 110, Math.max(110, wf.boardItem.width - wf.x), wf.boardItem.width);
                let nhh = wf.rubberBand(startH + dh, 80, Math.max(80, wf.boardItem.height - wf.y), wf.boardItem.height);
                WidgetsService.setSize(wf.index, nww, nhh, false);
            }
            onPressed: m => {
                wf.bringToFront();
                let p = resizer.mapToItem(wf.boardItem, m.x, m.y);
                startMX = p.x;
                startMY = p.y;
                startW = wf.width;
                startH = wf.height;
            }
            onReleased: {
                if (wf.zoomed)
                    wf.save({
                        zoomed: false
                    });
                WidgetsService.setSize(wf.index, Math.max(110, Math.min(wf.boardItem.width - wf.x, wf.width)), Math.max(80, Math.min(wf.boardItem.height - wf.y, wf.height)), false);
                WidgetsService.persist();
            }

            Canvas {
                anchors.fill: parent

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = wf.lightCard ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.35);
                    ctx.lineWidth = 1.2;
                    for (let o = 5; o <= 13; o += 4) {
                        ctx.beginPath();
                        ctx.moveTo(width - o, height - 3);
                        ctx.lineTo(width - 3, height - o);
                        ctx.stroke();
                    }
                }
            }
        }

        // ── Right-click → context menu (left clicks pass through) ──────────
        MouseArea {
            acceptedButtons: Qt.RightButton
            anchors.fill: parent

            onClicked: m => {
                let p = mapToItem(wf.boardItem, m.x, m.y);
                wf.boardItem.openContext(wf.index, p.x, p.y);
            }
        }

        // ── Edit-mode drag: grab anywhere to move. A translucent preview on
        //    the board shows the snapped drop slot; dropping on a free slot
        //    places the widget there, anywhere else springs it back ──────────
        MouseArea {
            id: editDrag

            property real grabX: 0
            property real grabY: 0
            property bool moved: false
            property real origX: 0
            property real origY: 0

            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            visible: wf.inEditMode

            onPositionChanged: m => {
                moved = true;
                let p = editDrag.mapToItem(wf.boardItem, m.x, m.y);
                WidgetsService.setPosition(wf.index, wf.rubberBand(p.x - grabX, 0, Math.max(0, wf.boardItem.width - wf.width), wf.boardItem.width), wf.rubberBand(p.y - grabY, 0, Math.max(0, wf.boardItem.height - wf.height), wf.boardItem.height), false);
                wf.boardItem.updateDragPreview(wf.index, wf.x + wf.width / 2, wf.y + wf.height / 2);
            }
            onPressed: m => {
                wf.bringToFront();
                let p = editDrag.mapToItem(wf.boardItem, m.x, m.y);
                grabX = p.x - wf.x;
                grabY = p.y - wf.y;
                origX = wf.x;
                origY = wf.y;
                moved = false;
            }
            onReleased: {
                if (moved)
                    wf.boardItem.dropWidgetAt(wf.index, wf.x + wf.width / 2, wf.y + wf.height / 2, origX, origY);
                else
                    wf.boardItem.endDragPreview();
            }
        }
    }

    // ── Edit-mode delete badge (top-left, iOS jiggle style) ────────────────
    // Only for grid widgets; notes keep their own Stickies title-bar close box.
    Rectangle {
        id: deleteBadge

        border.color: Qt.rgba(1, 1, 1, 0.35)
        border.width: 1
        color: delHover.hovered ? "#FF453A" : "#FF3B30"
        height: 26
        radius: 13
        scale: delMa.pressed ? ThemeService.pressScale : 1.0
        visible: wf.inEditMode
        width: 26
        x: -9
        y: -9
        z: 10

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
            text: "✕"
        }
        HoverHandler {
            id: delHover
        }
        MouseArea {
            id: delMa

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: WidgetsService.removeAt(wf.index)
        }
    }
}
