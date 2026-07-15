#!/usr/bin/env python3

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


IGNORED_APPS = {
    "pipewire",
    "quickshell",
    "v4l2-ctl",
    "wireplumber",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
}
VOICE_MARKERS = ("noise", "cancel", "isolation", "rnnoise", "echo", "easyeffects")


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    path = Path(base) / "quickshell"
    path.mkdir(parents=True, exist_ok=True)
    return path / "privacy-controls.json"


def load_state():
    try:
        value = json.loads(state_path().read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(value):
    path = state_path()
    path.write_text(json.dumps(value, separators=(",", ":")))
    path.chmod(0o600)


def run(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()


def pipewire_graph():
    graph = json.loads(run(["pw-dump"]))
    clients = {}
    for item in graph:
        if item.get("type") == "PipeWire:Interface:Client":
            clients[item.get("id")] = item.get("info", {}).get("props", {})

    nodes = []
    links = []
    for item in graph:
        if item.get("type") == "PipeWire:Interface:Link":
            info = item.get("info", {})
            if str(info.get("state", "")).lower() == "active":
                links.append({"output": info.get("output-node-id"), "input": info.get("input-node-id")})
            continue
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        info = item.get("info", {})
        props = dict(clients.get(info.get("props", {}).get("client.id"), {}))
        props.update(info.get("props", {}))
        nodes.append({"id": item.get("id"), "state": str(info.get("state", "")).lower(), "props": props})
    return nodes, links


def app_info(node):
    props = node["props"]
    name = str(props.get("application.name") or props.get("application.process.binary") or "Application")
    app_id = str(props.get("application.id") or props.get("application.process.binary") or name).lower()
    binary = str(props.get("application.process.binary") or "").lower()
    fingerprint = " ".join((name.lower(), app_id, binary))
    if name.lower() in {"qs", "quickshell"} or app_id in {"qs", "quickshell"} or binary in {"qs", "quickshell"}:
        return None
    if any(ignored in fingerprint for ignored in IGNORED_APPS):
        return None
    return {"name": name, "id": app_id, "binary": binary}


def active_apps(nodes, media_class):
    apps = []
    seen = set()
    for node in nodes:
        if node["state"] != "running" or node["props"].get("media.class") != media_class:
            continue
        app = app_info(node)
        if not app:
            continue
        key = (app["name"].lower(), app["id"])
        if key not in seen:
            seen.add(key)
            apps.append(app)
    return apps


def linked_apps(nodes, links, source_ids, media_class):
    input_ids = {link["input"] for link in links if link["output"] in source_ids}
    apps = []
    seen = set()
    for node in nodes:
        if node["id"] not in input_ids or node["props"].get("media.class") != media_class:
            continue
        app = app_info(node)
        if not app:
            continue
        key = (app["name"].lower(), app["id"])
        if key not in seen:
            seen.add(key)
            apps.append(app)
    return apps


def process_app(pid):
    try:
        comm = (Path("/proc") / str(pid) / "comm").read_text().strip()
        cmdline = (Path("/proc") / str(pid) / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return None
    fingerprint = f"{comm} {cmdline}".lower()
    if comm.lower() in {"qs", "quickshell"} or any(ignored in fingerprint for ignored in IGNORED_APPS):
        return None
    aliases = {
        "chrome": ("Google Chrome", "google-chrome"),
        "chromium": ("Chromium", "chromium"),
        "firefox": ("Firefox", "firefox"),
        "obs": ("OBS Studio", "com.obsproject.Studio"),
        "zoom": ("Zoom", "Zoom"),
    }
    lower_comm = comm.lower()
    for marker, (name, app_id) in aliases.items():
        if marker in lower_comm or marker in fingerprint:
            return {"name": name, "id": app_id, "binary": lower_comm}
    return {"name": comm, "id": lower_comm, "binary": lower_comm}


def direct_device_apps(device_test):
    apps = []
    seen = set()
    uid = os.getuid()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != uid:
                continue
            fds = list((proc / "fd").iterdir())
        except OSError:
            continue
        targets = []
        for fd in fds:
            try:
                targets.append(os.readlink(fd))
            except OSError:
                continue
        if not any(device_test(target) for target in targets):
            continue
        app = process_app(proc.name)
        if not app:
            continue
        key = (app["name"].lower(), app["id"])
        if key not in seen:
            seen.add(key)
            apps.append(app)
    return apps


def merge_apps(*groups):
    merged = []
    seen = set()
    for group in groups:
        for app in group:
            key = (app["name"].lower(), app["id"])
            if key not in seen:
                seen.add(key)
                merged.append(app)
    return merged


def source_nodes(nodes, media_class):
    return [node for node in nodes if node["props"].get("media.class") == media_class]


def source_name(node):
    props = node["props"]
    return str(props.get("node.description") or props.get("device.description") or props.get("node.nick") or props.get("node.name") or "")


def is_voice_source(node):
    props = node["props"]
    text = " ".join(str(props.get(key, "")).lower() for key in ("node.name", "node.description", "device.description", "node.nick"))
    return any(marker in text for marker in VOICE_MARKERS)


def is_monitor_source(node):
    props = node["props"]
    text = " ".join(str(props.get(key, "")).lower() for key in ("node.name", "node.description", "device.description"))
    return props.get("device.class") == "monitor" or ".monitor" in text or "monitor of" in text


def is_camera_source(node):
    props = node["props"]
    return props.get("media.role") == "Camera" or props.get("device.api") == "v4l2" or bool(props.get("api.v4l2.path"))


def is_virtual_camera(node):
    props = node["props"]
    text = " ".join(str(props.get(key, "")).lower() for key in ("node.name", "node.description", "node.nick", "api.v4l2.cap.card"))
    return any(marker in text for marker in ("virtual camera", "quickshell camera", "qs camera", "v4l2loopback"))


def pulse_source_mutes():
    try:
        sources = json.loads(run(["pactl", "-f", "json", "list", "sources"]))
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}
    return {str(source.get("name", "")): bool(source.get("mute", False)) for source in sources}


def microphone_is_muted(active_microphones, source_mutes):
    active_names = [str(node["props"].get("node.name", "")) for node in active_microphones]
    relevant = [source_mutes[name] for name in active_names if name in source_mutes]
    if not relevant:
        relevant = [muted for name, muted in source_mutes.items() if ".monitor" not in name]
    return bool(relevant) and all(relevant)


def backend_path():
    configured = os.environ.get("QUICKSHELL_CAMERA_EFFECTS_BACKEND", "")
    if configured and os.access(configured, os.X_OK):
        return configured
    local = Path(__file__).with_name("camera-effects.py")
    if os.access(local, os.X_OK):
        return str(local)
    return shutil.which("quickshell-camera-effects") or ""


def camera_model_path():
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return Path(base) / "quickshell/camera-effects/SINet_Softmax.onnx"


def qs_camera_device(device_path=None, sys_class=None):
    device = Path(device_path or os.environ.get("QS_CAMERA_OUTPUT", "/dev/video10"))
    sys_root = Path(sys_class or "/sys/class/video4linux")
    if not device.exists():
        return {}
    try:
        name = (sys_root / device.name / "name").read_text().strip()
    except OSError:
        return {}
    if name.lower() != "qs camera":
        return {}
    return {"path": str(device), "name": name}


def status():
    state = load_state()
    try:
        nodes, links = pipewire_graph()
        error = ""
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        nodes = []
        links = []
        error = str(exc)

    cameras = [node for node in source_nodes(nodes, "Video/Source") if is_camera_source(node)]
    virtual_cameras = [node for node in cameras if is_virtual_camera(node)]
    qs_cameras = [node for node in virtual_cameras if "qs camera" in source_name(node).lower()]
    physical_cameras = [node for node in cameras if not is_virtual_camera(node)]
    microphones = [node for node in source_nodes(nodes, "Audio/Source") if not is_monitor_source(node)]
    active_cameras = [node for node in physical_cameras if node["state"] == "running"]
    active_virtual_cameras = [node for node in qs_cameras if node["state"] == "running"]
    active_microphones = [node for node in microphones if node["state"] == "running"]
    voice_sources = [node for node in microphones if is_voice_source(node)]
    physical_sources = [node for node in microphones if not is_voice_source(node)]
    effect_backend = backend_path()
    qs_device = qs_camera_device()
    source_mutes = pulse_source_mutes()
    physical_camera_paths = {
        str(node["props"].get("api.v4l2.path", ""))
        for node in physical_cameras
        if node["props"].get("api.v4l2.path")
    }
    virtual_camera_paths = {
        str(node["props"].get("api.v4l2.path", ""))
        for node in qs_cameras
        if node["props"].get("api.v4l2.path")
    }
    if qs_device:
        virtual_camera_paths.add(qs_device["path"])

    direct_mic_apps = direct_device_apps(lambda target: target.startswith("/dev/snd/pcm") and target.endswith("c"))
    direct_physical_camera_apps = direct_device_apps(lambda target: target in physical_camera_paths)
    direct_virtual_camera_apps = direct_device_apps(lambda target: target in virtual_camera_paths)
    pipewire_mic_apps = active_apps(nodes, "Stream/Input/Audio") if active_microphones else []
    pipewire_physical_camera_apps = linked_apps(nodes, links, {node["id"] for node in active_cameras}, "Stream/Input/Video")
    pipewire_virtual_camera_apps = linked_apps(nodes, links, {node["id"] for node in active_virtual_cameras}, "Stream/Input/Video")
    mic_apps = merge_apps(pipewire_mic_apps, direct_mic_apps)
    physical_camera_apps = merge_apps(pipewire_physical_camera_apps, direct_physical_camera_apps)
    virtual_camera_apps = merge_apps(pipewire_virtual_camera_apps, direct_virtual_camera_apps)
    camera_apps = merge_apps(virtual_camera_apps, physical_camera_apps)

    using_virtual_camera = bool(virtual_camera_apps)
    camera = ((active_virtual_cameras or qs_cameras) if using_virtual_camera else (active_cameras or physical_cameras) or [None])[0]
    virtual_camera_name = source_name(qs_cameras[0]) if qs_cameras else qs_device.get("name", "")
    microphone = (active_microphones or physical_sources or microphones or [None])[0]
    voice = (voice_sources or [None])[0]
    mic_muted = microphone_is_muted(active_microphones, source_mutes)
    return {
        "ok": not error,
        "error": error,
        "micActive": bool(mic_apps) and not mic_muted,
        "micMuted": mic_muted,
        "micApps": mic_apps,
        "micApp": mic_apps[0] if mic_apps else {},
        "micName": source_name(microphone) if microphone else "Microphone",
        "cameraActive": bool(camera_apps),
        "cameraApps": camera_apps,
        "cameraApp": camera_apps[0] if camera_apps else {},
        "cameraName": virtual_camera_name if using_virtual_camera else (source_name(camera) if camera else "Camera"),
        "cameraAvailable": bool(physical_cameras or qs_cameras or qs_device),
        "cameraUsingVirtual": using_virtual_camera,
        "cameraPreviewAvailable": bool(qs_cameras or qs_device),
        "cameraPreviewName": virtual_camera_name,
        "voiceIsolationAvailable": bool(voice),
        "voiceIsolationSource": voice["props"].get("node.name", "") if voice else "",
        "micMode": state.get("micMode", "standard"),
        "portraitAvailable": bool(effect_backend and qs_device and camera_model_path().exists()),
        "portraitEnabled": bool(state.get("portraitEnabled", False)),
        "backgroundAvailable": bool(effect_backend and qs_device and camera_model_path().exists()),
        "backgroundMode": state.get("backgroundMode", "none"),
        "backgroundValue": state.get("backgroundValue", ""),
        "backgroundImage": state.get("backgroundImage", "") or (
            state.get("backgroundValue", "") if state.get("backgroundMode") == "image" else ""
        ),
    }


def set_mic_mode(mode):
    if mode not in ("standard", "voice-isolation"):
        raise ValueError("invalid microphone mode")
    current = status()
    state = load_state()
    if mode == "voice-isolation":
        source = current["voiceIsolationSource"]
        if not source:
            raise RuntimeError("Voice Isolation source is unavailable")
        try:
            default_source = run(["pactl", "get-default-source"])
            if default_source and default_source != source:
                state["standardSource"] = default_source
        except (OSError, subprocess.SubprocessError):
            pass
    else:
        source = state.get("standardSource", "")
        if not source:
            raise RuntimeError("Standard microphone source is unavailable")

    run(["pactl", "set-default-source", source])
    for index in run(["pactl", "list", "short", "source-outputs"]).splitlines():
        fields = index.split("\t")
        if fields:
            subprocess.run(["pactl", "move-source-output", fields[0], source], capture_output=True)
    state["micMode"] = mode
    save_state(state)
    return status()


def set_effect(kind, value=""):
    backend = backend_path()
    if not backend:
        raise RuntimeError("Camera effects backend is unavailable")
    state = load_state()
    if kind == "portrait":
        enabled = value.lower() == "true"
        run([backend, "portrait", "on" if enabled else "off"])
        state["portraitEnabled"] = enabled
    elif kind == "background":
        mode, _, selected = value.partition(":")
        if mode not in ("none", "color", "image", "chroma"):
            raise ValueError("invalid background mode")
        saved_image = state.get("backgroundImage", "")
        if not saved_image and state.get("backgroundMode") == "image":
            saved_image = state.get("backgroundValue", "")
        if mode == "image" and not selected:
            selected = saved_image
        run([backend, "background", mode, selected])
        state["backgroundMode"] = mode
        state["backgroundValue"] = selected
        if mode == "image":
            state["backgroundImage"] = selected
        elif saved_image:
            state["backgroundImage"] = saved_image
    else:
        raise ValueError("invalid effect")
    save_state(state)
    return status()


def main():
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else "status"
        if command == "monitor":
            interval = max(0.25, min(5.0, float(sys.argv[2]) if len(sys.argv) > 2 else 0.5))
            while True:
                print(json.dumps(status(), separators=(",", ":")), flush=True)
                time.sleep(interval)
        elif command == "status":
            result = status()
        elif command == "mic-mode":
            result = set_mic_mode(sys.argv[2])
        elif command == "effect":
            result = set_effect(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
        else:
            raise ValueError("unknown command")
        print(json.dumps(result, separators=(",", ":")))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
