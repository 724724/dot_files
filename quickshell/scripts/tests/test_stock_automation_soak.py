import json
import tempfile
import unittest
from contextlib import ExitStack
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import AUTOMATION_TIMEZONE
from stock_service.automation_soak import (
    automation_soak_path,
    create_operations_part2_report,
    load_soak_state,
    operations_part2_status,
    record_soak_cycle,
    run_operations_part2,
    save_soak_state,
    soak_hash,
)


class StockAutomationSoakTests(unittest.TestCase):
    NOW = 1_800_100_000

    def state_patches(self, directory):
        stack = ExitStack()
        for module in (
            "stock_service.automation",
            "stock_service.automation_execution",
            "stock_service.automation_shadow",
            "stock_service.automation_accounting",
            "stock_service.automation_live",
            "stock_service.automation_operations",
            "stock_service.automation_soak",
        ):
            stack.enter_context(patch(f"{module}.state_directory", return_value=directory))
        return stack

    def cycle(self, timestamp, state="observed", status="ok"):
        return {
            "status": status,
            "startedAt": timestamp - 2,
            "updatedAt": timestamp,
            "durationMs": 2_000,
            "operationsPart1": {"status": "ok", "eligible": True},
            "reconciliation": {"status": "ok"},
            "automation": {
                "status": "ok" if state != "error" else "error",
                "state": state,
                "targetCount": 1,
                "brokerOrderSent": False,
                "plan": {"planId": f"plan-{timestamp}", "decision": "hold"},
            },
        }

    def test_part_two_start_preserves_evidence_and_enables_collection(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory), patch(
            "stock_service.automation_soak.operations_part2_start_readiness",
            return_value={"eligible": True, "gates": []},
        ), patch(
            "stock_service.automation_soak.operations_part2_status",
            return_value={"status": "ok", "enabled": True},
        ), patch(
            "stock_service.automation_operations.create_automation_snapshot",
            return_value={"snapshotId": "snapshot-1"},
        ):
            result = run_operations_part2({"confirmation": "START KIS PAPER SOAK"}, self.NOW)
            state, integrity = load_soak_state()

        self.assertEqual(result["status"], "ok")
        self.assertTrue(integrity)
        self.assertTrue(state["enabled"])
        self.assertEqual(state["startedAt"], self.NOW)
        self.assertEqual(result["snapshotCreated"]["snapshotId"], "snapshot-1")

    def test_worker_cycles_are_deduplicated_and_aggregated(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory), patch(
            "stock_service.automation_soak.operations_part2_status",
            return_value={"status": "ok"},
        ):
            state = {"enabled": True, "startedAt": self.NOW}
            save_soak_state(state)
            cycle = self.cycle(self.NOW + 10)
            record_soak_cycle(cycle)
            record_soak_cycle(cycle)
            stored, integrity = load_soak_state()

        self.assertTrue(integrity)
        self.assertEqual(stored["cycles"], 1)
        self.assertEqual(stored["brokerAttempts"], 1)
        self.assertEqual(stored["observations"], 1)
        self.assertEqual(len(stored["days"]), 1)

    def test_three_online_failures_engage_fail_closed_halt(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory), patch(
            "stock_service.automation_soak.operations_part2_status",
            return_value={"status": "ok"},
        ), patch("stock_service.automation_soak.halt_soak_automation") as halt:
            save_soak_state({"enabled": True, "startedAt": self.NOW})
            for offset in range(3):
                record_soak_cycle(self.cycle(self.NOW + offset + 1, "error", "partial"))
            stored, integrity = load_soak_state()

        self.assertTrue(integrity)
        self.assertFalse(stored["enabled"])
        self.assertEqual(stored["consecutiveFailures"], 3)
        self.assertEqual(stored["automaticHalts"], 1)
        halt.assert_called_once_with("critical_online_validation_failure")

    def test_complete_status_requires_paper_slo_and_verified_live_canary(self):
        date = datetime.fromtimestamp(self.NOW, AUTOMATION_TIMEZONE).date().isoformat()
        state = {
            "enabled": True,
            "startedAt": self.NOW - 1_000,
            "cycles": 1,
            "observations": 1,
            "durationSamplesMs": [2_000],
            "days": {date: {
                "cycles": 1,
                "successfulCycles": 1,
                "failedCycles": 0,
                "brokerAttempts": 1,
                "brokerSuccesses": 1,
                "brokerFailures": 0,
                "rateLimitEvents": 0,
                "criticalFailures": 0,
                "observations": 1,
            }},
        }
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory), (
            patch("stock_service.automation_soak.SOAK_MIN_WORKER_CYCLES", 1)
        ), patch(
            "stock_service.automation_soak.SOAK_MIN_BROKER_OBSERVATIONS", 1,
        ), patch(
            "stock_service.automation_soak.SOAK_MIN_HEALTHY_SESSIONS", 1,
        ), patch(
            "stock_service.automation_operations.operations_part1_status",
            return_value={"status": "ok", "eligible": True, "scheduler": {"consecutiveFailures": 0}},
        ), patch(
            "stock_service.scheduler.background_control_status",
            return_value={"enabled": True, "timerActive": True, "workerStatus": "active"},
        ), patch(
            "stock_service.automation_soak.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_soak.automation_accounting_status",
            return_value={"eligible": True},
        ), patch(
            "stock_service.automation_soak.shadow_status",
            return_value={"promotion": {"eligible": True}},
        ), patch(
            "stock_service.automation_live.load_live_state",
            return_value=({"stage": "verified"}, True),
        ), patch(
            "stock_service.automation_live.production_canary_status",
            return_value={"fills": 10, "requiredFills": 10, "passed": True},
        ):
            save_soak_state(state)
            result = operations_part2_status(self.NOW)

        self.assertTrue(result["paperEligible"])
        self.assertTrue(result["eligible"])
        self.assertEqual(result["phase"], "complete")

    def test_modified_evidence_fails_integrity(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            save_soak_state({"enabled": True, "startedAt": self.NOW})
            path = Path(automation_soak_path())
            value = json.loads(path.read_text(encoding="utf-8"))
            value["cycles"] = 500
            path.write_text(json.dumps(value), encoding="utf-8")
            _, integrity = load_soak_state()

        self.assertFalse(integrity)

    def test_verified_report_is_hash_sealed(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory), patch(
            "stock_service.automation_soak.operations_part2_status",
            return_value={
                "eligible": True,
                "metrics": {"healthySessions": 60},
                "thresholds": {"healthySessions": 60},
                "gates": [{"code": "complete", "passed": True}],
            },
        ):
            report = create_operations_part2_report({
                "confirmation": "CREATE VERIFIED OPERATIONS REPORT",
            }, self.NOW)
            report_exists = Path(report["path"]).is_file()
            stored_report = json.loads(Path(report["path"]).read_text(encoding="utf-8"))

        self.assertEqual(stored_report["reportHash"], soak_hash(stored_report))
        self.assertTrue(report_exists)


if __name__ == "__main__":
    unittest.main()
