import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: ed
    property int index: -1

    implicitWidth: 440
    implicitHeight: col.implicitHeight

    property var sources: []
    property var categories: []
    property int layout: 2
    property string modelName: NewsService.defaultModel
    property var modelChoices: NewsService.commonModels
    property string modelStatus: ""

    onIndexChanged: ed.reload()
    Component.onCompleted: ed.loadModels()

    function reload() {
        if (index === -1) return
        let d = WidgetsService.getData(index)
        layout = d.layout || 2
        sources = (d.sources && d.sources.length) ? d.sources.slice() : NewsService.defaultSources()
        categories = (d.categories && d.categories.length) ? d.categories.slice() : NewsService.defaultCategories()
        modelName = d.model || NewsService.defaultModel
        if (modelChoices.indexOf(modelName) < 0) {
            let m = modelChoices.slice()
            m.unshift(modelName)
            modelChoices = m
        }
    }

    function loadModels() {
        modelsProc.command = ["python3", NewsService.newsScript, "models"]
        modelsProc.running = true
    }

    function toggle(list, id) {
        let a = list.slice()
        let pos = a.indexOf(id)
        if (pos >= 0) {
            if (a.length === 1) return a
            a.splice(pos, 1)
        } else {
            a.push(id)
        }
        return a
    }

    function toggleSource(id) {
        sources = toggle(sources, id)
        WidgetsService.setData(index, { sources: sources })
    }

    function setLayout(n) {
        WidgetsService.setNewsLayout(index, n)
        ed.reload()
    }

    function toggleCategory(id) {
        categories = toggle(categories, id)
        WidgetsService.setData(index, { categories: categories })
    }

    function setModel(name) {
        if (!name || name.length === 0) return
        modelName = name
        WidgetsService.setData(index, { model: name })
    }

    Process {
        id: modelsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text || "{}")
                    let m = (j.models && j.models.length) ? j.models : NewsService.commonModels
                    if (m.indexOf(ed.modelName) < 0) m.unshift(ed.modelName)
                    ed.modelChoices = m
                    ed.modelStatus = (j.models && j.models.length) ? "" : "설치된 ollama 모델이 없으면 요약은 실행되지 않습니다."
                } catch (e) {
                    ed.modelChoices = NewsService.commonModels
                    ed.modelStatus = "ollama 모델 목록을 읽지 못했습니다."
                }
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 14

        Text {
            text: "News"
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Column {
            width: parent.width
            spacing: 8
            Text {
                text: "Layout"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Row {
                spacing: 8
                Repeater {
                    model: NewsService.layoutOptions
                    delegate: TogglePill {
                        required property var modelData
                        label: modelData.label
                        selected: ed.layout === modelData.id
                        onTriggered: ed.setLayout(modelData.id)
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8
            Text {
                text: "Newspapers"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: NewsService.sourceOptions
                    delegate: TogglePill {
                        required property var modelData
                        label: modelData.label
                        selected: NewsService.has(ed.sources, modelData.id)
                        onTriggered: ed.toggleSource(modelData.id)
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8
            Text {
                text: "Categories"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: NewsService.categoryOptions
                    delegate: TogglePill {
                        required property var modelData
                        label: modelData.label
                        selected: NewsService.has(ed.categories, modelData.id)
                        onTriggered: ed.toggleCategory(modelData.id)
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8
            Text {
                text: "Ollama Model"
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            ComboBox {
                id: modelBox
                width: parent.width
                height: 36
                editable: true
                model: ed.modelChoices
                currentIndex: Math.max(0, ed.modelChoices.indexOf(ed.modelName))
                onActivated: (i) => ed.setModel(ed.modelChoices[i])
                onAccepted: ed.setModel(editText)
                font.family: "SF Pro Display"
                font.pixelSize: 13
            }
            Text {
                visible: ed.modelStatus.length > 0
                width: parent.width
                text: ed.modelStatus
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    component TogglePill: Rectangle {
        id: pill
        property string label: ""
        property bool selected: false
        signal triggered()
        width: Math.max(78, txt.implicitWidth + 26)
        height: 32
        radius: 9
        color: selected ? Qt.rgba(0.30, 0.52, 0.95, 0.9)
             : (pillHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
        scale: pillMa.pressed ? ThemeService.pressScale : 1.0
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            id: txt
            anchors.centerIn: parent
            text: pill.label
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: pill.selected ? Font.DemiBold : Font.Normal
        }
        HoverHandler { id: pillHover }
        MouseArea {
            id: pillMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.triggered()
        }
    }
}
