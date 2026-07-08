import QtQuick

// Lightweight floating context menu for the control-center detail panels.
// Native Qt popups don't position correctly on the wlr layer surface, so this
// renders as an in-panel overlay instead: instantiate it once at a panel's
// root (it fills the panel), then call openAt(x, y, items) with coordinates
// already mapped into that root's coordinate space.
//
//   items: [ { label, danger?: bool, action: function } ]
Item {
    id: menu
    anchors.fill: parent
    z: 9999
    visible: open

    property bool open: false
    property var items: []
    property real menuX: 0
    property real menuY: 0

    readonly property bool dark: ThemeService.isDark
    readonly property int menuWidth: 200
    readonly property int rowHeight: 34

    function openAt(px, py, menuItems) {
        items = menuItems
        let h = menuItems.length * rowHeight + 10
        // Clamp inside the panel; flip upward when it would overflow the bottom.
        menuX = Math.max(4, Math.min(px, width - menuWidth - 4))
        menuY = (py + h > height - 4) ? Math.max(4, py - h) : py
        open = true
    }
    function close() { open = false }

    // Scrim — any press outside the card (left or right) dismisses the menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: menu.close()
    }

    Rectangle {
        id: card
        x: menu.menuX
        y: menu.menuY
        width: menu.menuWidth
        height: list.implicitHeight + 10
        radius: 12
        color: menu.dark ? "#2e2e30" : "#ffffff"
        border.color: menu.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
        border.width: 1

        transformOrigin: Item.TopLeft
        scale: menu.open ? 1 : 0.92
        opacity: menu.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Column {
            id: list
            y: 5
            width: parent.width
            spacing: 0

            Repeater {
                model: menu.items
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    width: list.width
                    height: menu.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        radius: 7
                        color: itemMa.containsMouse
                            ? (rowItem.modelData.danger
                                ? Qt.rgba(1, 69 / 255, 58 / 255, menu.dark ? 0.22 : 0.12)
                                : (menu.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)))
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 14
                            right: parent.right
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: rowItem.modelData.label
                        color: rowItem.modelData.danger
                            ? "#FF453A"
                            : (menu.dark ? "#f0f3f6" : "#1c1c1e")
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menu.close()
                            if (rowItem.modelData.action) rowItem.modelData.action()
                        }
                    }
                }
            }
        }
    }
}
