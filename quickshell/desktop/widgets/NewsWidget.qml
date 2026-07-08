import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: newsRoot
    property var frame
    readonly property var d: frame ? frame.dataObj : ({})
    readonly property var sources: (d && d.sources && d.sources.length) ? d.sources : NewsService.defaultSources()
    readonly property var categories: (d && d.categories && d.categories.length) ? d.categories : NewsService.defaultCategories()
    readonly property int layout: (d && d.layout) ? d.layout : 2
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
    readonly property int refreshIntervalMs: 60 * 60 * 1000
    readonly property int pageSize: layout === 1 ? 2 : (layout === 3 ? 6 : 4)
    readonly property int imageW: layout === 1 ? 86 : (layout === 3 ? 68 : 76)
    readonly property int imageH: imageW
    readonly property int rowMinH: layout === 1 ? 86 : (layout === 3 ? 76 : 82)
    readonly property int rowGap: layout === 3 ? 34 : (layout === 1 ? 28 : 30)
    readonly property int headlineSize: layout === 3 ? 18 : 20
    readonly property int sourceSize: layout === 3 ? 11 : 12
    readonly property var filteredItems: filterItems(items)
    readonly property int totalPages: Math.max(1, Math.ceil(filteredItems.length / pageSize))
    readonly property var pageItems: filteredItems.slice(page * pageSize, Math.min(filteredItems.length, (page + 1) * pageSize))
    readonly property int selectedCount: selectedItems().length
    readonly property int pageSelectableCount: countPageSelectable()
    readonly property int pageSelectedCount: countPageSelected()
    readonly property bool pageAllSelected: pageSelectableCount > 0 && pageSelectedCount === pageSelectableCount
    readonly property bool aiBusy: aiProc.running || summaryQueue.length > 0 || activeSummaryUrls.length > 0

    onActiveChanged: if (active && !loading) requestFetch(false)
    onSourcesChanged: filtersChanged()
    onCategoriesChanged: filtersChanged()
    onLayoutChanged: { page = 0; clampPage(); scheduleRowHeightRecalc() }
    onFilteredItemsChanged: { clampPage(); scheduleRowHeightRecalc() }
    onPageItemsChanged: scheduleRowHeightRecalc()
    onSelectModeChanged: scheduleRowHeightRecalc()
    onSummaryByUrlChanged: scheduleRowHeightRecalc()
    onLoadingUrlsChanged: scheduleRowHeightRecalc()
    onErrorByUrlChanged: scheduleRowHeightRecalc()
    onWidthChanged: scheduleRowHeightRecalc()
    Component.onCompleted: if (active) requestFetch(false)

    Timer { id: fetchDebounce; interval: 120; onTriggered: newsRoot.fetchNews() }
    Timer { id: rowMeasureTimer; interval: 1; onTriggered: if (typeof listCol !== "undefined") listCol.recomputeUniformRowH() }

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
        status = ""
        pruneSelection()
        pruneSummaries()
        requestFetch(true)
    }

    function scheduleRowHeightRecalc() {
        if (typeof rowMeasureTimer !== "undefined") rowMeasureTimer.restart()
    }

    function clampPage() {
        if (page >= totalPages) page = totalPages - 1
        if (page < 0) page = 0
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
            pruneSelection()
            pruneSummaries()
            clampPage()
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

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: newsRoot.bg
    }

    Item {
        id: header
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

    Item {
        id: listViewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: pager.top
        anchors.topMargin: 6
        anchors.bottomMargin: 12
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        clip: true

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
                            else if (modelData.url) {
                                openProc.command = ["xdg-open", modelData.url]
                                openProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }

    Row {
        id: pager
        visible: newsRoot.totalPages > 1
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
            enabled: newsRoot.page > 0
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
            enabled: newsRoot.page < newsRoot.totalPages - 1
            onClicked: newsRoot.page++
        }
    }

    Rectangle {
        id: confirmBar
        visible: newsRoot.selectMode && newsRoot.selectedCount > 0 && !newsRoot.aiBusy
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

        Text {
            anchors.centerIn: parent
            text: "Confirm"
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        MouseArea {
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
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: hp.clicked()
        }
    }

    component PagerButton: Rectangle {
        id: pb
        property string glyph: ""
        signal clicked()
        width: 28
        height: 28
        radius: 14
        color: pHover.hovered && enabled ? newsRoot.faint : newsRoot.bg
        border.color: newsRoot.line
        border.width: 1
        opacity: enabled ? 1 : 0.35
        Text {
            anchors.centerIn: parent
            text: pb.glyph
            color: newsRoot.fg
            font.family: NewsService.iconFont
            font.pixelSize: 10
        }
        HoverHandler { id: pHover; enabled: pb.enabled }
        MouseArea {
            anchors.fill: parent
            enabled: pb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }
}
