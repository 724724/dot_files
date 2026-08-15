#!/usr/bin/env python3
import argparse
import array
import ctypes
import fcntl
import json
import math
import os
import select
import signal
import subprocess
import sys
import time

SINK_NAME = "quickshell_pitch"
SINK_DESCRIPTION = "Pitch-Shifter"
RATE = 48000
CHANNELS = 2
ROUTE_INTERVAL = 0.4
CONTROL_INTERVAL = 0.04
PULSE_LATENCY_MS = 35
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
CONTROL_PATH = os.path.join(RUNTIME_DIR, "qs-pitch.json")
TARGET_PATH = os.path.join(RUNTIME_DIR, "qs-pitch-target")
LOCK_PATH = os.path.join(RUNTIME_DIR, "qs-pitch.lock")
stop_requested = False


def emit(event, **values):
    print(json.dumps({"event": event, **values}, separators=(",", ":")),
          flush=True)


def pactl(*arguments):
    result = subprocess.run(
        ["pactl", *arguments],
        capture_output=True,
        text=True,
        timeout=4,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "pactl failed")
    return result.stdout.strip()


def clamp_semitones(value):
    return max(-12, min(12, int(value)))


def pitch_ratio(semitones):
    return math.pow(2.0, semitones / 12.0)


def read_control(default):
    try:
        with open(CONTROL_PATH, encoding="utf-8") as handle:
            value = json.load(handle)
        return clamp_semitones(value.get("semitones", default))
    except (OSError, TypeError, ValueError):
        return default


def sink_inputs():
    try:
        return json.loads(pactl("-f", "json", "list", "sink-inputs") or "[]")
    except (RuntimeError, ValueError):
        return []


def is_ours(item):
    properties = item.get("properties", {}) or {}
    if str(properties.get("application.process.id", "")) == str(os.getpid()):
        return True
    identity = " ".join(str(properties.get(key, "")) for key in (
        "application.name", "application.process.binary",
        "node.name", "media.name",
    )).lower()
    return "quickshell-pitch" in identity or "pitch-shifter" in identity


def is_filterable(item):
    if is_ours(item):
        return False
    properties = item.get("properties", {}) or {}
    role = str(properties.get("media.role", "")).lower()
    return role not in {
        "event", "notification", "phone", "communication", "game",
    }


class Router:
    def __init__(self):
        self.module = ""
        self.target = ""

    def sink_index(self):
        for line in pactl("list", "short", "sinks").splitlines():
            fields = line.split("\t")
            if len(fields) > 1 and fields[1] == SINK_NAME:
                return fields[0]
        return "-1"

    def real_sinks(self):
        sinks = []
        for line in pactl("list", "short", "sinks").splitlines():
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            name = fields[1]
            if name == SINK_NAME or name.startswith("quickshell_"):
                continue
            sinks.append((0 if "RUNNING" in line.upper() else 1, name))
        sinks.sort()
        return [name for _, name in sinks]

    def choose_target(self):
        candidates = self.real_sinks()
        try:
            default = pactl("get-default-sink")
        except RuntimeError:
            default = ""
        if default in candidates:
            return default
        try:
            with open(TARGET_PATH, encoding="utf-8") as handle:
                remembered = handle.read().strip()
        except OSError:
            remembered = ""
        if remembered in candidates:
            return remembered
        return candidates[0] if candidates else ""

    def remember_target(self, target):
        if not target or target == SINK_NAME:
            return
        self.target = target
        try:
            with open(TARGET_PATH, "w", encoding="utf-8") as handle:
                handle.write(target)
        except OSError:
            pass

    def unload_stale(self):
        for line in pactl("list", "short", "modules").splitlines():
            if "module-null-sink" in line and SINK_NAME in line:
                pactl("unload-module", line.split("\t")[0])

    def setup(self):
        self.remember_target(self.choose_target())
        if not self.target:
            raise RuntimeError("no physical output sink is available")
        self.unload_stale()
        self.module = pactl(
            "load-module",
            "module-null-sink",
            "sink_name=" + SINK_NAME,
            "sink_properties=device.description=%s device.class=filter "
            "node.description=%s" % (SINK_DESCRIPTION, SINK_DESCRIPTION),
            "rate=%d" % RATE,
            "channels=2",
        )
        if self.sink_index() == "-1":
            raise RuntimeError("could not create the pitch-shifter sink")

    def move(self, index, target):
        pactl("move-sink-input", str(index), target)

    def rescan(self):
        candidates = self.real_sinks()
        try:
            default = pactl("get-default-sink")
        except RuntimeError:
            default = ""
        if default in candidates and default != self.target:
            self.remember_target(default)
        filter_index = self.sink_index()
        for item in sink_inputs():
            index = item.get("index")
            current = str(item.get("sink"))
            if is_ours(item):
                if self.target and current != self.target:
                    self.move(index, self.target)
            elif is_filterable(item) and current != filter_index:
                self.move(index, SINK_NAME)

    def teardown(self, pipeline=None):
        candidates = self.real_sinks()
        if self.target not in candidates:
            self.remember_target(candidates[0] if candidates else "")
        filter_index = self.sink_index()
        if self.target:
            for item in sink_inputs():
                if str(item.get("sink")) == filter_index and not is_ours(item):
                    try:
                        self.move(item.get("index"), self.target)
                    except RuntimeError:
                        pass
        if pipeline is not None:
            pipeline.stop()
        if self.module:
            try:
                pactl("unload-module", self.module)
            except RuntimeError:
                pass
        self.module = ""


def acquire_lock():
    handle = open(LOCK_PATH, "w", encoding="utf-8")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


class RubberBandLive:
    WINDOW_SHORT = 0x00000000
    FORMANT_PRESERVED = 0x01000000
    CHANNELS_TOGETHER = 0x10000000

    def __init__(self, semitones):
        self.library = ctypes.CDLL("librubberband.so.3")
        self.library.rubberband_live_new.argtypes = [
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_int,
        ]
        self.library.rubberband_live_new.restype = ctypes.c_void_p
        self.library.rubberband_live_delete.argtypes = [ctypes.c_void_p]
        self.library.rubberband_live_get_block_size.argtypes = [ctypes.c_void_p]
        self.library.rubberband_live_get_block_size.restype = ctypes.c_uint
        self.library.rubberband_live_set_pitch_scale.argtypes = [
            ctypes.c_void_p,
            ctypes.c_double,
        ]
        channel_pointer = ctypes.POINTER(ctypes.c_float)
        self.library.rubberband_live_shift.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(channel_pointer),
            ctypes.POINTER(channel_pointer),
        ]

        options = (
            self.WINDOW_SHORT
            | self.FORMANT_PRESERVED
            | self.CHANNELS_TOGETHER
        )
        self.state = self.library.rubberband_live_new(RATE, CHANNELS, options)
        if not self.state:
            raise RuntimeError("could not create the Rubber Band live shifter")

        self.block_size = self.library.rubberband_live_get_block_size(self.state)
        if self.block_size <= 0:
            self.close()
            raise RuntimeError("Rubber Band returned an invalid block size")

        channel = ctypes.c_float * self.block_size
        self.input_channels = [channel() for _ in range(CHANNELS)]
        self.output_channels = [channel() for _ in range(CHANNELS)]
        pointer_array = channel_pointer * CHANNELS
        self.input_pointers = pointer_array(*[
            ctypes.cast(values, channel_pointer)
            for values in self.input_channels
        ])
        self.output_pointers = pointer_array(*[
            ctypes.cast(values, channel_pointer)
            for values in self.output_channels
        ])
        self.current_ratio = pitch_ratio(semitones)
        self.target_ratio = self.current_ratio
        self.library.rubberband_live_set_pitch_scale(
            self.state,
            self.current_ratio,
        )

    def set_semitones(self, semitones):
        self.target_ratio = pitch_ratio(semitones)

    def process(self, payload):
        samples = array.array("f")
        samples.frombytes(payload)
        if sys.byteorder != "little":
            samples.byteswap()
        expected = self.block_size * CHANNELS
        if len(samples) != expected:
            raise RuntimeError("incomplete audio block")

        for frame in range(self.block_size):
            offset = frame * CHANNELS
            for channel in range(CHANNELS):
                self.input_channels[channel][frame] = samples[offset + channel]

        difference = self.target_ratio - self.current_ratio
        if abs(difference) < 0.000001:
            self.current_ratio = self.target_ratio
        else:
            self.current_ratio += difference * 0.45
        self.library.rubberband_live_set_pitch_scale(
            self.state,
            self.current_ratio,
        )
        self.library.rubberband_live_shift(
            self.state,
            self.input_pointers,
            self.output_pointers,
        )

        output = array.array("f", [0.0]) * expected
        for frame in range(self.block_size):
            offset = frame * CHANNELS
            for channel in range(CHANNELS):
                output[offset + channel] = self.output_channels[channel][frame]
        if sys.byteorder != "little":
            output.byteswap()
        return output.tobytes()

    def close(self):
        if self.state:
            self.library.rubberband_live_delete(self.state)
            self.state = None


class AudioPipeline:
    def __init__(self, target, semitones):
        self.target = target
        self.shifter = RubberBandLive(semitones)
        self.capture = None
        self.playback = None
        self.block_bytes = self.shifter.block_size * CHANNELS * 4

    def start(self):
        common = [
            "--raw",
            "--format=float32le",
            "--rate=" + str(RATE),
            "--channels=" + str(CHANNELS),
            "--latency-msec=" + str(PULSE_LATENCY_MS),
            "--process-time-msec=10",
        ]
        self.capture = subprocess.Popen(
            [
                "parec",
                "--device=" + SINK_NAME + ".monitor",
                "--client-name=quickshell-pitch-source",
                *common,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self.playback = subprocess.Popen(
            [
                "pacat",
                "--playback",
                "--device=" + self.target,
                "--client-name=quickshell-pitch",
                *common,
            ],
            stdin=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )

    def set_semitones(self, semitones):
        self.shifter.set_semitones(semitones)

    @staticmethod
    def _process_error(process):
        if not process or not process.stderr or process.poll() is None:
            return ""
        try:
            return process.stderr.read().decode(errors="replace").strip()
        except OSError:
            return ""

    def _read_block(self):
        if not self.capture or not self.capture.stdout:
            raise RuntimeError("audio capture is unavailable")
        payload = bytearray()
        descriptor = self.capture.stdout.fileno()
        while len(payload) < self.block_bytes and not stop_requested:
            if self.capture.poll() is not None:
                detail = self._process_error(self.capture)
                raise RuntimeError(detail or "audio capture stopped unexpectedly")
            ready, _, _ = select.select([descriptor], [], [], 0.1)
            if not ready:
                continue
            chunk = os.read(descriptor, self.block_bytes - len(payload))
            if not chunk:
                if stop_requested:
                    return None
                raise RuntimeError("audio capture ended unexpectedly")
            payload.extend(chunk)
        return bytes(payload) if len(payload) == self.block_bytes else None

    def process_block(self):
        payload = self._read_block()
        if payload is None:
            return
        if not self.playback or not self.playback.stdin:
            raise RuntimeError("audio playback is unavailable")
        if self.playback.poll() is not None:
            detail = self._process_error(self.playback)
            raise RuntimeError(detail or "audio playback stopped unexpectedly")
        output = self.shifter.process(payload)
        if stop_requested:
            return
        descriptor = self.playback.stdin.fileno()
        written = 0
        while written < len(output):
            try:
                written += os.write(descriptor, output[written:])
            except BrokenPipeError as error:
                if stop_requested:
                    return
                detail = self._process_error(self.playback)
                raise RuntimeError(detail or "audio playback pipe closed") from error

    def stop(self):
        if self.capture:
            self.capture.terminate()
            try:
                self.capture.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                self.capture.kill()
                self.capture.wait()
            self.capture = None
        if self.playback:
            if self.playback.stdin:
                self.playback.stdin.close()
            try:
                self.playback.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                self.playback.terminate()
                try:
                    self.playback.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    self.playback.kill()
                    self.playback.wait()
            self.playback = None
        self.shifter.close()


def request_stop(_signal, _frame):
    global stop_requested
    stop_requested = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--semitones", type=int, default=0)
    parser.add_argument(
        "--engine",
        choices=("rubberband-live",),
        default="rubberband-live",
    )
    arguments = parser.parse_args()
    semitones = clamp_semitones(arguments.semitones)
    lock = acquire_lock()
    if lock is None:
        emit("error", message="Pitch shifter is already running.")
        return 2

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    os.environ["PULSE_PROP_application.name"] = "quickshell-pitch"
    router = Router()
    pipeline = None

    try:
        router.setup()
        pipeline = AudioPipeline(router.target, semitones)
        pipeline.start()
        router.rescan()
        emit("ready", semitones=semitones, engine=arguments.engine)
        next_route = 0.0
        next_control = 0.0
        control_stamp = None

        while not stop_requested:
            now = time.monotonic()
            if now >= next_control:
                next_control = now + CONTROL_INTERVAL
                try:
                    stat = os.stat(CONTROL_PATH)
                    stamp = (stat.st_mtime_ns, stat.st_size)
                except OSError:
                    stamp = None
                if stamp != control_stamp:
                    control_stamp = stamp
                    updated = read_control(semitones)
                    if updated != semitones:
                        semitones = updated
                        pipeline.set_semitones(semitones)
                        emit("transpose", semitones=semitones)

            if now >= next_route:
                next_route = now + ROUTE_INTERVAL
                router.rescan()
            pipeline.process_block()
    except Exception as error:
        emit("error", message=str(error))
        return 1
    finally:
        router.teardown(pipeline)
        lock.close()

    emit("stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
