import QtQuick
import Quickshell

// Renderer shared by the lock preview and the real session-lock surface.
// Generic desktop widgets remain input-disabled. The only editable component
// is the dedicated, process-free LockRemindersWidget and it receives three
// itemId-based operations rather than WidgetFrame's generic save contract.
Item {
    id: frame

    property bool contentActive: true
    readonly property var contentItem: content.item
    readonly property real contentScale: Math.max(0.01, Math.min(width / Math.max(1, designWidth), height / Math.max(1, designHeight)))
    property real cornerRadius: 13
    readonly property var dataObj: {
        try {
            return JSON.parse(payload || "{}");
        } catch (e) {
            return ({});
        }
    }
    readonly property real designHeight: preset ? preset.nh : WidgetsService.gridCell
    readonly property real designWidth: preset ? preset.nw : WidgetsService.gridCell
    required property int index
    readonly property bool isXSmallNews: type === "news" && Number(dataObj.layout || 0) === 4
    property bool liveLockInteraction: false
    readonly property bool lockScrollBridgeEnabled: liveLockInteraction && (type === "note" || type === "news")
    readonly property bool lightCard: !!(contentItem && contentItem.lightCard === true)
    readonly property color neutralCard: Qt.rgba(0.17, 0.19, 0.24, 0.78)
    required property string payload
    readonly property var preset: WidgetsService.presetSize(type, Number(dataObj.layout || 0))
    required property string type
    required property int wid
    readonly property bool reminderEditingEnabled: liveLockInteraction && contentActive && type === "reminders" && WidgetsService.lockReminderLinked(index)
    readonly property bool sessionLockPassive: Quickshell.env("QS_LOCK_MODE") === "1"
    // Compatibility contract expected by current and future Widget.qml files.
    property var winRef: activityProxy

    signal inputFinished

    function addLockReminder(text) {
        if (!reminderEditingEnabled || typeof text !== "string")
            return false;
        return WidgetsService.addLockReminder(index, text);
    }

    function bringToFront() {
    }

    function dispatchLockScroll(delta) {
        if (!lockScrollBridgeEnabled || typeof delta !== "number" || !Number.isFinite(delta))
            return false;

        let bounded = Math.max(-180, Math.min(180, delta));
        if (Math.abs(bounded) < 0.01 || !contentItem || typeof contentItem.lockScrollBy !== "function")
            return false;

        // Only a bounded number crosses the lock boundary. Never forward the
        // WheelEvent (or any text/string payload) into a widget implementation.
        return contentItem.lockScrollBy(bounded) === true;
    }

    function requestClose() {
    }

    function finishLockInput() {
        inputFinished();
    }

    function renameLockReminder(itemId, text) {
        if (!reminderEditingEnabled || typeof itemId !== "string" || typeof text !== "string")
            return false;
        return WidgetsService.renameLockReminder(index, itemId, text);
    }

    function save(_patch) {
    }

    function toggleLockReminder(itemId) {
        if (!reminderEditingEnabled || typeof itemId !== "string")
            return false;
        return WidgetsService.toggleLockReminder(index, itemId);
    }

    QtObject {
        id: activityProxy

        // The lock may refresh only cache-backed, read-only data widgets. All
        // other desktop widget services stay passive even though their QML is
        // instantiated for display. Weather and News consult their one-hour
        // shared caches before they are allowed to launch a fetch.
        readonly property bool show: frame.contentActive
            && (!frame.sessionLockPassive
                || frame.type === "clock"
                || frame.type === "weather"
                || frame.type === "news")
    }

    WheelHandler {
        id: lockScrollWheel

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: frame.contentActive && frame.lockScrollBridgeEnabled
        target: null
        onWheel: event => {
            let wheelY = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y * 0.5;
            if (typeof wheelY !== "number" || !Number.isFinite(wheelY) || wheelY === 0)
                return;

            let designDelta = -wheelY / Math.max(0.25, frame.contentScale);
            if (frame.dispatchLockScroll(designDelta))
                event.accepted = true;
        }
    }

    Rectangle {
        color: "#26000000"
        height: parent.height
        radius: frame.cornerRadius
        width: parent.width
        x: 0
        y: Math.max(1, 3 * frame.contentScale)
    }

    Rectangle {
        anchors.fill: parent
        border.color: frame.lightCard ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.12)
        border.width: frame.isXSmallNews ? 0 : 1
        clip: true
        color: frame.contentItem && frame.contentItem.cardColor ? frame.contentItem.cardColor : frame.neutralCard
        radius: frame.isXSmallNews ? Math.min(width, height) * 0.12 : frame.cornerRadius

        Item {
            height: frame.designHeight
            scale: frame.contentScale
            transformOrigin: Item.TopLeft
            width: frame.designWidth
            x: (parent.width - width * frame.contentScale) / 2
            y: (parent.height - height * frame.contentScale) / 2

            Loader {
                id: content

                anchors.fill: parent
                asynchronous: true
                enabled: frame.reminderEditingEnabled
                Component.onCompleted: content.setSource(frame.type === "reminders" ? Qt.resolvedUrl("LockRemindersWidget.qml") : WidgetsService.componentSource(frame.type), {
                    "frame": frame
                })
            }
        }
    }
}
