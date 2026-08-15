import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_live import (
    LIVE_CANARY_FILLS_REQUIRED,
    LIVE_CANARY_MAX_NOTIONAL_KRW,
    automation_live_control,
    automation_live_status,
    production_canary_status,
)
from stock_service.core import StockServiceError


class StockAutomationLiveTests(unittest.TestCase):
    def evidence(self, eligible=True):
        return {"eligible": eligible, "gates": [{
            "code": "pre_live", "passed": eligible, "message": "pre-live",
        }]}

    def canary(self, passed=True):
        return {"fills": 10 if passed else 0, "requiredFills": 10, "uncertain": 0, "passed": passed}

    def test_live_readiness_stays_locked_by_default(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_live.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_live.live_readiness_evidence", return_value=self.evidence(),
        ), patch(
            "stock_service.automation_live.production_canary_status", return_value=self.canary(),
        ):
            status = automation_live_status()

        self.assertTrue(status["productionAutomationLocked"])
        self.assertFalse(status["productionAutomationEligible"])

    def test_canary_requires_all_pre_live_gates(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_live.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_live.live_readiness_evidence", return_value=self.evidence(False),
        ), patch(
            "stock_service.automation_live.production_canary_status", return_value=self.canary(False),
        ):
            with self.assertRaisesRegex(StockServiceError, "pre-live gate"):
                automation_live_control("arm-canary", {"confirmation": "ARM MANUAL LIVE CANARY"})

    def test_verified_canary_unlocks_readiness_only_after_confirmation(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_live.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_live.live_readiness_evidence", return_value=self.evidence(),
        ), patch(
            "stock_service.automation_live.production_canary_status", return_value=self.canary(),
        ):
            armed = automation_live_control(
                "arm-canary", {"confirmation": "ARM MANUAL LIVE CANARY"}, now=1800000000,
            )
            verified = automation_live_control(
                "verify-canary", {"confirmation": "VERIFY LIVE CANARY"}, now=1800000060,
            )

        self.assertEqual(armed["stage"], "manual_canary")
        self.assertTrue(verified["productionAutomationEligible"])
        self.assertFalse(verified["productionAutomationLocked"])

    def test_canary_counts_only_eligible_manual_orders_after_arming(self):
        armed_at = 1_800_000_000
        valid = {
            "requestId": "valid",
            "action": "order",
            "environment": "prod",
            "status": "accepted",
            "timestamp": armed_at,
            "brokerState": "filled",
            "reconciliation": "matched",
            "estimatedNotionalKrw": LIVE_CANARY_MAX_NOTIONAL_KRW,
            "automationPlanId": "",
        }
        invalid = [
            dict(valid, requestId="paper", environment="paper"),
            dict(valid, requestId="before-arm", timestamp=armed_at - 1),
            dict(valid, requestId="unreconciled", reconciliation="pending"),
            dict(valid, requestId="partial", brokerState="partial"),
            dict(valid, requestId="automated", automationPlanId="plan-1"),
            dict(valid, requestId="oversized",
                 estimatedNotionalKrw=LIVE_CANARY_MAX_NOTIONAL_KRW + 1),
            dict(valid, requestId="missing-notional", estimatedNotionalKrw=0),
        ]
        eligible = [
            dict(valid, requestId=f"valid-{index}")
            for index in range(LIVE_CANARY_FILLS_REQUIRED)
        ]
        with patch(
            "stock_service.automation_live.trade_activity",
            return_value={"activity": eligible + invalid},
        ):
            result = production_canary_status(armed_at)

        self.assertEqual(result["fills"], LIVE_CANARY_FILLS_REQUIRED)
        self.assertEqual(result["uncertain"], 0)
        self.assertTrue(result["passed"])
        self.assertEqual(result["armedAt"], armed_at)
        self.assertEqual(result["maxNotionalKrw"], LIVE_CANARY_MAX_NOTIONAL_KRW)

    def test_canary_requires_an_arm_time_and_rejects_uncertain_manual_order(self):
        armed_at = 1_800_000_000
        event = {
            "requestId": "manual",
            "action": "order",
            "environment": "prod",
            "status": "accepted",
            "timestamp": armed_at + 1,
            "brokerState": "filled",
            "reconciliation": "matched",
            "estimatedNotionalKrw": 10_000,
            "automationPlanId": "",
        }
        uncertain = dict(
            event,
            requestId="uncertain",
            status="uncertain",
            brokerState="submitted",
            reconciliation="unmatched",
        )
        eligible = [
            dict(event, requestId=f"manual-{index}")
            for index in range(LIVE_CANARY_FILLS_REQUIRED)
        ]
        with patch(
            "stock_service.automation_live.trade_activity",
            return_value={"activity": eligible + [uncertain]},
        ):
            unarmed = production_canary_status(0)
            armed = production_canary_status(armed_at)

        self.assertEqual(unarmed["fills"], 0)
        self.assertFalse(unarmed["passed"])
        self.assertEqual(armed["fills"], LIVE_CANARY_FILLS_REQUIRED)
        self.assertEqual(armed["uncertain"], 1)
        self.assertFalse(armed["passed"])


if __name__ == "__main__":
    unittest.main()
