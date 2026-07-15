import QtQuick
import QtQuick.Controls

// Editor for a reminders widget (right-click → Edit): only style, title and
// accent colour. Items are added/toggled directly on the widget (click empty
// space to add, click a circle to complete).
Item {
    id: ed
    property int index: -1

    implicitWidth: 440
    implicitHeight: col.implicitHeight

    property int layout: 2
    property string title: "Reminders"
    property string accent: "blue"
    property string icon: "list"
    readonly property var layoutNames: ["Small", "Medium", "Large"]

    onIndexChanged: ed.reload()
    function reload() {
        if (index < 0) return
        let d = WidgetsService.getData(index)
        layout = d.layout || 2
        title = (d.title !== undefined) ? d.title : "Reminders"
        accent = d.accent || "blue"
        icon = d.icon || "list"
    }
    function pickLayout(n) { WidgetsService.setRemindersLayout(index, n); ed.layout = n }
    function setTitle(t)   { WidgetsService.setData(index, { title: t }); ed.title = t }
    function setAccent(a)  { WidgetsService.setData(index, { accent: a }); ed.accent = a }
    function setIcon(name) { WidgetsService.setData(index, { icon: name }); ed.icon = name }

    Column {
        id: col
        width: parent.width
        spacing: 14

        Text { text: "Reminders"; color: "#ffffff"; font.family: "SF Pro Display"
               font.pixelSize: 18; font.weight: Font.DemiBold }

        // Style
        Column {
            width: parent.width; spacing: 8
            Text { text: "Style"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Row {
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

        // Title
        Column {
            width: parent.width; spacing: 8
            Text { text: "Title"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Rectangle {
                width: parent.width; height: 36; radius: 9
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: titleField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1
                TextField {
                    id: titleField
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    background: null; color: "#ffffff"
                    placeholderText: "List name"; placeholderTextColor: Qt.rgba(1, 1, 1, 0.4)
                    font.family: "SF Pro Display"; font.pixelSize: 13
                    text: ed.title
                    onEditingFinished: ed.setTitle(text)
                }
            }
        }

        // Accent colour
        Column {
            width: parent.width; spacing: 8
            Text { text: "Colour"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: ThemeService.accentNames
                    delegate: Rectangle {
                        required property var modelData
                        width: 26; height: 26; radius: 13
                        color: ThemeService.accent(modelData)
                        border.color: ed.accent === modelData ? "#ffffff" : Qt.rgba(0, 0, 0, 0.2)
                        border.width: ed.accent === modelData ? 2.5 : 1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.setAccent(modelData) }
                    }
                }
            }
        }

        // Icon
        Column {
            width: parent.width; spacing: 8
            Text { text: "Icon"; color: Qt.rgba(1, 1, 1, 0.55)
                   font.family: "SF Pro Display"; font.pixelSize: 12; font.weight: Font.DemiBold }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: ThemeService.reminderIcons
                    delegate: Rectangle {
                        required property var modelData
                        width: 32; height: 32; radius: 16
                        readonly property bool sel: ed.icon === modelData.name
                        color: sel ? ThemeService.accent(ed.accent)
                             : (ic.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                        scale: iconMa.pressed ? ThemeService.pressScale : 1.0
                        Behavior on scale { AppleSpring { spring: 18 } }
                        Text { anchors.centerIn: parent; text: modelData.glyph; color: "#ffffff"
                               font.family: ThemeService.iconFont; font.pixelSize: 15 }
                        HoverHandler { id: ic }
                        MouseArea { id: iconMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: ed.setIcon(modelData.name) }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Tip: click empty space on the widget to add an item, click a circle to complete it."
            color: Qt.rgba(1, 1, 1, 0.45); font.family: "SF Pro Display"; font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
