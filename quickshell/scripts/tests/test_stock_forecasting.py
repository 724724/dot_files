import copy
import json
import os
import sys
import tempfile
import unittest
from contextlib import nullcontext
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.forecasting import (
    evaluate_all_forecasts,
    evaluate_forecasts,
    forecast_target_close,
    record_forecast,
    session_close_timestamp,
)
from stock_service.quant import kis_history_points


KST = ZoneInfo("Asia/Seoul")


class StockForecastingTests(unittest.TestCase):
    def timestamp(self, year, month, day, hour=0, minute=0):
        return int(datetime(year, month, day, hour, minute, tzinfo=KST).timestamp())

    def point(self, year, month, day, price):
        return {"t": self.timestamp(year, month, day), "v": price}

    def open_forecast(self, entry_at):
        return {
            "id": "forecast-1",
            "symbol": "005930",
            "market": "KRX",
            "status": "open",
            "stance": "bullish",
            "entryPrice": 100,
            "generatedAt": entry_at,
            "targetAt": self.timestamp(2026, 1, 12, 10),
            "confidence": 70,
            "upProbability": 60,
            "flatProbability": 25,
            "downProbability": 15,
        }

    def completed_points(self):
        return [
            self.point(2026, 1, 5, 101),
            self.point(2026, 1, 6, 102),
            self.point(2026, 1, 7, 103),
            self.point(2026, 1, 9, 104),
            self.point(2026, 1, 12, 105),
            self.point(2026, 1, 13, 106),
        ]

    def evaluate(self, item, points, now, current_price=150):
        items = [item]
        saved = []
        quote = {
            "symbol": "005930",
            "market": "KRX",
            "mode": "kis",
            "environment": "paper",
            "price": current_price,
            "updatedAt": now,
        }
        with (
            patch("stock_service.forecasting.forecast_journal_lock", return_value=nullcontext()),
            patch("stock_service.forecasting.load_forecasts", return_value=items),
            patch("stock_service.forecasting.save_forecasts", side_effect=lambda value: saved.append(copy.deepcopy(value))),
            patch(
                "stock_service.forecasting.forecast_history_points",
                return_value=(points, "kis_adjusted_completed_daily_close"),
            ) as history,
            patch("stock_service.forecasting.time.time", return_value=now),
        ):
            evaluate_forecasts(quote)
        return items[0], saved, history

    def test_target_uses_fifth_completed_session_across_calendar_gap(self):
        entry_at = self.timestamp(2026, 1, 5, 10)
        target, completed = forecast_target_close(
            self.open_forecast(entry_at),
            self.completed_points(),
            self.timestamp(2026, 1, 12, 16),
        )

        self.assertEqual(completed, 5)
        self.assertEqual(target["t"], self.timestamp(2026, 1, 12, 15, 30))
        self.assertEqual(target["v"], 105)

    def test_session_is_not_complete_before_market_close(self):
        entry_at = self.timestamp(2026, 1, 5, 10)
        target, completed = forecast_target_close(
            self.open_forecast(entry_at),
            self.completed_points(),
            self.timestamp(2026, 1, 12, 14),
        )

        self.assertIsNone(target)
        self.assertEqual(completed, 4)

    def test_forecast_after_close_starts_with_next_session(self):
        entry_at = self.timestamp(2026, 1, 5, 16)
        target, completed = forecast_target_close(
            self.open_forecast(entry_at),
            self.completed_points(),
            self.timestamp(2026, 1, 13, 16),
        )

        self.assertEqual(completed, 5)
        self.assertEqual(target["t"], self.timestamp(2026, 1, 13, 15, 30))

    def test_late_evaluation_uses_target_close_not_current_quote(self):
        entry_at = self.timestamp(2026, 1, 5, 10)
        item, saved, _ = self.evaluate(
            self.open_forecast(entry_at),
            self.completed_points(),
            self.timestamp(2026, 1, 20, 16),
            current_price=150,
        )

        self.assertEqual(item["status"], "resolved")
        self.assertEqual(item["targetPrice"], 105)
        self.assertEqual(item["lastPrice"], 105)
        self.assertEqual(item["latestPrice"], 150)
        self.assertEqual(item["returnPct"], 5)
        self.assertEqual(item["targetSessionAt"], self.timestamp(2026, 1, 12, 15, 30))
        self.assertEqual(item["evaluationSource"], "kis_adjusted_completed_daily_close")
        self.assertTrue(item["correct"])
        self.assertEqual(item["dataMode"], "kis")
        self.assertEqual(item["environment"], "paper")
        self.assertEqual(len(saved), 1)

    def test_insufficient_sessions_remain_open_even_after_estimate(self):
        entry_at = self.timestamp(2026, 1, 5, 10)
        item, saved, _ = self.evaluate(
            self.open_forecast(entry_at),
            self.completed_points()[:4],
            self.timestamp(2026, 1, 20, 16),
            current_price=107,
        )

        self.assertEqual(item["status"], "open")
        self.assertEqual(item["evaluationStatus"], "awaiting_sessions")
        self.assertEqual(item["completedHorizonSessions"], 4)
        self.assertEqual(item["lastPrice"], 107)
        self.assertNotIn("returnPct", item)
        self.assertEqual(len(saved), 1)

    def test_resolved_forecast_is_idempotent(self):
        item = self.open_forecast(self.timestamp(2026, 1, 5, 10))
        item.update({"status": "resolved", "targetPrice": 105, "returnPct": 5})
        _, saved, history = self.evaluate(
            item,
            self.completed_points(),
            self.timestamp(2026, 1, 20, 16),
        )

        history.assert_not_called()
        self.assertEqual(saved, [])

    def test_record_forecast_persists_observation_and_source_context(self):
        generated_at = self.timestamp(2026, 1, 5, 10, 5)
        observed_at = self.timestamp(2026, 1, 5, 10)
        saved = []
        result = {
            "generatedAt": generated_at,
            "provider": "both",
            "profile": "balanced",
            "models": ["model-a", "model-b"],
            "stance": "neutral",
            "confidence": 65,
            "upProbability": 30,
            "flatProbability": 40,
            "downProbability": 30,
        }
        snapshot = {
            "symbol": "005930",
            "market": "KRX",
            "price": 100,
            "updatedAt": observed_at,
            "mode": "kis",
            "environment": "prod",
        }
        with (
            patch("stock_service.forecasting.forecast_journal_lock", return_value=nullcontext()),
            patch("stock_service.forecasting.load_forecasts", return_value=[]),
            patch("stock_service.forecasting.save_forecasts", side_effect=lambda value: saved.append(copy.deepcopy(value))),
        ):
            record_forecast(result, snapshot)

        item = saved[0][0]
        self.assertEqual(item["entryObservedAt"], observed_at)
        self.assertEqual(item["dataMode"], "kis")
        self.assertEqual(item["environment"], "prod")
        self.assertEqual(item["horizonSessions"], 5)
        self.assertEqual(item["evaluationStatus"], "awaiting_sessions")
        self.assertGreater(item["estimatedTargetAt"], observed_at)

    def test_background_evaluation_resolves_without_a_current_quote(self):
        entry_at = self.timestamp(2026, 1, 5, 10)
        item = self.open_forecast(entry_at)
        item.update({"dataMode": "kis", "environment": "paper"})
        items = [item]
        saved = []
        now = self.timestamp(2026, 1, 20, 16)
        with (
            patch("stock_service.forecasting.forecast_journal_lock", return_value=nullcontext()),
            patch("stock_service.forecasting.load_forecasts", return_value=items),
            patch("stock_service.forecasting.save_forecasts", side_effect=lambda value: saved.append(copy.deepcopy(value))),
            patch(
                "stock_service.forecasting.forecast_history_points",
                return_value=(self.completed_points(), "kis_adjusted_completed_daily_close"),
            ),
            patch("stock_service.forecasting.time.time", return_value=now),
        ):
            result = evaluate_all_forecasts()

        self.assertEqual(result["checked"], 1)
        self.assertEqual(result["resolved"], 1)
        self.assertEqual(result["awaiting"], 0)
        self.assertEqual(item["targetPrice"], 105)
        self.assertEqual(len(saved), 1)

    def test_session_close_uses_market_timezone(self):
        timestamp = self.timestamp(2026, 1, 5)
        self.assertEqual(session_close_timestamp(timestamp, "KRX"), self.timestamp(2026, 1, 5, 15, 30))

    def test_preclose_history_cache_is_refreshed_after_close(self):
        now = datetime(2026, 1, 5, 15, 45, tzinfo=KST)

        class FixedDateTime(datetime):
            @classmethod
            def now(cls, timezone=None):
                return now.astimezone(timezone) if timezone else now.replace(tzinfo=None)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history-paper-005930.json"
            points = [self.point(2025, 5, 26, 100 + index) for index in range(160)]
            points[-1] = self.point(2026, 1, 2, 260)
            cached_at = self.timestamp(2026, 1, 5, 15, 35)
            path.write_text(json.dumps({"updatedAt": cached_at, "points": points}), encoding="utf-8")
            os.utime(path, (cached_at, cached_at))
            with (
                patch("stock_service.quant.state_directory", return_value=directory),
                patch("stock_service.quant.datetime", FixedDateTime),
                patch("stock_service.quant.time.time", return_value=int(now.timestamp())),
                patch("stock_service.quant.kis_get", return_value={"output2": []}) as request,
            ):
                result = kis_history_points("paper", "005930", 160)

        request.assert_called_once()
        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()
