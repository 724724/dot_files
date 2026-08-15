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
    def test_active_microphone_mute_hides_indicator(self):
        microphone = node(4, "running", **{"node.name": "alsa_input.mic"})
        self.assertTrue(privacy.microphone_is_muted([microphone], {"alsa_input.mic": True}))
        self.assertFalse(privacy.microphone_is_muted([microphone], {"alsa_input.mic": False}))

    def test_event_filters_ignore_query_clients(self):
        self.assertTrue(privacy.pulse_microphone_event("Event 'new' on source-output #42"))
        self.assertTrue(privacy.pulse_microphone_event("Event 'change' on source #61"))
        self.assertFalse(privacy.pulse_microphone_event("Event 'new' on client #100"))
        self.assertTrue(privacy.pipewire_privacy_event(
            '    "type": "PipeWire:Interface:Node",'))
        self.assertTrue(privacy.pipewire_privacy_event(
            '    "type": "PipeWire:Interface:Link",'))
        self.assertFalse(privacy.pipewire_privacy_event(
            '    "type": "PipeWire:Interface:Client",'))

    def test_status_reports_microphone_and_camera_privacy(self):
        nodes = [
            node(1, "running", **{
                "media.class": "Audio/Source",
                "node.name": "alsa_input.mic",
                "node.description": "Integrated Microphone",
            }),
            node(2, "running", **{
                "media.class": "Stream/Input/Audio",
                "application.name": "Firefox",
                "application.id": "firefox",
            }),
            node(3, "running", **{
                "media.class": "Video/Source",
                "media.role": "Camera",
                "node.description": "Integrated Camera",
            }),
            node(4, "running", **{
                "media.class": "Stream/Input/Video",
                "application.name": "Firefox",
                "application.id": "firefox",
            }),
        ]
        links = [{"output": 3, "input": 4}]
        with mock.patch.object(privacy, "pipewire_graph", return_value=(nodes, links)), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
             mock.patch.object(privacy, "direct_camera_apps", return_value=[]), \
             mock.patch.object(privacy, "pulse_source_mutes", return_value={"alsa_input.mic": False}):
            result = privacy.status()
        self.assertTrue(result["micActive"])
        self.assertEqual(result["micName"], "Integrated Microphone")
        self.assertEqual([app["name"] for app in result["micApps"]], ["Firefox"])
        self.assertTrue(result["cameraActive"])
        self.assertEqual(result["cameraName"], "Integrated Camera")
        self.assertEqual([app["name"] for app in result["cameraApps"]], ["Firefox"])
        self.assertFalse(any(key.startswith(("portrait", "background")) for key in result))

    def test_muted_status_suppresses_microphone_dot(self):
        nodes = [node(1, "running", **{
            "media.class": "Audio/Source",
            "node.name": "alsa_input.mic",
        })]
        with mock.patch.object(privacy, "pipewire_graph", return_value=(nodes, [])), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
             mock.patch.object(privacy, "direct_camera_apps", return_value=[]), \
             mock.patch.object(privacy, "pulse_source_mutes", return_value={"alsa_input.mic": True}):
            result = privacy.status()
        self.assertTrue(result["micMuted"])
        self.assertFalse(result["micActive"])

    def test_monitor_sources_are_not_microphones(self):
        monitor = node(1, "running", **{
            "media.class": "Audio/Source",
            "node.name": "alsa_output.speaker.monitor",
        })
        self.assertTrue(privacy.is_monitor_source(monitor))

    def test_screen_share_source_is_not_a_camera(self):
        screen = node(1, "running", **{
            "media.class": "Video/Source",
            "media.role": "Screen",
            "node.description": "Screen Capture",
        })
        camera = node(2, "running", **{
            "media.class": "Video/Source",
            "api.v4l2.path": "/dev/video0",
        })
        self.assertFalse(privacy.is_camera_source(screen))
        self.assertTrue(privacy.is_camera_source(camera))

    def test_linked_camera_apps_exclude_screen_share(self):
        nodes = [
            node(10, "running", **{
                "media.class": "Stream/Input/Video",
                "application.name": "Firefox",
                "application.id": "firefox",
            }),
            node(11, "running", **{
                "media.class": "Stream/Input/Video",
                "application.name": "OBS Studio",
                "application.id": "com.obsproject.Studio",
            }),
        ]
        links = [{"output": 2, "input": 10}, {"output": 3, "input": 11}]
        apps = privacy.linked_apps(nodes, links, {2}, "Stream/Input/Video")
        self.assertEqual([app["name"] for app in apps], ["Firefox"])

    def test_direct_camera_app_activates_indicator(self):
        nodes = [node(1, "suspended", **{
            "media.class": "Video/Source",
            "media.role": "Camera",
            "api.v4l2.path": "/dev/video0",
            "node.description": "Integrated Camera",
        })]
        direct_app = {"name": "Zoom", "id": "zoom", "binary": "zoom"}
        with mock.patch.object(privacy, "pipewire_graph", return_value=(nodes, [])), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
             mock.patch.object(privacy, "direct_camera_apps", return_value=[direct_app]), \
             mock.patch.object(privacy, "pulse_source_mutes", return_value={}):
            result = privacy.status()
        self.assertTrue(result["cameraActive"])
        self.assertEqual(result["cameraApps"], [direct_app])

    def test_virtual_camera_paths_include_v4l2loopback_devices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            sysfs = root / "sys" / "class" / "video4linux"
            virtual = root / "sys" / "devices" / "virtual" / "video4linux" / "video10"
            physical = root / "sys" / "devices" / "pci0000:00" / "video4linux" / "video0"
            sysfs.mkdir(parents=True)
            virtual.mkdir(parents=True)
            physical.mkdir(parents=True)
            (sysfs / "video10").symlink_to(virtual)
            (sysfs / "video0").symlink_to(physical)
            self.assertEqual(
                privacy.virtual_camera_paths(sysfs),
                {"/dev/video10"},
            )

    def test_droidcam_provider_is_not_reported_as_camera_consumer(self):
        apps = [
            {"name": "droidcam", "id": "droidcam", "binary": "droidcam"},
            {"name": "OBS Studio", "id": "com.obsproject.Studio", "binary": "obs"},
        ]
        with mock.patch.object(privacy, "direct_device_apps", return_value=apps):
            self.assertEqual(
                privacy.direct_camera_apps({"/dev/video10"}),
                [apps[1]],
            )

    def test_status_scans_virtual_camera_even_when_pipewire_marks_it_as_output(self):
        consumer = {"name": "OBS Studio", "id": "com.obsproject.Studio", "binary": "obs"}
        with mock.patch.object(privacy, "pipewire_graph", return_value=([], [])), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
             mock.patch.object(privacy, "virtual_camera_paths", return_value={"/dev/video10"}), \
             mock.patch.object(privacy, "direct_camera_apps", return_value=[consumer]) as direct, \
             mock.patch.object(privacy, "pulse_source_mutes", return_value={}):
            result = privacy.status()
        direct.assert_called_once_with({"/dev/video10"})
        self.assertTrue(result["cameraActive"])
        self.assertEqual(result["cameraApps"], [consumer])


if __name__ == "__main__":
    unittest.main()
