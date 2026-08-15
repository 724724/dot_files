import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.quant import screen_watchlist, technical_screen_metrics


class StockScreenerTests(unittest.TestCase):
    @staticmethod
    def points(values):
        return [{"t": index + 1, "v": value} for index, value in enumerate(values)]

    def test_rising_history_ranks_bullish(self):
        metrics = technical_screen_metrics(self.points([100 + index for index in range(120)]))

        self.assertEqual(metrics["stance"], "bullish")
        self.assertGreater(metrics["score"], 20)
        self.assertGreater(metrics["momentum20Pct"], 0)
        self.assertEqual(metrics["sampleCount"], 120)

    def test_falling_history_ranks_bearish(self):
        metrics = technical_screen_metrics(self.points([220 - index for index in range(120)]))

        self.assertEqual(metrics["stance"], "bearish")
        self.assertLess(metrics["score"], -20)
        self.assertLess(metrics["drawdown60Pct"], 0)

    @patch("stock_service.quant.demo_history_points")
    @patch("stock_service.quant.demo_snapshot")
    def test_watchlist_is_sorted_and_deduplicated(self, snapshot, history):
        snapshot.side_effect = lambda symbol, market, period: {
            "name": symbol,
            "currency": "USD",
            "price": 100,
            "changePct": 0,
        }
        history.side_effect = lambda symbol, market, count: self.points(
            [100 + index for index in range(120)]
            if symbol == "UP"
            else [220 - index for index in range(120)]
        )

        result = screen_watchlist([
            {"symbol": "DOWN", "market": "NASDAQ"},
            {"symbol": "UP", "market": "NASDAQ"},
            {"symbol": "UP", "market": "NASDAQ"},
        ])

        self.assertEqual([item["symbol"] for item in result["items"]], ["UP", "DOWN"])
        self.assertEqual([item["rank"] for item in result["items"]], [1, 2])
        self.assertEqual(result["counts"]["screened"], 2)
        self.assertEqual(result["counts"]["bullish"], 1)
        self.assertEqual(result["counts"]["bearish"], 1)

    @patch("stock_service.quant.demo_history_points")
    @patch("stock_service.quant.demo_snapshot")
    def test_watchlist_has_no_eight_symbol_limit(self, snapshot, history):
        snapshot.side_effect = lambda symbol, market, period: {
            "name": symbol,
            "currency": "USD",
            "price": 100,
            "changePct": 0,
        }
        history.return_value = self.points([100 + index for index in range(120)])
        symbols = [
            {"symbol": f"TEST{index}", "market": "NASDAQ"}
            for index in range(10)
        ]

        result = screen_watchlist(symbols)

        self.assertEqual(result["counts"]["screened"], 10)


if __name__ == "__main__":
    unittest.main()
