pragma Singleton
import Quickshell
import QtQuick

// Single source of truth for the bar's visibility and geometry. Popups (clock
// flyout, control center, notification toasts) sit a fixed gap below the bar
// and read `contentTop` so they rise when the bar is hidden and drop back when
// it returns, instead of floating at a hardcoded y.
Singleton {
    id: root

    property bool visible: true

    // Must mirror Bar.qml's PanelWindow margins.top + implicitHeight.
    readonly property int topMargin: 10
    readonly property int barHeight: 33

    // Uniform gap every popup keeps from the bar (and, when the bar is hidden,
    // from the top of the screen). Change here to retune all popups at once.
    readonly property int gap: 10

    // Y at which popups should start: `gap` below the bar when shown, or `gap`
    // below the screen top when hidden. Consumers use this directly.
    readonly property int contentTop: visible ? (topMargin + barHeight + gap) : gap
}
