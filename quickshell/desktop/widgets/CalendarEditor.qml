import QtQuick
import QtQuick.Controls

// Editor body for a calendar widget (right-click → Edit).
//   • Switch the layout (Small / Medium / Large).
//   • Manage ICS subscriptions (shared by all calendar widgets): paste a
//     Google "secret iCal address" or an iCloud public-share (webcal://) link.
//     Click a source's color dot to cycle its Apple accent color.
Item {
    id: ed
    property int index: -1

    implicitWidth: 460
    implicitHeight: col.implicitHeight

    property int layout: 2
    readonly property var layoutNames: ["Small", "Medium", "Large"]

    onIndexChanged: ed.reload()
    function reload() {
        if (index < 0) return
        let d = WidgetsService.getData(index)
        layout = d.layout || 2
    }
    function pickLayout(n) { WidgetsService.setCalendarLayout(index, n); ed.layout = n }

    function addSource() {
        if (!urlField.text.trim()) return
        CalendarService.addSource(nameField.text, urlField.text)
        nameField.text = ""
        urlField.text = ""
    }

    // Which source's color palette is expanded (-1 = none).
    property int paletteIndex: -1
    function pickColor(i, c) {
        CalendarService.setSourceColor(i, c)
        ed.paletteIndex = -1
    }
    function validHex(t) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(t.trim()) }

    Column {
        id: col
        width: parent.width
        spacing: 16

        Text { text: "Calendar"; color: "#ffffff"; font.family: "SF Pro Display"
               font.pixelSize: 18; font.weight: Font.DemiBold }

        // ── Layout chooser ─────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Style"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        readonly property int n: index + 1
                        width: 92; height: 32; radius: 9
                        color: ed.layout === n ? Qt.rgba(0.30, 0.52, 0.95, 0.9)
                             : (lh.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                        scale: layoutMa.pressed ? ThemeService.pressScale : 1.0
                        Behavior on scale { AppleSpring { spring: 18 } }
                        Text { anchors.centerIn: parent; text: ed.layoutNames[parent.n - 1]
                               color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11 }
                        HoverHandler { id: lh }
                        MouseArea { id: layoutMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.pickLayout(parent.n) }
                    }
                }
            }
        }

        // ── Subscriptions ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Calendars (ICS subscriptions)"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }

            Repeater {
                model: CalendarService.sources
                delegate: Column {
                    id: srcRow
                    required property int index
                    required property var modelData
                    width: parent.width
                    spacing: 4

                    Rectangle {
                        width: parent.width; height: 46; radius: 10
                        color: srHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)

                        // Color dot — click to open the palette below the row.
                        Rectangle {
                            id: dot
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 8
                            color: ThemeService.resolveAccent(srcRow.modelData.color)
                            border.color: ed.paletteIndex === srcRow.index
                                ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.25)
                            border.width: ed.paletteIndex === srcRow.index ? 2 : 1
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ed.paletteIndex =
                                    (ed.paletteIndex === srcRow.index) ? -1 : srcRow.index
                            }
                        }
                        Column {
                            anchors.left: dot.right; anchors.leftMargin: 10
                            anchors.right: parent.right; anchors.rightMargin: 46
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Text { width: parent.width; elide: Text.ElideRight
                                   text: srcRow.modelData.name; color: "#ffffff"
                                   font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideMiddle
                                   text: srcRow.modelData.url; color: Qt.rgba(1, 1, 1, 0.45)
                                   font.family: "SF Pro Display"; font.pixelSize: 10 }
                        }
                        // Trash (hover)
                        Rectangle {
                            visible: srHover.hovered || trashHover.hovered
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 15
                            color: trashHover.hovered ? "#ff4d4d" : Qt.rgba(0.9, 0.3, 0.3, 0.85)
                            Text { anchors.centerIn: parent; text: "\uf1f8"; color: "#ffffff"
                                   font.family: ThemeService.iconFont; font.pixelSize: 13 }
                            HoverHandler { id: trashHover }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { ed.paletteIndex = -1; CalendarService.removeSource(srcRow.index) } }
                        }
                        HoverHandler { id: srHover }
                    }

                    // ── Color palette: Apple accent swatches + hex input ───
                    Rectangle {
                        visible: ed.paletteIndex === srcRow.index
                        width: parent.width
                        height: palCol.height + 20
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1

                        Column {
                            id: palCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                            spacing: 10

                            Flow {
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    model: ThemeService.accentNames
                                    delegate: Rectangle {
                                        id: swatch
                                        required property string modelData
                                        readonly property bool selected: srcRow.modelData.color === modelData
                                        width: 24; height: 24; radius: 12
                                        color: ThemeService.accent(modelData)
                                        border.color: selected ? "#ffffff" : Qt.rgba(1, 1, 1, 0.2)
                                        border.width: selected ? 2 : 1
                                        Text { anchors.centerIn: parent; visible: swatch.selected
                                               text: "✓"; color: "#ffffff"
                                               font.pixelSize: 11; font.weight: Font.Bold }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: ed.pickColor(srcRow.index, swatch.modelData) }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8
                                Rectangle {
                                    width: parent.width - 70; height: 30; radius: 8
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    border.color: hexField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7)
                                                : (hexField.text !== "" && !ed.validHex(hexField.text))
                                                    ? Qt.rgba(1, 0.35, 0.3, 0.8) : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1
                                    TextField {
                                        id: hexField
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 6
                                        background: null; color: "#ffffff"
                                        text: srcRow.modelData.color.charAt(0) === "#" ? srcRow.modelData.color : ""
                                        placeholderText: "#RRGGBB"
                                        placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                                        font.family: "JetBrainsMono Nerd Font Propo"; font.pixelSize: 12
                                        verticalAlignment: TextInput.AlignVCenter
                                        onAccepted: if (ed.validHex(text)) ed.pickColor(srcRow.index, text.trim().toUpperCase())
                                    }
                                }
                                Rectangle {
                                    width: 62; height: 30; radius: 8
                                    color: ed.validHex(hexField.text)
                                        ? (hexApHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85))
                                        : Qt.rgba(1, 1, 1, 0.08)
                                    scale: hexApplyMa.pressed ? ThemeService.pressScale : 1.0
                                    Behavior on scale { AppleSpring { spring: 18 } }
                                    Text { anchors.centerIn: parent; text: "Apply"
                                           color: ed.validHex(hexField.text) ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                                           font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.Medium }
                                    HoverHandler { id: hexApHover }
                                    MouseArea { id: hexApplyMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: if (ed.validHex(hexField.text))
                                                    ed.pickColor(srcRow.index, hexField.text.trim().toUpperCase()) }
                                }
                            }
                        }
                    }
                }
            }

            // Add form: name + URL.
            Row {
                width: parent.width
                spacing: 8
                Rectangle {
                    width: 130; height: 36; radius: 9
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: nameField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    TextField {
                        id: nameField
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6
                        background: null; color: "#ffffff"
                        placeholderText: "Name"
                        placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "SF Pro Display"; font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                    }
                }
                Rectangle {
                    width: parent.width - 130 - 62 - 16; height: 36; radius: 9
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: urlField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    TextField {
                        id: urlField
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6
                        background: null; color: "#ffffff"
                        placeholderText: "ICS / webcal URL…"
                        placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "SF Pro Display"; font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter
                        onAccepted: ed.addSource()
                    }
                }
                Rectangle {
                    width: 62; height: 36; radius: 9
                    color: urlField.text.trim()
                        ? (addHover.hovered ? Qt.rgba(0.30, 0.52, 0.95, 1.0) : Qt.rgba(0.30, 0.52, 0.95, 0.85))
                        : Qt.rgba(1, 1, 1, 0.08)
                    scale: addSourceMa.pressed ? ThemeService.pressScale : 1.0
                    Behavior on scale { AppleSpring { spring: 18 } }
                    Text { anchors.centerIn: parent; text: "Add"
                           color: urlField.text.trim() ? "#ffffff" : Qt.rgba(1, 1, 1, 0.4)
                           font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Medium }
                    HoverHandler { id: addHover }
                    MouseArea { id: addSourceMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: ed.addSource() }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Google Calendar: Settings → your calendar → \"Secret address in iCal format\".\n"
                    + "Apple/iCloud: Calendar → share as Public Calendar → paste the webcal:// link."
                color: Qt.rgba(1, 1, 1, 0.38)
                font.family: "SF Pro Display"; font.pixelSize: 11; lineHeight: 1.25
            }
        }

        // ── Sync status + manual refresh ───────────────────────────────────
        Row {
            width: parent.width
            spacing: 10
            Rectangle {
                width: 84; height: 30; radius: 9
                color: refHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                scale: refreshMa.pressed ? ThemeService.pressScale : 1.0
                Behavior on scale { AppleSpring { spring: 18 } }
                Text { anchors.centerIn: parent
                       text: CalendarService.refreshing ? "Syncing…" : "Refresh"
                       color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 12 }
                HoverHandler { id: refHover }
                MouseArea { id: refreshMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: CalendarService.refresh() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: CalendarService.statusMsg !== "" ? CalendarService.statusMsg
                    : CalendarService.lastSync
                        ? ("Updated " + Qt.formatTime(CalendarService.lastSync, "HH:mm")
                           + " · " + CalendarService.events.length + " events")
                        : ""
                color: CalendarService.statusMsg !== "" ? "#ff8a80" : Qt.rgba(1, 1, 1, 0.45)
                font.family: "SF Pro Display"; font.pixelSize: 11
            }
        }
    }
}
