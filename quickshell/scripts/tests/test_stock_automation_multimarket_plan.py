import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    automation_control,
    build_automation_plan,
    update_automation_policy,
)


class StockAutomationMultiMarketPlanTests(unittest.TestCase):
    NOW = 1_800_000_000

    def payload(self, allow_entry=True):
        return {
            "symbol": "AAPL",
            "market": "NASDAQ",
            "allowEntry": allow_entry,
            "dataMode": "kis",
            "environment": "paper",
            "strategy": "trend",
            "snapshot": {
                "price": 180,
                "currency": "USD",
                "exchangeRate": 1350,
                "updatedAt": self.NOW,
                "marketSafety": {
                    "checkedAt": self.NOW,
                    "available": True,
                    "tradable": True,
                    "restricted": False,
                },
            },
            "analysis": {
                "status": "ok",
                "stance": "bullish",
                "confidence": 84,
                "downProbability": 12,
                "generatedAt": self.NOW,
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
            },
        }

    def account(self):
        return {
            "status": "ok",
            "environment": "paper",
            "market": "NASDAQ",
            "currency": "USD",
            "exchangeRate": 1350,
            "cash": 10000,
            "buyingPower": 10000,
            "buyingQuantity": 50,
            "totalEvaluation": 10000,
            "stockEvaluation": 0,
            "holdingQuantity": 0,
            "sellableQuantity": 0,
            "holdings": [],
        }

    def test_us_plan_uses_usd_sizing_and_krw_global_limits(self):
        points = [
            {"t": index, "v": 100 + index, "volume": 1000000}
            for index in range(200)
        ]
        technical = {
            "score": 80,
            "stance": "bullish",
            "annualizedVolatilityPct": 18,
        }
        backtest = {
            "walkForward": {
                "status": "robust",
                "oosReturnPct": 8,
                "excessReturnPct": 3,
                "maxDrawdownPct": -6,
                "sharpe": 1.2,
            },
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation.kis_history_points", return_value=points,
        ), patch(
            "stock_service.automation.technical_screen_metrics", return_value=technical,
        ), patch(
            "stock_service.automation.run_backtest", return_value=backtest,
        ) as run_backtest:
            automation_control("arm", {"confirmation": "ARM PAPER DRY RUN"})
            update_automation_policy({
                "maxOrderValueKrw": 1000000,
                "maxDailyNewExposureKrw": 1000000,
            })
            plan = build_automation_plan(
                self.payload(), now=self.NOW, trusted_account=self.account(),
            )
            unselected = build_automation_plan(
                self.payload(False), now=self.NOW + 1, trusted_account=self.account(),
            )

        self.assertEqual(plan["currency"], "USD")
        self.assertEqual(plan["exchangeRate"], 1350)
        self.assertGreater(plan["quantity"], 0)
        self.assertEqual(
            plan["estimatedNotionalKrw"],
            round(plan["estimatedNotional"] * 1350),
        )
        self.assertNotIn("vi_clear", plan["failedGates"])
        self.assertIn("candidate_selected", unselected["failedGates"])
        self.assertEqual(plan["transactionCosts"]["commissionBps"], 25)
        self.assertEqual(plan["transactionCosts"]["sellTaxBps"], 1)
        self.assertEqual(run_backtest.call_args.args[-3:], (25, 5, 1))


if __name__ == "__main__":
    unittest.main()
