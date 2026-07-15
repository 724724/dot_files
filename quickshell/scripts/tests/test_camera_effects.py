import importlib.util
import pathlib
import unittest
from unittest import mock

import cv2
import numpy as np


MODULE_PATH = pathlib.Path(__file__).parents[1] / "camera-effects.py"
SPEC = importlib.util.spec_from_file_location("camera_effects", MODULE_PATH)
camera_effects = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(camera_effects)


class CameraEffectsTests(unittest.TestCase):
    def effects(self):
        effects = object.__new__(camera_effects.CameraEffects)
        effects.cv2 = cv2
        effects.np = np
        effects.mask = None
        effects.chroma_alpha = None
        return effects

    def test_portrait_blur_is_subtle(self):
        self.assertEqual(camera_effects.PORTRAIT_BLUR_SIGMA, 2.0)

    def test_large_backgrounds_are_decoded_at_reduced_size(self):
        self.assertEqual(camera_effects.image_decode_reduction(7680, 4320), 4)
        self.assertEqual(camera_effects.image_decode_reduction(1920, 1080), 1)

    def test_file_url_becomes_local_path(self):
        self.assertEqual(
            camera_effects.local_path("file:///home/user/My%20Background.jpg"),
            "/home/user/My Background.jpg",
        )

    def test_portrait_update_preserves_background(self):
        existing = {
            "portraitEnabled": False,
            "backgroundMode": "color",
            "backgroundValue": "#5AC8FA",
        }
        with mock.patch.object(camera_effects, "read_json", return_value=existing.copy()), \
             mock.patch.object(camera_effects, "write_json") as write_json, \
             mock.patch.object(camera_effects.subprocess, "run"):
            result = camera_effects.update_config("portrait", "on")
        self.assertTrue(result["portraitEnabled"])
        self.assertEqual(result["backgroundMode"], "color")
        write_json.assert_called_once()

    def test_background_rejects_missing_image(self):
        with mock.patch.object(camera_effects, "read_json", return_value=camera_effects.default_config()):
            with self.assertRaises(ValueError):
                camera_effects.update_config("background", "image", "")

    def test_background_rejects_unavailable_image(self):
        with self.assertRaises(ValueError):
            camera_effects.update_config("background", "image", "/missing/background.png")

    def test_background_mode_change_preserves_uploaded_image(self):
        existing = {
            "portraitEnabled": True,
            "backgroundMode": "image",
            "backgroundValue": "/home/user/background.jpg",
        }
        with mock.patch.object(camera_effects, "read_json", return_value=existing.copy()), \
             mock.patch.object(camera_effects, "write_json"), \
             mock.patch.object(camera_effects.subprocess, "run"):
            result = camera_effects.update_config("background", "color", "#5AC8FA")
        self.assertEqual(result["backgroundImage"], "/home/user/background.jpg")
        self.assertEqual(result["backgroundValue"], "#5AC8FA")

    def test_chroma_matte_protects_subject_and_clears_background(self):
        effects = self.effects()
        effects.mask = np.array([[0.0, 0.2, 0.55, 1.0]], dtype=np.float32)
        alpha = effects.composition_alpha("chroma")[:, :, 0]
        self.assertEqual(float(alpha[0, 0]), 0.0)
        self.assertEqual(float(alpha[0, 1]), 0.0)
        self.assertEqual(float(alpha[0, 2]), 1.0)
        self.assertEqual(float(alpha[0, 3]), 1.0)


if __name__ == "__main__":
    unittest.main()
