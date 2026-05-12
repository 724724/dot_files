import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Self-contained controller: IPC + GlobalShortcut + state + SwitcherWindow.
// IPC target renamed from "ctrl" → "switcher" so it can coexist with the
// spotlight and launchpad targets in the same process.
Scope {
    id: scope

    property bool switcherOpen: false
    property int _pendingDir: 0
    // Tracks whether the user has manually moved selection (Tab/Shift+Tab/arrow)
    // since opening — once they have, we stop auto-correcting selection when
    // fresh MRU data arrives.
    property bool _hasUserNavigated: false

    SwitcherWindow {
        id: switcher
        show: scope.switcherOpen
        onCloseRequested: scope.switcherOpen = false
        onConfirmRequested: scope.confirm()
        onNavigated: scope._hasUserNavigated = true
    }

    // Force WindowsService eager-load so the very first Super+Tab has data.
    Component.onCompleted: WindowsService.refresh()

    function _setSelectionFromDir(dir) {
        let n = WindowsService.windows.length
        if (n === 0) return false
        switcher.selectedIndex = dir > 0
            ? (n > 1 ? 1 : 0)        // macOS-style: jump to previous app
            : (n - 1)                // Shift: last in MRU
        return true
    }

    function openOrAdvance(dir) {
        if (scope.switcherOpen) {
            if (dir > 0) switcher.next()
            else         switcher.prev()
            scope._hasUserNavigated = true
            return
        }
        WindowsService.refresh()
        scope._hasUserNavigated = false
        _setSelectionFromDir(dir)
        scope._pendingDir = dir
        scope.switcherOpen = true
    }

    function confirm() {
        if (!scope.switcherOpen) return
        switcher.confirm()
        scope.switcherOpen = false
        scope._pendingDir = 0
        scope._hasUserNavigated = false
    }

    function cancel() {
        scope.switcherOpen = false
        scope._pendingDir = 0
        scope._hasUserNavigated = false
    }

    Connections {
        target: WindowsService
        function onWindowsChanged() {
            if (scope._pendingDir !== 0
                && scope.switcherOpen
                && !scope._hasUserNavigated) {
                if (scope._setSelectionFromDir(scope._pendingDir))
                    scope._pendingDir = 0
            }
        }
    }

    GlobalShortcut {
        appid: "switcher"
        name: "next"
        description: "App switcher: next window"
        onPressed: scope.openOrAdvance(+1)
    }
    GlobalShortcut {
        appid: "switcher"
        name: "prev"
        description: "App switcher: previous window"
        onPressed: scope.openOrAdvance(-1)
    }

    IpcHandler {
        target: "switcher"
        function next()    { scope.openOrAdvance(+1) }
        function prev()    { scope.openOrAdvance(-1) }
        function confirm() { scope.confirm() }
        function cancel()  { scope.cancel() }
    }
}
