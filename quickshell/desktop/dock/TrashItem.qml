import Quickshell
import Quickshell.Io
import QtQuick
import "../icons" as Icons

Item {
    id: item

    property var dockWin: null
    property bool dark: true
    property bool trashFull: false
    property bool dropSucceeded: false
    property bool emptyOperation: false
    readonly property string trashFilesPath:
        Quickshell.env("HOME") + "/.local/share/Trash/files"

    readonly property real densityScale: dockWin ? dockWin.dockScale : 1
    readonly property bool horizontalDock: !dockWin || dockWin.horizontalDock
    readonly property bool leftDock: dockWin && dockWin.leftDock
    readonly property bool rightDock: dockWin && dockWin.rightDock
    readonly property real baseIconSize: 42 * densityScale
    readonly property real iconInset: 12 * densityScale
    readonly property real slotPadding: 16 * densityScale
    readonly property real hoverScale: DockService.iconZoomScale
    readonly property real visualIconScale:
        1 + (hoverScale - 1) * hoverProgress
    readonly property real tooltipGap: 8
    readonly property bool interactionBlocked: dockWin
        && (dockWin.previewOpen || dockWin.menuOpen || dockWin.dragActive
            || dockWin.launchpadDropActive || dockWin.separatorInteractionActive)
    readonly property bool magnified: !interactionBlocked
        && ((DockService.iconZoomEnabled && hover.hovered)
            || trashDrop.containsDrag || dropSucceeded)
    property real hoverProgress: magnified ? 1 : 0

    readonly property real expandedSlotSize: baseIconSize + slotPadding
        + baseIconSize * (hoverScale - 1) * hoverProgress
    implicitWidth: horizontalDock ? expandedSlotSize : 66 * densityScale
    implicitHeight: horizontalDock ? 66 * densityScale : expandedSlotSize

    Behavior on hoverProgress { AppleSpring { spring: 13 } }

    function localUrls(urls) {
        let result = []
        if (!urls) return result
        for (let i = 0; i < urls.length; i++) {
            let value = String(urls[i])
            // Trash only filesystem objects. In particular, never hand an
            // arbitrary URL or text payload to a process as an argument.
            if (!value.startsWith("file://")) return []
            result.push(value)
        }
        return result
    }

    function trashUrls(urls) {
        let accepted = localUrls(urls)
        if (accepted.length === 0 || trashProc.running) return false
        emptyOperation = false
        trashProc.command = ["gio", "trash", "--force", "--"].concat(accepted)
        trashProc.running = true
        return true
    }

    function openTrash() {
        if (DockService.launchpadOpen) DockService.launchpadCloseRequested()
        Quickshell.execDetached(["nautilus", "--new-window", "trash:///"])
    }

    function emptyTrash() {
        if (trashProc.running) return false
        emptyOperation = true
        // Optimistic visual feedback is safe here: an empty icon does not claim
        // data was destroyed, and a failed command immediately re-queries GIO's
        // backing directory below.
        trashFull = false
        trashProc.command = ["gio", "trash", "--empty"]
        trashProc.running = true
        return true
    }

    function refreshTrashState() {
        if (!statusProc.running) statusProc.running = true
    }

    Component.onCompleted: refreshTrashState()

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: item.refreshTrashState()
    }

    Timer {
        id: monitorDebounce
        interval: 45
        onTriggered: item.refreshTrashState()
    }

    // Follow Nautilus/GIO changes instead of waiting for the polling backstop.
    // This covers files restored or emptied outside the Dock as well as drops.
    Process {
        id: trashMonitor
        running: true
        command: ["gio", "monitor", "--dir=" + item.trashFilesPath]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => monitorDebounce.restart()
        }
    }

    Timer {
        id: settleTimer
        interval: 80
        onTriggered: item.refreshTrashState()
    }

    Timer {
        id: successTimer
        interval: 520
        onTriggered: item.dropSucceeded = false
    }

    Process {
        id: statusProc
        command: ["find", item.trashFilesPath,
            "-mindepth", "1", "-maxdepth", "1", "-print", "-quit"]
        stdout: StdioCollector {
            onStreamFinished: item.trashFull = text.trim() !== ""
        }
    }

    Process {
        id: trashProc
        command: ["true"]
        stderr: StdioCollector { id: trashError }
        onExited: (exitCode, exitStatus) => {
            if (item.dockWin) item.dockWin.externalDragActive = false
            if (exitCode === 0) {
                item.trashFull = !item.emptyOperation
                item.dropSucceeded = true
                successTimer.restart()
                settleTimer.restart()
            } else {
                item.refreshTrashState()
                Quickshell.execDetached(["notify-send", "-a", "Dock",
                    "-u", "normal", "Could not move item to Trash",
                    trashError.text.trim() || "The file manager rejected the operation."])
            }
            item.emptyOperation = false
        }
    }

    HoverHandler { id: hover }

    Icons.AppIcon {
        id: trashIcon
        x: item.horizontalDock ? (parent.width - width) / 2
            : item.leftDock ? item.iconInset
            : parent.width - width - item.iconInset
        y: item.horizontalDock ? item.iconInset : (parent.height - height) / 2
        width: item.baseIconSize
        height: item.baseIconSize
        iconName: item.trashFull ? "user-trash-full" : "user-trash"
        appClass: "trash"
        resolvePriority: 100
        smooth: true
        mipmap: true

        transform: Scale {
            origin.x: item.leftDock ? 0
                : item.rightDock ? trashIcon.width : trashIcon.width / 2
            origin.y: item.horizontalDock ? trashIcon.height : trashIcon.height / 2
            xScale: item.visualIconScale
            yScale: xScale
        }
    }

    Rectangle {
        id: tooltip
        z: 200
        visible: opacity > 0
        opacity: (hover.hovered || trashDrop.containsDrag)
            && !item.interactionBlocked ? 1 : 0
        x: item.horizontalDock ? (parent.width - width) / 2
            : item.leftDock
                ? item.iconInset + item.baseIconSize * item.visualIconScale
                    + item.tooltipGap
                : parent.width - item.iconInset
                    - item.baseIconSize * item.visualIconScale
                    - item.tooltipGap - width
        y: item.horizontalDock
            ? item.iconInset
                - item.baseIconSize * (item.visualIconScale - 1)
                - item.tooltipGap - height
            : (parent.height - height) / 2
        width: tipLabel.implicitWidth + 16 * item.densityScale
        height: tipLabel.implicitHeight + 8 * item.densityScale
        radius: Math.max(4, 7 * item.densityScale)
        color: ThemeService.popupBg
        border.color: ThemeService.stroke
        border.width: 1
        Behavior on opacity { AppleSpring { spring: 13 } }

        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: trashDrop.containsDrag ? "Move to Trash" : "Trash"
            color: item.dark ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(0, 0, 0, 0.85)
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    DropArea {
        id: trashDrop
        anchors.fill: parent
        onEntered: (drag) => {
            let valid = item.localUrls(drag.urls).length > 0 && !trashProc.running
            drag.accepted = valid
            if (valid && item.dockWin) item.dockWin.beginExternalDrag()
        }
        onPositionChanged: (drag) => {
            drag.accepted = item.localUrls(drag.urls).length > 0 && !trashProc.running
        }
        onExited: if (item.dockWin) item.dockWin.endExternalDragSoon()
        onDropped: (drop) => {
            if (!item.trashUrls(drop.urls)) {
                drop.accepted = false
                if (item.dockWin) item.dockWin.endExternalDragSoon()
                return
            }
            // The target performs the move via GIO. Report the source's proposed
            // action only after the local-URL validation and process launch.
            drop.acceptProposedAction()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !trashDrop.containsDrag
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (item.dockWin) {
                    let p = item.mapToItem(item.dockWin.contentItem,
                        item.width / 2, item.height / 2)
                    item.dockWin.openUtilityMenu("trash", p.x, p.y)
                }
                return
            }
            item.openTrash()
        }
    }
}
