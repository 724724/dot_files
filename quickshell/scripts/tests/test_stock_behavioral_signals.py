import json
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.behavioral_signals import (
    behavior_signal_context,
    behavioral_ai_evidence,
    build_behavioral_evidence,
)


class StockBehavioralSignalTests(unittest.TestCase):
    now = 2_000_000_000

    def news(self, title, source, age_hours, **extra):
        relevance = extra.pop("relevanceWeight", 1)
        recency = extra.pop("recencyWeight", 0.95 if age_hours <= 6 else 0.55)
        return {
            "title": title,
            "source": source,
            "publishedAt": self.now - age_hours * 3600,
            "ageHours": age_hours,
            "recencyWeight": recency,
            "relevanceScore": round(relevance * 100),
            "relevanceWeight": relevance,
            "evidenceWeight": round(relevance * recency, 3),
            "relationType": "direct",
            "relationClass": "company",
            "materialEvent": True,
            "clusterId": "cluster:" + title.casefold(),
            "duplicateCount": 1,
            "duplicateSources": [source],
            **extra,
        }

    def snapshot(self, last_move_pct=1, volume_ratio=1):
        points = []
        for index in range(30):
            points.append({
                "t": self.now - (30 - index) * 86400,
                "v": 100 + index * 0.12 + (0.2 if index % 2 else -0.2),
                "volume": 1000,
            })
        return {
            "changePct": last_move_pct,
            "volume": 1000 * volume_ratio,
            "points": points,
        }

    def daily_context(self, volume_comparable=False):
        return {
            "timeframe": "1D",
            "completedSessions": True,
            "volumeComparable": volume_comparable,
            "sampleCount": 30,
            "sampleVolatilityPct": 12,
        }

    def test_negative_news_produces_structured_negativity(self):
        result = build_behavioral_evidence(
            self.snapshot(-1),
            self.daily_context(),
            [
                self.news("Company warns of weak demand and loss", "A", 1),
                self.news("Analyst downgrade follows investigation", "B", 3),
                self.news("회사가 적자와 수요 둔화 우려 발표", "C", 5),
            ],
            now=self.now,
        )

        polarity = result["features"]["newsPolarity"]
        self.assertEqual(polarity["direction"], "negative")
        self.assertGreater(polarity["negativeSharePct"], 90)
        self.assertGreater(result["features"]["negativity"]["score"], 60)

    def test_unique_events_improve_quality_without_creating_crowding(self):
        diverse = [
            self.news(
                f"Profit growth confirmed by filing {index}",
                f"Source {index}",
                index,
                clusterId=f"event-{index}",
            )
            for index in range(1, 6)
        ]
        repeated = [
            self.news(
                "Profit growth confirmed by filing",
                "Wire A",
                1,
                clusterId="one-event",
                duplicateCount=5,
                duplicateSources=["Wire A", "Outlet B", "Outlet C", "Outlet D", "Outlet E"],
            )
        ]

        diverse_result = build_behavioral_evidence(self.snapshot(), {}, diverse, now=self.now)
        repeated_result = build_behavioral_evidence(self.snapshot(), {}, repeated, now=self.now)

        self.assertEqual(diverse_result["status"], "usable")
        self.assertEqual(repeated_result["quality"]["eventCount"], 1)
        self.assertEqual(repeated_result["status"], "limited")
        self.assertGreater(diverse_result["quality"]["score"], repeated_result["quality"]["score"])
        self.assertLess(
            diverse_result["features"]["crowding"]["score"],
            repeated_result["features"]["crowding"]["score"],
        )

    def test_attention_requires_real_baseline_and_comparable_volume(self):
        news = [
            self.news(
                f"Breaking record demand surge for chip product {index}",
                f"S{index}",
                1,
                clusterId=f"event-{index}",
            )
            for index in range(5)
        ]
        without_baseline = build_behavioral_evidence(
            self.snapshot(2, volume_ratio=4),
            self.daily_context(volume_comparable=False),
            news,
            now=self.now,
        )
        with_baseline = build_behavioral_evidence(
            self.snapshot(2, volume_ratio=4),
            self.daily_context(volume_comparable=True),
            news,
            {"attentionBaseline": {"expectedEventWeight6h": 0.4, "sampleWindowCount": 20}},
            now=self.now,
        )

        self.assertFalse(without_baseline["features"]["attention"]["burstAvailable"])
        self.assertFalse(without_baseline["features"]["attention"]["volumeAvailable"])
        self.assertLessEqual(without_baseline["features"]["attention"]["score"], 10)
        self.assertTrue(with_baseline["features"]["attention"]["burstAvailable"])
        self.assertTrue(with_baseline["features"]["attention"]["volumeAvailable"])
        self.assertGreaterEqual(with_baseline["features"]["attention"]["score"], 70)

    def test_attention_can_detect_a_burst_after_observed_zero_windows(self):
        news = [
            self.news(
                f"Breaking demand surge {index}",
                f"S{index}",
                1,
                clusterId=f"zero-base-{index}",
            )
            for index in range(3)
        ]
        result = build_behavioral_evidence(
            self.snapshot(),
            self.daily_context(),
            news,
            {"attentionBaseline": {"expectedEventWeight6h": 0, "sampleWindowCount": 4}},
            now=self.now,
        )

        self.assertTrue(result["features"]["attention"]["burstAvailable"])
        self.assertGreater(result["features"]["attention"]["recentBurstRatio"], 1)

    def test_attention_uses_the_same_source_weighted_metric_as_its_baseline(self):
        news = [self.news(
            "Company confirms demand",
            "Standard Source",
            1,
            sourceWeight=0.5,
        )]
        result = build_behavioral_evidence(
            self.snapshot(),
            self.daily_context(),
            news,
            {"attentionBaseline": {"expectedEventWeight6h": 0.5, "sampleWindowCount": 12}},
            now=self.now,
        )

        self.assertEqual(result["features"]["attention"]["recentBurstRatio"], 1)

    def test_rejected_zero_stale_future_and_unknown_items_fail_closed(self):
        valid = self.news("Company confirms contract growth", "Valid", 1)
        zero = self.news("Company confirms profit", "Zero", 1, evidenceWeight=0)
        rejected = self.news("Company confirms growth", "Rejected", 1, relevanceStatus="rejected")
        stale = self.news("Company confirms record", "Stale", 100)
        future = self.news("Company confirms expansion", "Future", 1, publishedAt=self.now + 3600)
        unknown = self.news("Company confirms demand", "Unknown", 1, publishedAt=0)

        result = build_behavioral_evidence(
            self.snapshot(), {}, [valid, zero, rejected, stale, future, unknown], now=self.now
        )

        self.assertEqual(result["quality"]["eventCount"], 1)
        self.assertEqual(result["quality"]["rejectedItemCount"], 5)
        self.assertEqual(result["status"], "limited")

    def test_missing_relation_type_is_rejected(self):
        item = self.news("Record contract growth", "A", 1, relationType="")
        result = build_behavioral_evidence(self.snapshot(), {}, [item], now=self.now)

        self.assertEqual(result["status"], "insufficient")
        self.assertEqual(result["quality"]["eventCount"], 0)

    def test_clustered_duplicates_do_not_inflate_directional_sample(self):
        item = self.news(
            "Company reports profit growth",
            "A",
            1,
            clusterId="earnings-event",
            duplicateCount=8,
            duplicateSources=[f"Publisher {index}" for index in range(8)],
        )
        result = build_behavioral_evidence(self.snapshot(), {}, [item], now=self.now)

        self.assertEqual(result["quality"]["headlineCount"], 8)
        self.assertEqual(result["quality"]["eventCount"], 1)
        self.assertEqual(result["quality"]["directionalHeadlineCount"], 1)
        self.assertEqual(result["status"], "limited")
        self.assertGreater(result["features"]["crowding"]["score"], 40)

    def test_price_signals_require_completed_daily_context(self):
        news = [self.news("Company holds routine annual meeting", "A", 30)]
        unavailable = build_behavioral_evidence(self.snapshot(8, 3), {}, news, now=self.now)
        available = build_behavioral_evidence(
            self.snapshot(8, 3), self.daily_context(True), news, now=self.now
        )

        self.assertFalse(unavailable["features"]["overreaction"]["available"])
        self.assertEqual(unavailable["features"]["overreaction"]["score"], 0)
        self.assertTrue(available["features"]["overreaction"]["available"])
        self.assertGreaterEqual(available["features"]["overreaction"]["score"], 70)

    def test_intraday_points_fail_even_when_mislabeled_daily(self):
        snapshot = self.snapshot(8, 3)
        snapshot["points"] = [
            {"t": self.now - (30 - index) * 60, "v": 100 + index * 0.1, "volume": 1000}
            for index in range(30)
        ]
        result = build_behavioral_evidence(
            snapshot,
            self.daily_context(True),
            [self.news("Company holds annual meeting", "A", 1)],
            now=self.now,
        )

        self.assertFalse(result["features"]["overreaction"]["available"])
        self.assertEqual(
            result["features"]["overreaction"]["unavailableReason"],
            "daily_cadence_required",
        )

    def test_price_news_divergence_uses_completed_daily_data(self):
        news = [
            self.news("Demand decline prompts profit warning", "A", 1, clusterId="e1"),
            self.news("Analyst downgrade after weak results", "B", 2, clusterId="e2"),
            self.news("Investigation risk weighs on outlook", "C", 3, clusterId="e3"),
            self.news("Loss expected after product recall", "D", 4, clusterId="e4"),
            self.news("Growth forecast cut as demand falls", "E", 5, clusterId="e5"),
        ]
        result = build_behavioral_evidence(
            self.snapshot(4), self.daily_context(), news, now=self.now
        )

        divergence = result["features"]["priceNewsDivergence"]
        self.assertTrue(divergence["available"])
        self.assertEqual(divergence["kind"], "price_up_news_negative")
        self.assertGreater(divergence["score"], 40)

    def test_upstream_quality_caps_local_quality(self):
        news = [
            self.news(
                f"Record contract growth confirmed {index}", f"Source {index}", index,
                clusterId=f"event-{index}",
            )
            for index in range(1, 6)
        ]
        result = build_behavioral_evidence(
            self.snapshot(), {}, news, {"qualityScore": 25, "freshnessScore": 30}, now=self.now
        )

        self.assertLessEqual(result["quality"]["score"], 25)
        self.assertNotEqual(result["status"], "usable")

    def test_ai_evidence_contains_no_raw_headlines_or_source_names(self):
        title = "SECRET RAW HEADLINE profit growth"
        source = "PRIVATE SOURCE NAME"
        evidence = behavioral_ai_evidence(
            self.snapshot(), {}, [self.news(title, source, 1)], now=self.now
        )
        serialized = json.dumps(evidence, ensure_ascii=False)

        self.assertNotIn(title, serialized)
        self.assertNotIn(source, serialized)
        self.assertEqual(evidence["method"], "deterministic_behavioral_features")
        self.assertEqual(len(evidence["signals"]), 7)

    def test_risk_features_never_expose_bullish_direction(self):
        calm = [self.news("Company holds annual meeting", "A", 1)]
        crowded = [
            self.news(
                "Breaking profit surge",
                "A",
                1,
                clusterId="one-event",
                duplicateCount=8,
                duplicateSources=[f"Publisher {index}" for index in range(8)],
            )
        ]
        calm_context = behavior_signal_context(calm, {}, self.snapshot(), now=self.now)
        crowded_context = behavior_signal_context(crowded, {}, self.snapshot(), now=self.now)

        for key in ("attention", "crowding", "overreaction"):
            self.assertNotIn("direction", crowded_context[key])
            self.assertNotIn("upProbability", crowded_context[key])
        self.assertGreater(crowded_context["riskPenalty"], calm_context["riskPenalty"])
        self.assertLessEqual(
            crowded_context["riskAdjustedEvidenceConfidence"],
            crowded_context["evidenceConfidence"],
        )

    def test_evidence_confidence_name_and_compatibility_alias_match(self):
        news = [
            self.news(f"Contract confirmed {index}", f"S{index}", index, clusterId=f"e{index}")
            for index in range(5)
        ]
        context = behavior_signal_context(news, {}, self.snapshot(), now=self.now)

        self.assertEqual(context["confidence"], context["evidenceConfidence"])
        self.assertLessEqual(context["riskAdjustedEvidenceConfidence"], context["evidenceConfidence"])

    def test_article_order_does_not_change_evidence(self):
        news = [
            self.news(f"Contract growth event {index}", f"S{index}", index, clusterId=f"e{index}")
            for index in range(1, 6)
        ]
        first = build_behavioral_evidence(self.snapshot(), {}, news, now=self.now)
        second = build_behavioral_evidence(self.snapshot(), {}, list(reversed(news)), now=self.now)

        self.assertEqual(first["quality"], second["quality"])
        self.assertEqual(first["features"], second["features"])

    def test_theme_news_never_counts_as_direct_support(self):
        news = [
            self.news(
                f"Industry demand growth {index}",
                f"S{index}",
                index,
                clusterId=f"e{index}",
                relationType="theme",
                relationClass="industry",
            )
            for index in range(5)
        ]
        result = build_behavioral_evidence(
            self.snapshot(5), self.daily_context(), news, now=self.now
        )

        self.assertEqual(result["quality"]["directEventPct"], 0)
        self.assertEqual(result["features"]["overreaction"]["directionalNewsSupport"], 0)

    def test_nonmaterial_company_commentary_never_counts_as_direct_support(self):
        news = [
            self.news(
                f"Analyst bullish commentary {index}",
                f"S{index}",
                index,
                clusterId=f"commentary-{index}",
                materialEvent=False,
            )
            for index in range(5)
        ]
        result = build_behavioral_evidence(
            self.snapshot(5), self.daily_context(), news, now=self.now
        )

        self.assertEqual(result["quality"]["directEventPct"], 0)
        self.assertEqual(result["features"]["overreaction"]["directionalNewsSupport"], 0)

    def test_empty_news_is_insufficient_and_deterministic(self):
        first = build_behavioral_evidence(self.snapshot(), {}, [], now=self.now)
        second = build_behavioral_evidence(self.snapshot(), {}, [], now=self.now)

        self.assertEqual(first, second)
        self.assertEqual(first["status"], "insufficient")
        self.assertEqual(first["quality"]["eventCount"], 0)

    def test_english_terms_do_not_match_inside_unrelated_words(self):
        result = build_behavioral_evidence(
            self.snapshot(),
            {},
            [self.news("Company executes enterprise software plan", "A", 1)],
            now=self.now,
        )

        polarity = result["features"]["newsPolarity"]
        self.assertEqual(polarity["direction"], "neutral")
        self.assertEqual(polarity["uncertaintyPct"], 0)


if __name__ == "__main__":
    unittest.main()
