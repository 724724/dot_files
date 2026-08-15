#!/usr/bin/env python3
"""Pick the most vivid colour out of an ImageMagick histogram.

Reads `magick ... -format %c histogram:info:-` on stdin and prints one #rrggbb
line — the colour the bar's EQ bars are tinted with.

Scoring favours saturated, mid-brightness colours that actually cover a
meaningful share of the cover, so we don't end up tinting the bars with the
near-black background or a stray white highlight.
"""
import math
import re
import sys

HIST = re.compile(r"^\s*(\d+):.*#([0-9A-Fa-f]{6})")


def score(r, g, b, count, total):
    mx, mn = max(r, g, b), min(r, g, b)
    sat = 0.0 if mx == 0 else (mx - mn) / mx
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    # Penalise the extremes — pure black/white carry no hue to tint with.
    mid = 1.0 - min(1.0, ((lum - 0.55) / 0.55) ** 2)
    share = count / total if total else 0.0
    return sat * 1.6 + mid * 0.7 + math.sqrt(share) * 0.5


def main():
    best, best_score, total = None, -1.0, 0
    entries = []
    for line in sys.stdin:
        m = HIST.match(line)
        if not m:
            continue
        count = int(m.group(1))
        hexv = m.group(2)
        r = int(hexv[0:2], 16)
        g = int(hexv[2:4], 16)
        b = int(hexv[4:6], 16)
        entries.append((count, r, g, b, hexv))
        total += count

    for count, r, g, b, hexv in entries:
        s = score(r, g, b, count, total)
        if s > best_score:
            best_score, best = s, hexv

    if best:
        print("#" + best.lower())


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
