import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.broker import intraday_points, kis_http_json, kis_quote, kis_snapshot, kis_token, kis_vi_status
from stock_service.quant import demo_snapshot, kis_history_points


class StockMarketDataTests(unittest.TestCase):
    def test_demo_thirty_minute_range_uses_minute_points(self):
        result = demo_snapshot("005930", "KRX", "30M")

        self.assertEqual(len(result["points"]), 30)
        self.assertEqual(result["points"][1]["t"] - result["points"][0]["t"], 60)

    def test_kis_daily_history_preserves_turnover_volume(self):
        response = {
            "output2": [{
                "stck_bsop_date": "20260102",
                "stck_clpr": "73000",
                "acml_vol": "1234567",
            }],
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.quant.state_directory", return_value=directory,
        ), patch("stock_service.quant.kis_get", return_value=response) as request:
            result = kis_history_points("paper", "005930", 1)

        self.assertEqual(result[0]["v"], 73000)
        self.assertEqual(result[0]["volume"], 1234567)
        self.assertEqual(request.call_args.args[3]["FID_ORG_ADJ_PRC"], "1")

    def test_kis_quote_preserves_best_bid_and_ask(self):
        with patch("stock_service.broker.kis_get", side_effect=[
            {"output": {
                "stck_prpr": "70000",
                "iscd_stat_cls_code": "00",
                "temp_stop_yn": "N",
                "stck_mxpr": "91000",
                "stck_llam": "49000",
                "invt_caful_yn": "N",
                "mrkt_warn_cls_code": "00",
                "short_over_yn": "N",
                "sltr_yn": "N",
                "mang_issu_cls_code": "00",
            }},
            {"output1": {
                "askp1": "70010",
                "bidp1": "69990",
                "aspr_acpt_hour": datetime.now(ZoneInfo("Asia/Seoul")).strftime("%H%M%S"),
            }},
        ]):
            result = kis_quote("005930", "KRX", "paper", include_orderbook=True)

        self.assertEqual(result["ask"], 70010)
        self.assertEqual(result["bid"], 69990)
        self.assertGreater(result["orderbookUpdatedAt"], 0)
        self.assertTrue(result["marketSafety"]["available"])
        self.assertTrue(result["marketSafety"]["tradable"])

    def quote_output(self, **values):
        result = {
            "stck_prpr": "70000",
            "iscd_stat_cls_code": "00",
            "temp_stop_yn": "N",
            "stck_mxpr": "91000",
            "stck_llam": "49000",
            "invt_caful_yn": "N",
            "mrkt_warn_cls_code": "00",
            "short_over_yn": "N",
            "sltr_yn": "N",
            "mang_issu_cls_code": "00",
        }
        result.update(values)
        return result

    def test_credit_eligible_status_code_is_a_normal_tradable_state(self):
        with patch("stock_service.broker.kis_get", return_value={
            "output": self.quote_output(iscd_stat_cls_code="55"),
        }):
            result = kis_quote("005930", "KRX", "paper")

        self.assertTrue(result["marketSafety"]["tradable"])
        self.assertFalse(result["marketSafety"]["restricted"])

    def test_suspended_status_code_blocks_trading(self):
        with patch("stock_service.broker.kis_get", return_value={
            "output": self.quote_output(iscd_stat_cls_code="58"),
        }):
            result = kis_quote("005930", "KRX", "paper")

        self.assertFalse(result["marketSafety"]["tradable"])

    def test_warning_status_code_stays_tradable_but_restricted(self):
        with patch("stock_service.broker.kis_get", return_value={
            "output": self.quote_output(iscd_stat_cls_code="53"),
        }):
            result = kis_quote("005930", "KRX", "paper")

        self.assertTrue(result["marketSafety"]["tradable"])
        self.assertTrue(result["marketSafety"]["restricted"])
        self.assertIn("market_warning", result["marketSafety"]["restrictionReasons"])

    def test_kis_overseas_quote_uses_the_official_exchange_code(self):
        with patch("stock_service.broker.kis_get", return_value={"output": {
            "last": "221.45",
            "base": "219.20",
            "high": "223.10",
            "low": "217.50",
            "tvol": "123456",
            "curr": "USD",
            "t_rate": "1381.20",
            "t_xprc": "305841",
            "e_ordyn": "Y",
        }}) as request:
            result = kis_quote("AAPL", "NASDAQ", "paper")

        self.assertEqual(result["currency"], "USD")
        self.assertEqual(result["price"], 221.45)
        self.assertEqual(result["exchangeRate"], 1381.2)
        self.assertTrue(result["marketSafety"]["tradable"])
        self.assertEqual(request.call_args.args[1], "/uapi/overseas-price/v1/quotations/price-detail")
        self.assertEqual(request.call_args.args[3]["EXCD"], "NAS")

    def test_vi_status_detects_an_unreleased_interruption(self):
        response = {"output": [{
            "mksc_shrn_iscd": "005930",
            "bsop_date": "20260722",
            "cntg_vi_hour": "101500",
            "vi_cncl_hour": "",
            "vi_kind_code": "2",
        }]}
        now = datetime(2026, 7, 22, 10, 16, tzinfo=ZoneInfo("Asia/Seoul"))
        with patch("stock_service.broker.kis_get", return_value=response):
            result = kis_vi_status("005930", "paper", now)

        self.assertTrue(result["available"])
        self.assertTrue(result["active"])
        self.assertEqual(result["kindCode"], "2")

    @patch("stock_service.broker.intraday_points")
    @patch("stock_service.broker.intraday_response")
    @patch("stock_service.broker.kis_quote")
    def test_kis_thirty_minute_range_is_limited_to_latest_thirty_points(self, quote, response, intraday):
        response.return_value = {"output1": {}, "output2": []}
        quote.return_value = {
            "status": "ok",
            "price": 73000,
            "previousClose": 72500,
            "high": 0,
            "low": 0,
        }
        intraday.return_value = [{"t": index, "v": 72000 + index} for index in range(40)]

        result = kis_snapshot("005930", "KRX", "30M", "paper")

        self.assertEqual(len(result["points"]), 30)
        self.assertEqual(result["points"][0]["t"], 10)
        response.assert_called_once_with("paper", "005930")
        intraday.assert_called_once_with(response.return_value)
        quote.assert_called_once_with("005930", "KRX", "paper", include_vi=True)

    @patch("stock_service.broker.kis_wait_for_slot")
    @patch("stock_service.broker.time.sleep")
    @patch("stock_service.broker.http_json")
    def test_rate_limit_error_is_retried(self, request, sleep, wait):
        request.side_effect = [
            {"rt_cd": "1", "msg1": "초당 거래건수를 초과하였습니다."},
            {"rt_cd": "0", "output": {}},
        ]

        result = kis_http_json("paper", "https://example.test")

        self.assertEqual(result["rt_cd"], "0")
        self.assertEqual(request.call_count, 2)
        self.assertEqual(wait.call_count, 2)
        sleep.assert_called_once_with(0.75)

    def test_token_refresh_is_reused_after_serialized_refresh(self):
        secrets = {
            "kis_paper_app_key": "key",
            "kis_paper_app_secret": "secret",
        }
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.broker.state_directory", return_value=directory,
        ), patch(
            "stock_service.broker.secret_lookup", side_effect=lambda key: secrets.get(key, ""),
        ), patch(
            "stock_service.broker.secret_store", side_effect=lambda key, value: secrets.__setitem__(key, value),
        ), patch(
            "stock_service.broker.kis_http_json",
            return_value={"access_token": "shared-token", "expires_in": 86400},
        ) as request:
            first = kis_token("paper")
            second = kis_token("paper")

        self.assertEqual(first[3], "shared-token")
        self.assertEqual(second[3], "shared-token")
        request.assert_called_once()

    def test_intraday_points_use_the_broker_business_date(self):
        points = intraday_points({
            "output1": {},
            "output2": [{"stck_bsop_date": "20260721", "stck_cntg_hour": "153000", "stck_prpr": "73000"}],
        })

        self.assertEqual(points[0]["t"], 1784615400)


if __name__ == "__main__":
    unittest.main()
