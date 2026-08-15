pragma ComponentBehavior: Bound
import QtQuick

// Faithful, non-scrolling preview of the bounded lock-screen widget area.
// Clock and media reservations are structural siblings of the 6×3 grid, so
// neither drag nor malformed persisted data can place a widget over them.
Item {
    id: editor

    property bool active: false
    property bool contentActive: active
    property string placementMessage: ""

    signal widgetSettingsRequested(int index, real x, real y)

    function clearDragPreview() {
        dropPreview.visible = false;
    }

    opacity: active ? 1 : 0
    visible: active || opacity > 0.002

    Behavior on opacity {
        AppleSpring {
            spring: 18
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "#0d0e10"
    }
    Rectangle {
        id: glass

        anchors.centerIn: parent
        border.color: "#36ffffff"
        border.width: 1
        clip: true
        color: "#25272d"
        height: Math.min(parent.height - 150, 1040)
        radius: 32
        scale: editor.active ? 1 : 0.985
        width: Math.min(parent.width - 120, 1240)

        Behavior on scale {
            AppleSpring {
                epsilon: 0.001
                spring: 18
            }
        }

        Column {
            id: clockReservation

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 48
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#f8ffffff"
                font.family: "SF Pro Display"
                font.letterSpacing: -1.5
                font.pixelSize: 54
                font.weight: Font.Bold
                text: "09:41:00"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#dfffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
                text: "Tuesday, 11 Aug"
            }
        }
        Item {
            id: gridArea

            readonly property real cellHeight: WidgetsService.gridCell * layoutScale
            readonly property real cellWidth: cellHeight
            readonly property int columns: WidgetsService.lockGridColumns
            readonly property real designHeight: rows * WidgetsService.gridCell + (rows - 1) * WidgetsService.gridGap
            readonly property real designWidth: columns * WidgetsService.gridCell + (columns - 1) * WidgetsService.gridGap
            readonly property real gap: WidgetsService.gridGap * layoutScale
            readonly property real gridHeight: designHeight * layoutScale
            readonly property real gridWidth: designWidth * layoutScale
            readonly property real layoutScale: Math.max(0.01, Math.min(width / designWidth, height / designHeight))
            readonly property real originX: (width - gridWidth) / 2
            readonly property real originY: (height - gridHeight) / 2
            readonly property int rows: WidgetsService.lockGridRows
            readonly property real unitX: cellWidth + gap
            readonly property real unitY: cellHeight + gap

            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(170, parent.height * 0.225)
            anchors.left: parent.left
            anchors.leftMargin: 30
            anchors.right: parent.right
            anchors.rightMargin: 30
            anchors.top: parent.top
            anchors.topMargin: Math.max(180, parent.height * 0.255)
            clip: true

            Repeater {
                model: gridArea.columns * gridArea.rows

                delegate: Rectangle {
                    readonly property int column: index % gridArea.columns
                    required property int index
                    readonly property int row: Math.floor(index / gridArea.columns)

                    border.color: "#24ffffff"
                    border.width: 1
                    color: "#2d3037"
                    height: gridArea.cellHeight
                    radius: 11
                    width: gridArea.cellWidth
                    x: gridArea.originX + column * gridArea.unitX
                    y: gridArea.originY + row * gridArea.unitY
                }
            }
            Rectangle {
                id: dropPreview

                property bool valid: false

                border.color: valid ? "#b00a84ff" : "#c0ff6961"
                border.width: 2
                color: valid ? "#260a84ff" : "#26ff453a"
                radius: 13
                visible: false
                z: 50

                Behavior on x {
                    AppleSpring {
                        epsilon: 0.15
                        spring: 22
                    }
                }
                Behavior on y {
                    AppleSpring {
                        epsilon: 0.15
                        spring: 22
                    }
                }
            }
            Repeater {
                model: WidgetsService.lockWidgets

                delegate: Item {
                    id: tile

                    property int candidateColumn: column
                    property int candidateRow: row
                    property bool candidateValid: true
                    required property int column
                    required property int columns
                    property real draggedX: restingX
                    property real draggedY: restingY
                    property bool dragging: false
                    property real grabX: 0
                    property real grabY: 0
                    required property int index
                    required property string payload
                    readonly property real restingX: gridArea.originX + column * gridArea.unitX
                    readonly property real restingY: gridArea.originY + row * gridArea.unitY
                    required property int row
                    required property int rows
                    required property string type
                    required property int wid

                    height: rows * gridArea.cellHeight + (rows - 1) * gridArea.gap
                    width: columns * gridArea.cellWidth + (columns - 1) * gridArea.gap
                    x: dragging ? draggedX : restingX
                    y: dragging ? draggedY : restingY
                    z: dragging ? 100 : index + 2

                    Behavior on x {
                        enabled: !tile.dragging

                        AppleSpring {
                            epsilon: 0.15
                            spring: 20
                        }
                    }
                    Behavior on y {
                        enabled: !tile.dragging

                        AppleSpring {
                            epsilon: 0.15
                            spring: 20
                        }
                    }

                    WidgetPreviewFrame {
                        anchors.fill: parent
                        anchors.margins: 2
                        contentActive: editor.contentActive
                        cornerRadius: 13
                        index: tile.index
                        payload: tile.payload
                        type: tile.type
                        wid: tile.wid
                    }
                    MouseArea {
                        id: dragArea

                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        onCanceled: {
                            tile.dragging = false;
                            editor.clearDragPreview();
                        }
                        onPositionChanged: event => {
                            if (!pressed)
                                return;
                            const point = mapToItem(gridArea, event.x, event.y);
                            tile.draggedX = point.x - tile.grabX;
                            tile.draggedY = point.y - tile.grabY;
                            const centerX = tile.draggedX + tile.width / 2;
                            const centerY = tile.draggedY + tile.height / 2;
                            tile.candidateColumn = Math.max(0, Math.min(gridArea.columns - tile.columns, Math.round((centerX - gridArea.originX) / gridArea.unitX - tile.columns / 2)));
                            tile.candidateRow = Math.max(0, Math.min(gridArea.rows - tile.rows, Math.round((centerY - gridArea.originY) / gridArea.unitY - tile.rows / 2)));
                            tile.candidateValid = WidgetsService.lockRegionFree(tile.index, tile.candidateColumn, tile.candidateRow, tile.columns, tile.rows);
                            dropPreview.x = gridArea.originX + tile.candidateColumn * gridArea.unitX;
                            dropPreview.y = gridArea.originY + tile.candidateRow * gridArea.unitY;
                            dropPreview.width = tile.width;
                            dropPreview.height = tile.height;
                            dropPreview.valid = tile.candidateValid;
                            dropPreview.visible = true;
                        }
                        onPressed: event => {
                            tile.dragging = true;
                            tile.grabX = event.x;
                            tile.grabY = event.y;
                            tile.draggedX = tile.restingX;
                            tile.draggedY = tile.restingY;
                            tile.candidateColumn = tile.column;
                            tile.candidateRow = tile.row;
                            tile.candidateValid = true;
                        }
                        onReleased: {
                            if (dropPreview.visible && tile.candidateValid)
                                WidgetsService.moveLockWidget(tile.index, tile.candidateColumn, tile.candidateRow, true);
                            tile.dragging = false;
                            editor.clearDragPreview();
                        }
                    }
                    MouseArea {
                        acceptedButtons: Qt.RightButton
                        anchors.fill: parent

                        onClicked: event => {
                            const point = mapToItem(editor, event.x, event.y);
                            editor.widgetSettingsRequested(tile.index, point.x, point.y);
                        }
                    }
                    Rectangle {
                        border.color: "#70ffffff"
                        border.width: 1
                        color: deleteHover.hovered ? "#ff453a" : "#e83b32"
                        height: 24
                        radius: 12
                        scale: deleteTap.pressed ? 0.9 : 1
                        width: 24
                        x: -8
                        y: -8
                        z: 200

                        Behavior on scale {
                            AppleSpring {
                                spring: 22
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            color: "white"
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            text: "✕"
                        }
                        HoverHandler {
                            id: deleteHover
                        }
                        TapHandler {
                            id: deleteTap

                            onTapped: WidgetsService.removeLockWidget(tile.index)
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                color: "#b8ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.Medium
                text: "Add widgets with the + button"
                visible: WidgetsService.lockWidgets.count === 0
            }
        }
        Rectangle {
            id: mediaReservation

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter
            border.color: mediaHover.hovered ? "#62ffffff" : "#35ffffff"
            border.width: 1
            color: "#2b2b2f"
            height: 44
            opacity: WidgetsService.lockMediaEnabled ? 1 : 0.46
            radius: 22
            scale: mediaTap.pressed ? 0.985 : 1
            width: Math.min(parent.width - 72, 520)

            Behavior on opacity {
                AppleSpring {
                    spring: 18
                }
            }
            Behavior on scale {
                AppleSpring {
                    spring: 20
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: "#26ffffff"
                height: 26
                radius: 8
                width: 26

                Text {
                    anchors.centerIn: parent
                    color: "#d8ffffff"
                    font.pixelSize: 14
                    text: "♪"
                }
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 46
                anchors.right: equalizerPreview.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                elide: Text.ElideRight
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
                text: WidgetsService.lockMediaEnabled ? "Media on the Lock Screen" : "Media hidden on the Lock Screen"
            }
            Row {
                id: equalizerPreview

                anchors.right: mediaSwitch.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: 6

                    delegate: Rectangle {
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        color: "#b8ffffff"
                        height: 4 + (index % 3) * 3
                        radius: 1
                        width: 2
                    }
                }
            }
            Rectangle {
                id: mediaSwitch

                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                border.color: WidgetsService.lockMediaEnabled ? "#4dffffff" : "#30ffffff"
                border.width: 1
                color: WidgetsService.lockMediaEnabled ? "#0a84ff" : "#42444a"
                height: 24
                radius: 12
                width: 42

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: "white"
                    height: 18
                    radius: 9
                    width: 18
                    x: WidgetsService.lockMediaEnabled ? parent.width - width - 3 : 3

                    Behavior on x {
                        AppleSpring {
                            epsilon: 0.05
                            spring: 20
                        }
                    }
                }
            }
            HoverHandler {
                id: mediaHover

                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: mediaTap

                onTapped: WidgetsService.setLockMediaEnabled(!WidgetsService.lockMediaEnabled)
            }
        }
    }
}
