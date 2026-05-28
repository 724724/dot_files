import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    // Set from shell.qml = BarState.contentTop (gap centralized there), so
    // toasts track the bar and rise with it when the bar is hidden.
    property int barContentTop: 53

    anchors { top: true; right: true }
    margins { top: barContentTop; right: 10 }
    implicitWidth: 400
    implicitHeight: Math.max(popupCol.implicitHeight + 16, 1)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "qs-notif"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // While the control center is open the notifications are already shown
    // inside it, so suppress the duplicate transient popups.
    visible: !NcServer.controlCenterVisible

    // ScriptModel diffs popupActive against its previous contents and emits
    // granular row inserts/removes, so removing one popup destroys only that
    // delegate. Binding the Repeater straight to the JS array made every
    // change a full model reset — every surviving card was torn down and
    // recreated, replaying its slide-in and flickering the whole stack.
    ScriptModel {
        id: popupModel
        objectProp: "id"
        values: NcServer.popupActive
    }

    Column {
        id: popupCol
        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
        width: 390
        spacing: 8

        Repeater {
            // Only notifications that haven't yet finished their popup window
            model: popupModel

            delegate: Item {
                id: wrap
                required property var modelData
                width: popupCol.width
                height: card.implicitHeight
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // Slide-in + fade-out lifecycle
                property real slideX: 24
                property real fade: 0

                NotificationCard {
                    id: card
                    notification: wrap.modelData
                    width: popupCol.width
                    inControlCenter: false
                    opacity: wrap.fade
                    transform: Translate { x: wrap.slideX }
                }

                Component.onCompleted: { fade = 1; slideX = 0 }

                // The Repeater rebuilds delegates whenever popupActive
                // returns a fresh array (every notification arrival or
                // popup-seen mark). A fixed `interval: 3000` would restart
                // the countdown for every existing card on every rebuild,
                // producing the visual cascade where only the top one
                // disappeared and the rest "waited another 3 seconds."
                //
                // Anchor to the wall-clock arrival time instead: each card's
                // own deadline is `receivedAt + 3000`. A card recreated
                // mid-life simply gets the *remaining* time.
                Timer {
                    id: expireTimer
                    interval: {
                        if (wrap.modelData.urgency === NotificationUrgency.Critical) return 0
                        // honour notify-send -t when explicitly set
                        let t = wrap.modelData.expireTimeout
                        let total = t > 0 ? t : 3000
                        let recv = NcServer.receivedAt[wrap.modelData.id]
                        if (!recv) return total
                        let remaining = (recv + total) - Date.now()
                        return Math.max(50, remaining)
                    }
                    running: interval > 0
                    onTriggered: { wrap.fade = 0; hideTimer.start() }
                }

                Timer {
                    id: hideTimer
                    interval: 220
                    onTriggered: NcServer.markPopupSeen(wrap.modelData.id)
                }

                Behavior on fade   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on slideX { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
        }
    }
}
