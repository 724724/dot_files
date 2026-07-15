import QtQuick
import ".."

Item {
    id: overview
    required property var root
    implicitHeight: separator.y + separator.height

    function requestPaint() {
        chartCanvas.requestPaint()
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: 22
        height: 76
    
        Column {
            anchors.left: parent.left
            anchors.top: parent.top
            spacing: 3
            Row {
                spacing: 8
                Text {
                    width: Math.min(190, implicitWidth)
                    text: root.snapshot.name || root.symbol
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.25
                    elide: Text.ElideRight
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: demoText.implicitWidth + 12
                    height: 18
                    radius: 6
                    color: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
                    Text {
                        id: demoText
                        anchors.centerIn: parent
                        text: root.realtimeConnected ? "LIVE" : (root.snapshot.mode === "kis" ? "KIS" : "DEMO")
                        color: root.realtimeConnected ? root.positiveColor : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 18
                    radius: 6
                    color: watchStarHover.hovered ? root.raisedColor : root.separatorColor
                    scale: watchStarArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.currentWatched ? "★" : "☆"
                        color: root.currentWatched ? "#ff9f0a" : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                    }
                    HoverHandler { id: watchStarHover }
                    MouseArea {
                        id: watchStarArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.toggleCurrentWatch()
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 18
                    radius: 6
                    color: watchListHover.hovered ? root.raisedColor : root.separatorColor
                    scale: watchListArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: "≡"
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: watchListHover }
                    MouseArea {
                        id: watchListArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.openWatchlist()
                    }
                }
            }
            Text {
                text: root.market + " · " + root.symbol
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }
    
        Column {
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 2
            Text {
                anchors.right: parent.right
                text: StockService.money(root.snapshot.price, root.snapshot.currency)
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 28
                font.weight: Font.DemiBold
                font.letterSpacing: -0.75
            }
            Text {
                anchors.right: parent.right
                text: StockService.signed(root.snapshot.change, root.snapshot.currency === "KRW" ? 0 : 2)
                      + "  (" + StockService.signed(root.snapshot.changePct, 2) + "%)"
                color: root.movementColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
    }
    
    Row {
        id: rangeRow
        anchors { left: parent.left; top: header.bottom }
        anchors.leftMargin: 22
        spacing: 5
        Repeater {
            model: StockService.rangeOptions
            delegate: RangeButton {
                required property var modelData
                label: modelData.label
                selected: root.chartRange === modelData.id
                onTriggered: root.chooseRange(modelData.id)
            }
        }
    }
    
    Item {
        id: chartArea
        anchors { left: parent.left; right: parent.right; top: rangeRow.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 9
        height: 240
        clip: true
    
        Canvas {
            id: chartCanvas
            anchors.fill: parent
            property var values: root.points
            property color strokeColor: root.movementColor
            opacity: root.loading && root.points.length === 0 ? 0.35 : 1
            Behavior on opacity { AppleSpring { spring: 18 } }
            onValuesChanged: requestPaint()
            onStrokeColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (!values || values.length < 2) return
                let minValue = values[0].v
                let maxValue = values[0].v
                for (let i = 1; i < values.length; i++) {
                    minValue = Math.min(minValue, values[i].v)
                    maxValue = Math.max(maxValue, values[i].v)
                }
                let spread = Math.max(1, maxValue - minValue)
                let pad = 5
                function px(index) { return pad + index * (width - pad * 2) / (values.length - 1) }
                function py(value) { return pad + (maxValue - value) * (height - pad * 2) / spread }
                ctx.beginPath()
                for (let j = 0; j < values.length; j++) {
                    let x = px(j)
                    let y = py(values[j].v)
                    if (j === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                let lastX = px(values.length - 1)
                let lastY = py(values[values.length - 1].v)
                ctx.lineTo(lastX, height)
                ctx.lineTo(pad, height)
                ctx.closePath()
                let fill = ctx.createLinearGradient(0, 0, 0, height)
                fill.addColorStop(0, Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.24))
                fill.addColorStop(1, Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.0))
                ctx.fillStyle = fill
                ctx.fill()
                ctx.beginPath()
                for (let k = 0; k < values.length; k++) {
                    let lineX = px(k)
                    let lineY = py(values[k].v)
                    if (k === 0) ctx.moveTo(lineX, lineY)
                    else ctx.lineTo(lineX, lineY)
                }
                ctx.strokeStyle = strokeColor
                ctx.lineWidth = 2.2
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.stroke()
            }
        }
    
        Rectangle {
            visible: root.hoverIndex >= 0 && root.hoverIndex < root.points.length
            x: root.points.length > 1 ? root.hoverIndex * (chartArea.width - 10) / (root.points.length - 1) + 5 : 0
            width: 1
            height: parent.height
            color: root.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
        }
    
        Rectangle {
            visible: root.hoverIndex >= 0 && root.hoverIndex < root.points.length
            x: Math.max(0, Math.min(parent.width - width,
                (root.points.length > 1 ? root.hoverIndex * (parent.width - 10) / (root.points.length - 1) : 0) - width / 2))
            y: 7
            width: hoverPrice.implicitWidth + 16
            height: 28
            radius: 8
            color: root.dark ? "#3a3a3c" : "#ffffff"
            border.color: root.separatorColor
            border.width: 1
            Text {
                id: hoverPrice
                anchors.centerIn: parent
                text: root.hoverIndex >= 0 && root.hoverIndex < root.points.length
                    ? StockService.money(root.points[root.hoverIndex].v, root.snapshot.currency) : ""
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            function track(x) {
                if (root.points.length < 2) return
                root.hoverIndex = Math.max(0, Math.min(root.points.length - 1,
                    Math.round(x / width * (root.points.length - 1))))
            }
            onPressed: mouse => track(mouse.x)
            onPositionChanged: mouse => track(mouse.x)
            onExited: if (!pressed) root.hoverIndex = -1
            onReleased: if (!containsMouse) root.hoverIndex = -1
        }
    }
    
    Row {
        id: marketStats
        anchors { left: parent.left; right: parent.right; top: chartArea.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 8
        height: 38
        spacing: 30
        StatLabel { title: "LOW"; value: StockService.price(root.snapshot.low, root.snapshot.currency) }
        StatLabel { title: "HIGH"; value: StockService.price(root.snapshot.high, root.snapshot.currency) }
        StatLabel { title: "VOLUME"; value: Number(root.snapshot.volume || 0).toLocaleString(Qt.locale("en_US"), "f", 0) }
        Item { width: 1; height: 1 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.errorText !== "" ? root.errorText
                : (root.realtimeConnected ? "KIS WebSocket · Live"
                : (root.loading ? "Updating…" : (root.snapshot.mode === "kis" ? "KIS REST · " + (root.realtimeStatus || "Polling") : "Paper market data")))
            color: root.errorText !== "" ? root.negativeColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
    }
    
    Rectangle {
        id: separator
        anchors { left: parent.left; right: parent.right; top: marketStats.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        height: 1
        color: root.separatorColor
    }

    component RangeButton: Rectangle {
        id: rangeButton
        property string label: ""
        property bool selected: false
        signal triggered()
        width: 42
        height: 25
        radius: 8
        color: selected ? root.raisedColor : (rangeHover.hovered ? root.separatorColor : "transparent")
        scale: rangeArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: rangeButton.label
            color: rangeButton.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: rangeButton.selected ? Font.DemiBold : Font.Medium
        }
        HoverHandler { id: rangeHover }
        MouseArea {
            id: rangeArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: rangeButton.triggered()
        }
    }

    component StatLabel: Column {
        property string title: ""
        property string value: ""
        spacing: 2
        Text {
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.35
        }
        Text {
            text: parent.value
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }
}

