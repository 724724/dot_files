import importlib.util
import inspect
import pathlib
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
        self.assertTrue(privacy.pipewire_microphone_event(
            '    "type": "PipeWire:Interface:Node",'))
        self.assertTrue(privacy.pipewire_microphone_event(
            '    "type": "PipeWire:Interface:Link",'))
        self.assertFalse(privacy.pipewire_microphone_event(
            '    "type": "PipeWire:Interface:Client",'))

    def test_status_reports_only_microphone_privacy(self):
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
        ]
        with mock.patch.object(privacy, "pipewire_nodes", return_value=nodes), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
             mock.patch.object(privacy, "pulse_source_mutes", return_value={"alsa_input.mic": False}):
            result = privacy.status()
        self.assertTrue(result["micActive"])
        self.assertEqual(result["micName"], "Integrated Microphone")
        self.assertEqual([app["name"] for app in result["micApps"]], ["Firefox"])
        self.assertFalse(any(key.startswith(("portrait", "background")) for key in result))

    def test_muted_status_suppresses_microphone_dot(self):
        nodes = [node(1, "running", **{
            "media.class": "Audio/Source",
            "node.name": "alsa_input.mic",
        })]
        with mock.patch.object(privacy, "pipewire_nodes", return_value=nodes), \
             mock.patch.object(privacy, "direct_microphone_apps", return_value=[]), \
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

    def test_helper_has_no_camera_device_watcher_or_periodic_poll(self):
        source = inspect.getsource(privacy)
        self.assertNotIn("/dev/video", source)
        self.assertNotIn("inotify", source)
        self.assertNotIn("last_emit", source)


if __name__ == "__main__":
    unittest.main()
