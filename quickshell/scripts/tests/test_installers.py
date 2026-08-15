import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).parents[2]
INSTALL_DIR = ROOT / "scripts" / "installs"


class InstallerLayoutTests(unittest.TestCase):
    def read(self, name):
        return (INSTALL_DIR / name).read_text(encoding="utf-8")

    def test_install_scripts_are_grouped_under_installs(self):
        expected = {
            "install-all.sh",
            "install-focus-sites.sh",
            "install-quickshell-lock-pam.sh",
            "install-quickshell-lock.sh",
            "install-stem-split.sh",
            "install-stock-worker.sh",
            "install-wallpaper-portal.sh",
            "set-user-avatar.sh",
        }
        self.assertTrue(expected.issubset({path.name for path in INSTALL_DIR.iterdir()}))

        script_root = ROOT / "scripts"
        leftovers = {
            path.name
            for path in script_root.iterdir()
            if path.is_file()
            and (path.name.startswith("install-") or path.name.startswith("setup-"))
        }
        self.assertEqual(leftovers, set())

    def test_aggregate_installer_runs_every_component(self):
        source = self.read("install-all.sh")
        for installer in (
            "install-quickshell-lock.sh",
            "install-wallpaper-portal.sh",
            "install-focus-sites.sh",
            "install-stock-worker.sh",
            "set-user-avatar.sh",
            "install-stem-split.sh",
        ):
            self.assertIn(f'$INSTALL_DIR/{installer}', source)
        self.assertIn("--skip-stem", source)
        self.assertIn("--avatar IMAGE", source)
        self.assertNotIn("systemctl --user enable quickshell-lock", source)

    def test_every_shell_installer_parses(self):
        for path in sorted(INSTALL_DIR.glob("*.sh")):
            with self.subTest(path=path.name):
                subprocess.run(["bash", "-n", str(path)], check=True)

    def test_help_is_non_mutating_and_documents_large_stem_download(self):
        result = subprocess.run(
            [str(INSTALL_DIR / "install-all.sh"), "--help"],
            check=True,
            text=True,
            capture_output=True,
        )
        self.assertIn("~5 GiB", result.stdout)
        self.assertIn("--skip-stem", result.stdout)
        self.assertIn("--avatar IMAGE", result.stdout)


if __name__ == "__main__":
    unittest.main()
