import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.scheduler import (
    background_control,
    background_control_status,
    background_status,
    evaluate_alert_configs,
    run_background_cycle,
    stock_widget_configs,
)


class StockSchedulerTests(unittest.TestCase):
    def process(self, stdout="", returncode=0, stderr=""):
        return subprocess.CompletedProcess([], returncode, stdout=stdout, stderr=stderr)

    def config(self, source_id="screen:1", enabled=True):
        return {
            "sourceId": source_id,
            "mode": "kis",
            "environment": "paper",
            "alerts": [{
                "id": "alert-1",
                "symbol": "005930",
                "market": "KRX",
                "direction": "above",
                "target": 100,
                "enabled": enabled,
                "armed": True,
                "lastTriggeredAt": 0,
            }],
        }

    def quotes(self, price):
        return {
            "kis:paper:KRX:005930": {
                "status": "ok",
                "symbol": "005930",
                "market": "KRX",
                "name": "Samsung Electronics",
                "currency": "KRW",
                "price": price,
                "updatedAt": 1_700_000_000,
            }
        }

    def test_widget_state_reader_collects_monitor_specific_stock_alerts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "widgets.json"
            path.write_text(json.dumps({
                "version": 2,
                "boards": {
                    "eDP-1": [{
                        "wid": 7,
                        "type": "stock",
                        "payload": json.dumps({
                            "dataMode": "kis",
                            "kisEnvironment": "prod",
                            "priceAlerts": self.config()["alerts"],
                        }),
                    }],
                    "DP-4": [{"wid": 2, "type": "weather", "payload": "{}"}],
                },
            }), encoding="utf-8")

            result = stock_widget_configs(str(path))

        self.assertTrue(result["found"])
        self.assertEqual(len(result["items"]), 1)
        self.assertEqual(result["items"][0]["sourceId"], "eDP-1:7")
        self.assertEqual(result["items"][0]["mode"], "kis")
        self.assertEqual(result["items"][0]["environment"], "prod")

    def test_crossing_fires_once_rearms_then_can_fire_again(self):
        delivered = []
        notifier = lambda event: delivered.append(event) or True
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.scheduler.state_directory",
            return_value=directory,
        ):
            first = evaluate_alert_configs(
                [self.config()], self.quotes(101), notifier=notifier, now_ms=1_000,
            )
            second = evaluate_alert_configs(
                [self.config()], self.quotes(102), notifier=notifier, now_ms=2_000,
            )
            rearmed = evaluate_alert_configs(
                [self.config()], self.quotes(99), notifier=notifier, now_ms=3_000,
            )
            third = evaluate_alert_configs(
                [self.config()], self.quotes(101), notifier=notifier, now_ms=4_000,
            )

        self.assertEqual(first["triggered"], 1)
        self.assertFalse(first["states"][0]["armed"])
        self.assertEqual(second["triggered"], 0)
        self.assertTrue(rearmed["states"][0]["armed"])
        self.assertEqual(third["triggered"], 1)
        self.assertEqual(len(delivered), 2)

    def test_paused_alert_does_not_fire(self):
        delivered = []
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.scheduler.state_directory",
            return_value=directory,
        ):
            result = evaluate_alert_configs(
                [self.config(enabled=False)],
                self.quotes(120),
                notifier=lambda event: delivered.append(event) or True,
                now_ms=1_000,
            )

        self.assertEqual(result["triggered"], 0)
        self.assertEqual(result["states"][0]["quoteStatus"], "paused")
        self.assertEqual(delivered, [])

    def test_newer_user_revision_can_rearm_a_triggered_alert(self):
        config = self.config()
        config["alerts"][0]["stateRevision"] = 100
        delivered = []
        notifier = lambda event: delivered.append(event) or True
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.scheduler.state_directory",
            return_value=directory,
        ):
            evaluate_alert_configs([config], self.quotes(101), notifier=notifier, now_ms=1_000)
            resumed = self.config()
            resumed["alerts"][0]["stateRevision"] = 200
            result = evaluate_alert_configs([resumed], self.quotes(101), notifier=notifier, now_ms=2_000)

        self.assertEqual(result["triggered"], 1)
        self.assertEqual(len(delivered), 2)

    def test_monitor_alerts_use_independent_runtime_keys(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.scheduler.state_directory",
            return_value=directory,
        ):
            result = evaluate_alert_configs(
                [self.config("eDP-1:1"), self.config("DP-4:1")],
                self.quotes(101),
                notifier=lambda event: True,
                now_ms=1_000,
            )

        self.assertEqual(result["checked"], 2)
        self.assertEqual(result["triggered"], 2)
        self.assertEqual({state["sourceId"] for state in result["states"]}, {"eDP-1:1", "DP-4:1"})

    def test_background_cycle_still_evaluates_forecasts_without_widget_state(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                patch("stock_service.scheduler.state_directory", return_value=directory),
                patch("stock_service.scheduler.evaluate_all_forecasts", return_value={
                    "status": "ok", "checked": 2, "resolved": 1,
                }),
                patch("stock_service.scheduler.stock_widget_configs", return_value={
                    "found": False, "path": "", "items": [],
                }),
            ):
                result = run_background_cycle()
                status = background_status()

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["forecasts"]["resolved"], 1)
        self.assertEqual(result["alerts"]["status"], "unavailable")
        self.assertEqual(status["workerStatus"], "active")
        self.assertEqual(status["last"]["forecasts"]["resolved"], 1)

    def test_background_status_reports_disabled_timer(self):
        with (
            patch("stock_service.scheduler.systemctl_user", side_effect=[
                self.process("disabled\n", 1),
                self.process("inactive\n", 3),
            ]),
            patch("stock_service.scheduler.background_status", return_value={
                "workerStatus": "stale", "ageSeconds": 600,
            }),
        ):
            result = background_control_status()

        self.assertTrue(result["installed"])
        self.assertFalse(result["enabled"])
        self.assertFalse(result["timerActive"])
        self.assertEqual(result["workerStatus"], "disabled")

    def test_background_enable_starts_timer_and_immediate_cycle(self):
        with (
            patch("stock_service.scheduler.systemctl_user", side_effect=[
                self.process(),
                self.process(),
                self.process("enabled\n"),
                self.process("active\n"),
            ]) as systemctl,
            patch("stock_service.scheduler.background_status", return_value={
                "workerStatus": "active", "ageSeconds": 0,
            }),
        ):
            result = background_control("enable")

        self.assertTrue(result["enabled"])
        self.assertTrue(result["timerActive"])
        self.assertEqual(systemctl.call_args_list[0].args, ("enable", "--now", "quickshell-stock-worker.timer"))
        self.assertEqual(systemctl.call_args_list[1].args, ("start", "--no-block", "quickshell-stock-worker.service"))

    def test_background_disable_stops_all_periodic_work(self):
        with (
            patch("stock_service.scheduler.systemctl_user", side_effect=[
                self.process(),
                self.process(),
                self.process("disabled\n", 1),
                self.process("inactive\n", 3),
            ]) as systemctl,
            patch("stock_service.scheduler.background_status", return_value={
                "workerStatus": "active", "ageSeconds": 1,
            }),
        ):
            result = background_control("disable")

        self.assertFalse(result["enabled"])
        self.assertFalse(result["timerActive"])
        self.assertEqual(systemctl.call_args_list[0].args, ("disable", "--now", "quickshell-stock-worker.timer"))
        self.assertEqual(systemctl.call_args_list[1].args, ("stop", "quickshell-stock-worker.service"))


if __name__ == "__main__":
    unittest.main()
