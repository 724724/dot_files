import Quickshell
import Quickshell.Io

Scope {
    id: scope
    property bool padVisible: false

    IpcHandler {
        target: "ctrl"
        function show()   { scope.padVisible = true }
        function hide()   { scope.padVisible = false }
        function toggle() { scope.padVisible = !scope.padVisible }
    }

    LaunchpadWindow {
        show: scope.padVisible
        onCloseRequested: scope.padVisible = false
    }
}
