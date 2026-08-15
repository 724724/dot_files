import math
import re
import statistics
import time
from collections import defaultdict


BEHAVIORAL_EVIDENCE_VERSION = 5
MAX_NEWS_AGE_HOURS = 72
FUTURE_TOLERANCE_SECONDS = 5 * 60
ACCEPTED_RELATION_TYPES = {
    "direct", "theme", "direct-impact", "connected-impact", "sector-context",
}
REJECTED_RELEVANCE_VALUES = {
    "false", "invalid", "noise", "rejected", "unrelated", "excluded",
}

POSITIVE_TERMS = (
    "approval", "beat", "buyback", "contract", "demand", "dividend", "expansion", "growth", "launch",
    "outperform", "profit", "record", "recovery", "rise", "strong", "surge",
    "upgrade", "승인", "상승", "상향", "성장", "수요", "수주", "신기록",
    "출시", "최고", "호실적", "회복", "흑자", "증설", "강세", "수출", "배당", "자사주",
)
NEGATIVE_TERMS = (
    "bankruptcy", "crash", "cut", "default", "decline", "downgrade", "fraud",
    "investigation", "layoff", "lawsuit", "loss", "miss", "recall", "risk",
    "slump", "warning", "weak", "bubble", "overheat", "overvalued", "valuation gap", "감산", "급락", "둔화", "리콜", "부도",
    "부진", "소송", "손실", "수사", "위험", "우려", "적자", "조사",
    "폭락", "하락", "하향", "해고", "약세", "과열", "거품", "고평가", "괴리율",
)
UNCERTAINTY_TERMS = (
    "alleged", "considering", "could", "expected", "forecast", "may", "might",
    "reportedly", "rumor", "가능", "검토", "관측", "루머", "소문", "예상",
    "전망", "추정",
)
ATTENTION_TERMS = (
    "breaking", "crash", "exclusive", "hot", "must", "shocking", "skyrocket",
    "urgent", "긴급", "단독", "대박", "주목", "충격", "폭등", "폭락", "급등",
    "급락",
)
STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in",
    "is", "it", "of", "on", "or", "that", "the", "this", "to", "with", "after",
    "before", "new", "says", "said", "대한", "관련", "기자", "뉴스", "오늘", "통해",
    "위한", "에서", "으로", "한다", "밝혀", "발표",
}
TOKEN_PATTERN = re.compile(r"[0-9A-Za-z가-힣]+")


def _numeric(value, fallback=0.0):
    try:
        number = float(value)
        return number if math.isfinite(number) else float(fallback)
    except (TypeError, ValueError):
        return float(fallback)


def _clamp(value, minimum=0.0, maximum=100.0):
    return max(minimum, min(maximum, float(value)))


def _rounded(value, digits=1):
    return round(float(value), digits)


def _level(score):
    score = _numeric(score)
    if score >= 70:
        return "high"
    if score >= 40:
        return "moderate"
    return "low"


def _tokens(text):
    return [token.casefold() for token in TOKEN_PATTERN.findall(str(text))]


def _term_count(text, terms):
    lowered = str(text).casefold()
    count = 0
    for term in terms:
        if term.isascii():
            count += int(bool(re.search(r"(?<![0-9a-z])" + re.escape(term) + r"(?![0-9a-z])", lowered)))
        else:
            count += int(term in lowered)
    return count


def _source_key(source):
    value = re.sub(r"\s+", " ", str(source or "").strip().casefold())
    value = re.sub(r"\.(com|co\.kr|net|org)$", "", value)
    return value if value and value != "unknown" else ""


def _news_weight(item, age_hours):
    recency = math.exp(-max(0, age_hours) / 72) if age_hours < 9999 else 0
    relevance = item.get("relevanceWeight")
    if relevance is None:
        score = item.get("relevanceScore")
        if score is None:
            return 0
        relevance = _numeric(score) / 100
    derived = _clamp(_numeric(recency) * _numeric(relevance), 0, 1)
    if item.get("evidenceWeight") is None:
        return derived
    return min(derived, _clamp(_numeric(item.get("evidenceWeight")), 0, 1))


def _normalized_relation(value):
    return str(value or "").strip().casefold().replace("_", "-")


def _relevance_is_accepted(item):
    if item.get("accepted") is False:
        return False
    for key in ("relevanceStatus", "relevanceDecision", "status"):
        value = str(item.get(key) or "").strip().casefold()
        if value in REJECTED_RELEVANCE_VALUES:
            return False
    relation = _normalized_relation(item.get("relationType"))
    if relation not in ACCEPTED_RELATION_TYPES:
        return False
    if item.get("relevanceScore") is None and item.get("relevanceWeight") is None:
        return False
    if item.get("relevanceScore") is not None and _numeric(item.get("relevanceScore")) <= 0:
        return False
    if item.get("relevanceWeight") is not None and _numeric(item.get("relevanceWeight")) <= 0:
        return False
    return True


def _published_age_hours(item, now):
    published_at = int(_numeric(item.get("publishedAt")))
    if published_at <= 0 or published_at > 10_000_000_000:
        return 0, None
    if published_at > now + FUTURE_TOLERANCE_SECONDS:
        return published_at, None
    age_hours = max(0, (now - published_at) / 3600)
    if age_hours > MAX_NEWS_AGE_HOURS:
        return published_at, None
    return published_at, age_hours


def _story_key(item, title):
    for key in ("storyId", "eventClusterId", "clusterId"):
        value = str(item.get(key) or "").strip()
        if value:
            return value
    identity = " ".join(
        token for token in _tokens(title)
        if token not in STOP_WORDS
    )
    return "title:" + identity


def _provenance(item):
    nested = item.get("provenance") if isinstance(item.get("provenance"), dict) else {}
    primary = _source_key(
        item.get("originSource")
        or item.get("canonicalSource")
        or nested.get("originSource")
        or nested.get("canonicalSource")
        or item.get("source")
    )
    publishers = {primary} if primary else set()
    duplicate_sources = item.get("duplicateSources")
    if isinstance(duplicate_sources, list):
        publishers.update(
            source for source in (_source_key(value) for value in duplicate_sources)
            if source
        )
    duplicate_count = max(1, int(_numeric(item.get("duplicateCount"), 1)))
    return primary, publishers, duplicate_count


def _headline_observations(news, now):
    observations = []
    rejected_count = 0
    for item in news or []:
        if not isinstance(item, dict):
            rejected_count += 1
            continue
        title = str(item.get("title") or "").strip()
        if not title or not _relevance_is_accepted(item):
            rejected_count += 1
            continue
        published_at, age_hours = _published_age_hours(item, now)
        if age_hours is None:
            rejected_count += 1
            continue
        weight = _news_weight(item, age_hours)
        if weight <= 0:
            rejected_count += 1
            continue
        positive = _term_count(title, POSITIVE_TERMS)
        negative = _term_count(title, NEGATIVE_TERMS)
        directional = positive + negative
        polarity = (positive - negative) / directional if directional else 0
        source, publishers, article_count = _provenance(item)
        topic = str(item.get("relationTopic") or "").strip().casefold()
        topic_tokens = {
            token for token in _tokens(title)
            if len(token) >= 2
            and token not in STOP_WORDS
            and not any(term == token for term in POSITIVE_TERMS + NEGATIVE_TERMS + ATTENTION_TERMS)
        }
        observations.append({
            "publishedAt": published_at,
            "ageHours": age_hours,
            "weight": weight,
            "recencyWeight": math.exp(-age_hours / 72),
            "relevanceWeight": _clamp(
                _numeric(
                    item.get("relevanceWeight"),
                    _numeric(item.get("relevanceScore")) / 100,
                ),
                0,
                1,
            ),
            "attentionWeight": _clamp(
                _numeric(
                    item.get("relevanceWeight"),
                    _numeric(item.get("relevanceScore")) / 100,
                ),
                0,
                1,
            ) * _clamp(_numeric(item.get("sourceWeight"), 1), 0, 1),
            "polarity": polarity,
            "directional": directional > 0,
            "positive": positive,
            "negative": negative,
            "uncertainty": _term_count(title, UNCERTAINTY_TERMS),
            "attention": _term_count(title, ATTENTION_TERMS),
            "source": source,
            "publishers": publishers,
            "articleCount": article_count,
            "topic": topic,
            "tokens": topic_tokens,
            "storyId": _story_key(item, title),
            "direct": (
                _normalized_relation(item.get("relationType")) in {"direct", "direct-impact"}
                and bool(item.get("materialEvent"))
            ),
        })
    return observations, rejected_count


def _aggregate_events(observations):
    groups = defaultdict(list)
    for observation in observations:
        groups[observation["storyId"]].append(observation)
    events = []
    for story_id in sorted(groups):
        members = sorted(
            groups[story_id],
            key=lambda item: (item["publishedAt"], item["source"]),
        )
        weight_total = sum(item["weight"] for item in members)
        polarity = (
            sum(item["polarity"] * item["weight"] for item in members) / weight_total
            if weight_total > 0 else 0
        )
        publishers = set().union(*(item["publishers"] for item in members))
        primary_sources = {item["source"] for item in members if item["source"]}
        events.append({
            "storyId": story_id,
            "ageHours": min(item["ageHours"] for item in members),
            "weight": max(item["weight"] for item in members),
            "recencyWeight": max(item["recencyWeight"] for item in members),
            "relevanceWeight": max(item["relevanceWeight"] for item in members),
            "attentionWeight": max(item["attentionWeight"] for item in members),
            "polarity": polarity,
            "directional": abs(polarity) > 0.01,
            "uncertainty": max(item["uncertainty"] for item in members),
            "attention": max(item["attention"] for item in members),
            "direct": any(item["direct"] for item in members),
            "articleCount": max(
                len(members),
                max(item["articleCount"] for item in members),
            ),
            "publishers": publishers,
            "primarySources": primary_sources,
        })
    return events


def _completed_daily_context(snapshot, chart):
    contexts = [snapshot, chart]
    for container in (snapshot, chart):
        for key in ("analysisContext", "historyContext"):
            if isinstance(container.get(key), dict):
                contexts.append(container[key])
    timeframe = next(
        (
            str(context.get("timeframe") or context.get("pointsTimeframe") or "").upper()
            for context in contexts
            if context.get("timeframe") or context.get("pointsTimeframe")
        ),
        "",
    )
    completed = any(context.get("completedSessions") is True for context in contexts)
    volume_comparable = any(
        context.get("volumeComparable") is True or context.get("marketClosed") is True
        for context in contexts
    )
    return timeframe == "1D" and completed, volume_comparable


def _daily_points(points, now):
    normalized = {}
    for point in points or []:
        timestamp = int(_numeric(point.get("t")))
        value = _numeric(point.get("v"))
        if timestamp <= 0 or timestamp > now + FUTURE_TOLERANCE_SECONDS or value <= 0:
            continue
        normalized[timestamp] = {
            "t": timestamp,
            "v": value,
            "volume": max(0, _numeric(point.get("volume"))),
        }
    return [normalized[key] for key in sorted(normalized)]


def _daily_returns(points):
    values = [point["v"] for point in points]
    return [
        (current / previous - 1) * 100
        for previous, current in zip(values, values[1:])
        if previous > 0
    ]


def _price_evidence(snapshot, chart, now):
    daily_context, volume_comparable = _completed_daily_context(snapshot, chart)
    if not daily_context:
        return {
            "available": False,
            "volumeAvailable": False,
            "returnPct": 0,
            "dailyVolatilityPct": 0,
            "moveZScore": 0,
            "volumeRatio": 0,
            "reason": "completed_daily_context_required",
        }
    points = _daily_points(snapshot.get("points") or [], now)
    gaps = [current["t"] - previous["t"] for previous, current in zip(points, points[1:])]
    median_gap = statistics.median(gaps) if gaps else 0
    if median_gap < 12 * 60 * 60 or median_gap > 4 * 24 * 60 * 60:
        return {
            "available": False,
            "volumeAvailable": False,
            "returnPct": _numeric(snapshot.get("changePct")),
            "dailyVolatilityPct": 0,
            "moveZScore": 0,
            "volumeRatio": 0,
            "reason": "daily_cadence_required",
        }
    returns = _daily_returns(points)
    price_return = _numeric(snapshot.get("changePct"), returns[-1] if returns else 0)
    baseline = returns[-20:]
    daily_volatility = statistics.stdev(baseline) if len(baseline) >= 2 else 0
    if daily_volatility <= 0:
        annualized = _numeric(chart.get("sampleVolatilityPct"))
        sample_count = int(_numeric(chart.get("sampleCount")))
        daily_volatility = annualized / math.sqrt(252) if annualized > 0 and sample_count >= 10 else 0
    if daily_volatility <= 0 or len(returns) < 10:
        return {
            "available": False,
            "volumeAvailable": False,
            "returnPct": price_return,
            "dailyVolatilityPct": 0,
            "moveZScore": 0,
            "volumeRatio": 0,
            "reason": "daily_history_insufficient",
        }
    daily_volatility = max(0.5, daily_volatility)
    volumes = [
        point["volume"]
        for point in points
        if point["volume"] > 0
    ]
    current_volume = _numeric(snapshot.get("volume"), volumes[-1] if volumes else 0)
    baseline_volumes = volumes[-20:] if len(volumes) >= 5 else []
    volume_ratio = (
        current_volume / statistics.median(baseline_volumes)
        if volume_comparable
        and current_volume > 0
        and baseline_volumes
        and statistics.median(baseline_volumes) > 0
        else 0
    )
    return {
        "available": True,
        "volumeAvailable": volume_ratio > 0,
        "returnPct": price_return,
        "dailyVolatilityPct": daily_volatility,
        "moveZScore": abs(price_return) / daily_volatility,
        "volumeRatio": volume_ratio,
        "reason": "",
    }


def _attention_baseline(context):
    baseline = context.get("attentionBaseline")
    if not isinstance(baseline, dict):
        baseline = context.get("behaviorBaseline")
    if not isinstance(baseline, dict):
        return 0, 0, False
    expected_value = baseline.get("expectedEventWeight6h")
    if expected_value is None:
        expected_value = baseline.get("meanEventWeight6h")
    sample_value = baseline.get("sampleWindowCount")
    if sample_value is None:
        sample_value = baseline.get("sampleCount")
    expected = _numeric(expected_value, -1)
    samples = int(_numeric(sample_value, 0))
    return expected, samples, expected >= 0 and samples >= 4


def build_behavioral_evidence(snapshot, chart_features, news, news_context=None, now=None):
    now = int(now or time.time())
    snapshot = snapshot if isinstance(snapshot, dict) else {}
    chart = chart_features if isinstance(chart_features, dict) else {}
    context = news_context if isinstance(news_context, dict) else {}
    observations, rejected_count = _headline_observations(news, now)
    events = _aggregate_events(observations)
    event_count = len(events)
    headline_count = sum(item["articleCount"] for item in events)
    primary_sources = set().union(*(item["primarySources"] for item in events)) if events else set()
    publishers = set().union(*(item["publishers"] for item in events)) if events else set()
    direct_count = sum(item["direct"] for item in events)
    total_weight = sum(item["weight"] for item in events)
    directional = [item for item in events if item["directional"]]
    directional_weight = sum(item["weight"] for item in directional)
    weighted_polarity = (
        sum(item["polarity"] * item["weight"] for item in directional) / directional_weight
        if directional_weight > 0 else 0
    )
    positive_weight = sum(
        max(0, item["polarity"]) * item["weight"] for item in directional
    )
    negative_weight = sum(
        max(0, -item["polarity"]) * item["weight"] for item in directional
    )
    directional_total = positive_weight + negative_weight
    positive_share = positive_weight / directional_total * 100 if directional_total else 0
    negative_share = negative_weight / directional_total * 100 if directional_total else 0
    uncertainty_rate = (
        sum(item["uncertainty"] > 0 for item in events) / event_count * 100
        if event_count else 0
    )
    sensational_rate = (
        sum(item["attention"] > 0 for item in events) / event_count * 100
        if event_count else 0
    )

    relevance_total = sum(item["relevanceWeight"] for item in events)
    freshness = (
        sum(item["recencyWeight"] * item["relevanceWeight"] for item in events)
        / relevance_total * 100
        if relevance_total > 0 else 0
    )
    upstream_freshness = _numeric(context.get("freshnessScore"), -1)
    if upstream_freshness >= 0:
        freshness = min(freshness, upstream_freshness)
    source_independence = len(primary_sources) / event_count * 100 if event_count else 0
    source_coverage = min(100, len(primary_sources) / 5 * 100)
    event_coverage = min(100, event_count / 5 * 100)
    direct_weight = sum(item["weight"] for item in events if item["direct"])
    direct_share = direct_weight / total_weight * 100 if total_weight else 0
    mean_relevance = relevance_total / event_count * 100 if event_count else 0
    evidence_quality = (
        freshness * 0.20
        + source_coverage * 0.15
        + event_coverage * 0.20
        + source_independence * 0.10
        + direct_share * 0.15
        + mean_relevance * 0.20
    ) if event_count else 0
    upstream_quality = _numeric(context.get("qualityScore"), -1)
    if upstream_quality >= 0:
        evidence_quality = min(evidence_quality, upstream_quality)

    recent_six = sum(item["attentionWeight"] for item in events if item["ageHours"] <= 6)
    baseline_six, baseline_samples, burst_available = _attention_baseline(context)
    burst_ratio = recent_six / max(0.05, baseline_six) if burst_available else 0
    burst_score = (
        _clamp(max(0, math.log2(max(burst_ratio, 1))) * 28)
        if burst_available else 0
    )
    price = _price_evidence(snapshot, chart, now)
    volume_score = (
        _clamp((price["volumeRatio"] - 1) * 50)
        if price["volumeAvailable"] else 0
    )
    attention_score = _clamp(
        burst_score * 0.55
        + volume_score * 0.35
        + sensational_rate * 0.10
    )

    duplicate_count = max(0, headline_count - event_count)
    duplicate_rate = duplicate_count / headline_count * 100 if headline_count else 0
    dominant_story_share = (
        max(item["weight"] for item in events) / total_weight
        if total_weight else 0
    )
    consensus = max(positive_share, negative_share) if directional_total else 0
    narrative_concentration = dominant_story_share * consensus
    sample_factor = min(1, event_count / 3)
    crowding_score = _clamp(
        duplicate_rate * 0.55
        + narrative_concentration * 0.30 * sample_factor
        + sensational_rate * 0.15
    )

    price_direction = 1 if price["returnPct"] > 0.1 else -1 if price["returnPct"] < -0.1 else 0
    news_direction = 1 if weighted_polarity > 0.1 else -1 if weighted_polarity < -0.1 else 0
    direct_directional_count = sum(item["direct"] for item in directional)
    direct_sample_factor = min(1, direct_directional_count / 3)
    direction_support = (
        abs(weighted_polarity) * evidence_quality / 100 * direct_sample_factor
        if price["available"] and price_direction and price_direction == news_direction else 0
    )
    excess_move = max(0, price["moveZScore"] - 1) if price["available"] else 0
    unsupported = 1 - min(1, direction_support)
    overreaction_score = (
        _clamp(
            excess_move * 34 * (0.55 + unsupported * 0.45)
            + attention_score * 0.18
            + (100 - evidence_quality) * 0.10 * min(1, excess_move)
        )
        if price["available"] else 0
    )

    if price["available"] and price_direction and news_direction and price_direction != news_direction:
        divergence_kind = "price_up_news_negative" if price_direction > 0 else "price_down_news_positive"
        divergence_score = _clamp(
            min(1, price["moveZScore"] / 2.5)
            * abs(weighted_polarity)
            * evidence_quality
        )
    elif price["available"] and price_direction and news_direction == 0 and price["moveZScore"] >= 1:
        divergence_kind = "price_move_without_news"
        divergence_score = _clamp(
            min(1, price["moveZScore"] / 2.5) * (100 - evidence_quality)
        )
    elif not price["available"]:
        divergence_kind = "unavailable"
        divergence_score = 0
    else:
        divergence_kind = "aligned" if price_direction and news_direction else "none"
        divergence_score = 0

    news_disagreement = min(positive_share, negative_share) * 2 if directional_total else 0
    disagreement_score = max(news_disagreement, divergence_score)

    negativity_score = _clamp(
        negative_share * 0.70
        + max(0, -weighted_polarity) * 20
        + sensational_rate * 0.10
    )
    if not events:
        status = "insufficient"
    elif event_count >= 3 and len(primary_sources) >= 3 and evidence_quality >= 60:
        status = "usable"
    else:
        status = "limited"

    quality = {
        "status": status,
        "score": round(_clamp(evidence_quality)),
        "headlineCount": headline_count,
        "acceptedItemCount": len(observations),
        "rejectedItemCount": rejected_count,
        "eventCount": event_count,
        "directionalHeadlineCount": len(directional),
        "independentSourceCount": len(primary_sources),
        "distinctPublisherCount": len(publishers),
        "sourceIndependencePct": _rounded(source_independence),
        "freshnessScore": round(_clamp(freshness)),
        "directHeadlinePct": _rounded(direct_share),
        "directEventPct": _rounded(direct_share),
        "duplicateArticlePct": _rounded(duplicate_rate),
    }
    crowding = {
        "score": round(crowding_score),
        "level": _level(crowding_score),
        "directionalConsensusPct": _rounded(consensus),
        "dominantStorySharePct": _rounded(dominant_story_share * 100),
        "dominantTopicSharePct": _rounded(dominant_story_share * 100),
        "duplicateArticlePct": _rounded(duplicate_rate),
        "distinctPublisherCount": len(publishers),
    }
    features = {
        "newsPolarity": {
            "score": _rounded(weighted_polarity * 100),
            "direction": "positive" if news_direction > 0 else "negative" if news_direction < 0 else "neutral",
            "positiveSharePct": _rounded(positive_share),
            "negativeSharePct": _rounded(negative_share),
            "uncertaintyPct": _rounded(uncertainty_rate),
        },
        "negativity": {
            "score": round(negativity_score),
            "level": _level(negativity_score),
            "sensationalHeadlinePct": _rounded(sensational_rate),
        },
        "attention": {
            "score": round(attention_score),
            "level": _level(attention_score),
            "recentBurstRatio": _rounded(burst_ratio, 2),
            "burstAvailable": burst_available,
            "baselineWindowCount": baseline_samples,
            "abnormalVolumeRatio": _rounded(price["volumeRatio"], 2),
            "volumeAvailable": price["volumeAvailable"],
        },
        "crowding": crowding,
        "herding": crowding,
        "overreaction": {
            "score": round(overreaction_score),
            "level": _level(overreaction_score),
            "available": price["available"],
            "priceMovePct": _rounded(price["returnPct"], 2),
            "moveZScore": _rounded(price["moveZScore"], 2),
            "directionalNewsSupport": _rounded(direction_support * 100),
            "unavailableReason": price["reason"],
        },
        "priceNewsDivergence": {
            "score": round(divergence_score),
            "level": _level(divergence_score),
            "kind": divergence_kind,
            "available": price["available"],
        },
        "disagreement": {
            "score": round(disagreement_score),
            "level": _level(disagreement_score),
            "newsDirectionalConflictPct": _rounded(news_disagreement),
            "includesPriceNewsConflict": divergence_score > 0,
        },
    }
    ai_evidence = {
        "version": BEHAVIORAL_EVIDENCE_VERSION,
        "method": "deterministic_behavioral_features",
        "quality": quality,
        "signals": [
            dict({"id": signal_id}, **features[signal_id])
            for signal_id in (
                "newsPolarity", "negativity", "attention", "crowding",
                "overreaction", "priceNewsDivergence", "disagreement",
            )
        ],
        "interpretationRules": [
            "High attention or crowding is risk-only and never directional evidence.",
            "Overreaction and price-news divergence increase uncertainty, not expected return.",
            "Reduce confidence when evidence quality is limited or insufficient.",
            "Low risk scores must never be converted into bullish evidence.",
        ],
    }
    return {
        "version": BEHAVIORAL_EVIDENCE_VERSION,
        "generatedAt": now,
        "status": status,
        "quality": quality,
        "features": features,
        "aiEvidence": ai_evidence,
    }


def behavioral_ai_evidence(snapshot, chart_features, news, news_context=None, now=None):
    return build_behavioral_evidence(
        snapshot,
        chart_features,
        news,
        news_context,
        now,
    )["aiEvidence"]


def behavior_signal_context(news, chart_features=None, snapshot=None, news_context=None, now=None):
    evidence = build_behavioral_evidence(
        snapshot or {},
        chart_features or {},
        news,
        news_context,
        now,
    )
    features = evidence["features"]
    quality = evidence["quality"]
    attention = features["attention"]
    crowding = features["crowding"]
    overreaction = features["overreaction"]
    disagreement = features["disagreement"]
    divergence = features["priceNewsDivergence"]
    negativity = features["negativity"]
    risk_penalty = _clamp(
        attention["score"] * 0.18
        + crowding["score"] * 0.20
        + overreaction["score"] * 0.27
        + disagreement["score"] * 0.20
        + negativity["score"] * 0.15
    )
    uncertainty = features["newsPolarity"]["uncertaintyPct"] / 100
    sample_factor = min(1, quality["eventCount"] / 5)
    evidence_confidence = _clamp(
        quality["score"] * sample_factor * (1 - min(0.35, uncertainty * 0.35))
    )
    risk_adjusted_evidence_confidence = evidence_confidence * (1 - risk_penalty / 200)
    return {
        "version": BEHAVIORAL_EVIDENCE_VERSION,
        "status": evidence["status"],
        "evidenceConfidence": round(evidence_confidence),
        "riskAdjustedEvidenceConfidence": round(risk_adjusted_evidence_confidence),
        "confidence": round(evidence_confidence),
        "riskPenalty": round(risk_penalty),
        "attention": attention,
        "crowding": crowding,
        "overreaction": overreaction,
        "disagreement": disagreement,
        "priceNewsDivergence": divergence,
        "negativity": negativity,
        "newsPolarity": features["newsPolarity"],
        "quality": quality,
        "rules": [
            "Attention and crowding only increase risk; they never imply bullish direction.",
            "Price-news divergence and overreaction reduce conviction.",
            "Limited or insufficient evidence must reduce model confidence.",
            "Never transform a low risk penalty into positive expected return.",
        ],
    }
