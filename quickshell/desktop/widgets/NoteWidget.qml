import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

// Sticky-note content (rich text). Lives inside a WidgetFrame, which owns the
// geometry/drag/colour chrome (macOS-style title bar: close left, zoom +
// collapse right, revealed on hover). All persistence goes through
// `frame.save({...})`. Colour + font are changed via right-click → Edit
// (NoteEditor). See [[quickshell-hyprland-quirks]].
//
// Shortcuts (macOS Cmd -> Ctrl) while the note is focused:
//   Ctrl N new · Ctrl W/D close (asks to save if non-empty) · Ctrl S export .txt
//   Ctrl M collapse · Ctrl Z undo / Ctrl Shift Z (or Ctrl Y) redo · Ctrl B/I/U
//   toggle format · Ctrl Shift S toggle strikethrough · Ctrl +/- font (selection
//   if any, else whole note) · Alt Tab checklist · Shift Ctrl O import
Item {
    id: noteRoot
    property var frame

    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int fontSize: (d && d.fontSize) ? d.fontSize : 15
    // "SF Pro Display" has no Korean glyphs, so Hangul falls back to a taller
    // CJK font and the line height wanders on mixed-script lines. Pretendard
    // (an SF-style face with full Korean coverage) keeps the look and gives one
    // consistent line height. Any other explicit font choice is respected.
    readonly property string fontFamily: {
        let f = (d && d.fontFamily) ? d.fontFamily : ""
        return (!f || f === "SF Pro Display") ? "Pretendard Variable" : f
    }

    function _esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // Plain text of the note (HTML stripped) — used for the collapsed title and
    // the "is there anything to save?" check. Drops Qt's <head>/<style> block.
    function _plain(html) {
        let s = html || ""
        s = s.replace(/<head[\s\S]*?<\/head>/gi, "")
        s = s.replace(/<style[\s\S]*?<\/style>/gi, "")
        s = s.replace(/<\/(p|div|h[1-6]|li)>/gi, "\n")
        s = s.replace(/<br\s*\/?>/gi, "\n")
        s = s.replace(/<[^>]+>/g, "")
        s = s.replace(/&nbsp;/gi, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
        return s
    }
    readonly property string firstLine: {
        let lines = noteRoot._plain(noteRoot.d.content || "").split("\n")
        for (let i = 0; i < lines.length; i++) if (lines[i].trim()) return lines[i].trim()
        return ""
    }
    function hasContent() { return noteRoot._plain(body.text).replace(/\s/g, "").length > 0 }

    // ── Rich-text formatting (toggle-aware) ─────────────────────────────────
    // Pure-QML rich text has no per-selection char-format API, so we work on the
    // selection's HTML fragment: strip the property being toggled from any inner
    // spans, then wrap the fragment in one span with the new value. That keeps
    // *other* formatting (e.g. italic while toggling bold) and lets a key turn
    // the format back off. Qt serialises <b>/<i>/<u>/<s> as span styles
    // (font-weight:700, font-style:italic, text-decoration:…), so we match those.
    // (Verified against Qt's getFormattedText output.)
    readonly property var _fmtRe: ({
        b: /font-weight:\s*(?:[5-9]\d\d|bold)/i,
        i: /font-style:\s*italic/i,
        u: /text-decoration:[^";}]*underline/i,
        s: /text-decoration:[^";}]*line-through/i
    })
    readonly property var _fmtStrip: ({
        b: /font-weight:\s*[^;"}]*;?/gi,
        i: /font-style:\s*[^;"}]*;?/gi,
        u: /text-decoration:\s*[^;"}]*;?/gi,
        s: /text-decoration:\s*[^;"}]*;?/gi
    })
    readonly property var _fmtCss: ({ b: "font-weight", i: "font-style", u: "text-decoration", s: "text-decoration" })
    readonly property var _fmtOn:  ({ b: "700", i: "italic", u: "underline", s: "line-through" })
    readonly property var _fmtOff: ({ b: "400", i: "normal", u: "none", s: "none" })

    // The HTML of a range, unwrapped from Qt's full-document envelope.
    function _fragment(html) {
        let a = html.indexOf("<!--StartFragment-->")
        let b = html.indexOf("<!--EndFragment-->")
        if (a >= 0 && b > a) return html.substring(a + 20, b)   // 20 = len of the marker
        let m = html.match(/<body[^>]*>([\s\S]*)<\/body>/i)
        let inner = m ? m[1] : html
        return inner.replace(/^\s*<p[^>]*>/i, "").replace(/<\/p>\s*$/i, "").trim()
    }
    function applyFmt(k) {
        let s = body.selectionStart, e = body.selectionEnd
        if (s === e) return
        noteRoot._commit()
        let frag = noteRoot._fragment(body.getFormattedText(s, e))
        let value = noteRoot._fmtRe[k].test(frag) ? noteRoot._fmtOff[k] : noteRoot._fmtOn[k]
        frag = frag.replace(noteRoot._fmtStrip[k], "")
        body.remove(s, e)
        body.insert(s, "<span style=\"" + noteRoot._fmtCss[k] + ":" + value + ";\">" + frag + "</span>")
        body.select(s, e)                    // keep the run selected so B/I/U/S chain
        noteRoot._commit()
        frame.save({ content: body.text })
    }

    // Ctrl +/- : selection → resize just that run (keeps other formatting; the
    // current size is read back from the run so repeats accumulate). No
    // selection → change the whole note's base size.
    function _clampFont(v) { return Math.max(WidgetsService.minFont, Math.min(WidgetsService.maxFont, v)) }
    function bumpFont(delta) {
        let s = body.selectionStart, e = body.selectionEnd
        if (s === e) {                       // no selection → whole-note base size
            frame.save({ fontSize: noteRoot._clampFont(noteRoot.fontSize + delta) })
            return
        }
        noteRoot._commit()
        let frag = noteRoot._fragment(body.getFormattedText(s, e))
        let m = frag.match(/font-size:\s*(\d+)px/i)
        let next = noteRoot._clampFont((m ? parseInt(m[1]) : noteRoot.fontSize) + delta)
        frag = frag.replace(/font-size:\s*[^;"}]*;?/gi, "")
        body.remove(s, e)
        body.insert(s, "<span style=\"font-size:" + next + "px;\">" + frag + "</span>")
        body.select(s, e)
        noteRoot._commit()
        frame.save({ content: body.text })
    }

    // ── Undo / redo (snapshot based) ────────────────────────────────────────
    // remove()+insert() registers as *two* native undo steps (so Ctrl+Z once
    // left the text gone, needing a second press), and assigning `text` wipes
    // native history entirely. So we keep our own stack of whole-document
    // snapshots: typing is checkpointed on a short idle debounce, and each edit
    // op checkpoints before+after, so one Ctrl+Z reverts exactly one action.
    property var _undoStack: [""]
    property int _undoIdx: 0
    property bool _restoring: false
    function _commit() {
        let s = body.text
        if (_undoStack.length > 0 && s === _undoStack[_undoIdx]) return
        let st = _undoStack.slice(0, _undoIdx + 1)
        st.push(s)
        if (st.length > 200) st.shift()
        _undoStack = st
        _undoIdx = _undoStack.length - 1
    }
    function _applyUndo(html) {
        _restoring = true
        body.text = html
        body.cursorPosition = body.length
        _restoring = false
        frame.save({ content: html })
    }
    function undo() {
        commitTimer.stop()
        _commit()                            // capture any in-progress typing
        if (_undoIdx > 0) { _undoIdx -= 1; _applyUndo(_undoStack[_undoIdx]) }
    }
    function redo() {
        commitTimer.stop()
        if (_undoIdx < _undoStack.length - 1) { _undoIdx += 1; _applyUndo(_undoStack[_undoIdx]) }
    }
    function _initUndo() { _undoStack = [body.text]; _undoIdx = 0 }
    Timer { id: commitTimer; interval: 350; onTriggered: noteRoot._commit() }

    function insertChecklist() {
        noteRoot._commit()
        body.insert(body.cursorPosition, "☐ ")
        noteRoot._commit()
        frame.save({ content: body.text })
    }
    function continueChecklist() {
        let pre = body.getText(0, body.cursorPosition)
        let lastBreak = -1
        for (let i = pre.length - 1; i >= 0; i--) {
            let c = pre.charCodeAt(i)
            if (c === 10 || c === 0x2028 || c === 0x2029) { lastBreak = i; break }
        }
        let line = pre.substring(lastBreak + 1).replace(/^\s+/, "")
        let first = line.charAt(0)
        if (first === "☐" || first === "☑") {
            noteRoot._commit()
            body.insert(body.cursorPosition, "<br>☐ ")
            noteRoot._commit()
            frame.save({ content: body.text })
            return true
        }
        return false
    }

    // ── Close: ask to save when there's content, else just delete ───────────
    property bool confirming: false
    function requestClose() {
        if (!noteRoot.hasContent()) { WidgetsService.removeAt(frame.index); return }
        if (noteRoot.d.collapsed) frame.save({ collapsed: false })  // expand so the dialog fits
        confirming = true
    }

    // ── Export to .txt via GTK picker ───────────────────────────────────
    // Layer-shell overlays always paint above normal windows, so the picker
    // can't appear on top while the board is open. We hide the overlay first,
    // then reopen it once the dialog (Process) exits. `closeAfter` is set when
    // the export comes from the close-confirm dialog: delete the note once it's
    // actually been written.
    property bool _closeAfter: false
    function exportNote(closeAfter) {
        noteRoot._closeAfter = !!closeAfter
        let ord = WidgetsService.noteOrdinal(frame ? frame.index : -1)
        ioFile.path = "/tmp/qs-note-" + (frame ? frame.wid : 0) + ".txt"
        ioFile.setText(body.getText(0, body.length))
        frame.winRef.closeRequested()
        exportProc.command = ["bash", "-c",
            "p=$(zenity --file-selection --save --confirm-overwrite "
            + "--title='Export note' --filename=\"$HOME/notes-" + ord + ".txt\" 2>/dev/null) "
            + "&& cp \"" + ioFile.path + "\" \"$p\" && echo SAVED"]
        exportProc.running = true
    }
    function importNote() {
        frame.winRef.closeRequested()
        importProc.running = true
    }

    FileView { id: ioFile; blockLoading: true; printErrors: false }
    Process {
        id: exportProc
        stdout: StdioCollector {
            onStreamFinished: {
                frame.winRef.reopenRequested()
                if (noteRoot._closeAfter) {
                    noteRoot._closeAfter = false
                    // Only delete if the file was actually saved (zenity not
                    // cancelled) — avoids losing a note to a stray Cancel.
                    // Deferred so we don't destroy this Process inside its own
                    // signal handler.
                    if (text.indexOf("SAVED") >= 0) {
                        let i = frame.index
                        Qt.callLater(function () { WidgetsService.removeAt(i) })
                    }
                }
            }
        }
    }
    Process {
        id: importProc
        command: ["zenity", "--file-selection", "--title=Import into note"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim()
                if (p) {
                    ioFile.path = p
                    let c = ioFile.text()
                    if (c !== undefined && c !== null) {
                        noteRoot._commit()
                        body.insert(body.length, noteRoot._esc(c).replace(/\n/g, "<br>"))
                        noteRoot._commit()
                    }
                    frame.save({ content: body.text })
                }
                frame.winRef.reopenRequested()
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextArea.flickable: TextArea {
            id: body
            textFormat: TextEdit.RichText
            wrapMode: TextArea.Wrap
            selectByMouse: true
            persistentSelection: true
            // Leave room at the top for the hover title bar so its buttons never
            // sit over the first line of text.
            topPadding: 18
            color: Qt.rgba(0, 0, 0, 0.82)
            placeholderText: "Type a note…"
            placeholderTextColor: Qt.rgba(0, 0, 0, 0.32)
            font.family: noteRoot.fontFamily
            font.pixelSize: noteRoot.fontSize
            background: null

            Component.onCompleted: { text = (noteRoot.d.content || ""); noteRoot._initUndo() }
            Connections {
                target: noteRoot
                function onDChanged() {
                    // Only resync the body from stored data on a genuine
                    // *external* content change — never while the user is
                    // editing, and ignore HTML re-serialization noise (compare
                    // plain text). Otherwise every autosave / font / colour /
                    // collapse change would reparse the whole document and push
                    // a spurious undo step, so Ctrl+Z had to be pressed twice.
                    if (body.activeFocus) return
                    if (noteRoot._plain(body.text) !== noteRoot._plain(noteRoot.d.content || "")) {
                        noteRoot._restoring = true
                        body.text = (noteRoot.d.content || "")
                        noteRoot._restoring = false
                        noteRoot._initUndo()
                    }
                }
            }

            onActiveFocusChanged: {
                if (activeFocus && frame) frame.bringToFront()
                else if (frame) frame.save({ content: text })
            }
            onTextChanged: {
                saveTimer.restart()
                if (!noteRoot._restoring) commitTimer.restart()
            }

            Keys.onEscapePressed: {
                frame.save({ content: text })
                frame.winRef.closeRequested()
            }
            Keys.onPressed: (e) => {
                let ctrl  = (e.modifiers & Qt.ControlModifier) !== 0
                let shift = (e.modifiers & Qt.ShiftModifier)  !== 0
                let alt   = (e.modifiers & Qt.AltModifier)    !== 0

                // Undo / redo via our own snapshot stack (native undo splits
                // each format op into two steps — see _commit above).
                if (ctrl && !alt && e.key === Qt.Key_Z) {
                    if (shift) noteRoot.redo(); else noteRoot.undo()
                    e.accepted = true; return
                }
                if (ctrl && !shift && !alt && e.key === Qt.Key_Y) { noteRoot.redo(); e.accepted = true; return }

                if (ctrl && shift && e.key === Qt.Key_O) { noteRoot.importNote(); e.accepted = true; return }
                if (ctrl && shift && e.key === Qt.Key_S) { noteRoot.applyFmt("s"); e.accepted = true; return }

                if (ctrl && !shift && !alt) {
                    switch (e.key) {
                    case Qt.Key_B: noteRoot.applyFmt("b"); e.accepted = true; return
                    case Qt.Key_I: noteRoot.applyFmt("i"); e.accepted = true; return
                    case Qt.Key_U: noteRoot.applyFmt("u"); e.accepted = true; return
                    case Qt.Key_N: WidgetsService.addWidget("note"); e.accepted = true; return
                    case Qt.Key_W: noteRoot.requestClose(); e.accepted = true; return
                    case Qt.Key_D: noteRoot.requestClose(); e.accepted = true; return
                    case Qt.Key_S: noteRoot.exportNote(false); e.accepted = true; return
                    case Qt.Key_M: frame.save({ collapsed: !noteRoot.d.collapsed }); e.accepted = true; return
                    case Qt.Key_Plus:
                    case Qt.Key_Equal:      noteRoot.bumpFont(+1); e.accepted = true; return
                    case Qt.Key_Minus:
                    case Qt.Key_Underscore: noteRoot.bumpFont(-1); e.accepted = true; return
                    }
                }
                if (alt && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
                    noteRoot.insertChecklist(); e.accepted = true; return
                }
                if (!ctrl && !alt && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                    if (noteRoot.continueChecklist()) { e.accepted = true; return }
                }
            }

            Timer {
                id: saveTimer
                interval: 600
                onTriggered: frame.save({ content: body.text })
            }
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    // ── Close confirmation ("Save this note?") ──────────────────────────────
    component DialBtn: Rectangle {
        property string label: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        height: 30; radius: 8
        color: primary ? (dbHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85))
                       : (dbHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent; text: label
            color: danger ? "#ff6b6b" : "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 12
            font.weight: primary ? Font.Medium : Font.Normal
        }
        HoverHandler { id: dbHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: parent.clicked() }
    }

    Rectangle {
        id: confirmOverlay
        anchors.fill: parent
        visible: noteRoot.confirming
        color: Qt.rgba(0, 0, 0, 0.18)
        radius: 0
        // Swallow clicks so they don't reach the note behind the dialog.
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, 220)
            height: dialCol.implicitHeight + 24
            radius: 12
            color: Qt.rgba(0.16, 0.16, 0.18, 0.98)
            border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1

            Column {
                id: dialCol
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 12

                Text {
                    width: parent.width
                    text: "이 메모를 저장할까요?"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                DialBtn {
                    width: parent.width; label: "저장"; primary: true
                    onClicked: { noteRoot.confirming = false; noteRoot.exportNote(true) }
                }
                DialBtn {
                    width: parent.width; label: "저장 안 함"; danger: true
                    onClicked: { noteRoot.confirming = false; WidgetsService.removeAt(frame.index) }
                }
                DialBtn {
                    width: parent.width; label: "취소"
                    onClicked: noteRoot.confirming = false
                }
            }
        }
    }
}
