import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../icons" as Icons

Rectangle {
    id: btn
    required property var workspace

    // Icon names of the apps open on this workspace (one per distinct class).
    readonly property var apps: WorkspaceWindows.appsByWorkspace[String(workspace.id)] || []

    implicitWidth: Math.max(content.implicitWidth + 24, 36)
    implicitHeight: 33
    scale: pointer.pressed ? ThemeService.pressScale : 1
    transformOrigin: Item.Center

    color: workspace.focused
        ? Qt.rgba(255/255, 140/255, 130/255, 0.4)
        : workspace.urgent
            ? Qt.rgba(255/255, 100/255, 100/255, 0.5)
            : hover.hovered
                ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                : "transparent"
    border.color: workspace.focused
        ? Qt.rgba(255/255, 140/255, 130/255, 0.5)
        : "transparent"
    border.width: workspace.focused ? 1 : 0
    radius: 999

    Behavior on scale { AppleSpring { spring: 13 } }

    HoverHandler { id: hover }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 0

        Text {
            id: label
            Layout.alignment: Qt.AlignVCenter
            text: workspace.name
            color: ThemeService.isDark
                ? (workspace.focused ? "#ffd4d0" : workspace.urgent ? "#ffffff" : "#8ba3b8")
                : (workspace.focused || workspace.urgent ? "#1c1c1e" : Qt.rgba(0, 0, 0, 0.5))
            font.family: "SF Pro Display"
            font.pixelSize: 11

        }

        // Small app icons for whatever is open on this workspace. Grouped in a
        // Row with its own tight spacing and a left margin, so the gap from the
        // workspace number is a bit wider than the gap between icons.
        Row {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 7
            spacing: 3
            visible: btn.apps.length > 0
            // The number's text box reserves descent space below the digit, so
            // its visual centre sits ~1px above the box centre that the layout
            // aligns to. Nudge the icons up the same amount (render-only, no
            // layout impact) so they read as centred against the number.
            transform: Translate { y: -1 }

            Repeater {
                model: btn.apps
                delegate: Icons.AppIcon {
                    required property var modelData
                    width: 11
                    height: 11
                    sourceSize.width: 11
                    sourceSize.height: 11
                    smooth: true
                    mipmap: true
                    iconName: modelData
                }
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: workspace.activate()
    }
}
