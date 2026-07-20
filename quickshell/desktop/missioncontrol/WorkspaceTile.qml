import QtQuick
import Quickshell

// One workspace in the top strip. Collapsed it shows just the name; when the strip
// is hovered (`expanded`) it reveals a live mini-preview (wallpaper + windows) of
// the space. A full-screen space shows an exit-fullscreen button; any other space
// shows × (delete). Dropping a dragged window onto a full-screen space splits it.
Item {
    id: tile

    required property int wsId
    property var monitorData: null
    property int activeWsId: MCService.activeWorkspaceId
    property bool expanded: false
    property bool captureEnabled: false
    property var overview: null
    property real layoutThumbW: 176

    readonly property bool dark: ThemeService.isDark
    readonly property var wins: MCService.windowsForWorkspace(wsId)
    // Address-keyed model for the mini previews (see MissionControlWindow.stageModel:
    // avoids recreating every ScreencopyView on each hyprctl poll).
    property var winModel: []
    readonly property string _winSig: wins.map(w => w.address).join(",")
    on_WinSigChanged: winModel = _winSig === "" ? [] : _winSig.split(",")
    Component.onCompleted: winModel = _winSig === "" ? [] : _winSig.split(",")
    readonly property bool isActive: wsId === activeWsId
    readonly property bool hasFullscreen: MCService.workspaceHasFullscreen(wsId)
    readonly property bool isDropTarget: overview && overview.dropWsId === wsId
    readonly property bool isSplitTarget: overview && overview.dropSplitWsId === wsId
    readonly property string splitSide: overview ? overview.dropSplitSide : ""
    readonly property string label: MCService.workspaceLabel(wsId)

    // App name of the full-screen window (for the split-preview name).
    readonly property string fsAppName: {
        let fs = tile.wins.find(w => MCService.isRealFullscreen(w.fullscreen))
        return (fs && tile.overview) ? tile.overview.appNameForClass(fs.class) : ""
    }
    // "dragged & fullscreen" or "fullscreen & dragged" depending on drop side.
    readonly property string displayLabel: {
        if (!tile.isSplitTarget || !tile.overview) return tile.label
        let d = tile.overview.dragAppName
        return tile.splitSide === "left" ? (d + " & " + tile.fsAppName)
                                         : (tile.fsAppName + " & " + d)
    }

    readonly property real monLogW: monitorData ? monitorData.width / monitorData.scale : 1920
    readonly property real monLogH: monitorData ? monitorData.height / monitorData.scale : 1200
    readonly property real thumbW: Math.max(0.1, layoutThumbW)
    readonly property real thumbH: thumbW * (monLogH / monLogW)
    readonly property real miniScale: thumbW / monLogW

    // Always ≤ thumbW so long names never push tiles apart — the strip spacing
    // stays even (names elide with … instead of widening the tile).
    implicitWidth: tile.expanded ? tile.thumbW : Math.min(nameRow.implicitWidth, tile.thumbW)
    implicitHeight: thumbCard.height + (tile.expanded ? 6 : 0) + nameRow.implicitHeight
    Behavior on implicitWidth { AppleSpring { spring: 18; epsilon: 0.15 } }
    scale: (tileTap.pressed || tileDrag.active) ? ThemeService.pressScale : 1.0
    Behavior on scale { AppleSpring { spring: 18 } }

    // Dim while being dragged to a new position in the strip.
    opacity: (overview && overview.tileDragActive && overview.tileDragId === wsId) ? 0.35 : 1.0

    // ── Thumbnail (revealed on strip hover) ───────────────────────────────────
    Rectangle {
        id: thumbCard
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.thumbW
        height: tile.expanded ? tile.thumbH : 0
        opacity: tile.expanded ? 1 : 0
        clip: true
        radius: 8
        color: "transparent"
        border.color: (tile.isDropTarget || tile.isSplitTarget || tile.isActive)
            ? "#0A84FF" : (tile.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.18))
        border.width: (tile.isActive || tile.isDropTarget || tile.isSplitTarget) ? 3 : 1
        Behavior on width { AppleSpring { spring: 18; epsilon: 0.15 } }
        Behavior on height { AppleSpring { spring: 18; epsilon: 0.15 } }
        Behavior on opacity { AppleSpring { spring: 18 } }

        // Real desktop wallpaper behind the previews → looks like the actual space.
        Rectangle {
            anchors.fill: parent
            color: tile.overview ? tile.overview.wallpaperPaddingColor : "#000000"
        }
        Image {
            anchors.fill: parent
            source: tile.overview ? tile.overview.wallpaperUrl : ""
            sourceSize: tile.overview ? tile.overview.wallpaperThumbSourceSize : Qt.size(512, 512)
            fillMode: tile.overview ? tile.overview.wallpaperFillMode : Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            asynchronous: true
            cache: true
        }

        // Mini live previews of each window, at their real positions.
        Item {
            anchors.fill: parent
            visible: tile.expanded
            Repeater {
                model: tile.expanded ? tile.winModel : []
                delegate: WindowThumb {
                    required property var modelData
                    windowData: MCService.windowByAddress(modelData)
                    monitorData: tile.monitorData
                    mscale: tile.miniScale
                    live: tile.isActive
                    captureEnabled: tile.captureEnabled
                    flat: true
                    draggable: false
                    iconUrl: (tile.overview && windowData) ? tile.overview.iconUrlForClass(windowData.class) : ""
                }
            }
        }

        // Split-view drop preview: the fullscreen app keeps one half; a gray + slot
        // marks the side the dragged app will take (left / right).
        Rectangle {
            visible: tile.isSplitTarget
            y: 0
            height: parent.height
            x: tile.splitSide === "left" ? 0 : parent.width / 2
            width: parent.width / 2
            color: Qt.rgba(0.55, 0.55, 0.58, 0.6)
            Text {
                anchors.centerIn: parent
                text: "+"
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 34
                font.weight: Font.Light
            }
        }

        Text {
            anchors.centerIn: parent
            visible: tile.expanded && tile.wins.length === 0
            text: "Empty"
            color: tile.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)
            font.family: "SF Pro Display"
            font.pixelSize: 12
        }

        // A single control at top-left: exit-fullscreen for a full-screen space,
        // otherwise × (delete). Both remove the space, so only one is shown.
        MCRoundButton {
            anchors { top: parent.top; left: parent.left; margins: 5 }
            glyph: tile.hasFullscreen ? "󰊓" : "×"
            visible: tileHover.hovered && tile.expanded
            onClicked: {
                if (!tile.overview) return
                if (tile.hasFullscreen) tile.overview.requestExitFullscreen(tile.wsId)
                else tile.overview.requestDeleteWorkspace(tile.wsId)
            }
        }
    }

    // ── Name — always shown; sits on the strip, colour follows the theme ──────
    Item {
        id: nameRow
        anchors.top: thumbCard.bottom
        anchors.topMargin: tile.expanded ? 6 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: Math.min(nameLabel.implicitWidth + 16, tile.thumbW)
        implicitHeight: 24

        // Active-space highlight pill (macOS-style) when collapsed to names.
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(nameLabel.implicitWidth + 18, tile.thumbW)
            height: 22
            radius: 6
            visible: tile.isActive && !tile.expanded
            color: ThemeService.controlBg
        }
        Text {
            id: nameLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tile.thumbW)
            text: tile.displayLabel
            color: tile.isActive
                ? (tile.dark ? "#f5f5f7" : "#1c1c1e")
                : (tile.dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.6))
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: tile.isActive ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    HoverHandler {
        id: tileHover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (!tile.overview) return
            if (hovered) tile.overview.hoveredWorkspaceId = tile.wsId
            else if (tile.overview.hoveredWorkspaceId === tile.wsId) tile.overview.hoveredWorkspaceId = -1
        }
    }
    onExpandedChanged: if (!expanded && overview && overview.hoveredWorkspaceId === wsId) overview.hoveredWorkspaceId = -1
    Component.onDestruction: if (overview && overview.hoveredWorkspaceId === wsId) overview.hoveredWorkspaceId = -1

    // Tap switches to this workspace and dismisses the overview. A TapHandler
    // (not a fill MouseArea) leaves the icon button clickable on top.
    TapHandler {
        id: tileTap
        onTapped: if (tile.overview) tile.overview.activateWorkspace(tile.wsId)
    }

    // Drag to reorder the workspace within the strip. Cooperates with the
    // TapHandler (tap = switch, drag = reorder); only once the cells are revealed.
    DragHandler {
        id: tileDrag
        target: null
        enabled: tile.expanded && tile.overview !== null
        dragThreshold: 8
        onActiveChanged: {
            if (active) {
                let centre = tile.mapToItem(null, tile.width / 2, tile.height / 2)
                tile.overview.beginTileDrag(tile.wsId, centroid.scenePosition,
                    centroid.scenePressPosition, centre)
            }
            else tile.overview.endTileDrag()
        }
        onCentroidChanged: if (active && tile.overview) tile.overview.updateTileDrag(centroid.scenePosition)
    }
}
