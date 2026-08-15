pragma ComponentBehavior: Bound

import Quickshell
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Controls
import "../bar/clock" as Clock

// In-QML directory browser derived from the Bar clock's ClockFilePicker.
// It never launches zenity or a shell and exposes only the current directory.
Item {
    id: root

    property url currentFolder: "file://" + Quickshell.env("HOME")
    signal cancelled()
    signal folderSelected(string path)

    function localPath(url) {
        let value = String(url || "")
        if (value.indexOf("file://localhost/") === 0)
            value = value.slice("file://localhost".length)
        else if (value.indexOf("file://") === 0)
            value = value.slice("file://".length)
        try { return decodeURIComponent(value) } catch (e) { return "" }
    }

    function openAt(url) {
        const value = String(url || "")
        currentFolder = value.indexOf("file://") === 0
            ? value : "file://" + Quickshell.env("HOME")
        folderList.positionViewAtBeginning()
    }

    FolderListModel {
        id: folderModel
        folder: root.currentFolder
        showFiles: false
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 36

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Cancel"
            color: ThemeService.accent
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            scale: cancelTap.pressed ? 0.96 : 1
            Behavior on scale {
                SpringAnimation { spring: 20; damping: 1; epsilon: 0.002 }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { id: cancelTap; onTapped: root.cancelled() }
        }

        Text {
            anchors.centerIn: parent
            text: "Choose Folder"
            color: ThemeService.textPrimary
            font.family: "SF Pro Display"
            font.pixelSize: 17
            font.weight: Font.DemiBold
            font.letterSpacing: -0.2
        }

        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "Choose"
            color: ThemeService.accent
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            scale: chooseTap.pressed ? 0.96 : 1
            Behavior on scale {
                SpringAnimation { spring: 20; damping: 1; epsilon: 0.002 }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: chooseTap
                onTapped: root.folderSelected(root.localPath(folderModel.folder))
            }
        }
    }

    Rectangle {
        id: pathBar
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            topMargin: 8
        }
        height: 40
        radius: 11
        color: ThemeService.fieldBg

        Text {
            anchors {
                left: parent.left
                leftMargin: 12
                right: upButton.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: root.localPath(folderModel.folder).replace(Quickshell.env("HOME"), "~")
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 12
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
        }

        Rectangle {
            id: upButton
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            width: 30; height: 30; radius: 15
            color: upHover.hovered ? ThemeService.hoverBg : "transparent"
            Text {
                anchors.centerIn: parent
                text: "↑"
                color: ThemeService.textPrimary
                font.family: "SF Pro Display"
                font.pixelSize: 16
            }
            HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: if (String(folderModel.parentFolder) !== "") {
                    root.currentFolder = folderModel.parentFolder
                    folderList.positionViewAtBeginning()
                }
            }
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: pathBar.bottom
            bottom: parent.bottom
            topMargin: 8
        }
        radius: 12
        color: ThemeService.listBg
        clip: true

        Clock.ClockKineticList {
            id: folderList
            anchors.fill: parent
            model: folderModel
            wheelGain: 52
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: folderRow
                required property string fileName
                required property url fileUrl
                width: ListView.view.width
                height: 46
                color: rowTap.pressed ? Qt.rgba(0.03, 0.49, 0.94, 0.16)
                    : rowHover.hovered ? ThemeService.rowHover : "transparent"

                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "▸"
                    color: ThemeService.textTertiary
                    font.family: "SF Pro Display"
                    font.pixelSize: 15
                }
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 38
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    text: folderRow.fileName
                    color: ThemeService.textPrimary
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: ThemeService.separator
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: rowTap
                    onTapped: {
                        root.currentFolder = folderRow.fileUrl
                        folderList.positionViewAtBeginning()
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: folderModel.status === FolderListModel.Ready && folderModel.count === 0
            text: "No folders here"
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 13
        }
    }
}
