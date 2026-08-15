.pragma library

// Spatially anchored, non-overlapping overview packing. Every preview keeps its
// aspect ratio and a common scale. We begin at each window's real screen centre,
// resolve collisions with progressively weaker anchor attraction, then search
// for the largest common scale that fits the safe stage.

function _clamp(value, lower, upper) {
    return Math.max(lower, Math.min(upper, value))
}

function _number(value, fallback) {
    var number = Number(value)
    return Number.isFinite(number) ? number : fallback
}

function _windowMap(windows) {
    var result = {}
    for (var i = 0; i < windows.length; ++i) {
        var win = windows[i]
        if (win && win.address) result[win.address] = win
    }
    return result
}

function _entries(addresses, windows, monitor, width, height) {
    var byAddress = _windowMap(windows || [])
    var scale = Math.max(0.1, _number(monitor && monitor.scale, 1))
    var monitorWidth = Math.max(1, _number(monitor && monitor.width, width) / scale)
    var monitorHeight = Math.max(1, _number(monitor && monitor.height, height) / scale)
    var monitorX = _number(monitor && monitor.x, 0)
    var monitorY = _number(monitor && monitor.y, 0)
    var result = []

    for (var i = 0; i < addresses.length; ++i) {
        var address = addresses[i]
        var win = byAddress[address]
        if (!win || !win.size || !win.at) continue
        var sourceWidth = Math.max(8, _number(win.size[0], 8))
        var sourceHeight = Math.max(8, _number(win.size[1], 8))
        var localCenterX = _number(win.at[0], monitorX) - monitorX + sourceWidth / 2
        var localCenterY = _number(win.at[1], monitorY) - monitorY + sourceHeight / 2
        result.push({
            address: address,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            anchorX: _clamp(localCenterX / monitorWidth * width, 0, width),
            anchorY: _clamp(localCenterY / monitorHeight * height, 0, height),
            order: i
        })
    }
    return result
}

function _overlaps(boxes, gap) {
    for (var i = 0; i < boxes.length; ++i) {
        for (var j = i + 1; j < boxes.length; ++j) {
            var a = boxes[i]
            var b = boxes[j]
            if (Math.abs(a.cx - b.cx) < (a.width + b.width) / 2 + gap - 0.35
                    && Math.abs(a.cy - b.cy) < (a.height + b.height) / 2 + gap - 0.35)
                return true
        }
    }
    return false
}

function _relax(entries, scale, width, height, gap) {
    var boxes = []
    for (var i = 0; i < entries.length; ++i) {
        var entry = entries[i]
        var boxWidth = entry.sourceWidth * scale
        var boxHeight = entry.sourceHeight * scale
        if (boxWidth + gap * 2 > width || boxHeight + gap * 2 > height) return null
        boxes.push({
            address: entry.address,
            width: boxWidth,
            height: boxHeight,
            anchorX: entry.anchorX,
            anchorY: entry.anchorY,
            cx: _clamp(entry.anchorX, gap + boxWidth / 2, width - gap - boxWidth / 2),
            cy: _clamp(entry.anchorY, gap + boxHeight / 2, height - gap - boxHeight / 2),
            order: entry.order
        })
    }

    for (var iteration = 0; iteration < 260; ++iteration) {
        var dx = new Array(boxes.length).fill(0)
        var dy = new Array(boxes.length).fill(0)
        // Anchor attraction fades out, leaving a final pure collision pass.
        var anchorStrength = iteration < 150 ? 0.024 * (1 - iteration / 150) : 0

        for (var aIndex = 0; aIndex < boxes.length; ++aIndex) {
            var anchored = boxes[aIndex]
            dx[aIndex] += (anchored.anchorX - anchored.cx) * anchorStrength
            dy[aIndex] += (anchored.anchorY - anchored.cy) * anchorStrength
        }

        for (var left = 0; left < boxes.length; ++left) {
            for (var right = left + 1; right < boxes.length; ++right) {
                var first = boxes[left]
                var second = boxes[right]
                var centerDx = second.cx - first.cx
                var centerDy = second.cy - first.cy
                var overlapX = (first.width + second.width) / 2 + gap - Math.abs(centerDx)
                var overlapY = (first.height + second.height) / 2 + gap - Math.abs(centerDy)
                if (overlapX <= 0 || overlapY <= 0) continue

                // Resolve along the axis that needs the least relative travel.
                if (overlapX / Math.max(1, Math.min(first.width, second.width))
                        < overlapY / Math.max(1, Math.min(first.height, second.height))) {
                    var xDirection = Math.abs(centerDx) > 0.01
                        ? (centerDx > 0 ? 1 : -1)
                        : (first.anchorX !== second.anchorX
                            ? (second.anchorX > first.anchorX ? 1 : -1)
                            : (first.order < second.order ? 1 : -1))
                    var xPush = (overlapX + 0.45) * 0.53
                    dx[left] -= xDirection * xPush
                    dx[right] += xDirection * xPush
                } else {
                    var yDirection = Math.abs(centerDy) > 0.01
                        ? (centerDy > 0 ? 1 : -1)
                        : (first.anchorY !== second.anchorY
                            ? (second.anchorY > first.anchorY ? 1 : -1)
                            : (first.order < second.order ? 1 : -1))
                    var yPush = (overlapY + 0.45) * 0.53
                    dy[left] -= yDirection * yPush
                    dy[right] += yDirection * yPush
                }
            }
        }

        for (var move = 0; move < boxes.length; ++move) {
            var current = boxes[move]
            current.cx = _clamp(current.cx + dx[move] * 0.72,
                gap + current.width / 2, width - gap - current.width / 2)
            current.cy = _clamp(current.cy + dy[move] * 0.72,
                gap + current.height / 2, height - gap - current.height / 2)
        }
    }

    return _overlaps(boxes, gap) ? null : boxes
}

function _gridFallback(entries, width, height, gap) {
    var count = entries.length
    var columns = Math.max(1, Math.ceil(Math.sqrt(count * width / Math.max(1, height))))
    var rows = Math.max(1, Math.ceil(count / columns))
    var cellWidth = width / columns
    var cellHeight = height / rows
    var ordered = entries.slice().sort(function(a, b) {
        if (a.anchorY !== b.anchorY) return a.anchorY - b.anchorY
        if (a.anchorX !== b.anchorX) return a.anchorX - b.anchorX
        return a.order - b.order
    })
    var result = {}

    for (var i = 0; i < ordered.length; ++i) {
        var entry = ordered[i]
        var fitScale = Math.min(
            Math.max(0.02, (cellWidth - gap * 2) / entry.sourceWidth),
            Math.max(0.02, (cellHeight - gap * 2) / entry.sourceHeight),
            0.76)
        var boxWidth = entry.sourceWidth * fitScale
        var boxHeight = entry.sourceHeight * fitScale
        var column = i % columns
        var row = Math.floor(i / columns)
        result[entry.address] = {
            x: column * cellWidth + (cellWidth - boxWidth) / 2,
            y: row * cellHeight + (cellHeight - boxHeight) / 2,
            width: boxWidth,
            height: boxHeight,
            scale: fitScale
        }
    }
    return result
}

function pack(addresses, windows, monitor, width, height, requestedGap) {
    width = Math.max(1, _number(width, 1))
    height = Math.max(1, _number(height, 1))
    var gap = Math.max(8, _number(requestedGap, 20))
    var entries = _entries(addresses || [], windows || [], monitor, width, height)
    if (entries.length === 0) return {}

    var totalArea = 0
    var largestWidth = 1
    var largestHeight = 1
    for (var i = 0; i < entries.length; ++i) {
        totalArea += entries[i].sourceWidth * entries[i].sourceHeight
        largestWidth = Math.max(largestWidth, entries[i].sourceWidth)
        largestHeight = Math.max(largestHeight, entries[i].sourceHeight)
    }

    var areaScale = Math.sqrt(width * height * 0.66 / Math.max(1, totalArea))
    var maximumScale = Math.min(
        entries.length === 1 ? 0.78 : 0.72,
        areaScale,
        (width - gap * 2) / largestWidth,
        (height - gap * 2) / largestHeight)
    maximumScale = Math.max(0.02, maximumScale)

    var lower = 0
    var upper = maximumScale
    var best = null
    for (var attempt = 0; attempt < 11; ++attempt) {
        var candidateScale = (lower + upper) / 2
        var candidate = _relax(entries, candidateScale, width, height, gap)
        if (candidate) {
            best = candidate
            lower = candidateScale
        } else {
            upper = candidateScale
        }
    }

    if (!best) return _gridFallback(entries, width, height, gap)

    var result = {}
    for (var boxIndex = 0; boxIndex < best.length; ++boxIndex) {
        var box = best[boxIndex]
        result[box.address] = {
            x: box.cx - box.width / 2,
            y: box.cy - box.height / 2,
            width: box.width,
            height: box.height,
            scale: box.width / Math.max(1, entries[boxIndex].sourceWidth)
        }
    }
    return result
}
