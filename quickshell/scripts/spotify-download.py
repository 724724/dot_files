#!/usr/bin/env python3
"""Spotify → YouTube downloader backend (no spotdl, no auth).

  1. Resolve the Spotify track/album/playlist to its track list from Spotify's
     public embed page (no login). NOTE: the embed exposes only the FIRST 100
     tracks — the authenticated Web API that would page further is geo-blocked
     from some regions (e.g. Korea → 403), so 100 is the practical cap here.
  2. Find each track on YouTube with `yt-dlp "ytsearch1:artist - title"` and
     download the best audio.
  3. Tag the file (title / artist / album / cover art) with ffmpeg from the
     Spotify metadata. Existing files are skipped, so a big list can be run in
     chunks / re-run to fill gaps.

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
_UA = "Mozilla/5.0"


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


def _cover_from_entity(entity):
    for key in ("coverArt", "visualIdentity"):
        node = entity.get(key) or {}
        sources = node.get("sources") or node.get("image") or []
        if sources:
            best = max(sources, key=lambda s: (s.get("width") or 0))
            if best.get("url"):
                return best["url"]
    return ""


def _oembed_cover(spotify_url):
    try:
        quoted = urllib.parse.quote(spotify_url, safe="")
        data = json.loads(_http_get("https://open.spotify.com/oembed?url=" + quoted, 10))
        return data.get("thumbnail_url", "") or ""
    except Exception:
        return ""


def _embed_entity(kind, sid):
    # The embed page occasionally serves a variant without the expected shape;
    # a couple of retries makes the preview reliable.
    last = None
    for _ in range(3):
        try:
            html = _http_get("https://open.spotify.com/embed/{}/{}".format(kind, sid))
            match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
            if not match:
                raise ValueError("embed payload not found")
            data = json.loads(match.group(1))
            entity = (((data.get("props") or {}).get("pageProps") or {})
                      .get("state") or {}).get("data", {}).get("entity")
            if entity:
                return entity
            last = ValueError("embed entity missing")
        except Exception as error:
            last = error
        time.sleep(0.6)
    raise last or ValueError("embed entity unavailable")


def resolve_tracks(url):
    """→ (meta, tracks) from the public embed page. meta['truncated'] is set when
    the embed's 100-track cap was hit. Each track: {title, artists, album, cover,
    spotify_url}; cover may be '' (fetched lazily per track at download time)."""
    kind = _kind_from_url(url)
    sid = _spotify_id(url)
    entity = _embed_entity(kind, sid)
    title = _clean(entity.get("title"))
    cover = _cover_from_entity(entity)

    if kind == "track":
        # A single-track embed carries the artists in an `artists` list; only the
        # album/playlist trackList items put the artist in `subtitle`.
        names = [a.get("name", "") for a in (entity.get("artists") or []) if a.get("name")]
        artists = _clean(", ".join(names)) or _clean(entity.get("subtitle"))
        track = {"title": title, "artists": artists,
                 "album": "", "cover": cover, "spotify_url": _open_url("track", sid)}
        return {"kind": kind, "title": title, "cover": cover, "count": 1, "truncated": False}, [track]

    album_name = title if kind == "album" else ""
    shared_cover = cover if kind == "album" else ""   # playlists → per-track cover
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
             "count": len(tracks), "truncated": len(tracks) >= 100}, tracks)


# ── tagging (ffmpeg) ─────────────────────────────────────────────────────────

def _safe_name(text):
    text = re.sub(r"[\x00-\x1f/\\]", "_", text).strip()
    text = re.sub(r"\s+", " ", text)
    return (text[:180] or "track")


def _opus_picture_tag(image_bytes, mime=b"image/jpeg"):
    """Base64 FLAC picture block for an Opus/Ogg METADATA_BLOCK_PICTURE tag."""
    block = struct.pack(">i", 3)                       # type 3 = front cover
    block += struct.pack(">i", len(mime)) + mime
    block += struct.pack(">i", 0)                      # description length
    block += struct.pack(">iiii", 0, 0, 0, 0)          # w, h, depth, colours
    block += struct.pack(">i", len(image_bytes)) + image_bytes
    return base64.b64encode(block).decode()


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
            tag = _opus_picture_tag(Path(cover_path).read_bytes())
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
            dest.write_bytes(response.read())
        return dest.stat().st_size > 0
    except Exception:
        return False


def _download_one(ytdlp, ffmpeg, track, fmt, bitrate, out_dir, tmp):
    """Search + download + tag one track.
    Returns (status, path) with status in {'done', 'skipped', 'failed'}."""
    query = "{} - {}".format(track["artists"], track["title"]).strip(" -")
    if not query:
        return ("failed", None)

    dest = out_dir / "{}.{}".format(_safe_name(query), fmt)
    # Already in the folder from a previous run → skip. Lets a big list be run in
    # chunks or re-run to fill gaps without re-downloading what's done.
    if dest.exists() and dest.stat().st_size > 0:
        return ("skipped", dest)

    quality = bitrate if (bitrate and bitrate != "auto") else "0"
    work = tmp / "audio.%(ext)s"
    for stale in tmp.glob("audio.*"):
        stale.unlink()
    cmd = [
        ytdlp, "ytsearch1:" + query,
        "--no-playlist", "--no-warnings", "--no-progress",
        "-x", "--audio-format", fmt, "--audio-quality", quality,
        "-o", str(work),
    ]
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                            text=True, preexec_fn=_preexec)
    produced = next(iter(tmp.glob("audio." + fmt)), None) or next(iter(tmp.glob("audio.*")), None)
    if result.returncode != 0 or not produced:
        return ("failed", None)

    cover_url = track.get("cover") or _oembed_cover(track.get("spotify_url", ""))
    cover_path = tmp / "cover.jpg"
    have = _fetch_cover(cover_url, cover_path)

    try:
        _tag_file(ffmpeg, str(produced), str(cover_path) if have else "", track, fmt, str(dest))
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
    out_dir = output_directory()
    out_dir.mkdir(parents=True, exist_ok=True)

    emit("starting", outputDir=str(out_dir),
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
            emit("item", title=last_title, index=index, count=total)
            emit("progress", progress=(index - 1) / total * 100.0,
                 index=index, count=total, title=last_title)
            try:
                status, path = _download_one(ytdlp, ffmpeg, track, fmt, args.bitrate, out_dir, tmp)
            except Exception:
                status, path = "failed", None
            if status == "done":
                done += 1
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
    reply(ok=ready, outputDir=str(output_directory()))


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
