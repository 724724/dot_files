import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: aiValidationView
    required property var root
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 14
    visible: root.quantTab === "ai_eval"

    Row {
        id: aiValidationControls
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 36
        spacing: 10
        Rectangle {
            id: confidenceFloorPicker
            width: 180
            height: parent.height
            radius: 10
            color: root.dark ? "#38383b" : "#e9e9ed"
            Row {
                anchors.fill: parent
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: "50%"
                    selected: root.validationConfidenceFloor === 50
                    onChosen: { root.validationConfidenceFloor = 50; root.resetAiValidation(); root.refreshAiValidation() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: "60%"
                    selected: root.validationConfidenceFloor === 60
                    onChosen: { root.validationConfidenceFloor = 60; root.resetAiValidation(); root.refreshAiValidation() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: "70%"
                    selected: root.validationConfidenceFloor === 70
                    onChosen: { root.validationConfidenceFloor = 70; root.resetAiValidation(); root.refreshAiValidation() }
                }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - confidenceFloorPicker.width - parent.spacing
            spacing: 1
            Text {
                width: parent.width
                text: root.t("Qualified confidence floor")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: root.t("Lower-confidence predictions remain journaled but are excluded from qualified metrics.")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                elide: Text.ElideRight
            }
        }
    }

    Text {
        id: aiValidationStatus
        anchors { left: parent.left; right: parent.right; top: aiValidationControls.bottom }
        anchors.topMargin: 6
        height: 15
        text: root.aiValidationError !== "" ? root.t(root.aiValidationError)
            : (root.aiValidationBusy ? root.t("Recalculating calibration and qualified metrics…")
            : (root.aiValidationResult.status === "ok"
            ? root.t("%1 resolved forecasts · %2 model predictions", [
                Number(root.aiValidationResult.resolvedForecasts || 0),
                Number((root.aiValidationResult.summary || {}).samples || 0)])
            : root.t("Resolved forecasts are required before calibration becomes measurable.")))
        color: root.aiValidationError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Row {
        id: aiValidationSummary
        anchors { left: parent.left; right: parent.right; top: aiValidationStatus.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("QUALIFIED HIT RATE")
            value: root.aiValidationResult.status === "ok" ? Number((root.aiValidationResult.summary || {}).qualifiedHitRate || 0).toFixed(1) + "%" : "—"
            valueColor: Number((root.aiValidationResult.summary || {}).qualified || 0) >= 5 ? root.positiveColor : root.secondaryColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("QUALIFIED BRIER")
            value: root.aiValidationResult.status === "ok" ? Number((root.aiValidationResult.summary || {}).qualifiedBrierScore || 0).toFixed(3) : "—"
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("CALIBRATION ECE")
            value: root.aiValidationResult.status === "ok"
                ? root.t("%1pp", [Number((root.aiValidationResult.summary || {}).expectedCalibrationError || 0).toFixed(1)]) : "—"
            valueColor: Number((root.aiValidationResult.summary || {}).expectedCalibrationError || 0) <= 10 ? root.positiveColor : "#ff9f0a"
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("QUALIFIED / EXCLUDED")
            value: root.aiValidationResult.status === "ok" ? Number((root.aiValidationResult.summary || {}).qualified || 0) + " / "
                + Number((root.aiValidationResult.summary || {}).excluded || 0) : "—"
        }
    }

    Row {
        id: aiSignalSummary
        anchors { left: parent.left; right: parent.right; top: aiValidationSummary.bottom }
        anchors.topMargin: 8
        height: 68
        spacing: 8
        SignalValidationCard {
            width: (parent.width - 8) / 2
            title: root.t("Chart direction agreement")
            accent: "#0a84ff"
            metrics: (root.aiValidationResult.signals || {}).chart || ({})
        }
        SignalValidationCard {
            width: (parent.width - 8) / 2
            title: root.t("News direction agreement")
            accent: "#bf5af2"
            metrics: (root.aiValidationResult.signals || {}).news || ({})
        }
    }

    Text {
        id: aiModelHeader
        anchors { left: parent.left; right: parent.right; top: aiSignalSummary.bottom }
        anchors.topMargin: 9
        height: 13
        text: root.t("MODEL PERFORMANCE · RESOLVED PREDICTIONS")
        color: root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 8
        font.weight: Font.DemiBold
        font.letterSpacing: 0.35
    }

    ListView {
        id: aiModelList
        anchors { left: parent.left; right: parent.right; top: aiModelHeader.bottom; bottom: aiCalibration.top }
        anchors.topMargin: 5
        anchors.bottomMargin: 9
        clip: true
        spacing: 6
        model: root.aiValidationResult.models || []
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
        property var _ks: ({})
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                aiModelGlide.stop()
                if (Kinetic.onWheel(aiModelList, event, aiModelList._ks, { gain: 78 })) aiModelEndTimer.restart()
            }
        }
        Timer {
            id: aiModelEndTimer
            interval: 48
            onTriggered: {
                let glide = Kinetic.fling(aiModelList, aiModelList._ks, {})
                if (glide) {
                    aiModelGlide.from = glide.from
                    aiModelGlide.to = glide.to
                    aiModelGlide.restart()
                }
            }
        }
        SpringAnimation {
            id: aiModelGlide
            target: aiModelList
            property: "contentY"
            spring: 22
            damping: ThemeService.momentumDamping
            epsilon: 0.25
        }
        delegate: Rectangle {
            required property var modelData
            width: aiModelList.width
            height: 60
            radius: 11
            color: root.raisedColor
            border.color: root.separatorColor
            border.width: 1
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 4
                radius: 2
                color: root.validationStatusColor(modelData.dataStatus)
            }
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 230
                spacing: 3
                Text {
                    width: parent.width
                    text: modelData.model
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                Text {
                    width: parent.width
                    text: root.t(StockService.providerLabel(modelData.provider)).toUpperCase() + " · "
                        + root.t(StockService.profileLabel(modelData.profile)) + " · " + root.t(modelData.dataStatus)
                    color: root.validationStatusColor(modelData.dataStatus)
                    font.family: "SF Pro Display"
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }
            }
            Row {
                anchors { right: modelQualityPill.left; top: parent.top; bottom: parent.bottom }
                anchors.rightMargin: 8
                width: 280
                ComparisonValue {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width / 4
                    title: root.t("QUAL HIT")
                    value: Number(modelData.qualifiedHitRate || 0).toFixed(1) + "%"
                }
                ComparisonValue {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width / 4
                    title: root.t("BRIER")
                    value: Number(modelData.qualifiedBrierScore || 0).toFixed(3)
                }
                ComparisonValue {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width / 4
                    title: root.t("CAL GAP")
                    value: root.t("%1pp", [Number(modelData.calibrationGap || 0).toFixed(1)])
                }
                ComparisonValue {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width / 4
                    title: root.t("N / EXCL")
                    value: modelData.qualified + " / " + modelData.excluded
                }
            }
            Rectangle {
                id: modelQualityPill
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 58
                height: 30
                radius: 9
                color: root.separatorColor
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Number(modelData.qualityScore || 0) + "/100"
                        color: root.validationStatusColor(modelData.dataStatus)
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.t("QUALITY")
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 6
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: aiModelList.count === 0
            text: root.aiValidationBusy ? root.t("Loading model history…") : root.t("No resolved model predictions yet.")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
    }

    Row {
        id: aiCalibration
        anchors { left: parent.left; right: parent.right; bottom: aiValidationFootnote.top }
        anchors.bottomMargin: 8
        height: 58
        spacing: 8
        ReportMetric {
            width: (parent.width - 16) / 3
            title: root.t("CONFIDENCE 0–49")
            value: root.t("%1% actual · n%2", [Number(root.calibrationBucket(0).accuracy || 0).toFixed(1),
                Number(root.calibrationBucket(0).samples || 0)])
        }
        ReportMetric {
            width: (parent.width - 16) / 3
            title: root.t("CONFIDENCE 50–69")
            value: root.t("%1% actual · n%2", [Number(root.calibrationBucket(1).accuracy || 0).toFixed(1),
                Number(root.calibrationBucket(1).samples || 0)])
        }
        ReportMetric {
            width: (parent.width - 16) / 3
            title: root.t("CONFIDENCE 70–100")
            value: root.t("%1% actual · n%2", [Number(root.calibrationBucket(2).accuracy || 0).toFixed(1),
                Number(root.calibrationBucket(2).samples || 0)])
        }
    }

    Text {
        id: aiValidationFootnote
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 30
        text: root.aiValidationResult.status === "ok"
            ? root.t(root.aiValidationResult.methodology) + " " + root.t(root.aiValidationResult.disclaimer)
            : root.t("Signal agreement is descriptive, not causal attribution, and never authorizes an order.")
        color: root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 8
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    component QuantChoice: Item {
        id: quantChoice
        property string label: ""
        property bool selected: false
        signal chosen()
        scale: quantChoiceArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            color: quantChoice.selected ? (root.dark ? "#505055" : "#ffffff")
                : (quantChoiceHover.hovered ? root.separatorColor : "transparent")
        }
        Text {
            anchors.centerIn: parent
            text: quantChoice.label
            color: quantChoice.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: quantChoice.selected ? Font.DemiBold : Font.Medium
        }
        HoverHandler { id: quantChoiceHover }
        MouseArea {
            id: quantChoiceArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: quantChoice.chosen()
        }
    }

    component SignalValidationCard: Rectangle {
        property string title: ""
        property color accent: "#0a84ff"
        property var metrics: ({})
        radius: 11
        color: root.raisedColor
        border.color: root.separatorColor
        border.width: 1
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 4
            radius: 2
            color: parent.accent
        }
        Text {
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 14
            anchors.topMargin: 9
            width: parent.width - 28
            text: parent.title
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            anchors.bottomMargin: 8
            height: 30
            ComparisonValue {
                width: parent.width / 3
                title: root.t("QUAL HIT")
                value: Number(parent.parent.metrics.hitRate || 0).toFixed(1) + "%"
                valueColor: root.validationStatusColor(parent.parent.metrics.dataStatus)
            }
            ComparisonValue {
                width: parent.width / 3
                title: root.t("QUAL COVER")
                value: Number(parent.parent.metrics.qualifiedCoverage || 0).toFixed(1) + "%"
            }
            ComparisonValue {
                width: parent.width / 3
                title: root.t("AVG CONF")
                value: Number(parent.parent.metrics.averageConfidence || 0).toFixed(1) + "%"
            }
        }
    }

    component ComparisonValue: Column {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        spacing: 2
        Text {
            width: parent.width
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 7
            font.weight: Font.DemiBold
            font.letterSpacing: 0.25
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    component ReportMetric: Rectangle {
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
