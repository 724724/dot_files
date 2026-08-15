#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse


SEPARATOR = "\x1f"
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
PLAYER = ["playerctl", "--player=playerctld"]


def youtube_id(url):
    try:
        parsed = urlparse(url)
    except ValueError:
        return ""
    host = (parsed.hostname or "").lower()
    if host.startswith("www."):
        host = host[4:]
    if host == "youtu.be":
        candidate = parsed.path.strip("/").split("/", 1)[0]
    elif host in {"youtube.com", "m.youtube.com", "music.youtube.com"}:
        if parsed.path.rstrip("/") == "/watch":
            candidate = (parse_qs(parsed.query).get("v") or [""])[0]
        else:
            parts = [part for part in parsed.path.split("/") if part]
            candidate = parts[1] if len(parts) > 1 and parts[0] in {
                "embed", "live", "shorts"
            } else ""
    else:
        candidate = ""
    return candidate if VIDEO_ID.fullmatch(candidate) else ""


def youtube_thumbnail(url):
    video = youtube_id(url)
    return f"https://i.ytimg.com/vi/{video}/hqdefault.jpg" if video else ""


def number(value, divisor=1):
    try:
        result = float(value) / divisor
        return result if result >= 0 else 0
    except (TypeError, ValueError, ZeroDivisionError):
        return 0


def snapshot():
    fields = (
        "{{status}}", "{{title}}", "{{artist}}", "{{mpris:artUrl}}",
        "{{xesam:url}}", "{{mpris:length}}", "{{position}}"
    )
    try:
        result = subprocess.run(
            [*PLAYER, "metadata", "--format", SEPARATOR.join(fields)],
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.SubprocessError):
        result = None
    if not result or result.returncode != 0:
        return {
            "status": "none", "title": "", "artist": "", "artUrl": "",
            "url": "", "duration": 0, "position": 0,
            "artDark": True, "artAccent": "",
        }
    values = result.stdout.rstrip("\n").split(SEPARATOR)
    values.extend([""] * (len(fields) - len(values)))
    status, title, artist, art_url, url, length, position = values[:len(fields)]
    if status not in {"Playing", "Paused"}:
        status = "none"
        title = artist = art_url = url = ""
        length = position = "0"
    if not art_url:
        art_url = youtube_thumbnail(url)
    return {
        "status": status,
        "title": title,
        "artist": artist,
        "artUrl": art_url,
        "url": url,
        "duration": number(length, 1_000_000),
        "position": number(position, 1_000_000),
        "artDark": True,
        "artAccent": "",
    }


def cache_path(video):
    root = Path(os.environ.get(
        "XDG_CACHE_HOME", Path.home() / ".cache"
    )) / "quickshell/media"
    root.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(video.encode()).hexdigest()[:20]
    return root / f"youtube-{digest}.json"


def read_cache(path):
    try:
        value = json.loads(path.read_text())
        if value.get("duration", 0) > 0:
            return value
        if time.time() - float(value.get("fetchedAt", 0)) < 300:
            return value
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    return None


def write_cache(path, value):
    temporary = path.with_suffix(f".tmp-{os.getpid()}")
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    os.replace(temporary, path)


def youtube_duration(url):
    video = youtube_id(url)
    fallback = {
        "url": url,
        "duration": 0,
        "thumbnail": youtube_thumbnail(url),
        "fetchedAt": time.time(),
    }
    if not video:
        return fallback
    path = cache_path(video)
    cached = read_cache(path)
    if cached is not None:
        cached["url"] = url
        return cached
    executable = shutil.which("yt-dlp")
    if executable:
        try:
            result = subprocess.run(
                [
                    executable, "--no-warnings", "--no-playlist",
                    "--skip-download", "--socket-timeout", "6",
                    "--retries", "1", "--extractor-retries", "1",
                    "--dump-single-json", url,
                ],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if result.returncode == 0:
                value = json.loads(result.stdout)
                fallback["duration"] = number(value.get("duration"))
                fallback["thumbnail"] = value.get("thumbnail") or fallback["thumbnail"]
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
            pass
    write_cache(path, fallback)
    return fallback


def duration(url):
    current = snapshot()
    if current["duration"] > 0 and (not url or current["url"] == url):
        return {
            "url": current["url"] or url,
            "duration": current["duration"],
            "thumbnail": current["artUrl"],
        }
    return youtube_duration(url)


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command")
    duration_parser = subparsers.add_parser("duration")
    duration_parser.add_argument("--url", default="")
    args = parser.parse_args()
    value = duration(args.url) if args.command == "duration" else snapshot()
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
