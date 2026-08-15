import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_ownership import (
    managed_account_view,
    managed_position_ledger,
    managed_position_ownership,
)
from stock_service.automation_scheduler import planning_account_ownership
from stock_service.core import StockServiceError


class StockAutomationOwnershipTests(unittest.TestCase):
    def account(self, quantity=10, sellable=8):
        return {
            "holdingQuantity": quantity,
            "sellableQuantity": sellable,
            "totalEvaluation": 1000000,
            "holdings": [{
                "market": "KRX",
                "symbol": "005930",
                "quantity": quantity,
                "sellableQuantity": sellable,
                "price": 70000,
                "evaluation": quantity * 70000,
            }, {
                "market": "NASDAQ",
                "symbol": "AAPL",
                "quantity": 3,
                "sellableQuantity": 3,
                "price": 200,
                "evaluation": 600,
            }],
        }

    def test_ledger_tracks_confirmed_net_fills_by_environment_and_instrument(self):
        records = [
            {
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 4,
            },
            {
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "sell",
                "brokerState": "partial",
                "filledQuantity": 1,
            },
            {
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "sell",
                "brokerState": "canceled",
                "filledQuantity": 1,
            },
            {
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "accepted",
                "filledQuantity": 4,
            },
            {
                "environment": "paper",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 20,
            },
            {
                "environment": "prod",
                "market": "NASDAQ",
                "symbol": "AAPL",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 3,
            },
        ]

        ledger = managed_position_ledger(records, "prod")

        self.assertTrue(ledger["healthy"])
        self.assertEqual(ledger["quantities"]["prod:KRX:005930"], 2)
        self.assertEqual(ledger["fillCounts"]["prod:KRX:005930"], 3)
        self.assertEqual(ledger["quantities"]["prod:NASDAQ:AAPL"], 3)
        self.assertNotIn("paper:KRX:005930", ledger["quantities"])

    def test_ownership_separates_manual_and_managed_quantity(self):
        ownership = managed_position_ownership(
            [{
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 2,
            }],
            self.account(),
            "prod",
            "KRX",
            "005930",
        )

        self.assertEqual(ownership["journalQuantity"], 2)
        self.assertEqual(ownership["managedQuantity"], 2)
        self.assertEqual(ownership["managedSellableQuantity"], 2)
        self.assertEqual(ownership["manualQuantity"], 8)
        self.assertTrue(ownership["mixedWithManual"])

    def test_managed_account_view_caps_only_the_target_holding(self):
        source = self.account()
        ownership = managed_position_ownership(
            [{
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 2,
            }],
            source,
            "prod",
            "KRX",
            "005930",
        )

        result = managed_account_view(source, ownership, 71000)

        self.assertEqual(result["holdingQuantity"], 2)
        self.assertEqual(result["sellableQuantity"], 2)
        self.assertEqual(result["holdings"][0]["quantity"], 2)
        self.assertEqual(result["holdings"][0]["evaluation"], 142000)
        self.assertEqual(result["holdings"][1], source["holdings"][1])
        self.assertEqual(source["holdingQuantity"], 10)
        self.assertEqual(source["holdings"][0]["quantity"], 10)

    def test_negative_managed_position_is_rejected(self):
        records = [{
            "environment": "prod",
            "market": "KRX",
            "symbol": "005930",
            "side": "sell",
            "brokerState": "filled",
            "filledQuantity": 1,
        }]

        with self.assertRaisesRegex(StockServiceError, "negative net quantity"):
            managed_position_ownership(
                records,
                self.account(),
                "prod",
                "KRX",
                "005930",
            )

    def test_scheduler_planning_caps_production_but_not_paper(self):
        records = [{
            "environment": "prod",
            "market": "KRX",
            "symbol": "005930",
            "side": "buy",
            "brokerState": "partial",
            "filledQuantity": 2,
        }]
        source = self.account()

        with patch(
            "stock_service.automation_scheduler.load_execution_records",
            return_value=records,
        ):
            production, ownership = planning_account_ownership(
                source,
                "prod",
                "KRX",
                "005930",
                70000,
            )
            paper, paper_ownership = planning_account_ownership(
                source,
                "paper",
                "KRX",
                "005930",
                70000,
            )

        self.assertEqual(production["holdingQuantity"], 2)
        self.assertTrue(ownership["mixedWithManual"])
        self.assertIs(paper, source)
        self.assertEqual(paper_ownership, {})


if __name__ == "__main__":
    unittest.main()
