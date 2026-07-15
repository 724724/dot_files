#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse


VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
YOUTUBE_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "www.youtu.be",
}
BROWSER_CONFIGS = {
    "chrome": ([".config/google-chrome"], ["google-chrome-stable", "google-chrome"]),
    "chromium": ([".config/chromium"], ["chromium"]),
    "firefox": ([".mozilla/firefox"], ["firefox"]),
    "brave": ([".config/BraveSoftware/Brave-Browser"], ["brave", "brave-browser"]),
    "edge": ([".config/microsoft-edge"], ["microsoft-edge-stable", "microsoft-edge"]),
}
VIDEO_HEIGHTS = {"2160": 2160, "1440": 1440, "1080": 1080, "720": 720, "480": 480}
AUDIO_FORMATS = {"wav", "flac", "m4a", "mp3"}
REPEATED_TITLE = re.compile(r"^(.*\S)\s*\(\s*\1\s*\)$", re.IGNORECASE)


def emit(event, **values):
    print(json.dumps({"event": event, **values}, ensure_ascii=False), flush=True)


def normalize_input(value):
    value = value.strip()
    if VIDEO_ID.fullmatch(value):
        return f"https://www.youtube.com/watch?v={value}"
    if "://" not in value and any(host in value.lower() for host in ("youtube.com", "youtu.be")):
        value = "https://" + value
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or parsed.hostname not in YOUTUBE_HOSTS:
        raise ValueError("Enter a YouTube link or an 11-character video ID.")
    return value


def available_browsers(home=None):
    home = Path(home or Path.home())
    result = []
    for browser, (directories, executables) in BROWSER_CONFIGS.items():
        configured = any((home / directory).exists() for directory in directories)
        installed = any(shutil.which(executable) for executable in executables)
        if configured or installed:
            result.append(browser)
    return result


def browser_from_desktop_entry(value):
    value = str(value or "").strip().lower()
    mappings = (
        ("microsoft-edge", "edge"),
        ("google-chrome", "chrome"),
        ("com.google.chrome", "chrome"),
        ("brave", "brave"),
        ("chromium", "chromium"),
        ("firefox", "firefox"),
    )
    return next((browser for marker, browser in mappings if marker in value), "")


def default_browser(browsers=None):
    browsers = browsers if browsers is not None else available_browsers()
    executable = shutil.which("xdg-settings")
    if executable:
        try:
            result = subprocess.run(
                [executable, "get", "default-web-browser"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
            browser = browser_from_desktop_entry(result.stdout)
            if browser in browsers:
                return browser
        except (OSError, subprocess.SubprocessError):
            pass
    return browsers[0] if browsers else ""


def resolved_browser(browser, browsers=None):
    browsers = browsers if browsers is not None else available_browsers()
    if browser == "none":
        return ""
    if browser == "auto":
        preferred = os.environ.get("QS_YTDLP_BROWSER", "").strip().lower()
        return preferred if preferred in browsers else default_browser(browsers)
    if browser not in BROWSER_CONFIGS:
        raise ValueError("Unsupported browser cookie source.")
    return browser


def cookie_args(browser, browsers=None):
    browser = resolved_browser(browser, browsers)
    if not browser:
        return []
    return ["--cookies-from-browser", browser]


def is_playlist_url(value):
    parsed = urlparse(value)
    query = parse_qs(parsed.query)
    return parsed.path.rstrip("/").endswith("/playlist") or bool(query.get("list"))


def is_music_url(value):
    return urlparse(value).hostname == "music.youtube.com"


def video_selector(quality):
    if quality == "best":
        return "bv*+ba/b"
    if quality not in VIDEO_HEIGHTS:
        raise ValueError("Unsupported video quality.")
    height = VIDEO_HEIGHTS[quality]
    return f"bv*[height<={height}]+ba/b[height<={height}]"


def audio_options(output_format):
    if output_format not in AUDIO_FORMATS:
        raise ValueError("Unsupported audio output format.")
    return ["--extract-audio", "--audio-format", output_format, "--audio-quality", "0"]


def clean_music_title(value):
    value = " ".join(str(value or "").split())
    match = REPEATED_TITLE.fullmatch(value)
    return match.group(1).strip() if match else value


def clean_music_artist(value):
    value = " ".join(str(value or "").split())
    return re.sub(r"\s+-\s+Topic$", "", value, flags=re.IGNORECASE).strip()


def audio_metadata_options():
    return [
        "--replace-in-metadata", "title", r"^(.*\S)\s*\(\s*\1\s*\)$", r"\1",
        "--replace-in-metadata", "uploader", r"\s+-\s+Topic$", "",
        "--parse-metadata", "%(uploader)s:%(artist)s",
        "--parse-metadata", "%(title)s:%(track)s",
    ]


def output_template(directory, kind):
    name = "%(title)s - %(uploader)s.%(ext)s" if kind == "audio" else "%(uploader)s - %(title)s.%(ext)s"
    return str(directory / name)


def ratio_value(value):
    try:
        numerator, denominator = str(value or "0/1").split("/", 1)
        return round(float(numerator) / float(denominator), 2) if float(denominator) else 0
    except (TypeError, ValueError):
        return 0


def media_details(path):
    executable = shutil.which("ffprobe")
    if not executable or not path or not Path(path).is_file():
        return {}
    try:
        result = subprocess.run(
            [
                executable,
                "-v", "error",
                "-show_entries",
                "format=bit_rate:stream=codec_type,codec_name,width,height,r_frame_rate,bit_rate,sample_rate,channels",
                "-of", "json",
                path,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return {}
        value = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return {}
    streams = value.get("streams") or []
    video = next((stream for stream in streams if stream.get("codec_type") == "video"), {})
    audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), {})
    format_rate = int((value.get("format") or {}).get("bit_rate") or 0)
    audio_rate = int(audio.get("bit_rate") or (format_rate if audio and not video else 0))
    return {
        "videoCodec": video.get("codec_name") or "",
        "width": int(video.get("width") or 0),
        "height": int(video.get("height") or 0),
        "fps": ratio_value(video.get("r_frame_rate")),
        "videoBitrateKbps": round(int(video.get("bit_rate") or 0) / 1000),
        "audioCodec": audio.get("codec_name") or "",
        "audioBitrateKbps": round(audio_rate / 1000),
        "sampleRateHz": int(audio.get("sample_rate") or 0),
        "channels": int(audio.get("channels") or 0),
        "overallBitrateKbps": round(format_rate / 1000),
    }


def base_command(browser, playlist=False):
    executable = shutil.which("yt-dlp")
    if not executable:
        raise RuntimeError("yt-dlp is not installed.")
    selection = "--yes-playlist" if playlist else "--no-playlist"
    return [executable, selection, "--no-warnings", *cookie_args(browser)]


def positive_int(value, fallback=0):
    match = re.search(r"\d+", str(value or ""))
    return int(match.group()) if match else fallback


def thumbnail_url(value):
    if value.get("thumbnail"):
        return value["thumbnail"]
    thumbnails = value.get("thumbnails") or []
    return thumbnails[-1].get("url", "") if thumbnails else ""


def settings_path():
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base / "quickshell/youtube-downloader.json"


def load_settings():
    try:
        value = json.loads(settings_path().read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def output_directory():
    override = os.environ.get("QS_YOUTUBE_DOWNLOAD_DIR", "").strip()
    configured = str(load_settings().get("outputDir", "")).strip()
    return Path(override or configured or (Path.home() / "Downloads/YouTube")).expanduser()


def set_output_directory(path):
    target = Path(path).expanduser()
    if not target.is_absolute():
        raise ValueError("Download folder must use an absolute path.")
    target.mkdir(parents=True, exist_ok=True)
    state = load_settings()
    state["outputDir"] = str(target)
    destination = settings_path()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(state, ensure_ascii=False, separators=(",", ":")))
    destination.chmod(0o600)
    return target


def status_command(_args):
    executable = shutil.which("yt-dlp")
    version = ""
    if executable:
        try:
            version = subprocess.run(
                [executable, "--version"], check=True, capture_output=True, text=True, timeout=10
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
    browsers = available_browsers()
    print(json.dumps({
        "ok": bool(executable and shutil.which("ffmpeg")),
        "ytDlp": executable or "",
        "version": version,
        "ffmpeg": shutil.which("ffmpeg") or "",
        "browsers": browsers,
        "autoBrowser": resolved_browser("auto", browsers),
        "outputDir": str(output_directory()),
    }, ensure_ascii=False))


def set_output_command(args):
    target = set_output_directory(args.path)
    print(json.dumps({"ok": True, "outputDir": str(target)}, ensure_ascii=False))


def info_command(args):
    url = normalize_input(args.input)
    playlist_requested = is_playlist_url(url)
    command = [*base_command(args.browser, playlist_requested), "--skip-download"]
    if playlist_requested:
        command.append("--flat-playlist")
    command.extend(["--dump-single-json", url])
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "Unable to read video information.").strip().splitlines()[-1]
        raise RuntimeError(message)
    value = json.loads(result.stdout)
    is_playlist = value.get("_type") in {"playlist", "multi_video"}
    entries = [entry for entry in (value.get("entries") or []) if entry]
    representative = entries[0] if is_playlist and entries else value
    formats = representative.get("formats") or []
    heights = [int(item.get("height") or 0) for item in formats]
    audio_rates = [float(item.get("abr") or 0) for item in formats]
    raw_title = value.get("title") or representative.get("title") or "Untitled"
    raw_artist = value.get("uploader") or value.get("channel") or representative.get("uploader") or representative.get("channel") or ""
    print(json.dumps({
        "ok": True,
        "url": value.get("webpage_url") or url,
        "id": value.get("id") or representative.get("id") or "",
        "title": clean_music_title(raw_title) if is_music_url(url) and not is_playlist else raw_title,
        "channel": value.get("channel") or value.get("uploader") or representative.get("channel") or representative.get("uploader") or "",
        "uploader": value.get("uploader") or value.get("channel") or representative.get("uploader") or representative.get("channel") or "",
        "uploadDate": value.get("upload_date") or representative.get("upload_date") or "",
        "artist": clean_music_artist(raw_artist) if is_music_url(url) else value.get("artist") or representative.get("artist") or "",
        "album": value.get("album") or representative.get("album") or "",
        "duration": int(value.get("duration") or representative.get("duration") or 0),
        "thumbnail": thumbnail_url(value) or thumbnail_url(representative),
        "isPlaylist": is_playlist,
        "entryCount": len(entries) if is_playlist else 1,
        "maxHeight": max(heights, default=0),
        "maxAudioBitrate": round(max(audio_rates, default=0)),
        "cookieSource": resolved_browser(args.browser),
    }, ensure_ascii=False))


def download_command(args):
    url = normalize_input(args.input)
    playlist = is_playlist_url(url)
    kind = "audio" if is_music_url(url) else args.kind
    output_dir = output_directory()
    output_dir.mkdir(parents=True, exist_ok=True)
    template = output_template(output_dir, kind)
    command = [
        *base_command(args.browser, playlist),
        "--ignore-errors",
        "--newline",
        "--progress",
        "--embed-metadata",
        "--embed-chapters",
        "--output",
        template,
        "--progress-template",
        "download:__QS_PROGRESS__%(progress._percent_str)s\t%(progress._speed_str)s\t%(progress._eta_str)s\t%(info.playlist_index)s\t%(info.playlist_count)s",
        "--progress-template",
        "postprocess:__QS_STAGE__Finishing media and metadata…",
        "--print",
        "before_dl:__QS_ITEM__%(playlist_index)s\t%(playlist_count)s\t%(title)s",
        "--print",
        "after_move:__QS_FILE__%(filepath)s",
    ]
    if kind == "video":
        command.extend([
            "--embed-thumbnail", "--convert-thumbnails", "jpg",
            "--format", video_selector(args.quality), "--merge-output-format", "mp4",
        ])
    elif kind == "audio":
        command.extend(audio_metadata_options())
        command.extend(["--convert-thumbnails", "jpg"])
        command.append("--write-thumbnail" if args.audio_format == "wav" else "--embed-thumbnail")
        command.extend(["--format", "ba/b", *audio_options(args.audio_format)])
    else:
        raise ValueError("Unsupported media type.")
    command.append(url)

    emit("starting", outputDir=str(output_dir), playlist=playlist)
    child = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )

    def terminate_child(_signum, _frame):
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)

    signal.signal(signal.SIGTERM, terminate_child)
    signal.signal(signal.SIGINT, terminate_child)
    output_path = ""
    output_paths = []
    item_index = 0
    item_count = 0
    recent = []
    assert child.stdout is not None
    for raw_line in child.stdout:
        line = raw_line.rstrip()
        if line.startswith("__QS_PROGRESS__"):
            fields = line.removeprefix("__QS_PROGRESS__").split("\t")
            percent_text = fields[0].strip().replace("%", "") if fields else "0"
            try:
                progress = max(0.0, min(100.0, float(percent_text)))
            except ValueError:
                progress = 0.0
            progress_index = positive_int(fields[3], item_index) if len(fields) > 3 else item_index
            progress_count = positive_int(fields[4], item_count) if len(fields) > 4 else item_count
            overall = ((progress_index - 1 + progress / 100) / progress_count * 100
                       if progress_index > 0 and progress_count > 0 else progress)
            emit("progress", progress=overall, itemProgress=progress,
                 speed=fields[1].strip() if len(fields) > 1 else "",
                 eta=fields[2].strip() if len(fields) > 2 else "",
                 index=progress_index, count=progress_count)
        elif line.startswith("__QS_ITEM__"):
            fields = line.removeprefix("__QS_ITEM__").split("\t", 2)
            item_index = positive_int(fields[0], len(output_paths) + 1) if fields else len(output_paths) + 1
            item_count = positive_int(fields[1], item_count) if len(fields) > 1 else item_count
            title = fields[2].strip() if len(fields) > 2 else ""
            emit("item", title=title, index=item_index, count=item_count)
        elif line.startswith("__QS_FILE__"):
            output_path = line.removeprefix("__QS_FILE__").strip()
            output_paths.append(output_path)
            emit("itemCompleted", path=output_path, index=item_index, count=item_count,
                 completed=len(output_paths))
        elif line.startswith("__QS_STAGE__"):
            emit("processing", message=line.removeprefix("__QS_STAGE__").strip())
        elif line:
            recent.append(line)
            recent = recent[-8:]
    return_code = child.wait()
    if return_code != 0:
        raise RuntimeError(recent[-1] if recent else "Download failed.")
    if not output_paths:
        raise RuntimeError(recent[-1] if recent else "No downloadable playlist items were found.")
    emit("completed", progress=100, path=output_path, outputDir=str(output_dir),
         mediaInfo=media_details(output_path), files=len(output_paths), playlist=playlist)


def parser():
    value = argparse.ArgumentParser()
    subparsers = value.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    set_output = subparsers.add_parser("set-output")
    set_output.add_argument("--path", required=True)
    info = subparsers.add_parser("info")
    info.add_argument("--input", required=True)
    info.add_argument("--browser", default="auto")
    download = subparsers.add_parser("download")
    download.add_argument("--input", required=True)
    download.add_argument("--kind", choices=("video", "audio"), required=True)
    download.add_argument("--quality", default="best")
    download.add_argument("--audio-format", default="m4a", choices=tuple(sorted(AUDIO_FORMATS)))
    download.add_argument("--browser", default="auto")
    return value


def main():
    args = parser().parse_args()
    try:
        if args.command == "status":
            status_command(args)
        elif args.command == "set-output":
            set_output_command(args)
        elif args.command == "info":
            info_command(args)
        else:
            download_command(args)
    except (ValueError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        if args.command == "download":
            emit("error", message=str(error))
        else:
            print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
