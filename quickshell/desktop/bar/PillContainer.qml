import QtQuick

Rectangle {
    id: root

    property bool hovered: false
    // Lit like a hover while an attached popup is open (set by ClockWidget).
    property bool active: false
    // Pills that respond to clicks opt in to a pointing-hand cursor on hover.
    property bool clickable: false

    color: (hovered || active)
        ? Qt.rgba(40/255, 50/255, 60/255, 0.4)
        : Qt.rgba(30/255, 40/255, 50/255, 0.25)
    border.color: (hovered || active)
        ? Qt.rgba(100/255, 210/255, 180/255, 0.4)
        : Qt.rgba(100/255, 210/255, 180/255, 0.3)
    border.width: 1
    radius: 999

    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }

    HoverHandler {
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: root.hovered = hovered
    }
}
