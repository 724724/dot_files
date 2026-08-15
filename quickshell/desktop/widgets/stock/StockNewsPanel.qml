import ".."
import "../kinetic.js" as Kinetic
import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: panel

    required property var root
    property var items: []
    property string status: ""
    property int updatedAt: 0
    property int newsPage: 0
    property string relationFilter: "all"
    property bool loading: false
    property bool cachedResult: false
    property bool pendingFetch: false
    property string pendingRefreshMode: ""
    property string delayedRefreshMode: "cache"
    property int nameWaitAttempts: 0
    property string loadedInstrumentKey: ""
    property string requestedInstrumentKey: ""
    readonly property bool active: root.active && root.xxlLayout
    readonly property string companyName: selectedCompanyName()
    readonly property string instrumentKey: root.market + ":" + root.symbol + ":" + companyName
    readonly property var articles: buildArticles(items)
    readonly property var dateArticles: articles.filter(item => item.newsDayOffset === newsPage)
    readonly property var pageArticles: relationFilter === "all" ? dateArticles
        : dateArticles.filter(item => item.relationType === relationFilter)

    function selectedCompanyName() {
        let currentSnapshot = root.snapshot || {};
        let snapshotSymbol = String(currentSnapshot.symbol || "").toUpperCase();
        let snapshotMarket = String(currentSnapshot.market || "KRX").toUpperCase();
        let snapshotName = String(currentSnapshot.name || "").trim();
        if (snapshotSymbol === String(root.symbol || "").toUpperCase()
                && snapshotMarket === String(root.market || "KRX").toUpperCase()
                && snapshotName !== "" && snapshotName !== root.symbol)
            return snapshotName;

        let quoted = (root.watchlistState || {
        }).items || [];
        for (let i = 0; i < quoted.length; i++) {
            if (quoted[i].symbol === root.symbol && (quoted[i].market || "KRX") === root.market && quoted[i].name)
                return quoted[i].name;
        }
        return root.symbol;
    }

    function requestFetch(refresh) {
        let mode = refresh === "hourly" ? "hourly"
            : ((refresh === true || refresh === "force") ? "force" : "cache");
        if (!active)
            return ;

        if (companyName === root.symbol && nameWaitAttempts < 8) {
            nameWaitAttempts++;
            delayedRefreshMode = mode;
            instrumentFetchTimer.restart();
            return ;
        }
        nameWaitAttempts = 0;

        if (mode === "cache" && loadedInstrumentKey === instrumentKey)
            return ;

        if (fetchProc.running) {
            pendingFetch = true;
            if (mode === "force" || pendingRefreshMode === "")
                pendingRefreshMode = mode;
            else if (mode === "hourly" && pendingRefreshMode === "cache")
                pendingRefreshMode = mode;
            return ;
        }

        status = "";
        requestedInstrumentKey = instrumentKey;
        fetchProc.command = ["python3", NewsService.newsScript, "stock-fetch", root.symbol, root.market, companyName, "90", mode];
        fetchProc.running = true;
    }

    function scheduleHourlyRefresh() {
        if (!active) {
            hourlyRefresh.stop();
            return ;
        }
        let now = new Date();
        let next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0);
        hourlyRefresh.interval = Math.max(1000, next.getTime() - now.getTime());
        hourlyRefresh.restart();
    }

    function instrumentChanged() {
        loadedInstrumentKey = "";
        nameWaitAttempts = 0;
        delayedRefreshMode = "cache";
        items = [];
        status = "";
        cachedResult = false;
        newsPage = 0;
        relationFilter = "all";
        instrumentFetchTimer.restart();
    }

    function applyNews(text) {
        try {
            let value = JSON.parse(text || "{}");
            if (!value.ok) {
                status = value.error || root.t("Could not load market news.");
                return ;
            }
            if (value.symbol !== root.symbol || value.market !== root.market) {
                pendingFetch = true;
                return ;
            }
            if (requestedInstrumentKey !== instrumentKey) {
                pendingFetch = true;
                return ;
            }
            items = value.items || [];
            updatedAt = Number(value.updatedAt || Math.floor(Date.now() / 1000));
            cachedResult = !!value.cached;
            loadedInstrumentKey = requestedInstrumentKey;
            status = items.length === 0
                ? root.t("No news about %1 from the last three days.", [companyName]) : "";
        } catch (error) {
            status = root.t("Could not read market news.");
        }
    }

    function epoch(item) {
        let value = Date.parse((item || {
        }).published || "");
        return isNaN(value) ? 0 : Math.floor(value / 1000);
    }

    function dateKey(date) {
        let month = date.getMonth() + 1;
        let day = date.getDate();
        return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day;
    }

    function dayOffset(timestamp) {
        let today = new Date();
        let date = new Date(timestamp * 1000);
        let todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        let dateStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        return Math.round((todayStart - dateStart) / 86400000);
    }

    function buildArticles(source) {
        let output = [];
        let symbol = String(root.symbol || "").toUpperCase();
        for (let i = 0; i < source.length; i++) {
            let item = source[i] || ({
            });
            let ts = epoch(item);
            let offset = dayOffset(ts);
            if (ts <= 0 || offset < 0 || offset > 2)
                continue;
            if (String(item.stockSymbol || "").toUpperCase() !== symbol
                    || String(item.stockMarket || "").toUpperCase() !== root.market)
                continue;

            let date = new Date(ts * 1000);
            output.push(Object.assign({
            }, item, {
                "newsTimestamp": ts,
                "newsDate": dateKey(date),
                "newsDayOffset": offset,
                "relationType": item.relationType === "theme" ? "theme" : "direct"
            }));
        }
        output.sort(function(a, b) {
            if (a.newsDate !== b.newsDate)
                return b.newsTimestamp - a.newsTimestamp;

            return b.newsTimestamp - a.newsTimestamp;
        });
        return output.slice(0, 90);
    }

    function displayTime(item) {
        if (item.publishedText)
            return item.publishedText;

        let ts = epoch(item);
        return ts > 0 ? Qt.formatTime(new Date(ts * 1000), "HH:mm") : "";
    }

    function relationClassLabel(item) {
        switch (String((item || {}).relationClass || "")) {
        case "company": return root.t((item || {}).materialEvent ? "Company event" : "Company context");
        case "product": return root.t("Product");
        case "supply_chain": return root.t("Supply chain");
        case "competitor": return root.t("Competitor");
        case "regulation": return root.t("Regulation");
        case "macro": return root.t("Macro");
        case "industry": return root.t("Industry");
        default: return root.t((item || {}).relationType === "theme" ? "Industry" : "Company");
        }
    }

    function sourceQualityLabel(item) {
        switch (String((item || {}).sourceTier || "")) {
        case "authoritative": return root.t("Top-tier source");
        case "established": return root.t("Established source");
        case "aggregator": return root.t("Aggregator");
        case "low": return root.t("Low-confidence source");
        default: return "";
        }
    }

    function articleMetadata(item) {
        let parts = [relationClassLabel(item), item.source || root.t("Unknown source")];
        let time = displayTime(item);
        if (time !== "")
            parts.push(time);
        let sourceQuality = sourceQualityLabel(item);
        if (sourceQuality !== "")
            parts.push(sourceQuality);
        let sources = ((item || {}).duplicateSources || []).length;
        let copies = Math.max(1, Number((item || {}).duplicateCount || 1));
        if (sources > 1)
            parts.push(root.t("%1 reporting sources", [sources]));
        else if (copies > 1)
            parts.push(root.t("%1 reports grouped", [copies]));
        return parts.join(" · ");
    }

    function openArticle(url) {
        if (!url || openProc.running)
            return ;

        openProc.command = ["xdg-open", url];
        if (root.frame && root.frame.winRef)
            root.frame.winRef.closeRequested();

        Qt.callLater(() => {
            return openProc.running = true;
        });
    }

    onActiveChanged: {
        if (!active) {
            hourlyRefresh.stop();
            instrumentFetchTimer.stop();
            return ;
        }
        scheduleHourlyRefresh();
        instrumentFetchTimer.restart();
    }
    onNewsPageChanged: {
        newsGlide.stop();
        newsList.contentY = 0;
    }
    onRelationFilterChanged: {
        newsGlide.stop();
        newsList.contentY = 0;
    }
    Component.onCompleted: {
        scheduleHourlyRefresh();
        if (active)
            instrumentFetchTimer.restart();
    }

    Connections {
        target: root
        function onSymbolChanged() { panel.instrumentChanged(); }
        function onMarketChanged() { panel.instrumentChanged(); }
        function onSnapshotChanged() {
            if (panel.active && panel.loadedInstrumentKey !== panel.instrumentKey)
                instrumentFetchTimer.restart();
        }
        function onXxlLayoutChanged() { panel.scheduleHourlyRefresh(); }
    }

    Timer {
        id: instrumentFetchTimer
        interval: 180
        onTriggered: {
            let mode = panel.delayedRefreshMode;
            panel.delayedRefreshMode = "cache";
            panel.requestFetch(mode);
        }
    }

    Timer {
        id: hourlyRefresh
        repeat: false
        onTriggered: {
            panel.requestFetch("hourly");
            panel.scheduleHourlyRefresh();
        }
    }

    Process {
        id: fetchProc

        onRunningChanged: panel.loading = running
        onExited: (code, exitStatus) => {
            if (code !== 0 && panel.articles.length === 0)
                panel.status = panel.root.t("Could not load market news.");
            if (panel.pendingFetch) {
                let mode = panel.pendingRefreshMode || "cache";
                panel.pendingFetch = false;
                panel.pendingRefreshMode = "";
                Qt.callLater(() => panel.requestFetch(mode));
            }
        }

        stdout: StdioCollector {
            onStreamFinished: panel.applyNews(text)
        }

    }

    Process {
        id: openProc

        command: ["true"]
    }

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: root.raisedColor
        border.color: root.separatorColor
        border.width: 1

        Item {
            id: header

            anchors.leftMargin: 13
            anchors.rightMargin: 10
            height: 94

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }

            Column {
                anchors.rightMargin: 10
                anchors.topMargin: 12
                spacing: 1

                anchors {
                    left: parent.left
                    right: headerActions.left
                    top: parent.top
                }

                Text {
                    width: parent.width
                    text: root.t("Market News")
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: panel.updatedAt > 0 ? root.t(panel.cachedResult ? "Cached · Updated %1" : "Updated %1", [NewsService.clock(panel.updatedAt)]) : root.t("Up to 3 days")
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

            }

            Row {
                id: headerActions

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 10
                spacing: 5

                HeaderButton {
                    label: "↻"
                    enabled: !panel.loading
                    onTriggered: panel.requestFetch(true)
                }

            }

            Rectangle {
                id: relationSelector

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 54
                height: 34
                radius: 10
                color: root.backgroundColor

                Row {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: [{ id: "all", label: root.t("All") },
                            { id: "direct", label: root.t("Company") },
                            { id: "theme", label: root.t("Industry") }]

                        Rectangle {
                            required property var modelData

                            width: (relationSelector.width - 8) / 3
                            height: 30
                            radius: 8
                            color: panel.relationFilter === modelData.id
                                ? Qt.rgba(0.04, 0.52, 1, root.dark ? 0.28 : 0.16)
                                : (relationHover.hovered ? root.separatorColor : "transparent")
                            scale: relationArea.pressed ? ThemeService.pressScale : 1

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: panel.relationFilter === parent.modelData.id ? "#0a84ff" : root.secondaryColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            HoverHandler { id: relationHover }
                            MouseArea {
                                id: relationArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: panel.relationFilter = parent.modelData.id
                            }
                            Behavior on scale { AppleSpring { spring: 24 } }
                        }
                    }
                }
            }

        }

        Rectangle {
            id: pageSelector

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 13
            anchors.rightMargin: 10
            anchors.bottomMargin: 10
            height: 34
            radius: 10
            color: root.backgroundColor
            z: 2

            Row {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2

                Repeater {
                    model: [root.t("Today"), root.t("Yesterday"), root.t("Two days ago")]

                    Rectangle {
                        required property int index
                        required property string modelData

                        width: (pageSelector.width - 8) / 3
                        height: 30
                        radius: 8
                        color: panel.newsPage === index
                            ? Qt.rgba(0.04, 0.52, 1, root.dark ? 0.28 : 0.16)
                            : (pageHover.hovered ? root.separatorColor : "transparent")
                        scale: pageArea.pressed ? ThemeService.pressScale : 1

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: panel.newsPage === parent.index ? "#0a84ff" : root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        HoverHandler { id: pageHover }
                        MouseArea {
                            id: pageArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: panel.newsPage = parent.index
                        }
                        Behavior on scale { AppleSpring { spring: 24 } }
                    }
                }
            }
        }

        Rectangle {
            height: 1
            color: root.separatorColor

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
            }

        }

        ListView {
            id: newsList

            property var _ks: ({
            })

            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 2
            anchors.bottomMargin: 6
            clip: true
            model: panel.pageArticles
            boundsBehavior: Flickable.DragAndOvershootBounds
            boundsMovement: Flickable.FollowBoundsBehavior
            flickDeceleration: 6000
            maximumFlickVelocity: 6000

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: pageSelector.top
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    newsGlide.stop();
                    if (Kinetic.onWheel(newsList, event, newsList._ks, {
                        "gain": 72
                    }))
                        newsEndTimer.restart();

                }
            }

            Timer {
                id: newsEndTimer

                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(newsList, newsList._ks, {
                    });
                    if (!glide)
                        return ;

                    newsGlide.from = glide.from;
                    newsGlide.to = glide.to;
                    newsGlide.restart();
                }
            }

            SpringAnimation {
                id: newsGlide

                target: newsList
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }

            rebound: Transition {
                SpringAnimation {
                    properties: "x,y"
                    spring: 18
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }

            }

            delegate: Item {
                id: articleRow

                required property var modelData

                width: newsList.width
                height: 84
                scale: articleTap.pressed ? 0.985 : 1

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 10
                    color: articleTap.pressed ? Qt.rgba(0.04, 0.52, 1, root.dark ? 0.17 : 0.1) : (articleHover.hovered ? Qt.rgba(0.5, 0.5, 0.55, root.dark ? 0.12 : 0.07) : "transparent")
                }

                Column {
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    anchors.topMargin: 9
                    spacing: 4

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }

                    Text {
                        width: parent.width
                        text: panel.articleMetadata(modelData)
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: modelData.title
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        lineHeight: 1.08
                    }

                }

                Rectangle {
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    height: 1
                    color: root.separatorColor

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }

                }

                HoverHandler {
                    id: articleHover
                }

                TapHandler {
                    id: articleTap

                    onTapped: panel.openArticle(articleRow.modelData.url)
                }

                Behavior on scale {
                    AppleSpring {
                        spring: 24
                    }

                }

            }

        }

        Column {
            visible: panel.pageArticles.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: newsList.verticalCenter
            width: parent.width - 38
            spacing: 7

            Text {
                width: parent.width
                text: panel.loading ? "↻" : "\uf1ea"
                color: root.secondaryColor
                font.family: panel.loading ? "SF Pro Display" : NewsService.iconFont
                font.pixelSize: 28
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: panel.loading ? root.t("Loading market news…") : (panel.status || root.t("No news for this day."))
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

        }

    }

    component HeaderButton: Rectangle {
        property string label: ""
        property bool accented: false

        signal triggered()

        width: Math.max(30, buttonLabel.implicitWidth + 16)
        height: 28
        radius: 9
        color: accented ? Qt.rgba(0.04, 0.52, 1, buttonHover.hovered ? 0.28 : 0.18) : (buttonHover.hovered ? root.separatorColor : "transparent")
        opacity: enabled ? 1 : 0.38
        scale: buttonArea.pressed ? ThemeService.pressScale : 1

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: parent.label
            color: parent.accented ? "#0a84ff" : root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: parent.accented ? 10 : 17
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: buttonHover
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: parent.triggered()
        }

        Behavior on scale {
            AppleSpring {
                spring: 24
            }

        }

    }

}
