#!/usr/bin/env python3
import array
import hashlib
import json
import math
import pathlib
import subprocess
import sys
import time


def run(command):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def duration_of(path):
    result = run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path)
    ])
    return max(0.0, float(result.stdout.decode().strip()))


def waveform(path, duration, bins=180, rate=4000):
    process = subprocess.Popen([
        "ffmpeg", "-v", "error", "-i", str(path), "-vn", "-ac", "1",
        "-ar", str(rate), "-f", "s16le", "pipe:1"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    peaks = [0] * bins
    total_samples = max(1, int(math.ceil(duration * rate)))
    sample_index = 0
    while True:
        chunk = process.stdout.read(16384)
        if not chunk:
            break
        samples = array.array("h")
        samples.frombytes(chunk[:len(chunk) - len(chunk) % 2])
        for sample in samples:
            index = min(bins - 1, sample_index * bins // total_samples)
            peaks[index] = max(peaks[index], abs(sample))
            sample_index += 1
    process.wait()
    maximum = max(peaks) or 1
    return [round(value / maximum, 3) for value in peaks]


def probe(path_value):
    path = pathlib.Path(path_value).expanduser().resolve()
    duration = duration_of(path)
    print(json.dumps({
        "ok": True,
        "path": str(path),
        "label": path.stem,
        "duration": round(duration, 3),
        "peaks": waveform(path, duration)
    }, ensure_ascii=False))


def create(path_value, start_value, end_value, output_dir_value):
    source = pathlib.Path(path_value).expanduser().resolve()
    start = max(0.0, float(start_value))
    end = min(duration_of(source), float(end_value))
    if end - start < 0.5:
        raise ValueError("The selected sound must be at least 0.5 seconds long.")
    output_dir = pathlib.Path(output_dir_value).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(f"{source}:{start:.3f}:{end:.3f}:{time.time_ns()}".encode()).hexdigest()[:12]
    output = output_dir / f"{source.stem}-{digest}.wav"
    run([
        "ffmpeg", "-y", "-v", "error", "-ss", f"{start:.3f}", "-i", str(source),
        "-t", f"{end - start:.3f}", "-vn", "-ac", "2", "-ar", "44100",
        "-c:a", "pcm_s16le", str(output)
    ])
    print(json.dumps({
        "ok": True,
        "id": "custom:" + digest,
        "label": source.stem,
        "path": str(output),
        "duration": round(end - start, 3)
    }, ensure_ascii=False))


def main():
    try:
        if len(sys.argv) < 3:
            raise ValueError("Missing command arguments.")
        if sys.argv[1] == "probe":
            probe(sys.argv[2])
        elif sys.argv[1] == "create" and len(sys.argv) == 6:
            create(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
        else:
            raise ValueError("Unknown command.")
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
