import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: view
    required property var root
    visible: root.quantTab === "automation"

    readonly property var policy: root.automationState.policy || ({})
    readonly property var historyCounts: (root.automationState.history || {}).counts || ({})
    readonly property var executionState: root.automationState.execution || ({})
    readonly property var schedulerState: root.automationState.scheduler || ({})
    readonly property var shadowState: root.automationState.shadow || ({})
    readonly property var shadowMetrics: shadowState.metrics || ({})
    readonly property var promotionState: shadowState.promotion || ({})
    readonly property var executionQuality: promotionState.executionQuality || ({})
    readonly property var notificationState: root.automationState.notifications || ({})
    readonly property var backgroundState: root.automationState.background || ({})
    readonly property var auditState: root.automationState.audit || ({})
    readonly property var accountingState: root.automationState.accounting || ({})
    readonly property var resilienceState: root.automationState.resilience || ({})
    readonly property var liveState: root.automationState.liveReadiness || ({})
    readonly property var operationsState: root.automationState.operationsPart1 || ({})
    readonly property var operationsPartTwoState: root.automationState.operationsPart2 || ({})
    readonly property var gates: root.automationPlan.gates || []
    readonly property var allGates: gates.concat(promotionState.gates || [])
        .concat(accountingState.gates || []).concat(resilienceState.gates || [])
        .concat(operationsState.gates || []).concat(operationsPartTwoState.gates || [])
        .concat(liveState.gates || [])
    readonly property bool armed: !!policy.enabled && !policy.halted
    readonly property bool autoPaper: schedulerState.mode === "paper_auto"
    readonly property bool planAttempted: (executionState.records || []).some(
        record => record.planId === root.automationPlan.planId
    )
    property bool paperConfirmationPending: false
    property bool autoConfirmationPending: false
    readonly property string operationalLabel: {
        if (root.automationBusy || auditState.healthy === undefined) return root.t("Checking…")
        if (root.automationError !== "") return root.t("Unavailable")
        if (auditState.healthy === false) return root.t("Audit Failure")
        if (operationsState.eligible === false) return root.t("System Test Due")
        if (operationsPartTwoState.status === "error") return root.t("Online Validation Failure")
        if (operationsPartTwoState.phase === "halted") return root.t("Soak Halted")
        if (accountingState.healthy === false) return root.t("Reconcile Required")
        if (resilienceState.eligible === false) return root.t("Self-Test Due")
        if (policy.schedulerEnabled && !backgroundState.enabled) return root.t("Worker Off")
        if (backgroundState.enabled && backgroundState.workerStatus !== "active"
                && backgroundState.workerStatus !== "running") return root.t("Worker Stale")
        if (notificationState.enabled === false) return root.t("Alerts Off")
        if (operationsPartTwoState.phase === "not_started") return root.t("Online Test Due")
        if (operationsPartTwoState.phase === "collecting" || operationsPartTwoState.phase === "paused")
            return root.t("Soak %1%", [Number(operationsPartTwoState.progressPercent || 0).toFixed(0)])
        if (operationsPartTwoState.phase === "live_canary") return root.t("Live Canary")
        return root.t("Healthy")
    }
    readonly property color operationalColor: auditState.healthy === false
        || accountingState.healthy === false || resilienceState.eligible === false
        || operationsState.eligible === false
        || operationsPartTwoState.status === "error" || operationsPartTwoState.phase === "halted"
        || (policy.schedulerEnabled && !backgroundState.enabled)
        || (backgroundState.enabled && backgroundState.workerStatus !== "active"
            && backgroundState.workerStatus !== "running")
        ? root.negativeColor : (notificationState.enabled === false
            || operationsPartTwoState.phase !== "complete" ? "#ff9f0a" : root.positiveColor)

    Timer {
        id: paperConfirmationTimer
        interval: 3000
        onTriggered: view.paperConfirmationPending = false
    }
    Timer {
        id: autoConfirmationTimer
        interval: 3000
        onTriggered: view.autoConfirmationPending = false
    }

    Row {
        id: automationSummary
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 12
        height: 58
        spacing: 10

        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("MODE")
            value: policy.executionMode === "live" ? root.t("KIS Live")
                : (policy.executionMode === "paper" ? root.t("KIS Paper") : root.t("Dry Run"))
            accent: policy.executionMode === "live" ? root.negativeColor : "#0a84ff"
        }
        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("STATE")
            value: policy.halted ? root.t("Kill Switch") : (view.armed
                ? root.t(view.autoPaper
                    ? (policy.executionMode === "live" ? "Live Auto Armed" : "Paper Auto Armed")
                    : (policy.executionMode === "live" ? "KIS Live Armed"
                    : (policy.executionMode === "paper" ? "KIS Paper Armed" : "Dry Run Armed")))
                : root.t("Paused"))
            accent: policy.halted ? root.negativeColor : (view.armed ? root.positiveColor : "#ff9f0a")
        }
        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("OPERATIONS")
            value: view.operationalLabel
            accent: view.operationalColor
        }
        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("FILL QUALITY")
            value: Number(view.executionQuality.qualifiedFills || 0) > 0
                ? Number(view.executionQuality.averageAdverseSlippageBps || 0).toFixed(1) + " bp"
                : "—"
            accent: Number(view.executionQuality.qualifiedFills || 0) === 0 ? root.secondaryColor
                : (Number(view.executionQuality.averageAdverseSlippageBps || 0) <= 10
                ? root.positiveColor : root.negativeColor)
        }
        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("SHADOW RETURN")
            value: StockService.signed(Number(shadowMetrics.netReturnPercent || 0), 2) + "%"
            accent: Number(shadowMetrics.netReturnPercent || 0) > 0 ? root.positiveColor
                : (Number(shadowMetrics.netReturnPercent || 0) < 0 ? root.negativeColor : root.secondaryColor)
        }
        AutomationMetric {
            width: (parent.width - 50) / 6
            title: root.t("DECISION")
            value: root.automationDecisionLabel()
            accent: root.automationDecisionColor()
        }
    }

    Rectangle {
        id: protectionPanel
        anchors { left: parent.left; right: parent.right; top: automationSummary.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 12
        height: 106
        radius: 13
        color: root.raisedColor

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 5
            radius: 2.5
            color: policy.halted ? root.negativeColor : (view.armed ? root.positiveColor : "#ff9f0a")
        }
        Column {
            anchors { left: parent.left; right: automationControls.left; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            spacing: 5
            Text {
                text: root.t("Capital Protection Protocol")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
            }
            Text {
                width: parent.width
                text: root.t("Hard stop %1% · trailing starts +%2% · exits %3% below peak.", [
                    Number(policy.maxPositionLossPercent || 3).toFixed(1),
                    Number(policy.trailingActivationPercent || 5).toFixed(1),
                    Number(policy.trailingStopPercent || 2).toFixed(1)
                ])
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: view.autoPaper
                    ? root.t("Promotion-gated paper automation is active · every order is rechecked before submission.")
                    : (schedulerState.enabled
                    ? root.t("Observer checks every %1 minutes · promotion %2/%3 · automatic execution locked.", [
                        policy.schedulerIntervalMinutes || 30,
                        promotionState.passed || 0,
                        promotionState.total || 0
                    ])
                    : (policy.executionMode === "live"
                    ? root.t("Live execution · expiring session · every order rechecked")
                    : (policy.executionMode === "paper"
                    ? root.t("Only explicitly armed KIS orders can be sent. Live sessions expire automatically and every order is rechecked.")
                    : root.t("Dry Run records hypothetical plans and never contacts the broker order endpoint.")))
                    )
                color: "#0a84ff"
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
        Column {
            id: automationControls
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.rightMargin: 12
            width: 304
            spacing: 6
            Item {
                width: parent.width
                height: 32
                Row {
                    anchors.right: parent.right
                    height: parent.height
                    spacing: 7
                    ActionButton {
                        width: 104
                        label: policy.halted ? root.t("Reset Kill Switch") : (view.armed ? root.t("Pause") : root.t("Arm Dry Run"))
                        accent: policy.halted ? "#ff9f0a" : (view.armed ? root.secondaryColor : root.positiveColor)
                        enabled: !root.automationBusy
                        onTriggered: root.controlAutomation(policy.halted ? "reset-kill" : (view.armed ? "pause" : "arm"))
                    }
                    ActionButton {
                        visible: !view.armed && !policy.halted
                        width: visible ? 104 : 0
                        label: root.t("Arm KIS Paper")
                        accent: "#0a84ff"
                        enabled: !root.automationBusy && root.dataMode === "kis" && root.kisEnvironment === "paper"
                            && root.tradingConfigured
                        onTriggered: root.controlAutomation("arm-paper")
                    }
                    ActionButton {
                        visible: !view.armed && !policy.halted && policy.liveConsent === true
                            && !!view.liveState.productionAutomationEligible
                        width: visible ? 104 : 0
                        label: root.t("Arm KIS Live")
                        accent: root.negativeColor
                        enabled: !root.automationBusy && root.dataMode === "kis" && root.tradingConfigured
                        onTriggered: root.controlAutomation("arm-live")
                    }
                    ActionButton {
                        width: 82
                        label: root.t("Kill Switch")
                        accent: root.negativeColor
                        enabled: !root.automationBusy && !policy.halted
                        onTriggered: root.controlAutomation("kill")
                    }
                }
            }
            Row {
                width: parent.width
                height: 28
                spacing: 7
                ActionButton {
                    width: (parent.width - parent.spacing * 3) / 4
                    height: parent.height
                    label: root.t(schedulerState.enabled ? "Observer On" : "Enable Observer")
                    accent: schedulerState.enabled ? root.positiveColor : "#0a84ff"
                    filled: !!schedulerState.enabled
                    enabled: !root.automationBusy
                    onTriggered: root.controlAutomation(schedulerState.enabled ? "scheduler-disable" : "scheduler-enable")
                }
                ActionButton {
                    width: (parent.width - parent.spacing * 3) / 4
                    height: parent.height
                    label: view.autoPaper ? root.t("Auto Paper On")
                        : (promotionState.eligible
                        ? root.t(view.autoConfirmationPending ? "Confirm Auto Paper" : "Enable Auto Paper")
                        : root.t("Auto Paper Locked"))
                    accent: view.autoPaper ? root.positiveColor : (promotionState.eligible ? "#0a84ff" : root.secondaryColor)
                    filled: view.autoPaper
                    enabled: !root.automationBusy && (view.autoPaper || (view.armed
                        && policy.executionMode === "paper" && schedulerState.enabled && promotionState.eligible))
                    onTriggered: {
                        if (view.autoPaper) {
                            view.autoConfirmationPending = false
                            autoConfirmationTimer.stop()
                            root.controlAutomation("scheduler-auto-disable")
                        } else if (!view.autoConfirmationPending) {
                            view.autoConfirmationPending = true
                            autoConfirmationTimer.restart()
                        } else {
                            view.autoConfirmationPending = false
                            autoConfirmationTimer.stop()
                            root.controlAutomation("scheduler-auto-enable")
                        }
                    }
                }
                ActionButton {
                    width: (parent.width - parent.spacing * 3) / 4
                    height: parent.height
                    label: root.t(root.automationTargetEnabled ? "Target Selected" : "Observe This Stock")
                    accent: root.automationTargetEnabled ? root.positiveColor : root.secondaryColor
                    filled: root.automationTargetEnabled
                    enabled: root.dataMode === "kis" && root.kisEnvironment === "paper"
                        && root.market === "KRX" && root.aiProvider !== "none" && root.tradingConfigured
                    onTriggered: root.setAutomationTargetEnabled(!root.automationTargetEnabled)
                }
                ActionButton {
                    width: (parent.width - parent.spacing * 3) / 4
                    height: parent.height
                    label: root.t(!operationsState.eligible ? "Run System Test"
                        : (operationsPartTwoState.enabled ? "Pause Soak"
                        : (operationsPartTwoState.phase === "complete" ? "Validated"
                        : (operationsPartTwoState.startedAt ? "Resume Soak" : "Start Soak"))))
                    accent: operationsPartTwoState.phase === "complete" ? root.positiveColor
                        : (operationsPartTwoState.phase === "halted" ? root.negativeColor : "#ff9f0a")
                    filled: operationsPartTwoState.enabled || operationsPartTwoState.phase === "complete"
                    enabled: !root.automationBusy && operationsPartTwoState.phase !== "complete"
                    onTriggered: {
                        if (!operationsState.eligible) root.runAutomationPartOne()
                        else root.controlAutomationPartTwo(operationsPartTwoState.enabled ? "pause" : "start")
                    }
                }
            }
        }
    }

    Row {
        anchors { left: parent.left; right: parent.right; top: protectionPanel.bottom; bottom: parent.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 12
        anchors.bottomMargin: 14
        spacing: 10

        Rectangle {
            width: (parent.width - 10) * 0.39
            height: parent.height
            radius: 13
            color: root.raisedColor

            Text {
                id: planTitle
                anchors { left: parent.left; top: parent.top }
                anchors.leftMargin: 14
                anchors.topMargin: 12
                text: root.t("Guarded Order Plan")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; verticalCenter: planTitle.verticalCenter }
                anchors.rightMargin: 14
                text: Number(view.historyCounts.today || 0) + " " + root.t("today")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
            }

            Flickable {
                id: planScroll
                anchors { left: parent.left; right: parent.right; top: planTitle.bottom; bottom: planActions.top }
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 8
                clip: true
                contentWidth: width
                contentHeight: planContent.implicitHeight
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
                property var _ks: ({})
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        planGlide.stop()
                        if (Kinetic.onWheel(planScroll, event, planScroll._ks, { gain: 72 }))
                            planEndTimer.restart()
                    }
                }
                Timer {
                    id: planEndTimer
                    interval: 48
                    onTriggered: {
                        let glide = Kinetic.fling(planScroll, planScroll._ks, {})
                        if (glide) {
                            planGlide.from = glide.from
                            planGlide.to = glide.to
                            planGlide.restart()
                        }
                    }
                }
                SpringAnimation {
                    id: planGlide
                    target: planScroll
                    property: "contentY"
                    spring: 18
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }
                Column {
                    id: planContent
                    width: planScroll.width
                    spacing: 8
                    PlanRow {
                        label: root.t("Symbol")
                        value: root.automationPlan.symbol || root.symbol
                    }
                    PlanRow {
                        label: root.t("Action")
                        value: root.automationPlan.side === "buy" ? root.t("Buy")
                            : (root.automationPlan.side === "sell" ? root.t("Sell") : root.t("Hold"))
                        valueColor: root.automationPlan.side === "buy" ? root.positiveColor
                            : (root.automationPlan.side === "sell" ? root.negativeColor : root.secondaryColor)
                    }
                    PlanRow {
                        label: root.t("Quantity")
                        value: Number(root.automationPlan.quantity || 0).toString()
                    }
                    PlanRow {
                        label: root.t("Notional")
                        value: StockService.money(Number(root.automationPlan.estimatedNotional || 0), "KRW")
                    }
                    PlanRow {
                        label: root.t("Technical Score")
                        value: Number((root.automationPlan.technical || {}).score || 0).toFixed(0)
                    }
                    PlanRow {
                        label: root.t("AI Confidence")
                        value: Number((root.automationPlan.ai || {}).confidence || 0).toFixed(0) + "%"
                    }
                    PlanRow {
                        label: root.t("OOS Return")
                        value: StockService.signed(Number((root.automationPlan.validation || {}).oosReturnPct || 0), 2) + "%"
                    }
                    PlanRow {
                        label: root.t("Portfolio Drawdown")
                        value: Number((root.automationPlan.risk || {}).drawdownPercent || 0).toFixed(2) + "%"
                        valueColor: Number((root.automationPlan.risk || {}).drawdownPercent || 0) < 0
                            ? root.negativeColor : root.secondaryColor
                    }
                    PlanRow {
                        label: root.t("Risk-sized cap")
                        value: StockService.money(Number((root.automationPlan.riskSizing || {}).positionLimitKrw || 0), "KRW")
                            + " · " + Number((root.automationPlan.riskSizing || {}).riskDistancePercent || 0).toFixed(2) + "%"
                    }
                    PlanRow {
                        label: root.t("Sector exposure")
                        value: root.t((root.automationPlan.sectorRisk || {}).sector || "Unknown")
                            + " · " + Number((root.automationPlan.sectorRisk || {}).projectedExposurePercent || 0).toFixed(2) + "%"
                    }
                    PlanRow {
                        label: root.t("Max return correlation")
                        value: ((root.automationPlan.correlationRisk || {}).strongestSymbol || "—")
                            + " · " + Number((root.automationPlan.correlationRisk || {}).maxCorrelation || 0).toFixed(2)
                    }
                    PlanRow {
                        label: root.t("Market participation")
                        value: Number((root.automationPlan.liquidityRisk || {}).orderParticipationPercent || 0).toFixed(3) + "%"
                            + " · " + StockService.money(Number((root.automationPlan.liquidityRisk || {}).medianDailyTurnoverKrw || 0), "KRW")
                    }
                    PlanRow {
                        label: root.t("Portfolio tail risk")
                        value: "VaR " + Number((root.automationPlan.portfolioTailRisk || {}).var95Percent || 0).toFixed(2)
                            + "% · CVaR " + Number((root.automationPlan.portfolioTailRisk || {}).cvar95Percent || 0).toFixed(2)
                            + "% · " + root.t("Stress") + " "
                            + Number((root.automationPlan.portfolioTailRisk || {}).stressLossPercent || 0).toFixed(2) + "%"
                    }
                }
            }

            Row {
                id: planActions
                anchors { left: parent.left; right: parent.right; bottom: planMessage.top }
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 8
                height: 34
                spacing: 7
                ActionButton {
                    width: policy.executionMode === "paper" ? (parent.width - parent.spacing) / 2 : parent.width
                    height: parent.height
                    label: root.automationBusy ? root.t("Evaluating…")
                        : (policy.executionMode === "paper" ? root.t("Generate Paper Plan") : root.t("Generate Dry Run Plan"))
                    accent: "#0a84ff"
                    filled: true
                    enabled: !root.automationBusy
                    onTriggered: {
                        view.paperConfirmationPending = false
                        root.generateAutomationPlan()
                    }
                }
                ActionButton {
                    visible: policy.executionMode === "paper"
                    width: visible ? (parent.width - parent.spacing) / 2 : 0
                    height: parent.height
                    label: Number(view.executionState.unresolved || 0) > 0
                        ? root.t("Reconcile KIS")
                        : (view.planAttempted ? root.t("Plan Executed")
                        : (view.paperConfirmationPending ? root.t("Confirm Paper Order") : root.t("Execute Paper Plan")))
                    accent: Number(view.executionState.unresolved || 0) > 0 ? "#ff9f0a" : root.positiveColor
                    filled: !!root.automationPlan.executionEligible && Number(view.executionState.unresolved || 0) === 0
                    enabled: !root.automationBusy && (Number(view.executionState.unresolved || 0) > 0
                        || (!!root.automationPlan.executionEligible && !view.planAttempted))
                    onTriggered: {
                        if (Number(view.executionState.unresolved || 0) > 0) {
                            root.reconcileAutomation()
                        } else if (!view.paperConfirmationPending) {
                            view.paperConfirmationPending = true
                            paperConfirmationTimer.restart()
                        } else {
                            view.paperConfirmationPending = false
                            paperConfirmationTimer.stop()
                            root.executeAutomationPlan()
                        }
                    }
                }
            }
            Text {
                id: planMessage
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 10
                text: root.automationError !== "" ? root.t(root.automationError)
                    : (root.automationExecution.message ? root.t(root.automationExecution.message)
                    : (root.automationPlan.planId
                        ? (root.automationPlan.executionEligible ? root.t("Ready for explicit KIS paper confirmation") : root.t("No broker order sent"))
                        : root.t("Generate a plan to evaluate every safety gate.")))
                color: root.automationError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: parent.width - (parent.width - 10) * 0.39 - 10
            height: parent.height
            radius: 13
            color: root.raisedColor

            Text {
                id: gateTitle
                anchors { left: parent.left; top: parent.top }
                anchors.leftMargin: 14
                anchors.topMargin: 12
                text: root.t("Safety & Promotion Gates")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; verticalCenter: gateTitle.verticalCenter }
                anchors.rightMargin: 14
                text: view.allGates.length > 0
                    ? root.t("%1/%2 passed", [view.allGates.filter(gate => gate.passed).length, view.allGates.length])
                    : "—"
                color: promotionState.eligible ? root.positiveColor : "#ff9f0a"
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            ListView {
                id: gateList
                anchors { left: parent.left; right: parent.right; top: gateTitle.bottom; bottom: parent.bottom }
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 8
                anchors.bottomMargin: 10
                clip: true
                spacing: 5
                model: view.allGates
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
                property var _ks: ({})
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        gateGlide.stop()
                        if (Kinetic.onWheel(gateList, event, gateList._ks, { gain: 72 })) gateEndTimer.restart()
                    }
                }
                Timer {
                    id: gateEndTimer
                    interval: 48
                    onTriggered: {
                        let glide = Kinetic.fling(gateList, gateList._ks, {})
                        if (glide) {
                            gateGlide.from = glide.from
                            gateGlide.to = glide.to
                            gateGlide.restart()
                        }
                    }
                }
                SpringAnimation {
                    id: gateGlide
                    target: gateList
                    property: "contentY"
                    spring: 18
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }
                delegate: Rectangle {
                    required property var modelData
                    width: gateList.width
                    height: 34
                    radius: 9
                    color: modelData.passed
                        ? Qt.rgba(0.19, 0.82, 0.35, root.dark ? 0.12 : 0.09)
                        : Qt.rgba(1, 0.27, 0.23, root.dark ? 0.12 : 0.08)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 9
                        color: modelData.passed ? root.positiveColor : root.negativeColor
                        Text {
                            anchors.centerIn: parent
                            text: modelData.passed ? "✓" : "×"
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        anchors.leftMargin: 36
                        anchors.rightMargin: 10
                        text: root.t(modelData.message || modelData.code || "")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: gateList.count === 0
                    text: root.t("No safety evaluation yet.")
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                }
            }
        }
    }

    component AutomationMetric: Rectangle {
        property string title: ""
        property string value: "—"
        property color accent: "#0a84ff"
        height: 58
        radius: 11
        color: root.raisedColor
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 4
            radius: 2
            color: parent.accent
        }
        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 13
            anchors.rightMargin: 8
            spacing: 3
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
                color: parent.parent.accent
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }

    component PlanRow: Item {
        property string label: ""
        property string value: "—"
        property color valueColor: root.foregroundColor
        width: parent ? parent.width : 0
        height: 18
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        property string label: ""
        property color accent: "#0a84ff"
        property bool filled: false
        signal triggered()
        height: 32
        radius: 9
        color: filled ? accent : (actionHover.hovered ? Qt.rgba(accent.r, accent.g, accent.b, 0.22) : root.separatorColor)
        opacity: enabled ? 1 : 0.38
        scale: actionArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Text {
            anchors.centerIn: parent
            text: actionButton.label
            color: actionButton.filled ? "#ffffff" : actionButton.accent
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }
        HoverHandler { id: actionHover }
        MouseArea {
            id: actionArea
            anchors.fill: parent
            enabled: actionButton.enabled
            cursorShape: Qt.PointingHandCursor
            onReleased: if (containsMouse) actionButton.triggered()
        }
    }
}
