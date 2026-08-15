import QtQuick

// One interruptible, velocity-aware progress value for the whole overview.
// Qt Quick's SpringAnimation exposes a maximum velocity, not an initial one,
// so it cannot hand a trackpad's release velocity into the settle. This small
// display-synchronised integrator uses Apple's response/damping vocabulary and
// always continues from the currently presented value.
QtObject {
    id: root

    property real value: 0
    property real velocity: 0          // normalised progress units / second
    property real targetValue: 0
    property real response: 0.30       // visually reaches the target in ~230ms
    property real dampingRatio: 1.0    // critically damped: no decorative bounce
    property bool reducedMotion: false

    readonly property bool running: frameDriver.running || fadeDriver.running
    signal settled(real value)

    function _clamp(value, lower, upper) {
        return Math.max(lower, Math.min(upper, value))
    }

    function _finite(value, fallback) {
        let number = Number(value)
        return Number.isFinite(number) ? number : fallback
    }

    function stop() {
        frameDriver.stop()
        fadeDriver.stop()
    }

    function snapTo(nextValue) {
        root.stop()
        root.targetValue = root._clamp(root._finite(nextValue, 0), 0, 1)
        root.velocity = 0
        root.value = root.targetValue
    }

    // Direct manipulation path. The caller supplies both the finger-linked
    // value and its measured velocity; neither is low-pass animated here.
    function track(nextValue, nextVelocity) {
        root.stop()
        root.value = root._clamp(root._finite(nextValue, root.value), 0, 1)
        root.targetValue = root.value
        root.velocity = root._clamp(root._finite(nextVelocity, 0), -6, 6)
    }

    function settleTo(nextValue, initialVelocity) {
        let target = root._clamp(root._finite(nextValue, root.value), 0, 1)
        let inheritedVelocity = root._clamp(
            root._finite(initialVelocity, root.velocity), -6, 6)

        // Stopping leaves `value` at the live presentation value. Retargeting
        // therefore cannot jump even when open/close is reversed mid-flight.
        root.stop()
        root.targetValue = target
        root.velocity = inheritedVelocity

        if (Math.abs(root.value - target) < 0.0008
                && Math.abs(root.velocity) < 0.01) {
            root.value = target
            root.velocity = 0
            root.settled(target)
            return
        }

        if (root.reducedMotion) {
            root.velocity = 0
            fadeDriver.from = root.value
            fadeDriver.to = target
            fadeDriver.duration = Math.max(80,
                Math.round(150 * Math.abs(target - root.value)))
            fadeDriver.restart()
        } else {
            frameDriver.restart()
        }
    }

    function _advance(frameSeconds) {
        let dt = root._finite(frameSeconds, 0)
        if (dt <= 0) return
        // A debugger pause or a late frame must not explode the integrator.
        dt = Math.min(dt, 1 / 30)

        let response = Math.max(0.16, root.response)
        let omega = 2 * Math.PI / response
        let stiffness = omega * omega
        let damping = 2 * Math.max(0.5, root.dampingRatio) * omega
        let steps = Math.max(1, Math.ceil(dt / (1 / 120)))
        let step = dt / steps
        let position = root.value
        let speed = root.velocity

        for (let i = 0; i < steps; ++i) {
            let acceleration = stiffness * (root.targetValue - position)
                - damping * speed
            speed += acceleration * step
            position += speed * step
        }

        // A fast flick may cross an endpoint. Finish on that presentation frame
        // instead of integrating an invisible out-of-range spring tail.
        if (position <= 0 && speed <= 0 && root.targetValue <= 0) {
            position = 0
            speed = 0
        } else if (position >= 1 && speed >= 0 && root.targetValue >= 1) {
            position = 1
            speed = 0
        } else {
            position = root._clamp(position, 0, 1)
        }

        if (!Number.isFinite(position) || !Number.isFinite(speed)) {
            root.snapTo(root.targetValue)
            root.settled(root.targetValue)
            return
        }

        root.value = position
        root.velocity = speed
        if (Math.abs(root.value - root.targetValue) < 0.0008
                && Math.abs(root.velocity) < 0.01) {
            let target = root.targetValue
            frameDriver.stop()
            root.value = target
            root.velocity = 0
            root.settled(target)
        }
    }

    property FrameAnimation _frameDriver: FrameAnimation {
        id: frameDriver
        running: false
        onTriggered: root._advance(frameTime)
    }

    property NumberAnimation _fadeDriver: NumberAnimation {
        id: fadeDriver
        target: root
        property: "value"
        easing.type: Easing.OutCubic
        onFinished: {
            root.value = root.targetValue
            root.velocity = 0
            root.settled(root.targetValue)
        }
    }
}
