import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "kinetic.js" as Kinetic

// In-board "save as" dialog for exporting a note to a text file — the same
// in-QML folder-browser pattern as the clock's alarm-sound picker
// (ClockFilePicker), restyled dark to match the board's modals. Replaces the
// zenity dialog, which could only be seen by hiding the whole layer-shell
// board first. Click a folder to enter it, ↑ goes up; clicking a .txt file
// copies its name into the filename field. Overwrite is two-step: when the
// name already exists in the folder, the first 저장 click arms a warning and
// the button becomes 바꾸기.
Item {
    id: root

    property string filename: ""
    property string content: ""
    property bool active: false
    signal cancelled
    signal saved(string path)

    implicitWidth: 470
    implicitHeight: 470

    property bool armed: false
    property bool writeFailed: false

    onActiveChanged: {
        if (!active) return
        folderModel.folder = "file://" + Quickshell.env("HOME")
        nameField.text = root.filename
        root.armed = false
        root.writeFailed = false
        nameField.forceActiveFocus()
        let dot = nameField.text.lastIndexOf(".")
        nameField.select(0, dot > 0 ? dot : nameField.text.length)
    }

    function localPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
    }
    // Filename actually written: trimmed, path separators dropped, ".txt"
    // appended when there's no extension.
    function targetName() {
        let n = nameField.text.trim().replace(/\//g, "-")
        if (n !== "" && !/\.[A-Za-z0-9]+$/.test(n)) n += ".txt"
        return n
    }
    function fileExists(name) {
        for (let i = 0; i < folderModel.count; i++)
            if (!folderModel.isFolder(i) && folderModel.get(i, "fileName") === name)
                return true
        return false
    }
    function save() {
        let name = root.targetName()
        if (name === "") return
        if (root.fileExists(name) && !root.armed) { root.armed = true; return }
        writer.failed = false
        writer.path = root.localPath(folderModel.folder) + "/" + name
        writer.setText(root.content)
        if (writer.failed) { root.writeFailed = true; root.armed = false; return }
        root.saved(writer.path)
    }

    // blockWrites makes setText synchronous, so `failed` is valid right after.
    FileView {
        id: writer
        property bool failed: false
        blockLoading: true
        blockWrites: true
        printErrors: false
        onSaveFailed: failed = true
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + Quickshell.env("HOME")
        showFiles: true
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        nameFilters: ["*.txt"]
    }

    // ── Header: 취소 / title / 저장 ─────────────────────────────────────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 32

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "취소"
            color: Qt.rgba(0.42, 0.62, 1, 1)
            font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold
            scale: cancelTap.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 20 } }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { id: cancelTap; onPressedChanged: if (pressed) root.cancelled() }
        }
        Text {
            anchors.centerIn: parent
            text: "메모 저장"
            color: "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 17
            font.weight: Font.DemiBold; font.letterSpacing: -0.2
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.armed ? "바꾸기" : "저장"
            color: root.armed ? "#ffd60a" : Qt.rgba(0.42, 0.62, 1, 1)
            opacity: nameField.text.trim() !== "" ? 1 : 0.35
            font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.DemiBold
            scale: saveTap.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 20 } }
            HoverHandler { enabled: nameField.text.trim() !== ""; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: saveTap
                enabled: nameField.text.trim() !== ""
                onPressedChanged: if (pressed) root.save()
            }
        }
    }

    // ── Current folder + up button ──────────────────────────────────────────
    Rectangle {
        id: pathBar
        anchors { left: parent.left; right: parent.right; top: header.bottom }
        anchors.topMargin: 10
        height: 40
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: upButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.localPath(folderModel.folder).replace(Quickshell.env("HOME"), "~")
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "SF Pro Display"; font.pixelSize: 12
            elide: Text.ElideMiddle
        }
        Rectangle {
            id: upButton
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: upHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "↑"
                color: "#ffffff"
                font.family: "SF Pro Display"; font.pixelSize: 16
            }
            HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onPressedChanged: if (pressed && String(folderModel.parentFolder) !== "") {
                    root.armed = false
                    folderModel.folder = folderModel.parentFolder
                }
            }
        }
    }

    // ── Folder contents (dirs + .txt files) ─────────────────────────────────
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: pathBar.bottom; bottom: warnText.top }
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        radius: 14
        color: "transparent"
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            model: folderModel
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

            // Kinetic scroll (kinetic.js) — same feel as the note body.
            property var _ks: ({})
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (ev) => {
                    listGlide.stop()
                    if (Kinetic.onWheel(list, ev, list._ks, { gain: 52 }))
                        listEndTimer.restart()
                }
            }
            Timer {
                id: listEndTimer
                interval: 48
                onTriggered: {
                    let g = Kinetic.fling(list, list._ks, {})
                    if (g) { listGlide.from = g.from; listGlide.to = g.to; listGlide.restart() }
                }
            }
            SpringAnimation {
                id: listGlide
                target: list
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }

            delegate: Rectangle {
                id: fileRow
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                width: ListView.view.width
                height: 44
                radius: 9
                color: (!fileIsDir && nameField.text === fileName)
                     ? Qt.rgba(0.30, 0.52, 0.95, 0.30)
                     : rowHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                scale: rowTap.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 20 } }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: fileRow.fileIsDir ? "" : ""   // nf folder / doc
                    color: fileRow.fileIsDir ? Qt.rgba(0.42, 0.62, 1, 1) : Qt.rgba(1, 1, 1, 0.55)
                    font.family: ThemeService.iconFont; font.pixelSize: 14
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: fileRow.fileName
                    color: "#ffffff"
                    font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: rowTap
                    onPressedChanged: if (pressed) {
                        root.armed = false
                        if (fileRow.fileIsDir) folderModel.folder = fileRow.fileUrl
                        else nameField.text = fileRow.fileName
                    }
                    onDoubleTapped: if (!fileRow.fileIsDir) root.save()
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: folderModel.status === FolderListModel.Ready && folderModel.count === 0
            text: "빈 폴더"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "SF Pro Display"; font.pixelSize: 13
        }
    }

    // ── Overwrite / failure notice ──────────────────────────────────────────
    Text {
        id: warnText
        anchors { left: parent.left; right: parent.right; bottom: nameRow.top }
        anchors.bottomMargin: visible ? 8 : 0
        height: visible ? implicitHeight : 0
        visible: root.armed || root.writeFailed
        text: root.writeFailed
            ? "저장하지 못했습니다 — 이 폴더에 쓸 수 없습니다."
            : "\"" + root.targetName() + "\" 파일이 이미 있습니다. 바꾸기를 누르면 덮어씁니다."
        color: root.writeFailed ? "#ff6b6b" : "#ffd60a"
        wrapMode: Text.Wrap
        font.family: "SF Pro Display"; font.pixelSize: 12
    }

    // ── Filename ────────────────────────────────────────────────────────────
    Rectangle {
        id: nameRow
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 40
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: nameField.activeFocus ? Qt.rgba(0.4, 0.6, 1, 0.7) : Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
        Text {
            id: nameLabel
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "파일 이름"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "SF Pro Display"; font.pixelSize: 12
        }
        TextField {
            id: nameField
            anchors.fill: parent
            anchors.leftMargin: nameLabel.width + 22
            anchors.rightMargin: 10
            background: null
            color: "#ffffff"
            font.family: "SF Pro Display"; font.pixelSize: 13
            verticalAlignment: TextInput.AlignVCenter
            onTextChanged: { root.armed = false; root.writeFailed = false }
            onAccepted: root.save()
        }
    }
}
