import "../icons" as Icons
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

Item {
    id: root

    required property var notification
    property int lifetimeMs: 5000
    readonly property bool dark: ThemeService.isDark
    readonly property string appName: notification ? (notification.appName || "Notification") : "Notification"
    readonly property string appIcon: notification ? (notification.appIcon || "") : ""
    readonly property string image: notification ? (notification.image || "") : ""
    readonly property string summary: notification ? (notification.summary || "") : ""
    readonly property string body: notification ? (notification.body || "") : ""
    readonly property var actions: notification ? notification.actions : []
    readonly property int notificationId: notification ? notification.id : -1
    readonly property bool hasAppIcon: appIcon !== ""
    readonly property bool hasImage: image !== ""
    property bool revealed: false
    property bool closing: false
    property bool completionSent: false
    property real motionX: 414
    property real motionScale: 0.97
    property real motionOpacity: 0

    signal finished()

    function reveal() {
        if (closing || completionSent)
            return ;

        revealed = true;
        motionX = 0;
        motionScale = 1;
        motionOpacity = 1;
    }

    function dismiss() {
        if (closing || completionSent)
            return ;

        closing = true;
        lifetime.stop();
        motionX = root.width + 24;
        motionScale = 0.97;
        motionOpacity = 0;
    }

    function completeDismissal() {
        if (!closing || completionSent)
            return ;

        completionSent = true;
        finished();
    }

    implicitWidth: 390
    implicitHeight: Math.max(68, contentRow.implicitHeight + 28)
    Component.onCompleted: Qt.callLater(root.reveal)
    onMotionOpacityChanged: {
        if (closing && motionOpacity <= 0.002)
            completeDismissal();

    }

    Timer {
        id: lifetime

        interval: Math.max(1, root.lifetimeMs)
        running: root.revealed && !root.closing
        onTriggered: root.dismiss()
    }

    Item {
        id: visual

        anchors.fill: parent
        opacity: root.motionOpacity
        scale: root.motionScale
        transformOrigin: Item.TopRight

        Rectangle {
            x: 1
            y: 3
            width: parent.width - 2
            height: parent.height
            radius: 18
            color: Qt.rgba(0, 0, 0, root.dark ? 0.075 : 0.05)
        }

        Rectangle {
            id: material

            anchors.fill: parent
            radius: 18
            color: root.dark ? Qt.rgba(38 / 255, 38 / 255, 40 / 255, 0.96) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.96)
            border.width: 1
            border.color: root.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.74)

            HoverHandler {
                id: cardHover
            }

            Text {
                text: NcServer.relativeTime(root.notificationId)
                color: root.dark ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0, 0, 0, 0.48)
                font.family: "SF Pro Display"
                font.pixelSize: 10
                opacity: cardHover.hovered || closeArea.containsMouse ? 0 : 1

                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 14
                    rightMargin: 15
                }

                Behavior on opacity {
                    AppleSpring {
                        spring: 16
                    }

                }

            }

            Rectangle {
                id: closeButton

                width: 22
                height: 22
                radius: 11
                color: closeArea.containsMouse ? (root.dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12)) : (root.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07))
                opacity: cardHover.hovered || closeArea.containsMouse ? 1 : 0
                scale: closeArea.pressed ? 0.9 : 1

                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 10
                    rightMargin: 11
                }

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.dark ? "#f2f2f7" : "#3a3a3c"
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeArea

                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                }

                Behavior on opacity {
                    AppleSpring {
                        spring: 16
                    }

                }

                Behavior on scale {
                    AppleSpring {
                        spring: 18
                    }

                }

            }

            RowLayout {
                id: contentRow

                spacing: 12

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14
                    rightMargin: 14
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 9
                    clip: true
                    color: root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)

                    Icons.AppIcon {
                        anchors.fill: parent
                        anchors.margins: 4
                        iconName: root.hasAppIcon ? root.appIcon : ""
                        appClass: root.appName
                        visible: root.hasAppIcon && status === Image.Ready
                        sourceSize.width: 32
                        sourceSize.height: 32
                        smooth: true
                        asynchronous: true
                    }

                    Image {
                        anchors.fill: parent
                        source: !root.hasAppIcon && root.hasImage ? root.image : ""
                        visible: !root.hasAppIcon && root.hasImage && status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 76
                        sourceSize.height: 76
                        smooth: true
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.appName.charAt(0).toUpperCase()
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.58)
                        font.family: "SF Pro Display"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        visible: !root.hasAppIcon && !root.hasImage
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 1
                        border.color: root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.1)
                    }

                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        Layout.rightMargin: 42
                        text: root.appName.toUpperCase()
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.58) : Qt.rgba(0, 0, 0, 0.6)
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.35
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.summary
                        color: root.dark ? "#f5f5f7" : "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: text !== ""
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.body
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(0, 0, 0, 0.72)
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        visible: text !== ""
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: visible ? 6 : 0
                        Layout.preferredHeight: visible ? implicitHeight : 0
                        spacing: 6
                        visible: root.actions.length > 0

                        Repeater {
                            model: root.actions

                            delegate: Rectangle {
                                id: actionButton

                                required property NotificationAction modelData

                                width: actionLabel.implicitWidth + 20
                                height: 27
                                radius: 13.5
                                color: actionArea.containsMouse ? (root.dark ? Qt.rgba(1, 1, 1, 0.19) : Qt.rgba(0, 0, 0, 0.1)) : (root.dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.06))
                                scale: actionArea.pressed ? 0.96 : 1

                                Text {
                                    id: actionLabel

                                    anchors.centerIn: parent
                                    text: actionButton.modelData.text
                                    color: root.dark ? "#f5f5f7" : "#1c1c1e"
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }

                                MouseArea {
                                    id: actionArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: actionButton.modelData.invoke()
                                }

                                Behavior on scale {
                                    AppleSpring {
                                        spring: 18
                                    }

                                }

                            }

                        }

                    }

                }

            }

        }

        transform: Translate {
            x: root.motionX
        }

    }

    Behavior on motionX {
        AppleSpring {
            spring: 18
            epsilon: 0.1
        }

    }

    Behavior on motionScale {
        AppleSpring {
            spring: 10
        }

    }

    Behavior on motionOpacity {
        AppleSpring {
            spring: 13
        }

    }

}
