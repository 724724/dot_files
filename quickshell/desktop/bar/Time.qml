pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm:ss   ddd dd MMM")

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
