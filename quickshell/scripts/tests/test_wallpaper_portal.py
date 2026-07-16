import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "wallpaper-portal.py"
SPEC = importlib.util.spec_from_file_location("wallpaper_portal", MODULE_PATH)
wallpaper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wallpaper)


class WallpaperPortalTests(unittest.TestCase):
    def test_rejects_non_file_uri(self):
        self.assertIsNone(wallpaper.path_from_uri("https://example.com/a.jpg"))

    def test_persists_selected_file_by_content_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source = base / "source.jpg"
            source.write_bytes(b"wallpaper bytes")

            with mock.patch.object(wallpaper, "WALLPAPER_DIR", base / "stored"):
                first = wallpaper.persist_wallpaper(source)
                second = wallpaper.persist_wallpaper(source)

            self.assertEqual(first, second)
            self.assertEqual(first.read_bytes(), b"wallpaper bytes")
            self.assertEqual(first.suffix, ".jpg")

    def test_applies_persisted_file_with_current_gnome_options(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source = base / "source.png"
            source.write_bytes(b"png bytes")
            helper = base / "wallpaper.sh"
            helper.write_text("#!/bin/sh\n")

            completed = mock.Mock(returncode=0)
            with (
                mock.patch.object(wallpaper, "WALLPAPER_DIR", base / "stored"),
                mock.patch.object(wallpaper, "WALLPAPER_SH", helper),
                mock.patch.object(
                    wallpaper,
                    "choose_wallpaper_options",
                    return_value=("fit", "#123456"),
                ),
                mock.patch.object(wallpaper.subprocess, "run", return_value=completed) as run,
            ):
                response = wallpaper.set_wallpaper(source.as_uri(), {"set-on": "background"})

            self.assertEqual(response, 0)
            command = run.call_args.args[0]
            self.assertEqual(command[0], str(helper))
            self.assertTrue(Path(command[1]).is_file())
            self.assertEqual(command[2:], ["fit", "#123456"])

    def test_cancel_does_not_copy_or_apply_wallpaper(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source = base / "source.png"
            source.write_bytes(b"png bytes")
            helper = base / "wallpaper.sh"
            helper.write_text("#!/bin/sh\n")

            with (
                mock.patch.object(wallpaper, "WALLPAPER_DIR", base / "stored"),
                mock.patch.object(wallpaper, "WALLPAPER_SH", helper),
                mock.patch.object(wallpaper, "choose_wallpaper_options", return_value=None),
                mock.patch.object(wallpaper.subprocess, "run") as run,
            ):
                response = wallpaper.set_wallpaper(source.as_uri())

            self.assertEqual(response, 1)
            self.assertFalse((base / "stored").exists())
            run.assert_not_called()

    def test_rejects_lockscreen_only_request(self):
        self.assertEqual(
            wallpaper.set_wallpaper("file:///does/not/matter", {"set-on": "lockscreen"}),
            2,
        )


if __name__ == "__main__":
    unittest.main()
