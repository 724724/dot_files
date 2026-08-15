import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: review
    required property var root
    anchors.fill: parent
    visible: root.liveAutopilotReviewVisible || panel.opacity > 0.002
    z: 160

    readonly property var policy: root.automationState.policy || ({})
    readonly property var selectedCandidates: (root.autopilotState.candidates || []).filter(
        candidate => candidate.selected
    )
    readonly property string selectedMarkets: {
        let values = []
        for (let candidate of selectedCandidates) {
            let market = String(candidate.market || "")
            if (market !== "" && values.indexOf(market) < 0) values.push(market)
        }
        return values.length > 0 ? values.join(" · ") : "—"
    }

    onVisibleChanged: {
        if (!root.liveAutopilotReviewVisible) confirmationField.text = ""
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.48)
        opacity: root.liveAutopilotReviewVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.liveAutopilotReviewVisible
        onPressed: root.closeLiveAutopilotReview()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(540, parent.width - 36)
        height: 434
        radius: 18
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.liveAutopilotReviewVisible ? 1 : 0
        scale: root.liveAutopilotReviewVisible ? 1 : 0.965
        transformOrigin: Item.BottomRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: title
            anchors { left: parent.left; right: closeButton.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.rightMargin: 12
            anchors.topMargin: 19
            text: root.t("Review Live Auto Trading")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
            elide: Text.ElideRight
        }

        Rectangle {
            id: closeButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 15
            anchors.topMargin: 15
            width: 32
            height: 32
            radius: 10
            color: closeHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            HoverHandler { id: closeHover }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeLiveAutopilotReview()
            }
        }

        Text {
            id: subtitle
            anchors { left: title.left; right: parent.right; top: title.bottom }
            anchors.rightMargin: 22
            anchors.topMargin: 4
            text: root.t("KIS production account · actual broker orders")
            color: root.negativeColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: warning
            anchors { left: parent.left; right: parent.right; top: subtitle.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 14
            height: 72
            radius: 13
            color: Qt.rgba(1, 0.27, 0.23, root.dark ? 0.13 : 0.08)
            border.color: Qt.rgba(1, 0.27, 0.23, root.dark ? 0.28 : 0.18)
            border.width: 1
            Text {
                anchors.fill: parent
                anchors.margins: 13
                text: root.t("Actual funds will be traded. Market gaps, latency, and partial fills can exceed configured loss limits. Safety gates reduce risk but cannot prevent losses or guarantee returns.")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
        }

        Grid {
            id: summary
            anchors { left: parent.left; right: parent.right; top: warning.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 14
            columns: 2
            columnSpacing: 10
            rowSpacing: 8

            SummaryCell {
                title: root.t("Candidates")
                value: root.t("%1 selected", [Number(root.autopilotState.selectedCount || 0)])
            }
            SummaryCell {
                title: root.t("Markets")
                value: review.selectedMarkets
            }
            SummaryCell {
                title: root.t("Per-order limit")
                value: StockService.money(Number(review.policy.maxOrderValueKrw || 0), "KRW")
            }
            SummaryCell {
                title: root.t("Daily exposure limit")
                value: StockService.money(Number(review.policy.maxDailyNewExposureKrw || 0), "KRW")
            }
            SummaryCell {
                title: root.t("Daily loss halt")
                value: Number(review.policy.maxDailyLossPercent || 0).toFixed(2) + "%"
            }
            SummaryCell {
                title: root.t("Portfolio drawdown halt")
                value: Number(review.policy.maxPortfolioDrawdownPercent || 0).toFixed(2) + "%"
            }
        }

        Text {
            id: confirmationLabel
            anchors { left: parent.left; right: parent.right; top: summary.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 15
            text: root.t("Type START LIVE AUTO to authorize this live session.")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }

        Rectangle {
            id: confirmationBox
            anchors { left: parent.left; right: parent.right; top: confirmationLabel.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 7
            height: 40
            radius: 11
            color: root.raisedColor
            border.color: confirmationField.activeFocus ? root.negativeColor : root.separatorColor
            border.width: 1
            TextField {
                id: confirmationField
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                placeholderText: "START LIVE AUTO"
                color: root.foregroundColor
                placeholderTextColor: root.secondaryColor
                selectionColor: root.negativeColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                background: null
                onAccepted: {
                    if (text.trim() === "START LIVE AUTO" && !root.autopilotBusy)
                        root.startAutopilot(true, true)
                }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.bottomMargin: 18
            height: 40
            spacing: 10

            ReviewButton {
                width: (parent.width - parent.spacing) * 0.36
                label: root.t("Cancel")
                accent: root.secondaryColor
                filled: false
                enabled: root.autopilotAction !== "autopilot-start"
                onTriggered: root.closeLiveAutopilotReview()
            }
            ReviewButton {
                width: (parent.width - parent.spacing) * 0.64
                label: root.autopilotAction === "autopilot-start"
                    ? root.t("Starting…") : root.t("Start Live Auto Trading")
                accent: root.negativeColor
                filled: true
                enabled: confirmationField.text.trim() === "START LIVE AUTO"
                    && !root.autopilotBusy && root.autopilotCanStart
                onTriggered: root.startAutopilot(true, true)
            }
        }
    }

    component SummaryCell: Rectangle {
        property string title: ""
        property string value: "—"
        width: (summary.width - summary.columnSpacing) / 2
        height: 45
        radius: 11
        color: root.raisedColor
        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 2
            Text {
                width: parent.width
                text: parent.parent.title
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: parent.parent.value
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }

    component ReviewButton: Rectangle {
        id: button
        property string label: ""
        property color accent: "#0a84ff"
        property bool filled: false
        signal triggered()
        height: 40
        radius: 11
        color: filled ? accent : (buttonHover.hovered ? root.raisedColor : root.separatorColor)
        opacity: enabled ? 1 : 0.42
        scale: buttonArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: button.label
            color: button.filled ? "#ffffff" : root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        HoverHandler { id: buttonHover }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: button.triggered()
        }
    }
}
