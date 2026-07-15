import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

// A single window preview: a live ScreencopyView of the matching Wayland toplevel,
// positioned and sized from the window's logical Hyprland geometry. Used both big
// (in the stage) and tiny (inside a workspace tile). Draggable in the stage.
Item {
    id: thumb

    required property var windowData
    property var monitorData: null     // only needed in geometry mode (mini-previews)
    property real mscale: 1
    property bool draggable: false
    property bool live: true
    property bool dim: false              // dragged elsewhere / inactive look
    property bool flat: false
    property string iconUrl: ""

    readonly property string address: windowData ? windowData.address : ""
    readonly property bool dragging: draggable && overview && overview.dragActive && overview.dragAddress === address

    // Reference to the MissionControlWindow (which owns the shared drag state).
    // Stays null when the thumb is used outside it (e.g. a workspace mini-preview),
    // which also makes it non-interactive.
    property var overview: null

    // Two layout modes. Geometry mode (default) places the preview at the window's
    // real position — used by the workspace mini-previews so a tile looks like the
    // real space. Slot mode (slotW > 0) fits the preview into a given grid cell —
    // used by the stage so overlapping windows are spread out and shrink as the
    // count grows. `spread` (0..1) lerps between the real position and the slot, so
    // the stage can animate the windows flying apart when Mission Control opens.
    property real slotX: 0
    property real slotY: 0
    property real slotW: 0
    property real slotH: 0
    property real spread: 1
    readonly property bool slotMode: slotW > 0
    readonly property real _aspect: (windowData && windowData.size[1] > 0)
        ? windowData.size[0] / windowData.size[1] : 1.5

    readonly property real _geomX: (windowData && monitorData) ? (windowData.at[0] - monitorData.x) * mscale : 0
    readonly property real _geomY: (windowData && monitorData) ? (windowData.at[1] - monitorData.y) * mscale : 0
    readonly property real _geomW: windowData ? windowData.size[0] * mscale : 10
    readonly property real _geomH: windowData ? windowData.size[1] * mscale : 10
    readonly property real _slotFitW: Math.min(slotW, slotH * _aspect)
    readonly property real _slotFitH: _slotFitW / _aspect
    readonly property real _slotX: slotX + (slotW - _slotFitW) / 2
    readonly property real _slotY: slotY + (slotH - _slotFitH) / 2

    x: slotMode ? (_geomX + (_slotX - _geomX) * spread) : _geomX
    y: slotMode ? (_geomY + (_slotY - _geomY) * spread) : _geomY
    width: Math.max(8, slotMode ? (_geomW + (_slotFitW - _geomW) * spread) : _geomW)
    height: Math.max(8, slotMode ? (_geomH + (_slotFitH - _geomH) * spread) : _geomH)

    visible: !dragging
    clip: false
    scale: thumbTap.pressed && !dragging ? ThemeService.pressScale : 1.0
    Behavior on scale { AppleSpring { spring: 18 } }

    // Smoothly settle when the layout reflows (window count changes) — but stay out
    // of the way while the open/close spread is animating, which drives x/y directly
    // via the binding above.
    readonly property bool _settled: thumb.slotMode && thumb.overview && !thumb.overview.spreadAnimating
    Behavior on x { enabled: thumb._settled; AppleSpring { spring: 18; epsilon: 0.15 } }
    Behavior on y { enabled: thumb._settled; AppleSpring { spring: 18; epsilon: 0.15 } }
    Behavior on width { enabled: thumb._settled; AppleSpring { spring: 18; epsilon: 0.15 } }
    Behavior on height { enabled: thumb._settled; AppleSpring { spring: 18; epsilon: 0.15 } }

    // Resolve the Wayland capture handle via Hyprland's own toplevel list, matched
    // by address — the same source the bar's workspace icons use. (Matching Wayland
    // ToplevelManager by attached property didn't capture on this setup.)
    readonly property var toplevel: {
        let tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < tops.length; i++) {
            let t = tops[i]
            let o = (t && t.lastIpcObject) ? t.lastIpcObject : null
            if (o && o.address === thumb.address && t.wayland) return t.wayland
        }
        return null
    }

    readonly property bool interactive: overview !== null
    readonly property bool hovered: hoverH.hovered
    readonly property bool isDropTarget: overview && overview.dropWindowAddress === thumb.address

    readonly property bool _highlighted: thumb.isDropTarget || (thumb.hovered && thumb.interactive)

    // Separated focus ring: sits ~3px OUTSIDE the thumbnail (not hugging it),
    // thicker and a deeper blue, shown only while hovered or a drop target.
    Rectangle {
        anchors.fill: card
        anchors.margins: -8
        radius: card.radius + 8
        color: "transparent"
        border.color: "#0A84FF"
        border.width: 5
        visible: opacity > 0.002
        opacity: thumb._highlighted ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 18 } }
    }

    ClippingRectangle {
        id: card
        anchors.fill: parent
        radius: thumb.flat ? 0 : Math.min(10, parent.height * 0.12)
        color: thumb.flat ? "transparent" : ThemeService.previewBg

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: thumb.toplevel
            live: thumb.live
            paintCursor: false
        }

        // Fallback icon when there's no captured frame yet (e.g. a window on an
        // inactive workspace that hasn't been rendered since opening).
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.4
            height: width
            source: thumb.iconUrl
            visible: thumb.iconUrl !== "" && (!capture.hasContent)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // Rounded dim overlay (used while dragging elsewhere).
        Rectangle {
            anchors.fill: parent
            radius: thumb.flat ? 0 : card.radius
            visible: thumb.dim
            color: Qt.rgba(0, 0, 0, 0.35)
        }
    }

    // Window-name pill, floating over the preview — shown only on hover (macOS-
    // style). Lives outside the clipped card so it's never cut off.
    Rectangle {
        visible: opacity > 0.002
        opacity: thumb.hovered && thumb.interactive ? 1 : 0
        scale: thumb.hovered && thumb.interactive ? 1 : 0.96
        Behavior on opacity { AppleSpring { spring: 18 } }
        Behavior on scale { AppleSpring { spring: 18 } }
        anchors.centerIn: parent
        width: Math.min(pillText.implicitWidth + 22, thumb.width + 40)
        height: pillText.implicitHeight + 10
        radius: 7
        color: Qt.rgba(1, 1, 1, 0.94)
        border.color: Qt.rgba(0, 0, 0, 0.08)
        border.width: 1
        Text {
            id: pillText
            anchors.centerIn: parent
            width: parent.width - 22
            text: thumb.windowData ? (thumb.windowData.title || "") : ""
            color: "#1c1c1e"
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }

    HoverHandler {
        id: hoverH
        enabled: thumb.interactive
        cursorShape: Qt.PointingHandCursor
    }

    // TapHandler (not MouseArea) so it cooperates with the DragHandler — a tap
    // focuses + dismisses, a drag past threshold reorders.
    TapHandler {
        id: thumbTap
        enabled: thumb.overview !== null
        onTapped: thumb.overview.activateWindow(thumb.address)
    }

    DragHandler {
        id: thumbDrag
        target: null
        enabled: thumb.draggable && thumb.overview !== null
        dragThreshold: 6
        onActiveChanged: {
            if (active) {
                let centre = thumb.mapToItem(null, thumb.width / 2, thumb.height / 2)
                thumb.overview.beginWindowDrag(thumb.address, centroid.scenePosition,
                    centroid.scenePressPosition, centre)
            }
            else thumb.overview.endWindowDrag()
        }
        onCentroidChanged: if (active && thumb.overview) thumb.overview.updateWindowDrag(centroid.scenePosition)
    }
}
