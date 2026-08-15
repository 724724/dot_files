import fcntl
import json
import math
import os
import time
from contextlib import contextmanager
from datetime import datetime
from zoneinfo import ZoneInfo

from .automation import (
    AUTOMATION_TIMEZONE,
    MARKET_DATA_FUTURE_SKEW_SECONDS,
    automation_plan_audit_status,
    automation_plan_integrity_key,
    automation_lock,
    canonical_record_hash,
    automation_risk_snapshot,
    exit_only_protection_enabled,
    live_auto_session_status,
    load_automation_risk,
    load_automation_plans,
    load_automation_policy,
    portfolio_sector_risk,
    save_automation_risk,
    save_automation_policy,
)
from .broker import KisPostError, kis_get, kis_quote
from .core import StockServiceError, load_risk_policy, numeric, state_directory
from .trading import broker_order_match, kis_account_summary, kis_cancel, kis_order, kis_order_history
from .automation_positions import position_risk_audit_status
from .automation_ownership import managed_position_ownership


PAPER_EXECUTION_CONFIRMATION = "EXECUTE KIS PAPER"
LIVE_EXECUTION_CONFIRMATION = "EXECUTE KIS LIVE"


def policy_execution_environment(policy):
    return "prod" if policy.get("executionMode") == "live" else "paper"
MARKET_SAFETY_OPEN = (9, 10)
MARKET_SAFETY_CLOSE = (15, 10)
US_MARKET_TIMEZONE = ZoneInfo("America/New_York")
US_SAFETY_OPEN = (9, 40)
US_SAFETY_CLOSE = (15, 50)
US_MARKETS = {
    "NASDAQ": {"quoteExchange": "NAS", "currency": "USD"},
    "NYSE": {"quoteExchange": "NYS", "currency": "USD"},
}
SUPPORTED_EXECUTION_MARKETS = {"KRX", *US_MARKETS}
UNRESOLVED_EXECUTION_STATES = {"claimed", "accepted", "uncertain", "partial", "submitted", "pending"}
FINAL_BROKER_STATES = {"filled", "rejected", "canceled"}


def normalized_execution_market(value):
    market = str(value or "KRX").strip().upper()
    if market not in SUPPORTED_EXECUTION_MARKETS:
        raise StockServiceError("Automation execution does not support this market")
    return market


def market_timezone(market):
    return AUTOMATION_TIMEZONE if normalized_execution_market(market) == "KRX" else US_MARKET_TIMEZONE


def market_session_date(timestamp, market):
    return datetime.fromtimestamp(int(timestamp), market_timezone(market)).date().isoformat()


def record_market(record):
    try:
        return normalized_execution_market(record.get("market", "KRX"))
    except StockServiceError:
        return "KRX"


def automation_broker_order_match(record, orders):
    if (
        str(record.get("environment", "paper")).lower() == "prod"
        and not str(record.get("orderNumber", "")).strip()
    ):
        return None
    return broker_order_match(dict(record, action="order"), orders)


def automation_execution_path():
    return os.path.join(state_directory(), "automation-executions.jsonl")


def automation_calendar_path():
    return os.path.join(state_directory(), "automation-market-calendar.json")


@contextmanager
def automation_execution_lock():
    descriptor = os.open(automation_execution_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def append_execution_event(event):
    audit = execution_journal_audit_status()
    if not audit["healthy"]:
        raise StockServiceError("Automation execution journal integrity check failed")
    payload = dict(event)
    payload.pop("previousHash", None)
    payload.pop("recordHash", None)
    payload["timestamp"] = int(numeric(payload.get("timestamp"))) or int(time.time())
    payload["journalVersion"] = 1
    payload["previousHash"] = audit["latestHash"]
    payload["recordHash"] = canonical_record_hash(payload, ("recordHash",))
    descriptor = os.open(automation_execution_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    return payload


def load_execution_events():
    events = []
    try:
        with open(automation_execution_path(), encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(event, dict):
                    events.append(event)
    except OSError:
        pass
    return events


def execution_journal_audit_status():
    verified = 0
    legacy = 0
    invalid = 0
    first_error = None
    previous_hash = ""
    chain_started = False
    try:
        with open(automation_execution_path(), encoding="utf-8") as handle:
            lines = list(handle)
    except OSError:
        lines = []
    for index, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "invalid_json"}
            continue
        if not isinstance(event, dict):
            invalid += 1
            first_error = first_error or {"line": index, "reason": "invalid_record"}
            continue
        record_hash = str(event.get("recordHash", ""))
        if not record_hash:
            legacy += 1
            if chain_started:
                invalid += 1
                first_error = first_error or {"line": index, "reason": "missing_record_hash"}
            continue
        try:
            expected_hash = canonical_record_hash(event, ("recordHash",))
        except StockServiceError:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "non_canonical_record"}
            expected_hash = record_hash
        if record_hash != expected_hash:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "record_hash_mismatch"}
        if str(event.get("previousHash", "")) != previous_hash:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "chain_link_mismatch"}
        if numeric(event.get("journalVersion")) != 1:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "unsupported_journal_version"}
        chain_started = True
        previous_hash = record_hash
        verified += 1
    return {
        "healthy": invalid == 0,
        "verifiedRecords": verified,
        "legacyRecords": legacy,
        "invalidRecords": invalid,
        "latestHash": previous_hash,
        "firstError": first_error or {},
    }


def automation_audit_status():
    plans = automation_plan_audit_status()
    executions = execution_journal_audit_status()
    positions = position_risk_audit_status(state_directory())
    return {
        "healthy": plans["healthy"] and executions["healthy"] and positions["healthy"],
        "plans": plans,
        "executions": executions,
        "positions": positions,
    }


def load_execution_records(limit=2000):
    records = {}
    for event in load_execution_events():
        plan_id = str(event.get("planId", ""))
        if not plan_id:
            continue
        merged = dict(records.get(plan_id, {}))
        merged.update(event)
        records[plan_id] = merged
    merged_records = list(records.values())
    if limit is None:
        return merged_records
    return merged_records[-max(1, min(5000, int(limit))):]


def execution_is_unresolved(record):
    state = str(record.get("brokerState") or record.get("state") or "")
    return state in UNRESOLVED_EXECUTION_STATES


def automation_execution_status(limit=20):
    all_records = load_execution_records(limit=None)
    display_limit = max(1, min(5000, int(limit)))
    records = list(reversed(all_records[-display_limit:]))
    now = int(time.time())
    unresolved_count = sum(
        1 for record in all_records if execution_is_unresolved(record)
    )
    policy = load_automation_policy()
    live_armed = policy.get("executionMode") == "live"
    return {
        "status": "ok",
        "supported": True,
        "paperOnly": not live_armed,
        "productionLocked": not live_armed,
        "records": records,
        "latest": records[0] if records else {},
        "unresolved": unresolved_count,
        "unresolvedCount": unresolved_count,
        "uncertaintyLock": unresolved_count > 0,
        "audit": automation_audit_status(),
        "today": sum(
            1
            for record in all_records
            if str(record.get("sessionDate") or record.get("date", ""))
            == market_session_date(now, record_market(record))
        ),
        "updatedAt": now,
    }


def load_market_calendar():
    try:
        with open(automation_calendar_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def save_market_calendar(value):
    path = automation_calendar_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def kis_business_day(environment, moment):
    date_text = moment.strftime("%Y%m%d")
    cache = load_market_calendar()
    cached = cache.get(date_text) if isinstance(cache.get(date_text), dict) else None
    if cached and int(numeric(cached.get("checkedAt"))) > int(time.time()) - 18 * 60 * 60:
        return bool(cached.get("open")), "cached"
    # The holiday inquiry (CTCA0903R) is production-only; the paper server
    # rejects it with "모의투자 TR이 아닙니다". Route it through production
    # credentials when they exist, and otherwise fall back to the caller's
    # weekday check — stale-quote freshness gates still block executions on
    # an unverified holiday.
    try:
        response = kis_get(
            "prod" if environment == "paper" else environment,
            "/uapi/domestic-stock/v1/quotations/chk-holiday",
            "CTCA0903R",
            {"BASS_DT": date_text, "CTX_AREA_FK": "", "CTX_AREA_NK": ""},
        )
    except StockServiceError:
        if environment != "paper":
            raise
        return True, "weekday_fallback"
    rows = response.get("output") or []
    if isinstance(rows, dict):
        rows = [rows]
    row = next((item for item in rows if str(item.get("bass_dt", "")) == date_text), None)
    if not row:
        raise StockServiceError("KIS business-day verification returned no matching date")
    opened = str(row.get("opnd_yn", "")).upper() == "Y"
    cache[date_text] = {"open": opened, "checkedAt": int(time.time())}
    cache = {key: value for key, value in cache.items() if key >= date_text}
    save_market_calendar(cache)
    return opened, "kis"


def market_session_gate(environment, now=None, market="KRX"):
    timestamp = int(now if now is not None else time.time())
    market = normalized_execution_market(market)
    timezone = market_timezone(market)
    moment = datetime.fromtimestamp(timestamp, timezone)
    if moment.weekday() >= 5:
        return {
            "passed": False,
            "message": f"{market} is closed on weekends",
            "market": market,
            "sessionDate": moment.date().isoformat(),
            "checkedAt": timestamp,
        }
    minute = moment.hour * 60 + moment.minute
    if market != "KRX":
        start = US_SAFETY_OPEN[0] * 60 + US_SAFETY_OPEN[1]
        end = US_SAFETY_CLOSE[0] * 60 + US_SAFETY_CLOSE[1]
        passed = start <= minute < end
        return {
            "passed": passed,
            "message": (
                f"{market} is inside the 09:40–15:50 America/New_York safety window"
                if passed
                else f"Automation execution is limited to the {market} 09:40–15:50 America/New_York safety window"
            ),
            "market": market,
            "sessionDate": moment.date().isoformat(),
            "source": "exchange_clock",
            "requiresFreshOrderbook": True,
            "checkedAt": timestamp,
        }
    start = MARKET_SAFETY_OPEN[0] * 60 + MARKET_SAFETY_OPEN[1]
    end = MARKET_SAFETY_CLOSE[0] * 60 + MARKET_SAFETY_CLOSE[1]
    if minute < start or minute >= end:
        return {
            "passed": False,
            "message": "Automation execution is limited to the 09:10–15:10 KST safety window",
            "market": market,
            "sessionDate": moment.date().isoformat(),
            "checkedAt": timestamp,
        }
    opened, source = kis_business_day(environment, moment)
    if source == "weekday_fallback":
        message = "Weekday session assumed; the holiday calendar needs production credentials"
    else:
        message = "KIS confirms an open KRX business day" if opened else "KIS reports a KRX market holiday"
    return {
        "passed": opened,
        "message": message,
        "market": market,
        "sessionDate": moment.date().isoformat(),
        "source": source,
        "checkedAt": timestamp,
    }


def find_automation_plan(plan_id):
    return next((plan for plan in reversed(load_automation_plans(2000)) if plan.get("planId") == plan_id), None)


def execution_usage(now, market=None):
    target_market = normalized_execution_market(market) if market else ""
    active = [
        record for record in load_execution_records()
        if (not target_market or record_market(record) == target_market)
        and str(record.get("sessionDate") or record.get("date", ""))
        == market_session_date(now, record_market(record))
        and str(record.get("brokerState") or record.get("state"))
        not in ("rejected", "canceled", "preflight_failed")
    ]
    strategy_orders = [
        record for record in active
        if not bool(record.get("protectiveExit"))
    ]
    return {
        "orders": len(active),
        "strategyOrders": len(strategy_orders),
        "protectiveExits": len(active) - len(strategy_orders),
        "buyOrders": sum(1 for record in active if record.get("side") == "buy"),
        "newExposureKrw": int(sum(
            numeric(record.get("estimatedNotionalKrw"), numeric(record.get("estimatedNotional")))
            for record in active
            if record.get("side") == "buy"
        )),
    }


def first_mapping(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, list) and value and isinstance(value[0], dict):
        return value[0]
    return {}


def overseas_orderbook(environment, symbol, market, now=None):
    market = normalized_execution_market(market)
    if market not in US_MARKETS:
        raise StockServiceError("Overseas orderbook requires a supported US market")
    timestamp = int(now if now is not None else time.time())
    response = kis_get(
        environment,
        "/uapi/overseas-price/v1/quotations/inquire-asking-price",
        "HHDFS76200100",
        {
            "AUTH": "",
            "EXCD": US_MARKETS[market]["quoteExchange"],
            "SYMB": str(symbol).strip().upper(),
        },
    )
    values = {}
    for key in ("output", "output1", "output2", "output3"):
        values.update(first_mapping(response.get(key)))
    date_text = str(values.get("dymd") or values.get("xymd") or "").strip()
    time_text = str(values.get("dhms") or values.get("xhms") or "").strip()[:6]
    quote_timestamp = 0
    if len(date_text) == 8 and len(time_text) == 6:
        try:
            quote_timestamp = int(
                datetime.strptime(date_text + time_text, "%Y%m%d%H%M%S")
                .replace(tzinfo=US_MARKET_TIMEZONE)
                .timestamp()
            )
        except ValueError:
            quote_timestamp = 0
    return {
        "market": market,
        "currency": str(values.get("curr") or US_MARKETS[market]["currency"]),
        "ask": numeric(values.get("pask1")),
        "bid": numeric(values.get("pbid1")),
        "askQuantity": int(numeric(values.get("vask1"))),
        "bidQuantity": int(numeric(values.get("vbid1"))),
        "quoteTimestamp": quote_timestamp,
        "quoteAgeSeconds": timestamp - quote_timestamp if quote_timestamp > 0 else 10 ** 9,
        "decimalPlaces": int(numeric(values.get("zdiv"))),
    }


def market_risk_snapshot(environment, market, total_evaluation_krw, exchange_rate, now=None):
    market = normalized_execution_market(market)
    if market == "KRX":
        return automation_risk_snapshot(environment, total_evaluation_krw, now)
    now = max(int(now if now is not None else time.time()), int(time.time()))
    total_evaluation_krw = numeric(total_evaluation_krw)
    date_text = market_session_date(now, market)
    state = load_automation_risk()
    key = f"{environment}:{market}"
    account = state.get(key, {}) if isinstance(state.get(key), dict) else {}
    if account.get("date") != date_text or numeric(account.get("dayStartEvaluation")) <= 0:
        account = {
            "date": date_text,
            "dayStartEvaluation": total_evaluation_krw,
            "peakEvaluation": total_evaluation_krw,
        }
    account["peakEvaluation"] = max(numeric(account.get("peakEvaluation")), total_evaluation_krw)
    account["lastEvaluation"] = total_evaluation_krw
    account["localCurrency"] = US_MARKETS[market]["currency"]
    account["exchangeRate"] = numeric(exchange_rate)
    account["updatedAt"] = now
    start = numeric(account.get("dayStartEvaluation"))
    peak = numeric(account.get("peakEvaluation"))
    account["dailyReturnPercent"] = (
        round((total_evaluation_krw / start - 1) * 100, 3) if start > 0 else 0
    )
    account["drawdownPercent"] = (
        round((total_evaluation_krw / peak - 1) * 100, 3) if peak > 0 else 0
    )
    state[key] = account
    save_automation_risk(state)
    return account


def halt_automation(reason="Automation execution safety halt", halt_class="execution"):
    with automation_lock():
        policy = load_automation_policy()
        exit_only = (
            halt_class == "capital_loss"
            and policy.get("schedulerMode") == "paper_auto"
            and policy.get("schedulerEnabled")
        )
        policy["enabled"] = False
        policy["halted"] = True
        policy["haltReason"] = str(reason)[:240]
        policy["haltClass"] = str(halt_class)[:40]
        policy["haltedAt"] = int(time.time())
        policy["haltIncidentId"] = os.urandom(8).hex()
        policy["exitOnlyProtection"] = exit_only
        save_automation_policy(policy)


def validate_execution_policy(
    policy,
    environment,
    now,
    expected_session_id="",
    protective_exit=False,
):
    expected_mode = "live" if environment == "prod" else "paper"
    active = bool(policy.get("enabled")) and not policy.get("halted")
    exit_only = bool(protective_exit) and exit_only_protection_enabled(policy)
    if policy.get("executionMode") != expected_mode or not (active or exit_only):
        raise StockServiceError("Automation was paused, halted, or changed before order submission")
    if environment != "prod":
        return {}
    if not policy.get("liveConsent"):
        raise StockServiceError("Live automation consent was revoked before order submission")
    session = live_auto_session_status(policy, now, "prod")
    if not session.get("valid"):
        raise StockServiceError(
            "Live automation session is invalid: "
            + ",".join(session.get("reasons") or ["unknown"]),
        )
    if expected_session_id and session.get("sessionId") != expected_session_id:
        raise StockServiceError("Live automation session changed before order submission")
    if not load_risk_policy().get("productionEnabled"):
        raise StockServiceError("Production trading was locked before order submission")
    return session


def execution_preflight(plan, policy, now=None):
    now = max(int(now if now is not None else time.time()), int(time.time()))
    audit = automation_audit_status()
    if not audit["healthy"]:
        raise StockServiceError("Automation audit journal integrity check failed")
    if numeric(plan.get("integrityVersion")) != 2:
        raise StockServiceError("Legacy automation plans cannot be executed; generate a fresh plan")
    if plan.get("executionKey") != automation_plan_integrity_key(plan):
        raise StockServiceError("Automation plan integrity check failed")
    if plan.get("decision") != "ready" or not plan.get("executionEligible"):
        raise StockServiceError("Only an execution-eligible ready plan can be submitted")
    environment = policy_execution_environment(policy)
    if plan.get("environment") != environment or plan.get("dataMode") != "kis":
        raise StockServiceError("Execution requires a plan built against the armed KIS account")
    if plan.get("executionMode") != policy.get("executionMode") or policy.get("executionMode") not in ("paper", "live"):
        raise StockServiceError("KIS execution is not armed for this plan's mode")
    protective_exit = (
        plan.get("side") == "sell"
        and bool((plan.get("riskExit") or {}).get("triggered"))
    )
    validate_execution_policy(
        policy,
        environment,
        now,
        protective_exit=protective_exit,
    )
    age = now - int(numeric(plan.get("createdAt")))
    if age < 0 or age > int(policy["maxPlanAgeSeconds"]):
        raise StockServiceError("Automation plan expired; generate a fresh plan")
    if any(not gate.get("passed") for gate in plan.get("gates", [])):
        raise StockServiceError("Automation plan contains a failed safety gate")
    if any(execution_is_unresolved(record) for record in load_execution_records()):
        raise StockServiceError("An earlier automation order is unresolved; reconcile before continuing")

    market = normalized_execution_market(plan.get("market", "KRX"))
    symbol = str(plan["symbol"]).strip().upper()
    session = market_session_gate(environment, now, market)
    if not session["passed"]:
        raise StockServiceError(session["message"])
    side = str(plan.get("side"))
    quote = kis_quote(
        symbol,
        market,
        environment,
        include_orderbook=market == "KRX",
        include_vi=market == "KRX",
    )
    expected_currency = "KRW" if market == "KRX" else "USD"
    quote_market = str(quote.get("market", market)).strip().upper()
    quote_currency = str(quote.get("currency") or expected_currency).strip().upper()
    if quote_market != market or quote_currency != expected_currency:
        raise StockServiceError("KIS returned market data for a different instrument market")
    quote_reference_now = max(now, int(time.time()))
    quote_updated_at = int(numeric(
        quote.get("sourceUpdatedAt", quote.get("updatedAt")),
    ))
    quote_age_seconds = (
        quote_reference_now - quote_updated_at
        if quote_updated_at > 0
        else 10 ** 9
    )
    if (
        quote_updated_at <= 0
        or quote_age_seconds < -MARKET_DATA_FUTURE_SKEW_SECONDS
        or quote_age_seconds > int(policy["maxMarketDataAgeSeconds"])
    ):
        raise StockServiceError("KIS quote is outside the execution freshness window")
    market_safety = quote.get("marketSafety") if isinstance(quote.get("marketSafety"), dict) else {}
    if not market_safety.get("available") or not market_safety.get("tradable"):
        raise StockServiceError("KIS reports that the security is not in a normal tradable state")
    if market == "KRX" and not protective_exit:
        if not market_safety.get("viAvailable"):
            raise StockServiceError("KIS volatility interruption status is unavailable")
        if market_safety.get("viActive"):
            raise StockServiceError("A volatility interruption is active; paper order blocked")
    if side == "buy" and market_safety.get("restricted"):
        raise StockServiceError("KIS risk flags block new automated exposure")
    current_price = numeric(quote.get("price"))
    planned_price = numeric(plan.get("price"))
    if current_price <= 0 or planned_price <= 0:
        raise StockServiceError("Current KIS price is unavailable")
    orderbook = {}
    if market == "KRX" and not protective_exit:
        best_ask = numeric(quote.get("ask"))
        best_bid = numeric(quote.get("bid"))
        orderbook_updated_at = int(numeric(quote.get("orderbookUpdatedAt")))
        orderbook_age = (
            max(quote_reference_now, int(time.time())) - orderbook_updated_at
            if orderbook_updated_at > 0
            else 10 ** 9
        )
        if (
            orderbook_updated_at <= 0
            or orderbook_age < -MARKET_DATA_FUTURE_SKEW_SECONDS
            or orderbook_age > int(policy["maxMarketDataAgeSeconds"])
        ):
            raise StockServiceError("KIS KRX orderbook is outside the execution freshness window")
        quote_age_seconds = max(quote_age_seconds, orderbook_age)
    elif market != "KRX":
        orderbook = overseas_orderbook(
            environment,
            symbol,
            market,
            max(quote_reference_now, int(time.time())),
        )
        orderbook_age = int(numeric(orderbook.get("quoteAgeSeconds"), 10 ** 9))
        if (
            int(numeric(orderbook.get("quoteTimestamp"))) <= 0
            or orderbook_age < -MARKET_DATA_FUTURE_SKEW_SECONDS
            or orderbook_age > int(policy["maxMarketDataAgeSeconds"])
        ):
            raise StockServiceError("KIS US orderbook is outside the execution freshness window")
        best_ask = numeric(orderbook.get("ask"))
        best_bid = numeric(orderbook.get("bid"))
        quote_age_seconds = max(quote_age_seconds, orderbook_age)
    else:
        best_ask = numeric(quote.get("ask"))
        best_bid = numeric(quote.get("bid"))
    spread_bps = 0
    if not protective_exit or market != "KRX":
        if best_ask <= 0 or best_bid <= 0 or best_ask < best_bid:
            raise StockServiceError("Paper order requires a valid KIS bid-ask quote")
        midpoint = (best_ask + best_bid) / 2
        spread_bps = (best_ask - best_bid) / midpoint * 10000
        if spread_bps > numeric(policy["maxBidAskSpreadBps"]):
            raise StockServiceError("Paper order would breach the bid-ask spread limit")
    execution_price = (
        current_price
        if protective_exit and market == "KRX"
        else (best_ask if side == "buy" else best_bid)
    )
    upper_limit = numeric(market_safety.get("upperLimit"))
    lower_limit = numeric(market_safety.get("lowerLimit"))
    if market == "KRX" and side == "buy" and upper_limit > 0 and execution_price >= upper_limit:
        raise StockServiceError("Paper buy order is blocked at the daily upper price limit")
    if (
        market == "KRX"
        and side == "sell"
        and not protective_exit
        and lower_limit > 0
        and execution_price <= lower_limit
    ):
        raise StockServiceError("Paper sell order is blocked at the daily lower price limit")
    drift = abs(execution_price / planned_price - 1) * 100
    if not protective_exit and drift > numeric(policy["maxPriceDriftPercent"]):
        raise StockServiceError("Price moved beyond the execution drift limit; generate a fresh plan")

    quantity = int(numeric(plan.get("quantity")))
    local_notional = (
        int(round(quantity * execution_price))
        if market == "KRX"
        else round(quantity * execution_price, 8)
    )
    if quantity < 1 or local_notional <= 0:
        raise StockServiceError("Paper order exceeds the current per-order safety limit")
    order_type = "market" if protective_exit and market == "KRX" else "limit"
    account = kis_account_summary(
        environment,
        symbol,
        execution_price,
        "market" if market == "KRX" else "limit",
        market,
    )
    account_market = str(account.get("market", market)).strip().upper()
    account_currency = str(account.get("currency") or expected_currency).strip().upper()
    if account_market != market or account_currency != expected_currency:
        raise StockServiceError("KIS returned an account snapshot for a different market")
    ownership = {}
    if environment == "prod":
        ownership = managed_position_ownership(
            load_execution_records(5000),
            account,
            environment,
            market,
            symbol,
        )
        if side == "buy" and ownership["mixedWithManual"]:
            raise StockServiceError(
                "Live automated entry is blocked because this symbol has a manual holding",
            )
        if (
            side == "sell"
            and quantity > int(ownership["managedSellableQuantity"])
        ):
            raise StockServiceError(
                "Live automated sell exceeds the confirmed managed position",
            )
    exchange_rate = 1 if market == "KRX" else numeric(account.get("exchangeRate"))
    if market != "KRX" and exchange_rate <= 0:
        raise StockServiceError("The USD/KRW exchange rate is unavailable for automated risk checks")
    notional_krw = int(round(local_notional * exchange_rate))
    if notional_krw <= 0 or (
        not protective_exit and notional_krw > numeric(policy["maxOrderValueKrw"])
    ):
        raise StockServiceError("Paper order exceeds the current per-order safety limit")
    total_local = numeric(account.get("totalEvaluation"))
    total_krw = total_local * exchange_rate
    if total_local <= 0 or total_krw <= 0:
        raise StockServiceError("Account evaluation is unavailable at execution")
    risk = market_risk_snapshot(environment, market, total_krw, exchange_rate, now)
    if side == "buy" and numeric(risk.get("dailyReturnPercent")) <= -numeric(policy["maxDailyLossPercent"]):
        error = StockServiceError(
            "Daily loss safety cooldown is active; automation will retry automatically",
        )
        error.failure_class = "transient"
        raise error
    if side == "buy" and numeric(risk.get("drawdownPercent")) <= -numeric(policy["maxPortfolioDrawdownPercent"]):
        error = StockServiceError(
            "Portfolio drawdown safety cooldown is active; automation will retry automatically",
        )
        error.failure_class = "transient"
        raise error

    usage = execution_usage(now)
    if (
        side == "buy"
        and usage["buyOrders"] >= int(policy["maxOrdersPerDay"])
    ):
        raise StockServiceError("Daily paper execution count limit reached")
    if side == "buy":
        if quantity > int(numeric(account.get("buyingQuantity"))):
            raise StockServiceError("Paper order exceeds the current buyable quantity")
        if usage["newExposureKrw"] + notional_krw > numeric(policy["maxDailyNewExposureKrw"]):
            raise StockServiceError("Daily new exposure limit reached")
        holding = next((
            item
            for item in account.get("holdings", [])
            if item.get("symbol") == symbol
            and str(item.get("market", market)).strip().upper() == market
        ), {})
        projected = numeric(holding.get("evaluation")) + local_notional
        sector_risk = portfolio_sector_risk(
            account, symbol, local_notional, total_local, policy, market, exchange_rate,
        )
        if not sector_risk.get("available"):
            raise StockServiceError("Paper order requires complete sector classification data")
        if numeric(sector_risk.get("projectedExposurePercent")) > numeric(policy["maxSectorExposurePercent"]):
            raise StockServiceError("Paper order would breach the sector concentration limit")
        correlation = plan.get("correlationRisk") or {}
        current_symbols = sorted({
            f"{str(item.get('market', market)).strip().upper()}:"
            f"{str(item.get('symbol', '')).strip().upper()}"
            for item in account.get("holdings", [])
            if str(item.get("symbol", "")).strip().upper() != plan["symbol"]
            and max(0, numeric(
                item.get("evaluation"),
                numeric(item.get("quantity")) * numeric(item.get("price")),
            )) > 0
        })
        if current_symbols != sorted(correlation.get("evaluatedSymbols") or []):
            raise StockServiceError("Portfolio holdings changed; generate a fresh automation plan")
        if not correlation.get("available"):
            raise StockServiceError("Paper order requires complete return correlation data")
        if numeric(correlation.get("maxCorrelation")) > numeric(policy["maxCorrelationCoefficient"]):
            raise StockServiceError("Paper order would breach the return correlation limit")
        liquidity = plan.get("liquidityRisk") or {}
        if not liquidity.get("available"):
            raise StockServiceError("Paper order requires complete liquidity data")
        turnover = numeric(liquidity.get("medianDailyTurnoverKrw"))
        participation = notional_krw / turnover * 100 if turnover > 0 else float("inf")
        if participation > numeric(policy["maxMarketParticipationPercent"]):
            raise StockServiceError("Paper order would breach the market participation limit")
        tail_risk = plan.get("portfolioTailRisk") or {}
        if not tail_risk.get("available"):
            raise StockServiceError("Paper order requires complete portfolio tail-risk history")
        if not tail_risk.get("passed"):
            raise StockServiceError("Paper order would breach portfolio tail-risk limits")
        sizing = plan.get("riskSizing") or {}
        annualized = numeric(sizing.get("annualizedVolatilityPercent"))
        current_distance = max(
            numeric(policy["maxPositionLossPercent"]),
            annualized / math.sqrt(252) * numeric(policy["volatilityRiskMultiplier"]),
        )
        risk_distance = max(numeric(sizing.get("riskDistancePercent")), current_distance)
        risk_budget = total_local * numeric(policy["maxRiskPerTradePercent"]) / 100
        if risk_distance <= 0 or projected * risk_distance / 100 > risk_budget:
            raise StockServiceError("Paper order would breach the volatility-adjusted loss budget")
        reserve = total_local * numeric(policy["cashReservePercent"]) / 100
        if numeric(account.get("cash")) - local_notional < reserve:
            raise StockServiceError("Paper order would breach the required cash reserve")
        if projected / total_local * 100 > numeric(policy["maxPositionPercent"]):
            raise StockServiceError("Paper order would breach the position concentration limit")
    elif side == "sell":
        if quantity > int(numeric(account.get("sellableQuantity"))):
            raise StockServiceError("Paper order exceeds the current sellable quantity")
    else:
        raise StockServiceError("Hold plans cannot be executed")
    return {
        "session": session,
        "market": market,
        "currency": str(account.get("currency") or ("KRW" if market == "KRX" else "USD")),
        "exchangeRate": exchange_rate,
        "quote": quote,
        "orderbook": orderbook,
        "quoteAgeSeconds": quote_age_seconds,
        "marketSafety": market_safety,
        "account": account,
        "managedPositionOwnership": ownership,
        "risk": risk,
        "usage": usage,
        "orderType": order_type,
        "currentPrice": execution_price,
        "lastPrice": current_price,
        "bestAsk": best_ask,
        "bestBid": best_bid,
        "bidAskSpreadBps": round(spread_bps, 2),
        "priceDriftPercent": round(drift, 4),
        "estimatedNotional": local_notional,
        "estimatedNotionalKrw": notional_krw,
        "protectiveExit": protective_exit,
        "environment": environment,
        "checkedAt": now,
    }


def execute_automation_plan(payload, now=None):
    if not isinstance(payload, dict):
        raise StockServiceError("Automation execution payload must be an object")
    plan_id = str(payload.get("planId", ""))
    if not plan_id:
        raise StockServiceError("Automation plan ID is required")
    now = max(int(now if now is not None else time.time()), int(time.time()))
    with automation_execution_lock():
        previous = next((
            record for record in load_execution_records()
            if record.get("planId") == plan_id
        ), None)
        if previous and execution_is_unresolved(previous):
            raise StockServiceError(
                "This automation plan already has an execution attempt that is uncertain or unresolved",
            )
        if previous:
            raise StockServiceError("This automation plan already has an execution attempt")
        plan = find_automation_plan(plan_id)
        if not plan:
            raise StockServiceError("Automation plan was not found")
        policy = load_automation_policy()
        live = policy.get("executionMode") == "live"
        prefix = LIVE_EXECUTION_CONFIRMATION if live else PAPER_EXECUTION_CONFIRMATION
        if str(payload.get("confirmation", "")) != f"{prefix} {plan_id}":
            raise StockServiceError("Execution requires exact plan confirmation for the armed mode")
        preflight = execution_preflight(plan, policy, now)
        environment = preflight["environment"]
        market = preflight["market"]
        execution_id = os.urandom(8).hex()
        session_date = str(
            preflight.get("session", {}).get("sessionDate")
            or market_session_date(now, market)
        )
        base = {
            "kind": "execution",
            "executionId": execution_id,
            "planId": plan_id,
            "date": session_date,
            "sessionDate": session_date,
            "environment": environment,
            "market": market,
            "currency": preflight["currency"],
            "exchangeRate": preflight["exchangeRate"],
            "side": plan["side"],
            "symbol": plan["symbol"],
            "quantity": int(plan["quantity"]),
            "orderType": preflight["orderType"],
            "price": preflight["currentPrice"],
            "estimatedNotional": preflight["estimatedNotional"],
            "estimatedNotionalKrw": preflight["estimatedNotionalKrw"],
            "transactionCosts": dict(plan.get("transactionCosts") or {}),
            "pendingTimeoutSeconds": int(policy["maxPendingOrderSeconds"]),
            "accountBefore": {
                "currency": preflight["currency"],
                "cash": numeric(preflight["account"].get("cash")),
                "totalEvaluation": numeric(preflight["account"].get("totalEvaluation")),
                "holdingQuantity": int(numeric(preflight["account"].get("holdingQuantity"))),
                "sellableQuantity": int(numeric(preflight["account"].get("sellableQuantity"))),
            },
        }
        order_request = {
            "requestId": execution_id,
            "automationPlanId": plan_id,
            "symbol": plan["symbol"],
            "market": market,
            "side": plan["side"],
            "orderType": preflight["orderType"],
            "quantity": int(plan["quantity"]),
            "price": preflight["currentPrice"],
        }
        if environment == "prod":
            order_request["confirmation"] = "LIVE"
        try:
            with automation_lock():
                current_policy = load_automation_policy()
                validate_execution_policy(
                    current_policy,
                    environment,
                    int(time.time()),
                    str(policy.get("liveSessionId", "")) if live else "",
                    preflight["protectiveExit"],
                )
                append_execution_event(dict(
                    base,
                    state="claimed",
                    brokerState="claimed",
                    timestamp=now,
                ))
                order = kis_order(environment, order_request)
        except KisPostError as error:
            if not error.outcome_ambiguous:
                append_execution_event(dict(
                    base,
                    state="rejected" if error.request_sent else "preflight_failed",
                    brokerState="rejected" if error.request_sent else "preflight_failed",
                    brokerCode=error.broker_code,
                    requestSent=error.request_sent,
                    message=str(error),
                    timestamp=now,
                ))
                raise
            append_execution_event(dict(
                base,
                state="uncertain",
                brokerState="uncertain",
                requestSent=True,
                message=str(error),
                timestamp=now,
            ))
            try:
                halt_automation(
                    "Order outcome is uncertain; broker reconciliation is required",
                    "order_uncertainty",
                )
            except OSError:
                pass
            uncertain = StockServiceError(
                "Order outcome is uncertain. Automation was halted; reconcile with KIS before continuing"
            )
            uncertain.failure_class = "hard"
            raise uncertain from error
        except StockServiceError as error:
            append_execution_event(dict(
                base,
                state="preflight_failed",
                brokerState="preflight_failed",
                requestSent=False,
                message=str(error),
                timestamp=now,
            ))
            raise
        except Exception as error:
            append_execution_event(dict(
                base,
                state="uncertain",
                brokerState="uncertain",
                requestSent=True,
                message=str(error),
                timestamp=now,
            ))
            try:
                halt_automation(
                    "Order outcome is uncertain; broker reconciliation is required",
                    "order_uncertainty",
                )
            except OSError:
                pass
            uncertain = StockServiceError(
                "Order outcome is uncertain. Automation was halted; reconcile with KIS before continuing"
            )
            uncertain.failure_class = "hard"
            raise uncertain from error
        result = dict(
            base,
            status="ok",
            state="accepted",
            brokerState="accepted",
            orderNumber=str(order.get("orderNumber", "")),
            organizationNumber=str(order.get("organizationNumber", "")),
            brokerOrderSent=True,
            message=(
                ("Protective live exit accepted; reconciliation is in progress"
                 if environment == "prod"
                 else "Protective paper exit accepted; reconciliation is in progress")
                if preflight["protectiveExit"]
                else ("KIS live order accepted; reconciliation is required before another execution"
                      if environment == "prod"
                      else "KIS paper order accepted; reconciliation is required before another execution")
            ),
            protectiveExit=preflight["protectiveExit"],
            preflight={
                "checkedAt": preflight["checkedAt"],
                "priceDriftPercent": preflight["priceDriftPercent"],
                "bidAskSpreadBps": preflight["bidAskSpreadBps"],
                "session": preflight["session"],
            },
            timestamp=now,
        )
        append_execution_event(result)
        return result


def reconcile_automation_executions(now=None):
    now = int(now if now is not None else time.time())
    with automation_execution_lock():
        records = [
            record
            for record in load_execution_records(limit=None)
            if execution_is_unresolved(record)
        ]
        if not records:
            return dict({
                "kind": "reconciliation",
                "matched": 0,
                "pending": 0,
                "cancelRequested": 0,
            }, **automation_execution_status())
        orders_by_identity = {}
        identities = sorted({
            (str(record.get("environment", "paper")), record_market(record))
            for record in records
        })
        for record_environment, market in identities:
            history = kis_order_history(record_environment, "", 200, 7, market)
            orders_by_identity[(record_environment, market)] = history.get("orders", [])
        matched = 0
        pending = 0
        cancel_requested = 0
        for record in records:
            record_environment = str(record.get("environment", "paper"))
            market = record_market(record)
            orders = orders_by_identity.get((record_environment, market), [])
            match = automation_broker_order_match(record, orders)
            if not match:
                pending += 1
                live_confirmation_required = (
                    record_environment == "prod"
                    and not str(record.get("orderNumber", "")).strip()
                )
                append_execution_event(dict(
                    record,
                    state="uncertain" if record.get("state") == "uncertain" else record.get("state", "claimed"),
                    brokerState="uncertain" if record.get("state") == "uncertain" else record.get("brokerState", "claimed"),
                    reconciliationMatch=(
                        "manual_confirmation_required"
                        if live_confirmation_required
                        else str(record.get("reconciliationMatch", ""))
                    ),
                    message=(
                        "Live order has no broker order number; explicit broker confirmation is required"
                        if live_confirmation_required
                        else str(record.get("message", ""))
                    ),
                    lastReconciledAt=now,
                ))
                continue
            _, order, match_type = match
            broker_state = str(order.get("state", "submitted"))
            remaining = int(numeric(order.get("remainingQuantity")))
            age = max(0, now - int(numeric(record.get("timestamp"))))
            timeout = int(numeric(record.get("pendingTimeoutSeconds"), 120))
            stale_limit = (
                record.get("orderType") == "limit"
                and broker_state in UNRESOLVED_EXECUTION_STATES
                and remaining > 0
                and age >= timeout
                and not numeric(record.get("cancelRequestedAt"))
            )
            if stale_limit:
                cancel_request = {"orderNumber": str(order.get("orderNumber", ""))}
                if market != "KRX":
                    cancel_request.update({
                        "market": market,
                        "symbol": str(record.get("symbol") or order.get("symbol") or ""),
                    })
                if record_environment == "prod":
                    cancel_request["confirmation"] = "LIVE"
                try:
                    cancellation = kis_cancel(record_environment, cancel_request)
                except Exception as error:
                    append_execution_event(dict(
                        record,
                        state="uncertain",
                        brokerState="uncertain",
                        cancelAttemptedAt=now,
                        lastReconciledAt=now,
                        message=str(error)[:240],
                    ))
                    try:
                        halt_automation(
                            "Order cancellation outcome is uncertain; broker reconciliation is required",
                            "order_uncertainty",
                        )
                    except OSError:
                        pass
                    raise StockServiceError(
                        "Stale limit order cancellation outcome is uncertain; automation was halted"
                    ) from error
                append_execution_event(dict(
                    record,
                    state="cancel_requested",
                    brokerState=broker_state,
                    orderNumber=str(order.get("orderNumber", "")),
                    filledQuantity=int(numeric(order.get("filledQuantity"))),
                    remainingQuantity=remaining,
                    averagePrice=numeric(order.get("averagePrice")),
                    filledNotional=numeric(order.get("filledNotional")),
                    commission=numeric(order.get("commission")),
                    tax=numeric(order.get("tax")),
                    settlementAmount=numeric(order.get("settlementAmount")),
                    costSource=str(order.get("costSource", "estimated")),
                    reconciliationMatch=match_type,
                    cancelRequestedAt=now,
                    cancellationOrderNumber=str(cancellation.get("orderNumber", "")),
                    message="Stale limit order cancellation requested",
                    lastReconciledAt=now,
                ))
                matched += 1
                cancel_requested += 1
                continue
            append_execution_event(dict(
                record,
                state="reconciled" if broker_state in FINAL_BROKER_STATES else broker_state,
                brokerState=broker_state,
                orderNumber=str(order.get("orderNumber", "")),
                filledQuantity=int(numeric(order.get("filledQuantity"))),
                remainingQuantity=remaining,
                averagePrice=numeric(order.get("averagePrice")),
                filledNotional=numeric(order.get("filledNotional")),
                commission=numeric(order.get("commission")),
                tax=numeric(order.get("tax")),
                settlementAmount=numeric(order.get("settlementAmount")),
                costSource=str(order.get("costSource", "estimated")),
                reconciliationMatch=match_type,
                lastReconciledAt=now,
            ))
            matched += 1
        result = automation_execution_status()
        result.update({
            "kind": "reconciliation",
            "matched": matched,
            "pending": pending,
            "cancelRequested": cancel_requested,
        })
        return result
