#!/usr/bin/env python3

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse


WIDTH = 1280
HEIGHT = 720
FPS = 30
MASK_INTERVAL = 3
PORTRAIT_BLUR_SIGMA = 2.0
CHROMA_KEY_COLOR = "#00FF00"
CHROMA_MATTE_LOW = 0.20
CHROMA_MATTE_HIGH = 0.55
VIRTUAL_DEVICE = os.environ.get("QS_CAMERA_OUTPUT", "/dev/video10")
MODEL_NAME = "SINet_Softmax.onnx"
MEAN = (102.890434, 111.25247, 126.91212)
STD = (62.93292, 62.82138, 66.355705)


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def state_home():
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))


def data_home():
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))


CONFIG_PATH = config_home() / "quickshell" / "camera-effects.json"
RUNTIME_PATH = state_home() / "quickshell" / "camera-effects-runtime.json"
MODEL_PATH = data_home() / "quickshell" / "camera-effects" / MODEL_NAME


def default_config():
    return {
        "portraitEnabled": False,
        "backgroundMode": "none",
        "backgroundValue": "",
        "backgroundImage": "",
    }


def read_json(path, fallback):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else fallback.copy()
    except (OSError, ValueError):
        return fallback.copy()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, separators=(",", ":")))
    os.replace(temporary, path)


def update_config(kind, value, selected=""):
    config = read_json(CONFIG_PATH, default_config())
    if kind == "portrait":
        if value not in ("on", "off"):
            raise ValueError("portrait expects on or off")
        config["portraitEnabled"] = value == "on"
    elif kind == "background":
        if value not in ("none", "color", "image", "chroma"):
            raise ValueError("invalid background mode")
        saved_image = config.get("backgroundImage", "")
        if not saved_image and config.get("backgroundMode") == "image":
            saved_image = config.get("backgroundValue", "")
        if value == "image" and not selected:
            selected = saved_image
        if value == "color" and not selected.startswith("#"):
            raise ValueError("background color must be hexadecimal")
        if value == "image" and not selected:
            raise ValueError("background image is required")
        if value == "image" and not Path(local_path(selected)).expanduser().is_file():
            raise ValueError("background image is unavailable")
        config["backgroundMode"] = value
        config["backgroundValue"] = selected
        if value == "image":
            config["backgroundImage"] = selected
        elif saved_image:
            config["backgroundImage"] = saved_image
    else:
        raise ValueError("unknown camera effect")
    write_json(CONFIG_PATH, config)
    subprocess.run(
        ["systemctl", "--user", "start", "quickshell-camera-effects.service"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return config


def process_uses_device(pid, device):
    try:
        if int(pid) == os.getpid():
            return False
        cmdline = (Path("/proc") / pid / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").lower()
        if "camera-effects.py" in cmdline or any(name in cmdline for name in ("pipewire", "wireplumber", "xdg-desktop-portal")):
            return False
        for fd in (Path("/proc") / pid / "fd").iterdir():
            try:
                if os.path.realpath(fd) == device:
                    return True
            except OSError:
                continue
    except (OSError, ValueError):
        return False
    return False


def consumers(device):
    found = []
    for process in Path("/proc").iterdir():
        if process.name.isdigit() and process_uses_device(process.name, device):
            found.append(int(process.name))
    return found


def pipewire_consumers():
    try:
        graph = json.loads(subprocess.run(
            ["pw-dump"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    clients = {}
    nodes = {}
    links = []
    for item in graph:
        info = item.get("info", {})
        if item.get("type") == "PipeWire:Interface:Client":
            clients[item.get("id")] = info.get("props", {})
        elif item.get("type") == "PipeWire:Interface:Link" and str(info.get("state", "")).lower() == "active":
            links.append((info.get("output-node-id"), info.get("input-node-id")))
        elif item.get("type") == "PipeWire:Interface:Node":
            props = dict(clients.get(info.get("props", {}).get("client.id"), {}))
            props.update(info.get("props", {}))
            nodes[item.get("id")] = props
    sources = {
        node_id for node_id, props in nodes.items()
        if props.get("media.class") == "Video/Source"
        and "qs camera" in " ".join(str(props.get(key, "")).lower() for key in ("node.name", "node.description", "device.description", "node.nick"))
    }
    found = []
    for output_id, input_id in links:
        props = nodes.get(input_id, {})
        if output_id not in sources or props.get("media.class") != "Stream/Input/Video":
            continue
        try:
            found.append(int(props.get("application.process.id", -1)))
        except (TypeError, ValueError):
            found.append(-1)
    return found


def physical_camera():
    preferred = os.environ.get("QS_CAMERA_INPUT", "")
    if preferred and Path(preferred).exists():
        return preferred
    for device in sorted(Path("/dev").glob("video*")):
        if str(device) == VIRTUAL_DEVICE:
            continue
        try:
            name = (Path("/sys/class/video4linux") / device.name / "name").read_text().strip().lower()
        except OSError:
            name = ""
        if "metadata" in name or "infrared" in name or name.endswith(" ir"):
            continue
        result = subprocess.run(
            ["v4l2-ctl", "--device", str(device), "--list-formats-ext"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and ("'MJPG'" in result.stdout or "'YUYV'" in result.stdout):
            return str(device)
    return "/dev/video0"


def local_path(value):
    if value.startswith("file://"):
        return unquote(urlparse(value).path)
    return value


def image_decode_reduction(width, height):
    coverage = min(float(width) / WIDTH, float(height) / HEIGHT)
    if coverage >= 8:
        return 8
    if coverage >= 4:
        return 4
    if coverage >= 2:
        return 2
    return 1


class CameraEffects:
    def __init__(self):
        os.environ.setdefault("OPENCV_OPENCL_DEVICE", "Intel:GPU:")
        import cv2
        import numpy as np
        try:
            from PIL import Image
        except ImportError:
            Image = None

        self.cv2 = cv2
        self.np = np
        self.Image = Image
        cv2.setNumThreads(2)
        cv2.ocl.setUseOpenCL(True)
        self.input_device = physical_camera()
        self.capture = None
        self.writer = None
        self.net = None
        self.compiled_model = None
        self.network_output = None
        self.backend = "cpu"
        self.mask = None
        self.chroma_alpha = None
        self.frame_index = 0
        self.config = default_config()
        self.config_mtime = 0
        self.background_key = ""
        self.background = None
        self.background_failed = False
        self.error = ""
        self.active_since = 0.0
        self.consumer_pids = []
        self.last_consumer_check = 0.0
        self.last_runtime_write = 0.0
        self.running = True

    def load_config(self):
        try:
            mtime = CONFIG_PATH.stat().st_mtime_ns
        except OSError:
            mtime = 0
        if mtime == self.config_mtime:
            return
        self.config_mtime = mtime
        self.config = read_json(CONFIG_PATH, default_config())
        key = self.config.get("backgroundValue", "")
        if key != self.background_key:
            self.background_key = key
            self.background = None
            self.background_failed = False

    def load_network(self):
        if self.net is not None or self.compiled_model is not None:
            return
        if not MODEL_PATH.exists():
            raise RuntimeError(f"Missing segmentation model: {MODEL_PATH}")
        try:
            from openvino import Core

            core = Core()
            devices = list(core.available_devices)
            device = "NPU" if "NPU" in devices else ""
            if not device:
                for candidate in devices:
                    name = str(core.get_property(candidate, "FULL_DEVICE_NAME"))
                    if candidate.startswith("GPU") and "Intel" in name:
                        device = candidate
                        break
            if not device:
                device = "CPU"
            options = {
                "PERFORMANCE_HINT": "LATENCY",
                "CACHE_DIR": str(data_home() / "quickshell/camera-effects/cache"),
            }
            if device.startswith("GPU") or device == "NPU":
                options["INFERENCE_PRECISION_HINT"] = "f16"
            model = core.read_model(str(MODEL_PATH))
            self.compiled_model = core.compile_model(model, device, options)
            self.network_output = self.compiled_model.output(0)
            self.backend = "intel-npu" if device == "NPU" else "intel-igpu" if device.startswith("GPU") else "cpu"
            return
        except (ImportError, RuntimeError):
            self.compiled_model = None
        self.net = self.cv2.dnn.readNetFromONNX(str(MODEL_PATH))
        self.backend = "cpu"
        self.net.setPreferableTarget(self.cv2.dnn.DNN_TARGET_CPU)

    def open_writer(self):
        if self.writer is not None and self.writer.isOpened():
            return True
        pipeline = (
            f"appsrc is-live=true format=time do-timestamp=true ! "
            f"video/x-raw,format=BGR,width={WIDTH},height={HEIGHT},framerate={FPS}/1 ! "
            "queue leaky=downstream max-size-buffers=1 ! videoconvert ! "
            f"video/x-raw,format=YUY2 ! v4l2sink device={VIRTUAL_DEVICE} sync=false"
        )
        self.writer = self.cv2.VideoWriter(pipeline, self.cv2.CAP_GSTREAMER, 0, FPS, (WIDTH, HEIGHT))
        if not self.writer.isOpened():
            self.writer = None
            raise RuntimeError(f"Unable to open {VIRTUAL_DEVICE}")
        self.writer.write(self.np.zeros((HEIGHT, WIDTH, 3), dtype=self.np.uint8))
        return True

    def open_capture(self):
        if self.capture is not None and self.capture.isOpened():
            return True
        pipeline = (
            f"v4l2src device={self.input_device} io-mode=2 ! "
            f"image/jpeg,width={WIDTH},height={HEIGHT},framerate={FPS}/1 ! "
            "jpegdec ! videoconvert ! video/x-raw,format=BGR ! "
            "appsink drop=true max-buffers=1 sync=false"
        )
        self.capture = self.cv2.VideoCapture(pipeline, self.cv2.CAP_GSTREAMER)
        if not self.capture.isOpened():
            self.capture = self.cv2.VideoCapture(self.input_device, self.cv2.CAP_V4L2)
            self.capture.set(self.cv2.CAP_PROP_FOURCC, self.cv2.VideoWriter_fourcc(*"MJPG"))
            self.capture.set(self.cv2.CAP_PROP_FRAME_WIDTH, WIDTH)
            self.capture.set(self.cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)
            self.capture.set(self.cv2.CAP_PROP_FPS, FPS)
            self.capture.set(self.cv2.CAP_PROP_BUFFERSIZE, 1)
        if not self.capture.isOpened():
            self.capture = None
            raise RuntimeError(f"Unable to open {self.input_device}")
        self.frame_index = 0
        self.mask = None
        self.chroma_alpha = None
        return True

    def close_capture(self):
        if self.capture is not None:
            self.capture.release()
        self.capture = None
        self.mask = None

    def infer_mask(self, frame):
        self.load_network()
        small = self.cv2.resize(frame, (320, 320), interpolation=self.cv2.INTER_AREA).astype(self.np.float32)
        small -= self.np.asarray(MEAN, dtype=self.np.float32)
        small *= self.np.asarray((1.0 / STD[0], 1.0 / STD[1], 1.0 / STD[2]), dtype=self.np.float32)
        blob = self.cv2.dnn.blobFromImage(small, 1.0 / 255.0, (320, 320), swapRB=False, crop=False)
        if self.compiled_model is not None:
            score = self.compiled_model([blob])[self.network_output]
        else:
            self.net.setInput(blob)
            score = self.net.forward()
        if score.ndim == 4 and score.shape[1] > 1:
            foreground = score[0, 1].astype(self.np.float32)
        elif score.ndim == 4 and score.shape[-1] > 1:
            foreground = score[0, :, :, 1].astype(self.np.float32)
        else:
            foreground = score.reshape(score.shape[-2], score.shape[-1]).astype(self.np.float32)
        foreground = self.cv2.resize(foreground, (WIDTH, HEIGHT), interpolation=self.cv2.INTER_LINEAR)
        foreground = self.cv2.GaussianBlur(foreground, (0, 0), 0.85)
        foreground = self.np.clip(foreground, 0.0, 1.0)
        if self.mask is not None and self.mask.shape == foreground.shape:
            foreground = foreground * 0.72 + self.mask * 0.28
        self.mask = foreground
        self.chroma_alpha = None
        return self.mask

    def composition_alpha(self, mode):
        alpha = self.mask.astype(self.np.float32)
        if mode == "chroma":
            if self.chroma_alpha is not None and self.chroma_alpha.shape[:2] == alpha.shape:
                return self.chroma_alpha
            alpha = self.np.clip(
                (alpha - CHROMA_MATTE_LOW) / (CHROMA_MATTE_HIGH - CHROMA_MATTE_LOW),
                0.0,
                1.0,
            )
            alpha = alpha * alpha * (3.0 - 2.0 * alpha)
            self.chroma_alpha = alpha[:, :, self.np.newaxis]
            return self.chroma_alpha
        return alpha[:, :, self.np.newaxis]

    def background_frame(self, frame, mode, value):
        if mode in ("color", "chroma"):
            color = (CHROMA_KEY_COLOR if mode == "chroma" else value).lstrip("#")
            if len(color) != 6:
                color = (CHROMA_KEY_COLOR if mode == "chroma" else "5AC8FA").lstrip("#")
            rgb = tuple(int(color[index:index + 2], 16) for index in (0, 2, 4))
            return self.np.full_like(frame, (rgb[2], rgb[1], rgb[0]))
        if mode == "image":
            if self.background_failed:
                return frame
            path = local_path(value)
            if self.background is None:
                try:
                    reduction = 1
                    if self.Image is not None:
                        with self.Image.open(path) as probe:
                            reduction = image_decode_reduction(*probe.size)
                    read_flag = {
                        2: self.cv2.IMREAD_REDUCED_COLOR_2,
                        4: self.cv2.IMREAD_REDUCED_COLOR_4,
                        8: self.cv2.IMREAD_REDUCED_COLOR_8,
                    }.get(reduction, self.cv2.IMREAD_COLOR)
                    image = self.cv2.imread(path, read_flag)
                    if image is None or image.shape[0] < 1 or image.shape[1] < 1:
                        raise ValueError("Unable to load background image")
                    source_height, source_width = image.shape[:2]
                    target_ratio = WIDTH / HEIGHT
                    source_ratio = source_width / source_height
                    if source_ratio > target_ratio:
                        crop_width = max(1, round(source_height * target_ratio))
                        start = max(0, (source_width - crop_width) // 2)
                        image = image[:, start:start + crop_width]
                    else:
                        crop_height = max(1, round(source_width / target_ratio))
                        start = max(0, (source_height - crop_height) // 2)
                        image = image[start:start + crop_height, :]
                    interpolation = (
                        self.cv2.INTER_AREA
                        if image.shape[1] > WIDTH or image.shape[0] > HEIGHT
                        else self.cv2.INTER_LINEAR
                    )
                    self.background = self.cv2.resize(image, (WIDTH, HEIGHT), interpolation=interpolation)
                except Exception:
                    self.background_failed = True
                    return frame
            return self.background
        reduced = self.cv2.resize(frame, (320, 180), interpolation=self.cv2.INTER_AREA)
        reduced = self.cv2.GaussianBlur(reduced, (0, 0), PORTRAIT_BLUR_SIGMA)
        return self.cv2.resize(reduced, (WIDTH, HEIGHT), interpolation=self.cv2.INTER_LINEAR)

    def process(self, frame):
        portrait = bool(self.config.get("portraitEnabled", False))
        mode = self.config.get("backgroundMode", "none")
        if not portrait and mode == "none":
            return frame
        if self.frame_index % MASK_INTERVAL == 0 or self.mask is None:
            self.infer_mask(frame)
        output = frame
        if portrait or mode != "none":
            background = self.background_frame(frame, mode, self.config.get("backgroundValue", ""))
            alpha = self.composition_alpha(mode)
            blended = frame.astype(self.np.float32) * alpha + background.astype(self.np.float32) * (1.0 - alpha)
            output = self.np.clip(blended, 0, 255).astype(self.np.uint8)
        return output

    def write_runtime(self, active, consumer_pids):
        now = time.monotonic()
        if now - self.last_runtime_write < 1.0:
            return
        self.last_runtime_write = now
        write_json(RUNTIME_PATH, {
            "ok": not self.error,
            "active": active,
            "backend": self.backend,
            "inputDevice": self.input_device,
            "outputDevice": VIRTUAL_DEVICE,
            "consumers": consumer_pids,
            "error": self.error,
        })

    def current_consumers(self):
        now = time.monotonic()
        if now - self.last_consumer_check < 0.75:
            return self.consumer_pids
        self.last_consumer_check = now
        self.consumer_pids = consumers(VIRTUAL_DEVICE)
        if not self.consumer_pids:
            self.consumer_pids = pipewire_consumers()
        return self.consumer_pids

    def run(self):
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, "running", False))
        signal.signal(signal.SIGINT, lambda *_: setattr(self, "running", False))
        self.open_writer()
        last_idle_frame = 0.0
        while self.running:
            self.load_config()
            consumer_pids = self.current_consumers()
            now = time.monotonic()
            if consumer_pids:
                self.active_since = now
            active = bool(consumer_pids) or now - self.active_since < 2.0
            if not active:
                self.close_capture()
                if now - last_idle_frame >= 1.0:
                    self.writer.write(self.np.zeros((HEIGHT, WIDTH, 3), dtype=self.np.uint8))
                    last_idle_frame = now
                self.error = ""
                self.write_runtime(False, consumer_pids)
                time.sleep(0.35)
                continue
            try:
                self.open_capture()
                ok, frame = self.capture.read()
                if not ok or frame is None:
                    raise RuntimeError("Camera frame unavailable")
                if frame.shape[1] != WIDTH or frame.shape[0] != HEIGHT:
                    frame = self.cv2.resize(frame, (WIDTH, HEIGHT), interpolation=self.cv2.INTER_LINEAR)
                self.writer.write(self.process(frame))
                self.frame_index += 1
                self.error = ""
            except Exception as exc:
                self.error = str(exc)
                self.close_capture()
                self.writer.write(self.np.zeros((HEIGHT, WIDTH, 3), dtype=self.np.uint8))
                time.sleep(0.5)
            self.write_runtime(True, consumer_pids)
        self.close_capture()
        if self.writer is not None:
            self.writer.release()


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "daemon":
        CameraEffects().run()
        return
    if command == "status":
        print(json.dumps({
            "config": read_json(CONFIG_PATH, default_config()),
            "runtime": read_json(RUNTIME_PATH, {}),
            "modelAvailable": MODEL_PATH.exists(),
            "deviceAvailable": Path(VIRTUAL_DEVICE).exists(),
        }, separators=(",", ":")))
        return
    if command == "portrait":
        result = update_config("portrait", sys.argv[2])
    elif command == "background":
        result = update_config("background", sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    else:
        raise ValueError("unknown command")
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")))
        raise SystemExit(1)
