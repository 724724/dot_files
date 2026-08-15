import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    automation_ai_evidence,
    automation_plan_audit_status,
    automation_control,
    automation_status,
    build_automation_plan,
    load_automation_plans,
    load_automation_policy,
    update_automation_policy,
)
from stock_service.core import StockServiceError


class StockAutomationTests(unittest.TestCase):
    PLAN_TIME = 1_800_000_000

    def payload(self, **values):
        result = {
            "symbol": "005930",
            "market": "KRX",
            "dataMode": "demo",
            "environment": "paper",
            "strategy": "trend",
            "snapshot": {"price": 70000, "buyingPower": 10000000, "updatedAt": self.PLAN_TIME},
            "analysis": {
                "status": "ok",
                "stance": "bullish",
                "confidence": 84,
                "generatedAt": self.PLAN_TIME,
                "downProbability": 12,
                "models": ["model-a", "model-b"],
                "ensembleAgreement": {
                    "status": "high",
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
            },
        }
        result.update(values)
        return result

    def technical(self):
        return {
            "score": 80,
            "stance": "bullish",
            "signalStrength": 80,
            "annualizedVolatilityPct": 18,
            "drawdown60Pct": -2,
        }

    def backtest(self):
        return {
            "status": "ok",
            "walkForward": {
                "status": "robust",
                "oosReturnPct": 8,
                "excessReturnPct": 3,
                "maxDrawdownPct": -6,
                "sharpe": 1.2,
            },
        }

    def mocks(self):
        return (
            patch("stock_service.automation.demo_history_points", return_value=[{"t": i, "v": 100 + i, "volume": 1000000} for i in range(200)]),
            patch("stock_service.automation.technical_screen_metrics", return_value=self.technical()),
            patch("stock_service.automation.run_backtest", return_value=self.backtest()),
        )

    def test_defaults_are_paused_paper_only_dry_run(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            status = automation_status()

        self.assertFalse(status["policy"]["enabled"])
        self.assertTrue(status["policy"]["paperOnly"])
        self.assertEqual(status["policy"]["executionMode"], "dry_run")
        self.assertFalse(status["guarantees"]["noLossGuaranteed"])
        self.assertTrue(status["guarantees"]["paperExecutionAvailable"])

    def test_automation_ai_evidence_defaults_missing_context_to_maximum_risk(self):
        result = automation_ai_evidence({"analysis": {
            "status": "ok",
            "stance": "bullish",
            "confidence": 90,
            "generatedAt": self.PLAN_TIME,
        }})

        self.assertEqual(result["newsStatus"], "insufficient")
        self.assertEqual(result["newsQualityScore"], 0)
        self.assertEqual(result["verifiedDirectNews"], 0)
        self.assertEqual(result["behaviorStatus"], "insufficient")
        self.assertEqual(result["behaviorRiskScore"], 100)
        self.assertEqual(result["behaviorEvidenceConfidence"], 0)

    def test_position_protection_thresholds_are_configurable_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            policy = update_automation_policy({
                "maxPositionLossPercent": 2.5,
                "trailingActivationPercent": 7.5,
                "trailingStopPercent": 1.5,
                "maxRiskPerTradePercent": 0.2,
                "volatilityRiskMultiplier": 2.5,
                "maxSectorExposurePercent": 12,
                "maxCorrelationCoefficient": 0.8,
                "maxPortfolioVar95Percent": 1.5,
                "maxPortfolioCvar95Percent": 2.5,
                "maxStressLossPercent": 7.5,
                "maxSingleDayLossPercent": 4.5,
                "maxMarketParticipationPercent": 0.08,
                "maxBidAskSpreadBps": 15,
                "maxPendingOrderSeconds": 90,
                "maxMarketDataAgeSeconds": 15,
                "maxPlanAgeSeconds": 60,
            })
            bounded = update_automation_policy({
                "maxPositionLossPercent": 0,
                "trailingActivationPercent": 100,
                "trailingStopPercent": 100,
                "maxRiskPerTradePercent": 100,
                "volatilityRiskMultiplier": 100,
                "maxSectorExposurePercent": 100,
                "maxCorrelationCoefficient": 100,
                "maxPortfolioVar95Percent": 100,
                "maxPortfolioCvar95Percent": 100,
                "maxStressLossPercent": 100,
                "maxSingleDayLossPercent": 100,
                "maxMarketParticipationPercent": 100,
                "maxBidAskSpreadBps": 1000,
                "maxPendingOrderSeconds": 10000,
                "maxMarketDataAgeSeconds": 1000,
                "maxPlanAgeSeconds": 1000,
            })

        self.assertEqual(policy["maxPositionLossPercent"], 2.5)
        self.assertEqual(policy["trailingActivationPercent"], 7.5)
        self.assertEqual(policy["trailingStopPercent"], 1.5)
        self.assertEqual(policy["maxRiskPerTradePercent"], 0.2)
        self.assertEqual(policy["volatilityRiskMultiplier"], 2.5)
        self.assertEqual(policy["maxSectorExposurePercent"], 12)
        self.assertEqual(policy["maxCorrelationCoefficient"], 0.8)
        self.assertEqual(policy["maxPortfolioVar95Percent"], 1.5)
        self.assertEqual(policy["maxPortfolioCvar95Percent"], 2.5)
        self.assertEqual(policy["maxStressLossPercent"], 7.5)
        self.assertEqual(policy["maxSingleDayLossPercent"], 4.5)
        self.assertEqual(policy["maxMarketParticipationPercent"], 0.08)
        self.assertEqual(policy["maxBidAskSpreadBps"], 15)
        self.assertEqual(policy["maxPendingOrderSeconds"], 90)
        self.assertEqual(policy["maxMarketDataAgeSeconds"], 15)
        self.assertEqual(policy["maxPlanAgeSeconds"], 60)
        self.assertEqual(bounded["maxPositionLossPercent"], 0.5)
        self.assertEqual(bounded["trailingActivationPercent"], 30)
        self.assertEqual(bounded["trailingStopPercent"], 15)
        self.assertEqual(bounded["maxRiskPerTradePercent"], 2)
        self.assertEqual(bounded["volatilityRiskMultiplier"], 5)
        self.assertEqual(bounded["maxSectorExposurePercent"], 50)
        self.assertEqual(bounded["maxCorrelationCoefficient"], 0.99)
        self.assertEqual(bounded["maxPortfolioVar95Percent"], 10)
        self.assertEqual(bounded["maxPortfolioCvar95Percent"], 15)
        self.assertEqual(bounded["maxStressLossPercent"], 25)
        self.assertEqual(bounded["maxSingleDayLossPercent"], 20)
        self.assertEqual(bounded["maxMarketParticipationPercent"], 1)
        self.assertEqual(bounded["maxBidAskSpreadBps"], 100)
        self.assertEqual(bounded["maxPendingOrderSeconds"], 600)
        self.assertEqual(bounded["maxMarketDataAgeSeconds"], 120)
        self.assertEqual(bounded["maxPlanAgeSeconds"], 300)

    def test_operational_notifications_can_be_disabled_without_unlocking_safety(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            disabled = update_automation_policy({"notificationsEnabled": False})
            enabled = update_automation_policy({"notificationsEnabled": True})

        self.assertFalse(disabled["notificationsEnabled"])
        self.assertTrue(enabled["notificationsEnabled"])
        self.assertTrue(enabled["paperOnly"])

    def test_two_model_requirement_can_be_relaxed_without_unlocking_safety(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            relaxed = update_automation_policy({"requireTwoModels": False})
            restored = update_automation_policy({"requireTwoModels": True})

        self.assertFalse(relaxed["requireTwoModels"])
        self.assertTrue(relaxed["requireAi"])
        self.assertTrue(relaxed["paperOnly"])
        self.assertTrue(restored["requireTwoModels"])

    def test_arming_requires_explicit_confirmation(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            with self.assertRaises(StockServiceError):
                automation_control("arm", {})
            result = automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})

        self.assertTrue(result["policy"]["enabled"])
        self.assertFalse(result["policy"]["halted"])

    def test_automatic_paper_mode_requires_every_promotion_gate(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_scheduler.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_shadow.shadow_status",
            return_value={"promotion": {"eligible": False}},
        ):
            automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})
            automation_control("scheduler-enable", {"confirmation": "ENABLE OBSERVE SCHEDULER"})
            with self.assertRaisesRegex(StockServiceError, "promotion gate"):
                automation_control("scheduler-auto-enable", {
                    "confirmation": "ENABLE PROMOTION-GATED PAPER AUTO",
                })

    def test_automatic_paper_mode_requires_exact_confirmation(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_scheduler.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_shadow.shadow_status",
            return_value={"promotion": {"eligible": True}},
        ):
            automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})
            with self.assertRaisesRegex(StockServiceError, "explicit confirmation"):
                automation_control("scheduler-auto-enable", {})
            result = automation_control("scheduler-auto-enable", {
                "confirmation": "ENABLE PROMOTION-GATED PAPER AUTO",
            })

        self.assertEqual(result["policy"]["schedulerMode"], "paper_auto")

    def test_qualified_plan_is_ready_but_never_sends_an_order(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["decision"], "ready")
        self.assertEqual(result["side"], "buy")
        self.assertEqual(result["quantity"], 1)
        self.assertFalse(result["brokerOrderSent"])
        self.assertEqual(result["executionMode"], "dry_run")

    def test_missing_ai_evidence_blocks_a_buy_plan(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(analysis={}), now=self.PLAN_TIME)

        self.assertEqual(result["decision"], "blocked")
        self.assertIn("ai_available", result["failedGates"])
        self.assertIn("signal_alignment", result["failedGates"])
        self.assertIn("news_status", result["failedGates"])
        self.assertIn("news_quality", result["failedGates"])
        self.assertIn("verified_direct_news", result["failedGates"])
        self.assertIn("behavior_status", result["failedGates"])
        self.assertIn("behavior_risk", result["failedGates"])

    def test_missing_news_and_behavior_context_blocks_an_otherwise_valid_entry(self):
        analysis = dict(self.payload()["analysis"])
        analysis.pop("newsContext")
        analysis.pop("behaviorContext")
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(
                self.payload(analysis=analysis), now=self.PLAN_TIME,
            )

        self.assertEqual(result["side"], "buy")
        self.assertEqual(result["decision"], "blocked")
        self.assertNotIn("ai_available", result["failedGates"])
        self.assertNotIn("ai_confidence", result["failedGates"])
        self.assertIn("news_status", result["failedGates"])
        self.assertIn("news_quality", result["failedGates"])
        self.assertIn("verified_direct_news", result["failedGates"])
        self.assertIn("behavior_status", result["failedGates"])
        self.assertIn("behavior_risk", result["failedGates"])
        self.assertEqual(result["ai"]["behaviorRiskScore"], 100)

    def test_low_quality_news_and_high_behavior_risk_block_entry(self):
        analysis = dict(
            self.payload()["analysis"],
            newsContext={
                "status": "limited",
                "qualityScore": 35,
                "verifiedDirectCount": 0,
                "independentEventCount": 1,
                "sourceQualityScore": 40,
            },
            behaviorContext={
                "status": "limited",
                "riskPenalty": 82,
                "evidenceConfidence": 35,
            },
        )
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(
                self.payload(analysis=analysis), now=self.PLAN_TIME,
            )

        self.assertEqual(result["decision"], "blocked")
        self.assertNotIn("news_status", result["failedGates"])
        self.assertNotIn("behavior_status", result["failedGates"])
        self.assertIn("news_quality", result["failedGates"])
        self.assertIn("verified_direct_news", result["failedGates"])
        self.assertIn("behavior_risk", result["failedGates"])

    def test_stale_market_snapshot_blocks_a_plan(self):
        history, technical, backtest = self.mocks()
        stale_snapshot = {
            "price": 70000,
            "buyingPower": 10000000,
            "updatedAt": self.PLAN_TIME - 31,
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(
                self.payload(snapshot=stale_snapshot), now=self.PLAN_TIME,
            )

        self.assertEqual(result["decision"], "blocked")
        self.assertIn("market_data_freshness", result["failedGates"])
        self.assertEqual(result["marketData"]["ageSeconds"], 31)

    def test_missing_volatility_evidence_blocks_a_buy_plan(self):
        history, _, backtest = self.mocks()
        technical = self.technical()
        technical.pop("annualizedVolatilityPct")
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, patch(
            "stock_service.automation.technical_screen_metrics", return_value=technical,
        ), backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["decision"], "blocked")
        self.assertIn("volatility_data", result["failedGates"])

    def test_high_volatility_reduces_position_size_from_loss_budget(self):
        history, _, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, patch(
            "stock_service.automation.technical_screen_metrics",
            return_value=dict(self.technical(), annualizedVolatilityPct=80),
        ), backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            update_automation_policy({
                "maxOrderValueKrw": 10000000,
                "maxDailyNewExposureKrw": 50000000,
                "maxPositionPercent": 25,
                "cashReservePercent": 20,
                "maxRiskPerTradePercent": 0.25,
                "volatilityRiskMultiplier": 2,
            })
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["quantity"], 3)
        self.assertGreater(result["riskSizing"]["riskDistancePercent"], 10)
        self.assertLess(result["riskSizing"]["positionLimitKrw"], 250000)

    def test_same_sector_holdings_block_additional_concentration(self):
        history, technical, backtest = self.mocks()
        account = {
            "status": "ok",
            "environment": "paper",
            "buyingPower": 8520000,
            "cash": 8520000,
            "totalEvaluation": 10000000,
            "stockEvaluation": 1480000,
            "holdingQuantity": 0,
            "sellableQuantity": 0,
            "holdings": [{
                "symbol": "000660",
                "evaluation": 1480000,
                "quantity": 20,
                "sellableQuantity": 20,
            }],
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest, patch(
            "stock_service.automation.automation_account", return_value=account,
        ):
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["sectorRisk"]["sector"], "memory-semiconductors")
        self.assertEqual(result["quantity"], 0)
        self.assertIn("sector_concentration", result["failedGates"])

    def test_highly_correlated_holding_blocks_new_position(self):
        history, technical, backtest = self.mocks()
        account = {
            "status": "ok",
            "environment": "paper",
            "buyingPower": 9500000,
            "cash": 9500000,
            "totalEvaluation": 10000000,
            "stockEvaluation": 500000,
            "holdingQuantity": 0,
            "sellableQuantity": 0,
            "holdings": [{
                "symbol": "005380",
                "evaluation": 500000,
                "quantity": 2,
                "sellableQuantity": 2,
            }],
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest, patch(
            "stock_service.automation.automation_account", return_value=account,
        ):
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["correlationRisk"]["strongestSymbol"], "005380")
        self.assertAlmostEqual(result["correlationRisk"]["maxCorrelation"], 1)
        self.assertIn("portfolio_correlation", result["failedGates"])

    def test_illiquid_history_blocks_a_new_position(self):
        technical = patch("stock_service.automation.technical_screen_metrics", return_value=self.technical())
        backtest = patch("stock_service.automation.run_backtest", return_value=self.backtest())
        history = patch(
            "stock_service.automation.demo_history_points",
            return_value=[{"t": i, "v": 100 + i, "volume": 1} for i in range(200)],
        )
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertEqual(result["quantity"], 0)
        self.assertTrue(result["liquidityRisk"]["available"])
        self.assertIn("market_participation", result["failedGates"])

    def test_missing_volume_history_forces_abstention(self):
        technical = patch("stock_service.automation.technical_screen_metrics", return_value=self.technical())
        backtest = patch("stock_service.automation.run_backtest", return_value=self.backtest())
        history = patch(
            "stock_service.automation.demo_history_points",
            return_value=[{"t": i, "v": 100 + i} for i in range(200)],
        )
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(self.payload(), now=self.PLAN_TIME)

        self.assertFalse(result["liquidityRisk"]["available"])
        self.assertIn("liquidity_data", result["failedGates"])

    def test_unknown_sector_data_forces_abstention(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(
                self.payload(symbol="999999"), now=self.PLAN_TIME
            )

        self.assertEqual(result["decision"], "blocked")
        self.assertIn("sector_data", result["failedGates"])

    def test_production_environment_is_hard_blocked(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            with self.assertRaisesRegex(StockServiceError, "hard-locked"):
                build_automation_plan(self.payload(environment="prod"))

    def test_duplicate_ready_plan_is_blocked_by_cooldown(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            first = build_automation_plan(self.payload(), now=self.PLAN_TIME)
            second = build_automation_plan(self.payload(snapshot={
                "price": 70000,
                "buyingPower": 10000000,
                "updatedAt": self.PLAN_TIME + 60,
            }), now=self.PLAN_TIME + 60)

        self.assertEqual(first["decision"], "ready")
        self.assertEqual(second["decision"], "blocked")
        self.assertIn("cooldown", second["failedGates"])

    def test_symbol_cooldown_does_not_block_a_different_symbol(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            first = build_automation_plan(self.payload(), now=self.PLAN_TIME)
            other = build_automation_plan(self.payload(
                symbol="000660",
                snapshot={
                    "price": 120000,
                    "buyingPower": 10000000,
                    "updatedAt": self.PLAN_TIME + 60,
                },
                analysis=dict(
                    self.payload()["analysis"],
                    generatedAt=self.PLAN_TIME + 60,
                ),
            ), now=self.PLAN_TIME + 60)

        self.assertEqual(first["decision"], "ready")
        self.assertNotIn("cooldown", other["failedGates"])

    def test_plan_journal_is_hash_chained_and_detects_tampering(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            build_automation_plan(self.payload(), now=self.PLAN_TIME)
            build_automation_plan(self.payload(snapshot={
                "price": 70000,
                "buyingPower": 10000000,
                "updatedAt": self.PLAN_TIME + 60,
            }), now=self.PLAN_TIME + 60)
            plans = load_automation_plans()
            healthy = automation_plan_audit_status()
            path = Path(directory) / "automation-plans.jsonl"
            lines = path.read_text(encoding="utf-8").splitlines()
            changed = json.loads(lines[0])
            changed["decision"] = "blocked"
            lines[0] = json.dumps(changed, ensure_ascii=False, separators=(",", ":"))
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            damaged = automation_plan_audit_status()

        self.assertTrue(healthy["healthy"])
        self.assertEqual(plans[1]["previousHash"], plans[0]["recordHash"])
        self.assertFalse(damaged["healthy"])
        self.assertEqual(damaged["firstError"]["reason"], "record_hash_mismatch")

    def test_loss_limit_blocks_entry_without_disabling_automation(self):
        history, technical, backtest = self.mocks()
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), history, technical, backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            build_automation_plan(self.payload(), now=self.PLAN_TIME)
            falling = self.payload(snapshot={
                "price": 70000,
                "buyingPower": 9900000,
                "updatedAt": self.PLAN_TIME + 300,
            })
            result = build_automation_plan(falling, now=self.PLAN_TIME + 300)
            policy = load_automation_policy()

        self.assertEqual(result["decision"], "blocked")
        self.assertIn("daily_loss", result["failedGates"])
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])

    def test_position_stop_creates_ready_exit_without_ai_or_backtest(self):
        account = {
            "status": "ok",
            "environment": "paper",
            "buyingPower": 0,
            "cash": 9000000,
            "totalEvaluation": 10000000,
            "stockEvaluation": 1000000,
            "holdingQuantity": 3,
            "sellableQuantity": 3,
            "holdings": [{
                "symbol": "005930",
                "quantity": 3,
                "sellableQuantity": 3,
                "averagePrice": 73000,
                "price": 70000,
            }],
        }
        payload = self.payload(
            dataMode="kis",
            snapshot={
                "price": 70000,
                "updatedAt": self.PLAN_TIME,
                "marketSafety": {
                    "checkedAt": self.PLAN_TIME,
                    "available": True,
                    "tradable": True,
                    "viAvailable": True,
                    "viActive": False,
                    "atUpperLimit": False,
                    "atLowerLimit": False,
                    "restricted": False,
                },
            },
            analysis={},
        )
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation.automation_account", return_value=account,
        ), patch(
            "stock_service.automation.kis_history_points",
        ) as history, patch(
            "stock_service.automation.run_backtest",
        ) as backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            result = build_automation_plan(payload, now=self.PLAN_TIME)

        self.assertEqual(result["decision"], "ready")
        self.assertEqual(result["side"], "sell")
        self.assertEqual(result["quantity"], 3)
        self.assertTrue(result["riskExit"]["triggered"])
        self.assertEqual(result["riskExit"]["reason"], "hard_stop")
        self.assertEqual(result["failedGates"], [])
        gate_codes = {gate["code"] for gate in result["gates"]}
        self.assertTrue({
            "news_status",
            "news_quality",
            "verified_direct_news",
            "behavior_status",
            "behavior_risk",
        }.isdisjoint(gate_codes))
        history.assert_not_called()
        backtest.assert_not_called()


if __name__ == "__main__":
    unittest.main()
