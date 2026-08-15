import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.cli import (
    emergency_stop_autopilot_with_worker,
    full_automation_status,
    reconcile_automation_with_accounting,
    start_autopilot_with_worker,
    stop_autopilot_with_worker,
)
from stock_service.core import StockServiceError


class StockAutopilotCliTests(unittest.TestCase):
    def test_start_enables_an_installed_worker(self):
        with patch(
            "stock_service.cli.start_autopilot",
            return_value={"status": "ok", "enabled": True},
        ) as start, patch(
            "stock_service.cli.background_control_status",
            return_value={"status": "ok", "installed": True, "enabled": False},
        ), patch(
            "stock_service.cli.background_control",
            return_value={"status": "ok", "installed": True, "enabled": True},
        ) as control:
            result = start_autopilot_with_worker({
                "confirmation": "START KIS PAPER AUTOPILOT",
            })

        self.assertTrue(result["worker"]["enabled"])
        start.assert_called_once()
        control.assert_called_once_with("enable")

    def test_start_reactivates_an_enabled_but_inactive_worker(self):
        with patch(
            "stock_service.cli.start_autopilot",
            return_value={"status": "ok", "enabled": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "degraded",
                "installed": True,
                "enabled": True,
                "timerActive": False,
            },
        ), patch(
            "stock_service.cli.background_control",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": True,
                "timerActive": True,
            },
        ) as control, patch(
            "stock_service.cli.stop_autopilot",
        ) as stop:
            result = start_autopilot_with_worker({
                "confirmation": "START KIS PAPER AUTOPILOT",
            })

        self.assertTrue(result["worker"]["enabled"])
        self.assertTrue(result["worker"]["timerActive"])
        control.assert_called_once_with("enable")
        stop.assert_not_called()

    def test_start_rolls_back_when_the_worker_is_not_installed(self):
        with patch(
            "stock_service.cli.start_autopilot",
            return_value={"status": "ok", "enabled": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={"status": "ok", "installed": False, "enabled": False},
        ), patch(
            "stock_service.cli.stop_autopilot",
        ) as stop:
            with self.assertRaisesRegex(StockServiceError, "Install"):
                start_autopilot_with_worker({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                })

        stop.assert_called_once_with({"confirmation": "STOP KIS PAPER AUTOPILOT"})

    def test_live_start_rolls_back_with_live_confirmation_when_worker_enable_fails(self):
        with patch(
            "stock_service.cli.start_autopilot",
            return_value={"status": "ok", "enabled": True, "environment": "prod"},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={"status": "ok", "installed": True, "enabled": False},
        ), patch(
            "stock_service.cli.background_control",
            side_effect=RuntimeError("worker unavailable"),
        ), patch(
            "stock_service.cli.stop_autopilot",
        ) as stop:
            with self.assertRaisesRegex(StockServiceError, "Could not enable"):
                start_autopilot_with_worker({
                    "confirmation": "START KIS LIVE AUTOPILOT",
                    "environment": "prod",
                })

        stop.assert_called_once_with({
            "confirmation": "STOP KIS LIVE AUTOPILOT",
        })

    def test_emergency_stop_halts_autopilot_but_keeps_worker_for_reconciliation(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "safety_halted"},
        ) as stop, patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": True,
                "timerActive": True,
            },
        ) as worker_status, patch(
            "stock_service.cli.background_control",
        ) as control:
            result = emergency_stop_autopilot_with_worker({
                "confirmation": "EMERGENCY STOP AI AUTOPILOT",
            })

        self.assertFalse(result["enabled"])
        stop.assert_called_once_with({
            "confirmation": "EMERGENCY STOP AI AUTOPILOT",
        }, emergency=True)
        self.assertTrue(result["worker"]["enabled"])
        self.assertTrue(result["worker"]["reconciliationAvailable"])
        worker_status.assert_called_once_with()
        control.assert_not_called()

    def test_emergency_stop_enables_a_disabled_installed_worker(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "safety_halted"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": False,
                "timerActive": False,
            },
        ), patch(
            "stock_service.cli.background_control",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": True,
                "timerActive": True,
            },
        ) as control:
            result = emergency_stop_autopilot_with_worker({
                "confirmation": "EMERGENCY STOP AI AUTOPILOT",
            })

        control.assert_called_once_with("enable")
        self.assertEqual(result["worker"]["availability"], "available")
        self.assertTrue(result["worker"]["reconciliationAvailable"])

    def test_emergency_stop_without_uncertainty_disables_worker(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "safety_halted"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": False},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": True,
                "timerActive": True,
            },
        ), patch(
            "stock_service.cli.background_control",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": False,
                "timerActive": False,
            },
        ) as control:
            result = emergency_stop_autopilot_with_worker({
                "confirmation": "EMERGENCY STOP AI AUTOPILOT",
            })

        control.assert_called_once_with("disable")
        self.assertFalse(result["worker"]["enabled"])
        self.assertFalse(result["worker"]["reconciliationAvailable"])
        self.assertFalse(result["worker"]["reconciliationOnly"])

    def test_emergency_stop_reports_uninstalled_worker_as_critical_unavailable(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "safety_halted"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "ok",
                "installed": False,
                "enabled": False,
                "timerActive": False,
            },
        ), patch(
            "stock_service.cli.background_control",
        ) as control:
            result = emergency_stop_autopilot_with_worker({
                "confirmation": "EMERGENCY STOP AI AUTOPILOT",
            })

        control.assert_not_called()
        self.assertEqual(result["worker"]["status"], "unavailable")
        self.assertEqual(result["worker"]["severity"], "critical")
        self.assertFalse(result["worker"]["reconciliationAvailable"])

    def test_emergency_stop_reports_activation_failure_as_critical_unavailable(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "safety_halted"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": True},
        ), patch(
            "stock_service.cli.background_control_status",
            return_value={
                "status": "ok",
                "installed": True,
                "enabled": False,
                "timerActive": False,
            },
        ), patch(
            "stock_service.cli.background_control",
            side_effect=StockServiceError("timer failed"),
        ):
            result = emergency_stop_autopilot_with_worker({
                "confirmation": "EMERGENCY STOP AI AUTOPILOT",
            })

        self.assertEqual(result["worker"]["status"], "unavailable")
        self.assertEqual(result["worker"]["severity"], "critical")
        self.assertTrue(result["worker"]["installed"])
        self.assertFalse(result["worker"]["reconciliationAvailable"])
        self.assertIn("timer failed", result["worker"]["message"])

    def test_normal_stop_disables_worker_when_no_order_is_unresolved(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "idle"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": False},
        ), patch(
            "stock_service.cli.background_control",
            return_value={"status": "ok", "enabled": False, "timerActive": False},
        ) as control:
            result = stop_autopilot_with_worker({
                "confirmation": "STOP KIS PAPER AUTOPILOT",
            })

        control.assert_called_once_with("disable")
        self.assertFalse(result["worker"]["enabled"])
        self.assertFalse(result["worker"]["reconciliationOnly"])

    def test_normal_stop_keeps_worker_only_for_unresolved_order(self):
        with patch(
            "stock_service.cli.stop_autopilot",
            return_value={"status": "ok", "enabled": False, "phase": "idle"},
        ), patch(
            "stock_service.cli.automation_execution_status",
            return_value={"uncertaintyLock": True},
        ), patch(
            "stock_service.cli.background_control",
            return_value={"status": "ok", "enabled": True, "timerActive": True},
        ) as control:
            result = stop_autopilot_with_worker({
                "confirmation": "STOP KIS PAPER AUTOPILOT",
            })

        control.assert_called_once_with("enable")
        self.assertTrue(result["worker"]["enabled"])
        self.assertTrue(result["worker"]["reconciliationOnly"])

    def test_full_status_exposes_accounting_for_both_environments_and_active_prod(self):
        paper = {"status": "ok", "environment": "paper"}
        prod = {"status": "ok", "environment": "prod"}
        dependencies = {
            "automation_execution_status": Mock(return_value={"audit": {}}),
            "automation_recovery_status": Mock(return_value={}),
            "automation_scheduler_status": Mock(return_value={"consecutiveFailures": 0}),
            "shadow_status": Mock(return_value={}),
            "automation_notification_status": Mock(return_value={}),
            "automation_resilience_status": Mock(return_value={}),
            "automation_live_status": Mock(return_value={}),
            "operations_part1_status": Mock(return_value={}),
            "operations_part2_status": Mock(return_value={}),
            "autopilot_status": Mock(return_value={}),
            "background_control_status": Mock(return_value={}),
        }
        with patch.multiple("stock_service.cli", **dependencies), patch(
            "stock_service.cli.automation_accounting_status",
            side_effect=[paper, prod],
        ) as accounting:
            result = full_automation_status({
                "status": "ok",
                "policy": {"executionMode": "live"},
            })

        self.assertEqual(result["accountingEnvironment"], "prod")
        self.assertIs(result["accounting"], prod)
        self.assertEqual(result["accountingByEnvironment"], {
            "paper": paper,
            "prod": prod,
        })
        self.assertEqual(accounting.call_args_list, [
            unittest.mock.call("paper"),
            unittest.mock.call("prod"),
        ])

    def test_full_status_uses_paper_accounting_for_dry_run_compatibility(self):
        paper = {"status": "ok", "environment": "paper"}
        prod = {"status": "ok", "environment": "prod"}
        dependencies = {
            "automation_execution_status": Mock(return_value={"audit": {}}),
            "automation_recovery_status": Mock(return_value={}),
            "automation_scheduler_status": Mock(return_value={"consecutiveFailures": 0}),
            "shadow_status": Mock(return_value={}),
            "automation_notification_status": Mock(return_value={}),
            "automation_resilience_status": Mock(return_value={}),
            "automation_live_status": Mock(return_value={}),
            "operations_part1_status": Mock(return_value={}),
            "operations_part2_status": Mock(return_value={}),
            "autopilot_status": Mock(return_value={}),
            "background_control_status": Mock(return_value={}),
        }
        with patch.multiple("stock_service.cli", **dependencies), patch(
            "stock_service.cli.automation_accounting_status",
            side_effect=[paper, prod],
        ):
            result = full_automation_status({
                "status": "ok",
                "policy": {"executionMode": "dry_run"},
            })

        self.assertEqual(result["accountingEnvironment"], "paper")
        self.assertIs(result["accounting"], paper)

    def test_reconcile_uses_production_accounting_when_live_is_active(self):
        with patch(
            "stock_service.cli.load_automation_policy",
            return_value={"executionMode": "live"},
        ), patch(
            "stock_service.cli.reconcile_automation_executions",
            return_value={"status": "ok"},
        ) as executions, patch(
            "stock_service.cli.reconcile_automation_accounting",
            return_value={"status": "ok", "healthy": True},
        ) as accounting:
            result = reconcile_automation_with_accounting()

        executions.assert_called_once_with()
        accounting.assert_called_once_with("prod")
        self.assertEqual(result["accountingEnvironment"], "prod")
        self.assertTrue(result["accounting"]["healthy"])


if __name__ == "__main__":
    unittest.main()
