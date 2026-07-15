import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import "kinetic.js" as Kinetic

Item {
    id: newsRoot
    property var frame
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property var sources: (d && d.sources && d.sources.length) ? d.sources : NewsService.defaultSources()
    readonly property var categories: (d && d.categories && d.categories.length) ? d.categories : NewsService.defaultCategories()
    readonly property int layout: (d && d.layout) ? d.layout : 2
    readonly property bool xSmall: layout === 4
    readonly property string modelName: (d && d.model) ? d.model : NewsService.defaultModel
    readonly property bool active: frame && frame.winRef ? frame.winRef.show : true

    readonly property bool dark: ThemeService.isDark
    readonly property color bg: dark ? "#1c1c1e" : "#ffffff"
    readonly property color fg: dark ? "#f5f5f7" : "#050506"
    readonly property color muted: dark ? "#8e8e93" : "#9b9ba1"
    readonly property color faint: dark ? "#2c2c2e" : "#f2f2f7"
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.10) : "#e5e5ea"
    property color cardColor: bg
    property bool lightCard: !dark
    property var items: []
    property var selectedUrls: ({})
    property var summaryByUrl: ({})
    property var loadingUrls: ({})
    property var errorByUrl: ({})
    property var activeSummaryUrls: []
    property var summaryQueue: []
    property string status: ""
    property int updatedAt: 0
    property bool loading: false
    property bool selectMode: false
    property bool pendingFetch: false
    property bool pendingFetchForce: false
    property bool batchHandled: false
    property double lastFetchMs: 0
    property int page: 0
    property int xSmallIndex: 0
    property real xSmallWheelDelta: 0
    property bool xSmallPageVisible: false
    readonly property int refreshIntervalMs: 60 * 60 * 1000
    readonly property int pageSize: xSmall ? 1 : (layout === 1 ? 2 : (layout === 3 ? 6 : 4))
    readonly property int imageW: layout === 1 ? 86 : (layout === 3 ? 68 : 76)
    readonly property int imageH: imageW
    readonly property int rowMinH: layout === 1 ? 86 : (layout === 3 ? 76 : 82)
    readonly property int rowGap: layout === 3 ? 34 : (layout === 1 ? 28 : 30)
    readonly property int headlineSize: layout === 3 ? 18 : 20
    readonly property int sourceSize: layout === 3 ? 11 : 12
    readonly property var filteredItems: filterItems(items)
    readonly property var xSmallItems: {
        let pictured = []
        for (let i = 0; i < filteredItems.length; i++) {
            if (filteredItems[i].image) pictured.push(filteredItems[i])
        }
        return pictured.length > 0 ? pictured : filteredItems
    }
    readonly property var xSmallCurrent: xSmallItems.length > 0
        ? xSmallItems[Math.min(xSmallIndex, xSmallItems.length - 1)]
        : ({})
    // Plain int, recounted from signal handlers: a lazy binding through the
    // filteredItems var-array (new identity every evaluation) re-dirties any
    // reader mid-evaluation and trips the binding-loop detector.
    property int totalPages: 1
    readonly property var pageItems: filteredItems.slice(page * pageSize, Math.min(filteredItems.length, (page + 1) * pageSize))
    readonly property int selectedCount: selectedItems().length
    readonly property int pageSelectableCount: countPageSelectable()
    readonly property int pageSelectedCount: countPageSelected()
    readonly property bool pageAllSelected: pageSelectableCount > 0 && pageSelectedCount === pageSelectableCount
    readonly property bool aiBusy: aiProc.running || summaryQueue.length > 0 || activeSummaryUrls.length > 0

    onActiveChanged: if (active && !loading) requestFetch(false)
    onSourcesChanged: filtersChanged()
    onCategoriesChanged: filtersChanged()
    onLayoutChanged: { page = 0; xSmallIndex = 0; _recountPages(); scheduleRowHeightRecalc() }
    onFilteredItemsChanged: {
        _recountPages()
        scheduleRowHeightRecalc()
    }
    onXSmallItemsChanged: xSmallIndex = Math.max(0, Math.min(xSmallIndex, xSmallItems.length - 1))
    onPageItemsChanged: scheduleRowHeightRecalc()
    onPageChanged: { nvGlide.stop(); listViewport.contentY = 0 }
    onSelectModeChanged: scheduleRowHeightRecalc()
    onSummaryByUrlChanged: scheduleRowHeightRecalc()
    onLoadingUrlsChanged: scheduleRowHeightRecalc()
    onErrorByUrlChanged: scheduleRowHeightRecalc()
    onWidthChanged: scheduleRowHeightRecalc()
    Component.onCompleted: { _recountPages(); if (active) requestFetch(false) }

    Timer { id: fetchDebounce; interval: 120; onTriggered: newsRoot.fetchNews() }
    Timer { id: rowMeasureTimer; interval: 1; onTriggered: if (typeof listCol !== "undefined") listCol.recomputeUniformRowH() }
    Timer { id: xSmallPageTimer; interval: 900; onTriggered: newsRoot.xSmallPageVisible = false }

    Process {
        id: fetchProc
        stdout: StdioCollector { onStreamFinished: newsRoot.applyNews(text) }
        onRunningChanged: newsRoot.loading = running
        onExited: (code, status) => {
            if (code !== 0 && newsRoot.filteredItems.length === 0) newsRoot.status = "뉴스를 불러오지 못했습니다."
            if (!running && newsRoot.pendingFetch) {
                let force = newsRoot.pendingFetchForce
                newsRoot.pendingFetch = false
                newsRoot.pendingFetchForce = false
                newsRoot.requestFetch(force)
            }
        }
    }

    Process {
        id: aiProc
        stdout: StdioCollector { onStreamFinished: newsRoot.applyBatchSummary(text) }
        onExited: (code, status) => {
            Qt.callLater(function () {
                if (!newsRoot.batchHandled && newsRoot.activeSummaryUrls.length > 0) newsRoot.markActiveError("Summary failed.")
                newsRoot.startNextSummary()
            })
        }
    }

    Process { id: openProc; command: ["true"] }

    function requestFetch(force) {
        if (!active) return
        if (!force && lastFetchMs > 0 && Date.now() - lastFetchMs < refreshIntervalMs) return
        if (fetchProc.running) {
            pendingFetch = true
            pendingFetchForce = pendingFetchForce || !!force
            return
        }
        fetchDebounce.restart()
    }

    function filtersChanged() {
        page = 0
        xSmallIndex = 0
        status = ""
        pruneSelection()
        pruneSummaries()
        requestFetch(true)
    }

    function moveXSmall(step) {
        if (xSmallItems.length < 2 || step === 0) return
        xSmallIndex = Math.max(0, Math.min(xSmallItems.length - 1, xSmallIndex + step))
        xSmallPageVisible = true
        xSmallPageTimer.restart()
    }

    function _recountPages() {
        totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize))
        clampPage()
    }

    function clampPage() {
        if (page >= totalPages) page = totalPages - 1
        if (page < 0) page = 0
    }

    function scheduleRowHeightRecalc() {
        if (typeof rowMeasureTimer !== "undefined") rowMeasureTimer.restart()
    }

    function filterItems(src) {
        let out = []
        for (let i = 0; i < src.length; i++) {
            let it = src[i]
            if (NewsService.has(sources, it.sourceId) && NewsService.has(categories, it.categoryId)) out.push(it)
        }
        return out
    }

    function pruneSelection() {
        let keep = ({})
        for (let i = 0; i < filteredItems.length; i++) {
            let url = filteredItems[i].url
            if (selectedUrls[url]) keep[url] = true
        }
        selectedUrls = keep
    }

    function pruneSummaries() {
        let summaries = ({})
        let loadingMap = ({})
        let errors = ({})
        for (let i = 0; i < filteredItems.length; i++) {
            let url = filteredItems[i].url
            if (summaryByUrl[url]) summaries[url] = summaryByUrl[url]
            if (loadingUrls[url]) loadingMap[url] = true
            if (errorByUrl[url]) errors[url] = errorByUrl[url]
        }
        summaryByUrl = summaries
        loadingUrls = loadingMap
        errorByUrl = errors
    }

    function isSelected(url) {
        return !!selectedUrls[url]
    }

    function toggleSelected(url) {
        let next = Object.assign({}, selectedUrls)
        if (next[url]) delete next[url]
        else next[url] = true
        selectedUrls = next
    }

    function countPageSelectable() {
        let n = 0
        for (let i = 0; i < pageItems.length; i++) {
            if (pageItems[i].url) n++
        }
        return n
    }

    function countPageSelected() {
        let n = 0
        for (let i = 0; i < pageItems.length; i++) {
            if (pageItems[i].url && selectedUrls[pageItems[i].url]) n++
        }
        return n
    }

    function togglePageSelection() {
        let next = Object.assign({}, selectedUrls)
        if (pageAllSelected) {
            for (let i = 0; i < pageItems.length; i++) {
                if (pageItems[i].url) delete next[pageItems[i].url]
            }
        } else {
            for (let j = 0; j < pageItems.length; j++) {
                if (pageItems[j].url) next[pageItems[j].url] = true
            }
        }
        selectedUrls = next
    }

    function selectedItems() {
        let out = []
        for (let i = 0; i < filteredItems.length; i++) {
            if (selectedUrls[filteredItems[i].url]) out.push(filteredItems[i])
        }
        return out
    }

    function isSummarizing(url) {
        return !!loadingUrls[url]
    }

    function rowSummary(url) {
        return cleanAiText(summaryByUrl[url] || "")
    }

    function rowError(url) {
        return errorByUrl[url] || ""
    }

    function cleanAiText(value) {
        let text = (value || "").toString().replace(/\s+/g, " ").trim()
        text = text.replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, "")
        text = text.replace(/\u009b[0-?]*[ -/]*[@-~]/g, "")
        text = text.replace(/\ufffd(\[[0-?]*[ -/]*[@-~]|[A-Za-z])?/g, "")
        text = text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/g, "")
        text = text.replace(/\s+/g, " ").trim()
        text = text.replace(/^\s*(요약|summary|결과|answer)\s*[:：-]\s*/i, "").trim()
        text = text.replace(/^\s*\d+\s*[|:：.)-]\s*/, "").trim()
        text = text.replace(/([.!?。])\s*[12]\s*[.)|:：-]?\s*(?=[가-힣])/g, "$1 ").trim()
        text = text.replace(/^[\s"'`“”‘’.,;:·…-]+/, "").trim()
        if (text.length === 0) return ""
        if (!/[가-힣]/.test(text)) return ""
        text = text.replace(/\s*\([^)]*[A-Za-z][^)]*\)\s*$/, "").trim()
        let lowered = text.toLowerCase()
        if (lowered.indexOf("language:") >= 0 || lowered.indexOf("approx") >= 0) return ""
        let badMarkers = ["do not", "core noun", "from the title", "fragment", "like just", "output", "the "]
        for (let m = 0; m < badMarkers.length; m++) {
            if (lowered.indexOf(badMarkers[m]) >= 0) return ""
        }
        let englishWords = text.match(/\b[A-Za-z]{3,}\b/g)
        if (englishWords && englishWords.length > 1) return ""
        if (text[0] === "[" || text[0] === "{" || text.indexOf("https://") >= 0 || text.indexOf("\"id\"") >= 0) return ""
        if (text.replace(/\s+/g, "").length < 14) return ""
        let badStarts = ["며", "으며", "면서", "했다", "됐다", "있다", "없다", "운용할 것을", "운용하기로", "추진하기로", "전장보다", "전날보다", "전일보다", "관련 "]
        for (let i = 0; i < badStarts.length; i++) {
            if (text.indexOf(badStarts[i]) === 0) return ""
        }
        let firstWord = text.split(/\s+/)[0].replace(/[.,;:·…!?"'“”‘’]+$/g, "")
        if (/^[가-힣]{1,2}(은|는|이|가|을|를|의|에|도|만|로|으로)?$/.test(firstWord)) return ""
        if (/^[가-힣]{1,8}(했다|됐다|였다|밝혔다|전했다|말했다|설명했다|마무리했다|했습니다|됐습니다|였습니다|밝혔습니다|전했습니다)$/.test(firstWord)) return ""
        return text
    }

    function cleanAiError(value) {
        return cleanAiText(value) || "Summary failed."
    }

    function selectedPayload() {
        let picked = selectedItems()
        let out = []
        for (let i = 0; i < picked.length; i++) {
            let it = picked[i]
            out.push({
                id: it.url,
                source: it.source,
                category: it.category,
                title: it.title,
                summary: it.summary,
                url: it.url
            })
        }
        return out
    }

    function fetchNews() {
        if (!active || fetchProc.running || sources.length === 0 || categories.length === 0) return
        status = ""
        fetchProc.command = ["python3", NewsService.newsScript, "fetch", sources.join(","), categories.join(","), "42"]
        fetchProc.running = true
    }

    function applyNews(text) {
        try {
            let j = JSON.parse(text || "{}")
            if (!j.ok) {
                status = j.error || "뉴스를 불러오지 못했습니다."
                return
            }
            items = filterItems(j.items || [])
            updatedAt = j.updatedAt || Math.floor(Date.now() / 1000)
            lastFetchMs = Date.now()
            status = filteredItems.length === 0 ? "선택한 조건의 뉴스가 없습니다." : ""
            clampPage()
            pruneSelection()
            pruneSummaries()
        } catch (e) {
            status = "뉴스 데이터를 읽지 못했습니다."
        }
    }

    function aiClicked() {
        if (aiBusy) return
        selectedUrls = ({})
        selectMode = !selectMode
    }

    function confirmSummaries() {
        if (aiBusy || selectedCount === 0) return
        let payload = selectedPayload()
        let summaries = Object.assign({}, summaryByUrl)
        let loadingMap = Object.assign({}, loadingUrls)
        let errors = Object.assign({}, errorByUrl)
        activeSummaryUrls = []
        for (let i = 0; i < payload.length; i++) {
            let id = payload[i].id
            activeSummaryUrls.push(id)
            loadingMap[id] = true
            delete summaries[id]
            delete errors[id]
        }
        summaryByUrl = summaries
        loadingUrls = loadingMap
        errorByUrl = errors
        batchHandled = false
        summaryQueue = payload.slice()
        selectedUrls = ({})
        selectMode = false
        startNextSummary()
    }

    function startNextSummary() {
        if (aiProc.running || summaryQueue.length === 0) return
        let queue = summaryQueue.slice()
        let item = queue.shift()
        summaryQueue = queue
        activeSummaryUrls = [item.id]
        batchHandled = false
        aiProc.command = ["python3", NewsService.newsScript, "summarize-batch", modelName, JSON.stringify([item])]
        aiProc.running = true
    }

    function markActiveError(message) {
        let loadingMap = Object.assign({}, loadingUrls)
        let errors = Object.assign({}, errorByUrl)
        for (let i = 0; i < activeSummaryUrls.length; i++) {
            let id = activeSummaryUrls[i]
            delete loadingMap[id]
            errors[id] = cleanAiError(message)
        }
        loadingUrls = loadingMap
        errorByUrl = errors
        activeSummaryUrls = []
        selectedUrls = ({})
        selectMode = false
        batchHandled = true
    }

    function applyBatchSummary(text) {
        batchHandled = true
        let loadingMap = Object.assign({}, loadingUrls)
        let summaries = Object.assign({}, summaryByUrl)
        let errors = Object.assign({}, errorByUrl)
        try {
            let j = JSON.parse(text || "{}")
            if (!j.ok) {
                markActiveError(j.error || "Summary failed.")
                return
            }
            let byId = ({})
            let rows = j.items || []
            for (let i = 0; i < rows.length; i++) byId[rows[i].id] = cleanAiText(rows[i].summary)
            if (activeSummaryUrls.length === 1 && rows.length > 0 && !byId[activeSummaryUrls[0]]) {
                byId[activeSummaryUrls[0]] = cleanAiText(rows[0].summary)
            }
            for (let k = 0; k < activeSummaryUrls.length; k++) {
                let id = activeSummaryUrls[k]
                delete loadingMap[id]
                if (byId[id]) {
                    summaries[id] = byId[id]
                    delete errors[id]
                } else {
                    delete errors[id]
                }
            }
            loadingUrls = loadingMap
            summaryByUrl = summaries
            errorByUrl = errors
            activeSummaryUrls = []
            selectedUrls = ({})
            selectMode = false
        } catch (e) {
            markActiveError("Summary failed.")
        }
    }

    function openArticle(url) {
        if (!url || openProc.running) return
        openProc.command = ["xdg-open", url]
        if (frame && frame.winRef) frame.winRef.closeRequested()
        Qt.callLater(() => openProc.running = true)
    }

    Rectangle {
        anchors.fill: parent
        radius: newsRoot.xSmall ? 26 : 13
        color: newsRoot.bg
    }

    Item {
        id: xSmallLayout
        anchors.fill: parent
        visible: newsRoot.xSmall

        Rectangle {
            id: xSmallSurface
            anchors.fill: parent
            radius: 26
            color: newsRoot.faint

            ListView {
                id: xSmallStack
                anchors.fill: parent
                visible: false
                model: newsRoot.xSmallItems
                interactive: false
                orientation: ListView.Vertical
                contentY: newsRoot.xSmallIndex * height
                cacheBuffer: height
                Behavior on contentY {
                    AppleSpring {
                        spring: 22
                        damping: ThemeService.momentumDamping
                        epsilon: 0.2
                    }
                }

                delegate: Item {
                    required property var modelData
                    width: xSmallStack.width
                    height: xSmallStack.height

                    Image {
                        id: xSmallImage
                        anchors.fill: parent
                        source: modelData.image || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: xSmallImage.status === Image.Ready ? "transparent" : newsRoot.faint
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: xSmallImage.status !== Image.Ready
                        text: "\uf1ea"
                        color: newsRoot.muted
                        font.family: NewsService.iconFont
                        font.pixelSize: 42
                    }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.18; color: Qt.rgba(0, 0, 0, 0.04) }
                            GradientStop { position: 0.52; color: Qt.rgba(0, 0, 0, 0.18) }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.92) }
                        }
                    }

                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.bottomMargin: 15
                        spacing: 3

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: modelData.source || ""
                            color: Qt.rgba(1, 1, 1, 0.74)
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.title || ""
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 19
                            font.weight: Font.Black
                            font.letterSpacing: -0.25
                            lineHeight: 0.94
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                }
            }

            Rectangle {
                id: xSmallMask
                anchors.fill: parent
                radius: parent.radius
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: xSmallStack
                maskSource: xSmallMask
                cached: false
                scale: xSmallArticle.pressed ? 0.985 : 1
                Behavior on scale { AppleSpring { spring: 20 } }
            }

            MouseArea {
                id: xSmallArticle
                anchors.fill: parent
                enabled: !!newsRoot.xSmallCurrent.url
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: newsRoot.openArticle(newsRoot.xSmallCurrent.url)
            }

            Column {
                anchors.centerIn: parent
                visible: newsRoot.xSmallItems.length === 0
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf1ea"
                    color: newsRoot.muted
                    font.family: NewsService.iconFont
                    font.pixelSize: 34
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: newsRoot.loading ? "Loading..." : newsRoot.status
                    color: newsRoot.muted
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    let delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y
                    if (delta === 0) return
                    if (newsRoot.xSmallWheelDelta !== 0 && (delta > 0) !== (newsRoot.xSmallWheelDelta > 0))
                        newsRoot.xSmallWheelDelta = 0
                    newsRoot.xSmallWheelDelta += delta
                    let threshold = event.pixelDelta.y !== 0 ? 48 : 120
                    if (Math.abs(newsRoot.xSmallWheelDelta) >= threshold) {
                        newsRoot.moveXSmall(newsRoot.xSmallWheelDelta < 0 ? 1 : -1)
                        newsRoot.xSmallWheelDelta = 0
                    }
                    event.accepted = true
                }
            }
        }

        Row {
            anchors { top: parent.top; right: parent.right }
            anchors.topMargin: 12
            anchors.rightMargin: 12
            spacing: 6
            z: 5

            Rectangle {
                visible: newsRoot.updatedAt > 0
                width: updateClock.implicitWidth + 16
                height: 30
                radius: 15
                color: Qt.rgba(0, 0, 0, 0.5)
                border.color: Qt.rgba(1, 1, 1, 0.18)
                border.width: 1

                Text {
                    id: updateClock
                    anchors.centerIn: parent
                    text: NewsService.clock(newsRoot.updatedAt)
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                width: 30
                height: 30
                radius: 15
                color: xSmallRefreshHover.hovered ? Qt.rgba(0, 0, 0, 0.72) : Qt.rgba(0, 0, 0, 0.5)
                border.color: Qt.rgba(1, 1, 1, 0.22)
                border.width: 1
                opacity: fetchProc.running ? 0.58 : 1
                scale: xSmallRefreshTap.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 18 } }

                Text {
                    anchors.centerIn: parent
                    text: "\uf021"
                    color: "#ffffff"
                    font.family: NewsService.iconFont
                    font.pixelSize: 11
                    rotation: fetchProc.running ? 180 : 0
                    Behavior on rotation { AppleSpring { spring: 18 } }
                }

                HoverHandler { id: xSmallRefreshHover; enabled: !fetchProc.running }
                TapHandler {
                    id: xSmallRefreshTap
                    enabled: !fetchProc.running
                    onTapped: newsRoot.requestFetch(true)
                }
            }
        }

        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            anchors.bottomMargin: 4
            width: xSmallPageLabel.implicitWidth + 14
            height: 18
            radius: 9
            color: Qt.rgba(0, 0, 0, 0.58)
            border.color: Qt.rgba(1, 1, 1, 0.18)
            border.width: 1
            opacity: newsRoot.xSmallPageVisible && newsRoot.xSmallItems.length > 1 ? 1 : 0
            visible: opacity > 0.002
            z: 5
            Behavior on opacity { AppleSpring { spring: 20 } }

            Text {
                id: xSmallPageLabel
                anchors.centerIn: parent
                text: (newsRoot.xSmallIndex + 1) + "/" + newsRoot.xSmallItems.length
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

    }

    Item {
        id: header
        visible: !newsRoot.xSmall
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 70

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: "Headlines"
            color: newsRoot.fg
            font.family: "SF Pro Display"
            font.pixelSize: 28
            font.letterSpacing: -0.5
            font.weight: Font.Black
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: titleText.verticalCenter
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: updatedAt > 0 ? (NewsService.clock(updatedAt) + " Update") : ""
                color: newsRoot.muted
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            HeaderPill {
                visible: newsRoot.selectMode && !newsRoot.aiBusy
                text: newsRoot.pageAllSelected ? "Deselect All" : "Select All"
                onClicked: newsRoot.togglePageSelection()
            }
            HeaderButton {
                glyph: "✦"
                active: newsRoot.selectMode
                enabled: !newsRoot.aiBusy
                onClicked: newsRoot.aiClicked()
            }
            HeaderButton {
                glyph: "\uf021"
                iconFont: NewsService.iconFont
                enabled: !fetchProc.running
                onClicked: newsRoot.requestFetch(true)
            }
        }
    }

    Flickable {
        id: listViewport
        visible: !newsRoot.xSmall
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: pager.visible ? pager.top : (confirmBar.visible ? confirmBar.top : parent.bottom)
        anchors.topMargin: 6
        anchors.bottomMargin: pager.visible ? 6 : (confirmBar.visible ? 10 : 16)
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        clip: true
        contentWidth: width
        contentHeight: listCol.height + 4
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

        // Kinetic scroll (kinetic.js) within the current page: rows keep
        // their paged layout, but when AI summaries stretch the column past
        // the widget height the overflow scrolls instead of clipping.
        property var _ks: ({})
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (ev) => {
                nvGlide.stop()
                if (Kinetic.onWheel(listViewport, ev, listViewport._ks, { gain: 90 }))
                    nvEndTimer.restart()
            }
        }
        Timer {
            id: nvEndTimer
            interval: 48
            onTriggered: {
                let g = Kinetic.fling(listViewport, listViewport._ks, {})
                if (g) { nvGlide.from = g.from; nvGlide.to = g.to; nvGlide.restart() }
            }
        }
        SpringAnimation {
            id: nvGlide
            target: listViewport
            property: "contentY"
            spring: 18
            damping: ThemeService.momentumDamping
            epsilon: 0.25
        }

        Column {
            id: listCol
            width: parent.width
            spacing: newsRoot.rowGap
            property int uniformRowH: Math.max(newsRoot.rowMinH, newsRoot.imageH)

            function recomputeUniformRowH() {
                let next = Math.max(newsRoot.rowMinH, newsRoot.imageH)
                for (let i = 0; i < newsRepeater.count; i++) {
                    let row = newsRepeater.itemAt(i)
                    if (row) next = Math.max(next, row.contentHeight)
                }
                uniformRowH = next
            }

            Text {
                visible: loading && newsRoot.filteredItems.length === 0
                width: parent.width
                height: 92
                verticalAlignment: Text.AlignVCenter
                text: "Loading..."
                color: newsRoot.muted
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                visible: status.length > 0 && !loading
                width: parent.width
                height: 92
                verticalAlignment: Text.AlignVCenter
                text: status
                color: newsRoot.muted
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Repeater {
                id: newsRepeater
                model: newsRoot.pageItems
                onItemAdded: listCol.recomputeUniformRowH()
                onItemRemoved: listCol.recomputeUniformRowH()
                delegate: Item {
                    required property var modelData
                    width: listCol.width
                    height: listCol.uniformRowH
                    readonly property int selectPad: newsRoot.selectMode ? 30 : 0
                    readonly property string catLabel: modelData.category || NewsService.labelOf(NewsService.categoryOptions, modelData.categoryId)
                    readonly property color catColor: NewsService.categoryColor(modelData.categoryId)
                    readonly property int contentHeight: Math.max(newsRoot.rowMinH, newsRoot.imageH, Math.ceil(rowTextCol.implicitHeight) + 4)

                    onContentHeightChanged: listCol.recomputeUniformRowH()

                    Rectangle {
                        visible: newsRoot.selectMode
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        width: 18
                        height: 18
                        radius: 9
                        color: newsRoot.isSelected(modelData.url) ? "#0a84ff" : "transparent"
                        border.color: newsRoot.isSelected(modelData.url) ? "#0a84ff" : "#c7c7cc"
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            visible: newsRoot.isSelected(modelData.url)
                            text: "\uf00c"
                            color: "#ffffff"
                            font.family: NewsService.iconFont
                            font.pixelSize: 9
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: newsRoot.toggleSelected(modelData.url)
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: parent.selectPad
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 12

                        Column {
                            id: rowTextCol
                            width: parent.width - newsRoot.imageW - parent.spacing
                            spacing: 1
                            onImplicitHeightChanged: listCol.recomputeUniformRowH()
                            Row {
                                id: metaRow
                                width: parent.width
                                spacing: 5
                                Text {
                                    id: sourceLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width - categoryLabel.implicitWidth - bullet.implicitWidth - 12)
                                    text: modelData.source
                                    color: newsRoot.muted
                                    font.family: "SF Pro Display"
                                    font.pixelSize: newsRoot.sourceSize
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: bullet
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "•"
                                    color: newsRoot.muted
                                    font.family: "SF Pro Display"
                                    font.pixelSize: newsRoot.sourceSize
                                    font.weight: Font.Bold
                                }
                                Text {
                                    id: categoryLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: catLabel
                                    color: catColor
                                    font.family: "SF Pro Display"
                                    font.pixelSize: newsRoot.sourceSize
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                id: headline
                                width: parent.width
                                text: modelData.title
                                color: newsRoot.fg
                                font.family: "SF Pro Display"
                                font.pixelSize: newsRoot.headlineSize
                                font.weight: Font.Black
                                lineHeight: 0.95
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: newsRoot.isSummarizing(modelData.url)
                                width: parent.width
                                text: "Summarizing..."
                                color: newsRoot.muted
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: !newsRoot.isSummarizing(modelData.url) && newsRoot.rowError(modelData.url).length > 0
                                width: parent.width
                                text: newsRoot.rowError(modelData.url)
                                color: "#ff453a"
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }
                            Text {
                                visible: !newsRoot.isSummarizing(modelData.url) && newsRoot.rowSummary(modelData.url).length > 0
                                width: parent.width
                                text: newsRoot.rowSummary(modelData.url)
                                color: newsRoot.muted
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                lineHeight: 1.05
                            }
                        }

                        Rectangle {
                            id: imageBox
                            width: newsRoot.imageW
                            height: newsRoot.imageH
                            radius: 9
                            color: newsRoot.faint
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: modelData.image || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !modelData.image || modelData.image.length === 0
                                text: "\uf1ea"
                                color: newsRoot.muted
                                font.family: NewsService.iconFont
                                font.pixelSize: 20
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.leftMargin: parent.selectPad
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (newsRoot.selectMode) newsRoot.toggleSelected(modelData.url)
                            else newsRoot.openArticle(modelData.url)
                        }
                    }
                }
            }
        }
    }

    Row {
        id: pager
        visible: !newsRoot.xSmall && newsRoot.totalPages > 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: confirmBar.visible ? confirmBar.top : parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.bottomMargin: confirmBar.visible ? 10 : 16
        height: 28
        spacing: 8

        PagerButton {
            glyph: "\uf053"
            active: newsRoot.page > 0
            onClicked: newsRoot.page--
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 72
            text: (newsRoot.page + 1) + " / " + newsRoot.totalPages
            horizontalAlignment: Text.AlignHCenter
            color: newsRoot.muted
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        PagerButton {
            glyph: "\uf054"
            active: newsRoot.page < newsRoot.totalPages - 1
            onClicked: newsRoot.page++
        }
    }

    Rectangle {
        id: confirmBar
        visible: !newsRoot.xSmall && newsRoot.selectMode && newsRoot.selectedCount > 0 && !newsRoot.aiBusy
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.bottomMargin: 14
        height: 34
        radius: 12
        color: "#0a84ff"
        border.color: "#0a84ff"
        border.width: 1
        clip: true
        scale: confirmMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }

        Text {
            anchors.centerIn: parent
            text: "Confirm"
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        MouseArea {
            id: confirmMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: newsRoot.confirmSummaries()
        }
    }

    component HeaderButton: Rectangle {
        id: hb
        property string glyph: ""
        property string iconFont: "SF Pro Display"
        property bool active: false
        signal clicked()
        width: 24
        height: 24
        radius: 12
        color: active ? "#0a84ff" : (hHover.hovered ? newsRoot.faint : newsRoot.bg)
        border.color: active ? "#0a84ff" : newsRoot.line
        border.width: 1
        opacity: enabled ? 1 : 0.45
        scale: hbMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: hb.glyph
            color: hb.active ? "#ffffff" : newsRoot.fg
            font.family: hb.iconFont
            font.pixelSize: hb.iconFont === NewsService.iconFont ? 10 : 13
            font.weight: Font.DemiBold
        }
        HoverHandler { id: hHover; enabled: hb.enabled }
        MouseArea {
            id: hbMa
            anchors.fill: parent
            enabled: hb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }

    component HeaderPill: Rectangle {
        id: hp
        property string text: ""
        signal clicked()
        width: visible ? label.implicitWidth + 18 : 0
        height: 24
        radius: 12
        color: pHover.hovered ? newsRoot.faint : newsRoot.bg
        border.color: newsRoot.line
        border.width: 1
        scale: hpMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            id: label
            anchors.centerIn: parent
            text: hp.text
            color: newsRoot.fg
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.Bold
        }
        HoverHandler { id: pHover; enabled: hp.enabled }
        MouseArea {
            id: hpMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: hp.clicked()
        }
    }

    // `active` (not the built-in Item.enabled) gates the button — binding
    // enabled on a Row child re-triggers itself through the enable-propagation
    // to the child MouseArea and warns about a binding loop.
    component PagerButton: Rectangle {
        id: pb
        property string glyph: ""
        property bool active: true
        signal clicked()
        width: 28
        height: 28
        radius: 8
        color: pbMa.containsMouse && pb.active ? newsRoot.faint : "transparent"
        opacity: active ? 1 : 0.35
        scale: pbMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: pb.glyph
            color: newsRoot.muted
            font.family: NewsService.iconFont
            font.pixelSize: 11
        }
        MouseArea {
            id: pbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pb.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (pb.active) pb.clicked()
        }
    }

}
