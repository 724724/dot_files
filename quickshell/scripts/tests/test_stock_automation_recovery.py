import json
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import load_automation_policy
from stock_service.automation_recovery import automation_recovery_status, recover_automation_audit
from stock_service.core import StockServiceError


class StockAutomationRecoveryTests(unittest.TestCase):
    NOW = 1_800_018_000

    def state_patches(self, directory):
        stack = ExitStack()
        for module in (
            "stock_service.automation",
            "stock_service.automation_execution",
            "stock_service.automation_scheduler",
            "stock_service.automation_shadow",
            "stock_service.automation_recovery",
            "stock_service.automation_accounting",
            "stock_service.automation_resilience",
            "stock_service.automation_live",
            "stock_service.automation_operations",
            "stock_service.automation_soak",
        ):
            stack.enter_context(patch(f"{module}.state_directory", return_value=directory))
        return stack

    def test_recovery_requires_exact_confirmation(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            path = Path(directory) / "automation-plans.jsonl"
            path.write_text("{broken\n", encoding="utf-8")
            with self.assertRaisesRegex(StockServiceError, "requires ARCHIVE"):
                recover_automation_audit({})
            self.assertTrue(path.exists())

    def test_corrupt_state_is_archived_and_reset_to_halted(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            plan_path = Path(directory) / "automation-plans.jsonl"
            execution_path = Path(directory) / "automation-executions.jsonl"
            plan_path.write_text("{broken\n", encoding="utf-8")
            execution_path.write_text("{also-broken\n", encoding="utf-8")
            result = recover_automation_audit({
                "confirmation": "ARCHIVE AND RESET AUTOMATION",
            }, now=self.NOW)
            policy = load_automation_policy()
            status = automation_recovery_status()
            archive = Path(result["archiveDirectory"])
            manifest = json.loads((archive / "manifest.json").read_text(encoding="utf-8"))

            self.assertFalse(plan_path.exists())
            self.assertFalse(execution_path.exists())
            self.assertEqual((archive / "automation-plans.jsonl").read_text(encoding="utf-8"), "{broken\n")
            self.assertEqual((archive / "automation-executions.jsonl").read_text(encoding="utf-8"), "{also-broken\n")

        self.assertTrue(result["auditAfter"]["healthy"])
        self.assertTrue(result["requiresKillSwitchReset"])
        self.assertTrue(policy["halted"])
        self.assertFalse(policy["enabled"])
        self.assertFalse(policy["schedulerEnabled"])
        self.assertTrue(status["available"])
        self.assertEqual(manifest["archiveName"], result["archiveName"])

    def test_healthy_state_cannot_be_reset_through_recovery(self):
        with tempfile.TemporaryDirectory() as directory, self.state_patches(directory):
            with self.assertRaisesRegex(StockServiceError, "healthy"):
                recover_automation_audit({
                    "confirmation": "ARCHIVE AND RESET AUTOMATION",
                }, now=self.NOW)


if __name__ == "__main__":
    unittest.main()
