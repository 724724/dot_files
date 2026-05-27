import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property Notification notification
    property bool inControlCenter: false

    // Invoked by the × button. When null, dismisses just this notification.
    // The grouped stack overrides it so a collapsed group's × clears every
    // notification from that app at once.
    property var closeAction: null

    readonly property bool dark: ThemeService.isDark
    readonly property bool hasImage: notification.image && notification.image !== ""

    implicitWidth: 380
    implicitHeight: cardContent.implicitHeight + 24
    radius: 14

    color: dark ? Qt.rgba(58/255, 58/255, 64/255, 0.92)
                : Qt.rgba(255/255, 255/255, 255/255, 0.94)
    border.color: dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.06)
    border.width: 1

    Behavior on implicitHeight { NumberAnimation { duration: 150 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Top-right relative timestamp — always at the corner of the card,
    // even when an image preview is rendered.
    Text {
        id: timeText
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 12
            topMargin: 12
        }
        text: NcServer.relativeTime(card.notification.id)
        color: dark ? Qt.rgba(1,1,1,0.4) : Qt.rgba(0,0,0,0.40)
        font.family: "SF Pro Display"
        font.pixelSize: 10
        opacity: hoverArea.containsMouse || closeMa.containsMouse ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 100 } }
        z: 5
    }

    // × close — replaces the timestamp on hover.
    Rectangle {
        id: closeBtn
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 8
            topMargin: 8
        }
        width: 18; height: 18
        radius: 9
        color: dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.10)
        border.color: dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.10)
        border.width: 1
        opacity: hoverArea.containsMouse || closeMa.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
        z: 10

        Text {
            anchors.centerIn: parent
            text: "×"
            color: dark ? "#dcdce0" : "#3a3a3c"
            font.pixelSize: 14
            font.family: "SF Pro Display"
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.closeAction ? card.closeAction() : card.notification.dismiss()
        }
    }

    RowLayout {
        id: cardContent
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 12
            topMargin: 12
            bottomMargin: 12
        }
        spacing: 12

        // App icon — square with subtle background
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 8
            color: dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(0,0,0,0.05)

            Image {
                anchors.fill: parent
                anchors.margins: 4
                source: card.notification.appIcon
                    ? "image://icon/" + card.notification.appIcon
                    : ""
                visible: status === Image.Ready
                sourceSize.width: 32; sourceSize.height: 32
                smooth: true
                asynchronous: true
            }

            Text {
                anchors.centerIn: parent
                text: (card.notification.appName || "?").charAt(0).toUpperCase()
                color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                visible: !card.notification.appIcon
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                // Reserve room for the absolute-positioned timestamp/close
                // when there is no image to push the column inward.
                Layout.rightMargin: card.hasImage ? 0 : 36
                text: (card.notification.appName || "Notification").toUpperCase()
                color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.50)
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: card.notification.summary
                color: dark ? "#f5f6f8" : "#1c1c1e"
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
                text: card.notification.body
                color: dark ? Qt.rgba(1,1,1,0.65) : Qt.rgba(0,0,0,0.60)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                visible: text !== ""
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 6
                visible: card.notification.actions.length > 0

                Repeater {
                    model: card.notification.actions
                    delegate: Rectangle {
                        required property NotificationAction modelData
                        height: 26
                        width: actLabel.implicitWidth + 18
                        radius: 13
                        color: actMa.containsMouse
                            ? (dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.10))
                            : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: modelData.text
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }
        }

        // Right-side image preview — pushed down with topMargin so it
        // doesn't visually clash with the timestamp at the top-right corner.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            Layout.topMargin: 18
            radius: 8
            color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.04)
            visible: card.hasImage
            clip: true

            Image {
                anchors.fill: parent
                source: card.notification.image
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 112
                sourceSize.height: 112
                smooth: true
                asynchronous: true
            }
        }
    }
}
