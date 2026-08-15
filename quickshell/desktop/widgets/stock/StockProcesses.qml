import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: backend
    required property var root
    property alias fetchDelay: fetchDelay
    property alias realtimeReconnect: realtimeReconnect
    property alias accountDelay: accountDelay
    property alias quote: quoteProcess
    property alias credentialStatus: credentialStatusProcess
    property alias account: accountProcess
    property alias order: orderProcess
    property alias preflight: preflightProcess
    property alias orderHistory: orderHistoryProcess
    property alias cancel: cancelProcess
    property alias realtime: realtimeProcess
    property alias analysis: analysisProcess
    property alias activity: activityProcess
    property alias forecast: forecastProcess
    property alias deleteForecast: deleteForecastProcess
    property alias backtest: backtestProcess
    property alias comparison: comparisonProcess
    property alias aiValidation: aiValidationProcess
    property alias aiUsage: aiUsageProcess
    property alias screener: screenerProcess
    property alias automation: automationProcess
    property alias autopilot: autopilotProcess
    property alias autopilotEmergency: autopilotEmergencyProcess
    property alias watchlist: watchlistProcess
    property alias watchSearch: watchSearchProcess
    property alias alertEvaluation: alertEvaluationProcess

Connections {
    target: StockService
    function onCredentialsChanged() {
        root.refreshCredentialState()
        root.scheduleFetch()
        root.scheduleRealtime()
    }
    function onRiskPolicyChanged() { root.refreshCredentialState() }
}

Timer {
    id: fetchDelay
    interval: 60
    onTriggered: root.fetchSnapshot()
}

Timer {
    interval: 60000
    repeat: true
    running: root.active
    onTriggered: root.fetchSnapshot()
}

Timer {
    id: realtimeReconnect
    interval: 650
    onTriggered: root.startRealtime()
}

Timer {
    id: accountDelay
    interval: 80
    onTriggered: root.refreshAccount()
}

Timer {
    interval: 120000
    repeat: true
    running: root.active && root.dataMode === "kis" && root.tradingConfigured
    onTriggered: root.refreshAccount()
}

Timer {
    interval: 30000
    repeat: true
    running: root.active && root.ordersVisible && root.dataMode === "kis" && root.tradingConfigured
    onTriggered: root.refreshOrderHistory()
}

Timer {
    interval: 60000
    repeat: true
    running: root.active && root.alertPollingReady
        && (root.enabledAlertCount > 0 || root.watchlistVisible || root.xxlLayout)
    onTriggered: root.refreshWatchlist()
}

Timer {
    interval: 60000
    repeat: true
    running: root.active && root.forecastVisible && root.quantTab === "forecasts"
    onTriggered: root.refreshForecasts(true)
}

Timer {
    interval: 10000
    repeat: true
    running: root.autopilotStatusPolling
    onTriggered: {
        root.refreshAutopilot()
        root.refreshAutomation()
    }
}

Process {
    id: quoteProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Quote unavailable")
                if (result.symbol !== root.symbol || result.market !== root.market
                        || result.range !== root.chartRange || result.mode !== root.dataMode
                        || (result.mode === "kis" && result.environment !== root.kisEnvironment)) {
                    root.pendingFetch = true
                    return
                }
                root.snapshot = result
                root.errorText = ""
                mainPanel.syncLimitPrice(StockService.price(result.price, result.currency))
                if (root.dataMode === "kis" && root.tradingConfigured) root.scheduleAccount()
            } catch (error) {
                root.errorText = error.message || "Quote unavailable"
            }
        }
    }
    onRunningChanged: root.loading = running
    onExited: {
        if (!running && root.pendingFetch) {
            root.pendingFetch = false
            root.fetchSnapshot()
        }
    }
}

Process {
    id: credentialStatusProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status === "ok") {
                    root.credentialState = result
                }
            } catch (error) {
                root.credentialState = ({ kisProd: false, kisPaper: false, kisProdAccount: false, kisPaperAccount: false, openai: false, claude: false, productionTradingEnabled: false })
            }
        }
    }
}

Process {
    id: accountProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Account unavailable")
                root.accountState = result
                root.accountError = ""
            } catch (error) {
                root.accountError = error.message || "Account unavailable"
            }
        }
    }
    onRunningChanged: root.accountBusy = running
    onExited: if (!running && root.pendingAccount) accountDelay.restart()
}

Process {
    id: orderProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Order failed")
                root.orderMessage = result.message + (result.orderNumber ? " · #" + result.orderNumber : "")
                root.orderError = ""
                mainPanel.clearLiveConfirmation()
                root.reviewVisible = false
                root.reviewOrder = ({})
                root.preflightState = ({})
                root.scheduleAccount()
                root.refreshOrderHistory()
            } catch (error) {
                root.orderError = error.message || "Order failed"
            }
        }
    }
    onStarted: {
        orderProcess.write(root.pendingOrder + "\n")
        root.pendingOrder = ""
    }
}

Process {
    id: preflightProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            if (!root.reviewVisible || root.preflightToken !== String(root.reviewOrder.token || "")) return
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Preflight failed")
                root.preflightState = result
                root.preflightError = ""
            } catch (error) {
                root.preflightState = ({})
                root.preflightError = error.message || "Preflight failed"
            }
        }
    }
    onStarted: {
        preflightProcess.write(root.pendingPreflight + "\n")
        root.pendingPreflight = ""
    }
    onExited: {
        if (root.preflightQueued && root.reviewVisible) {
            root.preflightQueued = false
            root.runPreflight()
        }
    }
}

Process {
    id: orderHistoryProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Orders unavailable")
                root.orderHistory = result.orders || []
                root.pendingOrderCount = Number(result.pendingCount || 0)
                root.orderHistoryError = ""
            } catch (error) {
                root.orderHistoryError = error.message || "Orders unavailable"
            }
        }
    }
    onRunningChanged: root.orderHistoryBusy = running
}

Process {
    id: cancelProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Cancellation failed")
                root.orderMessage = result.message
                root.orderHistoryError = ""
                root.cancelReviewVisible = false
                root.cancelTarget = ({})
                mainPanel.clearCancelConfirmation()
                root.refreshOrderHistory()
                root.scheduleAccount()
            } catch (error) {
                root.orderHistoryError = error.message || "Cancellation failed"
            }
        }
    }
    onStarted: {
        cancelProcess.write(root.pendingCancel + "\n")
        root.pendingCancel = ""
    }
}

Process {
    id: realtimeProcess
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: data => root.applyRealtime(data)
    }
    onExited: {
        root.realtimeConnected = false
        if (root.shouldStream) realtimeReconnect.restart()
    }
}

Process {
    id: analysisProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Analysis failed")
                if (result.modelCatalog) StockService.updateModelCatalog(result.modelCatalog)
                root.analysisResult = result
                root.analysisError = ""
                root.analysisMessage = result.disclaimer || ""
                root.refreshForecasts(false)
                if (root.quantTab === "usage") root.refreshAiUsage()
            } catch (error) {
                root.analysisError = error.message || "Analysis failed"
            }
        }
    }
    onRunningChanged: root.analysisBusy = running
    onStarted: {
        analysisProcess.write(root.pendingAnalysis + "\n")
        root.pendingAnalysis = ""
    }
}

Process {
    id: activityProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Activity unavailable")
                root.activityState = result
                root.activityError = ""
            } catch (error) {
                root.activityError = error.message || "Activity unavailable"
            }
        }
    }
    onRunningChanged: root.activityBusy = running
    onExited: {
        if (root.activityQueued && root.activityVisible) {
            root.activityQueued = false
            root.refreshActivity()
        }
    }
}

Process {
    id: forecastProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Forecast history unavailable")
                root.forecastState = result
                root.forecastError = ""
                if (root.quantTab === "ai_eval") root.refreshAiValidation()
            } catch (error) {
                root.forecastError = error.message || "Forecast history unavailable"
            }
        }
    }
    onStarted: {
        if (root.pendingForecastInput !== "") {
            forecastProcess.write(root.pendingForecastInput + "\n")
            root.pendingForecastInput = ""
        }
    }
    onExited: {
        if (root.forecastQueued) {
            root.forecastQueued = false
            root.refreshForecasts(true)
        }
    }
}

Process {
    id: deleteForecastProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Could not delete forecast")
                root.forecastState = result
                root.forecastError = ""
            } catch (error) {
                root.forecastError = error.message || "Could not delete forecast"
            }
        }
    }
}

Process {
    id: backtestProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Backtest unavailable")
                root.backtestResult = result
                root.backtestError = ""
            } catch (error) {
                root.backtestResult = ({})
                root.backtestError = error.message || "Backtest unavailable"
            }
        }
    }
    onRunningChanged: root.backtestBusy = running
}

Process {
    id: comparisonProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Strategy comparison unavailable")
                root.comparisonResult = result
                root.comparisonError = ""
            } catch (error) {
                root.comparisonResult = ({ items: [] })
                root.comparisonError = error.message || "Strategy comparison unavailable"
            }
        }
    }
    onRunningChanged: root.comparisonBusy = running
}

Process {
    id: aiValidationProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "AI validation unavailable")
                root.aiValidationResult = result
                root.aiValidationError = ""
            } catch (error) {
                root.aiValidationResult = ({ models: [], calibration: [], signals: {} })
                root.aiValidationError = error.message || "AI validation unavailable"
            }
        }
    }
    onRunningChanged: root.aiValidationBusy = running
    onExited: {
        if (root.aiValidationQueued) {
            root.aiValidationQueued = false
            root.refreshAiValidation()
        }
    }
}

Process {
    id: aiUsageProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "AI usage unavailable")
                root.aiUsageState = result
                root.aiUsageError = ""
            } catch (error) {
                root.aiUsageState = ({ summary: {}, models: [], recent: [] })
                root.aiUsageError = error.message || "AI usage unavailable"
            }
        }
    }
    onRunningChanged: root.aiUsageBusy = running
}

Process {
    id: screenerProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Screener unavailable")
                root.screenerState = result
                root.screenerError = ""
            } catch (error) {
                root.screenerState = ({ items: [], counts: {} })
                root.screenerError = error.message || "Screener unavailable"
            }
        }
    }
    onRunningChanged: root.screenerBusy = running
    onStarted: {
        screenerProcess.write(root.pendingScreener + "\n")
        root.pendingScreener = ""
    }
    onExited: {
        if (root.screenerQueued && root.forecastVisible && root.quantTab === "screener") {
            root.screenerQueued = false
            root.refreshScreener()
        }
    }
}

Process {
    id: automationProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Automation unavailable")
                if (result.kind === "plan") {
                    root.automationPlan = result
                    root.automationState = Object.assign({}, root.automationState, { policy: result.policy || {} })
                } else if (result.kind === "execution") {
                    root.automationExecution = result
                    root.automationRefreshQueued = true
                } else if (result.kind === "reconciliation") {
                    root.automationExecution = result.latest || ({})
                    root.automationState = Object.assign({}, root.automationState, { execution: result })
                } else if (result.part === 1) {
                    root.automationState = Object.assign({}, root.automationState, { operationsPart1: result })
                } else if (result.part === 2) {
                    root.automationState = Object.assign({}, root.automationState, { operationsPart2: result })
                } else if (result.productionAutomationEligible !== undefined
                        && result.gates !== undefined) {
                    root.automationState = Object.assign(
                        {}, root.automationState, { liveReadiness: result }
                    )
                } else {
                    root.automationState = result
                    if (result.autopilot && result.autopilot.kind === "autopilot")
                        root.autopilotState = result.autopilot
                }
                root.automationError = ""
            } catch (error) {
                root.automationError = error.message || "Automation unavailable"
            }
        }
    }
    onRunningChanged: root.automationBusy = running
    onStarted: {
        if (root.pendingAutomation !== "") {
            automationProcess.write(root.pendingAutomation + "\n")
            root.pendingAutomation = ""
        }
    }
    onExited: {
        if (root.automationRefreshQueued && (root.autopilotStatusPolling
                || (root.forecastVisible && root.quantTab === "automation"))) {
            root.automationRefreshQueued = false
            root.refreshAutomation()
        } else if (root.automationRefreshQueued) {
            root.automationRefreshQueued = false
        }
    }
}

Process {
    id: autopilotProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok" || result.kind !== "autopilot")
                    throw new Error(result.message || "AI Autopilot unavailable")
                root.autopilotState = result
                root.autopilotError = ""
            } catch (error) {
                root.autopilotError = error.message || "AI Autopilot unavailable"
            }
        }
    }
    onRunningChanged: root.autopilotBusy = running
    onStarted: {
        if (root.pendingAutopilot !== "") {
            autopilotProcess.write(root.pendingAutopilot + "\n")
            root.pendingAutopilot = ""
        }
    }
    onExited: {
        let completedAction = root.autopilotAction
        root.autopilotAction = ""
        if (root.autopilotRefreshQueued) {
            root.autopilotRefreshQueued = false
            root.refreshAutopilot()
        }
        if (completedAction === "autopilot-start" || completedAction === "autopilot-stop") {
            StockService.automationPolicyChanged()
            if (!automationProcess.running) root.refreshAutomation()
        } else if (root.forecastVisible && root.quantTab === "automation" && !automationProcess.running)
            root.refreshAutomation()
    }
}

Process {
    id: autopilotEmergencyProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok" || result.kind !== "autopilot")
                    throw new Error(result.message || "Emergency stop failed")
                root.autopilotState = result
                root.autopilotError = ""
            } catch (error) {
                root.autopilotError = error.message || "Emergency stop failed"
            }
        }
    }
    onRunningChanged: root.autopilotEmergencyBusy = running
    onStarted: {
        autopilotEmergencyProcess.write(root.pendingAutopilotEmergency + "\n")
        root.pendingAutopilotEmergency = ""
    }
    onExited: {
        StockService.automationPolicyChanged()
        if (!automationProcess.running)
            root.refreshAutomation()
    }
}

Process {
    id: watchlistProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Watchlist unavailable")
                root.watchlistState = result
                root.watchlistError = ""
                root.evaluatePriceAlerts(result.items || [])
            } catch (error) {
                root.watchlistError = error.message || "Watchlist unavailable"
            }
        }
    }
    onStarted: {
        watchlistProcess.write(root.pendingWatchlist + "\n")
        root.pendingWatchlist = ""
    }
    onExited: {
        if (root.watchlistQueued && (root.watchlistVisible || root.enabledAlertCount > 0 || root.xxlLayout)) {
            root.watchlistQueued = false
            root.refreshWatchlist()
        }
    }
}

Process {
    id: watchSearchProcess
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Search unavailable")
                if (result.query !== root.watchSearchText.trim()) return
                root.watchSearchResults = result.items || []
                root.watchSearchError = result.stale ? "Offline catalog · results may be limited" : ""
            } catch (error) {
                root.watchSearchResults = []
                root.watchSearchError = error.message || "Search unavailable"
            }
        }
    }
    onExited: {
        if (root.watchSearchQueued) {
            root.watchSearchQueued = false
            root.searchWatchlist(root.watchSearchText)
        }
    }
}

Process {
    id: alertEvaluationProcess
    stdinEnabled: true
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                let result = JSON.parse(text || "{}")
                if (result.status !== "ok") throw new Error(result.message || "Alert evaluation unavailable")
                root.applyAlertRuntimeStates(result.states || [])
            } catch (error) {
                root.watchlistError = error.message || "Alert evaluation unavailable"
            }
        }
    }
    onStarted: {
        alertEvaluationProcess.write(root.pendingAlertEvaluation + "\n")
        root.pendingAlertEvaluation = ""
    }
    onExited: {
        if (root.alertEvaluationQueued) {
            root.alertEvaluationQueued = false
            root.evaluatePriceAlerts((root.watchlistState || {}).items || [])
        }
    }
}
}
