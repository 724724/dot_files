import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Self-contained controller: IPC + visibility state + the WidgetsWindow.
// IPC target "widgets". Toggle via:
//   qs ipc -c desktop call widgets toggle
Scope {
    id: scope
    property bool widgetsVisible: false

    GlobalShortcut {
        appid: "widgets"
        name: "toggle"
        description: "Widgets: toggle"
        onPressed: scope.widgetsVisible = !scope.widgetsVisible
    }

    IpcHandler {
        target: "widgets"
        function show()   { scope.widgetsVisible = true }
        function hide()   { scope.widgetsVisible = false }
        function toggle() { scope.widgetsVisible = !scope.widgetsVisible }
    }

    WidgetsWindow {
        show: scope.widgetsVisible
        onCloseRequested: scope.widgetsVisible = false
        // Re-show after a GTK file dialog (which needs the overlay hidden).
        onReopenRequested: scope.widgetsVisible = true
    }
}
