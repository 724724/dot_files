import QtQuick
import QtQuick.Controls

// macOS Reminders-style widget with 3 layouts (small / medium / large), light
// & dark theming (ThemeService = Apple system colours) and a per-list accent
// colour + icon. Completed items disappear from the widget 3s after you check
// them (they stay in the list — see right-click → View All). Click empty space
// to add an item; style/title/colour/icon are set in the editor.
//   1 small   2 medium   3 large
Item {
    id: remRoot
    property var frame
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property int layout: (d && d.layout) ? d.layout : 2
    readonly property string title: (d && d.title) ? d.title : "Reminders"
    readonly property var items: (d && d.items) ? d.items : []
    readonly property string iconName: (d && d.icon) ? d.icon : "list"
    readonly property color accentColor: ThemeService.accent((d && d.accent) ? d.accent : "blue")

    property color cardColor: ThemeService.cardBg
    property bool lightCard: !ThemeService.isDark

    readonly property int incompleteCount: {
        let n = 0
        for (let i = 0; i < items.length; i++) if (!items[i].done) n++
        return n
    }

    // Completed items linger for 3s (grace[di] = expiry ms) so the check is
    // visible, then drop out of the widget view.
    property var grace: ({})
    readonly property var visibleItems: {
        let out = []
        for (let i = 0; i < items.length; i++) {
            if (!items[i].done) out.push({ text: items[i].text, done: false, di: i })
            else if (grace[i] !== undefined) out.push({ text: items[i].text, done: true, di: i })
        }
        return out
    }
    Timer {
        interval: 400; repeat: true
        running: Object.keys(remRoot.grace).length > 0
        onTriggered: {
            let now = Date.now(), g = Object.assign({}, remRoot.grace), changed = false
            for (let k in g) if (now >= g[k]) { delete g[k]; changed = true }
            if (changed) remRoot.grace = g
        }
    }

    // View model mirroring visibleItems with *granular* updates. A JS-array
    // model rebuilds every delegate on any change (no animation possible), so we
    // diff into a ListModel: when one item drops out (e.g. 3s after you check
    // it) only that row is removed, and the rows below slide up via the `move`
    // transition on the rows Column.
    ListModel { id: visModel }
    function syncModel() {
        let target = remRoot.visibleItems
        let present = ({})
        for (let i = 0; i < target.length; i++) present[target[i].di] = true
        for (let i = visModel.count - 1; i >= 0; i--)
            if (!present[visModel.get(i).di]) visModel.remove(i)
        for (let i = 0; i < target.length; i++) {
            let t = target[i]
            if (i < visModel.count && visModel.get(i).di === t.di) {
                if (visModel.get(i).done !== t.done) visModel.setProperty(i, "done", t.done)
                if (visModel.get(i).text !== t.text) visModel.setProperty(i, "text", t.text)
            } else {
                let at = -1
                for (let j = i + 1; j < visModel.count; j++)
                    if (visModel.get(j).di === t.di) { at = j; break }
                if (at >= 0) visModel.move(at, i, 1)
                else visModel.insert(i, { di: t.di, text: t.text, done: t.done })
            }
        }
    }
    onVisibleItemsChanged: syncModel()
    Component.onCompleted: syncModel()

    function toggle(di) {
        let a = items.slice()
        if (!a[di]) return
        let nd = !a[di].done
        a[di] = { text: a[di].text, done: nd }
        frame.save({ items: a })
        let g = Object.assign({}, grace)
        if (nd) g[di] = Date.now() + 3000; else delete g[di]
        grace = g
    }

    property bool adding: false
    function addItem(t) {
        if (!t || !t.trim()) return
        let a = items.slice()
        a.push({ text: t.trim(), done: false })
        frame.save({ items: a })
    }
    // Rename an item (click its name in the widget to edit).
    function rename(di, t) {
        let a = items.slice()
        if (a[di] && a[di].text !== t) { a[di] = { text: t, done: a[di].done }; frame.save({ items: a }) }
    }

    // ── A single reminder row (circle + text), display + toggle ─────────────
    component ReminderItem: Row {
        property int di: 0
        property string txt: ""
        property bool done: false
        property real rowWidth: 200
        width: rowWidth
        height: 27
        spacing: 9
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9
            color: done ? remRoot.accentColor : "transparent"
            border.color: done ? remRoot.accentColor : ThemeService.checkRing
            border.width: done ? 0 : 1.6
            Text { anchors.centerIn: parent; visible: done; text: "\uf00c"
                   color: "#ffffff"; font.family: ThemeService.iconFont; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor; onClicked: remRoot.toggle(di) }
        }
        TextField {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 27
            text: txt
            background: null
            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
            color: done ? ThemeService.secondaryLabel : ThemeService.label
            font.family: "SF Pro Display"; font.pixelSize: 13
            font.strikeout: done
            selectByMouse: true
            onEditingFinished: remRoot.rename(di, text)
        }
    }

    // Accent icon disc (top of the list).
    component ListIcon: Rectangle {
        property real d: 30
        width: d; height: d; radius: d / 2
        color: remRoot.accentColor
        Text { anchors.centerIn: parent; text: ThemeService.reminderGlyph(remRoot.iconName)
               color: "#ffffff"; font.family: ThemeService.iconFont; font.pixelSize: parent.d * 0.5 }
    }

    // A scrollable item list (used by every layout). Items scroll when they
    // overflow; a filler below the rows keeps "click empty space to add"
    // working inside the list area.
    component ItemList: Flickable {
        id: il
        property real spacingV: 6
        clip: true
        contentWidth: width
        contentHeight: listCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: listCol
            width: il.width
            Column {
                id: rows
                width: parent.width
                spacing: il.spacingV
                // When a row is removed (e.g. a checked item dropping out), the
                // rows below slide up to fill the gap.
                move: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
                Repeater {
                    model: visModel
                    delegate: ReminderItem {
                        di: model.di; rowWidth: rows.width
                        txt: model.text; done: model.done
                    }
                }
            }
            MouseArea {
                width: il.width
                height: Math.max(0, il.height - rows.implicitHeight)
                onClicked: remRoot.adding = true
            }
        }
    }

    // Background: click empty space anywhere to start adding an item.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: remRoot.adding = true
    }

    // ── Layout 1: small ─────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 14
        visible: remRoot.layout === 1
        Row {
            id: sTop
            width: parent.width
            Text { width: parent.width - sCount.width; text: remRoot.title; color: remRoot.accentColor
                   font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Text { id: sCount; text: remRoot.incompleteCount; color: remRoot.accentColor
                   font.family: "SF Pro Display"; font.pixelSize: 17; font.weight: Font.Bold }
        }
        ItemList {
            anchors.top: sTop.bottom; anchors.topMargin: 8
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            spacingV: 5
        }
    }

    // ── Layout 2: medium (icon top-left, count/title bottom-left) ───────────
    Item {
        anchors.fill: parent
        anchors.margins: 18
        visible: remRoot.layout === 2
        ListIcon {
            id: mIcon; d: 36
            anchors.top: parent.top; anchors.left: parent.left
        }
        Column {
            id: mMeta
            anchors.left: parent.left; anchors.bottom: parent.bottom
            width: 112
            spacing: 0
            Text { text: remRoot.incompleteCount; color: ThemeService.label
                   font.family: "SF Pro Display"; font.pixelSize: 34; font.weight: Font.Bold }
            Text { width: parent.width; text: remRoot.title; color: remRoot.accentColor
                   font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
        }
        ItemList {
            anchors.left: parent.left; anchors.leftMargin: 132
            anchors.right: parent.right
            anchors.top: parent.top; anchors.bottom: parent.bottom
            spacingV: 9
        }
    }

    // ── Layout 3: large ─────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 16
        visible: remRoot.layout === 3
        Text {
            id: lCount
            anchors.left: parent.left; anchors.top: parent.top
            text: remRoot.incompleteCount; color: ThemeService.label
            font.family: "SF Pro Display"; font.pixelSize: 28; font.weight: Font.Bold
        }
        ListIcon { d: 30; anchors.right: parent.right; anchors.top: parent.top }
        Text {
            id: lTitle
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: lCount.bottom; anchors.topMargin: 2
            text: remRoot.title; color: remRoot.accentColor
            font.family: "SF Pro Display"; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight
        }
        Rectangle {
            id: lSep
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: lTitle.bottom; anchors.topMargin: 7
            height: 1; color: ThemeService.separator
        }
        ItemList {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: lSep.bottom; anchors.topMargin: 7; anchors.bottom: parent.bottom
            spacingV: 7
        }
    }

    // Empty hint
    Text {
        anchors.centerIn: parent
        visible: remRoot.visibleItems.length === 0 && !remRoot.adding
        text: "No reminders\nClick to add"
        horizontalAlignment: Text.AlignHCenter
        color: ThemeService.secondaryLabel
        font.family: "SF Pro Display"; font.pixelSize: 12; lineHeight: 1.3
    }

    // ── Inline add bar (shown when clicking empty space) ────────────────────
    Rectangle {
        id: addBar
        visible: remRoot.adding
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: remRoot.layout === 1 ? 14 : 16
        height: 28
        color: ThemeService.cardBg
        onVisibleChanged: if (visible) addField.forceActiveFocus()
        Row {
            anchors.fill: parent
            spacing: 9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: "transparent"; border.color: ThemeService.checkRing; border.width: 1.6
            }
            TextField {
                id: addField
                width: parent.width - 27
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: ThemeService.label
                placeholderText: "New reminder…"
                placeholderTextColor: ThemeService.secondaryLabel
                font.family: "SF Pro Display"; font.pixelSize: 13
                onAccepted: { remRoot.addItem(text); text = "" }
                Keys.onEscapePressed: remRoot.adding = false
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        if (text.trim()) remRoot.addItem(text)
                        text = ""
                        remRoot.adding = false
                    }
                }
            }
        }
    }
}
