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


def child_exits_with_parent():
    """Terminate an observer if its Quickshell-owned parent disappears."""
    if sys.platform.startswith("linux"):
        libc = ctypes.CDLL(None)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
        if os.getppid() == 1:
            os.kill(os.getpid(), signal.SIGTERM)


def run(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()


def pipewire_nodes():
    graph = json.loads(run(["pw-dump"]))
    clients = {}
    for item in graph:
        if item.get("type") == "PipeWire:Interface:Client":
            clients[item.get("id")] = item.get("info", {}).get("props", {})

    nodes = []
    for item in graph:
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
    return nodes


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


def direct_microphone_apps():
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
        using_microphone = False
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("/dev/snd/pcm") and target.endswith("c"):
                using_microphone = True
                break
        if not using_microphone:
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


def source_name(node):
    props = node["props"]
    return str(props.get("node.description") or props.get("device.description")
               or props.get("node.nick") or props.get("node.name") or "")


def is_monitor_source(node):
    props = node["props"]
    text = " ".join(str(props.get(key, "")).lower()
                    for key in ("node.name", "node.description", "device.description"))
    return props.get("device.class") == "monitor" or ".monitor" in text or "monitor of" in text


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
    try:
        nodes = pipewire_nodes()
        error = ""
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        nodes = []
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
    return {
        "ok": not error,
        "error": error,
        "micActive": bool(mic_apps or active_microphones) and not mic_muted,
        "micMuted": mic_muted,
        "micApps": mic_apps,
        "micApp": mic_apps[0] if mic_apps else {},
        "micName": source_name(microphone) if microphone else "Microphone",
    }


def pulse_microphone_event(line):
    event = line.lower()
    return "source-output" in event or " on source #" in event


def pipewire_microphone_event(line):
    # pw-dump's monitor output is multiline; node/link changes are settled into
    # one refresh, whose status path considers Audio nodes only.
    return "PipeWire:Interface:Node" in line or "PipeWire:Interface:Link" in line


def monitor(settle_seconds=0.5):
    """Emit microphone state only when Pulse/PipeWire reports a change."""
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

    emit()
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
            emit()
            continue

        dirty = False
        last_event = 0.0
        try:
            while all(observer.poll() is None for observer, _kind in observers):
                timeout = max(0.0, settle_seconds - (time.monotonic() - last_event)) if dirty else None
                ready, _, _ = select.select(list(streams), [], [], timeout)
                if dirty and not ready:
                    emit()
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
                            or (kind == "pipewire" and pipewire_microphone_event(line))):
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
        emit()


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
