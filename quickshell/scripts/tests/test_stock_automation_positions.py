import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_positions import observe_position_risk, position_risk_audit_status
from stock_service.core import StockServiceError


class StockAutomationPositionRiskTests(unittest.TestCase):
    NOW = 1_800_018_000
    POLICY = {
        "maxPositionLossPercent": 3,
        "trailingActivationPercent": 5,
        "trailingStopPercent": 2,
    }

    def holding(self, quantity=3, average=100):
        return {
            "symbol": "005930",
            "quantity": quantity,
            "sellableQuantity": quantity,
            "averagePrice": average,
        }

    def test_hard_stop_triggers_full_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            result = observe_position_risk(
                "paper", "005930", self.holding(), 96, self.POLICY, self.NOW, directory,
            )
            audit = position_risk_audit_status(directory)

        self.assertTrue(result["triggered"])
        self.assertEqual(result["reason"], "hard_stop")
        self.assertEqual(result["sellableQuantity"], 3)
        self.assertTrue(audit["healthy"])
        self.assertEqual(audit["trackedPositions"], 1)

    def test_trailing_stop_arms_after_gain_and_triggers_from_peak(self):
        with tempfile.TemporaryDirectory() as directory:
            peak = observe_position_risk(
                "paper", "005930", self.holding(), 106, self.POLICY, self.NOW, directory,
            )
            result = observe_position_risk(
                "paper", "005930", self.holding(), 103.5, self.POLICY, self.NOW + 60, directory,
            )

        self.assertTrue(peak["trailingArmed"])
        self.assertFalse(peak["triggered"])
        self.assertTrue(result["triggered"])
        self.assertEqual(result["reason"], "trailing_stop")
        self.assertEqual(result["highWaterPrice"], 106)

    def test_closed_position_removes_tracking_state(self):
        with tempfile.TemporaryDirectory() as directory:
            observe_position_risk(
                "paper", "005930", self.holding(), 101, self.POLICY, self.NOW, directory,
            )
            result = observe_position_risk(
                "paper", "005930", {}, 101, self.POLICY, self.NOW + 60, directory,
            )
            audit = position_risk_audit_status(directory)

        self.assertFalse(result["triggered"])
        self.assertEqual(audit["trackedPositions"], 0)

    def test_corrupt_position_state_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "automation-positions.json"
            path.write_text('{"version":1,"positions":{},"integrityHash":"wrong"}', encoding="utf-8")
            audit = position_risk_audit_status(directory)
            with self.assertRaisesRegex(StockServiceError, "integrity"):
                observe_position_risk(
                    "paper", "005930", self.holding(), 100, self.POLICY, self.NOW, directory,
                )

        self.assertFalse(audit["healthy"])


if __name__ == "__main__":
    unittest.main()
