import Quickshell
import Quickshell.Io

// Self-contained controller: IPC + visibility state + the LaunchpadWindow.
// IPC target renamed from "ctrl" → "launchpad" so it can coexist with the
// spotlight and switcher targets in the same process.
// (The dock-rise signalling lives in LaunchpadWindow so the screen name is set
// before the open flag — see DockService.launchpad* there.)
Scope {
    id: scope
    property bool padVisible: false

    IpcHandler {
        target: "launchpad"
        function show()   { scope.padVisible = true }
        function hide()   { scope.padVisible = false }
        function toggle() { scope.padVisible = !scope.padVisible }
    }

    LaunchpadWindow {
        show: scope.padVisible
        onCloseRequested: scope.padVisible = false
    }
}
