import base64
import importlib.util
import pathlib
import tempfile
import types
import unittest
import urllib.parse
import wave
from unittest import mock

from mutagen.wave import WAVE


MODULE_PATH = pathlib.Path(__file__).parents[1] / "spotify-download.py"
SPEC = importlib.util.spec_from_file_location("spotify_download", MODULE_PATH)
spotify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spotify)

PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def playlist_item(index):
    return {
        "itemV2": {
            "data": {
                "name": f"Track {index}",
                "uri": f"spotify:track:id{index}",
                "artists": {"items": [{"profile": {"name": f"Artist {index}"}}]},
                "albumOfTrack": {
                    "name": f"Album {index}",
                    "coverArt": {
                        "sources": [
                            {"url": f"small-{index}", "width": 64},
                            {"url": f"large-{index}", "width": 640},
                        ]
                    },
                },
            }
        }
    }


def playlist_page(start, count, total, next_offset):
    return {
        "playlistV2": {
            "__typename": "Playlist",
            "name": "Full playlist",
            "images": {"items": [{"sources": [{"url": "playlist-cover"}]}]},
            "content": {
                "totalCount": total,
                "pagingInfo": {"nextOffset": next_offset},
                "items": [playlist_item(index) for index in range(start, start + count)],
            },
        }
    }


def write_test_wav(path):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(b"\0" * 400)


class SpotifyDownloadTests(unittest.TestCase):
    def test_detects_browser_profile_for_cookies(self):
        with tempfile.TemporaryDirectory() as directory:
            (pathlib.Path(directory) / ".mozilla/firefox").mkdir(parents=True)
            self.assertIn("firefox", spotify.available_browsers(directory))

    def test_resolves_automatic_browser_cookie_source(self):
        with mock.patch.object(spotify, "default_browser", return_value="firefox"):
            self.assertEqual(
                spotify.resolved_browser("auto", ["chrome", "firefox"]), "firefox"
            )
            self.assertEqual(
                spotify.cookie_args("auto", ["chrome", "firefox"]),
                ["--cookies-from-browser", "firefox"],
            )

    def test_selects_highest_resolution_image_with_max_width(self):
        entity = {
            "visualIdentity": {
                "image": [
                    {"url": "small", "maxWidth": 64},
                    {"url": "large", "maxWidth": 640},
                ]
            }
        }
        self.assertEqual(spotify._cover_from_entity(entity), "large")

    def test_pathfinder_track_keeps_album_and_album_art(self):
        track = spotify._pathfinder_track(playlist_item(7))
        self.assertEqual(track["title"], "Track 7")
        self.assertEqual(track["artists"], "Artist 7")
        self.assertEqual(track["album"], "Album 7")
        self.assertEqual(track["cover"], "large-7")

    def test_fetches_every_playlist_page_past_one_hundred(self):
        pages = [playlist_page(0, 100, 145, 100), playlist_page(100, 45, 145, None)]
        with mock.patch.object(spotify, "_pathfinder", side_effect=pages) as request:
            meta, tracks = spotify._playlist_tracks("playlist-id", "token")

        self.assertEqual(len(tracks), 145)
        self.assertEqual(tracks[0]["title"], "Track 0")
        self.assertEqual(tracks[100]["album"], "Album 100")
        self.assertEqual(tracks[-1]["cover"], "large-144")
        self.assertEqual(meta["count"], 145)
        self.assertFalse(meta["truncated"])
        self.assertEqual(meta["cover"], "playlist-cover")
        self.assertEqual([call.args[3]["offset"] for call in request.call_args_list], [0, 100])

    def test_exactly_one_hundred_tracks_is_not_truncated(self):
        with mock.patch.object(
            spotify, "_pathfinder", return_value=playlist_page(0, 100, 100, None)
        ):
            meta, tracks = spotify._playlist_tracks("playlist-id", "token")
        self.assertEqual(len(tracks), 100)
        self.assertFalse(meta["truncated"])

    def test_rejects_a_nonadvancing_playlist_page(self):
        with mock.patch.object(
            spotify, "_pathfinder", return_value=playlist_page(0, 0, 145, None)
        ):
            with self.assertRaises(ValueError):
                spotify._playlist_tracks("playlist-id", "token")

    def test_wav_tags_include_album_and_front_cover(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            audio_path = directory / "track.wav"
            cover_path = directory / "cover.png"
            write_test_wav(audio_path)
            cover_path.write_bytes(PNG_1PX)

            spotify._tag_wav(audio_path, cover_path, {
                "title": "Song",
                "artists": "Artist",
                "album": "Album",
            })

            tags = WAVE(audio_path).tags
            self.assertEqual(tags.getall("TIT2")[0].text, ["Song"])
            self.assertEqual(tags.getall("TPE1")[0].text, ["Artist"])
            self.assertEqual(tags.getall("TALB")[0].text, ["Album"])
            self.assertEqual(tags.getall("TPE2")[0].text, ["Artist"])
            pictures = tags.getall("APIC")
            self.assertEqual(len(pictures), 1)
            self.assertEqual(pictures[0].mime, "image/png")
            self.assertEqual(pictures[0].data, PNG_1PX)

    def test_existing_wav_is_retagged_without_downloading_again(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            destination = directory / "Artist - Song.wav"
            write_test_wav(destination)
            track = {
                "title": "Song",
                "artists": "Artist",
                "album": "Album",
                "cover": "https://example.test/cover",
                "spotify_url": "",
            }

            def fake_cover(_url, path):
                path.write_bytes(PNG_1PX)
                return True

            with mock.patch.object(spotify, "_fetch_cover", side_effect=fake_cover):
                with mock.patch.object(spotify.subprocess, "run") as run:
                    status, path = spotify._download_one(
                        "yt-dlp", "ffmpeg", track, "wav", "auto", directory, directory
                    )

            self.assertEqual(status, "skipped")
            self.assertEqual(path, destination)
            run.assert_not_called()
            tags = WAVE(destination).tags
            self.assertEqual(tags.getall("TALB")[0].text, ["Album"])
            self.assertEqual(len(tags.getall("APIC")), 1)

    def test_ytdlp_uses_music_songs_browser_cookies_and_best_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            calls = []

            def fake_run(command, *args, **kwargs):
                calls.append(command)
                if command[0] == "yt-dlp":
                    (directory / "audio.opus").write_bytes(b"audio")
                return types.SimpleNamespace(returncode=0, stderr="")

            track = {
                "title": "Song",
                "artists": "Artist",
                "album": "Album",
                "cover": "",
                "spotify_url": "",
            }
            with mock.patch.object(spotify, "_fetch_cover", return_value=False):
                with mock.patch.object(spotify.subprocess, "run", side_effect=fake_run):
                    status, _path = spotify._download_one(
                        "yt-dlp", "ffmpeg", track, "opus", "auto", directory, directory,
                        ["--cookies-from-browser", "firefox"],
                    )

            self.assertEqual(status, "done")
            command = calls[0]
            cookie_index = command.index("--cookies-from-browser")
            self.assertEqual(command[cookie_index + 1], "firefox")
            self.assertEqual(command[command.index("--format") + 1], "bestaudio/best")
            self.assertEqual(command[command.index("--playlist-items") + 1], "1")
            search = urllib.parse.urlparse(command[-1])
            parameters = urllib.parse.parse_qs(search.query)
            self.assertEqual(search.netloc, "music.youtube.com")
            self.assertEqual(search.path, "/search")
            self.assertEqual(parameters["q"], ["Artist Song Album"])
            self.assertEqual(parameters["sp"], [spotify._YTMUSIC_SONGS_FILTER])
            self.assertNotIn("ytsearch", command[-1])

    def test_unverified_existing_file_can_be_replaced_from_music(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            track = {
                "title": "Song",
                "artists": "Artist",
                "album": "Album",
                "cover": "",
                "spotify_url": "",
            }
            destination = directory / "Artist - Song.opus"
            destination.write_bytes(b"old-video-audio")
            calls = []

            def fake_run(command, *args, **kwargs):
                calls.append(command)
                if command[0] == "yt-dlp":
                    (directory / "audio.opus").write_bytes(b"music-audio")
                return types.SimpleNamespace(returncode=0, stderr="")

            with mock.patch.object(spotify, "_fetch_cover", return_value=False):
                with mock.patch.object(spotify.subprocess, "run", side_effect=fake_run):
                    status, path = spotify._download_one(
                        "yt-dlp", "ffmpeg", track, "opus", "auto", directory, directory,
                        ["--cookies-from-browser", "firefox"], replace_existing=True,
                    )

            self.assertEqual(status, "done")
            self.assertEqual(path, destination)
            self.assertEqual(calls[0][0], "yt-dlp")


if __name__ == "__main__":
    unittest.main()
