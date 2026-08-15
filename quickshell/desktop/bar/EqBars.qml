import QtQuick

// Compact spectrum meter that sits right of the media pill's title.
//
// Bars are centred vertically and grow symmetrically with each band's level.
// When playback stops every bar collapses to a dot, so the meter stays present
// (and the pill keeps its width) instead of popping in and out.
Item {
    id: root

    property var levels: []
    property color barColor: "#ffffff"
    property bool active: false

    property int bars: 8
    property real barWidth: 2
    property real gap: 1.0
    property real maxHeight: 20
    readonly property real dotSize: 2

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
                    if (!root.active) return 0
                    let l = root.levels
                    if (!l || bar.index >= l.length) return 0
                    let v = l[bar.index]
                    return v > 1 ? 1 : (v < 0 ? 0 : v)
                }

                anchors.verticalCenter: parent.verticalCenter
                width: root.barWidth
                height: root.active
                    ? Math.max(root.dotSize, bar.level * root.maxHeight)
                    : root.dotSize
                radius: root.barWidth / 2
                color: root.barColor
                // Louder bands read as more solid, so the meter has depth
                // rather than looking like 14 identical ticks.
                opacity: root.active ? (0.5 + 0.5 * bar.level) : 0.5

                // Short enough to keep up with the ~30fps stream (the capture
                // script already applies attack/decay smoothing).
                Behavior on height { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }
}
