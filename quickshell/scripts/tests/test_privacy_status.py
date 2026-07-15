import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "privacy-status.py"
SPEC = importlib.util.spec_from_file_location("privacy_status", MODULE_PATH)
privacy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(privacy)


def node(node_id, state, **props):
    return {"id": node_id, "state": state, "props": props}


class PrivacyStatusTests(unittest.TestCase):
    def test_screen_capture_is_not_a_camera(self):
        screen = node(1, "running", **{
            "media.class": "Video/Source",
            "media.role": "Screen",
            "node.name": "xdg-desktop-portal-hyprland",
        })
        self.assertFalse(privacy.is_camera_source(screen))

    def test_v4l2_camera_is_a_camera(self):
        camera = node(2, "running", **{
            "media.class": "Video/Source",
            "media.role": "Camera",
            "api.v4l2.path": "/dev/video0",
        })
        self.assertTrue(privacy.is_camera_source(camera))

    def test_qs_camera_is_virtual(self):
        camera = node(3, "running", **{
            "media.class": "Video/Source",
            "node.description": "QS Camera",
            "api.v4l2.path": "/dev/video10",
        })
        self.assertTrue(privacy.is_virtual_camera(camera))

    def test_qs_camera_device_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            device = root / "video10"
            device.touch()
            sys_class = root / "sys"
            (sys_class / "video10").mkdir(parents=True)
            (sys_class / "video10" / "name").write_text("QS Camera\n")
            self.assertEqual(
                privacy.qs_camera_device(device, sys_class),
                {"path": str(device), "name": "QS Camera"},
            )

    def test_linked_camera_apps_excludes_screen_capture(self):
        camera_app = node(10, "running", **{
            "media.class": "Stream/Input/Video",
            "application.name": "Firefox",
            "application.id": "firefox",
        })
        obs_screen = node(11, "running", **{
            "media.class": "Stream/Input/Video",
            "media.role": "Screen",
            "application.name": "OBS Studio",
            "application.id": "com.obsproject.Studio",
        })
        links = [{"output": 2, "input": 10}, {"output": 3, "input": 11}]
        apps = privacy.linked_apps([camera_app, obs_screen], links, {2}, "Stream/Input/Video")
        self.assertEqual([app["name"] for app in apps], ["Firefox"])

    def test_active_microphone_mute_hides_indicator(self):
        microphone = node(4, "running", **{"node.name": "alsa_input.mic"})
        self.assertTrue(privacy.microphone_is_muted([microphone], {"alsa_input.mic": True}))
        self.assertFalse(privacy.microphone_is_muted([microphone], {"alsa_input.mic": False}))

    def test_background_mode_change_preserves_uploaded_image(self):
        state = {
            "backgroundMode": "image",
            "backgroundValue": "/home/user/background.jpg",
        }
        with mock.patch.object(privacy, "backend_path", return_value="/backend"), \
             mock.patch.object(privacy, "load_state", return_value=state.copy()), \
             mock.patch.object(privacy, "run"), \
             mock.patch.object(privacy, "save_state") as save_state, \
             mock.patch.object(privacy, "status", return_value={"ok": True}):
            privacy.set_effect("background", "none:")
        saved = save_state.call_args.args[0]
        self.assertEqual(saved["backgroundImage"], "/home/user/background.jpg")
        self.assertEqual(saved["backgroundMode"], "none")


if __name__ == "__main__":
    unittest.main()
