import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import Qt5Compat.GraphicalEffects

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
        if (lc === "kakaotalk.exe") {
            // Wine app: its themed icon is a hash name from the .desktop entry,
            // so resolve it live; fall back to the known name if desktop
            // entries aren't loaded yet.
            let de = DesktopEntries.heuristicLookup("kakaotalk.exe")
            return de && de.icon ? de.icon : "DDB7_KakaoTalk.0"
        }
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
    property bool _presented: false
    property bool _sessionActive: false
    property var _sessionWins: []
    property bool _dismissing: false
    property var _frozenWins: []
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            _presented = false
            if (!_sessionActive) prepareOpen()
            _dismissing = false
            _frozenWins = []
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            _surfaceVisible = true
            revealTimer.restart()
        } else {
            revealTimer.stop()
            _presented = false
            keyCatcher.focus = false
        }
    }

    Timer {
        id: revealTimer
        interval: 16
        onTriggered: {
            if (!win.show) return
            win._presented = true
            keyCatcher.forceActiveFocus()
        }
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
    mask: show ? null : closedRegion
    Region { id: closedRegion }

    // Hyprland focus-grab — pins keyboard input to this layer regardless of
    // what other layers/windows are doing on the same screen.
    HyprlandFocusGrab {
        windows: [win]
        active: win.show
    }

    readonly property bool dark: ThemeService.isDark
    readonly property var wins: _dismissing ? _frozenWins
                               : (_sessionActive ? _sessionWins : WindowsService.windows)
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

    // ── Cycling helpers ──────────────────────────────────────────────────
    function next() {
        if (count === 0) return
        selectedIndex = (selectedIndex + 1) % count
    }
    function prev() {
        if (count === 0) return
        selectedIndex = (selectedIndex - 1 + count) % count
    }
    function prepareOpen() {
        _sessionWins = WindowsService.windows.slice()
        _sessionActive = true
        _dismissing = false
        _frozenWins = []
    }
    function beginDismissal() {
        let snapshot = wins.slice()
        let index = Math.max(0, Math.min(selectedIndex, snapshot.length - 1))
        let selected = snapshot.length > 0 ? snapshot[index] : null
        _frozenWins = snapshot
        _dismissing = true
        return selected && selected.address ? selected.address : ""
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
    DropShadow {
        anchors.fill: card
        source: card
        opacity: card.opacity
        scale: card.scale
        transformOrigin: Item.Center
        horizontalOffset: 0
        verticalOffset: 10
        radius: 22
        samples: 29
        color: Qt.rgba(0, 0, 0, dark ? 0.46 : 0.30)
        transparentBorder: true
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: win.cardW
        height: win.cardH
        radius: 22

        color: ThemeService.bg
        border.color: ThemeService.stroke
        border.width: 1

        opacity: win._presented ? 1.0 : 0.0
        scale:   win._presented ? 1.0 : 0.92
        transformOrigin: Item.Center
        Behavior on opacity { AppleSpring { spring: 18 } }
        Behavior on scale { AppleSpring { spring: 18 } }
        onOpacityChanged: {
            if (!win.show && opacity <= 0.002) {
                win._surfaceVisible = false
                win._sessionActive = false
                win._sessionWins = []
                win._dismissing = false
                win._frozenWins = []
            }
        }

        // Selected app title
        Text {
            id: titleLabel
            readonly property bool empty: win.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: empty ? Math.round((parent.height - implicitHeight) / 2) : 14
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
                                scale: cellMa.pressed ? ThemeService.pressScale : (selected ? 1.04 : 1.0)
                                Behavior on scale { AppleSpring { spring: 18 } }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: 14
                                    color: ThemeService.selectionBg
                                    border.color: ThemeService.selectionStroke
                                    border.width: 1
                                    opacity: cell.selected ? 1 : 0
                                    scale: cell.selected ? 1 : 0.94
                                    Behavior on opacity { AppleSpring { spring: 18 } }
                                    Behavior on scale { AppleSpring { spring: 18 } }
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
                                    id: cellMa
                                    anchors.fill: parent
                                    enabled: win.show
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onEntered: win.selectedIndex = cell.globalIndex
                                    onPressed: win.selectedIndex = cell.globalIndex
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
        enabled: win.show
        onPressed: win.closeRequested()
    }
}
