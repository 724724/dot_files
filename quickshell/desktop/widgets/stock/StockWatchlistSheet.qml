import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.watchlistVisible || watchlistPanel.x > -watchlistPanel.width - 7
    z: 90

    MouseArea {
        anchors { left: watchlistPanel.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        enabled: root.watchlistVisible
        onPressed: root.closeWatchlist()
    }
    Rectangle {
        x: watchlistPanel.x + 4
        y: 5
        width: watchlistPanel.width
        height: watchlistPanel.height
        radius: 16
        color: Qt.rgba(0, 0, 0, 0.24)
        opacity: root.watchlistVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }
    Rectangle {
        id: watchlistPanel
        x: root.watchlistVisible ? 0 : -width - 8
        y: 0
        width: 304
        height: parent.height
        radius: 16
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        Behavior on x { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: watchlistTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 18
            anchors.topMargin: 17
            text: root.t("Watchlist")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 19
            font.weight: Font.DemiBold
            font.letterSpacing: -0.3
        }
        Text {
            anchors { left: parent.left; top: watchlistTitle.bottom }
            anchors.leftMargin: 18
            anchors.topMargin: 3
            width: parent.width - 36
            text: root.watchSearchText.trim() !== ""
                ? (root.watchSearchBusy ? root.t("Searching…")
                    : (root.watchSearchError !== "" ? root.t(root.watchSearchError)
                    : root.t("%1 results", [root.watchSearchResults.length])))
                : (root.watchlistError !== "" ? root.t(root.watchlistError)
                    : (root.watchlistBusy ? root.t("Updating quotes…")
                    : root.t("%1 symbols", [root.watchlist.length])))
            color: root.watchSearchText.trim() !== "" && root.watchSearchError !== "" ? root.negativeColor
                : (root.watchlistError !== "" ? root.negativeColor : root.secondaryColor)
            font.family: "SF Pro Display"
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Rectangle {
            id: manageAlertsButton
            anchors { right: closeWatchlistButton.left; top: parent.top }
            anchors.rightMargin: 7
            anchors.topMargin: 12
            width: 66
            height: 32
            radius: 10
            color: manageAlertsHover.hovered ? root.raisedColor : root.separatorColor
            scale: manageAlertsArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.t("Alerts %1", [root.enabledAlertCount])
                color: root.enabledAlertCount > 0 ? "#0a84ff" : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: manageAlertsHover }
            MouseArea {
                id: manageAlertsArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openAlerts(root.snapshot)
            }
        }
        Rectangle {
            id: closeWatchlistButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 12
            anchors.topMargin: 12
            width: 32
            height: 32
            radius: 10
            color: closeWatchlistHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeWatchlistArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeWatchlistHover }
            MouseArea {
                id: closeWatchlistArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeWatchlist()
            }
        }
        Rectangle {
            id: watchSearchField
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 66
            height: 36
            radius: 10
            color: root.backgroundColor
            border.color: watchSearchInput.activeFocus ? "#0a84ff" : root.separatorColor
            border.width: 1
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: watchSearchInput.activeFocus ? "#0a84ff" : root.secondaryColor
                font.family: ThemeService.iconFont
                font.pixelSize: 10
            }
            TextField {
                id: watchSearchInput
                anchors { left: parent.left; right: clearWatchSearchButton.left; top: parent.top; bottom: parent.bottom }
                anchors.leftMargin: 30
                anchors.rightMargin: 4
                text: root.watchSearchText
                placeholderText: root.dataMode === "kis" ? root.t("Search Korean stocks") : root.t("Search name or symbol")
                placeholderTextColor: root.secondaryColor
                color: root.foregroundColor
                selectionColor: "#0a84ff"
                background: null
                font.family: "SF Pro Display"
                font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.searchWatchlist(text)
                onAccepted: if (root.watchSearchResults.length === 1) root.addSearchResult(root.watchSearchResults[0])
            }
            Rectangle {
                id: clearWatchSearchButton
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 8
                visible: root.watchSearchText !== ""
                color: clearWatchSearchHover.hovered ? root.separatorColor : "transparent"
                scale: clearWatchSearchArea.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 22 } }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                }
                HoverHandler { id: clearWatchSearchHover }
                MouseArea {
                    id: clearWatchSearchArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: {
                        root.searchWatchlist("")
                        watchSearchInput.forceActiveFocus()
                    }
                }
            }
        }

        ListView {
            id: searchResultsView
            anchors { left: parent.left; right: parent.right; top: watchSearchField.bottom; bottom: parent.bottom }
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            visible: root.watchSearchText.trim() !== ""
            clip: true
            spacing: 4
            model: root.watchSearchResults
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
            delegate: Rectangle {
                required property var modelData
                readonly property bool added: root.watchlist.some(item => item.symbol === modelData.symbol && item.market === modelData.market)
                readonly property bool canAdd: true
                width: searchResultsView.width
                height: 52
                radius: 11
                color: searchResultHover.hovered ? root.raisedColor : "transparent"
                opacity: canAdd ? 1 : 0.46
                scale: searchResultArea.pressed ? ThemeService.pressScale : 1
                Behavior on opacity { AppleSpring { spring: 22 } }
                Behavior on scale { AppleSpring { spring: 22 } }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 70
                    spacing: 2
                    Text {
                        width: parent.width
                        text: modelData.name || modelData.symbol
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: (modelData.exchange || modelData.market) + " · " + modelData.symbol
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 28
                    radius: 9
                    color: parent.added ? root.separatorColor : Qt.rgba(0.04, 0.52, 1, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: parent.parent.added ? root.t("Added") : root.t("Add")
                        color: parent.parent.added ? root.secondaryColor : "#0a84ff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: searchResultHover }
                MouseArea {
                    id: searchResultArea
                    anchors.fill: parent
                    enabled: parent.canAdd
                    cursorShape: Qt.PointingHandCursor
                    onPressed: if (!parent.added) root.addSearchResult(parent.modelData)
                }
            }
            Text {
                anchors.centerIn: parent
                visible: searchResultsView.count === 0
                width: parent.width - 28
                text: root.watchSearchBusy ? root.t("Searching symbols…")
                    : (root.watchSearchError !== "" ? root.t(root.watchSearchError) : root.t("No matching symbols."))
                color: root.watchSearchError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        ListView {
            id: watchlistView
            anchors { left: parent.left; right: parent.right; top: watchSearchField.bottom; bottom: parent.bottom }
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            visible: root.watchSearchText.trim() === ""
            clip: true
            spacing: 4
            model: root.watchlistState.items || []
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
                onWheel: (event) => {
                    watchlistGlide.stop()
                    if (Kinetic.onWheel(watchlistView, event, watchlistView._ks, { gain: 72 }))
                        watchlistEndTimer.restart()
                }
            }
            Timer {
                id: watchlistEndTimer
                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(watchlistView, watchlistView._ks, {})
                    if (glide) {
                        watchlistGlide.from = glide.from
                        watchlistGlide.to = glide.to
                        watchlistGlide.restart()
                    }
                }
            }
            SpringAnimation {
                id: watchlistGlide
                target: watchlistView
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
            delegate: Rectangle {
                required property var modelData
                readonly property bool selected: modelData.symbol === root.symbol && modelData.market === root.market
                width: watchlistView.width
                height: 58
                radius: 11
                color: selected ? (root.dark ? "#3a3a3c" : "#f1f1f4")
                    : (watchItemHover.hovered ? root.raisedColor : "transparent")
                scale: watchItemArea.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 22 } }
                MouseArea {
                    id: watchItemArea
                    anchors { left: parent.left; right: alertWatchButton.left; top: parent.top; bottom: parent.bottom }
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.selectWatchItem(modelData)
                }
                HoverHandler { id: watchItemHover }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: 118
                    spacing: 2
                    Text {
                        width: parent.width
                        text: modelData.name || modelData.symbol
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: modelData.market + " · " + modelData.symbol
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Column {
                    anchors.right: alertWatchButton.left
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 78
                    spacing: 2
                    Text {
                        width: parent.width
                        anchors.right: parent.right
                        text: modelData.status === "error" ? root.t("Unavailable")
                            : StockService.money(modelData.price, modelData.currency)
                        color: modelData.status === "error" ? root.secondaryColor : root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        anchors.right: parent.right
                        text: modelData.status === "error" ? (modelData.message ? root.t(modelData.message) : root.t("Quote error"))
                            : StockService.signed(modelData.changePct, 2) + "%"
                        color: modelData.status === "error" ? root.negativeColor
                            : (Number(modelData.changePct || 0) >= 0 ? root.positiveColor : root.negativeColor)
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    id: alertWatchButton
                    anchors.right: removeWatchButton.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: 9
                    color: alertWatchHover.hovered ? Qt.rgba(0.04, 0.52, 1, 0.18) : root.separatorColor
                    scale: alertWatchArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: ThemeService.reminderGlyph("bell")
                        color: root.alertCountFor(modelData) > 0 ? "#0a84ff" : root.secondaryColor
                        font.family: ThemeService.iconFont
                        font.pixelSize: 11
                    }
                    HoverHandler { id: alertWatchHover }
                    MouseArea {
                        id: alertWatchArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.openAlerts(modelData)
                    }
                }
                Rectangle {
                    id: removeWatchButton
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    radius: 9
                    color: removeWatchHover.hovered ? Qt.rgba(1, 0.27, 0.23, 0.18) : root.separatorColor
                    scale: removeWatchArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    HoverHandler { id: removeWatchHover }
                    MouseArea {
                        id: removeWatchArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.removeWatchItem(modelData)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: watchlistView.count === 0
                width: parent.width - 28
                text: root.watchlistError !== "" ? root.t(root.watchlistError)
                    : (root.watchlistBusy ? root.t("Loading watchlist…")
                    : root.t("Add the current symbol to start a watchlist."))
                color: root.watchlistError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
