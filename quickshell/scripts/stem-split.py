#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass

import numpy as np

SINK_NAME = "quickshell_stems"
SINK_DESC = "Stem-Filter"
RATE = 44100
CHANNELS = 2
FRAME_BYTES = CHANNELS * 4
STEMS = ("vocals", "drums", "bass", "other")
CONTROL_POLL_SECONDS = 0.03
ROUTE_POLL_SECONDS = 0.4
GAIN_RAMP_MS = 32
WRITE_CHUNK_MS = 20

_RUNDIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
CONTROL_PATH = os.path.join(_RUNDIR, "qs-stems.json")
TARGET_PATH = os.path.join(_RUNDIR, "qs-stems-target")
LOCK_PATH = os.path.join(_RUNDIR, "qs-stems.lock")


@dataclass(frozen=True)
class Mode:
    model: str
    context_seconds: float
    hop_seconds: float
    crossfade_ms: int
    playback_latency_ms: int
    amp: bool


MODES = {
    "speed": Mode("htdemucs", 1.4, 0.35, 30, 60, True),
    "quality": Mode("htdemucs_ft", 4.0, 1.0, 40, 80, True),
}
DEFAULT_MODE = "speed"

_event_lock = threading.Lock()


def emit(event, **fields):
    with _event_lock:
        print(json.dumps({"event": event, **fields}, separators=(",", ":")), flush=True)


def pactl(*args):
    result = subprocess.run(
        ["pactl", *args], capture_output=True, text=True, timeout=3
    )
    return result.stdout.strip()


def sink_inputs():
    try:
        return json.loads(pactl("-f", "json", "list", "sink-inputs") or "[]")
    except (ValueError, subprocess.SubprocessError):
        return []


def is_ours(item):
    props = item.get("properties", {}) or {}
    return "quickshell-stems" in str(props.get("application.name", "")).lower()


def is_filterable(item):
    if is_ours(item):
        return False
    props = item.get("properties", {}) or {}
    role = str(props.get("media.role", "")).lower()
    return role not in {
        "event", "notification", "phone", "communication", "game",
    }


def real_sinks():
    rows = []
    try:
        lines = pactl("list", "short", "sinks").splitlines()
    except subprocess.SubprocessError:
        return []
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 2 or parts[1] == SINK_NAME:
            continue
        rows.append((0 if "RUNNING" in line.upper() else 1, parts[1]))
    rows.sort()
    return [name for _, name in rows]


def acquire_lock():
    handle = open(LOCK_PATH, "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def default_control(mode=DEFAULT_MODE, generation=0):
    return {
        **{stem: True for stem in STEMS},
        "mode": mode,
        "generation": generation,
    }


def read_control(previous):
    try:
        with open(CONTROL_PATH) as handle:
            value = json.load(handle)
    except (OSError, ValueError, TypeError):
        return previous
    result = {stem: bool(value.get(stem, True)) for stem in STEMS}
    mode = str(value.get("mode", previous["mode"]))
    result["mode"] = mode if mode in MODES else DEFAULT_MODE
    try:
        result["generation"] = int(value.get("generation", previous["generation"]))
    except (TypeError, ValueError):
        result["generation"] = previous["generation"]
    return result


class ControlState:
    def __init__(self, initial):
        self._value = dict(initial)
        self._lock = threading.Lock()

    def update(self, value):
        with self._lock:
            self._value = dict(value)

    def snapshot(self):
        with self._lock:
            return dict(self._value)

    def targets(self, source_order):
        value = self.snapshot()
        return np.asarray(
            [1.0 if value.get(name, True) else 0.0 for name in source_order],
            dtype=np.float32,
        )


class ControlWatcher(threading.Thread):
    def __init__(self, state, stop_event):
        super().__init__(daemon=True)
        self.state = state
        self.stop_event = stop_event
        self._stamp = None

    def run(self):
        while not self.stop_event.is_set():
            try:
                stat = os.stat(CONTROL_PATH)
                stamp = (stat.st_mtime_ns, stat.st_size)
            except OSError:
                stamp = None
            if stamp != self._stamp:
                self._stamp = stamp
                self.state.update(read_control(self.state.snapshot()))
            self.stop_event.wait(CONTROL_POLL_SECONDS)


class Router:
    def __init__(self):
        self.module = ""
        self.target = ""
        self._lock = threading.RLock()

    def _sink_index(self):
        try:
            lines = pactl("list", "short", "sinks").splitlines()
        except subprocess.SubprocessError:
            return "-1"
        for line in lines:
            parts = line.split("\t")
            if len(parts) > 1 and parts[1] == SINK_NAME:
                return parts[0]
        return "-1"

    def _set_target(self, target):
        if not target or target == SINK_NAME:
            return
        self.target = target
        try:
            with open(TARGET_PATH, "w") as handle:
                handle.write(target)
        except OSError:
            pass

    def _choose_target(self):
        candidates = real_sinks()
        try:
            default = pactl("get-default-sink")
        except subprocess.SubprocessError:
            default = ""
        if default in candidates:
            return default
        try:
            with open(TARGET_PATH) as handle:
                remembered = handle.read().strip()
        except OSError:
            remembered = ""
        if remembered in candidates:
            return remembered
        return candidates[0] if candidates else ""

    @staticmethod
    def _move(index, target):
        subprocess.run(
            ["pactl", "move-sink-input", str(index), target],
            capture_output=True,
            timeout=3,
        )

    def setup(self):
        with self._lock:
            self._set_target(self._choose_target())
            if not self.target:
                raise RuntimeError("no real output sink")
            try:
                modules = pactl("list", "short", "modules").splitlines()
            except subprocess.SubprocessError as error:
                raise RuntimeError("cannot inspect audio modules") from error
            for line in modules:
                if "module-null-sink" in line and SINK_NAME in line:
                    subprocess.run(
                        ["pactl", "unload-module", line.split("\t")[0]],
                        capture_output=True,
                        timeout=3,
                    )
            self.module = pactl(
                "load-module",
                "module-null-sink",
                "sink_name=" + SINK_NAME,
                "sink_properties=device.description=%s device.class=filter "
                "node.description=%s" % (SINK_DESC, SINK_DESC),
                "rate=%d" % RATE,
                "channels=%d" % CHANNELS,
            )
            if self._sink_index() == "-1":
                raise RuntimeError("could not create the stem filter sink")
            self.rescan()

    def rescan(self):
        with self._lock:
            candidates = real_sinks()
            try:
                selected = pactl("get-default-sink")
            except subprocess.SubprocessError:
                selected = ""
            if selected in candidates and selected != self.target:
                self._set_target(selected)
            filter_index = self._sink_index()
            for item in sink_inputs():
                index = item.get("index")
                current = str(item.get("sink"))
                if is_ours(item):
                    if self.target and current != self.target:
                        self._move(index, self.target)
                elif is_filterable(item) and current != filter_index:
                    self._move(index, SINK_NAME)

    def teardown(self):
        with self._lock:
            candidates = real_sinks()
            try:
                selected = pactl("get-default-sink")
            except subprocess.SubprocessError:
                selected = ""
            if selected in candidates:
                self._set_target(selected)
            elif self.target not in candidates:
                self._set_target(candidates[0] if candidates else "")
            filter_index = self._sink_index()
            if self.target:
                for item in sink_inputs():
                    if str(item.get("sink")) == filter_index and not is_ours(item):
                        try:
                            self._move(item.get("index"), self.target)
                        except subprocess.SubprocessError:
                            pass
                try:
                    if pactl("get-default-sink") == SINK_NAME:
                        pactl("set-default-sink", self.target)
                except subprocess.SubprocessError:
                    pass
            if self.module:
                try:
                    subprocess.run(
                        ["pactl", "unload-module", self.module],
                        capture_output=True,
                        timeout=3,
                    )
                except subprocess.SubprocessError:
                    pass
            self.module = ""


class RouterWatcher(threading.Thread):
    def __init__(self, router, stop_event):
        super().__init__(daemon=True)
        self.router = router
        self.stop_event = stop_event

    def run(self):
        while not self.stop_event.wait(ROUTE_POLL_SECONDS):
            try:
                self.router.rescan()
            except (OSError, subprocess.SubprocessError):
                pass


class Separator:
    def __init__(self, mode_name):
        import torch
        from demucs.apply import BagOfModels
        from demucs.pretrained import get_model

        if not torch.cuda.is_available():
            raise RuntimeError("CUDA is not available")
        self.torch = torch
        self.device = torch.device("cuda")
        self.mode_name = mode_name
        self.config = MODES[mode_name]
        self.window = int(round(self.config.context_seconds * RATE))
        self.hop = int(round(self.config.hop_seconds * RATE))
        self.overlap = int(round(self.config.crossfade_ms * RATE / 1000))
        self.span = self.hop + self.overlap
        self.crop_start = (self.window - self.span) // 2 + self.hop // 2
        self.crop_end = self.crop_start + self.span
        if self.crop_start < 0 or self.crop_end > self.window:
            raise RuntimeError("invalid stem window profile")

        torch.backends.cudnn.benchmark = True
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.set_float32_matmul_precision("high")

        loaded = get_model(self.config.model)
        self._loaded = loaded
        self.source_order = list(loaded.sources)
        if set(self.source_order) != set(STEMS):
            raise RuntimeError("unexpected model sources: " + ", ".join(self.source_order))
        if isinstance(loaded, BagOfModels):
            models = list(loaded.models)
            weights = loaded.weights
        else:
            models = [loaded]
            weights = [[1.0] * len(self.source_order)]
        self.models = []
        self.weights = []
        for model, model_weights in zip(models, weights):
            if hasattr(model, "use_train_segment"):
                model.use_train_segment = False
            self.models.append(model.to(self.device).float().eval())
            self.weights.append(
                torch.as_tensor(
                    model_weights, dtype=torch.float32, device=self.device
                )[:, None, None]
            )
        totals = np.asarray(weights, dtype=np.float32).sum(axis=0)
        if np.any(totals <= 0):
            raise RuntimeError("invalid model source weights")
        self.weight_totals = torch.as_tensor(
            totals, dtype=torch.float32, device=self.device
        )[:, None, None]

    def separate(self, block):
        torch = self.torch
        tensor = torch.from_numpy(np.ascontiguousarray(block.T)).to(self.device)
        reference = tensor.mean(dim=0)
        mean = reference.mean()
        std = reference.std().clamp_min(1e-5)
        normalized = (tensor - mean) / std
        estimate = torch.zeros(
            (len(self.source_order), CHANNELS, self.window),
            dtype=torch.float32,
            device=self.device,
        )
        with torch.inference_mode():
            for model, weights in zip(self.models, self.weights):
                with torch.autocast(
                    "cuda", dtype=torch.float16, enabled=self.config.amp
                ):
                    prediction = model(normalized[None])[0]
                estimate.add_(prediction.float() * weights)
        estimate.div_(self.weight_totals)
        estimate.mul_(std)
        result = estimate.transpose(1, 2).cpu().numpy()
        if result.shape != (len(self.source_order), self.window, CHANNELS):
            raise RuntimeError("stem model returned an invalid shape")
        if not np.isfinite(result).all():
            raise RuntimeError("stem model returned non-finite audio")
        return result

    def warmup(self):
        self.separate(np.zeros((self.window, CHANNELS), dtype=np.float32))

    def crop(self, stems, mixture):
        return (
            stems[:, self.crop_start:self.crop_end].copy(),
            mixture[self.crop_start:self.crop_end].copy(),
        )


class CenterCrossfader:
    def __init__(self, overlap):
        self.overlap = overlap
        position = (np.arange(overlap, dtype=np.float32) + 1) / (overlap + 1)
        self.fade_in = position[None, :, None]
        self.fade_out = 1.0 - self.fade_in
        self.mix_fade_in = position[:, None]
        self.mix_fade_out = 1.0 - self.mix_fade_in
        self.pending_stems = None
        self.pending_mix = None

    def add(self, stems, mixture):
        if self.pending_stems is None:
            self.pending_stems = stems
            self.pending_mix = mixture
            return None
        overlap = self.overlap
        blended_stems = (
            self.pending_stems[:, -overlap:] * self.fade_out
            + stems[:, :overlap] * self.fade_in
        )
        blended_mix = (
            self.pending_mix[-overlap:] * self.mix_fade_out
            + mixture[:overlap] * self.mix_fade_in
        )
        output_stems = np.concatenate(
            (self.pending_stems[:, :-overlap], blended_stems), axis=1
        )
        output_mix = np.concatenate(
            (self.pending_mix[:-overlap], blended_mix), axis=0
        )
        self.pending_stems = stems[:, overlap:].copy()
        self.pending_mix = mixture[overlap:].copy()
        return output_stems, output_mix


class PCMReader(threading.Thread):
    def __init__(self, process, max_frames, stop_event):
        super().__init__(daemon=True)
        self.process = process
        self.max_bytes = max_frames * FRAME_BYTES
        self.stop_event = stop_event
        self.buffer = bytearray()
        self.condition = threading.Condition()
        self.alive = True
        self.error = ""

    def run(self):
        try:
            while not self.stop_event.is_set():
                chunk = self.process.stdout.read(32768)
                if not chunk:
                    if not self.stop_event.is_set():
                        self.error = "audio capture stopped"
                    break
                with self.condition:
                    if len(self.buffer) + len(chunk) > self.max_bytes:
                        self.error = "audio capture backlog exceeded"
                        self.stop_event.set()
                        break
                    self.buffer.extend(chunk)
                    self.condition.notify_all()
        except (OSError, ValueError) as error:
            if not self.stop_event.is_set():
                self.error = "audio capture failed: %s" % error
        finally:
            if self.error:
                self.stop_event.set()
            with self.condition:
                self.alive = False
                self.condition.notify_all()

    def read_frames(self, frames):
        size = frames * FRAME_BYTES
        with self.condition:
            while (
                len(self.buffer) < size
                and self.alive
                and not self.stop_event.is_set()
            ):
                self.condition.wait(timeout=0.5)
            if len(self.buffer) < size:
                if self.error:
                    raise RuntimeError(self.error)
                return None
            data = bytes(self.buffer[:size])
            del self.buffer[:size]
        return np.frombuffer(data, dtype="<f4").reshape(frames, CHANNELS).copy()

    def stop(self):
        with self.condition:
            self.alive = False
            self.condition.notify_all()


class SmoothMixer:
    def __init__(self, control, source_order):
        self.control = control
        self.source_order = source_order
        self.current = control.targets(source_order)
        self.target = self.current.copy()
        self.remaining = 0
        self.ramp_frames = max(1, int(RATE * GAIN_RAMP_MS / 1000))
        self.limiter_gain = 1.0

    def _gain_curve(self, frames):
        target = self.control.targets(self.source_order)
        if not np.array_equal(target, self.target):
            self.target = target
            self.remaining = self.ramp_frames
        curve = np.empty((frames, len(self.current)), dtype=np.float32)
        offset = 0
        while offset < frames:
            if self.remaining <= 0:
                self.current = self.target.copy()
                curve[offset:] = self.current
                break
            count = min(frames - offset, self.remaining)
            fraction = (
                np.arange(1, count + 1, dtype=np.float32) / self.remaining
            )[:, None]
            section = self.current + (self.target - self.current) * fraction
            curve[offset:offset + count] = section
            self.current = section[-1].copy()
            self.remaining -= count
            offset += count
        return curve

    def _limit(self, audio):
        peak = float(np.max(np.abs(audio), initial=0.0))
        target = min(1.0, 0.99 / peak) if peak > 0 else 1.0
        start = self.limiter_gain
        if target < start:
            end = target
        else:
            release = 1.0 - np.exp(-len(audio) / (RATE * 0.5))
            end = start + (target - start) * release
        gain = np.linspace(start, end, len(audio), dtype=np.float32)[:, None]
        self.limiter_gain = end
        limited = audio * gain
        return np.clip(limited, -1.0, 1.0)

    def mix(self, stems, mixture):
        gains = self._gain_curve(len(mixture))
        if np.all(gains == 1.0):
            if self.limiter_gain >= 0.9999:
                self.limiter_gain = 1.0
                return mixture
            start = self.limiter_gain
            end = min(1.0, start + len(mixture) / (RATE * 0.08))
            self.limiter_gain = end
            return mixture * np.linspace(
                start, end, len(mixture), dtype=np.float32
            )[:, None]
        if np.all(gains == 0.0):
            self.limiter_gain = 1.0
            return np.zeros_like(mixture)
        weighted = np.sum(stems * gains.T[:, :, None], axis=0)
        residual = mixture - np.sum(stems, axis=0)
        weighted += residual * (np.sum(gains, axis=1)[:, None] / len(stems))
        return self._limit(weighted)


class PlaybackWriter(threading.Thread):
    def __init__(self, process, control, source_order, stop_event, ready_callback):
        super().__init__(daemon=True)
        self.process = process
        self.stop_event = stop_event
        self.ready_callback = ready_callback
        self.blocks = queue.Queue(maxsize=4)
        self.mixer = SmoothMixer(control, source_order)
        self.chunk_frames = max(1, int(RATE * WRITE_CHUNK_MS / 1000))
        self.error = ""
        self.ready = False

    def push(self, stems, mixture):
        while not self.stop_event.is_set():
            if self.error:
                raise RuntimeError(self.error)
            try:
                self.blocks.put((stems, mixture), timeout=0.25)
                return
            except queue.Full:
                continue
        raise RuntimeError("playback stopped")

    @staticmethod
    def _write_all(handle, data):
        view = memoryview(data)
        while view:
            written = handle.write(view)
            if not written:
                raise BrokenPipeError("audio playback pipe closed")
            view = view[written:]

    def run(self):
        try:
            while not self.stop_event.is_set():
                try:
                    item = self.blocks.get(timeout=0.2)
                except queue.Empty:
                    continue
                if item is None:
                    break
                stems, mixture = item
                for offset in range(0, len(mixture), self.chunk_frames):
                    if self.stop_event.is_set():
                        return
                    end = min(len(mixture), offset + self.chunk_frames)
                    audio = self.mixer.mix(
                        stems[:, offset:end], mixture[offset:end]
                    )
                    self._write_all(
                        self.process.stdin,
                        np.ascontiguousarray(audio, dtype="<f4").tobytes(),
                    )
                    self.process.stdin.flush()
                    if not self.ready:
                        self.ready = True
                        self.ready_callback()
        except (BrokenPipeError, OSError, ValueError, RuntimeError) as error:
            if not self.stop_event.is_set():
                self.error = "audio playback failed: %s" % error
                self.stop_event.set()

    def stop(self):
        try:
            self.blocks.put_nowait(None)
        except queue.Full:
            pass


def terminate(process):
    if process and process.poll() is None:
        try:
            process.terminate()
        except OSError:
            pass


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=tuple(MODES))
    parser.add_argument("--generation", type=int)
    return parser.parse_args()


def main():
    args = parse_args()
    initial = read_control(
        default_control(
            args.mode or DEFAULT_MODE,
            args.generation if args.generation is not None else 0,
        )
    )
    mode_name = args.mode or initial["mode"]
    generation = (
        args.generation if args.generation is not None else initial["generation"]
    )
    initial["mode"] = mode_name
    initial["generation"] = generation

    lock = acquire_lock()
    if lock is None:
        emit(
            "error",
            mode=mode_name,
            generation=generation,
            message="another Stem Filter instance is already running",
        )
        return 1

    stop_event = threading.Event()
    external_stop = threading.Event()
    router = Router()
    processes = []
    threads = []

    def request_stop(*_):
        external_stop.set()
        stop_event.set()
        for process in processes:
            terminate(process)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, request_stop)

    try:
        controls = ControlState(initial)
        control_watcher = ControlWatcher(controls, stop_event)
        control_watcher.start()
        threads.append(control_watcher)

        emit("loading", mode=mode_name, generation=generation)
        separator = Separator(mode_name)
        separator.warmup()
        if stop_event.is_set():
            return 0
        state = controls.snapshot()
        if state["mode"] != mode_name or state["generation"] != generation:
            return 0

        router.setup()
        route_watcher = RouterWatcher(router, stop_event)
        route_watcher.start()
        threads.append(route_watcher)

        capture = subprocess.Popen(
            [
                "parec",
                "--device=" + SINK_NAME + ".monitor",
                "--rate=%d" % RATE,
                "--channels=%d" % CHANNELS,
                "--format=float32le",
                "--latency-msec=20",
                "--client-name=quickshell-stems",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
        playback = subprocess.Popen(
            [
                "pacat",
                "--device=" + router.target,
                "--rate=%d" % RATE,
                "--channels=%d" % CHANNELS,
                "--format=float32le",
                "--latency-msec=%d" % separator.config.playback_latency_ms,
                "--client-name=quickshell-stems",
            ],
            stdin=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
        processes.extend((capture, playback))

        reader = PCMReader(
            capture, separator.window + 4 * separator.hop, stop_event
        )

        def ready():
            state = controls.snapshot()
            if (
                state["mode"] == mode_name
                and state["generation"] == generation
                and not stop_event.is_set()
            ):
                emit("ready", mode=mode_name, generation=generation)

        writer = PlaybackWriter(
            playback, controls, separator.source_order, stop_event, ready
        )
        reader.start()
        writer.start()
        threads.extend((reader, writer))

        block = reader.read_frames(separator.window)
        if block is None:
            return 0
        stitcher = CenterCrossfader(separator.overlap)

        while not stop_event.is_set():
            state = controls.snapshot()
            if (
                state["mode"] != mode_name
                or state["generation"] != generation
            ):
                emit(
                    "restart_required",
                    mode=mode_name,
                    generation=generation,
                )
                break

            stems = separator.separate(block)
            output = stitcher.add(*separator.crop(stems, block))
            if output is not None:
                writer.push(*output)
            incoming = reader.read_frames(separator.hop)
            if incoming is None:
                break
            block[:-separator.hop] = block[separator.hop:]
            block[-separator.hop:] = incoming

        if writer.error:
            raise RuntimeError(writer.error)
        if reader.error:
            raise RuntimeError(reader.error)
        return 0
    except Exception as error:
        if not external_stop.is_set():
            message = str(error) or error.__class__.__name__
            emit(
                "error",
                mode=mode_name,
                generation=generation,
                message=message,
            )
            print("stem-split: " + message, file=sys.stderr)
            return 1
        return 0
    finally:
        stop_event.set()
        for thread in threads:
            stop = getattr(thread, "stop", None)
            if stop:
                stop()
        for process in processes:
            terminate(process)
        for thread in threads:
            if thread is not threading.current_thread():
                thread.join(timeout=2)
        router.teardown()


if __name__ == "__main__":
    sys.exit(main())
