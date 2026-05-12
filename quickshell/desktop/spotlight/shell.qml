import Quickshell
import Quickshell.Io

Scope {
    id: scope
    property bool spotlightVisible: false

    IpcHandler {
        target: "ctrl"
        function show()   { scope.spotlightVisible = true }
        function hide()   { scope.spotlightVisible = false }
        function toggle() { scope.spotlightVisible = !scope.spotlightVisible }
    }

    SpotlightWindow {
        show: scope.spotlightVisible
        onCloseRequested: scope.spotlightVisible = false
    }
}
