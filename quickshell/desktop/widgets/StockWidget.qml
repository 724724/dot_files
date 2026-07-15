import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "kinetic.js" as Kinetic
import "stock" as Stock

Item {
    id: root
    property var frame
    readonly property var config: frame ? frame.dataObj : ({})
    readonly property string symbol: config.symbol || "005930"
    readonly property string market: config.market || "KRX"
    property string chartRange: config.range || "1D"
    readonly property string aiProvider: config.aiProvider || "none"
    readonly property string analysisProfile: config.analysisProfile || "balanced"
    readonly property string dataMode: config.dataMode || "demo"
    readonly property string kisEnvironment: config.kisEnvironment || "paper"
    readonly property var watchlist: Array.isArray(config.watchlist) ? config.watchlist.slice(0, 8) : [
        { symbol: "005930", market: "KRX" },
        { symbol: "000660", market: "KRX" },
        { symbol: "035420", market: "KRX" }
    ]
    readonly property var priceAlerts: Array.isArray(config.priceAlerts) ? config.priceAlerts.slice(0, 16) : []
    readonly property bool productionTradingEnabled: !!config.productionTradingEnabled && !!credentialState.productionTradingEnabled
    readonly property bool active: frame && frame.winRef ? frame.winRef.show : true
    readonly property bool dark: ThemeService.isDark
    readonly property color backgroundColor: dark ? "#1c1c1e" : "#f7f7f9"
    readonly property color foregroundColor: dark ? "#f5f5f7" : "#111114"
    readonly property color secondaryColor: dark ? "#98989d" : "#6e6e73"
    readonly property color separatorColor: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color raisedColor: dark ? "#2c2c2e" : "#ffffff"
    readonly property color positiveColor: "#30d158"
    readonly property color negativeColor: "#ff453a"
    readonly property color movementColor: Number(snapshot.change) >= 0 ? positiveColor : negativeColor
    property color cardColor: backgroundColor
    property bool lightCard: !dark
    property var snapshot: ({
        name: symbol,
        symbol: symbol,
        market: market,
        currency: market === "KRX" ? "KRW" : "USD",
        price: 0,
        change: 0,
        changePct: 0,
        high: 0,
        low: 0,
        volume: 0,
        buyingPower: market === "KRX" ? 10000000 : 10000,
        points: []
    })
    property bool loading: false
    property bool pendingFetch: false
    property string errorText: ""
    property string selectedTab: "trade"
    property string orderSide: "buy"
    property string orderType: "market"
    property bool reviewVisible: false
    property string orderMessage: ""
    property string orderError: ""
    property string pendingOrder: ""
    property var reviewOrder: ({})
    property var preflightState: ({})
    property string preflightError: ""
    property string pendingPreflight: ""
    property string preflightToken: ""
    property bool preflightQueued: false
    property bool ordersVisible: false
    property bool portfolioVisible: false
    property bool activityVisible: false
    property string activityFilter: "all"
    property var activityState: ({ activity: [], counts: {} })
    property string activityError: ""
    property bool activityQueued: false
    property bool watchlistVisible: false
    property var watchlistState: ({ items: [] })
    property string watchlistError: ""
    property string pendingWatchlist: ""
    property bool watchlistQueued: false
    property string watchSearchText: ""
    property var watchSearchResults: []
    property string watchSearchError: ""
    property bool watchSearchQueued: false
    property bool alertsVisible: false
    property string alertDraftSymbol: symbol
    property string alertDraftMarket: market
    property real alertDraftPrice: Number(snapshot.price || 0)
    property string alertDirection: "above"
    property string alertTargetText: ""
    property string alertEditorError: ""
    property bool cancelReviewVisible: false
    property var orderHistory: []
    property int pendingOrderCount: 0
    property bool orderHistoryBusy: false
    property string orderHistoryError: ""
    property var cancelTarget: ({})
    property string pendingCancel: ""
    property var accountState: ({})
    property bool accountBusy: false
    property bool pendingAccount: false
    property string accountError: ""
    property string analysisMessage: ""
    property var analysisResult: ({})
    property bool analysisBusy: false
    property string analysisError: ""
    property string pendingAnalysis: ""
    property bool analysisReportVisible: false
    property bool forecastVisible: false
    property string quantTab: "forecasts"
    property var forecastState: ({ items: [], stats: {} })
    property string forecastError: ""
    property string pendingForecastInput: ""
    property bool forecastQueued: false
    property string backtestStrategy: "trend"
    property string backtestCostProfile: "base"
    property var backtestResult: ({})
    property string backtestError: ""
    property bool backtestBusy: false
    property var comparisonResult: ({ items: [] })
    property string comparisonError: ""
    property bool comparisonBusy: false
    property var aiValidationResult: ({ models: [], calibration: [], signals: {} })
    property string aiValidationError: ""
    property bool aiValidationBusy: false
    property bool aiValidationQueued: false
    property int validationConfidenceFloor: 60
    property var aiUsageState: ({ summary: {}, models: [], recent: [] })
    property string aiUsageError: ""
    property bool aiUsageBusy: false
    property var screenerState: ({ items: [], counts: {} })
    property string screenerError: ""
    property bool screenerBusy: false
    property string pendingScreener: ""
    property bool screenerQueued: false
    property bool realtimeConnected: false
    property string realtimeStatus: ""
    property int hoverIndex: -1
    property var credentialState: ({ kisProd: false, kisPaper: false, kisProdAccount: false, kisPaperAccount: false, openai: false, claude: false, productionTradingEnabled: false })
    readonly property var points: snapshot.points || []
    readonly property bool kisConfigured: kisEnvironment === "prod" ? !!credentialState.kisProd : !!credentialState.kisPaper
    readonly property bool kisAccountConfigured: kisEnvironment === "prod" ? !!credentialState.kisProdAccount : !!credentialState.kisPaperAccount
    readonly property bool tradingConfigured: kisConfigured && kisAccountConfigured
    readonly property bool paperOrderReady: dataMode === "kis" && kisEnvironment === "paper" && market === "KRX"
        && tradingConfigured && accountState.status === "ok"
    readonly property bool productionOrderReady: dataMode === "kis" && kisEnvironment === "prod" && market === "KRX"
        && productionTradingEnabled && tradingConfigured && accountState.status === "ok"
    readonly property bool demoOrderReady: dataMode === "demo"
    readonly property bool shouldStream: active && dataMode === "kis" && market === "KRX" && kisConfigured
    readonly property bool aiConfigured: aiProvider === "openai" ? !!credentialState.openai
        : (aiProvider === "claude" ? !!credentialState.claude
        : (aiProvider === "both" ? !!credentialState.openai && !!credentialState.claude : false))
    readonly property int quantity: mainPanel.quantity
    readonly property real orderPrice: mainPanel.orderPrice
    readonly property real estimatedTotal: quantity * orderPrice
    readonly property bool quantityAvailable: demoOrderReady || ((paperOrderReady || productionOrderReady) && (orderSide === "buy"
        ? quantity <= Number(accountState.buyingQuantity || 0)
        : quantity <= Number(accountState.sellableQuantity || 0)))
    readonly property bool canReviewOrder: orderPrice > 0 && quantityAvailable && !backend.order.running
    readonly property bool preflightReady: demoOrderReady || (preflightState.status === "ok" && !backend.preflight.running)
    readonly property bool orderRunning: backend.order.running
    readonly property bool preflightRunning: backend.preflight.running
    readonly property bool cancelRunning: backend.cancel.running
    readonly property bool currentWatched: watchlist.some(item => item.symbol === symbol && item.market === market)
    readonly property int enabledAlertCount: priceAlerts.filter(alert => alert.enabled !== false).length
    readonly property bool alertPollingReady: dataMode === "demo" || kisConfigured

    onSymbolChanged: { resetAnalysis(); resetBacktest(); resetComparison(); resetAiValidation(); closeForecasts(); scheduleFetch(); scheduleRealtime(); scheduleAccount(); ordersVisible = false; portfolioVisible = false }
    onMarketChanged: { resetAnalysis(); resetBacktest(); resetComparison(); resetAiValidation(); closeForecasts(); scheduleFetch(); scheduleRealtime() }
    onDataModeChanged: {
        resetBacktest()
        resetComparison()
        resetScreener()
        scheduleFetch()
        scheduleRealtime()
        scheduleAccount()
        ordersVisible = false
        portfolioVisible = false
        if (watchlistVisible || enabledAlertCount > 0) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onKisEnvironmentChanged: {
        resetBacktest()
        resetComparison()
        resetScreener()
        scheduleFetch()
        scheduleRealtime()
        scheduleAccount()
        ordersVisible = false
        portfolioVisible = false
        if (watchlistVisible || enabledAlertCount > 0) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onWatchlistChanged: {
        resetScreener()
        if (watchlistVisible || enabledAlertCount > 0) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onKisConfiguredChanged: {
        scheduleRealtime()
        if (enabledAlertCount > 0 && alertPollingReady) Qt.callLater(root.refreshWatchlist)
    }
    onTradingConfiguredChanged: scheduleAccount()
    onProductionTradingEnabledChanged: {
        reviewVisible = false
        preflightState = ({})
        cancelReviewVisible = false
    }
    onOrderTypeChanged: scheduleAccount()
    onAiProviderChanged: resetAnalysis()
    onAnalysisProfileChanged: resetAnalysis()
    onSelectedTabChanged: if (selectedTab !== "ai") { analysisReportVisible = false; closeForecasts() }
    onChartRangeChanged: {
        resetAnalysis()
        if (frame && frame.dataObj && frame.dataObj.range !== chartRange) frame.save({ range: chartRange })
        scheduleFetch()
    }
    onActiveChanged: {
        if (active) {
            scheduleFetch()
            scheduleRealtime()
            if (enabledAlertCount > 0) refreshWatchlist()
        } else {
            analysisReportVisible = false
            closeForecasts()
            closeAlerts()
            closeActivity()
            closeWatchlist()
            stopRealtime()
        }
    }
    Keys.onEscapePressed: event => {
        if (forecastVisible) {
            closeForecasts()
            event.accepted = true
        } else if (alertsVisible) {
            closeAlerts()
            event.accepted = true
        } else if (watchlistVisible) {
            closeWatchlist()
            event.accepted = true
        } else if (activityVisible) {
            closeActivity()
            event.accepted = true
        } else if (analysisReportVisible) {
            analysisReportVisible = false
            event.accepted = true
        }
    }
    onSnapshotChanged: marketOverview.requestPaint()
    onWidthChanged: marketOverview.requestPaint()
    Component.onCompleted: {
        refreshCredentialState()
        scheduleFetch()
        scheduleRealtime()
        scheduleAccount()
        if (enabledAlertCount > 0 && alertPollingReady) Qt.callLater(root.refreshWatchlist)
    }

    Stock.StockProcesses {
        id: backend
        root: root
    }

    function scheduleFetch() {
        if (active) backend.fetchDelay.restart()
    }

    function scheduleAccount() {
        accountState = ({})
        accountError = ""
        pendingAccount = false
        if (active && dataMode === "kis" && tradingConfigured && market === "KRX") {
            pendingAccount = true
            if (!backend.account.running) backend.accountDelay.restart()
        }
    }

    function refreshAccount() {
        if (!active || dataMode !== "kis" || !tradingConfigured || market !== "KRX" || backend.account.running) return
        pendingAccount = false
        backend.account.command = ["python3", StockService.stockScript, "account", kisEnvironment, symbol,
            String(orderPrice), orderType]
        backend.account.running = true
    }

    function refreshOrderHistory() {
        if (dataMode !== "kis" || !tradingConfigured || market !== "KRX" || backend.orderHistory.running) return
        backend.orderHistory.command = ["python3", StockService.stockScript, "orders", kisEnvironment, symbol]
        backend.orderHistory.running = true
    }

    function openOrders() {
        if (dataMode !== "kis" || !tradingConfigured || market !== "KRX") return
        portfolioVisible = false
        ordersVisible = true
        cancelReviewVisible = false
        orderHistoryError = ""
        refreshOrderHistory()
    }

    function closeOrders() {
        if (backend.cancel.running) return
        ordersVisible = false
        cancelReviewVisible = false
        cancelTarget = ({})
        mainPanel.clearCancelConfirmation()
    }

    function openActivity() {
        activityVisible = true
        activityError = ""
        activityQueued = false
        forceActiveFocus()
        refreshActivity()
    }

    function closeActivity() {
        activityVisible = false
        activityQueued = false
    }

    function refreshActivity() {
        if (backend.activity.running) {
            activityQueued = true
            return
        }
        backend.activity.command = ["python3", StockService.stockScript, "activity", activityFilter, "50"]
        backend.activity.running = true
    }

    function chooseActivityFilter(value) {
        if (activityFilter === value) return
        activityFilter = value
        refreshActivity()
    }

    function activityStatusLabel(value) {
        if (value === "accepted") return "Accepted"
        if (value === "failed") return "Failed"
        if (value === "uncertain") return "Verify"
        return "Submitting"
    }

    function activityStatusColor(value) {
        if (value === "accepted") return positiveColor
        if (value === "failed") return negativeColor
        if (value === "uncertain") return "#ff9f0a"
        return "#0a84ff"
    }

    function activityTitle(event) {
        if (event.action === "cancel") return "Cancel order #" + (event.originalOrderNumber || "Unknown")
        let side = event.side === "sell" ? "Sell" : "Buy"
        return side + " " + Number(event.quantity || 0) + " " + (event.symbol || "Unknown")
    }

    function activityDetail(event) {
        if (event.message) return event.message
        if (event.orderNumber) return "Broker order #" + event.orderNumber
        if (event.action === "order" && Number(event.estimatedNotional || 0) > 0)
            return StockService.money(event.estimatedNotional, "KRW") + " estimated"
        return event.status === "uncertain" ? "Final broker state is unknown; verify with KIS." : "Local audit event"
    }

    function openPortfolio() {
        if (dataMode !== "kis" || !tradingConfigured || market !== "KRX") return
        ordersVisible = false
        cancelReviewVisible = false
        portfolioVisible = true
        if (!backend.account.running) refreshAccount()
    }

    function closePortfolio() {
        portfolioVisible = false
    }

    function selectHolding(holding) {
        if (!holding || !holding.symbol || !frame) return
        closePortfolio()
        frame.save({ symbol: holding.symbol, market: "KRX" })
    }

    function openWatchlist() {
        watchlistVisible = true
        watchlistError = ""
        watchlistQueued = false
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        watchSearchQueued = false
        forceActiveFocus()
        refreshWatchlist()
    }

    function closeWatchlist() {
        watchlistVisible = false
        watchlistQueued = false
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        watchSearchQueued = false
    }

    function refreshWatchlist() {
        if ((!watchlistVisible && enabledAlertCount === 0) || !alertPollingReady) return
        if (backend.watchlist.running) {
            watchlistQueued = true
            return
        }
        if (watchlist.length === 0) {
            watchlistState = ({ status: "ok", items: [] })
            return
        }
        pendingWatchlist = JSON.stringify(watchlist)
        backend.watchlist.command = ["python3", StockService.stockScript, "watchlist", dataMode, kisEnvironment]
        backend.watchlist.running = true
    }

    function saveWatchlist(next) {
        if (!frame) return
        frame.save({ watchlist: next.slice(0, 8) })
    }

    function searchWatchlist(value) {
        watchSearchText = value
        watchSearchError = ""
        watchlistError = ""
        if (value.trim() === "") {
            watchSearchResults = []
            watchSearchQueued = false
            return
        }
        if (backend.watchSearch.running) {
            watchSearchQueued = true
            return
        }
        backend.watchSearch.command = ["python3", StockService.stockScript, "search", value.trim(), "8",
            dataMode === "kis" ? "KRX" : "ALL"]
        backend.watchSearch.running = true
    }

    function addSearchResult(item) {
        if (!item || !item.symbol || !frame) return
        if (watchlist.some(entry => entry.symbol === item.symbol && entry.market === item.market)) {
            watchSearchError = "Already in your watchlist."
            return
        }
        if (watchlist.length >= 8) {
            watchSearchError = "Watchlist is limited to 8 symbols."
            return
        }
        saveWatchlist(watchlist.concat([{ symbol: item.symbol, market: item.market }]))
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        forceActiveFocus()
    }

    function toggleCurrentWatch() {
        let next = watchlist.slice()
        let index = next.findIndex(item => item.symbol === symbol && item.market === market)
        if (index >= 0) {
            next.splice(index, 1)
        } else {
            if (next.length >= 8) {
                openWatchlist()
                watchlistError = "Watchlist is limited to 8 symbols."
                return
            }
            next.push({ symbol: symbol, market: market })
        }
        saveWatchlist(next)
    }

    function removeWatchItem(item) {
        if (alertCountFor(item) > 0) {
            watchlistError = "Remove this symbol's price alerts first."
            return
        }
        let next = watchlist.filter(entry => !(entry.symbol === item.symbol && entry.market === item.market))
        saveWatchlist(next)
    }

    function selectWatchItem(item) {
        if (!item || !item.symbol || !frame) return
        closeWatchlist()
        frame.save({ symbol: item.symbol, market: item.market || "KRX" })
    }

    function alertCountFor(item) {
        if (!item) return 0
        return priceAlerts.filter(alert => alert.symbol === item.symbol && alert.market === (item.market || "KRX")).length
    }

    function openAlerts(item) {
        let source = item && item.symbol ? item : snapshot
        alertDraftSymbol = source.symbol || symbol
        alertDraftMarket = source.market || market
        alertDraftPrice = Number(source.price || (source.symbol === symbol ? snapshot.price : 0))
        alertDirection = "above"
        alertEditorError = ""
        alertTargetText = ""
        closeWatchlist()
        alertsVisible = true
        forceActiveFocus()
    }

    function closeAlerts() {
        alertsVisible = false
        alertEditorError = ""
        alertTargetText = ""
    }

    function savePriceAlerts(next, watchlistPatch) {
        if (!frame) return
        let patch = { priceAlerts: next.slice(0, 16) }
        if (watchlistPatch) patch.watchlist = watchlistPatch.slice(0, 8)
        frame.save(patch)
    }

    function addPriceAlert() {
        let target = Number(alertTargetText.trim().replace(/,/g, ""))
        if (!isFinite(target) || target <= 0) {
            alertEditorError = "Enter a valid target price."
            return
        }
        if (priceAlerts.length >= 16) {
            alertEditorError = "Price alerts are limited to 16."
            return
        }
        let watched = watchlist.slice()
        if (!watched.some(item => item.symbol === alertDraftSymbol && item.market === alertDraftMarket)) {
            if (watched.length >= 8) {
                alertEditorError = "Watchlist is full. Remove a symbol before adding this alert."
                return
            }
            watched.push({ symbol: alertDraftSymbol, market: alertDraftMarket })
        }
        let duplicate = priceAlerts.some(alert => alert.symbol === alertDraftSymbol
            && alert.market === alertDraftMarket && alert.direction === alertDirection
            && Math.abs(Number(alert.target) - target) < 0.000001)
        if (duplicate) {
            alertEditorError = "That price alert already exists."
            return
        }
        let next = priceAlerts.slice()
        let alreadyCrossed = alertDraftPrice > 0 && (alertDirection === "below"
            ? alertDraftPrice <= target : alertDraftPrice >= target)
        next.push({
            id: Date.now().toString(36) + "-" + Math.floor(Math.random() * 1679616).toString(36),
            symbol: alertDraftSymbol,
            market: alertDraftMarket,
            direction: alertDirection,
            target: target,
            enabled: true,
            armed: !alreadyCrossed,
            lastTriggeredAt: 0
        })
        savePriceAlerts(next, watched)
        alertEditorError = ""
        alertTargetText = ""
        Qt.callLater(root.refreshWatchlist)
    }

    function togglePriceAlert(id) {
        let next = priceAlerts.map(alert => alert.id === id
            ? Object.assign({}, alert, { enabled: alert.enabled === false, armed: alert.armed !== false })
            : alert)
        savePriceAlerts(next)
        if (next.some(alert => alert.id === id && alert.enabled !== false)) Qt.callLater(root.refreshWatchlist)
    }

    function removePriceAlert(id) {
        savePriceAlerts(priceAlerts.filter(alert => alert.id !== id))
    }

    function alertDirectionLabel(direction) {
        return direction === "below" ? "Falls below" : "Rises above"
    }

    function alertCurrency(alert) {
        return alert.market === "KRX" ? "KRW" : "USD"
    }

    function evaluatePriceAlerts(items) {
        if (priceAlerts.length === 0 || items.length === 0) return
        let quotes = ({})
        for (let i = 0; i < items.length; i++) {
            let quote = items[i]
            if (quote.status !== "error") quotes[quote.market + ":" + quote.symbol] = quote
        }
        let changed = false
        let next = priceAlerts.map(alert => {
            if (alert.enabled === false) return alert
            let quote = quotes[alert.market + ":" + alert.symbol]
            let price = quote ? Number(quote.price) : 0
            let target = Number(alert.target)
            if (!isFinite(price) || price <= 0 || !isFinite(target) || target <= 0) return alert
            let armed = alert.armed !== false
            let crossed = alert.direction === "below" ? price <= target : price >= target
            let hysteresis = Math.max(target * 0.002, alert.market === "KRX" ? 1 : 0.01)
            let rearmed = alert.direction === "below" ? price >= target + hysteresis : price <= target - hysteresis
            if (armed && crossed) {
                changed = true
                let currency = quote.currency || alertCurrency(alert)
                Quickshell.execDetached([
                    "notify-send", "-a", "Stocks", "-t", "10000",
                    (quote.name || alert.symbol) + " price alert",
                    alertDirectionLabel(alert.direction) + " " + StockService.money(target, currency)
                        + " · Now " + StockService.money(price, currency)
                ])
                return Object.assign({}, alert, { armed: false, lastTriggeredAt: Date.now() })
            }
            if (!armed && rearmed) {
                changed = true
                return Object.assign({}, alert, { armed: true })
            }
            return alert
        })
        if (changed) savePriceAlerts(next)
    }

    function requestCancel(order) {
        if (!order.canCancel || backend.cancel.running) return
        if (kisEnvironment === "prod" && !productionTradingEnabled) return
        cancelTarget = order
        cancelReviewVisible = true
        orderHistoryError = ""
        mainPanel.clearCancelConfirmation()
    }

    function confirmCancel() {
        if (!cancelTarget.orderNumber || backend.cancel.running) return
        if (kisEnvironment === "prod" && (!productionTradingEnabled || mainPanel.cancelConfirmation !== "LIVE")) return
        pendingCancel = JSON.stringify({
            orderNumber: cancelTarget.orderNumber,
            confirmation: kisEnvironment === "prod" ? mainPanel.cancelConfirmation : ""
        })
        backend.cancel.command = ["python3", StockService.stockScript, "cancel", kisEnvironment]
        backend.cancel.running = true
    }

    function orderStateLabel(state) {
        if (state === "filled") return "Filled"
        if (state === "partial") return "Partially filled"
        if (state === "pending") return "Pending"
        if (state === "canceled") return "Canceled"
        if (state === "rejected") return "Rejected"
        return "Submitted"
    }

    function fetchSnapshot() {
        if (!active) return
        if (backend.quote.running) {
            pendingFetch = true
            return
        }
        backend.quote.command = ["python3", StockService.stockScript, "snapshot", symbol, market,
            chartRange, dataMode, kisEnvironment]
        backend.quote.running = true
    }

    function refreshCredentialState() {
        if (backend.credentialStatus.running) return
        backend.credentialStatus.command = ["python3", StockService.stockScript, "credentials", "status"]
        backend.credentialStatus.running = true
    }

    function scheduleRealtime() {
        backend.realtimeReconnect.stop()
        stopRealtime()
        if (shouldStream) backend.realtimeReconnect.restart()
    }

    function startRealtime() {
        if (!shouldStream) return
        if (backend.realtime.running) {
            backend.realtimeReconnect.restart()
            return
        }
        realtimeStatus = "Connecting"
        backend.realtime.command = ["python3", StockService.stockScript, "stream", symbol, kisEnvironment]
        backend.realtime.running = true
    }

    function stopRealtime() {
        realtimeConnected = false
        if (backend.realtime.running) {
            backend.realtime.signal(15)
        }
    }

    function applyRealtime(line) {
        try {
            let event = JSON.parse(line || "{}")
            if (event.status === "connecting") {
                realtimeStatus = "Connecting"
                return
            }
            if (event.status === "connected") {
                realtimeConnected = true
                realtimeStatus = "Live"
                return
            }
            if (event.status === "error") {
                realtimeConnected = false
                realtimeStatus = event.message || "Stream error"
                return
            }
            if (event.status !== "tick") return
            realtimeConnected = true
            realtimeStatus = "Live"
            let nextPoints = (snapshot.points || []).slice()
            if (chartRange === "1D") {
                let point = { t: Number(event.time) || Math.floor(Date.now() / 1000), v: Number(event.price) }
                if (nextPoints.length > 0 && point.t - Number(nextPoints[nextPoints.length - 1].t) < 60)
                    nextPoints[nextPoints.length - 1] = point
                else
                    nextPoints.push(point)
                if (nextPoints.length > 120) nextPoints = nextPoints.slice(nextPoints.length - 120)
            }
            snapshot = Object.assign({}, snapshot, {
                mode: "kis",
                price: Number(event.price),
                change: Number(event.change),
                changePct: Number(event.changePct),
                high: Number(event.high),
                low: Number(event.low),
                volume: Number(event.volume),
                bid: Number(event.bid),
                ask: Number(event.ask),
                points: nextPoints,
                updatedAt: Number(event.time)
            })
        } catch (error) {
            realtimeStatus = "Stream parse error"
        }
    }

    function runAnalysis() {
        if (!aiConfigured || backend.analysis.running) return
        analysisError = ""
        analysisMessage = ""
        let payload = Object.assign({}, snapshot, { chartRange: chartRange })
        let refreshMode = analysisResult.status === "ok" ? "force" : "cache"
        pendingAnalysis = JSON.stringify(payload)
        backend.analysis.command = ["python3", StockService.stockScript, "analyze", aiProvider,
            analysisProfile, refreshMode]
        backend.analysis.running = true
    }

    function resetAnalysis() {
        analysisResult = ({})
        analysisError = ""
        analysisMessage = ""
        analysisReportVisible = false
    }

    function openForecasts() {
        analysisReportVisible = false
        forecastVisible = true
        forecastError = ""
        forceActiveFocus()
        if (quantTab === "forecasts") refreshForecasts(true)
        else if (quantTab === "ai_eval") refreshAiValidation()
        else if (quantTab === "usage") refreshAiUsage()
        else if (quantTab === "screener") refreshScreener()
    }

    function closeForecasts() {
        forecastVisible = false
        forecastQueued = false
        screenerQueued = false
    }

    function refreshForecasts(evaluate) {
        if (backend.forecast.running) {
            forecastQueued = true
            return
        }
        forecastError = ""
        if (evaluate && Number(snapshot.price || 0) > 0) {
            pendingForecastInput = JSON.stringify({
                symbol: symbol,
                market: market,
                price: Number(snapshot.price),
                updatedAt: Number(snapshot.updatedAt || 0)
            })
            backend.forecast.command = ["python3", StockService.stockScript, "forecasts", "evaluate"]
        } else {
            pendingForecastInput = ""
            backend.forecast.command = ["python3", StockService.stockScript, "forecasts", "list", symbol, "50"]
        }
        backend.forecast.running = true
    }

    function deleteForecast(id) {
        if (!id || backend.deleteForecast.running) return
        forecastError = ""
        backend.deleteForecast.command = ["python3", StockService.stockScript, "forecasts", "delete", id]
        backend.deleteForecast.running = true
    }

    function chooseQuantTab(value) {
        quantTab = value
        if (value === "forecasts") refreshForecasts(true)
        else if (value === "ai_eval") refreshAiValidation()
        else if (value === "usage") refreshAiUsage()
        else if (value === "screener") refreshScreener()
    }

    function resetBacktest() {
        backtestResult = ({})
        backtestError = ""
    }

    function resetComparison() {
        comparisonResult = ({ items: [] })
        comparisonError = ""
    }

    function resetAiValidation() {
        aiValidationResult = ({ models: [], calibration: [], signals: {} })
        aiValidationError = ""
        aiValidationQueued = false
    }

    function refreshAiValidation() {
        if (backend.aiValidation.running) {
            aiValidationQueued = true
            return
        }
        aiValidationError = ""
        backend.aiValidation.command = ["python3", StockService.stockScript, "validate-ai", symbol,
            String(validationConfidenceFloor), "200"]
        backend.aiValidation.running = true
    }

    function refreshAiUsage() {
        if (backend.aiUsage.running) return
        aiUsageError = ""
        backend.aiUsage.command = ["python3", StockService.stockScript, "ai-usage", "30", "100"]
        backend.aiUsage.running = true
    }

    function resetScreener() {
        screenerState = ({ items: [], counts: {} })
        screenerError = ""
        screenerQueued = false
    }

    function refreshScreener() {
        if (backend.screener.running) {
            screenerQueued = true
            return
        }
        screenerError = ""
        if (watchlist.length === 0) {
            screenerState = ({ status: "ok", items: [], counts: { screened: 0, total: 0, bullish: 0, neutral: 0, bearish: 0 } })
            return
        }
        pendingScreener = JSON.stringify(watchlist)
        backend.screener.command = ["python3", StockService.stockScript, "screen", dataMode, kisEnvironment]
        backend.screener.running = true
    }

    function selectScreenerItem(item) {
        if (!item || item.status !== "ok" || !item.symbol || !frame) return
        closeForecasts()
        frame.save({ symbol: item.symbol, market: item.market || "KRX" })
    }

    function formatTokenCount(value) {
        let count = Number(value || 0)
        if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M"
        if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1) + "K"
        return Math.round(count).toString()
    }

    function runBacktest() {
        if (backend.backtest.running) return
        backtestResult = ({})
        backtestError = ""
        let costs = backtestCostSettings()
        backend.backtest.command = ["python3", StockService.stockScript, "backtest", symbol, market,
            dataMode, kisEnvironment, backtestStrategy, String(costs.commission), String(costs.slippage), String(costs.tax)]
        backend.backtest.running = true
    }

    function backtestCostSettings() {
        if (backtestCostProfile === "ideal") return { commission: 0, slippage: 0, tax: 0 }
        if (backtestCostProfile === "stress") return { commission: 3, slippage: 15, tax: market === "KRX" ? 20 : 0 }
        return { commission: 1.5, slippage: 5, tax: market === "KRX" ? 15 : 0 }
    }

    function runComparison() {
        if (backend.comparison.running) return
        resetComparison()
        let costs = backtestCostSettings()
        backend.comparison.command = ["python3", StockService.stockScript, "compare", symbol, market,
            dataMode, kisEnvironment, String(costs.commission), String(costs.slippage), String(costs.tax)]
        backend.comparison.running = true
    }

    function inspectComparisonStrategy(strategy) {
        backtestStrategy = strategy
        resetBacktest()
        quantTab = "backtest"
    }

    function comparisonRiskColor(risk) {
        return risk === "low" ? positiveColor : (risk === "high" ? negativeColor : "#ff9f0a")
    }

    function comparisonRiskLabel(risk) {
        return risk === "low" ? "Low overfit risk" : (risk === "high" ? "High overfit risk" : "Moderate risk")
    }

    function validationStatusColor(status) {
        return status === "usable" ? positiveColor : (status === "limited" ? "#ff9f0a" : secondaryColor)
    }

    function calibrationBucket(index) {
        let buckets = aiValidationResult.calibration || []
        return buckets.length > index ? buckets[index] : ({})
    }

    function walkForwardColor() {
        let status = (backtestResult.walkForward || {}).status || ""
        return status === "robust" ? positiveColor : (status === "weak" ? negativeColor : "#ff9f0a")
    }

    function backtestDate(value) {
        if (!Number(value)) return ""
        return Qt.formatDateTime(new Date(Number(value) * 1000), "yyyy.MM.dd")
    }

    function forecastStatusLabel(item) {
        if (item.status !== "resolved") return "Open"
        return item.correct === true ? "Correct" : "Miss"
    }

    function forecastStatusColor(item) {
        if (item.status !== "resolved") return "#0a84ff"
        return item.correct === true ? positiveColor : negativeColor
    }

    function forecastReturn(item) {
        return Number(item.status === "resolved" ? item.returnPct : item.currentReturnPct || 0)
    }

    function analysisTime(value) {
        if (!Number(value)) return ""
        return Qt.formatDateTime(new Date(Number(value) * 1000), "yyyy.MM.dd  hh:mm")
    }

    function stanceLabel(value) {
        if (value === "bullish") return "Bullish"
        if (value === "bearish") return "Bearish"
        return value === "neutral" ? "Neutral" : "Awaiting"
    }

    function chooseRange(value) {
        chartRange = value
        hoverIndex = -1
    }

    function orderStatusText() {
        if (dataMode === "demo") return "Local preview only"
        if (kisEnvironment === "prod" && !productionTradingEnabled) return "Production orders are locked"
        if (!kisConfigured) return "Save KIS " + (kisEnvironment === "prod" ? "production" : "paper") + " API credentials in Edit"
        if (!kisAccountConfigured) return "Save the " + (kisEnvironment === "prod" ? "production" : "paper") + " account number in Edit"
        if (accountBusy) return "Checking account…"
        if (accountError !== "") return accountError
        if (accountState.status !== "ok") return "Account data required"
        if (orderSide === "buy" && quantity > Number(accountState.buyingQuantity || 0)) return "Exceeds available buy quantity"
        if (orderSide === "sell" && quantity > Number(accountState.sellableQuantity || 0)) return "Exceeds sellable holdings"
        return kisEnvironment === "prod" ? "KIS production order · LIVE confirmation required" : "KIS paper order"
    }

    function preflightStatusText() {
        if (orderError !== "") return orderError
        if (backend.preflight.running) return "Checking account and risk policy…"
        if (preflightError !== "") return preflightError
        if (!preflightReady) return "Waiting for server checks…"
        if (demoOrderReady) return "Local preview only · no broker order will be sent"
        if (kisEnvironment === "paper") return "KIS paper account checks passed · rechecked at submit"
        let risk = preflightState.risk || {}
        let policy = risk.policy || {}
        if (reviewOrder.side === "buy" && Number(policy.maxBuyOrdersPerDay || 0) > 0)
            return "Risk Guard passed · daily buys " + (Number(risk.dailyBuyOrders || 0) + 1) + "/"
                + policy.maxBuyOrdersPerDay + " · rechecked at submit"
        return "Risk Guard passed · all limits are rechecked at submit"
    }

    function openOrderReview() {
        if (!canReviewOrder) return
        let token = String(Date.now()) + "-" + String(Math.random())
        reviewOrder = {
            token: token,
            symbol: symbol,
            side: orderSide,
            orderType: orderType,
            quantity: quantity,
            price: orderPrice,
            currency: snapshot.currency,
            estimatedTotal: estimatedTotal
        }
        orderError = ""
        orderMessage = ""
        preflightState = ({})
        preflightError = ""
        mainPanel.clearLiveConfirmation()
        reviewVisible = true
        runPreflight()
    }

    function closeOrderReview() {
        if (backend.order.running) return
        mainPanel.clearLiveConfirmation()
        reviewVisible = false
        reviewOrder = ({})
        preflightState = ({})
        preflightError = ""
        preflightQueued = false
    }

    function runPreflight() {
        if (!reviewVisible || !reviewOrder.symbol) return
        if (demoOrderReady) {
            preflightState = {
                status: "ok",
                availableQuantity: reviewOrder.quantity,
                risk: { estimatedNotional: reviewOrder.estimatedTotal, projectedPositionPercent: 0 }
            }
            return
        }
        if (backend.preflight.running) {
            preflightQueued = true
            return
        }
        preflightState = ({})
        preflightError = ""
        preflightToken = String(reviewOrder.token)
        pendingPreflight = JSON.stringify({
            symbol: reviewOrder.symbol,
            side: reviewOrder.side,
            orderType: reviewOrder.orderType,
            quantity: reviewOrder.quantity,
            price: reviewOrder.price
        })
        backend.preflight.command = ["python3", StockService.stockScript, "preflight", kisEnvironment]
        backend.preflight.running = true
    }

    function submitOrder() {
        if (!reviewVisible || !reviewOrder.symbol || !preflightReady) return
        if (demoOrderReady) {
            orderMessage = (reviewOrder.side === "buy" ? "Buy" : "Sell") + " " + reviewOrder.quantity
                + " " + reviewOrder.symbol + " · Local preview complete"
            orderError = ""
            closeOrderReview()
            return
        }
        if ((!paperOrderReady && !productionOrderReady) || backend.order.running) return
        if (kisEnvironment === "prod" && mainPanel.liveConfirmation !== "LIVE") return
        orderError = ""
        pendingOrder = JSON.stringify({
            symbol: reviewOrder.symbol,
            side: reviewOrder.side,
            orderType: reviewOrder.orderType,
            quantity: reviewOrder.quantity,
            price: reviewOrder.price,
            confirmation: kisEnvironment === "prod" ? mainPanel.liveConfirmation : ""
        })
        backend.order.command = ["python3", StockService.stockScript, "order", kisEnvironment]
        backend.order.running = true
    }

    Stock.StockMarketOverview {
        id: marketOverview
        root: root
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: implicitHeight
    }

    Stock.StockMainPanel {
        id: mainPanel
        root: root
        anchors { left: parent.left; right: parent.right; top: marketOverview.bottom; bottom: parent.bottom }
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: 14
        anchors.bottomMargin: 18
    }

    Loader {
        id: watchlistLoader
        anchors.fill: parent
        active: root.watchlistVisible || (item !== null && item.visible)
        z: 90
        sourceComponent: Component {
            Stock.StockWatchlistSheet { root: root }
        }
    }

    Loader {
        id: alertsLoader
        anchors.fill: parent
        active: root.alertsVisible || (item !== null && item.visible)
        z: 120
        sourceComponent: Component {
            Stock.StockAlertsSheet { root: root }
        }
    }

    Loader {
        id: analysisReportLoader
        anchors.fill: parent
        active: root.analysisReportVisible || (item !== null && item.visible)
        z: 100
        sourceComponent: Component {
            Stock.StockAnalysisReport { root: root }
        }
    }

    Loader {
        id: quantLoader
        anchors.fill: parent
        active: root.forecastVisible || (item !== null && item.visible)
        z: 130
        sourceComponent: Component {
            Stock.StockQuantSheet { root: root }
        }
    }

    Loader {
        id: activityLoader
        anchors.fill: parent
        active: root.activityVisible || (item !== null && item.visible)
        z: 110
        sourceComponent: Component {
            Stock.StockActivitySheet { root: root }
        }
    }




}
