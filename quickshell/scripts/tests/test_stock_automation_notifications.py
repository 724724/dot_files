import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_notifications import (
    automation_notification_status,
    process_automation_notification,
)


class StockAutomationNotificationTests(unittest.TestCase):
    def runtime(self, directory):
        stack = ExitStack()
        stack.enter_context(patch("stock_service.automation_notifications.state_directory", return_value=directory))
        stack.enter_context(patch("stock_service.automation.state_directory", return_value=directory))
        return stack

    def auto_execution(self):
        return {
            "status": "ok",
            "state": "auto_executed",
            "target": {"symbol": "005930", "language": "ko"},
            "plan": {"planId": "plan-1", "side": "buy"},
            "execution": {
                "executionId": "execution-1",
                "planId": "plan-1",
                "symbol": "005930",
                "side": "buy",
                "quantity": 2,
            },
        }

    def test_ordinary_observer_cycle_does_not_notify(self):
        delivered = []
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            result = process_automation_notification(
                {"status": "ok", "state": "observed"},
                notifier=lambda event: delivered.append(event) or True,
                enabled=True,
            )

        self.assertEqual(result["triggered"], 0)
        self.assertEqual(delivered, [])

    def test_paper_execution_notifies_once_and_is_deduplicated(self):
        delivered = []
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            first = process_automation_notification(
                self.auto_execution(),
                notifier=lambda event: delivered.append(event) or True,
                now=1_000,
                enabled=True,
            )
            second = process_automation_notification(
                self.auto_execution(),
                notifier=lambda event: delivered.append(event) or True,
                now=1_060,
                enabled=True,
            )
            status = automation_notification_status()

        self.assertEqual(first["triggered"], 1)
        self.assertEqual(first["delivered"], 1)
        self.assertTrue(second["duplicate"])
        self.assertEqual(len(delivered), 1)
        self.assertEqual(status["delivered"], 1)
        self.assertEqual(status["last"]["kind"], "paper_execution")

    def test_protective_exit_is_a_critical_notification(self):
        delivered = []
        result = self.auto_execution()
        result["state"] = "protective_exit_executed"
        result["execution"]["executionId"] = "exit-1"
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            process_automation_notification(
                result,
                notifier=lambda event: delivered.append(event) or True,
                enabled=True,
            )

        self.assertEqual(delivered[0]["kind"], "protective_exit")
        self.assertEqual(delivered[0]["urgency"], "critical")

    def test_kill_switch_and_scheduler_failure_have_distinct_events(self):
        delivered = []
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            process_automation_notification(
                {"state": "error", "consecutiveFailures": 1, "message": "network"},
                notifier=lambda event: delivered.append(event) or True,
                enabled=True,
            )
            process_automation_notification(
                {"state": "halted", "consecutiveFailures": 3, "message": "network"},
                notifier=lambda event: delivered.append(event) or True,
                enabled=True,
            )

        self.assertEqual([event["kind"] for event in delivered], ["scheduler_error", "kill_switch"])

    def test_failure_can_notify_again_after_a_healthy_cycle(self):
        delivered = []
        failure = {"state": "error", "consecutiveFailures": 1, "message": "network"}
        notifier = lambda event: delivered.append(event) or True
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            process_automation_notification(failure, notifier=notifier, enabled=True)
            duplicate = process_automation_notification(failure, notifier=notifier, enabled=True)
            process_automation_notification({"state": "observed"}, notifier=notifier, enabled=True)
            process_automation_notification(failure, notifier=notifier, enabled=True)

        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(len(delivered), 2)

    def test_operator_action_reports_the_exact_recoverable_reason_once(self):
        delivered = []
        event = {
            "state": "operator_action",
            "message": "OpenAI quota is unavailable",
            "failureClass": "operator",
        }
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            process_automation_notification(
                event,
                notifier=lambda value: delivered.append(value) or True,
                enabled=True,
            )
            duplicate = process_automation_notification(
                event,
                notifier=lambda value: delivered.append(value) or True,
                enabled=True,
            )

        self.assertEqual(delivered[0]["kind"], "operator_action")
        self.assertIn("OpenAI quota", delivered[0]["body"])
        self.assertTrue(duplicate["duplicate"])

    def test_repeated_halted_heartbeat_keeps_one_stable_incident(self):
        delivered = []
        notifier = lambda event: delivered.append(event) or True
        first = {
            "state": "halted",
            "haltIncidentId": "incident-1",
            "message": "audit integrity failed",
            "updatedAt": 1_000,
        }
        second = dict(first, updatedAt=1_060)
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            process_automation_notification(first, notifier=notifier, enabled=True)
            duplicate = process_automation_notification(second, notifier=notifier, enabled=True)

        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(len(delivered), 1)

    def test_disabled_notifications_do_not_write_or_deliver(self):
        delivered = []
        with tempfile.TemporaryDirectory() as directory, self.runtime(directory):
            result = process_automation_notification(
                self.auto_execution(),
                notifier=lambda event: delivered.append(event) or True,
                enabled=False,
            )

        self.assertFalse(result["enabled"])
        self.assertEqual(result["triggered"], 0)
        self.assertEqual(delivered, [])


if __name__ == "__main__":
    unittest.main()
