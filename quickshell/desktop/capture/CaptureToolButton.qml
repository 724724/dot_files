pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property string modeValue
    property string label: ""
    property bool recordVariant: false
    readonly property bool selected: CaptureService.mode === modeValue
    readonly property bool hovered: hover.hovered
    signal chosen

    implicitWidth: 56
    implicitHeight: 46

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: root.selected ? ThemeService.selectionBg
                             : root.hovered ? ThemeService.hoverBg
                                            : "transparent"

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Item {
        id: icon
        anchors.centerIn: parent
        width: 34
        height: 27

        // Screen and window tools share the same restrained outline language.
        Rectangle {
            visible: root.modeValue.indexOf("screen") >= 0
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            width: 29; height: 20; radius: 4
            color: "transparent"
            border.width: 2
            border.color: root.selected ? ThemeService.iconSelected : ThemeService.icon
        }
        Rectangle {
            visible: root.modeValue.indexOf("screen") >= 0
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: 14; height: 2; radius: 1
            color: root.selected ? ThemeService.iconSelected : ThemeService.icon
        }

        Rectangle {
            visible: root.modeValue.indexOf("window") >= 0
            anchors.centerIn: parent
            width: 27; height: 23; radius: 4
            color: "transparent"
            border.width: 2
            border.color: root.selected ? ThemeService.iconSelected : ThemeService.icon
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 4
                height: 2; radius: 1
                color: root.selected ? ThemeService.iconSelected : ThemeService.icon
            }
        }

        Item {
            visible: root.modeValue.indexOf("portion") >= 0
            anchors.centerIn: parent
            width: 29; height: 23
            Repeater {
                model: [
                    { x: 0, y: 0, w: 9, h: 2 }, { x: 0, y: 0, w: 2, h: 9 },
                    { x: 20, y: 0, w: 9, h: 2 }, { x: 27, y: 0, w: 2, h: 9 },
                    { x: 0, y: 21, w: 9, h: 2 }, { x: 0, y: 14, w: 2, h: 9 },
                    { x: 20, y: 21, w: 9, h: 2 }, { x: 27, y: 14, w: 2, h: 9 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y
                    width: modelData.w; height: modelData.h
                    radius: 1
                    color: root.selected ? ThemeService.iconSelected : ThemeService.icon
                }
            }
        }

        Rectangle {
            visible: root.recordVariant
            anchors { right: parent.right; bottom: parent.bottom }
            width: 11; height: 11; radius: 5.5
            color: root.selected ? ThemeService.accent : ThemeService.toolbarBg
            border.width: 2
            border.color: root.selected ? ThemeService.accent : ThemeService.icon
            Rectangle {
                anchors.centerIn: parent
                width: 4; height: 4; radius: 2
                color: root.selected ? "white" : ThemeService.icon
            }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: !CaptureService.recording && !CaptureService.countingDown
        onTapped: {
            CaptureService.setMode(root.modeValue)
            root.chosen()
        }
    }

    Rectangle {
        visible: root.hovered && root.label !== ""
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
        width: tip.implicitWidth + 16
        height: 25
        radius: 7
        color: Qt.rgba(0.10, 0.10, 0.11, 0.88)
        Text {
            id: tip
            anchors.centerIn: parent
            text: root.label
            color: "white"
            font.family: "SF Pro Display"
            font.pixelSize: 12
        }
    }
}
