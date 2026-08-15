import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import ".." as Bar

Item {
    id: root

    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color hoverFill: Qt.rgba(0, 0, 0, 0.06)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    property url currentFolder: "file://" + Quickshell.env("HOME") + "/Music"
    property string selectedPath: ""
    property bool active: false
    signal cancelled
    signal fileSelected(string path)

    implicitWidth: 470
    implicitHeight: 430
    onActiveChanged: if (!active) stopPreview()

    function localPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
    }

    function choose() {
        if (selectedPath !== "") {
            stopPreview()
            fileSelected(selectedPath)
        }
    }

    function cancel() {
        stopPreview()
        cancelled()
    }

    function stopPreview() {
        if (previewProcess.running) previewProcess.running = false
    }

    function selectFile(path) {
        selectedPath = path
        stopPreview()
        previewProcess.command = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path]
        previewProcess.running = true
    }

    Process { id: previewProcess }

    FolderListModel {
        id: folderModel
        folder: root.currentFolder
        showFiles: true
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        nameFilters: ["*.wav", "*.flac", "*.mp3", "*.m4a", "*.aac", "*.ogg", "*.oga", "*.opus"]
    }

    Item {
        anchors.fill: parent

        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 32

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                color: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                scale: cancelTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: cancelTap; onTapped: root.cancel() }
            }
            Text {
                anchors.centerIn: parent
                text: "Add Sound"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Add"
                color: root.accent
                opacity: root.selectedPath !== "" ? 1 : 0.35
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                scale: chooseTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { enabled: root.selectedPath !== ""; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: chooseTap
                    enabled: root.selectedPath !== ""
                    onTapped: root.choose()
                }
            }
        }

        Rectangle {
            id: pathBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.topMargin: 10
            height: 40
            radius: 12
            color: root.hoverFill
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: upButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.localPath(folderModel.folder)
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }
            Rectangle {
                id: upButton
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: upHover.hovered ? root.hoverFill : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: root.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                }
                HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: if (String(folderModel.parentFolder) !== "") {
                        root.stopPreview()
                        root.selectedPath = ""
                        root.currentFolder = folderModel.parentFolder
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: pathBar.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 10
            radius: 14
            color: "transparent"
            clip: true

            ClockKineticList {
                anchors.fill: parent
                model: folderModel
                wheelGain: 52
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: fileRow
                    required property string fileName
                    required property url fileUrl
                    required property bool fileIsDir
                    width: ListView.view.width
                    height: 52
                    readonly property string path: root.localPath(fileUrl)
                    color: root.selectedPath === path ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                        : rowHover.hovered ? root.hoverFill : "transparent"
                    scale: rowTap.pressed ? Bar.ThemeService.pressScale : 1
                    Behavior on scale { Bar.AppleSpring { spring: 20 } }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: fileRow.fileIsDir ? "▸" : "♪"
                        color: fileRow.fileIsDir ? root.secondaryText : root.accent
                        font.family: "SF Pro Display"
                        font.pixelSize: 15
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: fileRow.fileName
                        color: root.primaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: rowTap
                        onTapped: {
                            if (fileRow.fileIsDir) {
                                root.stopPreview()
                                root.selectedPath = ""
                                root.currentFolder = fileRow.fileUrl
                            } else root.selectFile(fileRow.path)
                        }
                        onDoubleTapped: if (!fileRow.fileIsDir) root.choose()
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: folderModel.status === FolderListModel.Ready && folderModel.count === 0
                text: "No supported audio files"
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 13
            }
        }
    }
}
