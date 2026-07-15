import QtQuick

Rectangle {
    id: root

    property bool hovered: false
    // Lit like a hover while an attached popup is open (set by ClockWidget).
    property bool active: false
    property bool pressed: false
    // Pills that respond to clicks opt in to a pointing-hand cursor on hover.
    property bool clickable: false

    color: (hovered || active) ? ThemeService.pillBgHover : ThemeService.pillBg
    border.color: (hovered || active) ? ThemeService.pillBorderHover : ThemeService.pillBorder
    border.width: 1
    radius: 999
    scale: pressed ? ThemeService.pressScale : 1
    transformOrigin: Item.Center

    Behavior on scale { AppleSpring { spring: 13 } }

    HoverHandler {
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: root.hovered = hovered
    }
}
