import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: screenerView
    required property var root
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 14
    visible: root.quantTab === "screener"

    readonly property var counts: root.screenerState.counts || ({})

    Text {
        id: screenerStatus
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 16
        text: root.screenerError !== "" ? root.screenerError
            : (root.screenerBusy ? "Ranking the watchlist from completed daily closes…"
            : (Number(screenerView.counts.total || 0) > 0
            ? Number(screenerView.counts.screened || 0) + " of " + Number(screenerView.counts.total || 0)
              + " symbols screened · select a row to inspect"
            : "Add symbols to the watchlist, then refresh the screener."))
        color: root.screenerError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Row {
        id: screenerSummary
        anchors { left: parent.left; right: parent.right; top: screenerStatus.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        ScreenerMetric {
            width: (parent.width - 24) / 4
            title: "SCREENED"
            value: Number(screenerView.counts.screened || 0) + " / " + Number(screenerView.counts.total || 0)
            valueColor: "#0a84ff"
        }
        ScreenerMetric {
            width: (parent.width - 24) / 4
            title: "BULLISH"
            value: Number(screenerView.counts.bullish || 0).toString()
            valueColor: root.positiveColor
        }
        ScreenerMetric {
            width: (parent.width - 24) / 4
            title: "NEUTRAL"
            value: Number(screenerView.counts.neutral || 0).toString()
            valueColor: "#0a84ff"
        }
        ScreenerMetric {
            width: (parent.width - 24) / 4
            title: "BEARISH"
            value: Number(screenerView.counts.bearish || 0).toString()
            valueColor: root.negativeColor
        }
    }

    ListView {
        id: screenerList
        anchors { left: parent.left; right: parent.right; top: screenerSummary.bottom; bottom: screenerFootnote.top }
        anchors.topMargin: 10
        anchors.bottomMargin: 8
        clip: true
        spacing: 7
        model: root.screenerState.items || []
        boundsBehavior: Flickable.DragAndOvershootBounds
        boundsMovement: Flickable.FollowBoundsBehavior
        flickDeceleration: 6000
        maximumFlickVelocity: 6000
        rebound: Transition {
            SpringAnimation {
                properties: "x,y"
                spring: 22
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: screenCard
            required property var modelData
            readonly property bool available: modelData.status === "ok"
            readonly property real score: Number(modelData.score || 0)
            width: screenerList.width
            height: 78
            radius: 12
            color: screenHover.hovered && available
                ? (root.dark ? "#353538" : "#f0f0f4")
                : root.raisedColor
            border.color: root.separatorColor
            border.width: 1
            scale: screenArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 4
                radius: 2
                color: !screenCard.available ? root.secondaryColor
                    : (modelData.stance === "bullish" ? root.positiveColor
                    : (modelData.stance === "bearish" ? root.negativeColor : "#0a84ff"))
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                text: screenCard.available ? "#" + Number(modelData.rank || 0) : "—"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                spacing: 3
                Text {
                    width: parent.width
                    text: modelData.name || modelData.symbol
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.1
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: modelData.symbol + " · " + modelData.market
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
            Column {
                visible: screenCard.available
                anchors.left: parent.left
                anchors.leftMargin: 205
                anchors.verticalCenter: parent.verticalCenter
                width: 114
                spacing: 5
                Text {
                    width: parent.width
                    text: root.stanceLabel(modelData.stance) + " · " + (screenCard.score > 0 ? "+" : "") + screenCard.score
                    color: modelData.stance === "bullish" ? root.positiveColor
                        : (modelData.stance === "bearish" ? root.negativeColor : "#0a84ff")
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: root.separatorColor
                    Rectangle {
                        readonly property real magnitude: Math.min(1, Math.abs(screenCard.score) / 100)
                        x: screenCard.score >= 0 ? parent.width / 2 : parent.width / 2 - width
                        width: parent.width / 2 * magnitude
                        height: parent.height
                        radius: parent.radius
                        color: screenCard.score >= 0 ? root.positiveColor : root.negativeColor
                        Behavior on x { AppleSpring { spring: 22 } }
                        Behavior on width { AppleSpring { spring: 22 } }
                    }
                }
            }
            Row {
                visible: screenCard.available
                anchors.right: parent.right
                anchors.rightMargin: 13
                anchors.verticalCenter: parent.verticalCenter
                spacing: 15
                ScreenValue {
                    label: "20D"
                    value: (Number(modelData.momentum20Pct || 0) > 0 ? "+" : "")
                        + Number(modelData.momentum20Pct || 0).toFixed(1) + "%"
                    valueColor: Number(modelData.momentum20Pct || 0) >= 0 ? root.positiveColor : root.negativeColor
                }
                ScreenValue {
                    label: "RSI"
                    value: Number(modelData.rsi14 || 0).toFixed(0)
                }
                ScreenValue {
                    label: "VOL"
                    value: Number(modelData.annualizedVolatilityPct || 0).toFixed(0) + "%"
                }
                ScreenValue {
                    label: "DD 60D"
                    value: Number(modelData.drawdown60Pct || 0).toFixed(1) + "%"
                    valueColor: Number(modelData.drawdown60Pct || 0) < -10 ? root.negativeColor : root.foregroundColor
                }
            }
            Text {
                visible: !screenCard.available
                anchors.left: parent.left
                anchors.leftMargin: 205
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.message || "Screening unavailable"
                color: root.negativeColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
            HoverHandler { id: screenHover }
            MouseArea {
                id: screenArea
                anchors.fill: parent
                enabled: screenCard.available
                cursorShape: Qt.PointingHandCursor
                onPressed: root.selectScreenerItem(modelData)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: screenerList.count === 0
            width: parent.width - 40
            text: root.screenerError !== "" ? root.screenerError
                : (root.screenerBusy ? "Screening watchlist…" : "No watchlist symbols to screen.")
            color: root.screenerError !== "" ? root.negativeColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Text {
        id: screenerFootnote
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 15
        text: root.screenerError !== "" ? root.screenerError
            : "Trend + momentum + RSI ranking from completed closes · not investment advice or an order signal."
        color: root.screenerError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    component ScreenerMetric: Rectangle {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        height: 58
        radius: 11
        color: root.raisedColor
        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            Text {
                width: parent.width
                text: parent.parent.title
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                font.weight: Font.DemiBold
                font.letterSpacing: 0.35
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: parent.parent.value
                color: parent.parent.valueColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: -0.1
                elide: Text.ElideRight
            }
        }
    }

    component ScreenValue: Column {
        property string label: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        width: 52
        spacing: 3
        Text {
            width: parent.width
            text: parent.label
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 8
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }
        Text {
            width: parent.width
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }
    }
}
