import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../missioncontrol" as MC
import "../dock" as Dock

Scope {
    id: barScope

    GlobalShortcut {
        appid: "bar"
        name: "toggle"
        description: "Menu bar: toggle"
        onPressed: BarState.visible = !BarState.visible
    }

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
            readonly property bool fullscreenHere:
                Dock.DockService.fullscreenMonitors.includes(win.modelData ? win.modelData.name : "")
            // No overlay at all in real fullscreen: this allows direct scanout
            // and avoids repainting a blurred bar over every 4K frame.
            visible: BarState.visible && !splitViewHere && !fullscreenHere
            anchors { top: true; left: true; right: true }
            margins { top: 10; left: 10; right: 10 }
            implicitHeight: 33
            color: "transparent"

            // Confine pointer input to the actual widget pills so the gaps
            // between them — above all the wide center gap on either side of
            // the media pill — stay click-through to the windows below.
            mask: Region {
                // Match the visible rounded surfaces instead of rectangular
                // layout slots. In particular, hidden animated widgets (such
                // as Magic and the media companion) must not leave an invisible
                // input blocker between the center pill and the right modules.
                Region { item: clockW; radius: 17 }
                Region { item: workspacesW; radius: 17 }
                Region { item: ddayW.visible ? ddayW : null; radius: 17 }
                Region { item: mediaW.visible ? mediaW : null; radius: 17 }
                Region { item: clockStatusW.visible ? clockStatusW : null; radius: 17 }
                Region { item: privacyW.micHitTarget; radius: 17 }
                Region { item: privacyW.cameraHitTarget; radius: 17 }
                Region { item: recordingW.visible ? recordingW : null; radius: 17 }
                Region { item: magicW.visible ? magicW : null; radius: 17 }
                Region { item: trayW; radius: 17 }
                Region { item: volumeW; radius: 17 }
                Region { item: batteryW; radius: 17 }
                Region { item: networkW; radius: 17 }
                Region { item: notificationW; radius: 17 }
            }

            RowLayout {
                id: barRow
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

                PrivacyIndicatorsWidget {
                    id: privacyW
                    screen: win.modelData
                    windowOriginX: 10
                }
                RecordingIndicator { id: recordingW }
                MagicWidget { id: magicW }
                TrayWidget { id: trayW; window: win }
                VolumeWidget { id: volumeW }
                BatteryWidget { id: batteryW }
                NetworkWidget { id: networkW }
                NotificationWidget { id: notificationW }
            }

            Item {
                id: centerGroup
                anchors.centerIn: parent
                height: parent.height
                readonly property real gap:
                    Math.min(8, mediaW.implicitWidth, companionSlot.width)
                width: mediaW.implicitWidth + gap + companionSlot.width

                MediaWidget {
                    id: mediaW
                    screen: win.modelData
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    id: companionSlot
                    anchors.left: mediaW.right
                    anchors.leftMargin: centerGroup.gap
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(ddayW.implicitWidth, clockStatusW.implicitWidth)
                    height: parent.height

                    DDayWidget {
                        id: ddayW
                        screen: win.modelData
                        suppressed: clockStatusW.hasEntries
                        anchors.centerIn: parent
                    }

                    ClockStatusWidget {
                        id: clockStatusW
                        screen: win.modelData
                        anchors.centerIn: parent
                    }
                }
            }
        }
    }

    // True fullscreen deliberately unmaps the full blurred bar for direct
    // scanout. Retain only active camera/microphone privacy indicators.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: privacyWin
            required property var modelData
            screen: modelData

            readonly property bool fullscreenHere:
                Dock.DockService.fullscreenMonitors.includes(
                    privacyWin.modelData ? privacyWin.modelData.name : "")
            readonly property bool privacyActive:
                PrivacyService.cameraActive || PrivacyService.micActive

            visible: fullscreenHere && privacyActive
            WlrLayershell.namespace: "qs-privacy-indicators"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; right: true }
            margins { top: 10; right: 10 }
            implicitWidth: Math.max(1, fullscreenPrivacy.implicitWidth)
            implicitHeight: 33
            color: "transparent"
            // 점은 표시 전용이므로 입력 영역을 비워 완전한 클릭 통과로 둔다.
            // (item: 로 두면 핸들러가 꺼져 있어도 클릭이 오버레이에 먹혀
            //  아래 전체화면 앱에 전달되지 않는다)
            mask: Region {}

            PrivacyIndicatorsWidget {
                id: fullscreenPrivacy
                anchors.centerIn: parent
                dotMode: true
                screen: privacyWin.modelData
                windowOriginX: privacyWin.modelData
                    ? privacyWin.modelData.width - 10 - privacyWin.width : 0
            }
        }
    }
}
