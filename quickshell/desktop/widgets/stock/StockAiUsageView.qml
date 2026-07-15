import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: usageView
    required property var root
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 14
    visible: root.quantTab === "usage"

    Text {
        id: usageStatus
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 16
        text: root.aiUsageError !== "" ? root.aiUsageError
            : (root.aiUsageBusy ? "Reading the local token ledger…"
            : Number((root.aiUsageState.summary || {}).calls || 0) + " completed provider calls in the last 30 days")
        color: root.aiUsageError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Row {
        id: usageSummary
        anchors { left: parent.left; right: parent.right; top: usageStatus.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        UsageMetric {
            width: (parent.width - 24) / 4
            title: "API CALLS"
            value: Number((root.aiUsageState.summary || {}).calls || 0).toString()
            valueColor: "#64d2ff"
        }
        UsageMetric {
            width: (parent.width - 24) / 4
            title: "BILLABLE INPUT"
            value: root.formatTokenCount((root.aiUsageState.summary || {}).billableInputTokens)
        }
        UsageMetric {
            width: (parent.width - 24) / 4
            title: "OUTPUT"
            value: root.formatTokenCount((root.aiUsageState.summary || {}).outputTokens)
        }
        UsageMetric {
            width: (parent.width - 24) / 4
            title: "TOTAL TOKENS"
            value: root.formatTokenCount((root.aiUsageState.summary || {}).totalTokens)
        }
    }

    Row {
        id: usageColumns
        anchors { left: parent.left; right: parent.right; top: usageSummary.bottom; bottom: usageFootnote.top }
        anchors.topMargin: 12
        anchors.bottomMargin: 9
        spacing: 12

        Column {
            id: modelUsageColumn
            width: (parent.width - usageColumns.spacing) * 0.54
            height: parent.height
            spacing: 6
            Text {
                width: parent.width
                height: 13
                text: "MODEL USAGE"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                font.weight: Font.DemiBold
                font.letterSpacing: 0.35
            }
            ListView {
                id: modelUsageList
                width: parent.width
                height: parent.height - 19
                clip: true
                spacing: 6
                model: root.aiUsageState.models || []
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
                delegate: Rectangle {
                    required property var modelData
                    width: modelUsageList.width
                    height: 62
                    radius: 11
                    color: root.raisedColor
                    border.color: root.separatorColor
                    border.width: 1
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 4
                        radius: 2
                        color: modelData.provider === "openai" ? "#10a37f" : "#d97757"
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.52
                        spacing: 3
                        Text {
                            width: parent.width
                            text: modelData.model || "Unknown model"
                            color: root.foregroundColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: StockService.providerLabel(modelData.provider) + " · "
                                + Number(modelData.calls || 0) + " calls"
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.38
                        spacing: 3
                        Text {
                            width: parent.width
                            text: root.formatTokenCount(modelData.totalTokens) + " total"
                            color: root.foregroundColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            width: parent.width
                            text: root.formatTokenCount(modelData.billableInputTokens) + " in · "
                                + root.formatTokenCount(modelData.outputTokens) + " out"
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 8
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: modelUsageList.count === 0
                    text: root.aiUsageBusy ? "Loading…" : "No recorded API usage"
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                }
            }
        }

        Column {
            width: parent.width - parent.spacing - modelUsageColumn.width
            height: parent.height
            spacing: 6
            Text {
                width: parent.width
                height: 13
                text: "RECENT CALLS"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                font.weight: Font.DemiBold
                font.letterSpacing: 0.35
            }
            ListView {
                id: recentUsageList
                width: parent.width
                height: parent.height - 19
                clip: true
                spacing: 5
                model: root.aiUsageState.recent || []
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
                delegate: Rectangle {
                    required property var modelData
                    width: recentUsageList.width
                    height: 48
                    radius: 10
                    color: root.raisedColor
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: modelData.provider === "openai" ? "#10a37f" : "#d97757"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 14
                            spacing: 2
                            Text {
                                width: parent.width
                                text: StockService.providerLabel(modelData.provider) + " · "
                                    + (modelData.symbol || "Unknown") + " · " + (modelData.profile || "")
                                color: root.foregroundColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: root.analysisTime(modelData.timestamp) + " · "
                                    + root.formatTokenCount(modelData.totalTokens) + " tokens"
                                color: root.secondaryColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: recentUsageList.count === 0
                    text: root.aiUsageBusy ? "Loading…" : "No recent calls"
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                }
            }
        }
    }

    Text {
        id: usageFootnote
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 15
        text: root.aiUsageError !== "" ? root.aiUsageError
            : "Local metadata only · provider billing dashboards remain the source of truth for cost."
        color: root.aiUsageError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    component UsageMetric: Rectangle {
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
}
