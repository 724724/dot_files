import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

Scope {
    id: barScope
    property bool barVisible: true

    IpcHandler {
        target: "bar"
        function toggle() { barScope.barVisible = !barScope.barVisible }
        function show() { barScope.barVisible = true }
        function reload() {
            barScope.barVisible = false
            reloadTimer.start()
        }
    }

    Timer {
        id: reloadTimer
        interval: 150
        repeat: false
        onTriggered: barScope.barVisible = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            visible: barScope.barVisible
            anchors { top: true; left: true; right: true }
            margins { top: 10; left: 10; right: 10 }
            implicitHeight: 33
            color: "transparent"

            // Confine pointer input to the actual widget pills so the gaps
            // between them — above all the wide center gap on either side of
            // the media pill — stay click-through to the windows below.
            mask: Region {
                Region { item: clockW }
                Region { item: workspacesW }
                Region { item: mediaW }
                Region { item: magicW }
                Region { item: trayW }
                Region { item: volumeW }
                Region { item: batteryW }
                Region { item: networkW }
                Region { item: swayncW }
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 2
                    rightMargin: 2
                }
                height: parent.height
                spacing: 8

                ClockWidget { id: clockW; screen: win.modelData }
                WorkspacesWidget { id: workspacesW; screen: win.modelData }

                Item { Layout.fillWidth: true }

                MagicWidget { id: magicW }
                TrayWidget { id: trayW; window: win }
                VolumeWidget { id: volumeW }
                BatteryWidget { id: batteryW }
                NetworkWidget { id: networkW }
                SwayncWidget { id: swayncW }
            }

            // MediaWidget is positioned independently from the RowLayout so it
            // sits at true bar center regardless of how wide the left/right
            // widget groups are. (Equal-fill spacers don't center it when the
            // two groups have different widths.)
            MediaWidget {
                id: mediaW
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
