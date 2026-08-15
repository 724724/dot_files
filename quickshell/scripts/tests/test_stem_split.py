import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "stem-split.py"
SPEC = importlib.util.spec_from_file_location("stem_split", MODULE_PATH)
STEM_SPLIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = STEM_SPLIT
SPEC.loader.exec_module(STEM_SPLIT)


def control(enabled=True, mode="speed", generation=0):
    value = STEM_SPLIT.default_control(mode, generation)
    for stem in STEM_SPLIT.STEMS:
        value[stem] = enabled
    return value


class CenterCrossfaderTests(unittest.TestCase):
    def test_overlapping_crops_preserve_timeline_and_sample_count(self):
        hop = 8
        overlap = 3
        span = hop + overlap
        crossfader = STEM_SPLIT.CenterCrossfader(overlap)
        stem_outputs = []
        mix_outputs = []
        output_lengths = []

        for chunk_index in range(5):
            start = chunk_index * hop
            timeline = np.arange(start, start + span, dtype=np.float32)
            mixture = np.stack((timeline, timeline + 100), axis=1)
            stems = np.stack(
                [
                    np.stack(
                        (timeline + source * 1000, timeline + source * 1000 + 100),
                        axis=1,
                    )
                    for source in range(4)
                ],
                axis=0,
            )
            result = crossfader.add(stems, mixture)
            if result is not None:
                output_stems, output_mix = result
                stem_outputs.append(output_stems)
                mix_outputs.append(output_mix)
                output_lengths.append(len(output_mix))

        combined_mix = np.concatenate(mix_outputs, axis=0)
        combined_stems = np.concatenate(stem_outputs, axis=1)
        expected_length = overlap + 4 * hop
        expected_timeline = np.arange(expected_length, dtype=np.float32)

        self.assertEqual(output_lengths, [span, hop, hop, hop])
        self.assertEqual(len(combined_mix), expected_length)
        np.testing.assert_allclose(combined_mix[:, 0], expected_timeline)
        np.testing.assert_allclose(combined_mix[:, 1], expected_timeline + 100)
        for source in range(4):
            np.testing.assert_allclose(
                combined_stems[source, :, 0],
                expected_timeline + source * 1000,
            )


class SmoothMixerTests(unittest.TestCase):
    def test_all_on_is_exact_dry_audio(self):
        state = STEM_SPLIT.ControlState(control(enabled=True))
        mixer = STEM_SPLIT.SmoothMixer(state, STEM_SPLIT.STEMS)
        mixture = np.asarray(
            [[1.25, -1.25], [0.12345679, -0.8765432]], dtype=np.float32
        )
        stems = np.full((4, len(mixture), 2), 0.75, dtype=np.float32)

        output = mixer.mix(stems, mixture)

        self.assertIs(output, mixture)
        np.testing.assert_array_equal(output, mixture)

    def test_all_off_is_exact_silence(self):
        state = STEM_SPLIT.ControlState(control(enabled=False))
        mixer = STEM_SPLIT.SmoothMixer(state, STEM_SPLIT.STEMS)
        mixture = np.full((64, 2), 0.5, dtype=np.float32)
        stems = np.full((4, len(mixture), 2), 0.125, dtype=np.float32)

        output = mixer.mix(stems, mixture)

        np.testing.assert_array_equal(output, np.zeros_like(mixture))

    def test_toggle_uses_continuous_32ms_gain_ramp(self):
        state = STEM_SPLIT.ControlState(control(enabled=True))
        mixer = STEM_SPLIT.SmoothMixer(state, STEM_SPLIT.STEMS)
        state.update(control(enabled=False))
        first_frames = int(STEM_SPLIT.RATE * STEM_SPLIT.WRITE_CHUNK_MS / 1000)
        total_frames = mixer.ramp_frames + 19
        stems = np.full((4, total_frames, 2), 0.125, dtype=np.float32)
        mixture = np.full((total_frames, 2), 0.5, dtype=np.float32)

        first = mixer.mix(stems[:, :first_frames], mixture[:first_frames])
        second = mixer.mix(stems[:, first_frames:], mixture[first_frames:])
        output = np.concatenate((first, second), axis=0)
        gain = np.maximum(
            0.0,
            1.0
            - (
                np.arange(1, total_frames + 1, dtype=np.float32)
                / mixer.ramp_frames
            ),
        )

        np.testing.assert_allclose(output[:, 0], 0.5 * gain, atol=2e-6)
        np.testing.assert_array_equal(
            output[mixer.ramp_frames - 1:],
            np.zeros_like(output[mixer.ramp_frames - 1:]),
        )
        self.assertAlmostEqual(
            mixer.ramp_frames * 1000 / STEM_SPLIT.RATE,
            STEM_SPLIT.GAIN_RAMP_MS,
            delta=1000 / STEM_SPLIT.RATE,
        )

    def test_partial_mix_distributes_reconstruction_residual(self):
        value = control(enabled=False)
        value["vocals"] = True
        state = STEM_SPLIT.ControlState(value)
        mixer = STEM_SPLIT.SmoothMixer(state, STEM_SPLIT.STEMS)
        frames = 48
        levels = np.asarray([0.05, 0.06, 0.07, 0.02], dtype=np.float32)
        stems = np.repeat(levels[:, None, None], frames, axis=1)
        stems = np.repeat(stems, 2, axis=2)
        mixture = np.full((frames, 2), 0.6, dtype=np.float32)
        expected = levels[0] + (0.6 - levels.sum()) / len(levels)

        output = mixer.mix(stems, mixture)

        np.testing.assert_allclose(output, expected, atol=1e-6)

    def test_return_to_dry_releases_limiter_without_a_gain_step(self):
        state = STEM_SPLIT.ControlState(control(enabled=True))
        mixer = STEM_SPLIT.SmoothMixer(state, STEM_SPLIT.STEMS)
        mixer.limiter_gain = 0.5
        mixture = np.ones((4000, 2), dtype=np.float32)
        stems = np.zeros((4, len(mixture), 2), dtype=np.float32)

        released = mixer.mix(stems, mixture)
        dry = mixer.mix(stems, mixture)

        self.assertAlmostEqual(float(released[0, 0]), 0.5, places=6)
        self.assertAlmostEqual(float(released[-1, 0]), 1.0, places=6)
        self.assertIs(dry, mixture)


class ControlTests(unittest.TestCase):
    def test_control_file_parses_mode_stems_and_generation(self):
        previous = control(enabled=True, mode="speed", generation=2)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "control.json"
            path.write_text(
                json.dumps(
                    {
                        "vocals": False,
                        "drums": True,
                        "bass": False,
                        "other": True,
                        "mode": "quality",
                        "generation": "17",
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch.object(STEM_SPLIT, "CONTROL_PATH", str(path)):
                result = STEM_SPLIT.read_control(previous)

        self.assertEqual(
            result,
            {
                "vocals": False,
                "drums": True,
                "bass": False,
                "other": True,
                "mode": "quality",
                "generation": 17,
            },
        )

    def test_malformed_control_preserves_previous_generation(self):
        previous = control(enabled=False, mode="quality", generation=23)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "control.json"
            path.write_text("{", encoding="utf-8")
            with mock.patch.object(STEM_SPLIT, "CONTROL_PATH", str(path)):
                result = STEM_SPLIT.read_control(previous)

        self.assertIs(result, previous)

    def test_invalid_generation_keeps_previous_value(self):
        previous = control(enabled=True, mode="speed", generation=31)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "control.json"
            path.write_text(
                json.dumps({"mode": "quality", "generation": "invalid"}),
                encoding="utf-8",
            )
            with mock.patch.object(STEM_SPLIT, "CONTROL_PATH", str(path)):
                result = STEM_SPLIT.read_control(previous)

        self.assertEqual(result["mode"], "quality")
        self.assertEqual(result["generation"], 31)

    def test_cli_accepts_mode_and_generation(self):
        argv = ["stem-split.py", "--mode", "quality", "--generation", "41"]
        with mock.patch.object(sys, "argv", argv):
            result = STEM_SPLIT.parse_args()

        self.assertEqual(result.mode, "quality")
        self.assertEqual(result.generation, 41)


if __name__ == "__main__":
    unittest.main()
