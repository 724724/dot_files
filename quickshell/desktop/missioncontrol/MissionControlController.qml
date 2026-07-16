import Quickshell
import Quickshell.Io
import QtQuick

// Self-contained controller: IPC target "mc" + visibility state + per-screen windows.
// Toggled from Hyprland by SUPER+XF86Display (see keybindings.lua).
Scope {
    id: scope
    property bool mcVisible: false
    property bool _openPending: false
    property int _openRevision: 0

    function requestShow() {
        if (scope.mcVisible || scope._openPending) return
        scope._openPending = true
        scope._openRevision = MCService.refreshForOpen()
    }

    function requestHide() {
        scope._openPending = false
        scope.mcVisible = false
    }

    function requestToggle() {
        if (scope.mcVisible || scope._openPending) scope.requestHide()
        else scope.requestShow()
    }

    Connections {
        target: MCService
        function onSnapshotRevisionChanged() {
            if (!scope._openPending || MCService.snapshotRevision < scope._openRevision) return
            // Let activeWorkspace bindings consume the new snapshot before the
            // layer surface maps. Hidden windows then reset their stage without
            // running the workspace-switch animation.
            Qt.callLater(() => {
                if (!scope._openPending || MCService.snapshotRevision < scope._openRevision) return
                scope._openPending = false
                scope.mcVisible = true
            })
        }
    }

    IpcHandler {
        target: "mc"
        function show()   { scope.requestShow() }
        function hide()   { scope.requestHide() }
        function toggle() { scope.requestToggle() }
    }

    Variants {
        model: Quickshell.screens
        MissionControlWindow {
            show: scope.mcVisible
            onCloseRequested: scope.mcVisible = false
        }
    }
}
