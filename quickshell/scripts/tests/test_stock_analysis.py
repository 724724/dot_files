import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.ai_models import (
    StockServiceError,
    analysis_history_context,
    analysis_prompt,
    chart_features,
    consensus_result,
    news_evidence_context,
    normalize_news_items,
    resolve_profile_models,
    walk_forward_evidence,
)
from stock_service.forecasting import (
    ai_provider_failure,
    analyze,
    apply_historical_calibration,
    historical_model_weighting,
)


class StockAnalysisTests(unittest.TestCase):
    def model_result(self, stance, confidence, probabilities):
        return {
            "stance": stance,
            "confidence": confidence,
            "upProbability": probabilities[0],
            "flatProbability": probabilities[1],
            "downProbability": probabilities[2],
            "chartStance": stance,
            "chartConfidence": confidence,
            "newsStance": stance,
            "newsConfidence": confidence,
            "summary": stance,
            "chartSignal": stance,
            "newsSignal": stance,
            "risks": [],
            "catalysts": [],
        }

    def test_demo_analysis_uses_daily_history(self):
        snapshot = {
            "mode": "demo",
            "symbol": "005930",
            "market": "KRX",
            "price": 73500,
            "points": [{"t": 1, "v": 72000}, {"t": 2, "v": 73500}],
        }
        points, context = analysis_history_context(snapshot)

        self.assertEqual(context["source"], "demo_synthetic_daily")
        self.assertFalse(context["fallback"])
        self.assertEqual(context["timeframe"], "1D")
        self.assertEqual(len(points), 260)
        self.assertAlmostEqual(points[-1]["v"], snapshot["price"], places=2)

        features = chart_features(dict(snapshot, points=points))
        evidence = walk_forward_evidence(dict(snapshot, points=points))

        self.assertEqual(features["sampleCount"], 260)
        self.assertIn(features["trendRegime"], ("bullish", "mixed", "bearish"))
        self.assertIn("return60dPct", features)
        self.assertEqual(evidence["status"], "usable")
        self.assertGreater(evidence["sampleCount"], 200)

    def test_kis_history_failure_uses_visible_range(self):
        snapshot = {
            "mode": "kis",
            "environment": "paper",
            "symbol": "005930",
            "market": "KRX",
            "chartRange": "1M",
            "points": [
                {"t": 3, "v": 73000},
                {"t": 1, "v": 71000},
                {"t": 2, "v": 72000},
            ],
        }
        with patch(
            "stock_service.ai_models.kis_history_points",
            side_effect=StockServiceError("offline"),
        ):
            points, context = analysis_history_context(snapshot)

        self.assertTrue(context["fallback"])
        self.assertEqual(context["timeframe"], "1M")
        self.assertEqual([point["t"] for point in points], [1, 2, 3])
        self.assertEqual(context["message"], "offline")

    def test_prompt_includes_data_context(self):
        context = {
            "source": "kis_adjusted_daily",
            "sampleCount": 260,
            "timeframe": "1D",
        }
        news_context = {"status": "usable", "sourceCount": 4}
        prompt = analysis_prompt(
            {"symbol": "005930", "market": "KRX"},
            {"return20dPct": 1.2},
            {"status": "usable"},
            [],
            context,
            news_context,
        )
        payload = json.loads(prompt.split("\n", 1)[1])

        self.assertEqual(payload["dataContext"], context)
        self.assertEqual(payload["newsContext"], news_context)

    def test_prompt_uses_selected_output_language(self):
        english = analysis_prompt({}, {}, {}, [], language="en")
        korean = analysis_prompt({}, {}, {}, [], language="ko")

        self.assertIn("in concise English", english.split("\n", 1)[0])
        self.assertIn("간결한 한국어", korean.split("\n", 1)[0])

    def test_news_normalization_deduplicates_and_weights_recency(self):
        now = 1_000_000
        news = normalize_news_items([
            {
                "title": "Company launches product - Source A",
                "source": "Source A",
                "publishedAt": now - 3600,
            },
            {
                "title": "Company launches product",
                "source": "Source B",
                "publishedAt": now - 7200,
            },
            {
                "title": "Analyst updates outlook - Source C",
                "source": "Source C",
                "publishedAt": now - 25 * 3600,
            },
        ], now=now)

        self.assertEqual(len(news), 2)
        self.assertEqual(news[0]["title"], "Company launches product")
        self.assertGreater(news[0]["recencyWeight"], news[1]["recencyWeight"])

        context = news_evidence_context(news)
        self.assertEqual(context["headlineCount"], 2)
        self.assertEqual(context["sourceCount"], 2)
        self.assertEqual(context["recent24h"], 1)
        self.assertEqual(context["status"], "limited")

    def test_historical_calibration_reduces_overconfidence(self):
        prediction = {
            "provider": "openai",
            "model": "gpt-test",
            "stance": "bullish",
            "confidence": 90,
            "upProbability": 80,
            "flatProbability": 10,
            "downProbability": 10,
        }
        history = [
            {
                "status": "resolved",
                "symbol": "005930",
                "profile": "balanced",
                "outcome": "down",
                "modelPredictions": [prediction],
            }
            for _ in range(10)
        ]
        result = apply_historical_calibration(
            dict(prediction),
            [prediction],
            "balanced",
            "005930",
            history,
        )

        self.assertEqual(result["rawConfidence"], 90)
        self.assertLess(result["confidence"], 90)
        self.assertEqual(result["calibrationAdjustment"]["status"], "applied")
        self.assertEqual(
            result["upProbability"]
            + result["flatProbability"]
            + result["downProbability"],
            100,
        )

    def test_historical_calibration_requires_five_samples(self):
        prediction = {
            "provider": "claude",
            "model": "claude-test",
            "stance": "bearish",
            "confidence": 82,
            "upProbability": 10,
            "flatProbability": 15,
            "downProbability": 75,
        }
        history = [
            {
                "status": "resolved",
                "symbol": "AAPL",
                "profile": "deep",
                "outcome": "up",
                "modelPredictions": [prediction],
            }
            for _ in range(4)
        ]
        result = apply_historical_calibration(
            dict(prediction),
            [prediction],
            "deep",
            "AAPL",
            history,
        )

        self.assertEqual(result["confidence"], 82)
        self.assertEqual(result["calibrationAdjustment"]["status"], "insufficient")

    def test_opposing_models_reduce_confidence_and_become_neutral(self):
        result = consensus_result([
            self.model_result("bullish", 90, (90, 5, 5)),
            self.model_result("bearish", 90, (5, 5, 90)),
        ])

        self.assertEqual(result["stance"], "neutral")
        self.assertLess(result["confidence"], 90)
        self.assertEqual(result["ensembleAgreement"]["status"], "low")
        self.assertTrue(result["ensembleAgreement"]["directConflict"])
        self.assertGreater(result["ensembleAgreement"]["confidencePenalty"], 0)

    def test_agreeing_models_keep_most_confidence(self):
        result = consensus_result([
            self.model_result("bullish", 80, (70, 20, 10)),
            self.model_result("bullish", 82, (68, 22, 10)),
        ])

        self.assertEqual(result["stance"], "bullish")
        self.assertEqual(result["ensembleAgreement"]["status"], "high")
        self.assertLessEqual(result["ensembleAgreement"]["confidencePenalty"], 2)
        self.assertGreaterEqual(result["confidence"], 79)

    def test_single_model_marks_agreement_unavailable(self):
        result = consensus_result([
            self.model_result("neutral", 64, (30, 40, 30)),
        ])

        self.assertEqual(result["confidence"], 64)
        self.assertEqual(result["ensembleAgreement"]["status"], "single_model")
        self.assertEqual(result["ensembleAgreement"]["confidencePenalty"], 0)

    def test_historical_model_weighting_favors_resolved_performance(self):
        strong = dict(
            {"provider": "openai", "model": "gpt-test"},
            **self.model_result("bullish", 80, (75, 15, 10)),
        )
        weak = dict(
            {"provider": "claude", "model": "claude-test"},
            **self.model_result("bearish", 80, (10, 15, 75)),
        )
        history = [
            {
                "status": "resolved",
                "symbol": "005930",
                "profile": "balanced",
                "outcome": "up",
                "modelPredictions": [strong, weak],
            }
            for _ in range(20)
        ]

        weighting = historical_model_weighting(
            [strong, weak],
            "balanced",
            "005930",
            history,
        )

        self.assertEqual(weighting["status"], "applied")
        self.assertGreater(weighting["models"][0]["weight"], weighting["models"][1]["weight"])
        self.assertAlmostEqual(sum(model["share"] for model in weighting["models"]), 100, places=1)

    def test_consensus_uses_supplied_model_weights(self):
        strong = self.model_result("bullish", 80, (75, 15, 10))
        weak = self.model_result("bearish", 80, (10, 15, 75))

        equal = consensus_result([strong, weak])
        weighted = consensus_result([strong, weak], [1.3, 0.7])

        self.assertGreater(weighted["upProbability"], equal["upProbability"])
        self.assertLess(weighted["downProbability"], equal["downProbability"])

    def test_historical_model_weighting_stays_equal_with_small_samples(self):
        strong = dict(
            {"provider": "openai", "model": "gpt-test"},
            **self.model_result("bullish", 80, (75, 15, 10)),
        )
        weak = dict(
            {"provider": "claude", "model": "claude-test"},
            **self.model_result("bearish", 80, (10, 15, 75)),
        )
        history = [
            {
                "status": "resolved",
                "symbol": "005930",
                "profile": "balanced",
                "outcome": "up",
                "modelPredictions": [strong, weak],
            }
            for _ in range(4)
        ]

        weighting = historical_model_weighting(
            [strong, weak],
            "balanced",
            "005930",
            history,
        )

        self.assertEqual(weighting["status"], "limited")
        self.assertEqual([model["weight"] for model in weighting["models"]], [1.0, 1.0])

    def test_provider_failure_classifies_quota_without_retry(self):
        failure = ai_provider_failure(
            "openai",
            StockServiceError("You exceeded your current quota, please check your billing details"),
        )

        self.assertEqual(failure["code"], "quota")
        self.assertFalse(failure["retryable"])

    def test_both_provider_catalog_allows_one_available_model(self):
        catalog = {
            "status": "ok",
            "profiles": {"balanced": {"claude": {"id": "claude-test"}}},
            "providers": {
                "openai": {"status": "error", "message": "OpenAI catalog unavailable"},
                "claude": {"status": "ok", "models": [{"id": "claude-test"}]},
            },
            "generatedAt": 1,
        }

        with patch("stock_service.ai_models.build_model_catalog", return_value=catalog):
            selected, returned_catalog = resolve_profile_models("both", "balanced")

        self.assertEqual(selected, {"claude": {"id": "claude-test"}})
        self.assertIs(returned_catalog, catalog)

    def test_both_providers_preserve_claude_result_when_openai_fails(self):
        catalog = {
            "status": "ok",
            "profiles": {},
            "providers": {
                "openai": {"status": "ok", "models": []},
                "claude": {"status": "ok", "models": []},
            },
            "generatedAt": 1,
        }
        models = {
            "openai": {"id": "gpt-test"},
            "claude": {"id": "claude-test"},
        }
        claude_result = self.model_result("bullish", 72, (65, 25, 10))
        snapshot = {
            "mode": "demo",
            "symbol": "005930",
            "market": "KRX",
            "price": 73500,
            "chartRange": "1M",
        }
        with (
            patch("stock_service.forecasting.resolve_profile_models", return_value=(models, catalog)),
            patch("stock_service.forecasting.load_analysis_cache", return_value=None),
            patch("stock_service.forecasting.fetch_news", return_value=[]),
            patch("stock_service.forecasting.call_openai", side_effect=StockServiceError("quota exceeded")),
            patch(
                "stock_service.forecasting.call_claude",
                return_value=(claude_result, "claude-test", {"input_tokens": 900, "output_tokens": 300}),
            ),
            patch("stock_service.forecasting.append_ai_usage", return_value={
                "provider": "claude",
                "model": "claude-test",
                "inputTokens": 900,
                "billableInputTokens": 900,
                "outputTokens": 300,
                "totalTokens": 1200,
                "cachedInputTokens": 0,
                "cacheWriteTokens": 0,
                "reasoningTokens": 0,
            }),
            patch("stock_service.forecasting.load_forecasts", return_value=[]),
            patch("stock_service.forecasting.record_forecast", return_value={"id": "forecast-test"}),
            patch("stock_service.forecasting.save_analysis_cache"),
        ):
            result = analyze("both", "balanced", snapshot, True)

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["models"], ["claude-test"])
        self.assertEqual(result["providerStatus"]["effective"], ["claude"])
        self.assertTrue(result["providerStatus"]["degraded"])
        self.assertEqual(result["providerStatus"]["failures"][0]["code"], "quota")
        self.assertEqual(result["qualityGate"]["status"], "provider_degraded")
        self.assertEqual(result["qualityGate"]["confidenceStatus"], "qualified")
        self.assertEqual(result["analysisUsage"]["totalTokens"], 1200)

    def test_both_providers_report_combined_failure(self):
        catalog = {
            "status": "ok",
            "profiles": {},
            "providers": {
                "openai": {"status": "ok", "models": []},
                "claude": {"status": "ok", "models": []},
            },
            "generatedAt": 1,
        }
        models = {
            "openai": {"id": "gpt-test"},
            "claude": {"id": "claude-test"},
        }
        snapshot = {
            "mode": "demo",
            "symbol": "005930",
            "market": "KRX",
            "price": 73500,
            "chartRange": "1M",
        }
        with (
            patch("stock_service.forecasting.resolve_profile_models", return_value=(models, catalog)),
            patch("stock_service.forecasting.load_analysis_cache", return_value=None),
            patch("stock_service.forecasting.fetch_news", return_value=[]),
            patch("stock_service.forecasting.call_openai", side_effect=StockServiceError("quota exceeded")),
            patch("stock_service.forecasting.call_claude", side_effect=StockServiceError("service unavailable")),
        ):
            with self.assertRaisesRegex(StockServiceError, "All selected AI providers failed"):
                analyze("both", "balanced", snapshot, True)


if __name__ == "__main__":
    unittest.main()
