import QtQuick
import QtQuick.Controls
import ".."

ComboBox {
    id: combo
    required property var widget
    height: 38
    textRole: "label"
    valueRole: "id"
    font.family: "SF Pro Display"
    font.pixelSize: 12
    enabled: !widget.service.busy
    contentItem: Text {
        leftPadding: 11
        rightPadding: 27
        text: combo.displayText
        color: widget.foreground
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.family: "SF Pro Display"
        font.pixelSize: 12
    }
    indicator: Text {
        x: combo.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        color: widget.secondary
        font.family: "SF Pro Display"
        font.pixelSize: 14
    }
    background: Rectangle {
        radius: 10
        color: combo.hovered ? widget.raised : widget.surface
        border.color: ThemeService.separator
        border.width: 1
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: combo.popup.availableWidth
        height: 34
        hoverEnabled: true
        highlighted: combo.highlightedIndex === option.index
        contentItem: Text {
            leftPadding: 8
            rightPadding: 8
            text: modelData.label
            color: widget.foreground
            verticalAlignment: Text.AlignVCenter
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: combo.currentIndex === option.index ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 7
            color: option.down ? widget.alpha(widget.accent, 0.16)
                : (option.hovered || option.highlighted ? widget.raised : "transparent")
        }
    }
    popup: Popup {
        id: menuPopup
        y: combo.height + 5
        width: combo.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 220)
        padding: 4
        contentItem: ListView {
            clip: true
            implicitWidth: menuPopup.availableWidth
            implicitHeight: contentHeight
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: 11
            color: ThemeService.isDark ? "#2c2c2e" : "#ffffff"
            border.color: ThemeService.separator
            border.width: 1
        }
    }
}
