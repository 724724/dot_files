import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../missioncontrol" as MC

Scope {
    id: barScope

    IpcHandler {
        target: "bar"
        function toggle() { BarState.visible = !BarState.visible }
        function show() { BarState.visible = true }
        function reload() {
            BarState.visible = false
            Qt.callLater(() => BarState.visible = true)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // Dedicated layer namespace (matched by the qs-bar layerrule in
            // hypr windowrules) so the bar no longer rides the generic
            // "quickshell" default.
            WlrLayershell.namespace: "qs-bar"

            // Hidden while this screen's active workspace is a Mission-Control
            // Split View space (macOS-style full-bleed split; unmapping also
            // releases the exclusive zone so the tiles get the full height).
            // Returns as soon as any normal workspace becomes active.
            readonly property bool splitViewHere:
                MC.MCService.splitViewActiveOn(win.modelData ? win.modelData.name : "")
            visible: BarState.visible && !splitViewHere
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
                Region { item: privacyW }
                Region { item: magicW }
                Region { item: trayW }
                Region { item: volumeW }
                Region { item: batteryW }
                Region { item: networkW }
                Region { item: notificationW }
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

                PrivacyIndicatorsWidget { id: privacyW; screen: win.modelData }
                MagicWidget { id: magicW }
                TrayWidget { id: trayW; window: win }
                VolumeWidget { id: volumeW }
                BatteryWidget { id: batteryW }
                NetworkWidget { id: networkW }
                NotificationWidget { id: notificationW }
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
