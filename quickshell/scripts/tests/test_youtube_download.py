import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "youtube-download.py"
SPEC = importlib.util.spec_from_file_location("youtube_download", MODULE_PATH)
youtube = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(youtube)


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


if __name__ == "__main__":
    unittest.main()
