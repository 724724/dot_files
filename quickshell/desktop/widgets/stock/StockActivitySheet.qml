import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.activityVisible || activityPanel.opacity > 0.002
    z: 110

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.activityVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.activityVisible
        onPressed: root.closeActivity()
    }
    Rectangle {
        id: activityPanel
        anchors.fill: parent
        anchors.margins: 14
        radius: 17
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.activityVisible ? 1 : 0
        scale: root.activityVisible ? 1 : 0.965
        transformOrigin: Item.BottomRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: activityTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 18
            text: root.t("Trade Activity")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
        }
        Text {
            anchors { left: parent.left; top: activityTitle.bottom }
            anchors.leftMargin: 22
            anchors.topMargin: 3
            text: root.t("Local audit trail · not a substitute for your KIS broker statement")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Rectangle {
            id: refreshActivityButton
            anchors { right: closeActivityButton.left; top: parent.top }
            anchors.rightMargin: 8
            anchors.topMargin: 14
            width: 72
            height: 32
            radius: 10
            color: refreshActivityHover.hovered ? root.raisedColor : root.separatorColor
            opacity: activityProcess.running ? 0.42 : 1
            scale: refreshActivityArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: activityProcess.running ? root.t("Updating…") : root.t("Refresh")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: refreshActivityHover }
            MouseArea {
                id: refreshActivityArea
                anchors.fill: parent
                enabled: !activityProcess.running
                cursorShape: Qt.PointingHandCursor
                onPressed: root.refreshActivity()
            }
        }
        Rectangle {
            id: closeActivityButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 14
            anchors.topMargin: 14
            width: 32
            height: 32
            radius: 10
            color: closeActivityHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeActivityArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeActivityHover }
            MouseArea {
                id: closeActivityArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeActivity()
            }
        }

        Rectangle {
            id: activityFilters
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 72
            width: 246
            height: 32
            radius: 10
            color: root.dark ? "#333336" : "#e9e9ee"
            Row {
                anchors.fill: parent
                ActivityFilterButton { width: parent.width / 3; label: root.t("All"); filterId: "all" }
                ActivityFilterButton { width: parent.width / 3; label: root.t("Paper"); filterId: "paper" }
                ActivityFilterButton { width: parent.width / 3; label: root.t("Production"); filterId: "prod" }
            }
        }

        Row {
            id: activitySummary
            anchors { left: parent.left; right: parent.right; top: activityFilters.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 12
            height: 58
            spacing: 10
            ActivityMetric {
                width: (parent.width - 30) / 4
                title: root.t("ACCEPTED")
                value: Number((root.activityState.counts || {}).accepted || 0).toString()
                accent: root.positiveColor
            }
            ActivityMetric {
                width: (parent.width - 30) / 4
                title: root.t("FAILED")
                value: Number((root.activityState.counts || {}).failed || 0).toString()
                accent: root.negativeColor
            }
            ActivityMetric {
                width: (parent.width - 30) / 4
                title: root.t("SUBMITTING")
                value: Number((root.activityState.counts || {}).pending || 0).toString()
                accent: "#0a84ff"
            }
            ActivityMetric {
                width: (parent.width - 30) / 4
                title: root.t("VERIFY")
                value: Number((root.activityState.counts || {}).uncertain || 0).toString()
                accent: "#ff9f0a"
            }
        }

        ListView {
            id: activityList
            anchors { left: parent.left; right: parent.right; top: activitySummary.bottom; bottom: parent.bottom }
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 12
            anchors.bottomMargin: 14
            clip: true
            spacing: 6
            model: root.activityState.activity || []
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
                    activityGlide.stop()
                    if (Kinetic.onWheel(activityList, event, activityList._ks, { gain: 78 }))
                        activityEndTimer.restart()
                }
            }
            Timer {
                id: activityEndTimer
                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(activityList, activityList._ks, {})
                    if (glide) {
                        activityGlide.from = glide.from
                        activityGlide.to = glide.to
                        activityGlide.restart()
                    }
                }
            }
            SpringAnimation {
                id: activityGlide
                target: activityList
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
            delegate: Rectangle {
                required property var modelData
                width: activityList.width
                height: 58
                radius: 11
                color: root.raisedColor
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 4
                    radius: 2
                    color: root.activityStatusColor(modelData.status)
                }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 12
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 94 - 96 - 24
                        spacing: 2
                        Text {
                            width: parent.width
                            text: root.activityTitle(modelData)
                            color: root.foregroundColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.activityDetail(modelData)
                            color: modelData.status === "uncertain" ? "#ff9f0a" : root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 94
                        height: 24
                        radius: 7
                        color: root.dark ? "#3a3a3c" : "#f1f1f4"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.environment === "prod" ? root.t("Production") : root.t("Paper")
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        spacing: 2
                        Text {
                            anchors.right: parent.right
                            text: root.t(root.activityStatusLabel(modelData.status))
                            color: root.activityStatusColor(modelData.status)
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.analysisTime(modelData.timestamp)
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 8
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: activityList.count === 0
                text: root.activityError !== "" ? root.t(root.activityError)
                    : (activityProcess.running ? root.t("Loading local activity…")
                        : root.t("No local trade activity yet."))
                color: root.activityError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }

        Rectangle {
            anchors { left: activityList.left; right: activityList.right; top: activityList.top }
            height: 18
            visible: activityList.contentY > 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: activityPanel.color }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: Math.min(1, activityList.contentY / 14)
            Behavior on opacity { AppleSpring { spring: 22 } }
        }
    }

    component ActivityFilterButton: Item {
        property string label: ""
        property string filterId: "all"
        readonly property bool selected: root.activityFilter === filterId
        scale: activityFilterArea.pressed ? ThemeService.pressScale : 1
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
            id: activityFilterArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: root.chooseActivityFilter(parent.filterId)
        }
    }

    component ActivityMetric: Rectangle {
        property string title: ""
        property string value: "0"
        property color accent: "#0a84ff"
        height: 58
        radius: 11
        color: root.raisedColor
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                radius: 2.5
                color: parent.parent.accent
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 13
                spacing: 2
                Text {
                    width: parent.width
                    text: parent.parent.parent.title
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.35
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: parent.parent.parent.value
                    color: parent.parent.parent.accent
                    font.family: "SF Pro Display"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
