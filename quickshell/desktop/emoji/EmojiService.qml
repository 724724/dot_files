pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "emoji-data.js" as EmojiData

// Emoji catalogue + recents + "use this emoji" action.
//
// The catalogue is the bundled unicode-emoji-json data (emoji-data.js), grouped
// into macOS-style categories. Picking an emoji copies it to the clipboard
// (Wayland has no portable synthetic-typing without an extra tool — if `wtype`
// or `ydotool` is installed we type it directly, otherwise we fall back to
// wl-copy so it can be pasted) and records it under Recents.
Singleton {
    id: root

    readonly property var categories: EmojiData.categories
    property var recents: []            // array of emoji chars, most-recent first
    readonly property int recentsMax: 48

    FileView {
        id: store
        path: Quickshell.stateDir + "/emoji-recents.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: root._load()
    function _load() {
        let raw = store.text()
        if (!raw) return
        try { let a = JSON.parse(raw); if (Array.isArray(a)) root.recents = a } catch (e) { /* start fresh */ }
    }
    function _persist() { store.setText(JSON.stringify(root.recents)) }

    // Flat search across every category by the emoji's CLDR name. Capped so the
    // grid stays snappy. Returns [[char, name], …].
    function search(q) {
        q = (q || "").trim().toLowerCase()
        if (!q) return []
        let out = []
        let cats = EmojiData.categories
        for (let c = 0; c < cats.length; c++) {
            let es = cats[c].emojis
            for (let i = 0; i < es.length; i++) {
                if (es[i][1].indexOf(q) >= 0) {
                    out.push(es[i])
                    if (out.length >= 240) return out
                }
            }
        }
        return out
    }

    // Pick an emoji: record under Recents, copy it to the clipboard, and also
    // type it straight into the focused field. The small sleep lets the picker's
    // layer surface unmap so keyboard focus returns to the app before wtype
    // types. The clipboard copy always happens (install `wtype` for direct
    // input too).
    function use(ch) {
        let r = root.recents.slice()
        let i = r.indexOf(ch)
        if (i >= 0) r.splice(i, 1)
        r.unshift(ch)
        if (r.length > root.recentsMax) r = r.slice(0, root.recentsMax)
        root.recents = r
        root._persist()

        Quickshell.execDetached(["bash", "-c",
            "e=\"$1\"; "
          + "printf %s \"$e\" | wl-copy; "
          + "if command -v wtype >/dev/null 2>&1; then sleep 0.08; wtype \"$e\"; "
          + "elif command -v ydotool >/dev/null 2>&1; then sleep 0.08; ydotool type \"$e\"; fi",
            "_", ch])
    }
}
