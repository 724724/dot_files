import QtQuick
import QtQuick.Controls
import "../../widgets/kinetic.js" as Kinetic
import ".." as Bar

ListView {
    id: root

    property real wheelGain: 58
    property var kineticState: ({})

    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    flickDeceleration: 6000
    maximumFlickVelocity: 6000
    rebound: Transition {
        SpringAnimation {
            properties: "x,y"
            spring: 22
            damping: Bar.ThemeService.momentumDamping
            epsilon: 0.25
        }
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            glide.stop()
            event.accepted = true
            if (Kinetic.onWheel(root, event, root.kineticState, { gain: root.wheelGain }))
                wheelEnd.restart()
        }
    }

    Timer {
        id: wheelEnd
        interval: 48
        onTriggered: {
            let motion = Kinetic.fling(root, root.kineticState, {})
            if (motion) {
                glide.from = motion.from
                glide.to = motion.to
                glide.restart()
            }
        }
    }

    SpringAnimation {
        id: glide
        target: root
        property: "contentY"
        spring: 22
        damping: Bar.ThemeService.momentumDamping
        epsilon: 0.25
    }
}
