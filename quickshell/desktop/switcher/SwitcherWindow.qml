import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

PanelWindow {
    id: win

    // ── Public state ─────────────────────────────────────────────────────
    property bool show: false
    property int selectedIndex: 0
    signal closeRequested
    signal confirmRequested

    // Class → icon-theme name. Handles three cases:
    //   1. Known Wine apps whose .exe class has no matching theme icon
    //      (Ableton in a virtual desktop, KakaoTalk's Wine-extracted hash).
    //   2. Qt apps that append `_PID_RANDOM` to their wmClass per launch
    //      (transmission e.g. "com.transmissionbt.transmission_66306_27265476")
    //      — strip the suffix.
    //   3. Otherwise fall back to the original class.
    function _iconNameFor(cls) {
        if (!cls) return ""
        let lc = cls.toLowerCase()
        if (lc === "explorer.exe") return "ableton"
        if (lc === "kakaotalk.exe") return "KakaoTalk"
        if (lc === "code") return "visual-studio-code"
        // Spotify reports class "Spotify" but its theme icon is "spotify-client".
        if (lc === "spotify") return "spotify-client"
        // Strip Qt instance suffix (transmission etc.).
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        let base = m ? m[1] : cls
        let baseLc = base.toLowerCase()
        if (baseLc === "com.transmissionbt.transmission") return "transmission"
        return base
    }

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            _surfaceVisible = true
            unmapTimer.stop()
            // Defer focus so the window is mapped before we ask for it.
            focusTimer.restart()
        } else {
            keyCatcher.focus = false
            unmapTimer.restart()
        }
    }

    Timer {
        id: unmapTimer
        interval: 180
        onTriggered: win._surfaceVisible = false
    }
    Timer {
        id: focusTimer
        interval: 1
        onTriggered: keyCatcher.forceActiveFocus()
    }

    // ── Layer / placement ───────────────────────────────────────────────
    WlrLayershell.namespace: "qs-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive keyboard focus only while open — drop to None on close so the
    // layer-shell `keyboard_interactivity` doesn't keep claiming focus during
    // the unmap-animation window. Without this, focuswindow dispatched right
    // after Super-release lands while the layer still owns keyboard focus,
    // and the target window only actually gets focus after the layer unmaps
    // (~180ms later). The user has to "wiggle the cursor" to trigger
    // follow_mouse to retake focus.
    WlrLayershell.keyboardFocus: win.show
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Hyprland focus-grab — pins keyboard input to this layer regardless of
    // what other layers/windows are doing on the same screen.
    HyprlandFocusGrab {
        windows: [win]
        active: win.show
    }

    readonly property bool dark: ThemeService.isDark
    readonly property var wins: WindowsService.windows
    readonly property int count: wins.length

    // ── Sizing ──────────────────────────────────────────────────────────
    readonly property int iconSize: 80
    readonly property int cellW:    iconSize + 28
    readonly property int cellH:    iconSize + 28
    readonly property int hPad:     20
    readonly property int vPad:     56
    readonly property int maxCardW: Math.min(1280, screen ? screen.width - 80 : 1200)

    // Up to 9 icons per row; overflow wraps onto new rows below.
    readonly property int maxPerRow: 9
    readonly property int columns:   Math.min(count, maxPerRow)
    readonly property int rowCount:  Math.ceil(count / maxPerRow)
    readonly property int cardW: Math.max(280, Math.min(maxCardW, columns * cellW + hPad * 2))
    readonly property int cardH: Math.max(1, rowCount) * cellH + vPad

    // Emitted when the selection moves due to user input (Tab / Shift+Tab /
    // arrow keys / global shortcut). Lets the controlling Scope distinguish
    // explicit navigation from a programmatic selection assignment when
    // fresh MRU data arrives.
    signal navigated

    // ── Cycling helpers ──────────────────────────────────────────────────
    function next() {
        if (count === 0) return
        selectedIndex = (selectedIndex + 1) % count
        navigated()
    }
    function prev() {
        if (count === 0) return
        selectedIndex = (selectedIndex - 1 + count) % count
        navigated()
    }
    function confirm() {
        if (count === 0) return
        let w = wins[Math.max(0, Math.min(selectedIndex, count - 1))]
        if (w && w.address) WindowsService.focusByAddress(w.address)
    }

    // ── Keyboard input — handled directly here, no submap needed ─────────
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        // Tab / Shift+Tab: advance / back. Catch even with Super held.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Tab) {
                if (event.modifiers & Qt.ShiftModifier) win.prev()
                else                                    win.next()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                win.closeRequested()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                win.confirmRequested()
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                win.prev(); event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                win.next(); event.accepted = true
            }
        }
        // Super (Meta) release → confirm. macOS Cmd+Tab semantics.
        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Super_L
                || event.key === Qt.Key_Super_R
                || event.key === Qt.Key_Meta) {
                win.confirmRequested()
                event.accepted = true
            }
        }
    }

    // ── UI ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: win.cardW
        height: win.cardH
        radius: 22

        color: dark ? Qt.rgba(28/255, 28/255, 32/255, 0.78)
                    : Qt.rgba(245/255, 245/255, 247/255, 0.78)
        border.color: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.13)
        border.width: 1

        opacity: win.show ? 1.0 : 0.0
        scale:   win.show ? 1.0 : 0.92
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 90;  easing.type: Easing.OutQuad } }
        Behavior on scale   { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        // Selected app title
        Text {
            id: titleLabel
            readonly property bool empty: win.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: empty ? undefined : parent.top
            anchors.topMargin: empty ? 0 : 14
            anchors.verticalCenter: empty ? parent.verticalCenter : undefined
            width: parent.width - 32
            text: {
                if (empty) return "No windows"
                let w = win.wins[Math.max(0, Math.min(win.selectedIndex, win.count - 1))]
                if (!w) return ""
                return w.title || w.class || ""
            }
            color: dark ? "#ffffff" : "#1a1a1a"
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        // Icon grid — up to win.maxPerRow icons per row, wrapping onto new
        // rows below. The card grows in height and stays centered via its own
        // anchors.centerIn. Each row is centered so a partial last row stays
        // balanced under the full rows above it.
        Column {
            id: iconGrid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: win.columns * win.cellW
            spacing: 0

            Repeater {
                model: win.rowCount

                // One row of cells.
                Item {
                    id: gridRow
                    required property int index
                    width: iconGrid.width
                    height: win.cellH
                    readonly property int startIdx: index * win.maxPerRow
                    readonly property int rowLen: Math.min(win.maxPerRow, win.count - startIdx)

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0

                        Repeater {
                            model: gridRow.rowLen

                            Item {
                                id: cell
                                required property int index
                                readonly property int globalIndex: gridRow.startIdx + index
                                readonly property var winData: win.wins[globalIndex]
                                width: win.cellW
                                height: win.cellH

                                readonly property bool selected: win.selectedIndex === globalIndex

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: 14
                                    color: cell.selected
                                        ? (dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10))
                                        : "transparent"
                                    border.color: cell.selected
                                        ? (dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.22))
                                        : "transparent"
                                    border.width: cell.selected ? 1 : 0

                                    Behavior on color        { ColorAnimation { duration: 110 } }
                                    Behavior on border.color { ColorAnimation { duration: 110 } }
                                }

                                Image {
                                    id: iconImg
                                    anchors.centerIn: parent
                                    width: win.iconSize
                                    height: win.iconSize
                                    sourceSize.width: win.iconSize * 2
                                    sourceSize.height: win.iconSize * 2
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    source: cell.winData && cell.winData.class
                                        ? "image://icon/" + win._iconNameFor(cell.winData.class)
                                        : ""

                                    onStatusChanged: {
                                        if (status === Image.Error) {
                                            // Try the original class as a fallback before
                                            // showing the generic exec icon.
                                            let orig = cell.winData.class
                                            let mapped = win._iconNameFor(orig)
                                            if (source.toString().endsWith(mapped) && mapped !== orig.toLowerCase())
                                                source = "image://icon/" + orig.toLowerCase()
                                            else if (source.toString().endsWith(orig.toLowerCase()))
                                                source = "image://icon/" + orig
                                            else
                                                source = "image://icon/application-x-executable"
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onPositionChanged: win.selectedIndex = cell.globalIndex
                                    onClicked: {
                                        win.selectedIndex = cell.globalIndex
                                        win.confirmRequested()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Click outside the card → cancel
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: win.closeRequested()
    }
}
