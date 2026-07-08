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

    required property int index
    required property int wid
    required property string type
    required property real nx
    required property real ny
    required property real nw
    required property real nh
    required property string payload

    property Item boardItem
    property var winRef

    readonly property var dataObj: {
        try { return JSON.parse(payload || "{}") } catch (e) { return ({}) }
    }
    readonly property bool isNote: type === "note"
    readonly property bool collapsed: isNote && dataObj.collapsed === true
    readonly property color swatch: dataObj.swatch || WidgetsService.palette[0]
    readonly property int headerH: 24
    readonly property color neutralCard: Qt.rgba(0.17, 0.19, 0.24, 0.64)

    // Content-provided appearance (clocks set these).
    readonly property var contentItem: content.item
    readonly property bool lightCard: !!(contentItem && contentItem.lightCard === true)

    x: nx
    y: ny
    width: nw
    height: collapsed ? headerH : nh
    z: index + 1

    function save(patch) { WidgetsService.setData(index, patch) }
    function bringToFront() { z = boardItem.topZ; boardItem.topZ += 1 }

    // macOS-style zoom: toggle between the note's normal size and a larger
    // "full" size. We stash the pre-zoom geometry so it restores exactly.
    readonly property bool zoomed: isNote && dataObj.zoomed === true
    function toggleZoom() {
        if (zoomed) {
            let rw = dataObj.restoreW || nw, rh = dataObj.restoreH || nh
            save({ zoomed: false })
            WidgetsService.setSize(index, rw, rh, true)
        } else {
            let bw = boardItem ? boardItem.width  : 1000
            let bh = boardItem ? boardItem.height : 800
            let zw = Math.min(560, Math.max(nw, bw * 0.5))
            let zh = Math.min(680, Math.max(nh, bh * 0.7))
            save({ zoomed: true, restoreW: nw, restoreH: nh })
            WidgetsService.setSize(index, zw, zh, true)
        }
    }
    function requestClose() {
        if (isNote && contentItem && contentItem.requestClose) contentItem.requestClose()
        else WidgetsService.removeAt(index)
    }

    HoverHandler { id: frameHover }

    Rectangle {
        x: 1; y: 5
        width: wf.width; height: wf.height
        radius: wf.isNote ? 0 : 13
        color: Qt.rgba(0, 0, 0, 0.28)
        z: -1
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: wf.isNote ? 0 : 13
        clip: true
        color: wf.isNote ? wf.swatch
             : (wf.contentItem && wf.contentItem.cardColor) ? wf.contentItem.cardColor : wf.neutralCard
        border.color: wf.lightCard ? Qt.rgba(0, 0, 0, 0.10)
                    : (wf.isNote ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.10))
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }

        // ── Content ────────────────────────────────────────────────────────
        Loader {
            id: content
            visible: !wf.collapsed
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                top: parent.top
            }
            sourceComponent: wf.type === "clock"     ? clockComp
                           : wf.type === "weather"   ? weatherComp
                           : wf.type === "reminders" ? remindersComp
                           : wf.type === "news"      ? newsComp
                           : noteComp
        }
        Component { id: noteComp;      NoteWidget      { frame: wf } }
        Component { id: clockComp;     ClockWidget     { frame: wf } }
        Component { id: weatherComp;   WeatherWidget   { frame: wf } }
        Component { id: remindersComp; RemindersWidget { frame: wf } }
        Component { id: newsComp;      NewsWidget      { frame: wf } }

        // ── Note title bar (macOS Stickies: close left, zoom + collapse
        //    right). Hover-only — the strip is hidden until you point at the
        //    note, except when collapsed (then it's the whole note) or while
        //    dragging. The first line of text shows in the bar when collapsed.
        Rectangle {
            id: header
            visible: wf.isNote && (frameHover.hovered || noteDrag.pressed || wf.collapsed)
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: wf.isNote ? wf.headerH : 0
            color: Qt.darker(wf.swatch, 1.10)

            MouseArea {
                id: noteDrag
                anchors.fill: parent
                cursorShape: Qt.OpenHandCursor
                property real grabX: 0
                property real grabY: 0
                onPressed: (m) => {
                    wf.bringToFront()
                    let p = noteDrag.mapToItem(wf.boardItem, m.x, m.y)
                    grabX = p.x - wf.x; grabY = p.y - wf.y
                }
                onPositionChanged: (m) => {
                    let p = noteDrag.mapToItem(wf.boardItem, m.x, m.y)
                    let nxx = Math.max(0, Math.min(wf.boardItem.width  - wf.width,  p.x - grabX))
                    let nyy = Math.max(0, Math.min(wf.boardItem.height - wf.height, p.y - grabY))
                    WidgetsService.setPosition(wf.index, nxx, nyy, false)
                }
                onReleased: WidgetsService.persist()
                onDoubleClicked: wf.save({ collapsed: !wf.dataObj.collapsed })
            }

            // Left: close box
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 8
                text: "✕"; font.pixelSize: 12; font.family: "SF Pro Display"
                color: closeHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                HoverHandler { id: closeHover }
                MouseArea { anchors.fill: parent; anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor; onClicked: wf.requestClose() }
            }

            // Collapsed: show the note's first line as the title.
            Text {
                visible: wf.collapsed
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 26
                anchors.right: parent.right; anchors.rightMargin: 48
                text: (wf.contentItem && wf.contentItem.firstLine) ? wf.contentItem.firstLine : ""
                elide: Text.ElideRight
                color: Qt.rgba(0, 0, 0, 0.6); font.family: "SF Pro Display"; font.pixelSize: 12
            }

            // Right: zoom (full size) + collapse (roll up to title line).
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right; anchors.rightMargin: 8
                spacing: 10
                Text {
                    text: wf.zoomed ? "⤡" : "⤢"; font.pixelSize: 12; font.family: "SF Pro Display"
                    color: zoomHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                    HoverHandler { id: zoomHover }
                    MouseArea { anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor; onClicked: wf.toggleZoom() }
                }
                Text {
                    text: wf.collapsed ? "▾" : "▴"; font.pixelSize: 12; font.family: "SF Pro Display"
                    color: collapseHover.hovered ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(0, 0, 0, 0.38)
                    HoverHandler { id: collapseHover }
                    MouseArea { anchors.fill: parent; anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wf.save({ collapsed: !wf.dataObj.collapsed }) }
                }
            }
        }

        // ── Hover chrome for non-note widgets ──────────────────────────────
        Item {
            id: hoverChrome
            visible: !wf.isNote && (frameHover.hovered || chromeDrag.pressed)
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 22

            Rectangle {
                anchors.fill: parent
                color: wf.lightCard ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.22)
            }
            MouseArea {
                id: chromeDrag
                anchors.fill: parent
                cursorShape: Qt.OpenHandCursor
                property real grabX: 0
                property real grabY: 0
                onPressed: (m) => {
                    wf.bringToFront()
                    let p = chromeDrag.mapToItem(wf.boardItem, m.x, m.y)
                    grabX = p.x - wf.x; grabY = p.y - wf.y
                }
                onPositionChanged: (m) => {
                    let p = chromeDrag.mapToItem(wf.boardItem, m.x, m.y)
                    let nxx = Math.max(0, Math.min(wf.boardItem.width  - wf.width,  p.x - grabX))
                    let nyy = Math.max(0, Math.min(wf.boardItem.height - wf.height, p.y - grabY))
                    WidgetsService.setPosition(wf.index, nxx, nyy, false)
                }
                onReleased: WidgetsService.persist()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 8
                text: "⠿"; font.pixelSize: 13; font.family: "SF Pro Display"
                color: wf.lightCard ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.55)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right; anchors.rightMargin: 8
                text: "✕"; font.pixelSize: 12; font.family: "SF Pro Display"
                color: wf.lightCard
                    ? (chromeDel.hovered ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.4))
                    : (chromeDel.hovered ? Qt.rgba(1, 1, 1, 0.9)  : Qt.rgba(1, 1, 1, 0.5))
                HoverHandler { id: chromeDel }
                MouseArea { anchors.fill: parent; anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor; onClicked: WidgetsService.removeAt(wf.index) }
            }
        }

        // ── Resize grip (hover) ────────────────────────────────────────────
        MouseArea {
            id: resizer
            visible: !wf.collapsed && (frameHover.hovered || resizer.pressed)
            width: 18; height: 18
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            cursorShape: Qt.SizeFDiagCursor
            property real startMX: 0
            property real startMY: 0
            property real startW: 0
            property real startH: 0
            property real startAspect: 1
            onPressed: (m) => {
                wf.bringToFront()
                let p = resizer.mapToItem(wf.boardItem, m.x, m.y)
                startMX = p.x; startMY = p.y; startW = wf.width; startH = wf.height
                startAspect = startH > 0 ? startW / startH : 1
            }
            onPositionChanged: (m) => {
                let p = resizer.mapToItem(wf.boardItem, m.x, m.y)
                let dw = p.x - startMX, dh = p.y - startMY
                let nww = Math.max(110, startW + dw)
                let nhh = Math.max(80, startH + dh)
                // Hold Shift to keep the widget's aspect ratio (drive by the
                // dominant drag axis, then re-derive the other side).
                if (m.modifiers & Qt.ShiftModifier) {
                    if (Math.abs(dw) >= Math.abs(dh)) { nww = Math.max(110, startW + dw); nhh = nww / startAspect }
                    else { nhh = Math.max(80, startH + dh); nww = nhh * startAspect }
                    if (nww < 110) { nww = 110; nhh = nww / startAspect }
                    if (nhh < 80)  { nhh = 80;  nww = nhh * startAspect }
                }
                WidgetsService.setSize(wf.index, nww, nhh, false)
            }
            onReleased: {
                if (wf.zoomed) wf.save({ zoomed: false })
                WidgetsService.persist()
            }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    let ctx = getContext("2d"); ctx.reset()
                    ctx.strokeStyle = wf.lightCard ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.35)
                    ctx.lineWidth = 1.2
                    for (let o = 5; o <= 13; o += 4) {
                        ctx.beginPath(); ctx.moveTo(width - o, height - 3); ctx.lineTo(width - 3, height - o); ctx.stroke()
                    }
                }
            }
        }

        // ── Right-click → context menu (left clicks pass through) ──────────
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (m) => {
                let p = mapToItem(wf.boardItem, m.x, m.y)
                wf.boardItem.openContext(wf.index, p.x, p.y)
            }
        }
    }
}
