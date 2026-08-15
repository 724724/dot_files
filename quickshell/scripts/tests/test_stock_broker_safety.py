import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.broker import (
    KisPostError,
    kis_overseas_quote,
    kis_post,
    kis_quote,
)
from stock_service.core import StockServiceError


class StockBrokerSafetyTests(unittest.TestCase):
    def test_krx_quote_keeps_broker_timestamp_separate_from_receipt_time(self):
        received_at = int(
            datetime(
                2027,
                1,
                12,
                10,
                1,
                tzinfo=ZoneInfo("Asia/Seoul"),
            ).timestamp()
        )
        source_at = int(
            datetime(
                2027,
                1,
                12,
                9,
                59,
                30,
                tzinfo=ZoneInfo("Asia/Seoul"),
            ).timestamp()
        )
        response = {
            "output": {
                "stck_prpr": "70000",
                "prdy_vrss": "100",
                "stck_bsop_date": "20270112",
                "stck_cntg_hour": "095930",
            },
        }
        with patch(
            "stock_service.broker.time.time",
            return_value=received_at,
        ), patch(
            "stock_service.broker.kis_get",
            return_value=response,
        ):
            result = kis_quote("005930", "KRX", "paper")

        self.assertEqual(result["receivedAt"], received_at)
        self.assertEqual(result["updatedAt"], received_at)
        self.assertEqual(result["sourceUpdatedAt"], source_at)

    def test_us_quote_keeps_exchange_timestamp_separate_from_receipt_time(self):
        received_at = int(
            datetime(
                2027,
                1,
                12,
                11,
                0,
                tzinfo=ZoneInfo("America/New_York"),
            ).timestamp()
        )
        source_at = int(
            datetime(
                2027,
                1,
                12,
                10,
                58,
                tzinfo=ZoneInfo("America/New_York"),
            ).timestamp()
        )
        response = {
            "output": {
                "last": "225.5",
                "base": "224.0",
                "dymd": "20270112",
                "dhms": "105800",
                "e_ordyn": "Y",
                "curr": "USD",
            },
        }
        with patch(
            "stock_service.broker.time.time",
            return_value=received_at,
        ), patch(
            "stock_service.broker.kis_get",
            return_value=response,
        ):
            result = kis_overseas_quote(
                "AAPL",
                "NASDAQ",
                "paper",
            )

        self.assertEqual(result["receivedAt"], received_at)
        self.assertEqual(result["updatedAt"], received_at)
        self.assertEqual(result["sourceUpdatedAt"], source_at)

    def test_order_error_before_http_is_not_ambiguous(self):
        with patch(
            "stock_service.broker.kis_token",
            side_effect=StockServiceError("credentials missing"),
        ), self.assertRaises(KisPostError) as raised:
            kis_post("paper", "/order", "TR", {})

        self.assertFalse(raised.exception.request_sent)
        self.assertFalse(raised.exception.outcome_ambiguous)
        self.assertEqual(raised.exception.failure_class, "operator")

    def test_order_transport_error_after_http_start_is_ambiguous(self):
        with patch(
            "stock_service.broker.kis_token",
            return_value=("https://example.invalid", "key", "secret", "token"),
        ), patch(
            "stock_service.broker.kis_http_json",
            side_effect=TimeoutError("timeout"),
        ), self.assertRaises(KisPostError) as raised:
            kis_post("paper", "/order", "TR", {})

        self.assertTrue(raised.exception.request_sent)
        self.assertTrue(raised.exception.outcome_ambiguous)
        self.assertEqual(raised.exception.failure_class, "hard")

    def test_explicit_broker_rejection_is_not_ambiguous(self):
        with patch(
            "stock_service.broker.kis_token",
            return_value=("https://example.invalid", "key", "secret", "token"),
        ), patch(
            "stock_service.broker.kis_http_json",
            return_value={
                "rt_cd": "1",
                "msg_cd": "REJECTED",
                "msg1": "order rejected",
            },
        ), self.assertRaises(KisPostError) as raised:
            kis_post("paper", "/order", "TR", {})

        self.assertTrue(raised.exception.request_sent)
        self.assertFalse(raised.exception.outcome_ambiguous)
        self.assertEqual(raised.exception.broker_code, "REJECTED")


if __name__ == "__main__":
    unittest.main()
