import QtQuick
import QtQuick.Controls
import "kinetic.js" as Kinetic

// Sticky-note content (rich text). Lives inside a WidgetFrame, which owns the
// geometry/drag/colour chrome (macOS-style title bar: close left, zoom +
// collapse right, revealed on hover). All persistence goes through
// `frame.save({...})`. Colour + font are changed via right-click → Edit
// (NoteEditor). See [[quickshell-hyprland-quirks]].
Item {
    id: noteRoot
    property var frame

    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int fontSize: (d && d.fontSize) ? d.fontSize : 15
    property bool _restoring: false
    // "SF Pro Display" has no Korean glyphs, so Hangul falls back to a taller
    // CJK font. Default to Apple SD Gothic Neo — full Korean + Latin coverage
    // and, crucially, a *static* family with real weight styles: Pretendard
    // Variable's bold renders nearly black in Qt rich text (the wght axis isn't
    // applied per-run so it synthesises), whereas Apple SD Gothic Neo's real
    // SemiBold/Bold render cleanly. "SF Pro Display" and "Pretendard Variable"
    // were only ever the creation-time defaults, so both redirect to the new
    // default; any other explicit font choice is respected.
    readonly property string fontFamily: {
        let f = (d && d.fontFamily) ? d.fontFamily : ""
        return (!f || f === "SF Pro Display" || f === "Pretendard Variable")
             ? "Apple SD Gothic Neo" : f
    }

    // Qt bakes the document's default font-family into the saved HTML, so a
    // newly-chosen base family wouldn't restyle existing text — and bold can
    // render weakly when the baked face has poor weight coverage. Strip baked
    // font-family so the live `font.family` (bound to fontFamily) always governs
    // the whole note. The formatting shortcuts (Ctrl+B/I/U/…) write whole
    // per-run fonts, family included — stripping those too is exactly what we
    // want: bold/size/etc survive, the family always follows the base font.
    function _stripFamily(s) {
        return (s || "").replace(/font-family:[^;"}]*;?/gi, "")
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

    // ── Close: ask to save when there's content, else just delete ───────────
    property bool confirming: false
    function requestClose() {
        if (!noteRoot.hasContent()) { WidgetsService.removeAt(frame.index); return }
        if (noteRoot.d.collapsed) frame.save({ collapsed: false })  // expand so the dialog fits
        confirming = true
    }

    // ── Export to .txt via the in-board save dialog ─────────────────────
    // Opens the macOS-style picker hosted by WidgetsWindow (NoteExportPicker)
    // instead of the old zenity dialog, which — layer-shell overlays painting
    // above normal windows — could only be shown by hiding the whole board.
    // `closeAfter` is set when the export comes from the close-confirm dialog:
    // the board deletes the note only once the file is actually written.
    function exportNote(closeAfter) {
        let ord = WidgetsService.noteOrdinal(frame ? frame.index : -1)
        frame.save({ content: body.text })
        frame.winRef.openNoteExport(frame.index, "notes-" + ord + ".txt",
                                    body.getText(0, body.length), !!closeAfter)
    }
    Flickable {
        id: bodyFlick
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        boundsMovement: Flickable.FollowBoundsBehavior
        flickDeceleration: 6000
        maximumFlickVelocity: 6000
        rebound: Transition {
            SpringAnimation {
                properties: "x,y"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
        }

        // Kinetic scroll (kinetic.js) — same feel as the emoji/nc lists.
        property var _ks: ({})
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (ev) => {
                bfGlide.stop()
                if (Kinetic.onWheel(bodyFlick, ev, bodyFlick._ks, { gain: 60 }))
                    bfEndTimer.restart()
            }
        }
        Timer {
            id: bfEndTimer
            interval: 48
            onTriggered: {
                let g = Kinetic.fling(bodyFlick, bodyFlick._ks, {})
                if (g) { bfGlide.from = g.from; bfGlide.to = g.to; bfGlide.restart() }
            }
        }
        SpringAnimation {
            id: bfGlide
            target: bodyFlick
            property: "contentY"
            spring: 18
            damping: ThemeService.momentumDamping
            epsilon: 0.25
        }

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

            Component.onCompleted: text = noteRoot._stripFamily(noteRoot.d.content || "")
            Connections {
                target: noteRoot
                function onDChanged() {
                    // Only resync the body from stored data on a genuine
                    // *external* content change — never while the user is
                    // editing, and ignore HTML re-serialization noise (compare
                    // plain text). Otherwise every autosave / font / colour /
                    // collapse change would unnecessarily reparse the document.
                    if (body.activeFocus) return
                    if (noteRoot._plain(body.text) !== noteRoot._plain(noteRoot.d.content || "")) {
                        noteRoot._restoring = true
                        body.text = noteRoot._stripFamily(noteRoot.d.content || "")
                        noteRoot._restoring = false
                    }
                }
                // Choosing a new font: re-parse the document with the baked
                // font-family stripped, so the new base font.family restyles the
                // WHOLE note (including already-loaded text). Runs even while the
                // note is focused — the editor changes the font while the note
                // still holds focus, and a plain rebind doesn't restyle a loaded
                // document. Cursor jumps to the end (acceptable for a deliberate
                // font change).
                function onFontFamilyChanged() {
                    let h = noteRoot._stripFamily(body.text)
                    noteRoot._restoring = true
                    body.text = h
                    body.cursorPosition = body.length
                    noteRoot._restoring = false
                    frame.save({ content: h })
                }
            }

            onActiveFocusChanged: {
                if (activeFocus && frame) frame.bringToFront()
                else if (frame) frame.save({ content: text })
            }
            onTextChanged: {
                saveTimer.restart()
            }

            // ── Formatting shortcuts ────────────────────────────────────────
            // Ctrl+B/I/U and Ctrl+Shift+S (strikethrough) restyle the current
            // selection via cursorSelection (Qt 6.7+). Ctrl+± grows/shrinks the
            // selection's per-run size, or the note's base size when nothing is
            // selected. Ctrl+S opens the save-to-file dialog (the note content
            // itself autosaves continuously). cursorSelection.font applies one
            // uniform font to the whole selection, so a mixed-format selection
            // is unified — fine for a sticky note, and Ctrl+Z undoes it.
            function restyleSelection(mut) {
                if (selectionStart === selectionEnd) return
                let f = cursorSelection.font
                mut(f)
                cursorSelection.font = f
                saveTimer.restart()
            }
            function bumpSize(delta) {
                if (selectionStart !== selectionEnd) {
                    restyleSelection(function (f) {
                        // Per-run fonts may carry point sizes (Qt rich text);
                        // fall back through pt→px before the note's base size.
                        let px = f.pixelSize > 0 ? f.pixelSize
                               : (f.pointSize > 0 ? Math.round(f.pointSize * 96 / 72)
                                                  : noteRoot.fontSize)
                        f.pixelSize = Math.max(WidgetsService.minFont,
                                      Math.min(WidgetsService.maxFont, px + delta))
                    })
                } else {
                    let v = Math.max(WidgetsService.minFont,
                            Math.min(WidgetsService.maxFont, noteRoot.fontSize + delta))
                    frame.save({ fontSize: v })
                }
            }
            Keys.onPressed: (ev) => {
                if (!(ev.modifiers & Qt.ControlModifier)) return
                const shift = ev.modifiers & Qt.ShiftModifier
                switch (ev.key) {
                case Qt.Key_B:
                    if (shift) return
                    body.restyleSelection(f => f.bold = !f.bold); ev.accepted = true; break
                case Qt.Key_I:
                    if (shift) return
                    body.restyleSelection(f => f.italic = !f.italic); ev.accepted = true; break
                case Qt.Key_U:
                    if (shift) return
                    body.restyleSelection(f => f.underline = !f.underline); ev.accepted = true; break
                case Qt.Key_S:
                    if (shift) body.restyleSelection(f => f.strikeout = !f.strikeout)
                    else { saveTimer.stop(); noteRoot.exportNote(false) }
                    ev.accepted = true; break
                // "+" usually needs Shift, so accept both = and + (and _ / -).
                case Qt.Key_Plus: case Qt.Key_Equal:
                    body.bumpSize(1); ev.accepted = true; break
                case Qt.Key_Minus: case Qt.Key_Underscore:
                    body.bumpSize(-1); ev.accepted = true; break
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
        id: dialBtn
        property string label: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        height: 30; radius: 8
        color: primary ? (dbHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85))
                       : (dbHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09))
        scale: dialMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent; text: label
            color: danger ? "#ff6b6b" : "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 12
            font.weight: primary ? Font.Medium : Font.Normal
        }
        HoverHandler { id: dbHover }
        MouseArea { id: dialMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: dialBtn.clicked() }
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
