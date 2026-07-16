import base64
import importlib.util
import json
import pathlib
import struct
import tempfile
import types
import unittest
import wave
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "youtube-download.py"
SPEC = importlib.util.spec_from_file_location("youtube_download", MODULE_PATH)
youtube = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(youtube)

PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def write_test_wav(path):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(b"\0" * 400)


class YoutubeDownloadTests(unittest.TestCase):
    def test_normalizes_video_id(self):
        self.assertEqual(
            youtube.normalize_input("dQw4w9WgXcQ"),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        )

    def test_rejects_non_youtube_url(self):
        with self.assertRaises(ValueError):
            youtube.normalize_input("https://example.com/video")

    def test_video_quality_selector(self):
        self.assertEqual(
            youtube.video_selector("1080"),
            "bv*[height<=1080]+ba/b[height<=1080]",
        )

    def test_audio_output_formats_use_best_quality(self):
        for output_format in ("wav", "flac", "m4a", "mp3"):
            options = youtube.audio_options(output_format)
            self.assertIn(output_format, options)
            self.assertEqual(options[-1], "0")

    def test_playlist_audio_metadata_has_album_and_track_fallbacks(self):
        options = youtube.audio_metadata_options(playlist=True)
        self.assertIn("%(album,playlist_title)s:%(meta_album)s", options)
        self.assertIn("%(album_artist,artist,uploader)s:%(meta_album_artist)s", options)
        self.assertIn("%(track_number,playlist_index)s:%(meta_track)s", options)

    def test_rejects_bitrate_as_audio_output(self):
        with self.assertRaises(ValueError):
            youtube.audio_options("256")

    def test_normalizes_music_title_and_artist(self):
        self.assertEqual(youtube.clean_music_title("LOVE THING (LOVE THING)"), "LOVE THING")
        self.assertEqual(youtube.clean_music_artist("woo!ah! - Topic"), "woo!ah!")

    def test_audio_filename_uses_title_then_uploader(self):
        template = youtube.output_template(pathlib.Path("/tmp"), "audio")
        self.assertTrue(template.endswith("%(title)s - %(uploader)s.%(ext)s"))

    def test_ratio_value(self):
        self.assertEqual(youtube.ratio_value("60000/1001"), 59.94)
        self.assertEqual(youtube.ratio_value("0/0"), 0)

    def test_detects_browser_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            (pathlib.Path(directory) / ".config/chromium").mkdir(parents=True)
            self.assertIn("chromium", youtube.available_browsers(directory))

    def test_resolves_automatic_browser(self):
        with mock.patch.object(youtube, "default_browser", return_value="firefox"):
            self.assertEqual(youtube.resolved_browser("auto", ["chrome", "firefox"]), "firefox")

    def test_maps_default_browser_desktop_entry(self):
        self.assertEqual(youtube.browser_from_desktop_entry("firefox.desktop"), "firefox")
        self.assertEqual(youtube.browser_from_desktop_entry("com.google.Chrome.desktop"), "chrome")

    def test_detects_playlist_urls(self):
        self.assertTrue(youtube.is_playlist_url("https://www.youtube.com/playlist?list=PL123"))
        self.assertTrue(youtube.is_playlist_url("https://www.youtube.com/watch?v=abc&list=PL123"))
        self.assertTrue(youtube.is_playlist_url("https://music.youtube.com/playlist?list=PL123"))
        self.assertFalse(youtube.is_playlist_url("https://www.youtube.com/watch?v=abc"))

    def test_detects_music_urls(self):
        self.assertTrue(youtube.is_music_url("https://music.youtube.com/watch?v=oP-WPpwBz80"))
        self.assertFalse(youtube.is_music_url("https://www.youtube.com/watch?v=oP-WPpwBz80"))

    def test_playlist_base_command(self):
        with mock.patch.object(youtube.shutil, "which", return_value="/usr/bin/yt-dlp"):
            with mock.patch.object(youtube, "cookie_args", return_value=[]):
                self.assertIn("--yes-playlist", youtube.base_command("none", True))

    def test_persists_output_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            state = pathlib.Path(directory) / "state"
            output = pathlib.Path(directory) / "downloads"
            with mock.patch.dict("os.environ", {"XDG_STATE_HOME": str(state)}, clear=False):
                youtube.set_output_directory(output)
                self.assertEqual(youtube.output_directory(), output)

    def test_embeds_mislabeled_png_as_wav_front_cover(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            audio = directory / "track.wav"
            cover = directory / "cover.jpg"
            write_test_wav(audio)
            cover.write_bytes(PNG_1PX)

            self.assertEqual(youtube.embed_wav_artwork(audio, cover), "image/png")
            tag = youtube._wav_id3(audio)
            _version, _flags, _prefix, frames, _padding = youtube._id3_parts(tag)
            pictures = [raw for frame_id, raw in frames if frame_id == b"APIC"]
            self.assertEqual(len(pictures), 1)
            self.assertIn(b"image/png\0\x03Cover\0", pictures[0])
            self.assertTrue(pictures[0].endswith(PNG_1PX))
            self.assertEqual(struct.unpack("<I", audio.read_bytes()[4:8])[0], audio.stat().st_size - 8)

    def test_reembedding_replaces_apic_and_keeps_one_id3_chunk(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            audio = directory / "track.wav"
            first = directory / "first.png"
            second = directory / "second.jpg"
            write_test_wav(audio)
            first.write_bytes(PNG_1PX)
            second.write_bytes(b"\xff\xd8\xff" + b"second-cover")
            youtube.embed_wav_artwork(audio, first)
            youtube.embed_wav_artwork(audio, second)

            _header, chunks = youtube._riff_chunks(audio)
            self.assertEqual(sum(chunk_id.lower() == b"id3 " for chunk_id, *_ in chunks), 1)
            tag = youtube._wav_id3(audio)
            _version, _flags, _prefix, frames, _padding = youtube._id3_parts(tag)
            pictures = [raw for frame_id, raw in frames if frame_id == b"APIC"]
            self.assertEqual(len(pictures), 1)
            self.assertIn(b"image/jpeg", pictures[0])
            self.assertNotIn(PNG_1PX, pictures[0])

    def test_playlist_cover_is_used_for_every_downloaded_wav(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            artwork = directory / "artwork"
            artwork.mkdir()
            (artwork / "playlist.jpg").write_bytes(PNG_1PX)
            (artwork / "entry-one.jpg").write_bytes(b"\xff\xd8\xffentry-one")
            records = []
            for video_id in ("one", "two"):
                audio = directory / f"{video_id}.wav"
                write_test_wav(audio)
                records.append((str(audio), video_id))

            self.assertEqual(youtube.embed_download_artwork(records, artwork, playlist=True), 2)
            for audio, _video_id in records:
                self.assertIn(PNG_1PX, youtube._wav_id3(audio))

    def test_media_details_ignores_attached_cover_stream(self):
        response = {
            "streams": [
                {"codec_type": "audio", "codec_name": "pcm_s16le", "sample_rate": "48000",
                 "channels": 2, "disposition": {"attached_pic": 0}},
                {"codec_type": "video", "codec_name": "png", "width": 640, "height": 640,
                 "disposition": {"attached_pic": 1}},
            ],
            "format": {"bit_rate": "1536000"},
        }
        completed = types.SimpleNamespace(returncode=0, stdout=json.dumps(response))
        with tempfile.NamedTemporaryFile(suffix=".wav") as audio:
            with mock.patch.object(youtube.shutil, "which", return_value="/usr/bin/ffprobe"):
                with mock.patch.object(youtube.subprocess, "run", return_value=completed):
                    details = youtube.media_details(audio.name)
        self.assertEqual(details["videoCodec"], "")
        self.assertEqual(details["width"], 0)
        self.assertEqual(details["audioBitrateKbps"], 1536)


if __name__ == "__main__":
    unittest.main()
