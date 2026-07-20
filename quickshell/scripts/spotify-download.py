#!/usr/bin/env python3
"""Spotify → YouTube downloader backend (no spotdl, no user login).

  1. Resolve Spotify metadata with the anonymous token exposed by Spotify's
     public embed player. Playlist pages are fetched until their final offset.
  2. Search YouTube Music's Songs catalogue for each track, load cookies from
     the selected browser, and download the best audio-only format.
  3. Tag the file (title / artist / album / cover art) with ffmpeg from the
     Spotify metadata. Existing files are re-tagged and skipped, so re-running
     fills playlist gaps without downloading audio twice.

Newline-delimited JSON event protocol; CLI: status / info / download / set-output.
"""

import argparse
import base64
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

AUDIO_FORMATS = {"mp3", "m4a", "flac", "opus", "wav"}
BROWSER_CONFIGS = {
    "chrome": ([".config/google-chrome"], ["google-chrome-stable", "google-chrome"]),
    "chromium": ([".config/chromium"], ["chromium"]),
    "firefox": ([".mozilla/firefox"], ["firefox"]),
    "brave": ([".config/BraveSoftware/Brave-Browser"], ["brave", "brave-browser"]),
    "edge": ([".config/microsoft-edge"], ["microsoft-edge-stable", "microsoft-edge"]),
}
_UA = "Mozilla/5.0"
_YTMUSIC_SONGS_FILTER = "EgWKAQIIAWoKEAoQAxAEEAkQBQ=="
_SOURCE_VERSION = "ytmusic-songs-v1"
_PATHFINDER_URL = "https://api-partner.spotify.com/pathfinder/v1/query"
_PLAYLIST_QUERY = (
    "queryPlaylist",
    "908a5597b4d0af0489a9ad6a2d41bc3b416ff47c0884016d92bbd6822d0eb6d8",
)
_TRACK_QUERY = (
    "queryTrack",
    "cc31bfe16d74df1e9f6f880a908bb3880674deca34c8b67576ecbf8246e967ba",
)


# ── output helpers ──────────────────────────────────────────────────────────

def emit(event, **payload):
    payload["event"] = event
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def reply(**payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


# ── environment ─────────────────────────────────────────────────────────────

def _user_bin(name):
    found = shutil.which(name)
    if found:
        return found
    for candidate in (Path.home() / ".local/bin" / name, Path("/usr/local/bin") / name):
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def ytdlp_bin():
    return _user_bin("yt-dlp")


def ffmpeg_bin():
    return _user_bin("ffmpeg")


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
    return ["--cookies-from-browser", browser] if browser else []


def settings_path():
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base / "quickshell/spotify-downloader.json"


def load_settings():
    try:
        value = json.loads(settings_path().read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_settings(data):
    path = settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def output_directory():
    override = os.environ.get("QS_SPOTIFY_DOWNLOAD_DIR", "").strip()
    configured = str(load_settings().get("outputDir", "")).strip()
    return Path(override or configured or (Path.home() / "Music/Spotify")).expanduser()


# ── Spotify metadata (public embed page + oEmbed, no auth) ───────────────────

def _http_get(url, timeout=15):
    request = urllib.request.Request(url, headers={"User-Agent": _UA})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def _http_json(url, payload=None, token="", timeout=20):
    headers = {"Accept": "application/json", "User-Agent": _UA}
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload, separators=(",", ":")).encode()
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _kind_from_url(url):
    lowered = url.lower()
    for kind in ("playlist", "album", "artist", "track"):
        if "/" + kind + "/" in lowered or ":" + kind + ":" in lowered:
            return kind
    return "track"


def _spotify_id(url):
    match = re.search(r"(?:/|:)(track|album|playlist|artist)(?:/|:)([A-Za-z0-9]+)", url)
    return match.group(2) if match else ""


def _open_url(kind, sid):
    return "https://open.spotify.com/{}/{}".format(kind, sid)


def _clean(text):
    return (text or "").replace("\xa0", " ").strip()


def _image_sources(node):
    if isinstance(node, list):
        for value in node:
            yield from _image_sources(value)
    elif isinstance(node, dict):
        if node.get("url"):
            yield node
        for key in ("sources", "image", "items"):
            if key in node:
                yield from _image_sources(node[key])


def _best_image(node):
    sources = list(_image_sources(node))
    if not sources:
        return ""
    best = max(sources, key=lambda source: (
        source.get("width") or source.get("maxWidth")
        or source.get("height") or source.get("maxHeight") or 0
    ))
    return str(best.get("url") or "")


def _cover_from_entity(entity):
    for key in ("coverArt", "visualIdentity", "images"):
        cover = _best_image(entity.get(key))
        if cover:
            return cover
    return ""


def _oembed_cover(spotify_url):
    try:
        quoted = urllib.parse.quote(spotify_url, safe="")
        data = json.loads(_http_get("https://open.spotify.com/oembed?url=" + quoted, 10))
        return data.get("thumbnail_url", "") or ""
    except Exception:
        return ""


def _embed_state(kind, sid):
    last = None
    for _ in range(3):
        try:
            html = _http_get("https://open.spotify.com/embed/{}/{}".format(kind, sid))
            match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
            if not match:
                raise ValueError("embed payload not found")
            data = json.loads(match.group(1))
            state = (((data.get("props") or {}).get("pageProps") or {}).get("state") or {})
            if (state.get("data") or {}).get("entity"):
                return state
            last = ValueError("embed state missing")
        except Exception as error:
            last = error
        time.sleep(0.6)
    raise last or ValueError("embed state unavailable")


def _embed_entity(kind, sid):
    return (_embed_state(kind, sid).get("data") or {}).get("entity") or {}


def _pathfinder(token, operation, query_hash, variables):
    response = _http_json(_PATHFINDER_URL, {
        "operationName": operation,
        "variables": variables,
        "extensions": {"persistedQuery": {"version": 1, "sha256Hash": query_hash}},
    }, token=token)
    errors = response.get("errors") or []
    if errors:
        messages = "; ".join(str(error.get("message") or error) for error in errors)
        raise ValueError(messages or "Spotify metadata request failed")
    return response.get("data") or {}


def _artist_names(node):
    if isinstance(node, dict):
        node = node.get("items") or node.get("contributors", {}).get("items") or []
    names = []
    for artist in node or []:
        profile = artist.get("profile") or {}
        name = _clean(artist.get("name") or profile.get("name"))
        if name:
            names.append(name)
    return names


def _pathfinder_track(item):
    item = item or {}
    v2 = (item.get("itemV2") or {}).get("data") or {}
    v3 = (item.get("itemV3") or {}).get("data") or {}
    data = v2 or v3 or item
    identity = v3.get("identityTrait") or data.get("identityTrait") or {}
    title = _clean(data.get("name") or identity.get("name"))
    artists = _artist_names(data.get("artists") or [])
    if not artists:
        artists = _artist_names(identity.get("contributors") or {})
    album = data.get("albumOfTrack") or data.get("album") or {}
    uri = str(data.get("uri") or identity.get("uri") or "")
    if not title:
        return None
    kind = "episode" if ":episode:" in uri else "track"
    sid = uri.rsplit(":", 1)[-1] if ":" in uri else ""
    return {
        "title": title,
        "artists": _clean(", ".join(artists)),
        "album": _clean(album.get("name")),
        "cover": _best_image(album.get("coverArt") or data.get("coverArt")),
        "spotify_url": _open_url(kind, sid) if sid else "",
    }


def _playlist_tracks(sid, token):
    operation, query_hash = _PLAYLIST_QUERY
    offset = 0
    total = None
    tracks = []
    playlist = {}
    seen_offsets = set()

    while total is None or offset < total:
        if offset in seen_offsets:
            raise ValueError("Spotify playlist pagination stopped advancing")
        seen_offsets.add(offset)
        data = _pathfinder(token, operation, query_hash, {
            "uri": "spotify:playlist:" + sid,
            "offset": offset,
            "limit": 100,
        })
        playlist = data.get("playlistV2") or {}
        if playlist.get("__typename") in ("NotFound", "GenericError"):
            raise ValueError(playlist.get("message") or "Spotify playlist unavailable")
        content = playlist.get("content") or {}
        items = content.get("items") or []
        total = int(content.get("totalCount") or 0)
        for item in items:
            track = _pathfinder_track(item)
            if track:
                tracks.append(track)

        paging = content.get("pagingInfo") or {}
        next_offset = paging.get("nextOffset")
        if next_offset is None and offset + len(items) < total:
            next_offset = offset + len(items)
        if next_offset is None:
            break
        next_offset = int(next_offset)
        if not items or next_offset <= offset:
            raise ValueError("Spotify playlist pagination returned an incomplete page")
        offset = next_offset

    return {
        "kind": "playlist",
        "title": _clean(playlist.get("name")),
        "cover": _best_image(playlist.get("images")),
        "count": len(tracks),
        "truncated": False,
    }, tracks


def _single_track(sid, token):
    operation, query_hash = _TRACK_QUERY
    data = _pathfinder(token, operation, query_hash, {"uri": "spotify:track:" + sid})
    entity = data.get("trackUnion") or {}
    track = _pathfinder_track(entity)
    if not track:
        raise ValueError(entity.get("message") or "Spotify track unavailable")
    return track


def resolve_tracks(url):
    """→ (meta, tracks), with every playlist page and canonical album metadata."""
    kind = _kind_from_url(url)
    sid = _spotify_id(url)
    if not sid:
        raise ValueError("invalid Spotify URL")
    state = _embed_state(kind, sid)
    entity = (state.get("data") or {}).get("entity") or {}
    session = ((state.get("settings") or {}).get("session") or {})
    token = str(session.get("accessToken") or "")
    title = _clean(entity.get("title"))
    cover = _cover_from_entity(entity)

    if kind == "playlist":
        if not token:
            raise ValueError("Spotify anonymous session token unavailable")
        meta, tracks = _playlist_tracks(sid, token)
        meta["title"] = meta["title"] or title
        meta["cover"] = meta["cover"] or cover
        return meta, tracks

    if kind == "track":
        if token:
            try:
                track = _single_track(sid, token)
                return ({"kind": kind, "title": track["title"], "cover": track["cover"],
                         "count": 1, "truncated": False}, [track])
            except Exception:
                pass
        names = [a.get("name", "") for a in (entity.get("artists") or []) if a.get("name")]
        artists = _clean(", ".join(names)) or _clean(entity.get("subtitle"))
        track = {"title": title, "artists": artists,
                 "album": "", "cover": cover, "spotify_url": _open_url("track", sid)}
        return {"kind": kind, "title": title, "cover": cover, "count": 1, "truncated": False}, [track]

    album_name = title if kind == "album" else ""
    shared_cover = cover if kind == "album" else ""
    tracks = []
    for item in entity.get("trackList", []):
        tid = (item.get("uri") or "").split(":")[-1]
        tracks.append({
            "title": _clean(item.get("title")),
            "artists": _clean(item.get("subtitle")),
            "album": album_name,
            "cover": shared_cover,
            "spotify_url": _open_url("track", tid) if tid else "",
        })
    return ({"kind": kind, "title": title, "cover": cover,
             "count": len(tracks), "truncated": False}, tracks)


# ── tagging (ffmpeg) ─────────────────────────────────────────────────────────

def _safe_name(text):
    text = re.sub(r"[\x00-\x1f/\\]", "_", text).strip()
    text = re.sub(r"\s+", " ", text)
    return (text[:180] or "track")


def _ytmusic_song_search(track):
    query = " ".join(filter(None, (
        _clean(track.get("artists")),
        _clean(track.get("title")),
        _clean(track.get("album")),
    )))
    return "https://music.youtube.com/search?" + urllib.parse.urlencode({
        "q": query,
        "sp": _YTMUSIC_SONGS_FILTER,
    })


def _track_output_path(track, fmt, out_dir):
    label = "{} - {}".format(track.get("artists", ""), track.get("title", "")).strip(" -")
    return Path(out_dir) / "{}.{}".format(_safe_name(label), fmt)


def _opus_picture_tag(image_bytes, mime=b"image/jpeg"):
    """Base64 FLAC picture block for an Opus/Ogg METADATA_BLOCK_PICTURE tag."""
    block = struct.pack(">i", 3)                       # type 3 = front cover
    block += struct.pack(">i", len(mime)) + mime
    block += struct.pack(">i", 0)                      # description length
    block += struct.pack(">iiii", 0, 0, 0, 0)          # w, h, depth, colours
    block += struct.pack(">i", len(image_bytes)) + image_bytes
    return base64.b64encode(block).decode()


def _artwork_mime(image_bytes):
    if image_bytes.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(image_bytes) >= 12 and image_bytes[:4] == b"RIFF" and image_bytes[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("unsupported album artwork")


def _tag_wav(path, cover_path, track):
    from mutagen.id3 import APIC, TALB, TIT2, TPE1, TPE2
    from mutagen.wave import WAVE

    audio = WAVE(path)
    if audio.tags is None:
        audio.add_tags()
    frames = (
        ("TIT2", TIT2, track.get("title")),
        ("TPE1", TPE1, track.get("artists")),
        ("TALB", TALB, track.get("album")),
        ("TPE2", TPE2, track.get("artists") if track.get("album") else ""),
    )
    for frame_id, frame_type, value in frames:
        if not value:
            continue
        audio.tags.delall(frame_id)
        audio.tags.add(frame_type(encoding=3, text=[str(value)]))
    if cover_path and os.path.exists(cover_path):
        image_bytes = Path(cover_path).read_bytes()
        audio.tags.delall("APIC")
        audio.tags.add(APIC(
            encoding=3,
            mime=_artwork_mime(image_bytes),
            type=3,
            desc="Cover",
            data=image_bytes,
        ))
    audio.save(v2_version=3)


def _tag_file(ffmpeg, source, cover_path, track, fmt, dest):
    meta = ["-metadata", "title=" + track["title"],
            "-metadata", "artist=" + track["artists"]]
    if track.get("album"):
        meta += ["-metadata", "album=" + track["album"],
                 "-metadata", "album_artist=" + track["artists"]]

    cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", source]
    have_cover = bool(cover_path and os.path.exists(cover_path))

    if fmt == "opus" and have_cover:
        try:
            image_bytes = Path(cover_path).read_bytes()
            tag = _opus_picture_tag(image_bytes, _artwork_mime(image_bytes).encode())
            cmd += ["-map", "0:a", "-c:a", "copy", "-map_metadata", "-1",
                    *meta, "-metadata", "METADATA_BLOCK_PICTURE=" + tag, dest]
        except Exception:
            cmd += ["-map", "0:a", "-c:a", "copy", "-map_metadata", "-1", *meta, dest]
    elif have_cover and fmt in ("mp3", "m4a", "flac"):
        cmd += ["-i", cover_path, "-map", "0:a", "-map", "1:v",
                "-c:a", "copy", "-c:v", "copy", "-disposition:v", "attached_pic",
                "-map_metadata", "-1", *meta]
        if fmt == "mp3":
            cmd += ["-id3v2_version", "3"]
        cmd += [dest]
    else:
        cmd += ["-map", "0:a", "-c:a", "copy", "-map_metadata", "-1", *meta, dest]

    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    if fmt == "wav":
        _tag_wav(dest, cover_path if have_cover else "", track)


def _retag_existing(ffmpeg, path, cover_path, track, fmt, tmp):
    if fmt == "wav":
        _tag_wav(path, cover_path, track)
        return
    tagged = tmp / ("retag." + fmt)
    tagged.unlink(missing_ok=True)
    _tag_file(ffmpeg, str(path), cover_path, track, fmt, str(tagged))
    os.replace(tagged, path)


# ── download ─────────────────────────────────────────────────────────────────

def _preexec():
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
    except Exception:
        pass


def _fetch_cover(url, dest):
    if not url:
        return False
    try:
        request = urllib.request.Request(url, headers={"User-Agent": _UA})
        with urllib.request.urlopen(request, timeout=15) as response:
            image_bytes = response.read()
        _artwork_mime(image_bytes)
        dest.write_bytes(image_bytes)
        return dest.stat().st_size > 0
    except Exception:
        return False


def _download_one(ytdlp, ffmpeg, track, fmt, bitrate, out_dir, tmp, cookies=(),
                  replace_existing=False):
    """Search + download + tag one track.
    Returns (status, path) with status in {'done', 'skipped', 'failed'}."""
    query = "{} - {}".format(track["artists"], track["title"]).strip(" -")
    if not query:
        return ("failed", None)

    dest = _track_output_path(track, fmt, out_dir)
    cover_url = track.get("cover") or _oembed_cover(track.get("spotify_url", ""))
    cover_path = tmp / "cover.img"
    cover_path.unlink(missing_ok=True)
    have_cover = _fetch_cover(cover_url, cover_path)

    if dest.exists() and dest.stat().st_size > 0 and not replace_existing:
        try:
            _retag_existing(
                ffmpeg, dest, str(cover_path) if have_cover else "", track, fmt, tmp
            )
        except Exception:
            pass
        return ("skipped", dest)

    quality = bitrate if (bitrate and bitrate != "auto") else "0"
    work = tmp / "audio.%(ext)s"
    for stale in tmp.glob("audio.*"):
        stale.unlink()
    cmd = [
        ytdlp, *cookies,
        "--playlist-items", "1", "--no-warnings", "--no-progress",
        "--format", "bestaudio/best",
        "-x", "--audio-format", fmt, "--audio-quality", quality,
        "-o", str(work),
        _ytmusic_song_search(track),
    ]
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                            text=True, preexec_fn=_preexec)
    produced = next(iter(tmp.glob("audio." + fmt)), None) or next(iter(tmp.glob("audio.*")), None)
    if result.returncode != 0 or not produced:
        return ("failed", None)

    try:
        _tag_file(
            ffmpeg, str(produced), str(cover_path) if have_cover else "", track, fmt, str(dest)
        )
    except Exception:
        shutil.move(str(produced), str(dest))   # tagging failed → keep the audio
    leftover = tmp / ("audio." + fmt)
    if leftover.exists():
        leftover.unlink()
    return ("done", dest)


def cmd_download(args):
    ytdlp = ytdlp_bin()
    ffmpeg = ffmpeg_bin()
    if not ytdlp or not ffmpeg:
        emit("error", message="yt-dlp and ffmpeg are required.")
        return
    url = (args.input or "").strip()
    if not url or ("spotify.com" not in url and not url.startswith("spotify:")):
        emit("error", message="Not a Spotify link.")
        return
    fmt = args.audio_format if args.audio_format in AUDIO_FORMATS else "opus"
    browsers = available_browsers()
    try:
        browser = resolved_browser(args.browser, browsers)
        cookies = cookie_args(args.browser, browsers)
    except ValueError as error:
        emit("error", message=str(error))
        return
    out_dir = output_directory()
    out_dir.mkdir(parents=True, exist_ok=True)
    download_settings = load_settings()
    source_files = download_settings.get("sourceFiles") or {}
    if not isinstance(source_files, dict):
        source_files = {}

    emit("starting", outputDir=str(out_dir), cookieSource=browser,
         playlist=_kind_from_url(url) in ("album", "playlist"))
    emit("processing", message="Reading Spotify…")

    try:
        meta, tracks = resolve_tracks(url)
    except Exception:
        emit("error", message="Could not read this Spotify link.")
        return
    total = len(tracks)
    if total == 0:
        emit("error", message="No tracks found in this Spotify link.")
        return

    done = 0
    skipped = 0
    failed = 0
    last_title = ""
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        for index, track in enumerate(tracks, start=1):
            last_title = "{} - {}".format(track["artists"], track["title"]).strip(" -")
            destination = _track_output_path(track, fmt, out_dir)
            replace_existing = (
                destination.exists()
                and source_files.get(str(destination)) != _SOURCE_VERSION
            )
            emit("item", title=last_title, index=index, count=total)
            emit("progress", progress=(index - 1) / total * 100.0,
                 index=index, count=total, title=last_title)
            try:
                status, path = _download_one(
                    ytdlp, ffmpeg, track, fmt, args.bitrate, out_dir, tmp, cookies,
                    replace_existing
                )
            except Exception:
                status, path = "failed", None
            if status == "done":
                done += 1
                source_files[str(path)] = _SOURCE_VERSION
                download_settings["sourceFiles"] = source_files
                save_settings(download_settings)
                emit("itemCompleted", completed=done + skipped, path=str(path))
            elif status == "skipped":
                skipped += 1
                emit("itemCompleted", completed=done + skipped, path=str(path), skipped=True)
            else:
                failed += 1
            emit("progress", progress=index / total * 100.0,
                 index=index, count=total, title=last_title)

    saved = done + skipped
    if saved > 0:
        emit("completed", outputDir=str(out_dir), files=saved,
             downloaded=done, skipped=skipped, failed=failed,
             truncated=bool(meta.get("truncated")),
             playlist=saved != 1, path=str(out_dir), mediaInfo={})
    else:
        emit("error", message="No tracks could be downloaded (no YouTube match found).")


# ── commands ────────────────────────────────────────────────────────────────

def cmd_status(_args):
    ready = ytdlp_bin() is not None and ffmpeg_bin() is not None
    browsers = available_browsers()
    reply(ok=ready, outputDir=str(output_directory()), browsers=browsers,
          autoBrowser=resolved_browser("auto", browsers))


def cmd_set_output(args):
    path = (args.path or "").strip()
    if not path:
        reply(ok=False, error="No folder selected.")
        return
    resolved = Path(path).expanduser()
    settings = load_settings()
    settings["outputDir"] = str(resolved)
    save_settings(settings)
    reply(ok=True, outputDir=str(resolved))


def cmd_info(args):
    url = (args.input or "").strip()
    if not url:
        reply(ok=False, error="No Spotify URL provided.")
        return
    if "spotify.com" not in url and not url.startswith("spotify:"):
        reply(ok=False, error="Not a Spotify link.")
        return
    kind = _kind_from_url(url)
    try:
        meta, tracks = resolve_tracks(url)
        reply(ok=True, kind=meta["kind"], isPlaylist=meta["kind"] in ("album", "playlist"),
              title=meta["title"] or ("Spotify " + kind),
              uploader="", entryCount=len(tracks),
              truncated=bool(meta.get("truncated")),
              thumbnail=meta.get("cover") or _oembed_cover(url), duration=0)
    except Exception:
        # embed parse failed → minimal answer from oEmbed + URL kind
        title = ""
        thumb = ""
        try:
            quoted = urllib.parse.quote(url.split("?")[0], safe="")
            data = json.loads(_http_get("https://open.spotify.com/oembed?url=" + quoted, 10))
            title = str(data.get("title") or "")
            thumb = str(data.get("thumbnail_url") or "")
        except Exception:
            pass
        reply(ok=True, kind=kind, isPlaylist=kind in ("album", "playlist"),
              title=title or ("Spotify " + kind), uploader="",
              entryCount=0, truncated=False, thumbnail=thumb, duration=0)


# ── entry point ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Spotify downloader backend (yt-dlp).")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status")

    info = sub.add_parser("info")
    info.add_argument("--input", required=True)

    download = sub.add_parser("download")
    download.add_argument("--input", required=True)
    download.add_argument("--audio-format", default="opus", dest="audio_format",
                          choices=tuple(sorted(AUDIO_FORMATS)))
    download.add_argument("--bitrate", default="auto")
    download.add_argument("--browser", default="auto")

    set_output = sub.add_parser("set-output")
    set_output.add_argument("--path", required=True)

    args = parser.parse_args()
    {
        "status": cmd_status,
        "info": cmd_info,
        "download": cmd_download,
        "set-output": cmd_set_output,
    }[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
    except KeyboardInterrupt:
        pass
