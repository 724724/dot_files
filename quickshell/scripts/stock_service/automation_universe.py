import fcntl
import json
import os
import re
import time
from contextlib import contextmanager

from .automation import (
    STOCK_PROFILE_PATH,
    automation_lock,
    clear_live_auto_session,
    load_automation_policy,
    open_live_auto_session,
    save_automation_policy,
)
from .broker import kis_snapshot
from .core import SECURITIES, StockServiceError, numeric, state_directory
from .forecasting import analyze
from .quant import normalized_history_points, technical_screen_metrics


AUTOPILOT_STATE_VERSION = 5
AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS = 60 * 60
AUTOPILOT_FAILED_SCAN_RETRY_SECONDS = 5 * 60
AUTOPILOT_MAX_UNIVERSE = 256
AUTOPILOT_SCAN_BATCH_SIZE = 24
AUTOPILOT_MAX_CANDIDATES = 12
AUTOPILOT_MAX_AI_ANALYSES = 6
AUTOPILOT_SCAN_BUDGET_SECONDS = 90
AUTOPILOT_TECHNICAL_SCAN_BUDGET_SECONDS = 40
DEFAULT_AUTOPILOT_UNIVERSE = (
    {"market": "KRX", "symbol": "035720"},
    {"market": "NASDAQ", "symbol": "INTC"},
    {"market": "NYSE", "symbol": "BAC"},
    {"market": "KRX", "symbol": "030200"},
    {"market": "NASDAQ", "symbol": "AAPL"},
    {"market": "NYSE", "symbol": "TSM"},
    {"market": "KRX", "symbol": "005930"},
    {"market": "NASDAQ", "symbol": "NVDA"},
    {"market": "NYSE", "symbol": "JPM"},
    {"market": "KRX", "symbol": "000660"},
    {"market": "NASDAQ", "symbol": "AMD"},
    {"market": "NYSE", "symbol": "XOM"},
    {"market": "KRX", "symbol": "034020"},
    {"market": "NASDAQ", "symbol": "MSFT"},
    {"market": "NYSE", "symbol": "WMT"},
    {"market": "KRX", "symbol": "035420"},
    {"market": "NASDAQ", "symbol": "TSLA"},
    {"market": "NYSE", "symbol": "LLY"},
    {"market": "KRX", "symbol": "005380"},
    {"market": "NASDAQ", "symbol": "GOOGL"},
    {"market": "NYSE", "symbol": "V"},
    {"market": "KRX", "symbol": "373220"},
    {"market": "NASDAQ", "symbol": "META"},
    {"market": "NYSE", "symbol": "JNJ"},
)


def automation_universe_path(directory=None):
    return os.path.join(directory or state_directory(), "automation-universe.json")


@contextmanager
def automation_universe_lock(directory=None):
    descriptor = os.open(
        automation_universe_path(directory) + ".lock", os.O_RDWR | os.O_CREAT, 0o600,
    )
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def default_autopilot_state():
    return {
        "version": AUTOPILOT_STATE_VERSION,
        "enabled": False,
        "environment": "paper",
        "automaticSelection": True,
        "selectedKeys": [],
        "universe": [],
        "candidates": [],
        "sectorPulse": [],
        "research": {},
        "phase": "idle",
        "lastScanAt": 0,
        "lastStartedAt": 0,
        "lastStoppedAt": 0,
        "scanCursor": 0,
        "stopGeneration": 0,
        "lastError": "",
        "updatedAt": int(time.time()),
    }


def normalized_market_symbol(value):
    if not isinstance(value, dict):
        return None
    market = str(value.get("market", "")).strip().upper()
    symbol = str(value.get("symbol", "")).strip().upper()
    if market == "KRX":
        valid = bool(re.fullmatch(r"\d{6}", symbol))
    elif market in ("NASDAQ", "NYSE"):
        valid = bool(re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol))
    else:
        valid = False
    if not valid:
        return None
    return {"market": market, "symbol": symbol, "key": f"{market}:{symbol}"}


def normalized_autopilot_universe(values):
    source = list(values) if isinstance(values, list) else []
    source += profile_autopilot_universe() + list(DEFAULT_AUTOPILOT_UNIVERSE)
    result = []
    seen = set()
    for value in source:
        item = normalized_market_symbol(value)
        if not item or item["key"] in seen:
            continue
        seen.add(item["key"])
        result.append(item)
        if len(result) >= AUTOPILOT_MAX_UNIVERSE:
            break
    return result


def profile_autopilot_universe():
    grouped = {"KRX": [], "NASDAQ": [], "NYSE": []}
    for key in sorted(stock_profile_companies()):
        if ":" not in key:
            continue
        market, symbol = key.split(":", 1)
        item = normalized_market_symbol({"market": market, "symbol": symbol})
        if item:
            grouped[item["market"]].append(item)
    result = []
    for index in range(max((len(values) for values in grouped.values()), default=0)):
        for market in ("KRX", "NASDAQ", "NYSE"):
            if index < len(grouped[market]):
                result.append(grouped[market][index])
    return result


def rotating_scan_universe(universe, cursor=0, limit=AUTOPILOT_SCAN_BATCH_SIZE):
    values = list(universe or [])
    if not values:
        return [], 0
    limit = max(1, min(len(values), int(limit)))
    start = max(0, int(numeric(cursor))) % len(values)
    batch = [values[(start + offset) % len(values)] for offset in range(limit)]
    return batch, (start + limit) % len(values)


def normalized_autopilot_state(value):
    state = default_autopilot_state()
    stored_version = int(numeric(value.get("version"))) if isinstance(value, dict) else 0
    if isinstance(value, dict):
        for key in state:
            if key in value:
                state[key] = value[key]
    if stored_version < AUTOPILOT_STATE_VERSION:
        state["universe"] = (
            list(state.get("universe") or []) + profile_autopilot_universe()
        )
        state["scanCursor"] = 0
    state["version"] = AUTOPILOT_STATE_VERSION
    state["enabled"] = bool(state.get("enabled"))
    state["environment"] = "prod" if state.get("environment") == "prod" else "paper"
    state["automaticSelection"] = bool(state.get("automaticSelection", True))
    state["phase"] = str(state.get("phase", "idle"))
    state["lastError"] = str(state.get("lastError", ""))[:240]
    state["universe"] = normalized_autopilot_universe(state.get("universe"))
    state["sectorPulse"] = [
        item for item in (state.get("sectorPulse") or [])
        if isinstance(item, dict)
    ][:12]
    state["research"] = (
        dict(state.get("research"))
        if isinstance(state.get("research"), dict)
        else {}
    )
    candidates = []
    keys = set()
    for candidate in state.get("candidates", []):
        identity = normalized_market_symbol(candidate)
        if not identity or identity["key"] in keys:
            continue
        item = dict(candidate)
        item.update(identity)
        item["recommended"] = bool(item.get("recommended"))
        candidates.append(item)
        keys.add(identity["key"])
        if len(candidates) >= AUTOPILOT_MAX_CANDIDATES:
            break
    state["candidates"] = candidates
    selected = state.get("selectedKeys") if isinstance(state.get("selectedKeys"), list) else []
    state["selectedKeys"] = sorted({
        str(key) for key in selected if str(key) in keys
    })
    for key in (
        "lastScanAt", "lastStartedAt", "lastStoppedAt", "scanCursor",
        "stopGeneration", "updatedAt",
    ):
        state[key] = int(numeric(state.get(key)))
    if state["universe"]:
        state["scanCursor"] %= len(state["universe"])
    else:
        state["scanCursor"] = 0
    return state


def load_autopilot_state():
    try:
        with open(automation_universe_path(), encoding="utf-8") as handle:
            return normalized_autopilot_state(json.load(handle))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_autopilot_state()


def save_autopilot_state(value):
    state = normalized_autopilot_state(value)
    state["updatedAt"] = int(time.time())
    path = automation_universe_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return state


def candidate_company_name(market, symbol, snapshot):
    name = str(snapshot.get("name", "")).strip()
    if name and name != symbol:
        return name
    return SECURITIES.get((market, symbol), (symbol, 0, ""))[0]


def stock_profile_companies():
    try:
        with open(STOCK_PROFILE_PATH, encoding="utf-8") as handle:
            value = json.load(handle)
        companies = value.get("companies") if isinstance(value, dict) else {}
        return companies if isinstance(companies, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def candidate_sectors(market, symbol, profiles=None):
    companies = profiles if isinstance(profiles, dict) else stock_profile_companies()
    profile = companies.get(f"{market}:{symbol}", {})
    values = profile.get("sectors") if isinstance(profile, dict) else []
    return [str(value) for value in values if str(value).strip()][:8]


def candidate_price_krw(item, snapshot, price):
    if item["market"] == "KRX":
        return numeric(price)
    direct = numeric(snapshot.get("priceKrw"))
    if direct > 0:
        return direct
    exchange_rate = numeric(snapshot.get("exchangeRate"))
    return numeric(price) * exchange_rate if exchange_rate > 0 else 0


def candidate_policy_gates(candidate, policy):
    model_count = int(numeric(candidate.get("modelCount")))
    gates = (
        (
            "affordable",
            bool(candidate.get("affordable")),
            numeric(candidate.get("priceKrw")),
            numeric(policy.get("maxOrderValueKrw")),
        ),
        (
            "technical_score",
            numeric(candidate.get("technicalScore"))
            >= numeric(policy.get("minTechnicalScore")),
            numeric(candidate.get("technicalScore")),
            numeric(policy.get("minTechnicalScore")),
        ),
        ("ai_status", candidate.get("aiStatus") == "ok", candidate.get("aiStatus"), "ok"),
        (
            "news_status",
            candidate.get("newsStatus") in ("limited", "usable"),
            candidate.get("newsStatus"),
            "limited_or_usable",
        ),
        (
            "news_quality",
            numeric(candidate.get("newsQualityScore"))
            >= numeric(policy.get("minNewsQualityScore")),
            numeric(candidate.get("newsQualityScore")),
            numeric(policy.get("minNewsQualityScore")),
        ),
        (
            "verified_direct_news",
            numeric(candidate.get("verifiedDirectNews"))
            >= numeric(policy.get("minVerifiedDirectNews")),
            numeric(candidate.get("verifiedDirectNews")),
            numeric(policy.get("minVerifiedDirectNews")),
        ),
        (
            "behavior_status",
            candidate.get("behaviorStatus") in ("limited", "usable"),
            candidate.get("behaviorStatus"),
            "limited_or_usable",
        ),
        (
            "behavior_risk",
            numeric(candidate.get("behaviorRiskScore"))
            <= numeric(policy.get("maxBehaviorRiskScore")),
            numeric(candidate.get("behaviorRiskScore")),
            numeric(policy.get("maxBehaviorRiskScore")),
        ),
        ("ai_stance", candidate.get("aiStance") == "bullish", candidate.get("aiStance"), "bullish"),
        (
            "ai_confidence",
            numeric(candidate.get("aiConfidence"))
            >= numeric(policy.get("minAiConfidence")),
            numeric(candidate.get("aiConfidence")),
            numeric(policy.get("minAiConfidence")),
        ),
        (
            "ai_tail_risk",
            numeric(candidate.get("downProbability"))
            <= numeric(policy.get("maxAiDownProbability")),
            numeric(candidate.get("downProbability")),
            numeric(policy.get("maxAiDownProbability")),
        ),
        (
            "model_agreement",
            numeric(candidate.get("agreementScore"))
            >= numeric(policy.get("minAgreementScore")),
            numeric(candidate.get("agreementScore")),
            numeric(policy.get("minAgreementScore")),
        ),
        ("model_conflict", not candidate.get("directConflict"), bool(candidate.get("directConflict")), False),
        (
            "model_count",
            not policy.get("requireTwoModels") or model_count >= 2,
            model_count,
            2 if policy.get("requireTwoModels") else 1,
        ),
    )
    return [
        {"code": code, "passed": bool(passed), "value": value, "threshold": threshold}
        for code, passed, value, threshold in gates
    ]


def sector_pulse(scanned):
    grouped = {}
    for candidate in scanned:
        for sector in candidate.get("sectors") or []:
            grouped.setdefault(sector, []).append(candidate)
    result = []
    for sector, items in grouped.items():
        score = sum(numeric(item.get("technicalScore")) for item in items) / len(items)
        momentum = sum(numeric(item.get("momentum20Pct")) for item in items) / len(items)
        leaders = sorted(
            items,
            key=lambda item: (
                numeric(item.get("technicalScore")),
                numeric(item.get("momentum20Pct")),
            ),
            reverse=True,
        )[:3]
        result.append({
            "id": sector,
            "score": round(score, 1),
            "momentum20Pct": round(momentum, 2),
            "candidateCount": len(items),
            "positiveCount": sum(
                1 for item in items if numeric(item.get("technicalScore")) > 0
            ),
            "leaders": [
                {
                    "key": item["key"],
                    "name": item.get("name", item["symbol"]),
                    "symbol": item["symbol"],
                    "market": item["market"],
                }
                for item in leaders
            ],
        })
    result.sort(
        key=lambda item: (item["score"], item["momentum20Pct"], item["candidateCount"]),
        reverse=True,
    )
    return result[:10]


def technical_candidate(item, environment, language, policy=None, profiles=None):
    snapshot = kis_snapshot(item["symbol"], item["market"], "3M", environment)
    points = normalized_history_points(snapshot.get("points") or [])
    metrics = technical_screen_metrics(points)
    price = numeric(snapshot.get("price"), metrics.get("close"))
    if price <= 0 or len(points) < 60:
        raise StockServiceError("Candidate history is incomplete")
    policy = policy if isinstance(policy, dict) else load_automation_policy()
    price_krw = candidate_price_krw(item, snapshot, price)
    max_order_value = numeric(policy.get("maxOrderValueKrw"))
    return {
        "key": item["key"],
        "market": item["market"],
        "symbol": item["symbol"],
        "name": candidate_company_name(item["market"], item["symbol"], snapshot),
        "currency": str(snapshot.get("currency") or ("KRW" if item["market"] == "KRX" else "USD")),
        "price": price,
        "priceKrw": round(price_krw, 2),
        "affordable": price_krw > 0 and price_krw <= max_order_value,
        "affordabilityKnown": price_krw > 0,
        "maxOrderValueKrw": max_order_value,
        "sectors": candidate_sectors(item["market"], item["symbol"], profiles),
        "changePct": round(numeric(snapshot.get("changePct")), 2),
        "technicalScore": int(numeric(metrics.get("score"))),
        "technicalStance": str(metrics.get("stance", "neutral")),
        "momentum20Pct": round(numeric(metrics.get("momentum20Pct")), 2),
        "drawdown60Pct": round(numeric(metrics.get("drawdown60Pct")), 2),
        "volatilityPct": round(numeric(metrics.get("annualizedVolatilityPct")), 2),
        "snapshot": dict(snapshot, language=language),
    }


def analyze_candidate(candidate, provider, profile, policy=None):
    result = analyze(provider, profile, candidate.pop("snapshot"), force=False)
    agreement = result.get("ensembleAgreement") if isinstance(result.get("ensembleAgreement"), dict) else {}
    news_context = result.get("newsContext") if isinstance(result.get("newsContext"), dict) else {}
    behavior_context = result.get("behaviorContext") if isinstance(result.get("behaviorContext"), dict) else {}
    policy = policy if isinstance(policy, dict) else load_automation_policy()
    candidate.update({
        "aiStatus": str(result.get("status", "")),
        "aiStance": str(result.get("stance", "neutral")),
        "aiConfidence": int(numeric(result.get("confidence"))),
        "downProbability": int(numeric(result.get("downProbability"))),
        "agreementScore": int(numeric(agreement.get("agreementScore"))),
        "directConflict": bool(agreement.get("directConflict")),
        "modelCount": len(result.get("models") or []),
        "summary": str(result.get("summary", ""))[:260],
        "newsSignal": str(result.get("newsSignal", ""))[:180],
        "chartSignal": str(result.get("chartSignal", ""))[:180],
        "newsCount": int(numeric(result.get("newsCount"))),
        "newsStatus": str(news_context.get("status", "insufficient")),
        "newsQualityScore": int(numeric(news_context.get("qualityScore"))),
        "verifiedDirectNews": int(numeric(news_context.get("verifiedDirectCount"))),
        "behaviorStatus": str(behavior_context.get("status", "insufficient")),
        "behaviorRiskScore": int(numeric(behavior_context.get("riskPenalty"))),
        "behaviorEvidenceConfidence": int(numeric(behavior_context.get("evidenceConfidence"))),
        "analysisGeneratedAt": int(numeric(result.get("generatedAt"))),
    })
    candidate["recommendationScore"] = int(round(
        numeric(candidate.get("technicalScore"))
        + (candidate["aiConfidence"] * 0.45 if candidate["aiStance"] == "bullish" else 0)
        - candidate["downProbability"] * 0.35
        + candidate["agreementScore"] * 0.15
        + candidate["newsQualityScore"] * 0.15
        - candidate["behaviorRiskScore"] * 0.25
    ))
    candidate["eligibilityGates"] = candidate_policy_gates(candidate, policy)
    candidate["recommended"] = all(
        gate["passed"] for gate in candidate["eligibilityGates"]
    )
    return candidate


def prescreen_candidate(candidate, policy):
    candidate.pop("snapshot", None)
    candidate.update({
        "aiStatus": "prescreened",
        "aiStance": "neutral",
        "aiConfidence": 0,
        "downProbability": 0,
        "agreementScore": 0,
        "directConflict": False,
        "modelCount": 0,
        "summary": "Technical pre-screen only",
        "newsSignal": "",
        "chartSignal": "",
        "newsCount": 0,
        "newsStatus": "insufficient",
        "newsQualityScore": 0,
        "verifiedDirectNews": 0,
        "behaviorStatus": "insufficient",
        "behaviorRiskScore": 100,
        "behaviorEvidenceConfidence": 0,
        "analysisGeneratedAt": 0,
        "recommendationScore": int(numeric(candidate.get("technicalScore"))),
        "recommended": False,
    })
    candidate["eligibilityGates"] = candidate_policy_gates(candidate, policy)


def candidate_blocker_summary(candidates):
    counts = {}
    for candidate in candidates:
        for gate in candidate.get("eligibilityGates") or []:
            if gate.get("passed"):
                continue
            code = str(gate.get("code", "unknown"))
            counts[code] = counts.get(code, 0) + 1
    priority = (
        "affordable",
        "technical_score",
        "ai_status",
        "ai_stance",
        "ai_confidence",
        "news_status",
        "news_quality",
        "verified_direct_news",
        "behavior_status",
        "behavior_risk",
        "ai_tail_risk",
        "model_agreement",
        "model_conflict",
        "model_count",
    )
    primary = next((code for code in priority if counts.get(code)), "")
    return {"primary": primary, "counts": counts}


def autopilot_scan_control_snapshot():
    with automation_universe_lock():
        state = load_autopilot_state()
    return {
        "enabled": bool(state.get("enabled")),
        "environment": state.get("environment", "paper"),
        "lastScanAt": int(numeric(state.get("lastScanAt"))),
        "stopGeneration": int(numeric(state.get("stopGeneration"))),
    }, state


def autopilot_scan_control_changed(snapshot, include_scan=False):
    with automation_universe_lock():
        state = load_autopilot_state()
    changed = (
        int(numeric(state.get("stopGeneration"))) != snapshot["stopGeneration"]
        or bool(state.get("enabled")) != snapshot["enabled"]
        or state.get("environment", "paper") != snapshot["environment"]
        or (
            include_scan
            and int(numeric(state.get("lastScanAt"))) != snapshot["lastScanAt"]
        )
    )
    return changed, state


def discover_autopilot_candidates(payload=None):
    payload = payload if isinstance(payload, dict) else {}
    environment = str(payload.get("environment", "paper")).lower()
    if environment not in ("paper", "prod"):
        raise StockServiceError("AI Autopilot environment must be paper or production")
    provider = str(payload.get("aiProvider", "none")).lower()
    profile = str(payload.get("analysisProfile", "balanced")).lower()
    language = "en" if payload.get("language") == "en" else "ko"
    strategy = str(payload.get("strategy", "trend")).lower()
    if provider not in ("openai", "claude", "both"):
        raise StockServiceError("Select an AI provider before analyzing candidates")
    if profile not in ("quick", "balanced", "deep"):
        profile = "balanced"
    if strategy not in ("trend", "momentum", "mean_reversion"):
        strategy = "trend"
    universe = normalized_autopilot_universe(payload.get("universe"))
    control_snapshot, initial_state = autopilot_scan_control_snapshot()
    scan_universe, next_scan_cursor = rotating_scan_universe(
        universe,
        initial_state.get("scanCursor", 0),
    )
    scanned = []
    errors = []
    policy = load_automation_policy()
    profiles = stock_profile_companies()
    started_at = time.monotonic()
    budget_exhausted = False
    attempted_count = 0
    for item in scan_universe:
        if (
            time.monotonic() - started_at
            >= AUTOPILOT_TECHNICAL_SCAN_BUDGET_SECONDS
        ):
            budget_exhausted = True
            break
        changed, current = autopilot_scan_control_changed(control_snapshot)
        if changed:
            return autopilot_status(current)
        attempted_count += 1
        try:
            scanned.append(
                technical_candidate(
                    item,
                    environment,
                    language,
                    policy,
                    profiles,
                )
            )
        except Exception as error:
            errors.append({"key": item["key"], "message": str(error)[:160]})
    scanned.sort(
        key=lambda item: (
            numeric(item.get("technicalScore")),
            numeric(item.get("momentum20Pct")),
            -numeric(item.get("volatilityPct")),
        ),
        reverse=True,
    )
    candidates = []
    selected_keys = set()
    for market in ("KRX", "NASDAQ", "NYSE"):
        for candidate in (
            item for item in scanned if item["market"] == market
        ):
            candidates.append(candidate)
            selected_keys.add(candidate["key"])
            if sum(1 for item in candidates if item["market"] == market) >= 2:
                break
    for candidate in scanned:
        if len(candidates) >= AUTOPILOT_MAX_CANDIDATES:
            break
        if candidate["key"] in selected_keys:
            continue
        candidates.append(candidate)
        selected_keys.add(candidate["key"])
    candidates.sort(
        key=lambda item: (
            bool(item.get("affordable")),
            numeric(item.get("technicalScore")),
            numeric(item.get("momentum20Pct")),
            -numeric(item.get("volatilityPct")),
        ),
        reverse=True,
    )
    for index, candidate in enumerate(candidates):
        can_analyze = (
            index < AUTOPILOT_MAX_AI_ANALYSES
            and time.monotonic() - started_at < AUTOPILOT_SCAN_BUDGET_SECONDS
        )
        if can_analyze:
            changed, current = autopilot_scan_control_changed(control_snapshot)
            if changed:
                return autopilot_status(current)
            try:
                analyze_candidate(candidate, provider, profile, policy)
            except Exception as error:
                candidate.pop("snapshot", None)
                candidate.update({
                    "aiStatus": "error",
                    "aiStance": "neutral",
                    "aiConfidence": 0,
                    "downProbability": 100,
                    "agreementScore": 0,
                    "directConflict": False,
                    "modelCount": 0,
                    "summary": str(error)[:220],
                    "newsSignal": "",
                    "chartSignal": "",
                    "newsCount": 0,
                    "newsStatus": "insufficient",
                    "newsQualityScore": 0,
                    "verifiedDirectNews": 0,
                    "behaviorStatus": "insufficient",
                    "behaviorRiskScore": 100,
                    "behaviorEvidenceConfidence": 0,
                    "analysisGeneratedAt": 0,
                    "recommendationScore": int(numeric(candidate.get("technicalScore"))),
                    "recommended": False,
                })
                candidate["eligibilityGates"] = candidate_policy_gates(
                    candidate,
                    policy,
                )
        else:
            if index < AUTOPILOT_MAX_AI_ANALYSES:
                budget_exhausted = True
            prescreen_candidate(candidate, policy)
        candidate["aiProvider"] = provider
        candidate["analysisProfile"] = profile
        candidate["strategy"] = strategy
        candidate["language"] = language
    candidates.sort(
        key=lambda item: (
            bool(item.get("recommended")),
            numeric(item.get("recommendationScore")),
            numeric(item.get("technicalScore")),
        ),
        reverse=True,
    )
    changed, current = autopilot_scan_control_changed(
        control_snapshot,
        include_scan=True,
    )
    if changed:
        return autopilot_status(current)
    with automation_universe_lock():
        current = load_autopilot_state()
        control_changed = (
            int(numeric(current.get("stopGeneration")))
            != control_snapshot["stopGeneration"]
            or bool(current.get("enabled")) != control_snapshot["enabled"]
            or current.get("environment", "paper")
            != control_snapshot["environment"]
            or int(numeric(current.get("lastScanAt")))
            != control_snapshot["lastScanAt"]
        )
        if control_changed:
            state = current
        else:
            same_environment = current.get("environment") == environment
            current_selected = (
                set(current.get("selectedKeys") or [])
                if same_environment
                else set()
            )
            latest_policy = load_automation_policy()
            scan_failed = not candidates
            analysis_failed = (
                bool(candidates)
                and not budget_exhausted
                and not any(
                    candidate.get("aiStatus") == "ok"
                    for candidate in candidates
                )
            )
            if scan_failed and same_environment and current.get("candidates"):
                candidates = list(current["candidates"])
            valid_keys = {candidate["key"] for candidate in candidates}
            pulses = sector_pulse(scanned)
            blockers = candidate_blocker_summary(candidates)
            completed_at = int(time.time())
            retry_scan = scan_failed or analysis_failed
            state = dict(current)
            state.update({
                "environment": environment,
                "candidates": candidates,
                "universe": universe,
                "sectorPulse": pulses,
                "research": {
                    "phase": (
                        "degraded"
                        if scan_failed or analysis_failed or budget_exhausted
                        else ("watching" if not any(
                            candidate.get("recommended") for candidate in candidates
                        ) else "shortlisted")
                    ),
                    "scannedCount": len(scanned),
                    "requestedCount": len(scan_universe),
                    "universeCount": len(universe),
                    "scanCursor": (
                        (int(numeric(initial_state.get("scanCursor"))) + attempted_count)
                        % len(universe)
                        if universe else 0
                    ),
                    "analyzedCount": sum(
                        1 for candidate in candidates
                        if candidate.get("aiStatus") == "ok"
                    ),
                    "candidateCount": len(candidates),
                    "eligibleCount": sum(
                        1 for candidate in candidates
                        if candidate.get("recommended")
                    ),
                    "primaryBlocker": blockers["primary"],
                    "blockerCounts": blockers["counts"],
                    "affordableCount": sum(
                        1 for candidate in candidates
                        if candidate.get("affordable")
                    ),
                    "sectorCount": len(pulses),
                    "aiProvider": provider,
                    "analysisProfile": profile,
                    "strategy": strategy,
                    "language": language,
                    "budgetExhausted": budget_exhausted,
                    "elapsedMs": int(
                        max(0, time.monotonic() - started_at) * 1000
                    ),
                    "nextRetryAt": (
                        completed_at + AUTOPILOT_FAILED_SCAN_RETRY_SECONDS
                        if retry_scan else 0
                    ),
                },
                "selectedKeys": sorted(current_selected & valid_keys),
                "phase": (
                    "safety_halted"
                    if latest_policy.get("halted")
                    else (
                        "running"
                        if current.get("enabled")
                        else (
                            "error"
                            if scan_failed or analysis_failed
                            else ("degraded" if budget_exhausted else "ready")
                        )
                    )
                ),
                "lastScanAt": (
                    completed_at
                    - AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS
                    + AUTOPILOT_FAILED_SCAN_RETRY_SECONDS
                    if retry_scan else completed_at
                ),
                "scanCursor": (
                    (int(numeric(initial_state.get("scanCursor"))) + attempted_count)
                    % len(universe)
                    if universe else next_scan_cursor
                ),
                "lastError": (
                    "Candidate refresh failed; previous candidates are preserved"
                    if scan_failed and candidates
                    else (
                        "No tradable AI candidates were found"
                        if scan_failed
                        else (
                            "Candidate refresh reached its time budget"
                            if budget_exhausted
                            else (
                                "AI candidate analysis is unavailable"
                                if analysis_failed
                                else ""
                            )
                        )
                    )
                ),
                "scanErrors": errors[:8],
            })
            state = save_autopilot_state(state)
    return autopilot_status(state)


def configure_autopilot(payload=None):
    payload = payload if isinstance(payload, dict) else {}
    with automation_universe_lock():
        state = load_autopilot_state()
        if "automaticSelection" in payload:
            state["automaticSelection"] = bool(payload.get("automaticSelection"))
        if "selectedKeys" in payload:
            selected = payload.get("selectedKeys") if isinstance(payload.get("selectedKeys"), list) else []
            valid = {candidate["key"] for candidate in state.get("candidates", [])}
            state["selectedKeys"] = sorted({str(key) for key in selected if str(key) in valid})
        state = save_autopilot_state(state)
    return autopilot_status(state)


def autopilot_entry_keys(state=None):
    state = normalized_autopilot_state(state if isinstance(state, dict) else load_autopilot_state())
    if state.get("automaticSelection"):
        if (
            int(time.time()) - int(numeric(state.get("lastScanAt")))
            > AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS
        ):
            return set()
        return {
            candidate["key"] for candidate in state.get("candidates", [])
            if candidate.get("recommended")
        }
    return set(state.get("selectedKeys") or [])


def autopilot_targets(state=None):
    state = normalized_autopilot_state(state if isinstance(state, dict) else load_autopilot_state())
    entry_keys = autopilot_entry_keys(state)
    targets = []
    for candidate in state.get("candidates", []):
        if candidate["key"] not in entry_keys:
            continue
        targets.append({
            "id": "autopilot:" + candidate["key"],
            "sourceId": "autopilot",
            "symbol": candidate["symbol"],
            "market": candidate["market"],
            "mode": "kis",
            "environment": state.get("environment", "paper"),
            "aiProvider": candidate.get("aiProvider", "none"),
            "analysisProfile": candidate.get("analysisProfile", "balanced"),
            "strategy": candidate.get("strategy", "trend"),
            "language": candidate.get("language", "ko"),
            "allowEntry": True,
            "autopilot": True,
            "recommendationScore": int(numeric(candidate.get("recommendationScore"))),
        })
    return sorted(
        targets,
        key=lambda item: numeric(item.get("recommendationScore")),
        reverse=True,
    )


def autopilot_status(state=None):
    state = normalized_autopilot_state(state if isinstance(state, dict) else load_autopilot_state())
    entry_keys = autopilot_entry_keys(state)
    candidates = []
    for candidate in state.get("candidates", []):
        item = dict(candidate)
        item["selected"] = item["key"] in entry_keys
        candidates.append(item)
    policy = load_automation_policy()
    environment = state.get("environment", "paper")
    policy_environment = "prod" if policy.get("executionMode") == "live" else "paper"
    enabled = bool(
        state.get("enabled")
        and environment == policy_environment
        and policy.get("autopilotEnabled")
        and policy.get("enabled")
        and policy.get("schedulerEnabled")
        and policy.get("schedulerMode") == "paper_auto"
        and not policy.get("halted")
    )
    stored_phase = str(state.get("phase", "idle"))
    phase = (
        "safety_halted"
        if policy.get("halted")
        else (
            ("running" if entry_keys else "researching")
            if enabled
            else ("stopped" if stored_phase == "safety_halted" else stored_phase)
        )
    )
    return {
        "kind": "autopilot",
        "status": "ok",
        "version": AUTOPILOT_STATE_VERSION,
        "enabled": enabled,
        "environment": environment,
        "automaticSelection": bool(state.get("automaticSelection")),
        "selectedKeys": sorted(entry_keys),
        "selectedCount": len(entry_keys),
        "candidates": candidates,
        "universe": list(state.get("universe") or []),
        "sectorPulse": list(state.get("sectorPulse") or []),
        "research": dict(state.get("research") or {}),
        "phase": phase,
        "lastScanAt": int(numeric(state.get("lastScanAt"))),
        "lastStartedAt": int(numeric(state.get("lastStartedAt"))),
        "lastStoppedAt": int(numeric(state.get("lastStoppedAt"))),
        "lastError": str(state.get("lastError", "")),
        "haltReason": str(policy.get("haltReason", "")),
        "haltClass": str(policy.get("haltClass", "")),
        "haltedAt": int(numeric(policy.get("haltedAt"))),
        "haltIncidentId": str(policy.get("haltIncidentId", "")),
        "scanErrors": list(state.get("scanErrors") or []),
        "candidateMaxAgeSeconds": AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS,
        "paperOnly": environment != "prod",
        "noLossGuaranteed": False,
        "updatedAt": int(time.time()),
    }


def start_autopilot(payload=None):
    payload = payload if isinstance(payload, dict) else {}
    environment = str(payload.get("environment", "paper")).lower()
    if environment not in ("paper", "prod"):
        raise StockServiceError("AI Autopilot environment must be paper or production")
    required_confirmation = (
        "START KIS LIVE AUTOPILOT" if environment == "prod"
        else "START KIS PAPER AUTOPILOT"
    )
    if str(payload.get("confirmation", "")) != required_confirmation:
        raise StockServiceError("Starting AI Autopilot requires exact environment confirmation")
    policy = load_automation_policy()
    if policy.get("halted") and policy.get("haltClass") != "manual":
        raise StockServiceError(
            "The safety kill switch is engaged; reset it in Advanced Safety before restarting",
        )
    if environment == "prod":
        if not policy.get("liveConsent"):
            raise StockServiceError("Accept the live automation risk consent in Settings first")
        from .core import load_risk_policy
        if not load_risk_policy().get("productionEnabled"):
            raise StockServiceError("Unlock production trading in Settings first")
        from .automation_live import automation_live_status
        from .automation_scheduler import load_automation_scheduler_runtime
        failures = int(numeric(load_automation_scheduler_runtime().get("consecutiveFailures")))
        if not automation_live_status(failures).get("productionAutomationEligible"):
            raise StockServiceError(
                "Live automation is locked until every live-readiness gate passes",
            )
    state = load_autopilot_state()
    automatic_selection = bool(payload.get("automaticSelection", True))
    state = dict(state, automaticSelection=automatic_selection)
    stop_generation = int(numeric(state.get("stopGeneration")))
    if not state.get("candidates") and not state.get("automaticSelection"):
        raise StockServiceError(
            "Manual candidate selection requires a completed candidate scan",
        )
    if state.get("lastError") and not state.get("automaticSelection"):
        raise StockServiceError(str(state["lastError"]))
    if not autopilot_entry_keys(state) and not state.get("automaticSelection"):
        raise StockServiceError(
            "Manual candidate selection requires at least one selected stock",
        )
    from .automation_execution import automation_audit_status
    audit = automation_audit_status()
    if not audit.get("healthy"):
        raise StockServiceError("Automation audit integrity must be repaired before AI Autopilot can start")
    with automation_lock():
        with automation_universe_lock():
            policy = load_automation_policy()
            state = load_autopilot_state()
            if policy.get("halted") and policy.get("haltClass") == "manual":
                policy.update({
                    "halted": False,
                    "haltReason": "",
                    "haltClass": "",
                    "haltedAt": 0,
                    "haltIncidentId": "",
                    "exitOnlyProtection": False,
                })
            if policy.get("halted") or int(numeric(
                state.get("stopGeneration"),
            )) != stop_generation:
                raise StockServiceError(
                    "AI Autopilot was stopped while startup was in progress",
                )
            if environment == "prod":
                if not policy.get("liveConsent"):
                    raise StockServiceError("Live automation consent was revoked during startup")
                from .core import load_risk_policy
                if not load_risk_policy().get("productionEnabled"):
                    raise StockServiceError("Production trading was locked during startup")
                from .automation_live import automation_live_status
                from .automation_scheduler import load_automation_scheduler_runtime
                failures = int(numeric(load_automation_scheduler_runtime().get("consecutiveFailures")))
                if not automation_live_status(failures).get("productionAutomationEligible"):
                    raise StockServiceError("Live-readiness was revoked during startup")
            policy.update({
                "enabled": True,
                "halted": False,
                "haltReason": "",
                "haltClass": "",
                "haltedAt": 0,
                "haltIncidentId": "",
                "exitOnlyProtection": False,
                "executionMode": "live" if environment == "prod" else "paper",
                "paperOnly": environment != "prod",
                "schedulerEnabled": True,
                "schedulerMode": "paper_auto",
                "autopilotEnabled": True,
            })
            policy = (
                open_live_auto_session(policy)
                if environment == "prod"
                else clear_live_auto_session(policy)
            )
            save_automation_policy(policy)
            environment_changed = state.get("environment") != environment
            research = (
                dict(state.get("research"))
                if isinstance(state.get("research"), dict)
                else {}
            )
            research.update({
                "aiProvider": str(payload.get("aiProvider", "none")).lower(),
                "analysisProfile": str(
                    payload.get("analysisProfile", "balanced"),
                ).lower(),
                "strategy": str(
                    payload.get("strategy", "trend"),
                ).lower(),
                "language": (
                    "en" if payload.get("language") == "en" else "ko"
                ),
                "phase": "researching",
            })
            state.update({
                "enabled": True,
                "environment": environment,
                "automaticSelection": automatic_selection,
                "candidates": (
                    [] if environment_changed
                    else state.get("candidates", [])
                ),
                "selectedKeys": (
                    [] if environment_changed
                    else state.get("selectedKeys", [])
                ),
                "lastScanAt": (
                    0 if environment_changed
                    else int(numeric(state.get("lastScanAt")))
                ),
                "research": research,
                "phase": "researching",
                "lastStartedAt": int(time.time()),
                "lastError": "",
            })
            if autopilot_entry_keys(state):
                state["phase"] = "running"
            state = save_autopilot_state(state)
    return autopilot_status(state)


def stop_autopilot(payload=None, emergency=False):
    payload = payload if isinstance(payload, dict) else {}
    with automation_lock():
        with automation_universe_lock():
            state = load_autopilot_state()
            environment = state.get("environment", "paper")
            required = (
                "EMERGENCY STOP AI AUTOPILOT"
                if emergency
                else ("STOP KIS LIVE AUTOPILOT" if environment == "prod"
                      else "STOP KIS PAPER AUTOPILOT")
            )
            if str(payload.get("confirmation", "")) != required:
                raise StockServiceError("Stopping AI Autopilot requires exact confirmation")
            policy = load_automation_policy()
            policy.update({
                "enabled": False,
                "schedulerEnabled": False,
                "schedulerMode": "observe",
                "autopilotEnabled": False,
                "exitOnlyProtection": False,
            })
            clear_live_auto_session(policy)
            if emergency:
                policy["halted"] = True
                policy["haltReason"] = "Manual AI Autopilot emergency stop"
                policy["haltClass"] = "manual"
                policy["haltedAt"] = int(time.time())
                policy["haltIncidentId"] = os.urandom(8).hex()
            else:
                policy["haltReason"] = ""
                policy["haltClass"] = ""
                policy["haltedAt"] = 0
                policy["haltIncidentId"] = ""
            save_automation_policy(policy)
            state.update({
                "enabled": False,
                "phase": "safety_halted" if emergency else "stopped",
                "lastStoppedAt": int(time.time()),
                "stopGeneration": int(numeric(state.get("stopGeneration"))) + 1,
            })
            state = save_autopilot_state(state)
    return autopilot_status(state)
