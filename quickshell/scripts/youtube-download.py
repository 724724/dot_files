#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
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


def audio_metadata_options(playlist=False):
    options = [
        "--replace-in-metadata", "title", r"^(.*\S)\s*\(\s*\1\s*\)$", r"\1",
        "--replace-in-metadata", "uploader", r"\s+-\s+Topic$", "",
        "--parse-metadata", "%(uploader)s:%(artist)s",
        "--parse-metadata", "%(title)s:%(track)s",
    ]
    if playlist:
        options.extend([
            # Album comes only from the track's real `album` field (written
            # natively by --embed-metadata). Do NOT fall back to playlist_title:
            # a mixed playlist like "Chill" would otherwise stamp every track
            # with the playlist name as its album.
            "--parse-metadata", "%(album_artist,artist,uploader)s:%(meta_album_artist)s",
            "--parse-metadata", "%(track_number,playlist_index)s:%(meta_track)s",
        ])
    return options


def output_template(directory, kind):
    name = "%(title)s - %(uploader)s.%(ext)s" if kind == "audio" else "%(uploader)s - %(title)s.%(ext)s"
    return str(directory / name)


def ratio_value(value):
    try:
        numerator, denominator = str(value or "0/1").split("/", 1)
        return round(float(numerator) / float(denominator), 2) if float(denominator) else 0
    except (TypeError, ValueError):
        return 0


def _syncsafe(value):
    if not 0 <= value < (1 << 28):
        raise ValueError("ID3 data is too large.")
    return bytes(((value >> 21) & 0x7f, (value >> 14) & 0x7f,
                  (value >> 7) & 0x7f, value & 0x7f))


def _unsyncsafe(value):
    if len(value) != 4 or any(byte & 0x80 for byte in value):
        raise ValueError("Invalid ID3 sync-safe size.")
    return (value[0] << 21) | (value[1] << 14) | (value[2] << 7) | value[3]


def artwork_mime(data):
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("Album artwork is not a supported JPEG, PNG, or WebP image.")


def _id3_parts(tag):
    if len(tag) < 10 or tag[:3] != b"ID3":
        raise ValueError("Invalid WAV ID3 tag.")
    version = tag[3]
    flags = tag[5]
    if version not in (3, 4):
        raise ValueError(f"Unsupported ID3v2.{version} tag in WAV file.")
    if flags & 0x80 or (version == 4 and flags & 0x10):
        raise ValueError("Unsynchronised or footer-bearing WAV ID3 tags are not supported safely.")
    body_size = _unsyncsafe(tag[6:10])
    if 10 + body_size > len(tag):
        raise ValueError("Truncated WAV ID3 tag.")
    body = tag[10:10 + body_size]
    position = 0
    prefix = b""
    if flags & 0x40:
        if len(body) < 4:
            raise ValueError("Truncated extended ID3 header.")
        extended_size = (4 + int.from_bytes(body[:4], "big")
                         if version == 3 else _unsyncsafe(body[:4]))
        if extended_size < 4 or extended_size > len(body):
            raise ValueError("Invalid extended ID3 header.")
        prefix = body[:extended_size]
        position = extended_size

    frames = []
    while position + 10 <= len(body):
        header = body[position:position + 10]
        if header[:4] == b"\0\0\0\0":
            break
        if not re.fullmatch(rb"[A-Z0-9]{4}", header[:4]):
            raise ValueError("Invalid ID3 frame in WAV file.")
        frame_size = (_unsyncsafe(header[4:8]) if version == 4
                      else int.from_bytes(header[4:8], "big"))
        frame_end = position + 10 + frame_size
        if frame_end > len(body):
            raise ValueError("Truncated ID3 frame in WAV file.")
        frames.append((header[:4], body[position:frame_end]))
        position = frame_end
    if any(body[position:]):
        raise ValueError("Unexpected data after WAV ID3 frames.")
    return version, flags, prefix, frames, len(body) - position


def _id3_with_artwork(existing, image_data, mime):
    version, flags, prefix, frames, old_padding = (
        _id3_parts(existing) if existing else (3, 0, b"", [], 0)
    )
    description = b"Cover\0"
    payload = b"\0" + mime.encode("ascii") + b"\0\x03" + description + image_data
    frame_size = _syncsafe(len(payload)) if version == 4 else len(payload).to_bytes(4, "big")
    apic = b"APIC" + frame_size + b"\0\0" + payload
    kept = b"".join(raw for frame_id, raw in frames if frame_id != b"APIC")
    padding = b"\0" * max(1024, old_padding)
    body = prefix + kept + apic + padding
    return b"ID3" + bytes((version, 0, flags)) + _syncsafe(len(body)) + body


def _riff_chunks(path):
    path = Path(path)
    with path.open("rb") as source:
        header = source.read(12)
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise ValueError(f"Not a supported RIFF/WAVE file: {path.name}")
        logical_end = int.from_bytes(header[4:8], "little") + 8
        source.seek(0, os.SEEK_END)
        file_size = source.tell()
        if logical_end != file_size:
            raise ValueError(f"Malformed RIFF size in WAV file: {path.name}")
        chunks = []
        position = 12
        while position < logical_end:
            if position + 8 > logical_end:
                raise ValueError(f"Truncated RIFF chunk in WAV file: {path.name}")
            source.seek(position)
            chunk_header = source.read(8)
            data_size = int.from_bytes(chunk_header[4:8], "little")
            chunk_end = position + 8 + data_size + (data_size & 1)
            if chunk_end > logical_end:
                raise ValueError(f"Truncated RIFF chunk in WAV file: {path.name}")
            chunks.append((chunk_header[:4], position, data_size, chunk_end))
            position = chunk_end
    return header, chunks


def _copy_bytes(source, destination, count):
    while count:
        block = source.read(min(count, 1024 * 1024))
        if not block:
            raise OSError("Unexpected end of WAV file while copying.")
        destination.write(block)
        count -= len(block)


def _wav_id3(path):
    _, chunks = _riff_chunks(path)
    with Path(path).open("rb") as source:
        for chunk_id, position, data_size, _chunk_end in chunks:
            if chunk_id.lower() == b"id3 ":
                source.seek(position + 8)
                return source.read(data_size)
    return b""


def embed_wav_artwork(audio_path, artwork_path):
    audio_path = Path(audio_path)
    artwork_path = Path(artwork_path)
    image_data = artwork_path.read_bytes()
    mime = artwork_mime(image_data)
    header, chunks = _riff_chunks(audio_path)
    existing = _wav_id3(audio_path)
    new_tag = _id3_with_artwork(existing, image_data, mime)
    temporary_name = ""
    try:
        with audio_path.open("rb") as source, tempfile.NamedTemporaryFile(
                mode="w+b", prefix=f".{audio_path.name}.", suffix=".tmp",
                dir=audio_path.parent, delete=False) as destination:
            temporary_name = destination.name
            destination.write(header)
            wrote_id3 = False
            for chunk_id, position, _data_size, chunk_end in chunks:
                if chunk_id.lower() == b"id3 ":
                    if wrote_id3:
                        continue
                    payload = new_tag
                    destination.write(b"id3 " + len(payload).to_bytes(4, "little") + payload)
                    if len(payload) & 1:
                        destination.write(b"\0")
                    wrote_id3 = True
                    continue
                source.seek(position)
                _copy_bytes(source, destination, chunk_end - position)
            if not wrote_id3:
                payload = new_tag
                destination.write(b"id3 " + len(payload).to_bytes(4, "little") + payload)
                if len(payload) & 1:
                    destination.write(b"\0")
            total_size = destination.tell()
            if total_size - 8 >= (1 << 32):
                raise ValueError("WAV file is too large for RIFF artwork metadata.")
            destination.seek(4)
            destination.write((total_size - 8).to_bytes(4, "little"))
            destination.flush()
            os.fsync(destination.fileno())
        shutil.copystat(audio_path, temporary_name)
        os.replace(temporary_name, audio_path)
        temporary_name = ""
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)

    saved = _wav_id3(audio_path)
    _version, _flags, _prefix, frames, _padding = _id3_parts(saved)
    if not any(frame_id == b"APIC" and raw.endswith(image_data) for frame_id, raw in frames):
        raise RuntimeError(f"Could not verify embedded artwork in {audio_path.name}.")
    return mime


def _temporary_artwork(directory, stem):
    directory = Path(directory)
    for candidate in sorted(directory.glob(f"{stem}.*")):
        try:
            artwork_mime(candidate.read_bytes())
            return candidate
        except (OSError, ValueError):
            continue
    return None


def embed_download_artwork(output_records, artwork_directory, playlist=False):
    shared = _temporary_artwork(artwork_directory, "playlist") if playlist else None
    embedded = 0
    for output_path, video_id in output_records:
        cover = shared or _temporary_artwork(artwork_directory, f"entry-{video_id}")
        if cover is None and len(output_records) == 1:
            cover = next((candidate for candidate in Path(artwork_directory).glob("entry-*")
                          if candidate.is_file()), None)
        if cover is None:
            continue
        embed_wav_artwork(output_path, cover)
        embedded += 1
    return embedded


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
                "format=bit_rate:stream=codec_type,codec_name,width,height,r_frame_rate,bit_rate,sample_rate,channels:stream_disposition=attached_pic",
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
    video = next((stream for stream in streams
                  if stream.get("codec_type") == "video"
                  and not (stream.get("disposition") or {}).get("attached_pic")), {})
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


def embed_artwork_command(args):
    cover = Path(args.cover).expanduser()
    audio_paths = [Path(path).expanduser() for path in args.audio]
    for audio_path in audio_paths:
        embed_wav_artwork(audio_path, cover)
    for image_path in args.delete:
        Path(image_path).expanduser().unlink(missing_ok=True)
    print(json.dumps({
        "ok": True,
        "cover": str(cover),
        "files": [str(path) for path in audio_paths],
    }, ensure_ascii=False))


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
    wav_artwork = kind == "audio" and args.audio_format == "wav"
    artwork_temp = tempfile.TemporaryDirectory(prefix="quickshell-youtube-artwork-") if wav_artwork else None
    artwork_dir = Path(artwork_temp.name) if artwork_temp else None
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
        "after_move:__QS_FILE__%(filepath)s\t%(id)s",
    ]
    if kind == "video":
        command.extend([
            "--embed-thumbnail", "--convert-thumbnails", "jpg",
            "--format", video_selector(args.quality), "--merge-output-format", "mp4",
        ])
    elif kind == "audio":
        command.extend(audio_metadata_options(playlist))
        command.extend(["--convert-thumbnails", "jpg"])
        if wav_artwork:
            command.extend([
                "--write-thumbnail",
                "--output", f"thumbnail:{artwork_dir}/entry-%(id)s.%(ext)s",
                "--output", f"pl_thumbnail:{artwork_dir}/playlist.%(ext)s",
            ])
        else:
            command.append("--embed-thumbnail")
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
    output_records = []
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
            fields = line.removeprefix("__QS_FILE__").split("\t", 1)
            output_path = fields[0].strip()
            video_id = fields[1].strip() if len(fields) > 1 else ""
            output_paths.append(output_path)
            output_records.append((output_path, video_id))
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
    if artwork_dir:
        emit("processing", message="Embedding album artwork…")
        embed_download_artwork(output_records, artwork_dir, playlist)
    emit("completed", progress=100, path=output_path, outputDir=str(output_dir),
         mediaInfo=media_details(output_path), files=len(output_paths), playlist=playlist)
    if artwork_temp:
        artwork_temp.cleanup()


def parser():
    value = argparse.ArgumentParser()
    subparsers = value.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    set_output = subparsers.add_parser("set-output")
    set_output.add_argument("--path", required=True)
    embed_artwork = subparsers.add_parser("embed-artwork")
    embed_artwork.add_argument("--cover", required=True)
    embed_artwork.add_argument("--audio", action="append", required=True)
    embed_artwork.add_argument("--delete", action="append", default=[])
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
        elif args.command == "embed-artwork":
            embed_artwork_command(args)
        elif args.command == "info":
            info_command(args)
        else:
            download_command(args)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        if args.command == "download":
            emit("error", message=str(error))
        else:
            print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
