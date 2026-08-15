import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation_portfolio import portfolio_tail_risk


class StockAutomationPortfolioTests(unittest.TestCase):
    def points(self, volatility=0.004):
        price = 100
        result = []
        for index in range(121):
            price *= 1 + (volatility if index % 3 else -volatility)
            result.append({"t": index, "v": price, "volume": 1000000})
        return result

    def policy(self):
        return {
            "maxPortfolioVar95Percent": 2,
            "maxPortfolioCvar95Percent": 3,
            "maxStressLossPercent": 8,
            "maxSingleDayLossPercent": 5,
        }

    def test_cash_heavy_position_passes_tail_limits(self):
        result = portfolio_tail_risk(
            {"holdings": []}, "005930", self.points(), 100000, 10000000,
            "kis", "paper", self.policy(),
        )

        self.assertTrue(result["available"])
        self.assertTrue(result["passed"])
        self.assertEqual(result["sampleSessions"], 120)

    def test_concentrated_position_fails_stress_scenario(self):
        result = portfolio_tail_risk(
            {"holdings": [{"symbol": "005930", "evaluation": 6000000}]},
            "005930", self.points(), 0, 10000000, "kis", "paper", self.policy(),
        )

        self.assertTrue(result["available"])
        self.assertFalse(result["passed"])
        self.assertGreater(result["stressLossPercent"], 8)

    def test_missing_holding_history_fails_closed(self):
        with patch("stock_service.automation_portfolio.kis_history_points", return_value=[]):
            result = portfolio_tail_risk(
                {"holdings": [{"symbol": "000660", "evaluation": 100000}]},
                "005930", self.points(), 100000, 10000000,
                "kis", "paper", self.policy(),
            )

        self.assertFalse(result["available"])
        self.assertFalse(result["passed"])
        self.assertEqual(result["missingSymbols"], ["000660"])

    def test_us_holdings_load_history_with_their_market_identity(self):
        with patch(
            "stock_service.automation_portfolio.kis_history_points",
            return_value=self.points(),
        ) as history:
            result = portfolio_tail_risk(
                {
                    "holdings": [{
                        "market": "NYSE",
                        "symbol": "IBM",
                        "evaluation": 500,
                    }],
                },
                "AAPL",
                self.points(),
                500,
                10000,
                "kis",
                "paper",
                self.policy(),
                market="NASDAQ",
            )

        self.assertTrue(result["available"])
        self.assertEqual(result["symbols"], ["NASDAQ:AAPL", "NYSE:IBM"])
        history.assert_called_once_with("paper", "IBM", 120, "NYSE")


if __name__ == "__main__":
    unittest.main()
