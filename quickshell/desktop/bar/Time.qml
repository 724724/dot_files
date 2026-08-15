pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    readonly property var now: clock.date
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm:ss")
    readonly property string dateText: Qt.formatDateTime(clock.date, "ddd d MMM")

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
