import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: win

    // ── Public state ─────────────────────────────────────────────────────
    property bool show: false
    signal closeRequested

    // Stay mapped during the close animation so it can fade out before unmap.
    property bool _surfaceVisible: false
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            queryField.text = ""
            pages.currentIndex = 0
            currentCellIndex = 0
            _surfaceVisible = true
            unmapTimer.stop()
            queryField.forceActiveFocus()
        } else {
            unmapTimer.restart()
        }
    }

    Timer {
        id: unmapTimer
        interval: 260
        onTriggered: win._surfaceVisible = false
    }

    // ── Layer / placement ───────────────────────────────────────────────
    WlrLayershell.namespace: "qs-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand so fcitx5's wayland_v2 frontend can bind for Hangul input.
    // See spotlight comment.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // ── App data ────────────────────────────────────────────────────────
    readonly property string query: queryField.text
    readonly property var filteredApps: {
        let apps = DesktopEntries.applications.values
        let q = query.trim().toLowerCase()
        let arr = []
        for (let i = 0; i < apps.length; i++) {
            let a = apps[i]
            if (!a || a.noDisplay) continue
            let n = (a.name || "").toLowerCase()
            if (!n) continue
            if (q) {
                let g = (a.genericName || "").toLowerCase()
                let kw = (a.keywords || []).join(" ").toLowerCase()
                let c = (a.comment || "").toLowerCase()
                if (!(n.includes(q) || g.includes(q) || kw.includes(q) || c.includes(q)))
                    continue
            }
            arr.push(a)
        }
        arr.sort((a, b) => (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase()))
        return arr
    }

    // ── Pagination ──────────────────────────────────────────────────────
    readonly property int gridCols: 9
    readonly property int gridRows: 6
    readonly property int perPage: gridCols * gridRows   // 54
    readonly property int pageCount: Math.max(1, Math.ceil(filteredApps.length / perPage))

    // Selection is tracked as an absolute index into filteredApps, not per-page.
    property int currentCellIndex: 0
    onFilteredAppsChanged: { currentCellIndex = 0; pages.currentIndex = 0 }

    function activateIndex(i) {
        let app = filteredApps[i]
        if (app) {
            // gtk-launch hands the .desktop file to GIO which handles the
            // full spec quoting (Wine apps with backslash-escaped paths,
            // etc.). Quickshell's app.execute() trips on those.
            //
            // execDetached fully reparents the child to PID 1 so slower-to-
            // initialize GTK apps (nwg-look, nwg-displays) aren't killed when
            // Quickshell tears down a tracked Process after gtk-launch returns.
            Quickshell.execDetached(["gtk-launch", app.id])
        }
        win.closeRequested()
    }

    function pageOfIndex(idx) { return Math.floor(idx / perPage) }
    function moveSelection(dx, dy) {
        if (filteredApps.length === 0) return
        let idx = currentCellIndex
        let onPage = idx % perPage
        let row = Math.floor(onPage / gridCols)
        let col = onPage % gridCols
        let newCol = col + dx
        let newRow = row + dy
        let newIdx = idx
        if (newCol < 0 && pages.currentIndex > 0) {
            // Go to last column of previous page, same row
            pages.currentIndex -= 1
            newIdx = pages.currentIndex * perPage + row * gridCols + (gridCols - 1)
        } else if (newCol >= gridCols && pages.currentIndex < pageCount - 1) {
            pages.currentIndex += 1
            newIdx = pages.currentIndex * perPage + row * gridCols + 0
        } else {
            newCol = Math.max(0, Math.min(gridCols - 1, newCol))
            newRow = Math.max(0, Math.min(gridRows - 1, newRow))
            newIdx = pages.currentIndex * perPage + newRow * gridCols + newCol
        }
        if (newIdx >= 0 && newIdx < filteredApps.length)
            currentCellIndex = newIdx
    }

    // ── Backdrop ────────────────────────────────────────────────────────
    // Theme-agnostic dark veil. Alpha is high enough to noticeably darken the
    // blurred background so app icons and labels remain readable; the actual
    // blur effect is supplied by Hyprland's `layerrule = blur on` for the
    // qs-launchpad namespace (see windowrules.conf).
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        opacity: win.show ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: win.closeRequested()
        }
    }

    // ── Content ──────────────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent

        opacity: win.show ? 1.0 : 0.0
        scale: win.show ? 1.0 : 0.97
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        // ── Search input (top center) ────────────────────────────────────
        Item {
            id: searchBar
            anchors.top: parent.top
            anchors.topMargin: 32
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 44

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Qt.rgba(1, 1, 1, 0.10)
                border.color: Qt.rgba(1, 1, 1, 0.20)
                border.width: 1
            }

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: Qt.rgba(1, 1, 1, 0.65)
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 18
            }

            TextField {
                id: queryField
                anchors.left: searchIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: "#ffffff"
                placeholderText: "Search"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 14
                selectByMouse: true

                Keys.onEscapePressed: win.closeRequested()
                Keys.onLeftPressed:  win.moveSelection(-1, 0)
                Keys.onRightPressed: win.moveSelection(+1, 0)
                Keys.onUpPressed:    win.moveSelection(0, -1)
                Keys.onDownPressed:  win.moveSelection(0, +1)
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_PageDown) {
                        if (pages.currentIndex < win.pageCount - 1) pages.currentIndex += 1
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        if (pages.currentIndex > 0) pages.currentIndex -= 1
                        event.accepted = true
                    }
                }
                Keys.onReturnPressed: win.activateIndex(win.currentCellIndex)
                Keys.onEnterPressed:  win.activateIndex(win.currentCellIndex)
            }
        }

        // ── Paged grid ───────────────────────────────────────────────────
        // Wrapper Item exists so the WheelHandler sits *outside* SwipeView
        // and consumes wheel events before SwipeView's inner ListView can
        // see them. Without this layer, even with `interactive: false` the
        // ListView still received wheel events at the boundary, scrolling a
        // few pixels and snapping back — that was the "bounce-back" the user
        // saw with mouse wheel input.
        Item {
            id: pageWrapper
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: searchBar.bottom
            anchors.bottom: pageDots.top
            anchors.topMargin: 24
            anchors.bottomMargin: 16

            // Time-based debounce so a continuous touchpad swipe flips one
            // page at a time, not all of them in a single sweep.
            property double lastFlipTime: 0

            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    // Always consume so the SwipeView/ListView underneath
                    // never sees the wheel event (= no rubber-band snap-back).
                    event.accepted = true

                    let dx = event.angleDelta.x + event.pixelDelta.x
                    let dy = event.angleDelta.y + event.pixelDelta.y

                    // Diagnostic — appears in `qs -c desktop log`. If a
                    // horizontal touchpad swipe shows dx=0/dy!=0 here, the
                    // hardware/libinput isn't generating a horizontal scroll
                    // event at all, and no QML code can rescue it.
                    console.log("[launchpad-wheel] dx=" + dx + " dy=" + dy
                        + " angle=(" + event.angleDelta.x + "," + event.angleDelta.y + ")"
                        + " pixel=(" + event.pixelDelta.x + "," + event.pixelDelta.y + ")")

                    // Use the dominant axis as the page-nav signal so any
                    // direction works even if a touchpad reports only y.
                    let primary = Math.abs(dx) >= Math.abs(dy) ? dx : dy
                    if (primary === 0) return

                    let now = Date.now()
                    if (now - pageWrapper.lastFlipTime < 280) return

                    if (primary < 0) {
                        if (pages.currentIndex < win.pageCount - 1) {
                            pages.currentIndex += 1
                            pageWrapper.lastFlipTime = now
                        }
                    } else {
                        if (pages.currentIndex > 0) {
                            pages.currentIndex -= 1
                            pageWrapper.lastFlipTime = now
                        }
                    }
                }
            }

        SwipeView {
            id: pages
            anchors.fill: parent
            clip: false
            interactive: false
            orientation: Qt.Horizontal  // explicit so pages slide left↔right

            Repeater {
                model: win.pageCount

                delegate: Item {
                    id: pageItem
                    required property int index   // page index
                    width: pages.width
                    height: pages.height

                    readonly property int pageStart: index * win.perPage
                    readonly property int pageEnd:   Math.min(pageStart + win.perPage, win.filteredApps.length)
                    readonly property int cellW: pageItem.width / win.gridCols
                    readonly property int cellH: pageItem.height / win.gridRows

                    Grid {
                        id: g
                        anchors.fill: parent
                        rows: win.gridRows
                        columns: win.gridCols

                        Repeater {
                            // Always render perPage cells; empty ones are blank
                            model: win.perPage

                            delegate: Item {
                                id: cell
                                required property int index   // cell index within page
                                width: pageItem.cellW
                                height: pageItem.cellH

                                readonly property int absIndex: pageItem.pageStart + index
                                readonly property var app: absIndex < win.filteredApps.length
                                    ? win.filteredApps[absIndex]
                                    : null
                                readonly property bool selected: win.currentCellIndex === absIndex

                                Rectangle {
                                    visible: cell.app !== null
                                    anchors.centerIn: parent
                                    width: parent.width - 14
                                    height: parent.height - 14
                                    radius: 18
                                    color: cell.selected
                                        ? Qt.rgba(1, 1, 1, 0.18)
                                        : (cellHover.hovered
                                            ? Qt.rgba(1, 1, 1, 0.10)
                                            : "transparent")
                                    Behavior on color { ColorAnimation { duration: 110 } }

                                    HoverHandler {
                                        id: cellHover
                                        onHoveredChanged: if (hovered && cell.app) win.currentCellIndex = cell.absIndex
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 5
                                        width: parent.width - 12

                                        Image {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 56
                                            height: 56
                                            sourceSize.width: 56
                                            sourceSize.height: 56
                                            source: cell.app && cell.app.icon
                                                ? "image://icon/" + cell.app.icon
                                                : "image://icon/application-x-executable"
                                            smooth: true
                                            mipmap: true
                                            fillMode: Image.PreserveAspectFit
                                            onStatusChanged: {
                                                if (status === Image.Error)
                                                    source = "image://icon/application-x-executable"
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: parent.width
                                            text: cell.app ? cell.app.name : ""
                                            color: "#ffffff"
                                            font.family: "SF Pro Display"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (cell.app) win.activateIndex(cell.absIndex)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        } // pageWrapper

        // ── Page indicator dots ──────────────────────────────────────────
        Row {
            id: pageDots
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            visible: win.pageCount > 1

            Repeater {
                model: win.pageCount
                delegate: Rectangle {
                    required property int index
                    width: 7; height: 7; radius: 999
                    color: index === pages.currentIndex
                        ? Qt.rgba(1, 1, 1, 0.85)
                        : Qt.rgba(1, 1, 1, 0.30)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pages.currentIndex = index
                    }
                }
            }
        }

        // ── Empty state ──────────────────────────────────────────────────
        Text {
            visible: win.filteredApps.length === 0
            anchors.centerIn: parent
            text: win.query !== "" ? "No results" : "Loading…"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: "SF Pro Display"
            font.pixelSize: 16
        }
    }
}
