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
    property string pendingFocusAddress: ""

    SwitcherWindow {
        id: switcher
        show: scope.switcherOpen
        onCloseRequested: scope.cancel()
        onConfirmRequested: scope.confirm()
    }

    Timer {
        id: focusCommit
        interval: 32
        onTriggered: {
            let address = scope.pendingFocusAddress
            scope.pendingFocusAddress = ""
            if (address) WindowsService.focusByAddress(address)
        }
    }

    // Force WindowsService eager-load so the very first Super+Tab has data.
    Component.onCompleted: WindowsService.refresh()

    function _setSelectionFromDir(dir) {
        let n = switcher.count
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
            return
        }
        focusCommit.stop()
        pendingFocusAddress = ""
        WindowsService.refresh()
        switcher.prepareOpen()
        _setSelectionFromDir(dir)
        scope.switcherOpen = true
    }

    function confirm() {
        if (!scope.switcherOpen) return
        let address = switcher.beginDismissal()
        scope.switcherOpen = false
        pendingFocusAddress = address
        if (address) focusCommit.restart()
    }

    function cancel() {
        if (!scope.switcherOpen) return
        switcher.beginDismissal()
        scope.switcherOpen = false
        focusCommit.stop()
        pendingFocusAddress = ""
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
    GlobalShortcut {
        appid: "switcher"
        name: "commit"
        description: "App switcher: commit on Super release"
        onPressed: scope.confirm()
    }

    IpcHandler {
        target: "switcher"
        function next()    { scope.openOrAdvance(+1) }
        function prev()    { scope.openOrAdvance(-1) }
        function confirm() { scope.confirm() }
        function cancel()  { scope.cancel() }
    }
}
