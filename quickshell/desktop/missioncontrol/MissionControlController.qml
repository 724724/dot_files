import Quickshell
import Quickshell.Io

// Self-contained controller: IPC target "mc" + visibility state + per-screen windows.
// Toggled from Hyprland by SUPER+XF86Display (see keybindings.lua).
Scope {
    id: scope
    property bool mcVisible: false

    IpcHandler {
        target: "mc"
        function show()   { scope.mcVisible = true }
        function hide()   { scope.mcVisible = false }
        function toggle() { scope.mcVisible = !scope.mcVisible }
    }

    Variants {
        model: Quickshell.screens
        MissionControlWindow {
            show: scope.mcVisible
            onCloseRequested: scope.mcVisible = false
        }
    }
}
