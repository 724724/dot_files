.pragma library

// UPower.Device.GetHistory returns a(udu): timestamp, percentage, device state.
// busctl wraps that array as { type: "a(udu)", data: [[...]] }.
function parseBusctl(text) {
    var payload
    try {
        payload = JSON.parse(text)
    } catch (error) {
        return []
    }

    var raw = payload && payload.data && payload.data.length > 0
        ? payload.data[0]
        : []
    if (!Array.isArray(raw)) return []

    var rows = []
    for (var i = 0; i < raw.length; ++i) {
        var item = raw[i]
        if (!Array.isArray(item) || item.length < 3) continue
        var timestamp = Number(item[0]) * 1000
        var percentage = Math.round(Number(item[1]))
        var state = Number(item[2])
        // UPower may include an initial 0%/UNKNOWN marker; it is not a real
        // battery reading and would otherwise draw a false empty battery.
        if (!isFinite(timestamp) || timestamp <= 0
                || !isFinite(percentage) || percentage <= 0
                || !isFinite(state) || state === 0) continue
        rows.push({ timestamp: timestamp, level: percentage, state: state })
    }

    // Although the interface documentation says earliest-to-newest, current
    // UPower versions can return newest-to-earliest.  The bucketer requires a
    // deterministic chronological stream so the latest reading wins per slot.
    rows.sort(function(a, b) { return a.timestamp - b.timestamp })
    return rows
}

function isCharging(state) {
    // UpDeviceState: 1 charging, 4 fully charged, 5 pending charge.
    return state === 1 || state === 4 || state === 5
}

function buildBuckets(text, now) {
    var slotMs = 15 * 60 * 1000
    var cellMs = 3 * 3600 * 1000
    var date = new Date(now)
    var cellStart = new Date(
        date.getFullYear(), date.getMonth(), date.getDate(),
        date.getHours() - (date.getHours() % 3), 0, 0, 0
    ).getTime()
    var rightEdge = cellStart >= now ? cellStart : cellStart + cellMs
    var start = rightEdge - 24 * 3600 * 1000
    var slotCount = 96

    var levels = new Array(slotCount).fill(-1)
    var charging = new Array(slotCount).fill(false)
    var seedLevel = -1
    var seedCharging = false
    var rows = parseBusctl(text)

    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        var rowCharging = isCharging(row.state)
        if (row.timestamp < start) {
            seedLevel = row.level
            seedCharging = rowCharging
            continue
        }
        if (row.timestamp > now) continue
        var slot = Math.floor((row.timestamp - start) / slotMs)
        if (slot < 0 || slot >= slotCount) continue
        levels[slot] = row.level
        charging[slot] = rowCharging
    }

    var samples = []
    var lastLevel = seedLevel
    var lastCharging = seedCharging
    for (var s = 0; s < slotCount; ++s) {
        if (start + s * slotMs >= now) {
            samples.push({ level: 0, charging: false, has: false })
            continue
        }
        if (levels[s] >= 0) {
            lastLevel = levels[s]
            lastCharging = charging[s]
        }
        samples.push({
            level: lastLevel >= 0 ? lastLevel : 0,
            charging: lastLevel >= 0 ? lastCharging : false,
            has: lastLevel >= 0
        })
    }

    return { histStart: start, samples: samples }
}
