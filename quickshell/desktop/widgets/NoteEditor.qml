import QtQuick
import QtQuick.Controls

// Editor for a sticky note (right-click → Edit): colour, font family and base
// text size. The font list is the set of fonts actually installed on the
// system (Qt.fontFamilies()), with a filter box. Per-run sizes set with
Item {
    id: ed
    property int index: -1

    implicitWidth: 440
    implicitHeight: col.implicitHeight

    property string swatch: WidgetsService.palette[0]
    property string fontFamily: "SF Pro Display"
    property int fontSize: 15
    property string query: ""

    readonly property var allFonts: Qt.fontFamilies()
    readonly property var filtered: {
        let q = query.trim().toLowerCase()
        if (!q) return allFonts
        let out = []
        for (let i = 0; i < allFonts.length; i++)
            if (allFonts[i].toLowerCase().indexOf(q) >= 0) out.push(allFonts[i])
        return out
    }

    onIndexChanged: ed.reload()
    function reload() {
        if (index < 0) return
        let d = WidgetsService.getData(index)
        swatch = d.swatch || WidgetsService.palette[0]
        fontFamily = d.fontFamily || "SF Pro Display"
        fontSize = (d.fontSize !== undefined) ? d.fontSize : 15
    }
    function setSwatch(c) { WidgetsService.setData(index, { swatch: c }); ed.swatch = c }
    function setFamily(f) { WidgetsService.setData(index, { fontFamily: f }); ed.fontFamily = f }
    function setSize(n) {
        let v = Math.max(WidgetsService.minFont, Math.min(WidgetsService.maxFont, n))
        WidgetsService.setData(index, { fontSize: v }); ed.fontSize = v
    }

    component StepBtn: Rectangle {
        id: stepBtn
        property string label: ""
        signal clicked()
        width: 32; height: 32; radius: 8
        color: sbHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09)
        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
        scale: stepMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text { anchors.centerIn: parent; text: label; color: "#ffffff"
               font.family: "SF Pro Display"; font.pixelSize: 18 }
        HoverHandler { id: sbHover }
        MouseArea { id: stepMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: stepBtn.clicked() }
    }

    Column {
        id: col
        width: parent.width
        spacing: 16

        Text { text: "Note"; color: "#ffffff"; font.family: "SF Pro Display"
               font.pixelSize: 18; font.weight: Font.DemiBold }

        // ── Colour ──────────────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 8
            Text { text: "Colour"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: WidgetsService.palette
                    delegate: Rectangle {
                        required property var modelData
                        width: 30; height: 30; radius: 8
                        color: modelData
                        border.color: ed.swatch === modelData ? "#ffffff" : Qt.rgba(0, 0, 0, 0.2)
                        border.width: ed.swatch === modelData ? 2.5 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.setSwatch(modelData) }
                    }
                }
            }
        }

        // ── Base text size ──────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 8
            Text { text: "Text size"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Row {
                spacing: 10
                StepBtn { label: "−"; onClicked: ed.setSize(ed.fontSize - 1) }
                Rectangle {
                    width: 56; height: 32; radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                    Text { anchors.centerIn: parent; text: ed.fontSize + " px"; color: "#ffffff"
                           font.family: "SF Pro Display"; font.pixelSize: 13 }
                }
                StepBtn { label: "+"; onClicked: ed.setSize(ed.fontSize + 1) }
            }
        }

        // ── Font family (installed fonts) ────────────────────────────────────
        Column {
            width: parent.width; spacing: 8
            Row {
                width: parent.width; spacing: 8
                Text { text: "Font"; color: Qt.rgba(1, 1, 1, 0.55)
                       font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold
                       anchors.verticalCenter: parent.verticalCenter }
                Text { text: ed.fontFamily; color: Qt.rgba(1, 1, 1, 0.85)
                       font.family: ed.fontFamily; font.pixelSize: 12; elide: Text.ElideRight
                       width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter }
            }
            // Filter box
            Rectangle {
                width: parent.width; height: 32; radius: 8
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: searchField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1
                TextField {
                    id: searchField
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    background: null; color: "#ffffff"
                    placeholderText: "Search fonts…"; placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                    font.family: "SF Pro Display"; font.pixelSize: 13
                    onTextChanged: ed.query = text
                }
            }
            // Scrollable list of installed families, each shown in its own font.
            Rectangle {
                width: parent.width; height: 184; radius: 10; clip: true
                color: Qt.rgba(1, 1, 1, 0.05); border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                ListView {
                    id: fontList
                    anchors.fill: parent; anchors.margins: 4
                    clip: true
                    model: ed.filtered
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    boundsMovement: Flickable.FollowBoundsBehavior
                    rebound: Transition {
                        SpringAnimation {
                            properties: "x,y"
                            spring: 18
                            damping: ThemeService.momentumDamping
                            epsilon: 0.25
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 32; radius: 7
                        readonly property bool sel: ed.fontFamily === modelData
                        color: sel ? Qt.rgba(0.30, 0.52, 0.95, 0.85)
                             : (fhHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.right: parent.right; anchors.rightMargin: 10
                            text: modelData; color: "#ffffff"
                            font.family: modelData; font.pixelSize: 14; elide: Text.ElideRight
                        }
                        HoverHandler { id: fhHover }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.setFamily(modelData) }
                    }
                }
            }
        }
    }
}
