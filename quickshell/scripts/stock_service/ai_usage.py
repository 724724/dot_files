import hashlib
import json
import os
import time
from collections import deque
from datetime import datetime

from .core import numeric, state_directory


AI_USAGE_READ_LIMIT = 5000


def ai_usage_path():
    return os.path.join(state_directory(), "ai-usage.jsonl")


def normalize_ai_usage(provider, usage):
    usage = usage if isinstance(usage, dict) else {}
    if provider == "openai":
        input_tokens = int(numeric(usage.get("input_tokens")))
        output_tokens = int(numeric(usage.get("output_tokens")))
        input_details = usage.get("input_tokens_details") or {}
        output_details = usage.get("output_tokens_details") or {}
        cached_tokens = int(numeric(input_details.get("cached_tokens")))
        cache_write_tokens = int(numeric(input_details.get("cache_write_tokens")))
        reasoning_tokens = int(numeric(output_details.get("reasoning_tokens")))
        billable_input_tokens = input_tokens
    else:
        input_tokens = int(numeric(usage.get("input_tokens")))
        output_tokens = int(numeric(usage.get("output_tokens")))
        cached_tokens = int(numeric(usage.get("cache_read_input_tokens")))
        cache_write_tokens = int(numeric(usage.get("cache_creation_input_tokens")))
        reasoning_tokens = int(numeric(usage.get("thinking_tokens")))
        billable_input_tokens = input_tokens + cached_tokens + cache_write_tokens
    total_tokens = max(
        int(numeric(usage.get("total_tokens"))),
        billable_input_tokens + output_tokens,
    )
    return {
        "inputTokens": input_tokens,
        "billableInputTokens": billable_input_tokens,
        "outputTokens": output_tokens,
        "totalTokens": total_tokens,
        "cachedInputTokens": cached_tokens,
        "cacheWriteTokens": cache_write_tokens,
        "reasoningTokens": reasoning_tokens,
    }


def append_ai_usage(provider, model, profile, symbol, usage, timestamp=None):
    normalized = normalize_ai_usage(provider, usage)
    if normalized["totalTokens"] <= 0:
        return None
    timestamp = int(timestamp or time.time())
    identity = ":".join([
        str(time.time_ns()),
        provider,
        model,
        profile,
        symbol,
    ])
    event = dict({
        "id": hashlib.sha256(identity.encode("utf-8")).hexdigest()[:20],
        "timestamp": timestamp,
        "provider": provider,
        "model": model,
        "profile": profile,
        "symbol": symbol,
    }, **normalized)
    descriptor = os.open(ai_usage_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        payload = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
        os.write(descriptor, payload.encode("utf-8"))
    finally:
        os.close(descriptor)
    return event


def load_ai_usage():
    events = deque(maxlen=AI_USAGE_READ_LIMIT)
    try:
        with open(ai_usage_path(), encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                    if isinstance(event, dict) and event.get("provider") in ("openai", "claude"):
                        events.append(event)
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return list(events)


def ai_usage_totals(events):
    keys = (
        "inputTokens",
        "billableInputTokens",
        "outputTokens",
        "totalTokens",
        "cachedInputTokens",
        "cacheWriteTokens",
        "reasoningTokens",
    )
    totals = {key: sum(int(numeric(event.get(key))) for event in events) for key in keys}
    totals["calls"] = len(events)
    totals["cacheRate"] = round(
        totals["cachedInputTokens"] / totals["billableInputTokens"] * 100,
        1,
    ) if totals["billableInputTokens"] else 0
    return totals


def ai_usage_summary(days=30, limit=100, now=None, events=None):
    days = max(1, min(365, int(numeric(days, 30))))
    limit = max(1, min(500, int(numeric(limit, 100))))
    now = int(now or time.time())
    cutoff = now - days * 24 * 60 * 60
    selected = [
        event
        for event in (load_ai_usage() if events is None else events)
        if cutoff <= int(numeric(event.get("timestamp"))) <= now
    ]
    selected.sort(key=lambda event: int(numeric(event.get("timestamp"))), reverse=True)
    groups = {}
    for event in selected:
        key = (str(event.get("provider", "")), str(event.get("model", "")))
        groups.setdefault(key, []).append(event)
    models = []
    for (provider, model), group in groups.items():
        models.append(dict({
            "provider": provider,
            "model": model,
            "lastUsedAt": max(int(numeric(event.get("timestamp"))) for event in group),
        }, **ai_usage_totals(group)))
    models.sort(key=lambda value: (value["totalTokens"], value["calls"]), reverse=True)
    return {
        "status": "ok",
        "days": days,
        "from": cutoff,
        "to": now,
        "summary": ai_usage_totals(selected),
        "models": models,
        "recent": selected[:limit],
        "storage": "local_metadata_only",
        "message": "Prompts, responses, API keys, and account identifiers are not stored in this ledger.",
    }
