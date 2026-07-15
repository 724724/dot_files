from .ai_models import *
from .ai_usage import ai_usage_summary, ai_usage_totals, append_ai_usage

def forecast_journal_path():
    return os.path.join(state_directory(), "forecasts.json")


def load_forecasts():
    try:
        with open(forecast_journal_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, list) else []
    except (OSError, ValueError, json.JSONDecodeError):
        return []


def save_forecasts(items):
    path = forecast_journal_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(items[:200], handle, ensure_ascii=False, separators=(",", ":"))
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def add_trading_days(timestamp, count):
    value = datetime.fromtimestamp(timestamp)
    remaining = count
    while remaining > 0:
        value += timedelta(days=1)
        if value.weekday() < 5:
            remaining -= 1
    return int(value.timestamp())


def outcome_for_return(return_pct):
    if return_pct > 1:
        return "up"
    if return_pct < -1:
        return "down"
    return "flat"


def record_forecast(result, snapshot):
    generated_at = int(result.get("generatedAt") or time.time())
    symbol = str(snapshot.get("symbol", "")).strip().upper()
    market = str(snapshot.get("market", "KRX")).strip().upper()
    entry_price = numeric(snapshot.get("price"))
    if not symbol or entry_price <= 0:
        raise StockServiceError("Forecast tracking requires a valid quote")
    identity = ":".join([
        market,
        symbol,
        str(generated_at),
        str(result.get("provider", "")),
        ",".join(result.get("models") or []),
    ])
    forecast_id = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:20]
    items = load_forecasts()
    for item in items:
        if item.get("id") == forecast_id:
            return {"id": forecast_id, "status": item.get("status", "open"), "targetAt": item.get("targetAt")}
    item = {
        "id": forecast_id,
        "symbol": symbol,
        "market": market,
        "name": str(snapshot.get("name") or symbol),
        "currency": str(snapshot.get("currency") or ("KRW" if market == "KRX" else "USD")),
        "provider": str(result.get("provider", "")),
        "profile": str(result.get("profile", "")),
        "models": list(result.get("models") or []),
        "stance": str(result.get("stance", "neutral")),
        "rawConfidence": int(numeric(result.get("rawConfidence", result.get("confidence")))),
        "confidence": int(numeric(result.get("confidence"))),
        "upProbability": int(numeric(result.get("upProbability"))),
        "flatProbability": int(numeric(result.get("flatProbability"))),
        "downProbability": int(numeric(result.get("downProbability"))),
        "chartStance": str(result.get("chartStance", "neutral")),
        "chartConfidence": int(numeric(result.get("chartConfidence"))),
        "chartSignal": str(result.get("chartSignal", ""))[:500],
        "newsStance": str(result.get("newsStance", "neutral")),
        "newsConfidence": int(numeric(result.get("newsConfidence"))),
        "newsSignal": str(result.get("newsSignal", ""))[:500],
        "newsContext": dict(result.get("newsContext") or {}),
        "modelPredictions": list(result.get("modelPredictions") or []),
        "modelWeighting": dict(result.get("modelWeighting") or {}),
        "providerStatus": dict(result.get("providerStatus") or {}),
        "ensembleAgreement": dict(result.get("ensembleAgreement") or {}),
        "calibrationAdjustment": dict(result.get("calibrationAdjustment") or {}),
        "qualityStatus": (
            "qualified"
            if int(numeric(result.get("confidence"))) >= AI_CONFIDENCE_FLOOR
            else "low_confidence"
        ),
        "summary": str(result.get("summary", ""))[:500],
        "entryPrice": entry_price,
        "lastPrice": entry_price,
        "currentReturnPct": 0,
        "generatedAt": generated_at,
        "targetAt": add_trading_days(generated_at, 5),
        "status": "open",
    }
    items.insert(0, item)
    save_forecasts(items)
    return {"id": forecast_id, "status": "open", "targetAt": item["targetAt"]}


def forecast_statistics(items):
    resolved = [item for item in items if item.get("status") == "resolved"]
    qualified = [item for item in resolved if numeric(item.get("confidence")) >= AI_CONFIDENCE_FLOOR]
    correct = sum(1 for item in resolved if item.get("correct") is True)
    brier_values = []
    for item in resolved:
        outcome = item.get("outcome")
        actual = [1 if outcome == name else 0 for name in ("up", "flat", "down")]
        predicted = [numeric(item.get(key)) / 100 for key in ("upProbability", "flatProbability", "downProbability")]
        brier_values.append(sum((value - actual[index]) ** 2 for index, value in enumerate(predicted)))
    return {
        "total": len(items),
        "open": sum(1 for item in items if item.get("status") == "open"),
        "resolved": len(resolved),
        "correct": correct,
        "hitRate": round(correct / len(resolved) * 100, 1) if resolved else 0,
        "brierScore": round(sum(brier_values) / len(brier_values), 3) if brier_values else 0,
        "qualifiedResolved": len(qualified),
        "qualifiedHitRate": (
            round(
                sum(1 for item in qualified if item.get("correct") is True)
                / len(qualified)
                * 100,
                1,
            )
            if qualified
            else 0
        ),
        "lowConfidence": sum(1 for item in items if numeric(item.get("confidence")) < AI_CONFIDENCE_FLOOR),
    }


def expected_outcome(stance):
    return {"bullish": "up", "bearish": "down", "neutral": "flat"}.get(stance, "flat")


def prediction_brier(prediction, outcome):
    actual = [1 if outcome == name else 0 for name in ("up", "flat", "down")]
    predicted = [numeric(prediction.get(key)) / 100 for key in ("upProbability", "flatProbability", "downProbability")]
    return sum((value - actual[index]) ** 2 for index, value in enumerate(predicted))


def forecast_prediction_records(items):
    records = []
    for item in items:
        if item.get("status") != "resolved" or item.get("outcome") not in ("up", "flat", "down"):
            continue
        predictions = item.get("modelPredictions") if isinstance(item.get("modelPredictions"), list) else []
        if not predictions:
            predictions = [{
                "provider": item.get("provider", "combined"),
                "model": " + ".join(item.get("models") or []) or item.get("provider", "Combined"),
                "stance": item.get("stance", "neutral"),
                "confidence": item.get("confidence", 0),
                "upProbability": item.get("upProbability", 0),
                "flatProbability": item.get("flatProbability", 0),
                "downProbability": item.get("downProbability", 0),
                "chartStance": item.get("chartStance"),
                "chartConfidence": item.get("chartConfidence", 0),
                "newsStance": item.get("newsStance"),
                "newsConfidence": item.get("newsConfidence", 0),
            }]
        for prediction in predictions:
            record = dict(prediction)
            record.update({
                "profile": item.get("profile", ""),
                "symbol": item.get("symbol", ""),
                "outcome": item.get("outcome"),
                "generatedAt": item.get("generatedAt", 0),
            })
            record["correct"] = expected_outcome(record.get("stance")) == record["outcome"]
            record["brier"] = prediction_brier(record, record["outcome"])
            records.append(record)
    return records


def prediction_metrics(records, threshold):
    qualified = [record for record in records if numeric(record.get("confidence")) >= threshold]
    calibration_gap = 0
    if records:
        average_confidence = sum(numeric(record.get("confidence")) for record in records) / len(records)
        accuracy = sum(1 for record in records if record["correct"]) / len(records) * 100
        calibration_gap = abs(average_confidence - accuracy)
    return {
        "samples": len(records),
        "qualified": len(qualified),
        "excluded": len(records) - len(qualified),
        "hitRate": round(sum(1 for record in records if record["correct"]) / len(records) * 100, 1) if records else 0,
        "qualifiedHitRate": (
            round(
                sum(1 for record in qualified if record["correct"])
                / len(qualified)
                * 100,
                1,
            )
            if qualified
            else 0
        ),
        "brierScore": round(sum(record["brier"] for record in records) / len(records), 3) if records else 0,
        "qualifiedBrierScore": (
            round(sum(record["brier"] for record in qualified) / len(qualified), 3)
            if qualified
            else 0
        ),
        "averageConfidence": (
            round(
                sum(numeric(record.get("confidence")) for record in records)
                / len(records),
                1,
            )
            if records
            else 0
        ),
        "calibrationGap": round(calibration_gap, 1),
        "dataStatus": "usable" if len(qualified) >= 5 else ("limited" if qualified else "insufficient"),
    }


def component_signal_metrics(records, stance_key, confidence_key, threshold):
    available = [record for record in records if record.get(stance_key) in ("bullish", "neutral", "bearish")]
    qualified = [record for record in available if numeric(record.get(confidence_key)) >= threshold]
    return {
        "samples": len(available),
        "qualified": len(qualified),
        "coverage": round(len(available) / len(records) * 100, 1) if records else 0,
        "qualifiedCoverage": round(len(qualified) / len(records) * 100, 1) if records else 0,
        "hitRate": (
            round(
                sum(
                    1
                    for record in qualified
                    if expected_outcome(record.get(stance_key)) == record["outcome"]
                )
                / len(qualified)
                * 100,
                1,
            )
            if qualified
            else 0
        ),
        "averageConfidence": (
            round(
                sum(numeric(record.get(confidence_key)) for record in available)
                / len(available),
                1,
            )
            if available
            else 0
        ),
        "dataStatus": "usable" if len(qualified) >= 5 else ("limited" if qualified else "insufficient"),
    }


def historical_model_weighting(model_predictions, profile, symbol, items=None):
    records = forecast_prediction_records(load_forecasts() if items is None else items)
    details = []
    for prediction in model_predictions:
        provider = str(prediction.get("provider", ""))
        model = str(prediction.get("model", ""))
        matching = [
            record
            for record in records
            if str(record.get("provider", "")) == provider
            and str(record.get("model", "")) == model
            and str(record.get("profile", "")) == str(profile)
            and str(record.get("symbol", "")).upper() == str(symbol).upper()
        ]
        metrics = prediction_metrics(matching, AI_CONFIDENCE_FLOOR)
        qualified = metrics["qualified"]
        if qualified >= 5:
            hit_quality = metrics["qualifiedHitRate"] / 100
            brier_quality = max(0, 1 - metrics["qualifiedBrierScore"] / 2)
            calibration_quality = max(0, 1 - metrics["calibrationGap"] / 50)
            quality = hit_quality * 0.5 + brier_quality * 0.3 + calibration_quality * 0.2
            target_weight = 0.7 + quality * 0.6
            sample_reliability = min(1, qualified / 20)
            raw_weight = 1 + (target_weight - 1) * sample_reliability
            status = "weighted"
        else:
            raw_weight = 1.0
            status = "limited" if qualified else "insufficient"
        details.append({
            "provider": provider,
            "model": model,
            "samples": metrics["samples"],
            "qualified": qualified,
            "qualifiedHitRate": metrics["qualifiedHitRate"],
            "qualifiedBrierScore": metrics["qualifiedBrierScore"],
            "calibrationGap": metrics["calibrationGap"],
            "rawWeight": raw_weight,
            "status": status,
        })

    total_raw_weight = sum(detail["rawWeight"] for detail in details) or 1
    model_count = len(details)
    for detail in details:
        detail["weight"] = round(detail["rawWeight"] * model_count / total_raw_weight, 3)
        detail["share"] = round(detail["rawWeight"] / total_raw_weight * 100, 1)
        detail.pop("rawWeight", None)

    usable = sum(1 for detail in details if detail["status"] == "weighted")
    spread = (
        max(detail["weight"] for detail in details) - min(detail["weight"] for detail in details)
        if len(details) > 1
        else 0
    )
    if len(details) < 2:
        status = "single_model"
        message = "Historical weighting requires more than one provider"
    elif usable and spread >= 0.01:
        status = "applied"
        message = "Resolved out-of-sample performance adjusted the ensemble"
    elif usable:
        status = "equal"
        message = "Historical performance supports equal model weights"
    elif any(detail["qualified"] for detail in details):
        status = "limited"
        message = "At least 5 qualified predictions per model are required"
    else:
        status = "insufficient"
        message = "No resolved qualified predictions are available for these models"
    return {
        "status": status,
        "scope": "same_symbol_model_profile",
        "minimumSamplesPerModel": 5,
        "models": details,
        "message": message,
    }


def apply_historical_calibration(result, model_predictions, profile, symbol, items=None):
    calibrated = dict(result)
    raw_confidence = int(max(0, min(100, numeric(result.get("confidence")))))
    calibrated["rawConfidence"] = raw_confidence
    pairs = {
        (str(prediction.get("provider", "")), str(prediction.get("model", "")))
        for prediction in model_predictions
    }
    records = forecast_prediction_records(load_forecasts() if items is None else items)
    matching = [
        record
        for record in records
        if (str(record.get("provider", "")), str(record.get("model", ""))) in pairs
        and str(record.get("profile", "")) == str(profile)
        and str(record.get("symbol", "")).upper() == str(symbol).upper()
    ]
    metrics = prediction_metrics(matching, AI_CONFIDENCE_FLOOR)
    qualified = [
        record
        for record in matching
        if numeric(record.get("confidence")) >= AI_CONFIDENCE_FLOOR
    ]
    adjustment = {
        "status": "insufficient",
        "scope": "same_symbol_model_profile",
        "minimumSamples": 5,
        "samples": metrics["samples"],
        "qualified": metrics["qualified"],
        "rawConfidence": raw_confidence,
        "adjustedConfidence": raw_confidence,
        "qualifiedHitRate": metrics["qualifiedHitRate"],
        "qualifiedBrierScore": metrics["qualifiedBrierScore"],
        "weight": 0,
        "message": "At least 5 resolved qualified predictions are required",
    }
    if len(qualified) < 5 or raw_confidence <= 0:
        calibrated["calibrationAdjustment"] = adjustment
        return calibrated

    hit_rate = sum(1 for record in qualified if record["correct"]) / len(qualified) * 100
    brier_score = sum(record["brier"] for record in qualified) / len(qualified)
    brier_penalty = max(0, brier_score - 2 / 3) * 20
    empirical_target = max(0, hit_rate - brier_penalty)
    weight = min(0.5, len(qualified) / 30)
    blended = raw_confidence * (1 - weight) + empirical_target * weight
    adjusted_confidence = min(raw_confidence, int(round(blended)))

    if adjusted_confidence < raw_confidence:
        shrink = adjusted_confidence / raw_confidence
        for key in ("upProbability", "flatProbability", "downProbability"):
            probability = numeric(calibrated.get(key), 100 / 3)
            calibrated[key] = 100 / 3 + (probability - 100 / 3) * shrink
        calibrated["confidence"] = adjusted_confidence
        calibrated = normalize_probabilities(calibrated)
        status = "applied"
        message = "Confidence was capped using resolved out-of-sample performance"
    else:
        calibrated["confidence"] = raw_confidence
        status = "validated"
        message = "Historical performance did not require a confidence reduction"

    calibrated["rawConfidence"] = raw_confidence
    calibrated["calibrationAdjustment"] = {
        "status": status,
        "scope": "same_symbol_model_profile",
        "minimumSamples": 5,
        "samples": len(matching),
        "qualified": len(qualified),
        "rawConfidence": raw_confidence,
        "adjustedConfidence": adjusted_confidence,
        "qualifiedHitRate": round(hit_rate, 1),
        "qualifiedBrierScore": round(brier_score, 3),
        "weight": round(weight, 3),
        "message": message,
    }
    return calibrated


def ai_validation(symbol="", threshold=AI_CONFIDENCE_FLOOR, limit=200):
    symbol = str(symbol).strip().upper()
    threshold = max(0, min(100, int(numeric(threshold, AI_CONFIDENCE_FLOOR))))
    limit = max(1, min(200, int(numeric(limit, 200))))
    items = load_forecasts()
    if symbol:
        items = [item for item in items if item.get("symbol") == symbol]
    resolved = [item for item in items if item.get("status") == "resolved"][:limit]
    records = forecast_prediction_records(resolved)
    overall = prediction_metrics(records, threshold)
    groups = {}
    for record in records:
        key = (
            str(record.get("provider", "combined")),
            str(record.get("model", "Unknown")),
            str(record.get("profile", "")),
        )
        groups.setdefault(key, []).append(record)
    models = []
    for (provider, model, profile), group_records in groups.items():
        metrics = prediction_metrics(group_records, threshold)
        quality_score = round(max(0, min(100,
            metrics["qualifiedHitRate"] * 0.55
            + max(0, 1 - metrics["qualifiedBrierScore"] / 2) * 25
            + max(0, 1 - metrics["calibrationGap"] / 50) * 20
        ))) if metrics["qualified"] else 0
        models.append(dict({
            "provider": provider,
            "model": model,
            "profile": profile,
            "qualityScore": quality_score,
        }, **metrics))
    models.sort(
        key=lambda value: (
            value["dataStatus"] == "usable",
            value["qualityScore"],
            value["qualified"],
        ),
        reverse=True,
    )
    buckets = []
    for label, low, high in (("0–49", 0, 49), ("50–69", 50, 69), ("70–100", 70, 100)):
        bucket = [record for record in records if low <= numeric(record.get("confidence")) <= high]
        accuracy = sum(1 for record in bucket if record["correct"]) / len(bucket) * 100 if bucket else 0
        average = sum(numeric(record.get("confidence")) for record in bucket) / len(bucket) if bucket else 0
        buckets.append({
            "label": label,
            "samples": len(bucket),
            "averageConfidence": round(average, 1),
            "accuracy": round(accuracy, 1),
            "gap": round(abs(average - accuracy), 1) if bucket else 0,
        })
    ece = sum(bucket["gap"] * bucket["samples"] for bucket in buckets) / len(records) if records else 0
    return {
        "status": "ok",
        "symbol": symbol,
        "threshold": threshold,
        "resolvedForecasts": len(resolved),
        "summary": dict(overall, expectedCalibrationError=round(ece, 1)),
        "models": models,
        "calibration": buckets,
        "signals": {
            "chart": component_signal_metrics(records, "chartStance", "chartConfidence", threshold),
            "news": component_signal_metrics(records, "newsStance", "newsConfidence", threshold),
        },
        "methodology": (
            "Predictions below the selected confidence floor are excluded from qualified metrics. "
            "Chart and news figures measure directional agreement, not causal contribution."
        ),
        "disclaimer": "Small samples are marked limited. Validation is descriptive and does not authorize an order.",
    }


def forecast_history(symbol="", limit=50):
    symbol = str(symbol).strip().upper()
    try:
        limit = max(1, min(200, int(limit)))
    except (TypeError, ValueError):
        limit = 50
    items = load_forecasts()
    if symbol:
        items = [item for item in items if item.get("symbol") == symbol]
    items.sort(key=lambda item: int(item.get("generatedAt", 0)), reverse=True)
    return {"status": "ok", "symbol": symbol, "items": items[:limit], "stats": forecast_statistics(items)}


def evaluate_forecasts(quote):
    if not isinstance(quote, dict):
        raise StockServiceError("Forecast evaluation requires a quote")
    symbol = str(quote.get("symbol", "")).strip().upper()
    market = str(quote.get("market", "KRX")).strip().upper()
    price = numeric(quote.get("price"))
    if not symbol or price <= 0:
        raise StockServiceError("Forecast evaluation requires a valid quote")
    now = int(time.time())
    items = load_forecasts()
    changed = False
    for item in items:
        if item.get("symbol") != symbol or item.get("market") != market or item.get("status") != "open":
            continue
        entry_price = numeric(item.get("entryPrice"))
        if entry_price <= 0:
            continue
        return_pct = round((price / entry_price - 1) * 100, 2)
        item["lastPrice"] = price
        item["lastObservedAt"] = now
        item["currentReturnPct"] = return_pct
        changed = True
        if now >= int(item.get("targetAt", 0)):
            outcome = outcome_for_return(return_pct)
            expected = {"bullish": "up", "bearish": "down", "neutral": "flat"}.get(item.get("stance"), "flat")
            item.update({
                "status": "resolved",
                "resolvedAt": now,
                "returnPct": return_pct,
                "outcome": outcome,
                "correct": outcome == expected,
            })
    if changed:
        save_forecasts(items)
    return forecast_history(symbol)


def delete_forecast(forecast_id):
    items = load_forecasts()
    target = next((item for item in items if item.get("id") == forecast_id), None)
    if not target:
        raise StockServiceError("Forecast record was not found")
    save_forecasts([item for item in items if item.get("id") != forecast_id])
    return forecast_history(target.get("symbol", ""))


def ai_provider_failure(provider, error, stage="analysis"):
    message = str(error).strip() or "Unknown provider error"
    lowered = message.lower()
    if "quota" in lowered or "billing" in lowered or "credit" in lowered:
        code = "quota"
        retryable = False
    elif "rate limit" in lowered or "too many request" in lowered:
        code = "rate_limit"
        retryable = True
    elif "api key" in lowered or "authentication" in lowered or "unauthorized" in lowered:
        code = "authentication"
        retryable = False
    elif "timed out" in lowered or "timeout" in lowered:
        code = "timeout"
        retryable = True
    elif "reach the remote api" in lowered or "unavailable" in lowered:
        code = "unavailable"
        retryable = True
    elif isinstance(error, json.JSONDecodeError) or "structured analysis" in lowered:
        code = "invalid_response"
        retryable = True
    else:
        code = "provider_error"
        retryable = False
    return {
        "provider": provider,
        "stage": stage,
        "code": code,
        "message": message,
        "retryable": retryable,
    }


def analyze(provider, profile, snapshot, force=False):
    if provider not in ("openai", "claude", "both"):
        raise StockServiceError("Select OpenAI, Claude, or Both")
    if profile not in MODEL_ROLE_HINTS["openai"]:
        raise StockServiceError("Select Quick, Balanced, or Deep")
    profile_models, catalog = resolve_profile_models(provider, profile)
    requested = ("openai", "claude") if provider == "both" else (provider,)
    available = [name for name in requested if profile_models.get(name)]
    model_ids = [profile_models[name]["id"] for name in available]
    if not force:
        cached = load_analysis_cache(provider, profile, snapshot, model_ids)
        if cached:
            return cached
    name = snapshot.get("name") or snapshot.get("symbol") or "Stock"
    symbol = snapshot.get("symbol") or ""
    market = snapshot.get("market") or "KRX"
    news = fetch_news(name, symbol, market)
    news_context = news_evidence_context(news)
    history, analysis_context = analysis_history_context(snapshot)
    historical_snapshot = dict(snapshot, points=history)
    features = chart_features(historical_snapshot)
    evidence = walk_forward_evidence(historical_snapshot)
    prompt = analysis_prompt(
        snapshot,
        features,
        evidence,
        news,
        analysis_context,
        news_context,
    )
    results = []
    models = []
    model_predictions = []
    analysis_usage = []
    provider_failures = []
    for name in requested:
        selected_model = profile_models.get(name)
        if not selected_model:
            message = catalog["providers"].get(name, {}).get("message") or "No compatible model is available"
            provider_failures.append(ai_provider_failure(name, StockServiceError(message), "catalog"))
            continue
        try:
            result, model, usage = (
                call_openai(prompt, selected_model["id"])
                if name == "openai"
                else call_claude(prompt, selected_model["id"])
            )
            try:
                usage_event = append_ai_usage(name, model, profile, symbol, usage)
                if usage_event:
                    analysis_usage.append(usage_event)
            except OSError:
                pass
            result = normalize_probabilities(result)
            results.append(result)
            models.append(model)
            model_predictions.append(dict({"provider": name, "model": model}, **{
                key: result.get(key) for key in (
                    "stance", "confidence", "upProbability", "flatProbability", "downProbability",
                    "chartStance", "chartConfidence", "newsStance", "newsConfidence",
                )
            }))
        except (StockServiceError, json.JSONDecodeError) as error:
            if provider != "both":
                raise StockServiceError(str(error)) from error
            provider_failures.append(ai_provider_failure(name, error))
    if not results:
        detail = " · ".join(
            failure["provider"].title() + ": " + failure["message"]
            for failure in provider_failures
        )
        raise StockServiceError("All selected AI providers failed" + (" · " + detail if detail else ""))

    effective_providers = [prediction["provider"] for prediction in model_predictions]
    provider_status = {
        "requested": list(requested),
        "effective": effective_providers,
        "degraded": bool(provider_failures),
        "failures": provider_failures,
    }
    forecast_items = load_forecasts()
    model_weighting = historical_model_weighting(
        model_predictions,
        profile,
        symbol,
        forecast_items,
    )
    for prediction, detail in zip(model_predictions, model_weighting["models"]):
        prediction["ensembleWeight"] = detail["weight"]
        prediction["ensembleShare"] = detail["share"]
    merged = consensus_result(
        results,
        [detail["weight"] for detail in model_weighting["models"]],
    )
    merged["modelWeighting"] = model_weighting
    merged = apply_historical_calibration(
        merged,
        model_predictions,
        profile,
        symbol,
        forecast_items,
    )
    qualified = int(numeric(merged.get("confidence"))) >= AI_CONFIDENCE_FLOOR
    merged.update({
        "status": "ok",
        "provider": provider,
        "providerStatus": provider_status,
        "profile": profile,
        "models": models,
        "modelPredictions": model_predictions,
        "analysisUsage": dict(ai_usage_totals(analysis_usage), items=analysis_usage),
        "modelCatalog": model_catalog_summary(catalog),
        "newsCount": len(news),
        "newsContext": news_context,
        "news": news[:5],
        "features": features,
        "evidence": evidence,
        "analysisContext": analysis_context,
        "generatedAt": int(time.time()),
        "cached": False,
        "cacheTtlSeconds": ANALYSIS_CACHE_SECONDS,
        "qualityGate": {
            "threshold": AI_CONFIDENCE_FLOOR,
            "status": "provider_degraded" if provider_failures else (
                "qualified" if qualified else "low_confidence"
            ),
            "confidenceStatus": "qualified" if qualified else "low_confidence",
            "message": (
                (
                    "One or more selected providers were unavailable; confidence remains qualified"
                    if qualified
                    else "One or more selected providers were unavailable; confidence is below the quality floor"
                )
                if provider_failures
                else "Included in qualified scorecards"
                if qualified
                else "Excluded from qualified scorecards until confidence improves"
            ),
        },
        "disclaimer": "AI 시나리오이며 투자 조언이나 주문 신호가 아닙니다.",
    })
    try:
        merged["forecast"] = record_forecast(merged, snapshot)
    except (OSError, StockServiceError) as error:
        merged["forecast"] = {"status": "unavailable", "message": str(error)}
    save_analysis_cache(provider, profile, snapshot, model_ids, merged)
    return merged
