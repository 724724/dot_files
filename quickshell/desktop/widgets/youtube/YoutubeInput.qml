import QtQuick
import QtQuick.Controls
import ".."

Rectangle {
    id: shell
    required property var widget
    property bool showInspect: true
    property int fieldSize: 14
    height: 42
    radius: 11
    color: widget.surface
    border.color: input.activeFocus ? widget.alpha(widget.accent, 0.8) : ThemeService.separator
    border.width: input.activeFocus ? 1.5 : 1

    Text {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: ""
        color: input.activeFocus ? widget.accent : widget.secondary
        font.family: ThemeService.iconFont
        font.pixelSize: 12
    }
    TextField {
        id: input
        anchors { left: parent.left; right: showInspect ? inspectButton.left : parent.right; top: parent.top; bottom: parent.bottom }
        anchors.leftMargin: 36
        anchors.rightMargin: showInspect ? 7 : 11
        text: widget.inputValue
        placeholderText: "YouTube link or video ID"
        placeholderTextColor: widget.tertiary
        color: widget.foreground
        selectionColor: widget.alpha(widget.accent, 0.55)
        selectedTextColor: widget.foreground
        background: null
        font.family: "SF Pro Display"
        font.pixelSize: shell.fieldSize
        verticalAlignment: TextInput.AlignVCenter
        onTextEdited: widget.inputValue = text
        onEditingFinished: widget.updateInput(text)
        onAccepted: widget.inspect(text)
    }
    Rectangle {
        id: inspectButton
        visible: shell.showInspect
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        width: 78
        height: parent.height - 10
        radius: 9
        color: inspectHover.hovered ? widget.raised : widget.alpha(widget.raised, 0.78)
        opacity: input.text.trim() !== "" && !widget.service.inspecting ? 1 : 0.45
        scale: inspectArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Text {
            anchors.centerIn: parent
            text: widget.service.inspecting ? "Loading…" : "Get Info"
            color: widget.foreground
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        HoverHandler { id: inspectHover }
        MouseArea {
            id: inspectArea
            anchors.fill: parent
            enabled: input.text.trim() !== "" && !widget.service.inspecting
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: widget.inspect(input.text)
        }
    }

    function value() { return input.text }
}
