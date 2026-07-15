import QtQuick
import QtQuick.Controls
import "kinetic.js" as Kinetic

// "View All" panel for a reminders widget (right-click → View All). Shows the
// FULL list including completed items (checkmark + strikethrough), each with a
// delete button. Press-and-hold a row to drag-reorder the list.
Item {
    id: vw
    property int index: -1

    implicitWidth: 420
    implicitHeight: header.height + 10 + Math.min(360, Math.max(44, lv.contentHeight)) + 10

    property string title: "Reminders"
    property string accentName: "blue"
    property bool dragging: false
    readonly property color accent: ThemeService.accent(accentName)

    ListModel { id: lm }

    onIndexChanged: vw.reload()
    function reload() {
        if (index < 0) return
        let d = WidgetsService.getData(index)
        title = (d.title !== undefined) ? d.title : "Reminders"
        accentName = d.accent || "blue"
        lm.clear()
        let its = d.items || []
        for (let i = 0; i < its.length; i++) lm.append({ text: its[i].text, done: its[i].done === true })
    }
    function persist() {
        let a = []
        for (let i = 0; i < lm.count; i++) { let it = lm.get(i); a.push({ text: it.text, done: it.done }) }
        WidgetsService.setData(index, { items: a })
    }
    function toggle(i)     { if (i < 0 || i >= lm.count) return; lm.setProperty(i, "done", !lm.get(i).done); persist() }
    function removeItem(i) { if (i < 0 || i >= lm.count) return; lm.remove(i); persist() }

    Row {
        id: header
        width: parent.width
        height: 34
        spacing: 10
        Rectangle {
            width: 28; height: 28; radius: 14; color: vw.accent
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent
                   text: ThemeService.reminderGlyph((vw.index >= 0 ? WidgetsService.getData(vw.index).icon : "list") || "list")
                   color: "#ffffff"; font.family: ThemeService.iconFont; font.pixelSize: 14 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: vw.title; color: vw.accent
            font.family: "SF Pro Display"; font.pixelSize: 18; font.weight: Font.Bold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: lm.count; color: Qt.rgba(1, 1, 1, 0.45)
            font.family: "SF Pro Display"; font.pixelSize: 16; font.weight: Font.DemiBold
        }
    }

    ListView {
        id: lv
        anchors.top: header.bottom; anchors.topMargin: 10
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        clip: true
        spacing: 2
        interactive: !vw.dragging
        cacheBuffer: 1000
        model: lm
        boundsBehavior: Flickable.DragAndOvershootBounds
        boundsMovement: Flickable.FollowBoundsBehavior
        flickDeceleration: 6000
        maximumFlickVelocity: 6000
        rebound: Transition {
            SpringAnimation {
                properties: "x,y"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Kinetic scroll (kinetic.js) — same feel as the emoji/nc lists.
        property var _ks: ({})
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: !vw.dragging
            onWheel: (ev) => {
                lvGlide.stop()
                if (Kinetic.onWheel(lv, ev, lv._ks, { gain: 44 }))
                    lvEndTimer.restart()
            }
        }
        Timer {
            id: lvEndTimer
            interval: 48
            onTriggered: {
                let g = Kinetic.fling(lv, lv._ks, {})
                if (g) { lvGlide.from = g.from; lvGlide.to = g.to; lvGlide.restart() }
            }
        }
        SpringAnimation {
            id: lvGlide
            target: lv
            property: "contentY"
            spring: 18
            damping: ThemeService.momentumDamping
            epsilon: 0.25
        }

        Text {
            anchors.centerIn: parent
            visible: lm.count === 0
            text: "No items yet"; color: Qt.rgba(1, 1, 1, 0.45)
            font.family: "SF Pro Display"; font.pixelSize: 13
        }

        delegate: MouseArea {
            id: dragArea
            property int visualIndex: index
            property bool held: false
            width: ListView.view.width
            height: 38
            z: held ? 10 : 0
            pressAndHoldInterval: 220
            cursorShape: held ? Qt.ClosedHandCursor : Qt.ArrowCursor
            drag.target: held ? content : undefined
            drag.axis: Drag.YAxis
            onPressAndHold: { held = true; vw.dragging = true }
            onReleased: { if (held) { held = false; vw.dragging = false; vw.persist() } }

            Rectangle {
                id: content
                width: dragArea.width; height: dragArea.height - 2; radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                color: dragArea.held ? Qt.rgba(1, 1, 1, 0.16)
                     : (rowHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                border.color: dragArea.held ? Qt.rgba(1, 1, 1, 0.20) : "transparent"
                border.width: 1
                HoverHandler { id: rowHover }
                Drag.active: dragArea.held
                Drag.source: dragArea
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                Rectangle {
                    id: cb
                    anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: model.done ? vw.accent : "transparent"
                    border.color: model.done ? vw.accent : Qt.rgba(1, 1, 1, 0.35)
                    border.width: model.done ? 0 : 1.7
                    Text { anchors.centerIn: parent; visible: model.done; text: "\uf00c"
                           color: "#ffffff"; font.family: ThemeService.iconFont; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor; onClicked: vw.toggle(dragArea.visualIndex) }
                }
                Text {
                    anchors.left: cb.right; anchors.leftMargin: 10
                    anchors.right: trash.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.text
                    color: model.done ? Qt.rgba(1, 1, 1, 0.45) : "#ffffff"
                    font.family: "SF Pro Display"; font.pixelSize: 14
                    font.strikeout: model.done
                    elide: Text.ElideRight
                }
                Text {
                    id: trash
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    visible: (rowHover.hovered || trashHover.hovered) && !dragArea.held
                    text: "\uf1f8"; color: trashHover.hovered ? "#ff5b5b" : Qt.rgba(1, 1, 1, 0.4)
                    font.family: ThemeService.iconFont; font.pixelSize: 14
                    HoverHandler { id: trashHover }
                    MouseArea { anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor; onClicked: vw.removeItem(dragArea.visualIndex) }
                }

                states: State {
                    when: dragArea.held
                    ParentChange { target: content; parent: lv }
                    AnchorChanges { target: content
                        anchors.horizontalCenter: undefined; anchors.verticalCenter: undefined }
                }
            }

            DropArea {
                anchors.fill: parent
                onEntered: (drag) => {
                    let from = drag.source.visualIndex
                    let to = dragArea.visualIndex
                    if (from !== to && from >= 0) lm.move(from, to, 1)
                }
            }
        }
    }
}
