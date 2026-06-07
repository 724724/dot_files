// Standalone runner for testing the widgets board in isolation:
//   qs -c widgets   (then: qs ipc -c widgets call widgets toggle)
// In normal use it runs inside the unified desktop process via the top-level
// desktop/shell.qml WidgetsController {}.
import Quickshell

Scope {
    WidgetsController {}
}
