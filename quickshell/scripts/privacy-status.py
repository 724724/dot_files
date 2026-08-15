#!/usr/bin/env python3

import ctypes
import json
import os
import select
import signal
import shutil
import subprocess
import sys
import time
from pathlib import Path


IGNORED_APPS = {
    "pipewire",
    "quickshell",
    "wireplumber",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
}
CAMERA_PROVIDER_BINARIES = {"droidcam", "droidcam-cli"}
DIRECT_CAMERA_CHECK_SECONDS = 1.0
_camera_device_paths = set()
_direct_camera_signature = ()


def child_exits_with_parent():
    """Terminate an observer if its Quickshell-owned parent disappears."""
    if sys.platform.startswith("linux"):
        libc = ctypes.CDLL(None)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
        if os.getppid() == 1:
            os.kill(os.getpid(), signal.SIGTERM)


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
                links.append({
                    "output": info.get("output-node-id"),
                    "input": info.get("input-node-id"),
                })
            continue
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        info = item.get("info", {})
        props = dict(clients.get(info.get("props", {}).get("client.id"), {}))
        props.update(info.get("props", {}))
        nodes.append({
            "id": item.get("id"),
            "state": str(info.get("state", "")).lower(),
            "props": props,
        })
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
    for proc in os.scandir("/proc"):
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat(follow_symlinks=False).st_uid != uid:
                continue
        except OSError:
            continue
        using_device = False
        try:
            with os.scandir(os.path.join(proc.path, "fd")) as fds:
                for fd in fds:
                    try:
                        target = os.readlink(fd.path)
                    except OSError:
                        continue
                    if device_test(target):
                        using_device = True
                        break
        except OSError:
            continue
        if not using_device:
            continue
        app = process_app(proc.name)
        if not app:
            continue
        key = (app["name"].lower(), app["id"])
        if key not in seen:
            seen.add(key)
            apps.append(app)
    return apps


def direct_microphone_apps():
    return direct_device_apps(
        lambda target: target.startswith("/dev/snd/pcm") and target.endswith("c")
    )


def direct_camera_apps(device_paths):
    paths = set(device_paths)
    if not paths:
        return []
    return [
        app for app in direct_device_apps(paths.__contains__)
        if app.get("binary") not in CAMERA_PROVIDER_BINARIES
    ]


def virtual_camera_paths(sysfs_root="/sys/class/video4linux"):
    paths = set()
    try:
        entries = Path(sysfs_root).glob("video*")
    except OSError:
        return paths
    for entry in entries:
        try:
            resolved = entry.resolve(strict=True).as_posix()
        except OSError:
            continue
        if "/devices/virtual/video4linux/" in resolved:
            paths.add("/dev/" + entry.name)
    return paths


def app_signature(apps):
    return tuple(sorted((app["name"].lower(), app["id"], app["binary"]) for app in apps))


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


def source_name(node):
    props = node["props"]
    return str(props.get("node.description") or props.get("device.description")
               or props.get("node.nick") or props.get("node.name") or "")


def is_monitor_source(node):
    props = node["props"]
    text = " ".join(str(props.get(key, "")).lower()
                    for key in ("node.name", "node.description", "device.description"))
    return props.get("device.class") == "monitor" or ".monitor" in text or "monitor of" in text


def is_camera_source(node):
    props = node["props"]
    if props.get("media.class") != "Video/Source":
        return False
    role = str(props.get("media.role", "")).lower()
    object_path = str(props.get("object.path", "")).lower()
    return role == "camera" or "api.v4l2.path" in props or object_path.startswith("v4l2:")


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


def status():
    global _camera_device_paths, _direct_camera_signature

    try:
        nodes, links = pipewire_graph()
        error = ""
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        nodes = []
        links = []
        error = str(exc)

    microphones = [
        node for node in nodes
        if node["props"].get("media.class") == "Audio/Source" and not is_monitor_source(node)
    ]
    active_microphones = [node for node in microphones if node["state"] == "running"]
    pipewire_apps = active_apps(nodes, "Stream/Input/Audio")
    direct_apps = direct_microphone_apps()
    mic_apps = merge_apps(pipewire_apps, direct_apps)
    microphone = (active_microphones or microphones or [None])[0]
    mic_muted = microphone_is_muted(active_microphones, pulse_source_mutes())
    cameras = [node for node in nodes if is_camera_source(node)]
    active_cameras = [node for node in cameras if node["state"] == "running"]
    _camera_device_paths = {
        str(node["props"]["api.v4l2.path"])
        for node in cameras
        if node["props"].get("api.v4l2.path")
    } | virtual_camera_paths()
    pipewire_camera_apps = linked_apps(
        nodes,
        links,
        {node["id"] for node in active_cameras},
        "Stream/Input/Video",
    )
    direct_camera = direct_camera_apps(_camera_device_paths)
    _direct_camera_signature = app_signature(direct_camera)
    camera_apps = merge_apps(pipewire_camera_apps, direct_camera)
    camera = (active_cameras or cameras or [None])[0]
    return {
        "ok": not error,
        "error": error,
        "micActive": bool(mic_apps or active_microphones) and not mic_muted,
        "micMuted": mic_muted,
        "micApps": mic_apps,
        "micApp": mic_apps[0] if mic_apps else {},
        "micName": source_name(microphone) if microphone else "Microphone",
        "cameraActive": bool(active_cameras or direct_camera),
        "cameraApps": camera_apps,
        "cameraApp": camera_apps[0] if camera_apps else {},
        "cameraName": source_name(camera) if camera else "Camera",
    }


def pulse_microphone_event(line):
    event = line.lower()
    return "source-output" in event or " on source #" in event


def pipewire_privacy_event(line):
    # pw-dump's monitor output is multiline; node/link changes are settled into
    # one refresh, whose status path considers privacy-sensitive media nodes.
    return "PipeWire:Interface:Node" in line or "PipeWire:Interface:Link" in line


def monitor(settle_seconds=0.5):
    """Emit privacy state only when Pulse/PipeWire reports a change."""
    settle_seconds = max(0.25, min(2.0, settle_seconds))
    observers = []

    def stop(_signum, _frame):
        for observer, _kind in observers:
            if observer.poll() is None:
                observer.terminate()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def emit():
        print(json.dumps(status(), separators=(",", ":")), flush=True)
        return _direct_camera_signature

    direct_signature = emit()
    next_direct_check = time.monotonic() + DIRECT_CAMERA_CHECK_SECONDS
    while True:
        observers = []
        if shutil.which("pactl"):
            observers.append((subprocess.Popen(
                ["pactl", "subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                preexec_fn=child_exits_with_parent,
            ), "pulse"))
        if shutil.which("pw-dump"):
            command = ["pw-dump", "-m"]
            if shutil.which("stdbuf"):
                command = ["stdbuf", "-oL", *command]
            observers.append((subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                preexec_fn=child_exits_with_parent,
            ), "pipewire"))

        streams = {
            observer.stdout: kind
            for observer, kind in observers
            if observer.stdout is not None
        }
        if not streams:
            time.sleep(5)
            direct_signature = emit()
            next_direct_check = time.monotonic() + DIRECT_CAMERA_CHECK_SECONDS
            continue

        dirty = False
        last_event = 0.0
        try:
            while all(observer.poll() is None for observer, _kind in observers):
                now = time.monotonic()
                deadlines = [next_direct_check]
                if dirty:
                    deadlines.append(last_event + settle_seconds)
                timeout = max(0.0, min(deadlines) - now)
                ready, _, _ = select.select(list(streams), [], [], timeout)
                if not ready:
                    now = time.monotonic()
                    should_emit = dirty and now - last_event >= settle_seconds
                    if now >= next_direct_check:
                        current_signature = app_signature(
                            direct_camera_apps(_camera_device_paths)
                        )
                        should_emit = should_emit or current_signature != direct_signature
                        direct_signature = current_signature
                        next_direct_check = now + DIRECT_CAMERA_CHECK_SECONDS
                    if should_emit:
                        direct_signature = emit()
                        dirty = False
                    continue
                restart = False
                for stream in ready:
                    line = stream.readline()
                    if line == "":
                        restart = True
                        break
                    kind = streams[stream]
                    if ((kind == "pulse" and pulse_microphone_event(line))
                            or (kind == "pipewire" and pipewire_privacy_event(line))):
                        dirty = True
                        last_event = time.monotonic()
                if restart:
                    break
        finally:
            for observer, _kind in observers:
                if observer.poll() is None:
                    observer.terminate()
                try:
                    observer.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    observer.kill()
                    observer.wait()
        time.sleep(1)
        direct_signature = emit()
        next_direct_check = time.monotonic() + DIRECT_CAMERA_CHECK_SECONDS


def main():
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else "status"
        if command == "monitor":
            interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
            monitor(interval)
            return
        if command != "status":
            raise ValueError("unknown command")
        print(json.dumps(status(), separators=(",", ":")))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
