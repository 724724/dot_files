import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    required property var modelData
    property int barContentTop: 53

    screen: modelData
    implicitHeight: Math.max(1, modelData.height - barContentTop - 8)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: !NcServer.controlCenterVisible && NcServer.popupActive.length > 0
    mask: toastRegion
    WlrLayershell.namespace: "qs-notif"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: barContentTop
    }

    Region {
        id: toastRegion

        item: inputArea
    }

    ScriptModel {
        id: popupModel

        objectProp: "id"
        values: NcServer.popupActive
    }

    Item {
        id: inputArea

        x: toastList.x
        y: toastList.y
        width: toastList.width
        height: Math.min(toastList.height, Math.max(0, Math.ceil(toastList.contentHeight)))
    }

    ListView {
        id: toastList

        width: 390
        spacing: 9
        clip: false
        interactive: false
        reuseItems: false
        currentIndex: -1
        cacheBuffer: Math.max(0, height)
        model: popupModel

        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            topMargin: 4
            rightMargin: 14
        }

        addDisplaced: Transition {
            AppleSpring {
                properties: "y"
                spring: 10
                epsilon: 0.1
            }

        }

        removeDisplaced: Transition {
            AppleSpring {
                properties: "y"
                spring: 10
                epsilon: 0.1
            }

        }

        delegate: Item {
            id: row

            required property var modelData

            width: toastList.width
            height: toast.implicitHeight

            NotificationToast {
                id: toast

                notification: row.modelData
                width: row.width
                lifetimeMs: {
                    let received = NcServer.receivedAt[row.modelData.id];
                    return received ? Math.max(50, 5000 - (Date.now() - received)) : 5000;
                }
                onFinished: {
                    let current = row.modelData;
                    if (!current)
                        return ;

                    if (current.transient)
                        current.dismiss();
                    else
                        NcServer.markPopupSeen(current.id);
                }
            }

        }

    }

}
