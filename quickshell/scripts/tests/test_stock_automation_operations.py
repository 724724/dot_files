import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import load_automation_policy, save_automation_policy
from stock_service.automation_operations import (
    automation_incident_audit_status,
    automation_incident_path,
    create_automation_snapshot,
    operations_part1_status,
    restore_automation_snapshot,
    run_operations_part1,
    verify_snapshot,
)
from stock_service.core import StockServiceError


class StockAutomationOperationsTests(unittest.TestCase):
    NOW = 1800000000

    def state_patches(self, directory):
        stack = ExitStack()
        for module in (
            "stock_service.automation",
            "stock_service.automation_execution",
            "stock_service.automation_scheduler",
            "stock_service.automation_shadow",
            "stock_service.automation_positions",
            "stock_service.automation_notifications",
            "stock_service.automation_accounting",
            "stock_service.automation_resilience",
            "stock_service.automation_live",
            "stock_service.automation_operations",
            "stock_service.automation_soak",
        ):
            stack.enter_context(patch(f"{module}.state_directory", return_value=directory))
        return stack

    def test_part_one_runs_fault_suite_and_creates_verified_snapshot(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            result = run_operations_part1({
                "confirmation": "RUN OPERATIONS PART ONE",
            }, now=self.NOW)
            snapshot_healthy = verify_snapshot(result["snapshotCreated"]["path"])["healthy"]

        self.assertTrue(result["eligible"])
        self.assertTrue(result["resilienceRun"]["passed"])
        self.assertTrue(snapshot_healthy)

    def test_snapshot_tampering_is_detected(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            save_automation_policy(load_automation_policy())
            snapshot = create_automation_snapshot({
                "confirmation": "CREATE AUTOMATION SNAPSHOT",
            }, now=self.NOW)
            policy = Path(snapshot["path"]) / "automation-policy.json"
            policy.write_text("{}", encoding="utf-8")
            status = verify_snapshot(snapshot["path"])

        self.assertFalse(status["healthy"])
        self.assertIn("automation-policy.json", status["invalidFiles"])

    def test_restore_requires_confirmation_and_forces_kill_switch(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            policy = load_automation_policy()
            policy.update({"enabled": True, "executionMode": "paper"})
            save_automation_policy(policy)
            snapshot = create_automation_snapshot({
                "confirmation": "CREATE AUTOMATION SNAPSHOT",
            }, now=self.NOW)
            with self.assertRaisesRegex(StockServiceError, "exact confirmation"):
                restore_automation_snapshot({"snapshotId": snapshot["snapshotId"]})
            result = restore_automation_snapshot({
                "snapshotId": snapshot["snapshotId"],
                "confirmation": "RESTORE HALTED AUTOMATION SNAPSHOT",
            }, now=self.NOW + 1)
            restored = load_automation_policy()

        self.assertTrue(result["restored"])
        self.assertTrue(restored["halted"])
        self.assertFalse(restored["enabled"])
        self.assertFalse(restored["schedulerEnabled"])

    def test_health_transitions_are_hash_chained_and_tamper_evident(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            run_operations_part1({
                "confirmation": "RUN OPERATIONS PART ONE",
            }, now=self.NOW)
            stale = Path(directory) / "automation-interrupted.tmp"
            stale.write_text("partial", encoding="utf-8")
            stale.touch()
            with patch("stock_service.automation_operations.time.time", return_value=self.NOW + 400):
                operations_part1_status(self.NOW + 400, record=True)
            stale.unlink()
            operations_part1_status(self.NOW + 500, record=True)
            healthy = automation_incident_audit_status()
            path = Path(automation_incident_path())
            path.write_text(path.read_text(encoding="utf-8").replace("degraded", "changed", 1), encoding="utf-8")
            tampered = automation_incident_audit_status()

        self.assertTrue(healthy["healthy"])
        self.assertEqual(healthy["verifiedRecords"], 2)
        self.assertFalse(tampered["healthy"])


if __name__ == "__main__":
    unittest.main()
