import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Self-contained controller: IPC + visibility state + the SpotlightWindow.
// Used by desktop/shell.qml so all shells share one qs process.
// IPC target renamed from "ctrl" → "spotlight" so it can coexist with the
// launchpad and switcher targets in the same process.
Scope {
    id: scope
    property bool spotlightVisible: false

    GlobalShortcut {
        appid: "spotlight"
        name: "toggle"
        description: "Spotlight: toggle"
        onPressed: scope.spotlightVisible = !scope.spotlightVisible
    }

    IpcHandler {
        target: "spotlight"
        function show()   { scope.spotlightVisible = true }
        function hide()   { scope.spotlightVisible = false }
        function toggle() { scope.spotlightVisible = !scope.spotlightVisible }
    }

    SpotlightWindow {
        show: scope.spotlightVisible
        onCloseRequested: scope.spotlightVisible = false
    }
}
