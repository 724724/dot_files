import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.alertsVisible || alertsPanel.opacity > 0.002
    z: 120

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.alertsVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.alertsVisible
        onPressed: root.closeAlerts()
    }
    Rectangle {
        id: alertsPanel
        anchors.fill: parent
        anchors.margins: 14
        radius: 17
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.alertsVisible ? 1 : 0
        scale: root.alertsVisible ? 1 : 0.965
        transformOrigin: Item.TopRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: alertsTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 18
            text: root.t("Price Alerts")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
        }
        Text {
            anchors { left: parent.left; top: alertsTitle.bottom }
            anchors.leftMargin: 22
            anchors.topMargin: 3
            text: root.t("Crossing alerts fire once, then re-arm after the price moves back.")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Rectangle {
            id: closeAlertsButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 14
            anchors.topMargin: 14
            width: 32
            height: 32
            radius: 10
            color: closeAlertsHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeAlertsArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeAlertsHover }
            MouseArea {
                id: closeAlertsArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeAlerts()
            }
        }

        Rectangle {
            id: alertComposer
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 78
            height: 112
            radius: 14
            color: root.raisedColor
            border.color: root.separatorColor
            border.width: 1

            Column {
                anchors { left: parent.left; top: parent.top }
                anchors.leftMargin: 14
                anchors.topMargin: 11
                width: 210
                spacing: 2
                Text {
                    width: parent.width
                    text: root.alertDraftSymbol
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.t(StockService.marketLabel(root.alertDraftMarket))
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                }
            }
            Text {
                anchors { right: parent.right; top: parent.top }
                anchors.rightMargin: 14
                anchors.topMargin: 16
                width: parent.width - 250
                text: root.alertEditorError !== "" ? root.t(root.alertEditorError)
                    : root.t("%1 of 16 alerts", [root.priceAlerts.length])
                color: root.alertEditorError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
            Rectangle {
                id: alertDirectionChoices
                anchors { left: parent.left; bottom: parent.bottom }
                anchors.leftMargin: 14
                anchors.bottomMargin: 13
                width: 190
                height: 36
                radius: 10
                color: root.dark ? "#333336" : "#e9e9ee"
                Row {
                    anchors.fill: parent
                    AlertDirectionButton { width: parent.width / 2; label: root.t("Above"); value: "above" }
                    AlertDirectionButton { width: parent.width / 2; label: root.t("Below"); value: "below" }
                }
            }
            Rectangle {
                anchors { left: alertDirectionChoices.right; right: addAlertButton.left; bottom: parent.bottom }
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.bottomMargin: 13
                height: 36
                radius: 10
                color: root.backgroundColor
                border.color: alertTargetField.activeFocus ? "#0a84ff" : root.separatorColor
                border.width: 1
                TextField {
                    id: alertTargetField
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    placeholderText: root.alertDraftPrice > 0
                        ? root.t("Target · %1", [StockService.price(root.alertDraftPrice,
                            root.alertDraftMarket === "KRX" ? "KRW" : "USD")])
                        : root.t("Target price")
                    placeholderTextColor: root.secondaryColor
                    color: root.foregroundColor
                    selectionColor: "#0a84ff"
                    background: null
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: DoubleValidator { bottom: 0.000001 }
                    text: root.alertTargetText
                    onTextChanged: {
                        root.alertTargetText = text
                        root.alertEditorError = ""
                    }
                    onAccepted: root.addPriceAlert()
                }
            }
            Rectangle {
                id: addAlertButton
                anchors { right: parent.right; bottom: parent.bottom }
                anchors.rightMargin: 14
                anchors.bottomMargin: 13
                width: 104
                height: 36
                radius: 10
                color: "#0a84ff"
                opacity: root.priceAlerts.length < 16 ? 1 : 0.46
                scale: addAlertArea.pressed ? ThemeService.pressScale : 1
                Behavior on opacity { AppleSpring { spring: 22 } }
                Behavior on scale { AppleSpring { spring: 22 } }
                Text {
                    anchors.centerIn: parent
                    text: root.t("Add Alert")
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: addAlertArea
                    anchors.fill: parent
                    enabled: root.priceAlerts.length < 16
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.addPriceAlert()
                }
            }
        }

        ListView {
            id: alertsList
            anchors { left: parent.left; right: parent.right; top: alertComposer.bottom; bottom: parent.bottom }
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 12
            anchors.bottomMargin: 14
            clip: true
            spacing: 6
            model: root.priceAlerts
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
                    alertsGlide.stop()
                    if (Kinetic.onWheel(alertsList, event, alertsList._ks, { gain: 78 })) alertsEndTimer.restart()
                }
            }
            Timer {
                id: alertsEndTimer
                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(alertsList, alertsList._ks, {})
                    if (glide) {
                        alertsGlide.from = glide.from
                        alertsGlide.to = glide.to
                        alertsGlide.restart()
                    }
                }
            }
            SpringAnimation {
                id: alertsGlide
                target: alertsList
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
            delegate: Rectangle {
                required property var modelData
                width: alertsList.width
                height: 62
                radius: 12
                color: root.raisedColor
                border.color: root.separatorColor
                border.width: 1

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: modelData.enabled === false ? root.secondaryColor
                        : (modelData.armed === false ? "#ff9f0a" : "#0a84ff")
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 31
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 31 - 218
                    spacing: 2
                    Text {
                        width: parent.width
                        text: modelData.symbol + " · " + root.t(StockService.marketLabel(modelData.market))
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: modelData.enabled === false ? root.t("Paused")
                            : (modelData.armed === false
                                ? (Number(modelData.lastTriggeredAt || 0) > 0
                                    ? root.t("Triggered · waiting to re-arm") : root.t("Waiting for recross"))
                                : root.t("Armed"))
                        color: modelData.armed === false && modelData.enabled !== false ? "#ff9f0a" : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Column {
                    anchors.right: alertToggleButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.alertDirectionLabel(modelData.direction)
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 8
                        horizontalAlignment: Text.AlignRight
                    }
                    Text {
                        width: parent.width
                        text: StockService.money(modelData.target, root.alertCurrency(modelData))
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    id: alertToggleButton
                    anchors.right: deleteAlertButton.left
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    height: 30
                    radius: 9
                    color: alertToggleHover.hovered ? root.separatorColor
                        : (modelData.enabled === false ? root.backgroundColor : Qt.rgba(0.04, 0.52, 1, 0.18))
                    scale: alertToggleArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.enabled === false ? root.t("Resume") : root.t("Pause")
                        color: modelData.enabled === false ? root.secondaryColor : "#0a84ff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: alertToggleHover }
                    MouseArea {
                        id: alertToggleArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.togglePriceAlert(modelData.id)
                    }
                }
                Rectangle {
                    id: deleteAlertButton
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 9
                    color: deleteAlertHover.hovered ? Qt.rgba(1, 0.27, 0.23, 0.18) : root.separatorColor
                    scale: deleteAlertArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    HoverHandler { id: deleteAlertHover }
                    MouseArea {
                        id: deleteAlertArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.removePriceAlert(modelData.id)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: alertsList.count === 0
                text: root.t("No price alerts yet.")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }
    }

    component AlertDirectionButton: Item {
        id: alertDirectionButton
        property string label: ""
        property string value: "above"
        readonly property bool selected: root.alertDirection === value
        scale: alertDirectionArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            color: parent.selected ? (root.dark ? "#505055" : "#ffffff") : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: parent.selected ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: alertDirectionArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: root.alertDirection = parent.value
        }
    }
}
