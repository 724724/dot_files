import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    DEFAULT_AUTOMATION_POLICY,
    automation_control,
    load_automation_policy,
    update_automation_policy,
)
from stock_service.automation_universe import (
    autopilot_status,
    autopilot_targets,
    candidate_policy_gates,
    configure_autopilot,
    discover_autopilot_candidates,
    load_autopilot_state,
    normalized_autopilot_universe,
    normalized_autopilot_state,
    profile_autopilot_universe,
    rotating_scan_universe,
    start_autopilot,
    stop_autopilot,
)
from stock_service.core import StockServiceError


class StockAutomationUniverseTests(unittest.TestCase):
    def eligible_candidate(self, **values):
        result = {
            "affordable": True,
            "priceKrw": 70000,
            "technicalScore": 75,
            "aiStatus": "ok",
            "aiStance": "bullish",
            "aiConfidence": 84,
            "downProbability": 12,
            "agreementScore": 88,
            "directConflict": False,
            "modelCount": 2,
            "newsStatus": "usable",
            "newsQualityScore": 82,
            "verifiedDirectNews": 2,
            "behaviorStatus": "usable",
            "behaviorRiskScore": 20,
        }
        result.update(values)
        return result

    def test_candidate_evidence_gates_fail_closed_and_cap_behavior_risk(self):
        missing = self.eligible_candidate(
            newsStatus="insufficient",
            newsQualityScore=0,
            verifiedDirectNews=0,
            behaviorStatus="insufficient",
            behaviorRiskScore=100,
        )
        crowded = self.eligible_candidate(behaviorRiskScore=90)

        missing_gates = {
            gate["code"]: gate["passed"]
            for gate in candidate_policy_gates(missing, DEFAULT_AUTOMATION_POLICY)
        }
        crowded_gates = {
            gate["code"]: gate["passed"]
            for gate in candidate_policy_gates(crowded, DEFAULT_AUTOMATION_POLICY)
        }

        self.assertFalse(missing_gates["news_status"])
        self.assertFalse(missing_gates["news_quality"])
        self.assertFalse(missing_gates["verified_direct_news"])
        self.assertFalse(missing_gates["behavior_status"])
        self.assertFalse(missing_gates["behavior_risk"])
        self.assertTrue(crowded_gates["news_quality"])
        self.assertTrue(crowded_gates["verified_direct_news"])
        self.assertTrue(crowded_gates["behavior_status"])
        self.assertFalse(crowded_gates["behavior_risk"])

    def test_user_watchlist_is_prioritized_and_profile_universe_is_still_included(self):
        custom = [
            {"market": "NYSE", "symbol": f"U{index}"}
            for index in range(24)
        ]

        result = normalized_autopilot_universe(custom)

        self.assertEqual(
            [item["key"] for item in result[:24]],
            [f"NYSE:U{index}" for index in range(24)],
        )
        self.assertGreater(len(result), len(custom))
        self.assertTrue(any(item["key"] == "NASDAQ:AAPL" for item in result))

    def test_profile_universe_covers_all_supported_markets_and_rotates_fairly(self):
        universe = normalized_autopilot_universe([])

        self.assertGreater(len(universe), 24)
        self.assertEqual(
            {item["market"] for item in universe},
            {"KRX", "NASDAQ", "NYSE"},
        )
        visited = []
        cursor = 0
        for _ in range(3):
            batch, cursor = rotating_scan_universe(universe, cursor, 24)
            visited.extend(item["key"] for item in batch)

        self.assertEqual(set(visited), {item["key"] for item in universe})

    def test_legacy_default_universe_migrates_to_profile_universe(self):
        legacy = [
            {"market": "KRX", "symbol": "035720"},
            {"market": "NASDAQ", "symbol": "INTC"},
            {"market": "NYSE", "symbol": "BAC"},
            {"market": "KRX", "symbol": "030200"},
            {"market": "NASDAQ", "symbol": "AAPL"},
            {"market": "NYSE", "symbol": "TSM"},
            {"market": "KRX", "symbol": "005930"},
            {"market": "NASDAQ", "symbol": "NVDA"},
            {"market": "NYSE", "symbol": "JPM"},
            {"market": "KRX", "symbol": "000660"},
            {"market": "NASDAQ", "symbol": "AMD"},
            {"market": "NYSE", "symbol": "XOM"},
            {"market": "KRX", "symbol": "034020"},
            {"market": "NASDAQ", "symbol": "MSFT"},
            {"market": "NYSE", "symbol": "WMT"},
            {"market": "KRX", "symbol": "035420"},
            {"market": "NASDAQ", "symbol": "TSLA"},
            {"market": "NYSE", "symbol": "LLY"},
            {"market": "KRX", "symbol": "005380"},
            {"market": "NASDAQ", "symbol": "GOOGL"},
            {"market": "NYSE", "symbol": "V"},
            {"market": "KRX", "symbol": "373220"},
            {"market": "NASDAQ", "symbol": "META"},
            {"market": "NYSE", "symbol": "JNJ"},
        ]

        migrated = normalized_autopilot_state({"version": 4, "universe": legacy})

        self.assertGreater(len(migrated["universe"]), len(legacy))

    def test_any_legacy_24_stock_scan_is_expanded_without_losing_its_symbols(self):
        legacy = profile_autopilot_universe()[:24]

        migrated = normalized_autopilot_state({"version": 4, "universe": legacy})

        self.assertGreater(len(migrated["universe"]), len(legacy))
        self.assertTrue(
            {item["key"] for item in legacy}.issubset(
                {item["key"] for item in migrated["universe"]}
            )
        )

    def snapshot(self, symbol, market, period, environment):
        return {
            "status": "ok",
            "symbol": symbol,
            "market": market,
            "name": symbol,
            "currency": "KRW" if market == "KRX" else "USD",
            "price": 100,
            "changePct": 1.2,
            "points": [
                {"t": index, "v": 100 + index, "volume": 1000000}
                for index in range(90)
            ],
        }

    def analysis(self, provider, profile, snapshot, force=False):
        return {
            "status": "ok",
            "stance": "bullish",
            "confidence": 84,
            "downProbability": 12,
            "generatedAt": 1_900_000_000,
            "summary": "Positive trend with bounded downside.",
            "newsSignal": "positive",
            "chartSignal": "bullish",
            "newsCount": 5,
            "models": ["one", "two"],
            "ensembleAgreement": {
                "agreementScore": 88,
                "modelCount": 2,
                "directConflict": False,
            },
            "newsContext": {
                "status": "usable",
                "qualityScore": 82,
                "verifiedDirectCount": 2,
                "independentEventCount": 4,
                "sourceQualityScore": 85,
            },
            "behaviorContext": {
                "status": "usable",
                "riskPenalty": 20,
                "evidenceConfidence": 78,
            },
        }

    def context(self, directory):
        return (
            patch("stock_service.automation.state_directory", return_value=directory),
            patch("stock_service.automation_universe.state_directory", return_value=directory),
            patch("stock_service.automation_universe.kis_snapshot", side_effect=self.snapshot),
            patch("stock_service.automation_universe.analyze", side_effect=self.analysis),
            patch("stock_service.automation_universe.technical_screen_metrics", return_value={
                "score": 72,
                "stance": "bullish",
                "momentum20Pct": 8,
                "drawdown60Pct": -3,
                "annualizedVolatilityPct": 18,
            }),
        )

    def test_discovery_supports_krx_and_us_candidates(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4]:
                result = discover_autopilot_candidates({
                    "environment": "paper",
                    "aiProvider": "both",
                    "analysisProfile": "balanced",
                })

        markets = {item["market"] for item in result["candidates"]}
        self.assertTrue({"KRX", "NASDAQ", "NYSE"}.issubset(markets))
        self.assertEqual(result["phase"], "ready")
        self.assertGreater(result["selectedCount"], 0)

    def test_manual_selection_controls_entry_without_dropping_monitors(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4]:
                discovered = discover_autopilot_candidates({
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                selected = discovered["candidates"][1]["key"]
                configured = configure_autopilot({
                    "automaticSelection": False,
                    "selectedKeys": [selected],
                })
                targets = autopilot_targets()

        self.assertEqual(configured["selectedKeys"], [selected])
        self.assertEqual(len(targets), 1)
        self.assertTrue(targets[0]["allowEntry"])

    def test_one_button_start_recovers_an_intentional_manual_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2] as snapshot, contexts[3], contexts[4], patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                running = start_autopilot({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                policy = load_automation_policy()
                stopped = stop_autopilot({
                    "confirmation": "EMERGENCY STOP AI AUTOPILOT",
                }, emergency=True)
                stopped_policy = load_automation_policy()
                restarted = start_autopilot({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                reset_policy = load_automation_policy()

        snapshot.assert_not_called()
        self.assertTrue(running["enabled"])
        self.assertEqual(running["phase"], "researching")
        self.assertTrue(policy["autopilotEnabled"])
        self.assertEqual(policy["executionMode"], "paper")
        self.assertFalse(stopped["enabled"])
        self.assertTrue(stopped_policy["halted"])
        self.assertTrue(restarted["enabled"])
        self.assertFalse(reset_policy["halted"])

    def test_one_button_start_defaults_back_to_automatic_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                discover_autopilot_candidates({
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                configure_autopilot({
                    "automaticSelection": False,
                    "selectedKeys": [],
                })
                running = start_autopilot({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                    "environment": "paper",
                    "aiProvider": "openai",
                })

        self.assertTrue(running["enabled"])
        self.assertTrue(running["automaticSelection"])

    def test_production_discovery_preserves_environment_for_candidates_and_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2] as snapshot, contexts[3], contexts[4]:
                result = discover_autopilot_candidates({
                    "environment": "prod",
                    "aiProvider": "openai",
                })
                targets = autopilot_targets()

        self.assertEqual(result["environment"], "prod")
        self.assertFalse(result["paperOnly"])
        self.assertTrue(result["candidates"])
        self.assertTrue(targets)
        self.assertTrue(all(target["environment"] == "prod" for target in targets))
        self.assertTrue(all(call.args[3] == "prod" for call in snapshot.call_args_list))

    def test_live_start_requires_exact_confirmation_and_preserves_live_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.core.load_risk_policy",
                return_value={"productionEnabled": True},
            ), patch(
                "stock_service.automation_live.automation_live_status",
                return_value={"productionAutomationEligible": True},
            ), patch(
                "stock_service.automation_scheduler.load_automation_scheduler_runtime",
                return_value={"consecutiveFailures": 0},
            ), patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                update_automation_policy({"liveConsent": True})
                discover_autopilot_candidates({
                    "environment": "prod",
                    "aiProvider": "openai",
                })
                with self.assertRaisesRegex(StockServiceError, "exact environment confirmation"):
                    start_autopilot({
                        "confirmation": "START KIS PAPER AUTOPILOT",
                        "environment": "prod",
                        "aiProvider": "openai",
                    })
                running = start_autopilot({
                    "confirmation": "START KIS LIVE AUTOPILOT",
                    "environment": "prod",
                    "aiProvider": "openai",
                })
                targets = autopilot_targets()
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "exact confirmation"):
                    stop_autopilot({
                        "confirmation": "STOP KIS PAPER AUTOPILOT",
                    })
                stopped = stop_autopilot({
                    "confirmation": "STOP KIS LIVE AUTOPILOT",
                })

        self.assertTrue(running["enabled"])
        self.assertEqual(running["environment"], "prod")
        self.assertFalse(running["paperOnly"])
        self.assertEqual(policy["executionMode"], "live")
        self.assertTrue(policy["autopilotEnabled"])
        self.assertTrue(any(target["allowEntry"] for target in targets))
        self.assertTrue(all(target["environment"] == "prod" for target in targets))
        self.assertFalse(stopped["enabled"])
        self.assertEqual(stopped["phase"], "stopped")

    def test_live_start_fails_closed_when_any_readiness_gate_is_false(self):
        cases = (
            ("consent", False, True, True, "risk consent"),
            ("production", True, False, True, "Unlock production"),
            ("readiness", True, True, False, "live-readiness gate"),
        )
        for name, consent, production, readiness, message in cases:
            with self.subTest(gate=name), tempfile.TemporaryDirectory() as directory:
                contexts = self.context(directory)
                with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                    "stock_service.core.load_risk_policy",
                    return_value={"productionEnabled": production},
                ), patch(
                    "stock_service.automation_live.automation_live_status",
                    return_value={"productionAutomationEligible": readiness},
                ), patch(
                    "stock_service.automation_scheduler.load_automation_scheduler_runtime",
                    return_value={"consecutiveFailures": 0},
                ), patch(
                    "stock_service.automation_execution.automation_audit_status",
                    return_value={"healthy": True},
                ):
                    update_automation_policy({"liveConsent": consent})
                    discover_autopilot_candidates({
                        "environment": "prod",
                        "aiProvider": "openai",
                    })
                    with self.assertRaisesRegex(StockServiceError, message):
                        start_autopilot({
                            "confirmation": "START KIS LIVE AUTOPILOT",
                            "environment": "prod",
                            "aiProvider": "openai",
                        })
                    policy = load_automation_policy()
                    status = autopilot_status()

                self.assertFalse(policy["enabled"])
                self.assertFalse(policy["autopilotEnabled"])
                self.assertFalse(status["enabled"])

    def test_start_keeps_researching_when_automatic_selection_has_no_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], patch(
                "stock_service.automation_universe.technical_screen_metrics",
                return_value={
                    "score": -20,
                    "stance": "bearish",
                    "momentum20Pct": -4,
                    "drawdown60Pct": -10,
                    "annualizedVolatilityPct": 20,
                },
            ), patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                running = start_autopilot({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                targets = autopilot_targets()

        self.assertTrue(running["enabled"])
        self.assertEqual(running["selectedCount"], 0)
        self.assertEqual(targets, [])

    def test_stop_during_startup_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4]:
                discover_autopilot_candidates({
                    "environment": "paper",
                    "aiProvider": "openai",
                })

                def stop_during_audit():
                    stop_autopilot({
                        "confirmation": "STOP KIS PAPER AUTOPILOT",
                    })
                    return {"healthy": True}

                with patch(
                    "stock_service.automation_execution.automation_audit_status",
                    side_effect=stop_during_audit,
                ):
                    with self.assertRaisesRegex(StockServiceError, "stopped while startup"):
                        start_autopilot({
                            "confirmation": "START KIS PAPER AUTOPILOT",
                            "environment": "paper",
                            "aiProvider": "openai",
                        })
                policy = load_automation_policy()
                status = autopilot_status()

        self.assertFalse(policy["enabled"])
        self.assertFalse(status["enabled"])

    def test_emergency_stop_during_discovery_cannot_be_revived_by_scan_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                start_autopilot({
                    "confirmation": "START KIS PAPER AUTOPILOT",
                    "environment": "paper",
                    "aiProvider": "openai",
                })
                before = load_autopilot_state()
                stopped = False

                def stop_during_snapshot(symbol, market, period, environment):
                    nonlocal stopped
                    if not stopped:
                        stopped = True
                        stop_autopilot({
                            "confirmation": "EMERGENCY STOP AI AUTOPILOT",
                        }, emergency=True)
                    return self.snapshot(symbol, market, period, environment)

                with patch(
                    "stock_service.automation_universe.kis_snapshot",
                    side_effect=stop_during_snapshot,
                ):
                    result = discover_autopilot_candidates({
                        "environment": "paper",
                        "aiProvider": "openai",
                    })
                persisted = load_autopilot_state()
                policy = load_automation_policy()

        self.assertFalse(result["enabled"])
        self.assertEqual(result["phase"], "safety_halted")
        self.assertFalse(persisted["enabled"])
        self.assertEqual(persisted["phase"], "safety_halted")
        self.assertEqual(
            persisted["stopGeneration"],
            before["stopGeneration"] + 1,
        )
        self.assertEqual(persisted["lastScanAt"], before["lastScanAt"])
        self.assertTrue(policy["halted"])

    def test_discovery_commits_partial_scan_when_time_budget_is_exhausted(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.context(directory)
            clock = {"now": 0}

            def timed_snapshot(symbol, market, period, environment):
                clock["now"] += 3
                return self.snapshot(symbol, market, period, environment)

            with contexts[0], contexts[1], patch(
                "stock_service.automation_universe.kis_snapshot",
                side_effect=timed_snapshot,
            ) as snapshot, contexts[3], contexts[4], patch(
                "stock_service.automation_universe.time.monotonic",
                side_effect=lambda: clock["now"],
            ), patch(
                "stock_service.automation_universe.AUTOPILOT_TECHNICAL_SCAN_BUDGET_SECONDS",
                5,
            ), patch(
                "stock_service.automation_universe.AUTOPILOT_SCAN_BUDGET_SECONDS",
                6,
            ):
                result = discover_autopilot_candidates({
                    "environment": "paper",
                    "aiProvider": "openai",
                })

        self.assertEqual(snapshot.call_count, 2)
        self.assertEqual(result["research"]["scannedCount"], 2)
        self.assertEqual(result["research"]["requestedCount"], 24)
        self.assertTrue(result["research"]["budgetExhausted"])
        self.assertEqual(result["phase"], "degraded")
        self.assertEqual(
            result["lastError"],
            "Candidate refresh reached its time budget",
        )


if __name__ == "__main__":
    unittest.main()
