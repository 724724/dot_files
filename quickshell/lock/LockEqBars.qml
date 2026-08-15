pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    property var levels: []
    property color barColor: "#ffffff"
    property bool active: false
    property int bars: 8
    property real barWidth: 2
    property real gap: 1
    property real maxHeight: 20
    readonly property real dotSize: Math.max(2, barWidth)

    implicitWidth: bars * barWidth + (bars - 1) * gap
    implicitHeight: maxHeight

    Row {
        anchors.centerIn: parent
        spacing: root.gap

        Repeater {
            model: root.bars

            delegate: Rectangle {
                id: bar
                required property int index
                readonly property real level: {
                    if (!root.active || !root.levels || index >= root.levels.length)
                        return 0
                    return Math.max(0, Math.min(1, Number(root.levels[index]) || 0))
                }

                anchors.verticalCenter: parent.verticalCenter
                width: root.barWidth
                height: root.active
                    ? Math.max(root.dotSize, level * root.maxHeight)
                    : root.dotSize
                radius: width / 2
                color: root.barColor
                opacity: root.active ? 0.5 + 0.5 * level : 0.5

                Behavior on height {
                    NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }
}
