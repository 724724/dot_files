pragma ComponentBehavior: Bound

import QtQuick

// A narrow input ring around floating capture chrome. It prevents a tiny
// pointer overshoot from falling through to the full-screen selection canvas.
Item {
    id: root

    required property Item targetItem
    property real extent: 5
    property int cursorShape: Qt.ArrowCursor
    readonly property bool hovered: topEdge.containsMouse
        || bottomEdge.containsMouse || leftEdge.containsMouse
        || rightEdge.containsMouse

    x: targetItem.x - extent
    y: targetItem.y - extent
    width: targetItem.width + extent * 2
    height: targetItem.height + extent * 2
    visible: targetItem.visible
    enabled: visible && extent > 0

    component EdgeArea: MouseArea {
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: root.cursorShape
        onPressed: function(mouse) { mouse.accepted = true }
    }

    EdgeArea {
        id: topEdge
        x: 0; y: 0
        width: parent.width; height: root.extent
    }
    EdgeArea {
        id: bottomEdge
        x: 0; y: parent.height - root.extent
        width: parent.width; height: root.extent
    }
    EdgeArea {
        id: leftEdge
        x: 0; y: root.extent
        width: root.extent
        height: Math.max(0, parent.height - root.extent * 2)
    }
    EdgeArea {
        id: rightEdge
        x: parent.width - root.extent; y: root.extent
        width: root.extent
        height: Math.max(0, parent.height - root.extent * 2)
    }
}
