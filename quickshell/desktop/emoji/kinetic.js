// Shared kinetic-scroll helpers for Flickable/ListView/GridView on Wayland.
//
// Why custom: native Flickable momentum needs scroll-*phase* wheel events that
// don't reach us here, and QWheelEvent.pixelDelta is empty off macOS. So we use
// angleDelta (which Wayland delivers). A touchpad swipe fires many rapid events
// → we measure the release velocity and glide; an isolated mouse-wheel notch is
// 1–2 events → one crisp step, no glide. We tell them apart by *sustained-ness*
// (event count + cadence), NOT delta magnitude, so a heavily down-scaled
// touchpad (Hyprland scroll_factor) is never misread as a mouse.
//
// `st` is a per-view scratch object: keep one `property var _ks: ({})` on the
// view and pass it in. Tunables via `opts`: { gain, fling }.
.pragma library

function onWheel(flick, ev, st, opts) {
    var gain = opts.gain;
    var now = Date.now();
    var gap = st.lastT > 0 ? (now - st.lastT) : 999;
    if (gap > 120)
        st.count = 0;                       // a fresh gesture started
    st.lastT = now;
    st.count = (st.count || 0) + 1;

    var step = ev.angleDelta.y / 120 * gain;
    var maxY = Math.max(0, flick.contentHeight - flick.height);
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - step));

    // Accumulate velocity only across rapidly-arriving events (a real swipe).
    if (gap < 80) {
        var v = (-step / Math.max(4, gap)) * 1000;   // contentY px / second
        st.vel = (st.vel || 0) * 0.2 + v * 0.8;
    }
    return true;                            // caller arms the end timer
}

// Call when the wheel stream stops. Returns { from, to, duration } to animate,
// or null when the gesture wasn't a sustained swipe (mouse notch → no glide).
function fling(flick, st, opts) {
    var vel = st.vel || 0, count = st.count || 0;
    st.vel = 0;
    if (count < 4 || Math.abs(vel) < 120)
        return null;
    var maxY = Math.max(0, flick.contentHeight - flick.height);
    var target = Math.max(0, Math.min(maxY, flick.contentY + vel * (opts.fling || 0.22)));
    var dist = Math.abs(target - flick.contentY);
    if (dist < 4)
        return null;
    return { from: flick.contentY, to: target, duration: Math.min(1200, Math.max(280, dist * 1.4)) };
}
