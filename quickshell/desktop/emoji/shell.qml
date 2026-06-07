// Standalone runner for testing the emoji picker in isolation:
//   qs -p ~/.config/quickshell/desktop/emoji/shell.qml
//   (then: qs ipc -c emoji call emoji toggle)
// In normal use it runs inside the unified desktop process via the top-level
// desktop/shell.qml EmojiController {}.
import Quickshell

Scope {
    EmojiController {}
}
