import tempfile
import time
import unittest
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import patch


import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.core import StockServiceError, trade_activity, trade_audit
from stock_service.trading import (
    broker_order_match,
    kis_cancel,
    kis_cancelable_orders,
    kis_account_summary,
    kis_order,
    kis_order_history,
    kis_reconcile_activity,
    parse_order_request,
    reconciled_trade_activity,
)


class StockTradingReconciliationTests(unittest.TestCase):
    def event(self, **values):
        result = {
            "requestId": "request-1",
            "action": "order",
            "environment": "paper",
            "status": "accepted",
            "side": "buy",
            "symbol": "005930",
            "quantity": 3,
            "orderType": "market",
            "orderNumber": "12345",
            "timestamp": int(time.time()) - 180,
        }
        result.update(values)
        return result

    def broker_order(self, **values):
        result = {
            "orderNumber": "12345",
            "symbol": "005930",
            "side": "buy",
            "quantity": 3,
            "filledQuantity": 3,
            "remainingQuantity": 0,
            "cancelQuantity": 0,
            "averagePrice": 72100,
            "state": "filled",
            "timestamp": int(time.time()) - 175,
        }
        result.update(values)
        return result

    def history(self, orders):
        return {
            "status": "ok",
            "environment": "paper",
            "orders": orders,
            "pendingCount": 0,
            "updatedAt": int(time.time()),
        }

    def test_exact_order_number_reconciles_to_filled(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ), patch(
            "stock_service.trading.kis_order_history",
            return_value=self.history([self.broker_order()]),
        ):
            trade_audit(self.event())
            result = kis_reconcile_activity("paper")
            activity = trade_activity("paper", 10)["activity"][0]

        self.assertEqual(result["matched"], 1)
        self.assertEqual(result["updated"], 1)
        self.assertEqual(activity["reconciliation"], "matched")
        self.assertEqual(activity["brokerState"], "filled")
        self.assertEqual(activity["filledQuantity"], 3)

    def test_activity_preserves_automation_plan_identity(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ):
            trade_audit(self.event(environment="prod", automationPlanId="plan-1"))
            activity = trade_activity("prod", 10)["activity"][0]

        self.assertEqual(activity["automationPlanId"], "plan-1")

    def test_reconciliation_does_not_append_unchanged_state(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ), patch(
            "stock_service.trading.kis_order_history",
            return_value=self.history([self.broker_order()]),
        ):
            trade_audit(self.event())
            first = kis_reconcile_activity("paper")
            line_count = len((Path(directory) / "trades.jsonl").read_text(encoding="utf-8").splitlines())
            second = kis_reconcile_activity("paper")
            second_line_count = len((Path(directory) / "trades.jsonl").read_text(encoding="utf-8").splitlines())

        self.assertEqual(first["updated"], 1)
        self.assertEqual(second["updated"], 0)
        self.assertEqual(line_count, second_line_count)

    def test_unique_request_signature_recovers_missing_order_number(self):
        event = self.event(orderNumber="")
        order = self.broker_order()
        match = broker_order_match(event, [order])

        self.assertIsNotNone(match)
        self.assertEqual(match[2], "request_signature")

    def test_ambiguous_request_signature_is_not_guessed(self):
        event = self.event(orderNumber="")
        order = self.broker_order()

        self.assertIsNone(broker_order_match(event, [order, dict(order, orderNumber="67890")]))

    def test_recent_unmatched_order_stays_pending_during_broker_grace_period(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ), patch(
            "stock_service.trading.kis_order_history", return_value=self.history([]),
        ):
            trade_audit(self.event(timestamp=int(time.time()) - 10))
            result = kis_reconcile_activity("paper")
            activity = trade_activity("paper", 10)["activity"][0]

        self.assertEqual(result["pending"], 1)
        self.assertEqual(activity["reconciliation"], "pending")

    def test_old_unmatched_submission_counts_as_one_verification(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ), patch(
            "stock_service.trading.kis_order_history", return_value=self.history([]),
        ):
            trade_audit(self.event(status="submitting", orderNumber="", timestamp=int(time.time()) - 360))
            kis_reconcile_activity("paper")
            result = trade_activity("paper", 10)

        self.assertEqual(result["counts"]["uncertain"], 1)
        self.assertEqual(result["counts"]["unmatched"], 1)
        self.assertEqual(result["counts"]["verify"], 1)

    def test_activity_remains_available_when_kis_reconciliation_fails(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.core.state_directory", return_value=directory,
        ), patch(
            "stock_service.trading.kis_reconcile_activity",
            side_effect=StockServiceError("KIS unavailable"),
        ):
            trade_audit(self.event(status="failed"))
            result = reconciled_trade_activity("paper", "all", 10)

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["reconciliation"]["status"], "error")
        self.assertEqual(len(result["activity"]), 1)

    def daily_ccld_row(self, **values):
        result = {
            "odno": "1001",
            "pdno": "005930",
            "prdt_name": "Samsung Electronics",
            "ord_qty": "2",
            "tot_ccld_qty": "0",
            "rmn_qty": "2",
            "cncl_cfrm_qty": "0",
            "rjct_qty": "0",
            "cncl_yn": "N",
            "sll_buy_dvsn_cd": "02",
            "ord_dvsn_cd": "00",
            "ord_dvsn_name": "지정가",
            "ord_unpr": "70000",
            "avg_prvs": "0",
            "ord_dt": "20260722",
            "ord_tmd": "100000",
            "ord_gno_brno": "06010",
        }
        result.update(values)
        return result

    def test_paper_cancelable_orders_use_daily_inquiry_not_production_service(self):
        rows = [
            self.daily_ccld_row(),
            self.daily_ccld_row(odno="1002", tot_ccld_qty="2", rmn_qty="0"),
            self.daily_ccld_row(odno="1003", cncl_yn="Y"),
            self.daily_ccld_row(odno="1004", rjct_qty="2"),
        ]
        with patch(
            "stock_service.trading.kis_account_parts", return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.kis_get", return_value={"output1": rows},
        ) as request:
            cancelable = kis_cancelable_orders("paper")

        self.assertEqual(request.call_args.args[:3], (
            "paper", "/uapi/domestic-stock/v1/trading/inquire-daily-ccld", "VTTC0081R",
        ))
        self.assertEqual([row["odno"] for row in cancelable], ["1001"])
        self.assertEqual(cancelable[0]["psbl_qty"], "2")
        self.assertEqual(cancelable[0]["krx_fwdg_ord_orgno"], "06010")

    def test_paper_order_history_marks_open_orders_without_extra_inquiry(self):
        rows = [
            self.daily_ccld_row(),
            self.daily_ccld_row(odno="1002", tot_ccld_qty="2", rmn_qty="0"),
        ]
        with patch(
            "stock_service.trading.kis_account_parts", return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.kis_get", return_value={"output1": rows},
        ) as request:
            history = kis_order_history("paper", "", 10, 7, "KRX")

        self.assertEqual(request.call_count, 1)
        orders = {order["orderNumber"]: order for order in history["orders"]}
        self.assertTrue(orders["1001"]["canCancel"])
        self.assertEqual(orders["1001"]["cancelQuantity"], 2)
        self.assertEqual(orders["1001"]["state"], "pending")
        self.assertFalse(orders["1002"]["canCancel"])
        self.assertEqual(orders["1002"]["state"], "filled")
        self.assertEqual(history["pendingCount"], 1)

    def test_paper_cancel_uses_order_derived_from_daily_inquiry(self):
        with patch(
            "stock_service.trading.kis_account_parts", return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.kis_get", return_value={"output1": [self.daily_ccld_row()]},
        ), patch(
            "stock_service.trading.trade_audit",
        ), patch(
            "stock_service.trading.kis_post",
            return_value={"output": {"ODNO": "2001"}, "msg1": "canceled"},
        ) as request:
            result = kis_cancel("paper", {"orderNumber": "1001"})

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["canceledQuantity"], 2)
        self.assertEqual(request.call_args.args[:3], (
            "paper", "/uapi/domestic-stock/v1/trading/order-rvsecncl", "VTTC0013U",
        ))
        self.assertEqual(request.call_args.args[3]["KRX_FWDG_ORD_ORGNO"], "06010")
        self.assertEqual(request.call_args.args[3]["ORGN_ODNO"], "1001")

    def test_overseas_market_order_is_rejected_before_broker_submission(self):
        with self.assertRaisesRegex(StockServiceError, "require a limit price"):
            parse_order_request("paper", {
                "symbol": "AAPL",
                "market": "NASDAQ",
                "side": "buy",
                "orderType": "market",
                "quantity": 1,
                "price": 220,
            })

    def test_overseas_paper_order_uses_official_kis_transaction(self):
        account = {
            "status": "ok",
            "currency": "USD",
            "exchangeRate": 1380,
            "buyingQuantity": 4,
            "sellableQuantity": 0,
        }
        with patch("stock_service.trading.kis_account_summary", return_value=account), patch(
            "stock_service.trading.kis_account_parts", return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.trade_audit",
        ), patch(
            "stock_service.trading.kis_post",
            return_value={"output": {"ODNO": "9001", "ORD_TMD": "101500"}, "msg1": "accepted"},
        ) as request:
            result = kis_order("paper", {
                "symbol": "AAPL",
                "market": "NASDAQ",
                "side": "buy",
                "orderType": "limit",
                "quantity": 2,
                "price": 220.25,
            })

        self.assertEqual(result["market"], "NASDAQ")
        self.assertEqual(result["currency"], "USD")
        self.assertEqual(request.call_args.args[:3], (
            "paper", "/uapi/overseas-stock/v1/trading/order", "VTTT1002U",
        ))
        self.assertEqual(request.call_args.args[3]["OVRS_EXCG_CD"], "NASD")
        self.assertEqual(request.call_args.args[3]["OVRS_ORD_UNPR"], "220.25")
        self.assertEqual(result["risk"]["estimatedNotionalKrw"], round(440.5 * 1380))

    def test_live_nasdaq_balance_uses_specific_exchange_and_filters_mixed_rows(self):
        balance = {
            "output1": [
                {
                    "ovrs_excg_cd": "NASD",
                    "ovrs_pdno": "AAPL",
                    "ovrs_cblc_qty": "2",
                    "ord_psbl_qty": "2",
                    "ovrs_stck_evlu_amt": "440",
                },
                {
                    "ovrs_excg_cd": "NYSE",
                    "ovrs_pdno": "IBM",
                    "ovrs_cblc_qty": "1",
                    "ord_psbl_qty": "1",
                    "ovrs_stck_evlu_amt": "200",
                },
            ],
            "output2": {"ovrs_stck_evlu_amt": "440"},
        }
        possible = {
            "output": {
                "ord_psbl_frcr_amt": "1000",
                "max_ord_psbl_qty": "4",
                "exrt": "1380",
            },
        }
        with patch(
            "stock_service.trading.kis_account_parts",
            return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.kis_get",
            side_effect=(balance, possible),
        ) as request:
            result = kis_account_summary("prod", "AAPL", 220, "limit", "NASDAQ")

        self.assertEqual(request.call_args_list[0].args[3]["OVRS_EXCG_CD"], "NAS")
        self.assertEqual(request.call_args_list[1].args[3]["OVRS_EXCG_CD"], "NASD")
        self.assertEqual([(item["market"], item["symbol"]) for item in result["holdings"]], [
            ("NASDAQ", "AAPL"),
        ])
        self.assertEqual(result["exchangeRate"], 1380)

    def test_overseas_paper_order_fails_closed_without_exchange_rate(self):
        account = {
            "status": "ok",
            "currency": "USD",
            "buyingQuantity": 4,
            "sellableQuantity": 0,
        }
        with patch("stock_service.trading.kis_account_summary", return_value=account):
            with self.assertRaisesRegex(StockServiceError, "exchange rate"):
                kis_order("paper", {
                    "symbol": "AAPL",
                    "market": "NASDAQ",
                    "side": "buy",
                    "orderType": "limit",
                    "quantity": 1,
                    "price": 220,
                })

    def test_live_nyse_sell_uses_official_us_route_and_krw_risk(self):
        account = {
            "status": "ok",
            "market": "NYSE",
            "currency": "USD",
            "exchangeRate": 1380,
            "buyingQuantity": 0,
            "sellableQuantity": 2,
        }
        risk = {
            "estimatedNotional": 400,
            "estimatedNotionalKrw": 552000,
        }
        with patch(
            "stock_service.trading.kis_account_summary", return_value=account,
        ), patch(
            "stock_service.trading.production_order_lock", return_value=nullcontext(),
        ), patch(
            "stock_service.trading.enforce_production_risk", return_value=risk,
        ), patch(
            "stock_service.trading.kis_account_parts", return_value=("12345678", "01"),
        ), patch(
            "stock_service.trading.trade_audit",
        ), patch(
            "stock_service.trading.kis_post",
            return_value={"output": {"ODNO": "live-us-1"}},
        ) as request:
            result = kis_order("prod", {
                "confirmation": "LIVE",
                "symbol": "IBM",
                "market": "NYSE",
                "side": "sell",
                "orderType": "limit",
                "quantity": 2,
                "price": 200,
            })

        self.assertEqual(result["market"], "NYSE")
        self.assertEqual(result["risk"]["estimatedNotionalKrw"], 552000)
        self.assertEqual(request.call_args.args[:3], (
            "prod", "/uapi/overseas-stock/v1/trading/order", "TTTT1006U",
        ))
        self.assertEqual(request.call_args.args[3]["OVRS_EXCG_CD"], "NYSE")
        self.assertEqual(request.call_args.args[3]["SLL_TYPE"], "00")


if __name__ == "__main__":
    unittest.main()
