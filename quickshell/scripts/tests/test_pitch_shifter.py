import array
import importlib.util
import math
import pathlib
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "pitch-shifter.py"
MEDIA_SERVICE_PATH = pathlib.Path(__file__).parents[2] / "desktop" / "bar" / "MediaService.qml"
SPEC = importlib.util.spec_from_file_location("pitch_shifter", MODULE_PATH)
pitch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pitch)


class Pipeline:
    def __init__(self, events):
        self.events = events

    def stop(self):
        self.events.append(("pipeline", "stop"))


class PitchShifterTests(unittest.TestCase):
    def test_live_shifter_stays_finite_across_repeated_pitch_changes(self):
        shifter = pitch.RubberBandLive(0)
        try:
            frames = shifter.block_size
            phase = 0
            for semitones in (1, 0, -1, 0, 1, -1, 0):
                shifter.set_semitones(semitones)
                samples = array.array("f")
                for frame in range(frames):
                    value = math.sin(2 * math.pi * 440 * (phase + frame) / pitch.RATE) * 0.25
                    samples.extend((value, value))
                phase += frames
                output = array.array("f")
                output.frombytes(shifter.process(samples.tobytes()))
                self.assertTrue(all(math.isfinite(value) for value in output))
                self.assertLessEqual(max(map(abs, output)), 1.0)
        finally:
            shifter.close()

    def test_zero_transpose_keeps_live_filter_until_media_stops(self):
        source = MEDIA_SERVICE_PATH.read_text(encoding="utf-8")
        self.assertIn("if (!pitchProc.running) _stopPitch()", source)
        self.assertIn("onHasMediaChanged:", source)
        self.assertIn("_stopPitch()\n        }\n    }\n    onTitleChanged:", source)

    def test_teardown_restores_player_before_stopping_pipeline(self):
        events = []
        router = pitch.Router()
        router.module = "42"
        router.target = "speaker"
        router.real_sinks = lambda: ["speaker"]
        router.sink_index = lambda: "10"
        router.sink_inputs = lambda: []
        router.move = lambda index, target: events.append(("move", index, target))

        with mock.patch.object(
            pitch,
            "sink_inputs",
            return_value=[{"index": 7, "sink": 10}],
        ), mock.patch.object(
            pitch,
            "pactl",
            side_effect=lambda *args: events.append(("pactl", *args)),
        ):
            router.teardown(Pipeline(events))

        self.assertEqual(events[0], ("move", 7, "speaker"))
        self.assertEqual(events[1][0], "pipeline")
        self.assertEqual(events[2], ("pactl", "unload-module", "42"))


if __name__ == "__main__":
    unittest.main()
