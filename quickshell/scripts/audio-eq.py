#!/usr/bin/env python3
"""Real-time spectrum for the bar's media pill.

Captures the default sink's monitor with `parec`, runs a small FFT, folds it
into N log-spaced bands (bass → treble) and prints one JSON array per frame:

    [0.03,0.41,0.77,...]        # N floats, 0..1

Design notes
------------
* Small FFT (1024 @ 22050 Hz) at ~30 fps — enough resolution for a 14-bar
  display while staying cheap; this runs only while something is playing.
* Log-spaced bands, because pitch is logarithmic: linear bins would give the
  bass a single bar and smear all the treble across the rest.
* Per-band attack/decay smoothing so bars punch up quickly and fall gently
  instead of strobing.
* The monitor source is re-resolved if `parec` dies (sink switch, e.g. moving
  from speakers to Bluetooth).
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import time

import numpy as np

RATE = 22050
CHUNK = 1024
BANDS = 8
FPS = 30
# Bars rise fast, fall slow — a VU-meter feel rather than a strobe.
ATTACK = 0.55
DECAY = 0.16
# Ignore the very bottom/top of the spectrum: DC rumble and inaudible highs
# only add noise to the display. 7 kHz is about where music still has content
# worth showing at this resolution.
FMIN, FMAX = 45.0, 7000.0
# Music energy rolls off roughly 1/f, so without a tilt the treble bands sit at
# the floor and never light up. Exponent applied to (band centre / FMIN).
TILT = 0.62
# Overall sensitivity of the log compressor, and the level that reads as "full".
GAIN = 260.0
REF = 2.05
# Below this the band is treated as silence, so idle audio shows clean dots
# instead of shimmering noise.
NOISE_FLOOR = 0.004
# Contrast shaping. Levels are normalised against a slowly-decaying peak (so the
# meter adapts to how loud the track is), then everything below FLOOR is pushed
# to zero — otherwise every band hovers at mid-height and the shape is unreadable.
PEAK_DECAY = 0.996
MIN_PEAK = 0.28
FLOOR = 0.52
# >1 pushes the mid-range down so only genuinely loud bands stay tall.
GAMMA = 1.25


def default_monitor():
    """Monitor source for the current default sink."""
    try:
        sink = subprocess.run(["pactl", "get-default-sink"], capture_output=True,
                              text=True, timeout=3).stdout.strip()
        if sink:
            return sink + ".monitor"
    except Exception:
        pass
    # Fall back to whatever monitor exists.
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True,
                             text=True, timeout=3).stdout
        for line in out.splitlines():
            parts = line.split()
            if len(parts) > 1 and parts[1].endswith(".monitor"):
                return parts[1]
    except Exception:
        pass
    return None


def band_edges():
    """Log-spaced bin ranges covering FMIN..FMAX, plus a per-band tilt."""
    freqs = np.fft.rfftfreq(CHUNK, 1.0 / RATE)
    edges = np.logspace(np.log10(FMIN), np.log10(FMAX), BANDS + 1)
    out = []
    tilt = np.empty(BANDS, dtype=np.float32)
    for i in range(BANDS):
        lo = np.searchsorted(freqs, edges[i], side="left")
        hi = np.searchsorted(freqs, edges[i + 1], side="right")
        if hi <= lo:
            hi = min(lo + 1, len(freqs))
        out.append((lo, hi))
        centre = (edges[i] * edges[i + 1]) ** 0.5
        tilt[i] = (centre / FMIN) ** TILT
    return out, tilt


def main():
    if not shutil.which("parec"):
        return 1

    window = np.hanning(CHUNK).astype(np.float32)
    edges, tilt = band_edges()
    smoothed = np.zeros(BANDS, dtype=np.float32)
    peak = MIN_PEAK
    frame_bytes = CHUNK * 2  # s16le mono
    interval = 1.0 / FPS
    proc = None
    last_emit = 0.0

    def stop(*_):
        if proc:
            proc.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    while True:
        monitor = default_monitor()
        if not monitor:
            time.sleep(2)
            continue
        try:
            proc = subprocess.Popen(
                ["parec", "--device=" + monitor, "--rate=%d" % RATE,
                 "--channels=1", "--format=s16le", "--latency-msec=30",
                 # The bar's privacy indicator ignores anything whose client
                 # name looks like the shell. Without this, capturing the
                 # output monitor lights up the "microphone in use" dot.
                 "--client-name=quickshell-eq", "--stream-name=quickshell-eq"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except Exception:
            time.sleep(2)
            continue

        while True:
            raw = proc.stdout.read(frame_bytes)
            if not raw or len(raw) < frame_bytes:
                break  # source died / switched — re-resolve below

            samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            # Remove any DC offset, then normalise by the window's coherent gain
            # so a full-scale tone lands at ~1.0 regardless of CHUNK size.
            samples -= samples.mean()
            spec = np.abs(np.fft.rfft(samples * window)) / (window.sum() * 0.5)

            levels = np.empty(BANDS, dtype=np.float32)
            for i, (lo, hi) in enumerate(edges):
                # PEAK, not mean. Log-spaced bands get progressively wider, so
                # averaging buries a sharp treble partial among dozens of empty
                # bins — which is exactly why the top bands never moved.
                levels[i] = spec[lo:hi].max() if hi > lo else 0.0

            levels[levels < NOISE_FLOOR] = 0.0
            # Tilt first (compensating music's 1/f rolloff), then compress the
            # remaining dynamic range into something the eye reads well.
            levels = np.log10(1.0 + levels * tilt * GAIN)
            levels = np.clip(levels / REF, 0.0, 1.0)

            # Normalise against the recent peak, then stretch: quiet bands fall
            # to the floor and loud ones reach the top, so tall/short actually
            # reads as tall/short.
            peak = max(float(levels.max()), peak * PEAK_DECAY, MIN_PEAK)
            levels = np.clip((levels / peak - FLOOR) / (1.0 - FLOOR), 0.0, 1.0) ** GAMMA

            rising = levels > smoothed
            smoothed += (levels - smoothed) * np.where(rising, ATTACK, DECAY)

            now = time.monotonic()
            if now - last_emit >= interval:
                last_emit = now
                sys.stdout.write(json.dumps([round(float(v), 3) for v in smoothed]) + "\n")
                sys.stdout.flush()

        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            pass
        time.sleep(1)


if __name__ == "__main__":
    try:
        sys.exit(main() or 0)
    except KeyboardInterrupt:
        pass
