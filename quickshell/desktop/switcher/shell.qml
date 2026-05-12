import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

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
        // Always kick a fresh refresh on open. The poll is at 300ms but the
        // user can Super+Tab faster than that — without an explicit refresh
        // here, the cached MRU (focusHistoryID order) is stale and the next
        // press would show the same "previous app" instead of the new one.
        WindowsService.refresh()
        scope._hasUserNavigated = false
        // Apply selection from cached data right away for instant visual
        // response. If the just-kicked refresh produces a different MRU, the
        // Connections handler below will re-apply before the user notices.
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
            // Re-apply MRU-based selection only if (a) the switcher is open,
            // (b) we still have a pending direction, and (c) the user hasn't
            // manually navigated since open. This corrects a stale-cache open
            // (e.g. rapid double Super+Tab) without overriding deliberate
            // Tab cycling.
            if (scope._pendingDir !== 0
                && scope.switcherOpen
                && !scope._hasUserNavigated) {
                if (scope._setSelectionFromDir(scope._pendingDir))
                    scope._pendingDir = 0
            }
        }
    }

    // ── Hyprland Global Shortcuts ────────────────────────────────────────
    // Hyprland binds (in keybindings.conf) route SUPER+TAB / SUPER+SHIFT+TAB
    // to these via `bind = ..., global, switcher:next` / `switcher:prev`.
    // GlobalShortcut exposes the actual keypress events to QML, so unlike
    // `exec` binds we get the press event directly without spawning a subshell.
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

    // ── IPC (kept for manual debugging / fallback) ──────────────────────
    IpcHandler {
        target: "ctrl"
        function next()    { scope.openOrAdvance(+1) }
        function prev()    { scope.openOrAdvance(-1) }
        function confirm() { scope.confirm() }
        function cancel()  { scope.cancel() }
    }
}
