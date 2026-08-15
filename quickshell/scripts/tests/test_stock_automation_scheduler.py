import tempfile
import unittest
import json
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    DEFAULT_AUTOMATION_POLICY,
    automation_control,
    load_automation_policy,
    save_automation_policy,
)
from stock_service.automation_scheduler import (
    combined_automation_targets,
    due_automation_targets,
    monitor_protective_positions,
    normalized_automation_targets,
    recover_recoverable_halt,
    run_automation_scheduler,
    scheduler_analysis_evidence,
    scheduler_failure_class,
    tracked_protection_targets,
)


class StockAutomationSchedulerTests(unittest.TestCase):
    NOW = 1_800_018_000

    def target(self):
        return {
            "sourceId": "eDP-1:7",
            "mode": "kis",
            "environment": "paper",
            "symbol": "005930",
            "market": "KRX",
            "language": "ko",
            "aiProvider": "both",
            "analysisProfile": "balanced",
            "backtestStrategy": "trend",
            "tradingMode": "automatic",
            "automationTargetEnabled": True,
        }

    def enable(self, directory):
        with patch("stock_service.automation.state_directory", return_value=directory):
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            automation_control("scheduler-enable", {"confirmation": "ENABLE OBSERVE SCHEDULER"})

    def enable_auto(self, directory):
        with patch("stock_service.automation.state_directory", return_value=directory), patch(
            "stock_service.automation_scheduler.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_shadow.shadow_status",
            return_value={"promotion": {"eligible": True}},
        ):
            automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})
            automation_control("scheduler-enable", {"confirmation": "ENABLE OBSERVE SCHEDULER"})
            automation_control("scheduler-auto-enable", {
                "confirmation": "ENABLE PROMOTION-GATED PAPER AUTO",
            })

    @contextmanager
    def isolated_policy_and_universe(self, directory):
        with patch(
            "stock_service.automation.state_directory",
            return_value=directory,
        ), patch(
            "stock_service.automation_scheduler.load_autopilot_state",
            return_value={"enabled": False, "candidates": []},
        ):
            yield

    def runtime_patches(self, directory):
        return (
            self.isolated_policy_and_universe(directory),
            patch("stock_service.automation_scheduler.state_directory", return_value=directory),
            patch("stock_service.automation_execution.state_directory", return_value=directory),
            patch(
                "stock_service.automation_scheduler.automation_execution_status",
                return_value={"status": "ok", "uncertaintyLock": False, "audit": {"healthy": True}},
            ),
            patch(
                "stock_service.automation_scheduler.market_session_gate",
                return_value={"passed": True, "message": "open"},
            ),
            patch(
                "stock_service.automation_scheduler.kis_account_summary",
                return_value={"holdings": []},
            ),
            patch(
                "stock_service.automation_scheduler.observe_position_risk",
                return_value={"triggered": False, "reason": ""},
            ),
        )

    def test_scheduler_is_disabled_by_default(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_scheduler.state_directory", return_value=directory,
        ):
            result = run_automation_scheduler([self.target()], now=self.NOW)

        self.assertEqual(result["state"], "disabled")
        self.assertFalse(result["brokerOrderSent"])

    def test_scheduler_forwards_news_and_behavior_evidence(self):
        source = {
            "status": "ok",
            "stance": "bullish",
            "confidence": 82,
            "downProbability": 14,
            "generatedAt": self.NOW,
            "models": ["one", "two"],
            "ensembleAgreement": {"agreementScore": 86, "modelCount": 2},
            "newsContext": {
                "status": "usable",
                "qualityScore": 81,
                "verifiedDirectCount": 2,
                "independentEventCount": 4,
            },
            "behaviorContext": {
                "status": "usable",
                "riskPenalty": 24,
                "evidenceConfidence": 76,
            },
            "behaviorAdjustment": {"method": "monotonic_confidence_only_guard"},
        }

        result = scheduler_analysis_evidence(source)

        self.assertEqual(result["newsContext"], source["newsContext"])
        self.assertEqual(result["behaviorContext"], source["behaviorContext"])
        self.assertEqual(result["behaviorAdjustment"], source["behaviorAdjustment"])
        self.assertIsNot(result["newsContext"], source["newsContext"])
        self.assertIsNot(result["behaviorContext"], source["behaviorContext"])

    def test_target_normalization_supports_both_environments_and_rejects_demo(self):
        valid = self.target()
        production = dict(valid, sourceId="prod", environment="prod")
        demo = dict(valid, sourceId="demo", mode="demo")

        result = normalized_automation_targets([valid, production, demo])

        self.assertEqual(len(result), 2)
        self.assertEqual(
            {item["environment"] for item in result},
            {"paper", "prod"},
        )

    def test_target_normalization_supports_us_markets(self):
        base = self.target()
        nasdaq = dict(base, sourceId="nasdaq", symbol="AAPL", market="NASDAQ")
        nyse = dict(base, sourceId="nyse", symbol="BRK.B", market="NYSE")
        invalid = dict(base, sourceId="invalid", symbol="bad symbol", market="NASDAQ")

        result = normalized_automation_targets([nasdaq, nyse, invalid])

        self.assertEqual([(item["market"], item["symbol"]) for item in result], [
            ("NASDAQ", "AAPL"),
            ("NYSE", "BRK.B"),
        ])

    def test_target_normalization_rejects_manual_trading_mode(self):
        manual = dict(self.target(), tradingMode="manual")

        self.assertEqual(normalized_automation_targets([manual]), [])

    def test_enabled_global_autopilot_overrides_duplicate_widget_target(self):
        state = {
            "enabled": True,
            "automaticSelection": False,
            "selectedKeys": ["KRX:005930"],
            "candidates": [{
                "market": "KRX",
                "symbol": "005930",
                "key": "KRX:005930",
                "aiProvider": "both",
                "analysisProfile": "balanced",
                "strategy": "trend",
                "language": "ko",
            }],
        }

        result = combined_automation_targets([self.target()], state)

        self.assertEqual(len(result), 1)
        self.assertTrue(result[0]["autopilot"])
        self.assertTrue(result[0]["allowEntry"])

    def test_observer_generates_plan_but_never_executes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze",
                return_value={
                    "status": "ok", "stance": "bullish", "confidence": 88, "downProbability": 10,
                    "generatedAt": self.NOW, "models": ["a", "b"],
                    "ensembleAgreement": {"agreementScore": 90, "modelCount": 2},
                    "newsContext": {
                        "status": "usable", "qualityScore": 80, "verifiedDirectCount": 2,
                    },
                    "behaviorContext": {
                        "status": "usable", "riskPenalty": 20, "evidenceConfidence": 75,
                    },
                },
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={"planId": "plan-1", "decision": "ready", "side": "buy", "failedGates": []},
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": True},
            ):
                result = run_automation_scheduler([self.target()], now=self.NOW)

        self.assertEqual(result["state"], "observed")
        self.assertEqual(result["plan"]["planId"], "plan-1")
        self.assertFalse(result["autoExecution"])
        self.assertFalse(result["brokerOrderSent"])
        build.assert_called_once()
        forwarded = build.call_args.args[0]["analysis"]
        self.assertEqual(forwarded["newsContext"]["qualityScore"], 80)
        self.assertEqual(forwarded["behaviorContext"]["riskPenalty"], 20)

    def test_observer_throttles_ai_and_plan_work(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze", return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={"planId": "plan-1", "decision": "blocked", "side": "buy", "failedGates": ["ai"]},
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": False},
            ):
                first = run_automation_scheduler([self.target()], now=self.NOW)
                second = run_automation_scheduler([self.target()], now=self.NOW + 60)

        self.assertEqual(first["state"], "observed")
        self.assertEqual(second["state"], "throttled")
        self.assertEqual(build.call_count, 1)

    def test_plan_uses_fresh_time_after_slow_ai_work(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.time.time",
                return_value=self.NOW + 12,
            ), patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze",
                return_value={
                    "status": "ok",
                    "stance": "bullish",
                    "confidence": 88,
                    "downProbability": 10,
                    "generatedAt": self.NOW + 12,
                    "models": ["a", "b"],
                    "ensembleAgreement": {"agreementScore": 90, "modelCount": 2},
                },
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={"planId": "fresh-plan", "decision": "hold", "side": "hold", "failedGates": []},
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": False},
            ):
                run_automation_scheduler([self.target()], now=self.NOW)

        self.assertEqual(build.call_args.kwargs["now"], self.NOW + 12)

    def test_promoted_auto_mode_submits_only_an_eligible_paper_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable_auto(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze",
                return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "plan-auto", "decision": "ready", "side": "buy",
                    "failedGates": [], "executionEligible": True,
                },
            ), patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": True}, "tradeApplied": True},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
                return_value={"executionId": "execution-1", "brokerOrderSent": True},
            ) as execute:
                result = run_automation_scheduler([self.target()], now=self.NOW)

        self.assertEqual(result["state"], "auto_executed")
        self.assertTrue(result["autoExecution"])
        self.assertTrue(result["brokerOrderSent"])
        execute.assert_called_once_with({
            "planId": "plan-auto",
            "confirmation": "EXECUTE KIS PAPER plan-auto",
        })

    def test_paper_autopilot_bypasses_only_the_long_shadow_promotion_gate(self):
        universe = {
            "enabled": True,
            "automaticSelection": False,
            "selectedKeys": ["KRX:005930"],
            "candidates": [{
                "market": "KRX",
                "symbol": "005930",
                "key": "KRX:005930",
                "aiProvider": "both",
                "analysisProfile": "balanced",
                "strategy": "trend",
                "language": "ko",
            }],
        }
        with tempfile.TemporaryDirectory() as directory:
            with patch("stock_service.automation.state_directory", return_value=directory):
                save_automation_policy(dict(
                    DEFAULT_AUTOMATION_POLICY,
                    enabled=True,
                    halted=False,
                    executionMode="paper",
                    schedulerEnabled=True,
                    schedulerMode="paper_auto",
                    autopilotEnabled=True,
                ))
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.load_autopilot_state", return_value=universe,
            ), patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze", return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "autopilot-plan",
                    "decision": "ready",
                    "side": "buy",
                    "failedGates": [],
                    "executionEligible": True,
                },
            ), patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": False}, "tradeApplied": True},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
                return_value={"executionId": "execution-1", "brokerOrderSent": True},
            ) as execute:
                result = run_automation_scheduler([], now=self.NOW)

        self.assertEqual(result["state"], "auto_executed")
        self.assertFalse(result.get("autoRevoked", False))
        execute.assert_called_once()

    def test_unselected_autopilot_candidate_cannot_open_a_position(self):
        universe = {
            "enabled": True,
            "automaticSelection": False,
            "selectedKeys": [],
            "candidates": [{
                "market": "KRX",
                "symbol": "005930",
                "key": "KRX:005930",
                "aiProvider": "both",
                "analysisProfile": "balanced",
                "strategy": "trend",
                "language": "ko",
            }],
        }
        with tempfile.TemporaryDirectory() as directory:
            with patch("stock_service.automation.state_directory", return_value=directory):
                save_automation_policy(dict(
                    DEFAULT_AUTOMATION_POLICY,
                    enabled=True,
                    halted=False,
                    executionMode="paper",
                    schedulerEnabled=True,
                    schedulerMode="paper_auto",
                    autopilotEnabled=True,
                ))
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.load_autopilot_state", return_value=universe,
            ), patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze", return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "blocked-entry",
                    "decision": "ready",
                    "side": "buy",
                    "failedGates": [],
                    "executionEligible": True,
                },
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": False}, "tradeApplied": False},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
            ) as execute:
                result = run_automation_scheduler([], now=self.NOW)

        self.assertEqual(result["state"], "no_target")
        build.assert_not_called()
        execute.assert_not_called()

    def test_scheduler_passes_us_market_through_every_runtime_boundary(self):
        target = dict(
            self.target(),
            sourceId="nasdaq",
            symbol="AAPL",
            market="NASDAQ",
        )
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], patch(
                "stock_service.automation_scheduler.market_session_gate",
                return_value={"passed": True, "message": "open"},
            ) as session, patch(
                "stock_service.automation_scheduler.load_autopilot_state",
                return_value={"enabled": False, "candidates": []},
            ), patch(
                "stock_service.automation_scheduler.kis_account_summary",
                return_value={"holdings": []},
            ) as account, contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "AAPL", "market": "NASDAQ", "price": 200},
            ) as snapshot, patch(
                "stock_service.automation_scheduler.analyze", return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={"planId": "us-plan", "decision": "blocked", "side": "buy", "failedGates": ["risk"]},
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": False},
            ):
                result = run_automation_scheduler([target], now=self.NOW)

        self.assertEqual(result["state"], "observed")
        session.assert_called_once_with("paper", market="NASDAQ", now=self.NOW)
        snapshot.assert_called_once_with("AAPL", "NASDAQ", "3M", "paper")
        account.assert_called_once_with("paper", "AAPL", 200, "limit", "NASDAQ")
        self.assertEqual(build.call_args.args[0]["market"], "NASDAQ")
        self.assertTrue(build.call_args.args[0]["allowEntry"])

    def test_auto_mode_is_revoked_when_promotion_is_lost(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable_auto(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.analyze", return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "plan-locked", "decision": "ready", "side": "buy",
                    "failedGates": [], "executionEligible": True,
                },
            ), patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": False}, "tradeApplied": True},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
            ) as execute:
                result = run_automation_scheduler([self.target()], now=self.NOW)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(result["state"], "observed")
        self.assertTrue(result["autoRevoked"])
        self.assertFalse(result["autoExecution"])
        self.assertEqual(policy["schedulerMode"], "observe")
        execute.assert_not_called()

    def test_promoted_auto_mode_prioritizes_protective_exit_without_ai(self):
        holding = {
            "symbol": "005930",
            "quantity": 3,
            "sellableQuantity": 3,
            "averagePrice": 73000,
        }
        position_risk = {
            "triggered": True,
            "reason": "hard_stop",
            "sellableQuantity": 3,
        }
        with tempfile.TemporaryDirectory() as directory:
            self.enable_auto(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.kis_account_summary",
                return_value={"holdings": [holding]},
            ), patch(
                "stock_service.automation_scheduler.observe_position_risk",
                return_value=position_risk,
            ), patch(
                "stock_service.automation_scheduler.analyze",
            ) as analyze, patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "exit-plan", "decision": "ready", "side": "sell",
                    "failedGates": [], "executionEligible": True, "riskExit": position_risk,
                },
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": False}, "tradeApplied": True},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
                return_value={"executionId": "exit-1", "brokerOrderSent": True, "protectiveExit": True},
            ) as execute:
                result = run_automation_scheduler([self.target()], now=self.NOW)
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                policy = load_automation_policy()

        self.assertEqual(result["state"], "protective_exit_executed")
        self.assertTrue(result["brokerOrderSent"])
        self.assertFalse(result.get("autoRevoked", False))
        analyze.assert_not_called()
        self.assertEqual(build.call_args.kwargs["trusted_account"]["holdings"][0]["symbol"], "005930")
        self.assertEqual(build.call_args.kwargs["trusted_position_risk"]["reason"], "hard_stop")
        execute.assert_called_once()
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])
        self.assertEqual(policy["schedulerMode"], "paper_auto")

    def test_tracked_position_protection_runs_before_normal_spacing_and_without_ai(self):
        position_state = {
            "positions": {
                "paper:KRX:005930": {
                    "environment": "paper",
                    "market": "KRX",
                    "symbol": "005930",
                    "quantity": 3,
                },
            },
        }
        holding = {
            "symbol": "005930",
            "market": "KRX",
            "quantity": 3,
            "sellableQuantity": 3,
            "averagePrice": 73000,
        }
        position_risk = {
            "triggered": True,
            "reason": "hard_stop",
            "sellableQuantity": 3,
        }
        with tempfile.TemporaryDirectory() as directory:
            self.enable_auto(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], patch(
                "stock_service.automation_scheduler.load_position_state",
                return_value=position_state,
            ), patch(
                "stock_service.automation_scheduler.market_session_gate",
                return_value={"passed": True, "message": "open"},
            ), patch(
                "stock_service.automation_scheduler.kis_quote",
                return_value={"status": "ok", "symbol": "005930", "market": "KRX", "price": 70000},
            ), patch(
                "stock_service.automation_scheduler.kis_account_summary",
                return_value={"holdings": [holding]},
            ), patch(
                "stock_service.automation_scheduler.observe_position_risk",
                return_value=position_risk,
            ), patch(
                "stock_service.automation_scheduler.analyze",
            ) as analyze, patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "tracked-exit",
                    "decision": "ready",
                    "side": "sell",
                    "failedGates": [],
                    "executionEligible": True,
                    "riskExit": position_risk,
                },
            ) as build, patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {"eligible": False}, "tradeApplied": True},
            ), patch(
                "stock_service.automation_scheduler.execute_automation_plan",
                return_value={"executionId": "exit-1", "brokerOrderSent": True},
            ) as execute, patch(
                "stock_service.automation_scheduler.load_automation_scheduler_runtime",
                return_value={"lastWorkAt": self.NOW},
            ):
                result = run_automation_scheduler([self.target()], now=self.NOW)

        self.assertEqual(result["state"], "protective_exit_executed")
        self.assertTrue(result["brokerOrderSent"])
        self.assertFalse(build.call_args.args[0]["allowEntry"])
        analyze.assert_not_called()
        execute.assert_called_once()

    def test_filled_execution_is_protected_before_first_position_observation(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_scheduler.load_position_state",
            return_value={"positions": {}},
        ):
            path = Path(directory) / "automation-executions.jsonl"
            path.write_text(json.dumps({
                "planId": "filled-us",
                "environment": "paper",
                "market": "NASDAQ",
                "symbol": "AAPL",
                "side": "buy",
                "filledQuantity": 2,
                "brokerState": "filled",
            }) + "\n", encoding="utf-8")
            targets = tracked_protection_targets("paper", directory)

        self.assertEqual([target["id"] for target in targets], ["protect:NASDAQ:AAPL"])
        self.assertTrue(targets[0]["protectOnly"])

    def test_protection_monitor_checks_all_due_positions_per_worker_run(self):
        position_state = {
            "positions": {
                "paper:KRX:005930": {
                    "environment": "paper",
                    "market": "KRX",
                    "symbol": "005930",
                    "quantity": 3,
                },
                "paper:NASDAQ:AAPL": {
                    "environment": "paper",
                    "market": "NASDAQ",
                    "symbol": "AAPL",
                    "quantity": 2,
                },
            },
        }
        runtime = {}
        policy = dict(DEFAULT_AUTOMATION_POLICY, schedulerMode="paper_auto")

        with patch(
            "stock_service.automation_scheduler.load_position_state",
            return_value=position_state,
        ), patch(
            "stock_service.automation_scheduler.market_session_gate",
            return_value={"passed": True, "message": "open"},
        ), patch(
            "stock_service.automation_scheduler.kis_quote",
            return_value={"status": "ok", "price": 100},
        ) as snapshot, patch(
            "stock_service.automation_scheduler.kis_account_summary",
            return_value={"holdings": []},
        ) as account, patch(
            "stock_service.automation_scheduler.observe_position_risk",
            return_value={"triggered": False, "reason": ""},
        ) as observe, patch(
            "stock_service.automation_scheduler.analyze",
        ) as analyze:
            first = monitor_protective_positions(policy, "paper", self.NOW, runtime)

        self.assertEqual(first["checked"], 2)
        self.assertEqual(snapshot.call_count, 2)
        self.assertEqual(account.call_count, 2)
        self.assertEqual(observe.call_count, 2)
        self.assertEqual(
            {
                f"protect:{item['market']}:{item['symbol']}"
                for item in first["observations"]
            },
            {"protect:KRX:005930", "protect:NASDAQ:AAPL"},
        )
        analyze.assert_not_called()

    def test_legacy_capital_loss_halt_recovers_automatically(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable_auto(directory)
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                policy = load_automation_policy()
                policy.update({
                    "enabled": False,
                    "halted": True,
                    "haltReason": "Capital-loss circuit breaker triggered",
                    "haltClass": "capital_loss",
                    "exitOnlyProtection": True,
                })
                save_automation_policy(policy)
                policy = load_automation_policy()
            universe = {"enabled": True}
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                recovered, changed = recover_recoverable_halt(policy, universe)

        self.assertTrue(changed)
        self.assertFalse(recovered["halted"])
        self.assertTrue(recovered["enabled"])
        self.assertEqual(recovered["schedulerMode"], "paper_auto")
        self.assertTrue(recovered["autopilotEnabled"])

    def test_unknown_failure_is_recoverable_but_integrity_failure_is_hard(self):
        self.assertEqual(scheduler_failure_class("unexpected provider response"), "transient")
        self.assertEqual(scheduler_failure_class("internal invariant failed"), "hard")

    def test_target_retry_does_not_block_other_symbols(self):
        first = dict(self.target(), id="first")
        second = dict(self.target(), id="second", symbol="000660")
        runtime = {
            "targets": {
                "first": {"attemptedAt": 0, "retryAt": self.NOW + 300},
                "second": {"attemptedAt": 0},
            },
        }

        due = due_automation_targets(
            [first, second],
            runtime,
            30 * 60,
            self.NOW,
        )

        self.assertEqual([target["id"] for target in due], ["second"])

    def test_transient_network_failures_back_off_without_tripping_kill_switch(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot", side_effect=RuntimeError("network fault"),
            ):
                first = run_automation_scheduler([self.target()], now=self.NOW)
                second = run_automation_scheduler([self.target()], now=self.NOW + 1800)
                third = run_automation_scheduler([self.target()], now=self.NOW + 3600)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(first["state"], "retrying")
        self.assertEqual(second["state"], "retrying")
        self.assertEqual(third["state"], "retrying")
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])
        self.assertEqual(third["transientFailures"], 3)

    def test_rate_limit_recovers_automatically_after_backoff(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            snapshot = {
                "status": "ok",
                "symbol": "005930",
                "market": "KRX",
                "price": 70000,
            }
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                side_effect=[
                    RuntimeError("EGW00201 초당 거래건수를 초과하였습니다"),
                    snapshot,
                ],
            ), patch(
                "stock_service.automation_scheduler.analyze",
                return_value={"status": "ok"},
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "recovered-rate-limit",
                    "decision": "blocked",
                    "side": "buy",
                    "failedGates": ["ai"],
                },
            ), patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": False},
            ):
                failed = run_automation_scheduler([self.target()], now=self.NOW)
                recovered = run_automation_scheduler([self.target()], now=self.NOW + 61)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(failed["state"], "retrying")
        self.assertEqual(failed["failureClass"], "transient")
        self.assertEqual(recovered["state"], "observed")
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])

    def test_ai_quota_recovers_automatically_without_global_halt(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                return_value={
                    "status": "ok",
                    "symbol": "005930",
                    "market": "KRX",
                    "price": 70000,
                },
            ), patch(
                "stock_service.automation_scheduler.analyze",
                side_effect=[
                    RuntimeError("OpenAI quota exceeded; check billing"),
                    {"status": "ok"},
                ],
            ), patch(
                "stock_service.automation_scheduler.build_automation_plan",
                return_value={
                    "planId": "recovered-ai-quota",
                    "decision": "blocked",
                    "side": "buy",
                    "failedGates": ["ai"],
                },
            ), patch(
                "stock_service.automation_scheduler.apply_shadow_plan",
                return_value={"metrics": {}, "promotion": {}, "tradeApplied": False},
            ):
                failed = run_automation_scheduler([self.target()], now=self.NOW)
                recovered = run_automation_scheduler([self.target()], now=self.NOW + 61)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(failed["state"], "operator_action")
        self.assertEqual(failed["failureClass"], "operator")
        self.assertTrue(failed["actionRequired"])
        self.assertEqual(recovered["state"], "observed")
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])

    def test_repeated_hard_failures_still_trip_kill_switch(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], contexts[5], contexts[6], patch(
                "stock_service.automation_scheduler.kis_snapshot",
                side_effect=RuntimeError("internal invariant failed"),
            ):
                first = run_automation_scheduler([self.target()], now=self.NOW)
                second = run_automation_scheduler([self.target()], now=self.NOW + 1800)
                third = run_automation_scheduler([self.target()], now=self.NOW + 3600)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(first["state"], "error")
        self.assertEqual(second["state"], "error")
        self.assertEqual(third["state"], "halted")
        self.assertTrue(policy["halted"])
        self.assertEqual(policy["haltClass"], "hard")

    def test_audit_failure_trips_kill_switch_before_market_work(self):
        with tempfile.TemporaryDirectory() as directory:
            self.enable(directory)
            contexts = self.runtime_patches(directory)
            with contexts[0], contexts[1], contexts[2], patch(
                "stock_service.automation_scheduler.automation_execution_status",
                return_value={"uncertaintyLock": False, "audit": {"healthy": False}},
            ), contexts[4], patch(
                "stock_service.automation_scheduler.kis_snapshot",
            ) as snapshot:
                result = run_automation_scheduler([self.target()], now=self.NOW)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(result["state"], "audit_failure")
        self.assertTrue(result["halted"])
        self.assertTrue(policy["halted"])
        self.assertFalse(policy["enabled"])
        snapshot.assert_not_called()


if __name__ == "__main__":
    unittest.main()
