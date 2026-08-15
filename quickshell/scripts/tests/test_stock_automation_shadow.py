import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_shadow import (
    PROMOTION_THRESHOLDS,
    apply_shadow_plan,
    execution_quality,
    reset_shadow_portfolio,
    shadow_promotion,
    shadow_status,
)
from stock_service.core import StockServiceError


class StockAutomationShadowTests(unittest.TestCase):
    NOW = 1_800_018_000

    def plan(self, plan_id, side="buy", price=100000, decision="ready"):
        return {
            "planId": plan_id,
            "symbol": "005930",
            "decision": decision,
            "side": side,
            "quantity": 1,
            "price": price,
        }

    def paths(self, directory):
        return (
            patch("stock_service.automation.state_directory", return_value=directory),
            patch("stock_service.automation_shadow.state_directory", return_value=directory),
            patch("stock_service.automation_execution.state_directory", return_value=directory),
        )

    def test_shadow_portfolio_starts_with_cash_and_no_trades(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_shadow.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_shadow.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_shadow.load_execution_records", return_value=[],
        ):
            result = shadow_status()

        self.assertEqual(result["metrics"]["totalEquityKrw"], 10000000)
        self.assertEqual(result["metrics"]["trades"], 0)
        self.assertFalse(result["promotion"]["eligible"])
        self.assertTrue(result["promotion"]["autoExecutionLocked"])

    def test_buy_plan_applies_costs_once(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.paths(directory)
            with contexts[0], contexts[1], contexts[2], patch(
                "stock_service.automation_shadow.automation_execution_status",
                return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
            ), patch(
                "stock_service.automation_shadow.load_execution_records", return_value=[],
            ):
                first = apply_shadow_plan(self.plan("buy-1"), 100000, self.NOW)
                second = apply_shadow_plan(self.plan("buy-1"), 100000, self.NOW + 1)

        self.assertTrue(first["tradeApplied"])
        self.assertEqual(first["metrics"]["trades"], 1)
        self.assertGreater(first["metrics"]["totalCostsKrw"], 0)
        self.assertTrue(second["duplicate"])
        self.assertEqual(second["metrics"]["observations"], 1)

    def test_sell_plan_records_realized_profit(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.paths(directory)
            with contexts[0], contexts[1], contexts[2], patch(
                "stock_service.automation_shadow.automation_execution_status",
                return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
            ), patch(
                "stock_service.automation_shadow.load_execution_records", return_value=[],
            ):
                apply_shadow_plan(self.plan("buy-1"), 100000, self.NOW)
                result = apply_shadow_plan(self.plan("sell-1", side="sell", price=110000), 110000, self.NOW + 86400)

        self.assertTrue(result["tradeApplied"])
        self.assertEqual(result["metrics"]["closedTrades"], 1)
        self.assertEqual(result["metrics"]["wins"], 1)
        self.assertGreater(result["metrics"]["realizedPnlKrw"], 0)

    def test_us_shadow_trade_converts_prices_and_costs_to_krw(self):
        buy = {
            "planId": "us-buy",
            "symbol": "AAPL",
            "market": "NASDAQ",
            "currency": "USD",
            "exchangeRate": 1350,
            "decision": "ready",
            "side": "buy",
            "quantity": 2,
            "price": 100,
            "transactionCosts": {
                "commissionBps": 25,
                "slippageBps": 5,
                "sellTaxBps": 1,
            },
        }
        sell = dict(buy, planId="us-sell", side="sell", price=110)
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.paths(directory)
            with contexts[0], contexts[1], contexts[2], patch(
                "stock_service.automation_shadow.automation_execution_status",
                return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
            ), patch(
                "stock_service.automation_shadow.load_execution_records", return_value=[],
            ), patch(
                "stock_service.automation_shadow.load_automation_policy",
                return_value={
                    "cashReservePercent": 70,
                    "maxOrderValueKrw": 1000000,
                    "usCommissionBps": 25,
                    "usSellFeeBps": 1,
                    "assumedSlippageBps": 5,
                },
            ):
                after_buy = apply_shadow_plan(buy, 100, self.NOW)
                after_sell = apply_shadow_plan(sell, 110, self.NOW + 86400)

        self.assertEqual(after_buy["positions"][0]["market"], "NASDAQ")
        self.assertGreater(after_buy["metrics"]["turnoverKrw"], 270000)
        self.assertEqual(after_sell["metrics"]["openPositions"], 0)
        self.assertGreater(after_sell["metrics"]["realizedPnlKrw"], 0)

    def test_blocked_plan_marks_to_market_without_trading(self):
        with tempfile.TemporaryDirectory() as directory:
            contexts = self.paths(directory)
            with contexts[0], contexts[1], contexts[2], patch(
                "stock_service.automation_shadow.automation_execution_status",
                return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
            ), patch(
                "stock_service.automation_shadow.load_execution_records", return_value=[],
            ):
                apply_shadow_plan(self.plan("buy-1"), 100000, self.NOW)
                result = apply_shadow_plan(
                    self.plan("blocked-1", price=80000, decision="blocked"), 80000, self.NOW + 86400,
                )

        self.assertFalse(result["tradeApplied"])
        self.assertEqual(result["metrics"]["trades"], 1)
        self.assertLess(result["metrics"]["maxDrawdownPercent"], 0)

    def test_promotion_unlocks_only_the_paper_auto_capability(self):
        metrics = {
            "observations": PROMOTION_THRESHOLDS["observations"],
            "sessions": PROMOTION_THRESHOLDS["sessions"],
            "closedTrades": PROMOTION_THRESHOLDS["closedTrades"],
            "netReturnPercent": 8,
            "excessReturnPercent": 3,
            "maxDrawdownPercent": -2,
            "profitFactor": 1.8,
            "winRatePercent": 60,
        }
        fills = [{
            "brokerState": "filled",
            "side": "buy",
            "price": 100000,
            "averagePrice": 100020,
        } for _ in range(PROMOTION_THRESHOLDS["manualPaperFills"])]
        with patch(
            "stock_service.automation_shadow.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_shadow.load_execution_records", return_value=fills,
        ), patch(
            "stock_service.automation_shadow.automation_accounting_status",
            return_value={"eligible": True},
        ), patch(
            "stock_service.automation_shadow.automation_resilience_status",
            return_value={"eligible": True},
        ):
            result = shadow_promotion(metrics)

        self.assertTrue(result["eligible"])
        self.assertFalse(result["autoExecutionLocked"])
        self.assertTrue(result["productionLocked"])

    def test_execution_quality_measures_adverse_buy_and_sell_slippage(self):
        quality = execution_quality([
            {"brokerState": "filled", "side": "buy", "price": 100, "averagePrice": 101},
            {"brokerState": "filled", "side": "sell", "price": 100, "averagePrice": 99},
        ])

        self.assertEqual(quality["fillRatePercent"], 100)
        self.assertEqual(quality["averageAdverseSlippageBps"], 100)
        self.assertEqual(quality["p90AdverseSlippageBps"], 100)

    def test_poor_execution_quality_blocks_paper_auto_promotion(self):
        metrics = {
            "observations": PROMOTION_THRESHOLDS["observations"],
            "sessions": PROMOTION_THRESHOLDS["sessions"],
            "closedTrades": PROMOTION_THRESHOLDS["closedTrades"],
            "netReturnPercent": 8,
            "excessReturnPercent": 3,
            "maxDrawdownPercent": -2,
            "profitFactor": 1.8,
            "winRatePercent": 60,
        }
        fills = [{
            "brokerState": "filled",
            "side": "buy",
            "price": 100000,
            "averagePrice": 100500,
        } for _ in range(PROMOTION_THRESHOLDS["manualPaperFills"])]
        with patch(
            "stock_service.automation_shadow.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_shadow.load_execution_records", return_value=fills,
        ):
            result = shadow_promotion(metrics)

        failed = [gate["code"] for gate in result["gates"] if not gate["passed"]]
        self.assertFalse(result["eligible"])
        self.assertIn("execution_slippage", failed)

    def test_low_fill_rate_blocks_paper_auto_promotion(self):
        metrics = {
            "observations": PROMOTION_THRESHOLDS["observations"],
            "sessions": PROMOTION_THRESHOLDS["sessions"],
            "closedTrades": PROMOTION_THRESHOLDS["closedTrades"],
            "netReturnPercent": 8,
            "excessReturnPercent": 3,
            "maxDrawdownPercent": -2,
            "profitFactor": 1.8,
            "winRatePercent": 60,
        }
        records = [{
            "brokerState": "filled",
            "side": "buy",
            "price": 100000,
            "averagePrice": 100020,
        } for _ in range(PROMOTION_THRESHOLDS["manualPaperFills"])]
        records.extend({"brokerState": "canceled"} for _ in range(10))
        with patch(
            "stock_service.automation_shadow.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_shadow.load_execution_records", return_value=records,
        ):
            result = shadow_promotion(metrics)

        failed = [gate["code"] for gate in result["gates"] if not gate["passed"]]
        self.assertFalse(result["eligible"])
        self.assertIn("paper_fill_rate", failed)

    def test_shadow_reset_requires_exact_confirmation(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_shadow.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_shadow.automation_execution_status",
            return_value={"uncertaintyLock": False, "audit": {"healthy": True}},
        ), patch(
            "stock_service.automation_shadow.load_execution_records", return_value=[],
        ):
            with self.assertRaises(StockServiceError):
                reset_shadow_portfolio({})
            result = reset_shadow_portfolio({"confirmation": "RESET SHADOW PORTFOLIO"})

        self.assertEqual(result["metrics"]["totalEquityKrw"], 10000000)


if __name__ == "__main__":
    unittest.main()
