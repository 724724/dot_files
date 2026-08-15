import QtQuick
import QtQuick.Controls

// Editor body for a clock widget (shown by WidgetsWindow when you right-click a
// clock and choose Edit). Lets you change the layout and the city/timezone of
// each face.
Item {
    id: ed
    property int index: -1

    implicitWidth: 420
    implicitHeight: col.implicitHeight

    // Local mirror of the widget data (the editor is the only writer while open).
    property int layout: 4
    property var faces: []
    readonly property int faceCount: (layout === 2 || layout === 3) ? 4 : 1
    readonly property var cityNames: {
        let a = []
        for (let i = 0; i < WidgetsService.cityPresets.length; i++) a.push(WidgetsService.cityPresets[i].name)
        return a
    }

    onIndexChanged: ed.reload()
    function reload() {
        if (index === -1) return
        let d = WidgetsService.getData(index)
        layout = d.layout || 4
        faces = (d.faces && d.faces.length) ? d.faces.slice() : [{ city: "Local", tz: 0 }]
    }
    function pickLayout(n) {
        WidgetsService.setClockLayout(index, n)
        ed.reload()
    }
    function pickCity(i, name) {
        let f = ed.faces.slice()
        f[i] = WidgetsService.faceFromName(name)
        WidgetsService.setData(index, { faces: f })
        ed.faces = f
    }

    readonly property var layoutNames: ["Digital", "World Row", "World 2×2", "Numbers", "Minimal"]

    Column {
        id: col
        width: parent.width
        spacing: 16

        Text {
            text: "Clock"
            color: "#ffffff"; font.family: "SF Pro Display"
            font.pixelSize: 18; font.weight: Font.DemiBold
        }

        // Layout chooser
        Column {
            width: parent.width
            spacing: 8
            Text { text: "Style"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        readonly property int n: index + 1
                        width: 76; height: 32; radius: 9
                        color: ed.layout === n ? Qt.rgba(0.30, 0.52, 0.95, 0.9)
                             : (lh.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                        scale: layoutMa.pressed ? ThemeService.pressScale : 1.0
                        Behavior on scale { AppleSpring { spring: 18 } }
                        Text {
                            anchors.centerIn: parent
                            text: ed.layoutNames[parent.n - 1]
                            color: "#ffffff"; font.family: "SF Pro Display"; font.pixelSize: 11
                        }
                        HoverHandler { id: lh }
                        MouseArea { id: layoutMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.pickLayout(parent.n) }
                    }
                }
            }
        }

        // Per-face city pickers
        Column {
            width: parent.width
            spacing: 10
            Text { text: ed.faceCount > 1 ? "Cities" : "City"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Repeater {
                model: ed.faceCount
                delegate: Row {
                    required property int index
                    width: col.width
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        text: ed.faceCount > 1 ? ("Clock " + (parent.index + 1)) : "City"
                        color: Qt.rgba(1, 1, 1, 0.7); font.family: "SF Pro Display"; font.pixelSize: 13
                    }
                    ComboBox {
                        id: cb
                        width: parent.width - 74
                        model: ed.cityNames
                        currentIndex: {
                            let c = (ed.faces[parent.index] && ed.faces[parent.index].city) || "Local"
                            let i = ed.cityNames.indexOf(c)
                            return i >= 0 ? i : 0
                        }
                        onActivated: (i) => ed.pickCity(parent.index, ed.cityNames[i])
                    }
                }
            }
        }
    }
}
