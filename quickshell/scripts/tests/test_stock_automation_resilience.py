import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_resilience import automation_resilience_status, run_resilience_self_test
from stock_service.core import StockServiceError


class StockAutomationResilienceTests(unittest.TestCase):
    NOW = 1800000000

    def test_self_test_requires_confirmation_and_expires(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_resilience.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.automation_audit_status",
            return_value={"healthy": True},
        ):
            with self.assertRaisesRegex(StockServiceError, "exact confirmation"):
                run_resilience_self_test({})
            result = run_resilience_self_test({
                "confirmation": "RUN AUTOMATION RESILIENCE TEST",
            }, now=self.NOW)
            fresh = automation_resilience_status(self.NOW + 60)
            stale = automation_resilience_status(self.NOW + 8 * 86400)

        self.assertTrue(result["passed"])
        self.assertTrue(fresh["eligible"])
        self.assertFalse(stale["eligible"])


if __name__ == "__main__":
    unittest.main()
