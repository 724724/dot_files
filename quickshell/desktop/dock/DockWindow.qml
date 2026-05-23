import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: win

    // Dedicated layer namespace so Hyprland layerrules can target the dock alone.
    // Without this, the dock shares "quickshell" with the bar/osd/nc, and the
    // global `animation slide top` rule re-runs every time the dock's height
    // changes (preview open/close).
    WlrLayershell.namespace: "qs-dock"
    // Overlay layer so the dock stays visible over fullscreen windows.
    WlrLayershell.layer: WlrLayer.Overlay

    // Anchor to the full bottom strip so the layer surface always spans the
    // screen width. With only `bottom: true` the surface auto-sized to
    // implicitWidth and re-centered when the preview opened — that shifted
    // the dock card and made the cached previewAnchorX point at the icon's
    // OLD position, so the arrow rendered under the wrong icon.
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Confine pointer input to the dock's own column (see triggerColumn): the
    // dock then reveals only when the cursor is over where it sits — not the
    // entire bottom edge — and the empty space to its left/right stays
    // click-through to the windows below. A preview grows the window and needs
    // its full surface (popup + click-outside-to-dismiss), so drop the mask
    // while one is open.
    mask: win.previewOpen ? null : dockRegion
    Region { id: dockRegion; item: triggerColumn }

    readonly property bool dark: ThemeService.isDark

    // ── Preview state ──────────────────────────────────────────────────────

    property bool previewOpen: false
    property string previewWmClass: ""
    property string previewIconName: ""
    property var previewWindows: []  // [{address, title}]
    // Anchor X (in this PanelWindow's coordinate space) of the clicked icon's center
    property real previewAnchorX: 0

    // Toggle: same icon click closes, different icon click switches.
    // Opens INSTANTLY using DockService data — no screenshot/grim, no spawn delay.
    function togglePreview(wmClass, iconName, anchorX) {
        if (previewOpen && previewWmClass === wmClass) {
            previewOpen = false
            return
        }
        let cached = DockService.clientsByClass[wmClass.toLowerCase()] || []
        let cleaned = cached
            .filter(c => c && c.size && c.size[0] > 0 && c.size[1] > 0)
            .map(c => ({ address: c.address, title: c.title || wmClass }))
        if (cleaned.length === 0) return

        previewWmClass = wmClass
        previewIconName = iconName
        previewWindows = cleaned
        previewAnchorX = anchorX
        previewOpen = true
        showDock = true
        hideTimer.stop()
    }

    // Preview grid sizing: up to 4 columns, wrap to multiple rows
    readonly property int previewCols: Math.min(4, Math.max(1, previewWindows.length))
    readonly property int previewRows: Math.ceil(previewWindows.length / Math.max(1, previewCols))
    readonly property int cardW: 200
    readonly property int cardH: 96
    readonly property int cardSpacing: 8
    readonly property int previewPadding: 12

    // Panel grows upward when preview is open: popup + gap + pointer + dock card area
    implicitHeight: previewOpen
        ? (previewRows * cardH + (previewRows - 1) * cardSpacing + previewPadding * 2 + 100)
        : 128

    // Smooth the layer-surface resize. Without this, Hyprland's no_anim
    // rule made the preview pop in by snapping the surface from 80 → 250+
    // in a single frame; the inner scale/fade looked broken because there
    // was no time to perceive it.
    Behavior on implicitHeight {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    implicitWidth: previewOpen
        ? Math.max(dockCard.implicitWidth,
                   previewCols * cardW + (previewCols - 1) * cardSpacing + previewPadding * 2 + 24)
        : dockCard.implicitWidth

    // ── Auto-hide ──────────────────────────────────────────────────────────

    property bool showDock: false
    margins.bottom: (showDock || previewOpen) ? 8 : -(128 - 4)
    Behavior on margins.bottom {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Invisible column matching the dock card's footprint. The window mask is
    // bound to this (see top of file), so all pointer input — clicks AND hover —
    // is confined to the dock's horizontal span: the strip to either side stays
    // click-through, and the reveal only triggers over the dock itself.
    Item {
        id: triggerColumn
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dockCard.implicitWidth
    }

    // Reveal / keep-open hover. Lives at the window level so it's an ancestor of
    // the dock card: ancestor handlers stay hovered while the cursor is over any
    // descendant, so the dock no longer retracts when you move onto the icons —
    // and the per-icon HoverHandlers beneath still fire, driving the hover zoom.
    // The mask already limits hover delivery to the dock column, so targeting the
    // whole window doesn't re-introduce the "reveal anywhere on the edge" bug.
    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop()
                win.showDock = true
            } else if (!win.previewOpen) {
                hideTimer.restart()
            }
        }
    }

    Timer { id: hideTimer; interval: 400; onTriggered: win.showDock = false }

    // ── Pinned apps ────────────────────────────────────────────────────────

    readonly property var pinnedApps: [
        { name: "Files",     wmClass: "org.gnome.Nautilus", iconName: "org.gnome.Nautilus", execCmd: ["gtk-launch", "org.gnome.Nautilus"] },
        { name: "Chrome",    wmClass: "google-chrome",      iconName: "google-chrome",      execCmd: ["gtk-launch", "google-chrome"] },
        { name: "KakaoTalk", wmClass: "kakaotalk.exe",      iconName: "KakaoTalk",          execCmd: ["gtk-launch", "wine-Programs-KakaoTalk"] },
        { name: "Spotify",   wmClass: "spotify",            iconName: "spotify-client",     execCmd: ["gtk-launch", "spotify"] }
    ]

    readonly property var pinnedClasses: pinnedApps.map(a => a.wmClass.toLowerCase())

    // Class → friendly name+icon. Handles:
    //  - Wine apps in virtual-desktop mode (class "explorer.exe" → Ableton)
    //  - KakaoTalk (Wine-extracted icon hash)
    //  - Qt apps that append _PID_RANDOM to the class on every launch
    //    (transmission, etc.) — strip the suffix so the icon theme finds it
    function _remapClass(cls) {
        let lc = cls.toLowerCase()
        if (lc === "explorer.exe") return { name: "Ableton", iconName: "ableton" }
        if (lc === "kakaotalk.exe") return { name: "KakaoTalk", iconName: "KakaoTalk" }
        if (lc === "code") return { name: "VS Code", iconName: "vscode" }
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        let base = m ? m[1] : cls
        let baseLc = base.toLowerCase()
        if (baseLc === "com.transmissionbt.transmission")
            return { name: "Transmission", iconName: "transmission" }
        return { name: base, iconName: base }
    }

    readonly property var extraApps: DockService.runningClasses
        .filter(cls => !pinnedClasses.includes(cls))
        .map(cls => {
            let m = _remapClass(cls)
            return { name: m.name, wmClass: cls, iconName: m.iconName, execCmd: [] }
        })

    // ── Dock card ──────────────────────────────────────────────────────────

    Rectangle {
        id: dockCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        implicitWidth: dockRow.implicitWidth + 20
        height: 68; radius: 22
        color: dark ? Qt.rgba(16/255, 16/255, 21/255, 0.72)
                    : Qt.rgba(1, 1, 1, 0.68)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.13)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: win.pinnedApps
                DockItem {
                    required property var modelData
                    name: modelData.name; wmClass: modelData.wmClass
                    iconName: modelData.iconName; execCmd: modelData.execCmd
                    dark: win.dark; dockWin: win
                }
            }

            // macOS-style separator between pinned apps and other running apps
            Item {
                visible: win.extraApps.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 52
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: 36
                    radius: 0.5
                    color: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
                }
            }

            Repeater {
                model: win.extraApps
                DockItem {
                    required property var modelData
                    name: modelData.name; wmClass: modelData.wmClass
                    iconName: modelData.iconName; execCmd: []
                    dark: win.dark; dockWin: win
                }
            }
        }
    }

    // ── Preview popup ──────────────────────────────────────────────────────

    // Dismiss overlay
    MouseArea {
        anchors.fill: parent
        visible: win.previewOpen
        z: 90
        onClicked: win.previewOpen = false
    }

    // Preview popup — instant, anchored to the clicked icon
    Rectangle {
        id: previewPopup
        visible: win.previewOpen && win.previewWindows.length > 0
        z: 100

        // Anchor horizontally to the clicked icon, clamped to panel edges
        x: {
            let target = win.previewAnchorX - width / 2
            let maxX = win.width - width - 8
            return Math.max(8, Math.min(maxX, target))
        }
        y: dockCard.y - height - 12

        width: cardGrid.implicitWidth + win.previewPadding * 2
        height: cardGrid.implicitHeight + win.previewPadding * 2
        radius: 18
        color: dark ? Qt.rgba(22/255, 23/255, 28/255, 0.94)
                    : Qt.rgba(248/255, 248/255, 248/255, 0.94)
        border.color: dark ? Qt.rgba(1,1,1,0.13) : Qt.rgba(0,0,0,0.11)
        border.width: 1

        // Smooth fade/scale entrance — visibly grows from the dock card
        opacity: win.previewOpen ? 1.0 : 0.0
        scale: win.previewOpen ? 1.0 : 0.88
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on scale   { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        // Tail pointer — tracks the icon center even when popup is clamped
        Canvas {
            id: pointer
            width: 18; height: 9
            // X within popup so the tip sits at previewAnchorX absolute
            x: Math.max(12,
                  Math.min(parent.width - width - 12,
                    win.previewAnchorX - parent.x - width / 2))
            anchors.top: parent.bottom
            anchors.topMargin: -1
            antialiasing: true
            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(width / 2, height)
                ctx.lineTo(width, 0)
                ctx.closePath()
                ctx.fillStyle = win.dark ? "rgba(22,23,28,0.94)" : "rgba(248,248,248,0.94)"
                ctx.fill()
                ctx.strokeStyle = win.dark ? "rgba(255,255,255,0.13)" : "rgba(0,0,0,0.11)"
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(width / 2, height)
                ctx.lineTo(width, 0)
                ctx.stroke()
            }
            // Re-paint on theme change
            Connections {
                target: win
                function onDarkChanged() { pointer.requestPaint() }
            }
        }

        Grid {
            id: cardGrid
            anchors.centerIn: parent
            columns: win.previewCols
            rowSpacing: win.cardSpacing
            columnSpacing: win.cardSpacing

            Repeater {
                model: win.previewWindows
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: win.cardW; height: win.cardH; radius: 12
                    color: cardHover.hovered
                        ? (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        : (dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.03))
                    border.color: cardHover.hovered
                        ? Qt.rgba(10/255, 132/255, 255/255, 0.55)
                        : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                    border.width: 1

                    Behavior on color        { ColorAnimation { duration: 90 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: cardHover }
                    scale: cardHover.hovered ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 44
                            source: "image://icon/" + win.previewIconName
                            smooth: true; mipmap: true
                            sourceSize.width: 44; sourceSize.height: 44
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 44 - 10
                            height: appName.implicitHeight + winTitle.implicitHeight + 4

                            Text {
                                id: appName
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                text: win.previewWmClass
                                color: dark ? Qt.rgba(1,1,1,0.95) : Qt.rgba(0,0,0,0.85)
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                id: winTitle
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: appName.bottom
                                anchors.topMargin: 2
                                text: card.modelData.title
                                color: dark ? Qt.rgba(1,1,1,0.62) : Qt.rgba(0,0,0,0.55)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.previewOpen = false
                            focusAddrProc.addr = card.modelData.address
                            focusAddrProc.running = true
                        }
                    }
                }
            }
        }
    }

    Process {
        id: focusAddrProc
        property string addr: ""
        command: ["hyprctl", "dispatch",
                  'hl.dsp.focus({ window = "address:' + addr + '" })']
    }
}
