import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
APP_ICON = ROOT / "desktop" / "icons" / "AppIcon.qml"
FALLBACK_SERVICE = ROOT / "desktop" / "icons" / "IconFallbackService.qml"
RESOLVER = ROOT / "scripts" / "resolve-app-icon.py"


def load_resolver():
    spec = importlib.util.spec_from_file_location("resolve_app_icon", RESOLVER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AppIconHotplugGuards(unittest.TestCase):
    def test_named_icons_do_not_reenter_quickshell_icon_provider(self):
        source = APP_ICON.read_text(encoding="utf-8")

        self.assertIn('icon.startsWith("image://icon/")', source)
        self.assertNotIn('return "image://icon/" + icon', source)
        self.assertIn("cache: true", source)
        self.assertIn("asynchronous: false", source)

    def test_empty_resolution_does_not_restore_provider_fallback(self):
        source = FALLBACK_SERVICE.read_text(encoding="utf-8")

        self.assertIn('let value = response.value || ""', source)
        self.assertNotIn(
            'root._output || "image://icon/application-x-executable"', source
        )

    def test_resolver_stays_alive_and_keeps_its_index_in_memory(self):
        source = FALLBACK_SERVICE.read_text(encoding="utf-8")

        self.assertIn('"--server"', source)
        self.assertIn("stdinEnabled: true", source)
        self.assertIn('resolver.write(JSON.stringify(root._active) + "\\n")', source)

    def test_provider_query_is_removed_before_file_lookup(self):
        resolver = load_resolver()

        self.assertEqual(
            resolver.clean_icon_name(
                "image://icon/input-mouse?path=/tmp/application-icons"
            ),
            "input-mouse",
        )

    def test_selected_theme_alias_wins_over_hicolor_exact_name(self):
        resolver = load_resolver()

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = root / "WhiteSur"
            inherited = root / "hicolor"
            selected.mkdir()
            inherited.mkdir()
            (selected / "app-class.svg").write_text("<svg/>", encoding="utf-8")
            (inherited / "advertised-name.svg").write_text("<svg/>", encoding="utf-8")

            match = resolver.find_in_roots(
                ["advertised-name", "app-class"], [selected, inherited]
            )

        self.assertEqual(match.name, "app-class.svg")

    def test_directly_pinned_icon_remains_authoritative(self):
        resolver = load_resolver()

        with tempfile.TemporaryDirectory() as directory:
            icon = Path(directory) / "custom.png"
            icon.write_bytes(b"custom")

            self.assertEqual(resolver.direct_path(icon.as_uri()), icon)

    def test_scalable_theme_art_wins_over_fixed_size_svg(self):
        resolver = load_resolver()

        with tempfile.TemporaryDirectory() as directory:
            theme = Path(directory)
            small = theme / "places" / "16x16"
            scalable = theme / "places" / "scalable"
            small.mkdir(parents=True)
            scalable.mkdir(parents=True)
            (small / "user-trash.svg").write_text("<svg/>", encoding="utf-8")
            expected = scalable / "user-trash.svg"
            expected.write_text("<svg/>", encoding="utf-8")

            match = resolver.find_named("user-trash", [theme])

        self.assertEqual(match, expected)

    def test_theme_index_is_reused_until_theme_directory_changes(self):
        resolver = load_resolver()

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            theme = root / "WhiteSur"
            apps = theme / "apps" / "scalable"
            cache = root / "cache"
            apps.mkdir(parents=True)
            (theme / "index.theme").write_text(
                "[Icon Theme]\nDirectories=apps/scalable\n", encoding="utf-8"
            )
            expected = apps / "kitty.svg"
            expected.write_text("<svg/>", encoding="utf-8")

            with mock.patch.dict(os.environ, {"QS_ICON_CACHE_DIR": str(cache)}):
                first = resolver.find_theme_icon(["kitty"], "WhiteSur", [theme])
                with mock.patch.object(
                    resolver, "build_theme_index",
                    side_effect=AssertionError("warm lookup rebuilt the index"),
                ):
                    second = resolver.find_theme_icon(["kitty"], "WhiteSur", [theme])

                added = apps / "new-app.svg"
                added.write_text("<svg/>", encoding="utf-8")
                resolver._MEMORY_THEME_INDICES.clear()
                third = resolver.find_theme_icon(["new-app"], "WhiteSur", [theme])

        self.assertEqual(first, expected)
        self.assertEqual(second, expected)
        self.assertEqual(third, added)

    def test_dock_icons_skip_ahead_of_hidden_launchpad_requests(self):
        app_icon = APP_ICON.read_text(encoding="utf-8")
        service = FALLBACK_SERVICE.read_text(encoding="utf-8")
        dock_item = (ROOT / "desktop" / "dock" / "DockItem.qml").read_text(
            encoding="utf-8"
        )
        trash_item = (ROOT / "desktop" / "dock" / "TrashItem.qml").read_text(
            encoding="utf-8"
        )

        self.assertIn("property int resolvePriority: 0", app_icon)
        self.assertIn("request.priority >", service)
        self.assertIn("resolvePriority: 100", dock_item)
        self.assertIn("resolvePriority: 100", trash_item)


if __name__ == "__main__":
    unittest.main()
