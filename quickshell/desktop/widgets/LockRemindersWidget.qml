pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Deliberately small, data-only Reminders renderer for the session lock.
// Unlike the desktop widget it has no generic save contract, URL handling, or
// process capability. The only writes are the three itemId-based operations
// exposed by WidgetPreviewFrame after WidgetsService revalidates the source.
Item {
    id: remRoot

    readonly property color accentColor: ThemeService.accent(d.accent || "blue")
    property bool adding: false
    property color cardColor: ThemeService.cardBg
    readonly property var d: frame ? frame.dataObj : ({})
    required property var frame
    property var grace: ({})
    readonly property int incompleteCount: {
        let count = 0;
        for (let i = 0; i < items.length; i++)
            if (items[i].done !== true)
                count++;
        return count;
    }
    readonly property string iconName: d.icon || "list"
    readonly property var items: Array.isArray(d.items) ? d.items : []
    readonly property int layout: Number(d.layout || 2)
    property bool lightCard: !ThemeService.isDark
    readonly property string title: d.title || "Reminders"
    readonly property var visibleItems: {
        const result = [];
        for (let i = 0; i < items.length; i++) {
            const item = items[i] || ({});
            const itemId = String(item.itemId || "");
            if (itemId === "")
                continue;
            if (item.done !== true || grace[itemId] !== undefined)
                result.push({
                    "itemId": itemId,
                    "text": String(item.text || ""),
                    "done": item.done === true
                });
        }
        return result;
    }

    function addItem(text) {
        const value = String(text || "").trim();
        if (value !== "")
            frame.addLockReminder(value);
    }

    function beginAdding() {
        if (!frame.reminderEditingEnabled)
            return;
        adding = true;
    }

    function finishInput() {
        frame.finishLockInput();
    }

    function listForLayout() {
        if (layout === 1)
            return smallList;
        if (layout === 3)
            return largeList;
        return mediumList;
    }

    function lockScrollBy(delta) {
        const list = listForLayout();
        return list ? list.scrollBy(delta) : false;
    }

    function renameItem(itemId, text) {
        const value = String(text || "").trim();
        if (value !== "")
            frame.renameLockReminder(itemId, value);
    }

    function syncModel() {
        const target = visibleItems;
        const present = ({});
        for (let i = 0; i < target.length; i++)
            present[target[i].itemId] = true;
        for (let i = visibleModel.count - 1; i >= 0; i--)
            if (!present[visibleModel.get(i).itemId])
                visibleModel.remove(i);
        for (let i = 0; i < target.length; i++) {
            const wanted = target[i];
            if (i < visibleModel.count && visibleModel.get(i).itemId === wanted.itemId) {
                visibleModel.setProperty(i, "text", wanted.text);
                visibleModel.setProperty(i, "done", wanted.done);
                continue;
            }
            let existing = -1;
            for (let j = i + 1; j < visibleModel.count; j++)
                if (visibleModel.get(j).itemId === wanted.itemId) {
                    existing = j;
                    break;
                }
            if (existing >= 0)
                visibleModel.move(existing, i, 1);
            else
                visibleModel.insert(i, wanted);
        }
    }

    function toggleItem(itemId, done) {
        const nextGrace = Object.assign({}, grace);
        if (done !== true)
            nextGrace[itemId] = Date.now() + 3000;
        else
            delete nextGrace[itemId];
        grace = nextGrace;
        frame.toggleLockReminder(itemId);
        finishInput();
    }

    onVisibleItemsChanged: syncModel()
    Component.onCompleted: syncModel()

    Timer {
        interval: 400
        repeat: true
        running: Object.keys(remRoot.grace).length > 0

        onTriggered: {
            const now = Date.now();
            const nextGrace = Object.assign({}, remRoot.grace);
            let changed = false;
            for (const itemId in nextGrace)
                if (now >= nextGrace[itemId]) {
                    delete nextGrace[itemId];
                    changed = true;
                }
            if (changed)
                remRoot.grace = nextGrace;
        }
    }

    ListModel {
        id: visibleModel
    }

    component ReminderRow: Row {
        id: reminderRow

        required property bool done
        required property string itemId
        required property string label
        property real rowWidth: 200
        spacing: 9
        height: 27
        width: rowWidth

        onLabelChanged: if (!renameField.activeFocus)
            renameField.text = label

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            border.color: reminderRow.done ? remRoot.accentColor : ThemeService.checkRing
            border.width: reminderRow.done ? 0 : 1.6
            color: reminderRow.done ? remRoot.accentColor : "transparent"
            height: 18
            radius: 9
            width: 18

            Text {
                anchors.centerIn: parent
                color: "#ffffff"
                font.family: ThemeService.iconFont
                font.pixelSize: 10
                text: "\uf00c"
                visible: reminderRow.done
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton

                onTapped: remRoot.toggleItem(reminderRow.itemId, reminderRow.done)
            }
        }
        TextField {
            id: renameField

            property bool explicitCommit: false

            anchors.verticalCenter: parent.verticalCenter
            background: null
            bottomPadding: 0
            color: reminderRow.done ? ThemeService.secondaryLabel : ThemeService.label
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.strikeout: reminderRow.done
            leftPadding: 0
            maximumLength: 512
            rightPadding: 0
            selectByMouse: true
            text: reminderRow.label
            topPadding: 0
            width: parent.width - 27

            Keys.onEscapePressed: event => {
                explicitCommit = false;
                text = reminderRow.label;
                focus = false;
                event.accepted = true;
                remRoot.finishInput();
            }
            onAccepted: {
                explicitCommit = true;
                const value = text;
                remRoot.renameItem(reminderRow.itemId, value);
                remRoot.finishInput();
            }
            onActiveFocusChanged: {
                if (activeFocus)
                    explicitCommit = false;
                else if (!explicitCommit)
                    text = reminderRow.label;
            }
            onEditingFinished: {
                // Focus loss is always cancel. Only Enter is a write. This
                // prevents password keystrokes from being saved when focus is
                // returned to the credential field.
                text = reminderRow.label;
                explicitCommit = false;
            }
        }
    }

    component ReminderList: Flickable {
        id: reminderList

        property real spacingV: 6

        function scrollBy(delta) {
            const amount = Number(delta);
            if (!Number.isFinite(amount))
                return false;
            const bounded = Math.max(-180, Math.min(180, amount));
            const minimum = originY;
            const maximum = Math.max(minimum, minimum + contentHeight - height);
            const next = Math.max(minimum, Math.min(maximum, contentY + bounded));
            if (Math.abs(next - contentY) < 0.01)
                return false;
            cancelFlick();
            contentY = next;
            return true;
        }

        boundsBehavior: Flickable.StopAtBounds
        clip: true
        contentHeight: reminderRows.implicitHeight
        contentWidth: width

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            target: null

            onWheel: event => {
                const raw = event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y * 0.4;
                if (reminderList.scrollBy(raw))
                    event.accepted = true;
            }
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        Column {
            id: reminderRows

            width: reminderList.width

            Column {
                id: reminderItemRows

                spacing: reminderList.spacingV
                width: parent.width

                Repeater {
                    model: visibleModel

                    delegate: ReminderRow {
                        required property var model

                        done: model.done
                        itemId: model.itemId
                        label: model.text
                        rowWidth: reminderItemRows.width
                    }
                }
            }
            MouseArea {
                height: Math.max(0, reminderList.height - reminderItemRows.implicitHeight)
                width: reminderList.width

                onClicked: remRoot.beginAdding()
            }
        }
    }

    component ListIcon: Rectangle {
        property real diameter: 30

        color: remRoot.accentColor
        height: diameter
        radius: diameter / 2
        width: diameter

        Text {
            anchors.centerIn: parent
            color: "#ffffff"
            font.family: ThemeService.iconFont
            font.pixelSize: parent.diameter * 0.5
            text: ThemeService.reminderGlyph(remRoot.iconName)
        }
    }

    MouseArea {
        acceptedButtons: Qt.LeftButton
        anchors.fill: parent

        onClicked: remRoot.beginAdding()
    }

    Item {
        anchors.fill: parent
        anchors.margins: 14
        visible: remRoot.layout === 1

        Row {
            id: smallHeader

            width: parent.width

            Text {
                color: remRoot.accentColor
                elide: Text.ElideRight
                font.family: "SF Pro Display"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                text: remRoot.title
                textFormat: Text.PlainText
                width: parent.width - smallCount.width
            }
            Text {
                id: smallCount

                color: remRoot.accentColor
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.Bold
                text: remRoot.incompleteCount
            }
        }
        ReminderList {
            id: smallList

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: smallHeader.bottom
            anchors.topMargin: 8
            spacingV: 5
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18
        visible: remRoot.layout === 2

        ListIcon {
            anchors.left: parent.left
            anchors.top: parent.top
            diameter: 36
        }
        Column {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            spacing: 0
            width: 112

            Text {
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.letterSpacing: -0.6
                font.pixelSize: 34
                font.weight: Font.Bold
                text: remRoot.incompleteCount
            }
            Text {
                color: remRoot.accentColor
                elide: Text.ElideRight
                font.family: "SF Pro Display"
                font.pixelSize: 15
                font.weight: Font.DemiBold
                text: remRoot.title
                textFormat: Text.PlainText
                width: parent.width
            }
        }
        ReminderList {
            id: mediumList

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 132
            anchors.right: parent.right
            anchors.top: parent.top
            spacingV: 9
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 16
        visible: remRoot.layout === 3

        Text {
            id: largeCount

            anchors.left: parent.left
            anchors.top: parent.top
            color: ThemeService.label
            font.family: "SF Pro Display"
            font.letterSpacing: -0.5
            font.pixelSize: 28
            font.weight: Font.Bold
            text: remRoot.incompleteCount
        }
        ListIcon {
            anchors.right: parent.right
            anchors.top: parent.top
        }
        Text {
            id: largeTitle

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: largeCount.bottom
            anchors.topMargin: 2
            color: remRoot.accentColor
            elide: Text.ElideRight
            font.family: "SF Pro Display"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            text: remRoot.title
            textFormat: Text.PlainText
        }
        Rectangle {
            id: largeSeparator

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: largeTitle.bottom
            anchors.topMargin: 7
            color: ThemeService.separator
            height: 1
        }
        ReminderList {
            id: largeList

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: largeSeparator.bottom
            anchors.topMargin: 7
            spacingV: 7
        }
    }

    Text {
        anchors.centerIn: parent
        color: ThemeService.secondaryLabel
        font.family: "SF Pro Display"
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 1.3
        text: "No reminders\nClick to add"
        textFormat: Text.PlainText
        visible: remRoot.visibleItems.length === 0 && !remRoot.adding
    }

    Rectangle {
        id: addBar

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: remRoot.layout === 1 ? 14 : 16
        anchors.right: parent.right
        color: ThemeService.cardBg
        height: 28
        visible: remRoot.adding
        z: 20

        onVisibleChanged: if (visible)
            Qt.callLater(() => addField.forceActiveFocus())

        Row {
            anchors.fill: parent
            spacing: 9

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                border.color: ThemeService.checkRing
                border.width: 1.6
                color: "transparent"
                height: 18
                radius: 9
                width: 18
            }
            TextField {
                id: addField

                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: ThemeService.label
                font.family: "SF Pro Display"
                font.pixelSize: 13
                maximumLength: 512
                placeholderText: "New reminder…"
                placeholderTextColor: ThemeService.secondaryLabel
                width: parent.width - 27

                Keys.onEscapePressed: event => {
                    text = "";
                    remRoot.adding = false;
                    event.accepted = true;
                    remRoot.finishInput();
                }
                onAccepted: {
                    const value = text;
                    text = "";
                    remRoot.adding = false;
                    remRoot.addItem(value);
                    remRoot.finishInput();
                }
                onActiveFocusChanged: if (!activeFocus) {
                    // Never commit on blur. Clicking the password field or
                    // leaving the widget discards the draft.
                    text = "";
                    remRoot.adding = false;
                }
            }
        }
    }
}
