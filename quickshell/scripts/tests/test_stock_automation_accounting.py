import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_accounting import (
    automation_accounting_path,
    automation_accounting_status,
    reconcile_automation_accounting,
)
from stock_service.core import StockServiceError


class StockAutomationAccountingTests(unittest.TestCase):
    def account(self, quantity=0):
        return {
            "cash": 10000000 - quantity * 70000,
            "totalEvaluation": 10000000,
            "holdings": ([{"symbol": "005930", "quantity": quantity}] if quantity else []),
        }

    def record(self, quantity=2):
        return {
            "planId": "plan-1",
            "environment": "paper",
            "symbol": "005930",
            "side": "buy",
            "filledQuantity": quantity,
            "averagePrice": 70000,
            "brokerState": "filled",
        }

    def test_repeated_position_reconciliation_becomes_eligible(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.load_execution_records", return_value=[],
        ):
            baseline = reconcile_automation_accounting("paper", trusted_account=self.account())
        self.assertTrue(baseline["healthy"])
        self.assertFalse(baseline["eligible"])

        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ):
            with patch("stock_service.automation_execution.load_execution_records", return_value=[]):
                reconcile_automation_accounting("paper", now=1800000000, trusted_account=self.account())
            with patch("stock_service.automation_execution.load_execution_records", return_value=[self.record()]):
                status = None
                for index in range(4):
                    status = reconcile_automation_accounting(
                        "paper", now=1800000061 + index * 61, trusted_account=self.account(2),
                    )

            self.assertTrue(status["eligible"])
            self.assertEqual(status["summary"]["filledQuantity"], 2)

    def test_manual_position_difference_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ):
            with patch("stock_service.automation_execution.load_execution_records", return_value=[]):
                reconcile_automation_accounting("paper", trusted_account=self.account())
            with patch("stock_service.automation_execution.load_execution_records", return_value=[]):
                status = reconcile_automation_accounting("paper", trusted_account=self.account(1))

        self.assertFalse(status["healthy"])
        self.assertEqual(status["mismatches"][0]["symbol"], "005930")

    def test_tampered_accounting_state_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ), patch("stock_service.automation_execution.load_execution_records", return_value=[]):
            reconcile_automation_accounting("paper", trusted_account=self.account())
            path = Path(automation_accounting_path())
            value = json.loads(path.read_text(encoding="utf-8"))
            value["updatedAt"] += 1
            path.write_text(json.dumps(value), encoding="utf-8")
            self.assertFalse(automation_accounting_status()["healthy"])
            with self.assertRaisesRegex(StockServiceError, "integrity"):
                reconcile_automation_accounting("paper", trusted_account=self.account())

    def test_overseas_fills_reconcile_by_market_and_convert_to_krw(self):
        empty = {"market": "NASDAQ", "holdings": []}
        invested = {
            "market": "NASDAQ",
            "holdings": [{"market": "NASDAQ", "symbol": "AAPL", "quantity": 2}],
        }
        fill = {
            "planId": "us-plan",
            "environment": "paper",
            "market": "NASDAQ",
            "currency": "USD",
            "exchangeRate": 1350,
            "symbol": "AAPL",
            "side": "buy",
            "filledQuantity": 2,
            "averagePrice": 100,
            "brokerState": "filled",
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ):
            with patch("stock_service.automation_execution.load_execution_records", return_value=[]):
                reconcile_automation_accounting("paper", trusted_account=empty)
            with patch("stock_service.automation_execution.load_execution_records", return_value=[fill]):
                status = reconcile_automation_accounting(
                    "paper", now=1_800_000_061, trusted_account=invested,
                )

        self.assertTrue(status["healthy"])
        self.assertEqual(status["mismatches"], [])
        self.assertEqual(status["summary"]["turnoverKrw"], 270000)
        self.assertEqual(status["summary"]["commissionKrw"], 675)
        self.assertEqual(status["summary"]["taxKrw"], 0)

    def test_production_krx_broker_profit_does_not_replace_mixed_market_journal_profit(self):
        fills = [
            {
                "planId": "krx-buy",
                "environment": "prod",
                "market": "KRX",
                "currency": "KRW",
                "exchangeRate": 1,
                "symbol": "005930",
                "side": "buy",
                "filledQuantity": 1,
                "averagePrice": 10000,
                "commission": 0,
                "tax": 0,
                "costSource": "broker",
                "brokerState": "filled",
            },
            {
                "planId": "krx-sell",
                "environment": "prod",
                "market": "KRX",
                "currency": "KRW",
                "exchangeRate": 1,
                "symbol": "005930",
                "side": "sell",
                "filledQuantity": 1,
                "averagePrice": 11000,
                "commission": 0,
                "tax": 0,
                "costSource": "broker",
                "brokerState": "filled",
            },
            {
                "planId": "us-buy",
                "environment": "prod",
                "market": "NASDAQ",
                "currency": "USD",
                "exchangeRate": 1000,
                "symbol": "AAPL",
                "side": "buy",
                "filledQuantity": 1,
                "averagePrice": 100,
                "commission": 0,
                "tax": 0,
                "costSource": "broker",
                "brokerState": "filled",
            },
            {
                "planId": "us-sell",
                "environment": "prod",
                "market": "NASDAQ",
                "currency": "USD",
                "exchangeRate": 1000,
                "symbol": "AAPL",
                "side": "sell",
                "filledQuantity": 1,
                "averagePrice": 110,
                "commission": 0,
                "tax": 0,
                "costSource": "broker",
                "brokerState": "filled",
            },
        ]
        broker_profit = {
            "status": "ok",
            "environment": "prod",
            "exact": True,
            "totals": {"realizedProfitLoss": 777},
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_accounting.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=fills,
        ), patch(
            "stock_service.automation_accounting.kis_period_trade_profit",
            return_value=broker_profit,
        ) as period_profit:
            status = reconcile_automation_accounting(
                "prod",
                now=1_800_000_000,
                trusted_account={"market": "KRX", "holdings": []},
            )

        self.assertTrue(status["healthy"])
        self.assertEqual(status["summary"]["realizedProfitLossKrw"], 11000)
        self.assertEqual(
            status["summary"]["brokerKrxPeriodRealizedProfitLossKrw"],
            777,
        )
        self.assertEqual(status["summary"]["brokerPeriodProfit"], broker_profit)
        period_profit.assert_called_once()


if __name__ == "__main__":
    unittest.main()
