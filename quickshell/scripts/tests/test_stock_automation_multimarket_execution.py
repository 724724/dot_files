import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import DEFAULT_AUTOMATION_POLICY, automation_plan_integrity_key
from stock_service.core import StockServiceError
from stock_service.automation_execution import (
    append_execution_event,
    execution_preflight,
    execute_automation_plan,
    market_session_gate,
    overseas_orderbook,
    reconcile_automation_executions,
)


class StockAutomationMultiMarketExecutionTests(unittest.TestCase):
    NOW = int(datetime(2027, 7, 6, 10, 0, 10, tzinfo=ZoneInfo("America/New_York")).timestamp())

    def policy(self):
        return dict(
            DEFAULT_AUTOMATION_POLICY,
            enabled=True,
            halted=False,
            executionMode="paper",
            maxOrderValueKrw=1000000,
            maxDailyNewExposureKrw=1000000,
            maxBidAskSpreadBps=100,
        )

    def plan(self, side="buy", protective=False):
        plan = {
            "integrityVersion": 2,
            "planId": "us-plan",
            "createdAt": self.NOW - 10,
            "environment": "paper",
            "dataMode": "kis",
            "executionMode": "paper",
            "decision": "ready",
            "executionEligible": True,
            "gates": [],
            "market": "NASDAQ",
            "symbol": "AAPL",
            "side": side,
            "quantity": 1,
            "price": 180,
            "riskExit": {"triggered": protective},
            "correlationRisk": {
                "available": True,
                "maxCorrelation": 0,
                "evaluatedSymbols": [],
            },
            "liquidityRisk": {
                "available": True,
                "medianDailyTurnoverKrw": 100000000000,
            },
            "portfolioTailRisk": {"available": True, "passed": True},
            "riskSizing": {
                "annualizedVolatilityPercent": 10,
                "riskDistancePercent": 3,
            },
        }
        plan["executionKey"] = automation_plan_integrity_key(plan)
        return plan

    def account(self, side="buy"):
        holding = {
            "market": "NASDAQ",
            "symbol": "AAPL",
            "quantity": 1,
            "sellableQuantity": 1,
            "evaluation": 180,
        }
        return {
            "status": "ok",
            "environment": "paper",
            "market": "NASDAQ",
            "currency": "USD",
            "exchangeRate": 1380,
            "buyingPower": 10000,
            "buyingQuantity": 10,
            "cash": 10000,
            "totalEvaluation": 10000,
            "holdingQuantity": 0 if side == "buy" else 1,
            "sellableQuantity": 0 if side == "buy" else 1,
            "holdings": [] if side == "buy" else [holding],
        }

    def quote(self):
        return {
            "status": "ok",
            "market": "NASDAQ",
            "currency": "USD",
            "price": 180,
            "updatedAt": self.NOW,
            "marketSafety": {
                "available": True,
                "tradable": True,
                "restricted": False,
            },
        }

    def book(self):
        return {
            "market": "NASDAQ",
            "currency": "USD",
            "ask": 180.01,
            "bid": 179.99,
            "askQuantity": 100,
            "bidQuantity": 100,
            "quoteTimestamp": self.NOW - 1,
            "quoteAgeSeconds": 1,
        }

    def test_us_session_gate_uses_new_york_clock_across_dst(self):
        summer = datetime(2027, 7, 6, 10, 0, tzinfo=ZoneInfo("America/New_York"))
        winter = datetime(2027, 1, 5, 10, 0, tzinfo=ZoneInfo("America/New_York"))
        too_early = datetime(2027, 7, 6, 9, 39, tzinfo=ZoneInfo("America/New_York"))

        self.assertTrue(market_session_gate("paper", int(summer.timestamp()), "NASDAQ")["passed"])
        self.assertTrue(market_session_gate("paper", int(winter.timestamp()), "NYSE")["passed"])
        self.assertFalse(market_session_gate("paper", int(too_early.timestamp()), "NASDAQ")["passed"])

    def test_us_orderbook_uses_official_rest_transaction_and_market_timestamp(self):
        response = {
            "output1": {"curr": "USD", "dymd": "20270706", "dhms": "100000"},
            "output2": {"pask1": "180.01", "pbid1": "179.99", "vask1": "20", "vbid1": "15"},
        }
        with patch(
            "stock_service.automation_execution.kis_get",
            return_value=response,
        ) as request:
            result = overseas_orderbook("paper", "AAPL", "NASDAQ", self.NOW)

        self.assertEqual(result["quoteAgeSeconds"], 10)
        self.assertEqual(result["ask"], 180.01)
        request.assert_called_once_with(
            "paper",
            "/uapi/overseas-price/v1/quotations/inquire-asking-price",
            "HHDFS76200100",
            {"AUTH": "", "EXCD": "NAS", "SYMB": "AAPL"},
        )

    def test_us_preflight_uses_fresh_marketable_limit_and_krw_risk_value(self):
        plan = self.plan()
        with patch(
            "stock_service.automation_execution.automation_audit_status",
            return_value={"healthy": True},
        ), patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=[],
        ), patch(
            "stock_service.automation_execution.market_session_gate",
            return_value={"passed": True, "sessionDate": "2027-07-06", "message": "open"},
        ), patch(
            "stock_service.automation_execution.kis_quote",
            return_value=self.quote(),
        ) as quote, patch(
            "stock_service.automation_execution.overseas_orderbook",
            return_value=self.book(),
        ), patch(
            "stock_service.automation_execution.kis_account_summary",
            return_value=self.account(),
        ) as account, patch(
            "stock_service.automation_execution.market_risk_snapshot",
            return_value={"dailyReturnPercent": 0, "drawdownPercent": 0},
        ), patch(
            "stock_service.automation_execution.portfolio_sector_risk",
            return_value={"available": True, "projectedExposurePercent": 2},
        ):
            result = execution_preflight(plan, self.policy(), self.NOW)

        self.assertEqual(result["market"], "NASDAQ")
        self.assertEqual(result["orderType"], "limit")
        self.assertEqual(result["currentPrice"], 180.01)
        self.assertEqual(result["estimatedNotionalKrw"], round(180.01 * 1380))
        self.assertEqual(quote.call_args.args[:3], ("AAPL", "NASDAQ", "paper"))
        self.assertEqual(account.call_args.args, ("paper", "AAPL", 180.01, "limit", "NASDAQ"))

    def test_us_protective_exit_remains_a_limit_order(self):
        plan = self.plan("sell", True)
        with patch(
            "stock_service.automation_execution.automation_audit_status",
            return_value={"healthy": True},
        ), patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=[],
        ), patch(
            "stock_service.automation_execution.market_session_gate",
            return_value={"passed": True, "sessionDate": "2027-07-06", "message": "open"},
        ), patch(
            "stock_service.automation_execution.kis_quote",
            return_value=self.quote(),
        ), patch(
            "stock_service.automation_execution.overseas_orderbook",
            return_value=self.book(),
        ), patch(
            "stock_service.automation_execution.kis_account_summary",
            return_value=self.account("sell"),
        ), patch(
            "stock_service.automation_execution.market_risk_snapshot",
            return_value={"dailyReturnPercent": 0, "drawdownPercent": 0},
        ):
            result = execution_preflight(plan, self.policy(), self.NOW)

        self.assertEqual(result["orderType"], "limit")
        self.assertEqual(result["currentPrice"], 179.99)

    def test_us_preflight_rejects_cross_market_account_snapshot(self):
        account = self.account()
        account["market"] = "NYSE"
        with patch(
            "stock_service.automation_execution.automation_audit_status",
            return_value={"healthy": True},
        ), patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=[],
        ), patch(
            "stock_service.automation_execution.market_session_gate",
            return_value={"passed": True, "sessionDate": "2027-07-06", "message": "open"},
        ), patch(
            "stock_service.automation_execution.kis_quote",
            return_value=self.quote(),
        ), patch(
            "stock_service.automation_execution.overseas_orderbook",
            return_value=self.book(),
        ), patch(
            "stock_service.automation_execution.kis_account_summary",
            return_value=account,
        ):
            with self.assertRaisesRegex(StockServiceError, "different market"):
                execution_preflight(self.plan(), self.policy(), self.NOW)

    def test_us_preflight_rejects_cross_market_quote(self):
        quote = self.quote()
        quote["market"] = "NYSE"
        with patch(
            "stock_service.automation_execution.automation_audit_status",
            return_value={"healthy": True},
        ), patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=[],
        ), patch(
            "stock_service.automation_execution.market_session_gate",
            return_value={"passed": True, "sessionDate": "2027-07-06", "message": "open"},
        ), patch(
            "stock_service.automation_execution.kis_quote",
            return_value=quote,
        ):
            with self.assertRaisesRegex(StockServiceError, "different instrument market"):
                execution_preflight(self.plan(), self.policy(), self.NOW)

    def test_execute_and_reconcile_keep_us_market_identity(self):
        plan = self.plan()
        preflight = {
            "environment": "paper",
            "market": "NASDAQ",
            "currency": "USD",
            "exchangeRate": 1380,
            "orderType": "limit",
            "currentPrice": 180.01,
            "estimatedNotional": 180.01,
            "estimatedNotionalKrw": 248414,
            "protectiveExit": False,
            "account": self.account(),
            "checkedAt": self.NOW,
            "priceDriftPercent": 0,
            "bidAskSpreadBps": 1,
            "session": {"sessionDate": "2027-07-06"},
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory",
            return_value=directory,
        ), patch(
            "stock_service.automation_execution.state_directory",
            return_value=directory,
        ), patch(
            "stock_service.automation_execution.find_automation_plan",
            return_value=plan,
        ), patch(
            "stock_service.automation_execution.load_automation_policy",
            return_value=self.policy(),
        ), patch(
            "stock_service.automation_execution.execution_preflight",
            return_value=preflight,
        ), patch(
            "stock_service.automation_execution.kis_order",
            return_value={"status": "ok", "orderNumber": "us-1"},
        ) as order:
            execute_automation_plan(
                {
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                },
                self.NOW,
            )
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "us-1",
                    "market": "NASDAQ",
                    "symbol": "AAPL",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 0,
                    "remainingQuantity": 1,
                    "state": "pending",
                }],
            }
            with patch(
                "stock_service.automation_execution.kis_order_history",
                return_value=history,
            ) as order_history, patch(
                "stock_service.automation_execution.kis_cancel",
                return_value={"status": "ok", "orderNumber": "cancel-us-1"},
            ) as cancel:
                reconcile_automation_executions(self.NOW + 121)

        self.assertEqual(order.call_args.args[1]["market"], "NASDAQ")
        self.assertEqual(order.call_args.args[1]["orderType"], "limit")
        order_history.assert_called_once_with("paper", "", 200, 7, "NASDAQ")
        cancel.assert_called_once_with(
            "paper",
            {"orderNumber": "us-1", "market": "NASDAQ", "symbol": "AAPL"},
        )


if __name__ == "__main__":
    unittest.main()
