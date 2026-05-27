import QtQuick

// iOS-style 24h battery-level chart. One bar per hour; height = battery %,
// green while on power (not discharging), grey otherwise. Reads the prepared
// buckets from BatteryService.hourly.
Item {
    id: graph
    readonly property bool dark: ThemeService.isDark
    readonly property var buckets: BatteryService.hourly

    readonly property int plotH: 110
    readonly property int rightGutter: 36   // room for the % axis labels
    readonly property int xAxisH: 18

    implicitHeight: plotH + xAxisH

    readonly property real plotW: width - rightGutter
    readonly property real slotW: plotW / 24

    // Horizontal gridlines + % labels (100 / 50 / 0)
    Repeater {
        model: [100, 50, 0]
        delegate: Item {
            required property int modelData
            required property int index
            width: graph.width
            height: 1
            y: graph.plotH * index / 2     // 0 -> top, 50 -> mid, 100 -> bottom

            Rectangle {
                width: graph.plotW
                height: 1
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: modelData + "%"
                color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }
    }

    // Hourly bars
    Item {
        id: plot
        width: graph.plotW
        height: graph.plotH

        Repeater {
            model: 24
            delegate: Item {
                required property int index
                readonly property var d: graph.buckets && graph.buckets[index]
                    ? graph.buckets[index]
                    : ({ level: 0, charging: false, has: false })

                x: index * graph.slotW
                width: graph.slotW
                height: graph.plotH

                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: Math.max(2, graph.slotW - 3)
                    height: parent.d.has ? Math.max(3, graph.plotH * parent.d.level / 100) : 0
                    radius: 2
                    color: parent.d.charging
                        ? "#34C759"
                        : (graph.dark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.18))
                }
            }
        }
    }

    // X-axis hour labels (00 / 06 / 12 / 18)
    Repeater {
        model: [0, 6, 12, 18]
        delegate: Text {
            required property int modelData
            y: graph.plotH + 3
            x: modelData * graph.slotW
            text: modelData < 10 ? "0" + modelData : "" + modelData
            color: graph.dark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
    }
}
