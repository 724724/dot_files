import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

// Full-screen macOS-style widget board. Mirrors the launchpad pattern: a
// WlrLayer.Overlay panel with a dark veil; Hyprland's `layerrule blur` on the
// qs-widgets namespace blurs the workspace windows behind it so they appear
// "covered" without being closed.
//
// reopenRequested is emitted after a GTK file dialog finishes — layer-shell
// overlays always paint above normal windows, so a note's export/import picker
// can only be seen if we hide the board first and reopen it afterwards.
PanelWindow {
    id: win

    property bool show: false
    signal closeRequested
    signal reopenRequested

    property bool _surfaceVisible: false
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            _surfaceVisible = true
            unmapTimer.stop()
            board.forceActiveFocus()
        } else {
            board.showGallery = false
            unmapTimer.restart()
        }
    }

    Timer { id: unmapTimer; interval: 260; onTriggered: win._surfaceVisible = false }

    WlrLayershell.namespace: "qs-widgets"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: win.show ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    FocusScope {
        id: board
        anchors.fill: parent
        focus: true

        property int topZ: WidgetsService.widgets.count + 10
        property bool showGallery: false
        property string galleryStage: ""   // "" = app list, "clock" = layouts

        // Right-click context menu + editor state.
        property int ctxIndex: -1
        property real ctxX: 0
        property real ctxY: 0
        property int editIndex: -1
        property int viewIndex: -1   // reminders "View All"

        function openContext(index, x, y) { ctxIndex = index; ctxX = x; ctxY = y }
        function closeContext() { ctxIndex = -1 }
        function openEditor(index) { ctxIndex = -1; editIndex = index }
        function closeEditor() { editIndex = -1 }
        function openView(index) { ctxIndex = -1; viewIndex = index }
        function closeView() { viewIndex = -1 }

        opacity: win.show ? 1.0 : 0.0
        scale: win.show ? 1.0 : 0.98
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: {
            if (board.ctxIndex >= 0) board.closeContext()
            else if (board.viewIndex >= 0) board.closeView()
            else if (board.editIndex >= 0) board.closeEditor()
            else if (board.showGallery) board.showGallery = false
            else win.closeRequested()
        }
        Keys.onPressed: (e) => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) {
                WidgetsService.addWidget("note", board.width / 2 - 120, board.height / 2 - 120)
                e.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: { board.forceActiveFocus(); board.showGallery = false }
            onDoubleClicked: (m) => WidgetsService.addWidget("note", m.x - 120, m.y - 120)
        }

        // ── Widgets ──────────────────────────────────────────────────────
        Repeater {
            model: WidgetsService.widgets
            delegate: WidgetFrame {
                boardItem: board
                winRef: win
            }
        }

        // ── Floating toolbar ───────────────────────────────────────────────
        Rectangle {
            id: toolbar
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            height: 46
            width: toolbarRow.width + 28
            radius: 23
            color: Qt.rgba(1, 1, 1, 0.12)
            border.color: Qt.rgba(1, 1, 1, 0.18)
            border.width: 1
            z: 100000

            Row {
                id: toolbarRow
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: addRow.width + 22
                    height: 32
                    radius: 16
                    color: board.showGallery ? Qt.rgba(1, 1, 1, 0.26)
                                             : (addHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+"; color: "#ffffff"
                            font.family: "SF Pro Display"; font.pixelSize: 19; font.weight: Font.Medium
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add Widget"; color: "#ffffff"
                            font.family: "SF Pro Display"; font.pixelSize: 14
                        }
                    }
                    HoverHandler { id: addHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { board.galleryStage = ""; board.showGallery = !board.showGallery }
                    }
                }

                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 22; color: Qt.rgba(1, 1, 1, 0.18) }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 16
                    color: closeHover.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 14 }
                    HoverHandler { id: closeHover }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: win.closeRequested() }
                }
            }
        }

        // ── Widget gallery (add menu) ──────────────────────────────────────
        Rectangle {
            id: gallery
            visible: board.showGallery
            anchors.top: toolbar.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            width: galleryCol.width + 28
            height: galleryCol.height + 24
            radius: 18
            color: Qt.rgba(0.10, 0.10, 0.12, 0.92)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            z: 100000

            Column {
                id: galleryCol
                anchors.centerIn: parent
                spacing: 12

                // Stage 1: pick an app
                Row {
                    visible: board.galleryStage === ""
                    spacing: 12
                    GalleryCard { label: "Clock";     kind: "clock" }
                    GalleryCard { label: "Note";      kind: "note" }
                    GalleryCard { label: "Weather";   kind: "weather" }
                    GalleryCard { label: "Reminders"; kind: "reminders" }
                }

                // Stage 2: pick a clock layout
                Column {
                    visible: board.galleryStage === "clock"
                    spacing: 10
                    Row {
                        spacing: 8
                        Text {
                            text: "‹ Back"; color: Qt.rgba(1, 1, 1, 0.7)
                            font.family: "SF Pro Display"; font.pixelSize: 13
                            MouseArea { anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: board.galleryStage = "" }
                        }
                        Text {
                            text: "Choose a clock layout"; color: "#ffffff"
                            font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        spacing: 12
                        ClockLayoutCard { layoutId: 1 }
                        ClockLayoutCard { layoutId: 2 }
                        ClockLayoutCard { layoutId: 3 }
                        ClockLayoutCard { layoutId: 4 }
                        ClockLayoutCard { layoutId: 5 }
                    }
                }

                // Stage 2: pick a weather layout
                Column {
                    visible: board.galleryStage === "weather"
                    spacing: 10
                    Row {
                        spacing: 8
                        Text {
                            text: "‹ Back"; color: Qt.rgba(1, 1, 1, 0.7)
                            font.family: "SF Pro Display"; font.pixelSize: 13
                            MouseArea { anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: board.galleryStage = "" }
                        }
                        Text {
                            text: "Choose a weather layout"; color: "#ffffff"
                            font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        spacing: 12
                        WeatherLayoutCard { layoutId: 1 }
                        WeatherLayoutCard { layoutId: 2 }
                        WeatherLayoutCard { layoutId: 3 }
                        WeatherLayoutCard { layoutId: 4 }
                    }
                }

                // Stage 2: pick a reminders layout
                Column {
                    visible: board.galleryStage === "reminders"
                    spacing: 10
                    Row {
                        spacing: 8
                        Text {
                            text: "‹ Back"; color: Qt.rgba(1, 1, 1, 0.7)
                            font.family: "SF Pro Display"; font.pixelSize: 13
                            MouseArea { anchors.fill: parent; anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: board.galleryStage = "" }
                        }
                        Text {
                            text: "Choose a reminders layout"; color: "#ffffff"
                            font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        spacing: 12
                        RemindersLayoutCard { layoutId: 1 }
                        RemindersLayoutCard { layoutId: 2 }
                        RemindersLayoutCard { layoutId: 3 }
                    }
                }
            }
        }

        // ── Empty state hint ───────────────────────────────────────────────
        Text {
            anchors.centerIn: parent
            visible: WidgetsService.widgets.count === 0 && !board.showGallery
            text: "No widgets\nClick \"Add Widget\", or double-click empty space for a note"
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: "SF Pro Display"; font.pixelSize: 16; lineHeight: 1.4
        }

        // ── Right-click context menu ───────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.ctxIndex >= 0
            z: 100002
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: board.closeContext()
            }
            Rectangle {
                x: Math.max(8, Math.min(board.ctxX, board.width - width - 8))
                y: Math.max(8, Math.min(board.ctxY, board.height - height - 8))
                width: 156
                height: menuCol.implicitHeight + 10
                radius: 11
                color: Qt.rgba(0.14, 0.14, 0.16, 0.97)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                Column {
                    id: menuCol
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    CtxRow {
                        label: "View All"
                        visible: WidgetsService.typeAt(board.ctxIndex) === "reminders"
                        onTriggered: board.openView(board.ctxIndex)
                    }
                    CtxRow {
                        label: "Edit…"
                        enabled: WidgetsService.typeAt(board.ctxIndex) === "clock"
                              || WidgetsService.typeAt(board.ctxIndex) === "weather"
                              || WidgetsService.typeAt(board.ctxIndex) === "reminders"
                              || WidgetsService.typeAt(board.ctxIndex) === "note"
                        onTriggered: board.openEditor(board.ctxIndex)
                    }
                    CtxRow {
                        label: "Delete"
                        danger: true
                        onTriggered: { let i = board.ctxIndex; board.closeContext(); WidgetsService.removeAt(i) }
                    }
                }
            }
        }

        // ── Editor (modal) ─────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.editIndex >= 0
            z: 100003
            MouseArea { anchors.fill: parent; onClicked: board.closeEditor() }
            Rectangle {
                anchors.centerIn: parent
                width: 484
                height: editCol.implicitHeight + 28
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                MouseArea { anchors.fill: parent }   // absorb clicks inside the panel
                Column {
                    id: editCol
                    anchors.centerIn: parent
                    width: parent.width - 44
                    spacing: 16
                    Loader {
                        id: editLoader
                        width: parent.width
                        sourceComponent: {
                            if (board.editIndex < 0) return noOptionsComp
                            let t = WidgetsService.typeAt(board.editIndex)
                            if (t === "clock") return clockEditorComp
                            if (t === "weather") return weatherEditorComp
                            if (t === "reminders") return remindersEditorComp
                            if (t === "note") return noteEditorComp
                            return noOptionsComp
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 78; height: 32; radius: 9
                        color: doneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                        Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"
                               font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                        HoverHandler { id: doneHover }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: board.closeEditor() }
                    }
                }
                Component { id: clockEditorComp; ClockEditor { index: board.editIndex } }
                Component { id: weatherEditorComp; WeatherEditor { index: board.editIndex } }
                Component { id: remindersEditorComp; RemindersEditor { index: board.editIndex } }
                Component { id: noteEditorComp; NoteEditor { index: board.editIndex } }
                Component {
                    id: noOptionsComp
                    Text { text: "No editable options for this widget."
                           color: Qt.rgba(1, 1, 1, 0.6); font.family: "SF Pro Display"; font.pixelSize: 14 }
                }
            }
        }

        // ── Reminders "View All" (modal) ───────────────────────────────────
        Item {
            anchors.fill: parent
            visible: board.viewIndex >= 0
            z: 100003
            MouseArea { anchors.fill: parent; onClicked: board.closeView() }
            Rectangle {
                anchors.centerIn: parent
                width: 452
                height: viewCol.implicitHeight + 28
                radius: 18
                color: Qt.rgba(0.10, 0.10, 0.12, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                MouseArea { anchors.fill: parent }
                Column {
                    id: viewCol
                    anchors.centerIn: parent
                    width: parent.width - 44
                    spacing: 14
                    RemindersViewer {
                        width: parent.width
                        index: board.viewIndex
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 78; height: 32; radius: 9
                        color: vDoneHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85)
                        Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"
                               font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                        HoverHandler { id: vDoneHover }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: board.closeView() }
                    }
                }
            }
        }
    }

    // ── Inline components ────────────────────────────────────────────────
    component GalleryCard: Rectangle {
        id: gcard
        property string label: ""
        property string kind: "note"
        width: 88; height: 84; radius: 14
        color: gcHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Column {
            anchors.centerIn: parent
            spacing: 9
            // Clock shows a real analog face; others use clean Nerd glyphs.
            Item {
                width: 44; height: 44
                anchors.horizontalCenter: parent.horizontalCenter
                AnalogClock {
                    visible: gcard.kind === "clock"
                    anchors.fill: parent
                    fixedDate: new Date(2024, 0, 1, 10, 9, 36); active: false
                    faceColor: "#ffffff"; tickColor: "#1c1c1e"; handColor: "#1c1c1e"
                }
                Text {
                    visible: gcard.kind !== "clock"
                    anchors.centerIn: parent
                    text: gcard.kind === "note" ? "\uf249"
                        : gcard.kind === "weather" ? "\ue302"
                        : "\uf046"
                    color: "#ffffff"
                    font.family: WeatherService.iconFont
                    font.pixelSize: 32
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: gcard.label
                   color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 12 }
        }
        HoverHandler { id: gcHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // Clock / Weather / Reminders offer layouts → drill into stage 2.
                if (gcard.kind === "clock" || gcard.kind === "weather" || gcard.kind === "reminders") { board.galleryStage = gcard.kind; return }
                WidgetsService.addWidget(gcard.kind, board.width / 2 - 130, board.height / 2 - 120)
                board.showGallery = false
            }
        }
    }

    // A clock-layout preview card (stage 2 of the gallery).
    component ClockLayoutCard: Rectangle {
        id: clc
        property int layoutId: 1
        readonly property var names: ["Digital", "World Row", "World 2×2", "Numbers", "Minimal"]
        readonly property var previewDate: new Date(2024, 0, 1, 10, 9, 36)
        width: layoutId === 2 ? 150 : 96
        height: 116
        radius: 14
        color: clcHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            // Mini preview
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: clc.layoutId === 2 ? 130 : 72
                height: 72
                radius: 12
                clip: true
                color: clc.layoutId === 1 ? "#ffffff"
                     : clc.layoutId === 4 ? Qt.rgba(0.84, 0.89, 0.96, 0.55) : "#1c1c1e"
                border.color: Qt.rgba(0, 0, 0, 0.1); border.width: clc.layoutId === 1 || clc.layoutId === 4 ? 1 : 0

                // 1: digital text
                Text {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 1
                    text: "9:41"; color: "#101012"
                    font.family: "SF Pro Display"; font.weight: Font.Bold; font.pixelSize: 26
                }
                // 2: row of mini clocks
                Row {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 2
                    spacing: 6
                    Repeater {
                        model: 4
                        delegate: AnalogClock {
                            width: 26; height: 26
                            fixedDate: clc.previewDate; active: false
                            faceColor: "#ffffff"; tickColor: "#1c1c1e"; handColor: "#1c1c1e"
                        }
                    }
                }
                // 3: 2x2 mini clocks
                Grid {
                    anchors.centerIn: parent
                    visible: clc.layoutId === 3
                    columns: 2; rows: 2; rowSpacing: 6; columnSpacing: 6
                    Repeater {
                        model: 4
                        delegate: AnalogClock {
                            width: 28; height: 28
                            fixedDate: clc.previewDate; active: false
                            faceColor: "#ffffff"; tickColor: "#1c1c1e"; handColor: "#1c1c1e"
                        }
                    }
                }
                // 4 & 5: single clock
                AnalogClock {
                    anchors.fill: parent; anchors.margins: 8
                    visible: clc.layoutId === 4
                    fixedDate: clc.previewDate; active: false
                    faceColor: Qt.rgba(1, 1, 1, 0.92)
                    tickColor: "#2a2a2e"; showNumbers: false; handColor: "#1c1c1e"
                }
                AnalogClock {
                    anchors.fill: parent; anchors.margins: 8
                    visible: clc.layoutId === 5
                    fixedDate: clc.previewDate; active: false
                    tickColor: Qt.rgba(1, 1, 1, 0.55); handColor: "#f2f2f7"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: clc.names[clc.layoutId - 1]
                color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11
            }
        }

        HoverHandler { id: clcHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                WidgetsService.addWidget("clock", board.width / 2 - 110, board.height / 2 - 110,
                    { layout: clc.layoutId, faces: WidgetsService.defaultClockFaces(clc.layoutId) })
                board.showGallery = false
                board.galleryStage = ""
            }
        }
    }

    // A weather-layout preview card (stage 2 of the gallery).
    component WeatherLayoutCard: Rectangle {
        id: wlc
        property int layoutId: 1
        readonly property var names: ["Large", "Hourly", "Conditions", "Sun"]
        width: 96
        height: 116
        radius: 14
        color: wlcHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72; radius: 12; clip: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a74d4" }
                    GradientStop { position: 1.0; color: "#73b7ef" }
                }
                // tiny representative content
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 6
                       text: "18°"; color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 16; font.weight: Font.Light }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6
                       text: wlc.layoutId === 4 ? "" : "\ue30d"; color: "#ffffff"
                       font.family: WeatherService.iconFont; font.pixelSize: 14 }
                // layout-specific hint
                Row {
                    visible: wlc.layoutId === 1 || wlc.layoutId === 2
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 8
                    spacing: 5
                    Repeater { model: 4; delegate: Rectangle { width: 4; height: 4; radius: 2; color: Qt.rgba(1,1,1,0.8) } }
                }
                Canvas {
                    visible: wlc.layoutId === 4
                    anchors.fill: parent; anchors.margins: 10
                    onPaint: {
                        let ctx = getContext("2d"); ctx.reset()
                        let w = width, h = height, hz = h * 0.7
                        ctx.beginPath()
                        for (let i = 0; i <= 24; i++) { let t = i/24; let x=t*w; let y=hz-Math.sin(t*Math.PI)*h*0.5; i?ctx.lineTo(x,y):ctx.moveTo(x,y) }
                        ctx.strokeStyle = Qt.rgba(1,1,1,0.5); ctx.lineWidth = 1.2; ctx.stroke()
                        ctx.beginPath(); ctx.arc(w*0.6, hz-Math.sin(0.6*Math.PI)*h*0.5, 3, 0, 2*Math.PI); ctx.fillStyle="#ffd34d"; ctx.fill()
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: wlc.names[wlc.layoutId - 1]
                   color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: wlcHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                WidgetsService.addWidget("weather", board.width / 2 - 130, board.height / 2 - 120, { layout: wlc.layoutId })
                board.showGallery = false
                board.galleryStage = ""
            }
        }
    }

    // A reminders-layout preview card (stage 2 of the gallery).
    component RemindersLayoutCard: Rectangle {
        id: rlc
        property int layoutId: 2
        readonly property var names: ["Small", "Medium", "Large"]
        readonly property color accent: ThemeService.accent("blue")
        width: 96
        height: 116
        radius: 14
        color: rlcHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 8
            // mini themed card preview
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72; radius: 12; clip: true
                color: ThemeService.cardBg
                border.color: ThemeService.separator; border.width: 1
                Column {
                    anchors.fill: parent; anchors.margins: 8
                    spacing: 5
                    Row {
                        spacing: 4
                        Rectangle { width: 12; height: 12; radius: 6; color: rlc.accent }
                        Text { text: "3"; color: ThemeService.label; font.family: "SF Pro Display"
                               font.pixelSize: 12; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Repeater {
                        model: 3
                        delegate: Row {
                            spacing: 4
                            Rectangle { width: 8; height: 8; radius: 4; color: "transparent"
                                        border.color: rlc.accent; border.width: 1.4; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle { width: 34; height: 4; radius: 2; color: ThemeService.separator
                                        anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: rlc.names[rlc.layoutId - 1]
                   color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11 }
        }

        HoverHandler { id: rlcHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                WidgetsService.addWidget("reminders", board.width / 2 - 130, board.height / 2 - 100, { layout: rlc.layoutId })
                board.showGallery = false
                board.galleryStage = ""
            }
        }
    }

    // A row in the right-click context menu.
    component CtxRow: Rectangle {
        id: cr
        property string label: ""
        property bool danger: false
        signal triggered()
        width: parent ? parent.width : 150
        height: 34
        color: crHover.hovered && enabled ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        opacity: enabled ? 1.0 : 0.4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 14
            text: cr.label
            color: cr.danger ? "#ff6b6b" : "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 13
        }
        HoverHandler { id: crHover; enabled: cr.enabled }
        MouseArea {
            anchors.fill: parent
            enabled: cr.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: cr.triggered()
        }
    }
}
