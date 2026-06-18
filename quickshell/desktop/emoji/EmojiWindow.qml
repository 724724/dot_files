import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import "kinetic.js" as Kinetic

// macOS-style emoji picker (Character Viewer): "Describe an Emoji" search on top,
// a 6-column emoji grid, and a category bar at the bottom. When an app window is
// focused it appears as a popover with a tail near the mouse pointer (Wayland
// can't expose another app's text caret, so the pointer is the anchor); on the
// bare desktop it appears centred. Picking an emoji types it into the focused
// field via EmojiService (wtype) and closes.
PanelWindow {
    id: win

    property bool show: false
    signal closeRequested

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    readonly property bool dark: ThemeService.isDark
    property string query: queryField.text
    property string activeCat: "recents"

    // ── Placement ────────────────────────────────────────────────────────────
    // popover = anchored to the pointer with a tail; otherwise centred.
    property bool popover: false
    property real anchorX: 0          // pointer, in the screen's logical coords
    property real anchorY: 0
    readonly property int cardW: 372
    readonly property int cardH: 452
    readonly property int arrowH: 9
    readonly property int edge: 8
    readonly property real scrW: win.screen ? win.screen.width : 1920
    readonly property real scrH: win.screen ? win.screen.height : 1080

    // Prefer above the pointer; flip below when there isn't room.
    readonly property bool placeBelow: popover && (anchorY - cardH - arrowH - 6 < edge)
    readonly property real cardX: popover
        ? Math.max(edge, Math.min(scrW - cardW - edge, anchorX - cardW / 2))
        : (scrW - cardW) / 2
    readonly property real cardY: popover
        ? (placeBelow ? anchorY + arrowH + 6 : anchorY - cardH - arrowH - 6)
        : Math.max(80, Math.round(scrH * 0.18))
    readonly property real arrowX: Math.max(18, Math.min(cardW - 18, anchorX - cardX))
    readonly property color cardColor: ThemeService.bg

    // Card fades in only once placement is computed (avoids a visible jump from
    // the default position to the pointer popover).
    property bool ready: false

    onShowChanged: {
        if (show) {
            win.ready = false
            win.popover = false
            queryField.text = ""
            win.activeCat = EmojiService.recents.length > 0 ? "recents" : "smileys"
            grid.contentY = 0
            unmapTimer.stop()
            let m = Hyprland.focusedMonitor      // default screen; refined by posProc
            if (m && m.screen) win.screen = m.screen
            _surfaceVisible = true               // map now; position async
            queryField.forceActiveFocus()
            posProc.running = true
            showFallback.restart()
        } else {
            posProc.running = false
            showFallback.stop()
            unmapTimer.restart()
        }
    }
    function _applyPos(text) {
        showFallback.stop()
        try {
            let d = JSON.parse(text)
            let cx = d.cursor.x, cy = d.cursor.y
            let mon = null
            let mons = d.monitors || []
            for (let i = 0; i < mons.length; i++) {
                let m = mons[i]
                let odd = (m.transform % 2) === 1            // 90°/270° swap w/h
                let lw = (odd ? m.height : m.width) / m.scale
                let lh = (odd ? m.width : m.height) / m.scale
                if (cx >= m.x && cx < m.x + lw && cy >= m.y && cy < m.y + lh) {
                    mon = { name: m.name, x: m.x, y: m.y }; break
                }
            }
            if (mon) {
                for (let s = 0; s < Quickshell.screens.length; s++)
                    if (Quickshell.screens[s].name === mon.name) { win.screen = Quickshell.screens[s]; break }
                win.anchorX = cx - mon.x
                win.anchorY = cy - mon.y
            } else {
                let fm = Hyprland.focusedMonitor
                if (fm && fm.screen) win.screen = fm.screen
            }
            // Popover only when a real app window holds focus (proxy for "you're
            // working in something"); on the bare desktop, centre it.
            win.popover = !!(mon && d.window && d.window.address)
        } catch (e) {
            win.popover = false
        }
        win.ready = true
    }

    Process {
        id: posProc
        command: ["bash", "-c",
            "printf '{\"cursor\":%s,\"window\":%s,\"monitors\":%s}' "
          + "\"$(hyprctl -j cursorpos)\" \"$(hyprctl -j activewindow)\" \"$(hyprctl -j monitors)\""]
        stdout: StdioCollector { id: posOut; onStreamFinished: win._applyPos(posOut.text) }
    }
    // If hyprctl is slow/unavailable, reveal centred rather than stay hidden.
    Timer {
        id: showFallback
        interval: 280
        onTriggered: { win.popover = false; win.ready = true }
    }
    Timer { id: unmapTimer; interval: 160; onTriggered: win._surfaceVisible = false }

    WlrLayershell.namespace: "qs-emoji"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // The set of emoji chars shown in the grid right now.
    readonly property var gridChars: {
        if (win.query.trim()) return EmojiService.search(win.query).map(e => e[0])
        if (win.activeCat === "recents") return EmojiService.recents
        let cats = EmojiService.categories
        for (let i = 0; i < cats.length; i++)
            if (cats[i].key === win.activeCat) return cats[i].emojis.map(e => e[0])
        return []
    }
    // Recents (🕘) first, then the 8 catalogue categories.
    readonly property var tabs: {
        let t = [{ key: "recents", icon: "🕘" }]
        let cats = EmojiService.categories
        for (let i = 0; i < cats.length; i++) t.push({ key: cats[i].key, icon: cats[i].icon })
        return t
    }

    function pick(ch) {
        if (!ch) return
        EmojiService.use(ch)
        win.closeRequested()
    }

    // ── Popover tail (drawn outside the clipped card) ────────────────────────
    Shape {
        id: arrow
        visible: win.popover
        width: 22; height: win.arrowH
        x: Math.round(win.cardX + win.arrowX - width / 2)
        y: win.placeBelow ? Math.round(win.cardY - win.arrowH) : Math.round(win.cardY + win.cardH)
        opacity: card.opacity
        antialiasing: true
        ShapePath {
            fillColor: win.cardColor
            strokeWidth: 0
            startX: 0; startY: win.placeBelow ? arrow.height : 0
            PathLine { x: arrow.width / 2; y: win.placeBelow ? 0 : arrow.height }
            PathLine { x: arrow.width; y: win.placeBelow ? arrow.height : 0 }
        }
    }

    // ── Card ────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        width: win.cardW
        height: win.cardH
        x: win.cardX
        y: win.cardY
        radius: 16
        clip: true
        color: win.cardColor
        border.color: ThemeService.stroke
        border.width: 1

        opacity: (win.show && win.ready) ? 1.0 : 0.0
        scale: (win.show && win.ready) ? 1.0 : 0.96
        transformOrigin: win.popover ? (win.placeBelow ? Item.Top : Item.Bottom) : Item.Top
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

        // Subtle macOS-like glow toward the bottom.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: win.dark ? Qt.rgba(0.30, 0.45, 0.70, 0.10)
                                                              : Qt.rgba(0.55, 0.70, 0.95, 0.16) }
            }
        }

        // ── Search row (top) ─────────────────────────────────────────────────
        Rectangle {
            id: searchBox
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.topMargin: 12
            height: 34
            radius: 9
            color: win.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
            border.color: queryField.activeFocus ? Qt.rgba(0.30, 0.52, 0.95, 0.65)
                                                  : (win.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
            border.width: 1

            Text {
                id: searchIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 10
                text: "🔍"; font.pixelSize: 12; opacity: 0.6
            }
            TextField {
                id: queryField
                anchors.left: searchIcon.right; anchors.leftMargin: 8
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: win.dark ? "#ffffff" : "#1a1a1a"
                placeholderText: "Describe an Emoji"
                placeholderTextColor: win.dark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(0, 0, 0, 0.38)
                font.family: "SF Pro Display"
                font.pixelSize: 14
                selectByMouse: true

                Keys.onEscapePressed: win.closeRequested()
                Keys.onReturnPressed: win.pick(win.gridChars.length > 0 ? win.gridChars[0] : "")
                Keys.onEnterPressed: win.pick(win.gridChars.length > 0 ? win.gridChars[0] : "")
            }
        }

        // ── Emoji grid ───────────────────────────────────────────────────────
        GridView {
            id: grid
            anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: catbar.top }
            anchors.leftMargin: 8; anchors.rightMargin: 4
            anchors.topMargin: 8; anchors.bottomMargin: 4
            clip: true
            cellWidth: Math.floor((width - 4) / 5)
            cellHeight: cellWidth
            model: win.gridChars
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 6000
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Kinetic scroll shared via kinetic.js (touchpad momentum, crisp mouse).
            property var _ks: ({})
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (ev) => {
                    glide.stop()
                    if (Kinetic.onWheel(grid, ev, grid._ks, { gain: grid.cellHeight }))
                        endTimer.restart()
                }
            }
            Timer {
                id: endTimer
                interval: 70
                onTriggered: {
                    let g = Kinetic.fling(grid, grid._ks, {})
                    if (g) { glide.from = g.from; glide.to = g.to; glide.duration = g.duration; glide.restart() }
                }
            }
            NumberAnimation { id: glide; target: grid; property: "contentY"; easing.type: Easing.OutCubic }

            Text {
                anchors.centerIn: parent
                visible: grid.count === 0
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: win.query.trim() ? "No emoji found"
                    : (win.activeCat === "recents" ? "Recently used emoji will appear here" : "")
                color: win.dark ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(0, 0, 0, 0.4)
                font.family: "SF Pro Display"; font.pixelSize: 13
            }

            delegate: Item {
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 6; height: parent.height - 6
                    radius: 9
                    color: cellHover.hovered ? (win.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                                             : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    // Scale with the cell so the glyphs stay large and fill it.
                    font.pixelSize: Math.round(grid.cellWidth * 0.58)
                    // Match the category tabs (and ~/.config/fontconfig) — Apple
                    // emoji. Hardcoding Noto here was bypassing the fontconfig
                    // fallback that the rest of the UI uses.
                    font.family: "Apple Color Emoji"
                }
                HoverHandler { id: cellHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.pick(parent.modelData)
                }
            }
        }

        // ── Category bar ─────────────────────────────────────────────────────
        Rectangle {
            id: catbar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 40
            color: win.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)

            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 1
                color: win.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
            }

            Row {
                anchors.centerIn: parent
                spacing: 0
                Repeater {
                    model: win.tabs
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: !win.query.trim() && win.activeCat === modelData.key
                        width: 34; height: 30; radius: 7
                        color: active ? (win.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                             : (tabHover.hovered ? (win.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)) : "transparent")
                        Text { anchors.centerIn: parent; text: modelData.icon; font.pixelSize: 16
                               opacity: active ? 1.0 : 0.85 }
                        HoverHandler { id: tabHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { queryField.text = ""; win.activeCat = modelData.key; grid.contentY = 0 }
                        }
                    }
                }
            }
        }
    }

    // Click-outside dismisses.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: win.closeRequested()
    }
}
