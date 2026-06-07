import Quickshell
import Quickshell.Io

// Self-contained controller: IPC + visibility state + the EmojiWindow.
// Used by desktop/shell.qml so all shells share one qs process.
// Toggle via:  qs ipc -c desktop call emoji toggle
Scope {
    id: scope
    property bool emojiVisible: false

    IpcHandler {
        target: "emoji"
        function show()   { scope.emojiVisible = true }
        function hide()   { scope.emojiVisible = false }
        function toggle() { scope.emojiVisible = !scope.emojiVisible }
    }

    EmojiWindow {
        show: scope.emojiVisible
        onCloseRequested: scope.emojiVisible = false
    }
}
