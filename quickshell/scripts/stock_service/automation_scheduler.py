import fcntl
import json
import os
import re
import time
from contextlib import contextmanager

from .automation import (
    automation_lock,
    build_automation_plan,
    clear_live_auto_session,
    exit_only_protection_enabled,
    live_auto_session_status,
    load_automation_policy,
    save_automation_policy,
)
from .automation_execution import (
    automation_execution_status,
    execution_is_unresolved,
    execute_automation_plan,
    load_execution_records,
    market_session_gate,
    reconcile_automation_executions,
)
from .broker import kis_quote, kis_snapshot
from .core import StockServiceError, numeric, state_directory
from .forecasting import analyze
from .automation_shadow import apply_shadow_plan
from .automation_positions import load_position_state, observe_position_risk
from .automation_ownership import managed_account_view, managed_position_ownership
from .automation_accounting import reconcile_automation_accounting
from .automation_universe import (
    AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS,
    autopilot_status,
    autopilot_targets,
    discover_autopilot_candidates,
    load_autopilot_state,
)
from .trading import kis_account_summary


AUTOMATION_GLOBAL_SPACING_SECONDS = 5 * 60
PROTECTION_MONITOR_INTERVAL_SECONDS = 60
AUTOMATION_TRANSIENT_BACKOFF_BASE_SECONDS = 60
AUTOMATION_TRANSIENT_BACKOFF_MAX_SECONDS = 15 * 60
PROTECTION_MONITOR_BUDGET_SECONDS = 45
TRANSIENT_FAILURE_MARKERS = (
    "freshness window",
    "rate limit",
    "too many request",
    "egw00201",
    "초당 거래건수",
    "network",
    "timed out",
    "timeout",
    "temporarily",
    "unavailable",
    "could not reach",
    "connection",
    "remote api",
    "모의투자 tr 이 아닙니다",
    "market session",
    "market calendar",
)
HARD_FAILURE_MARKERS = (
    "audit",
    "integrity",
    "uncertain",
    "unresolved",
    "accounting reconciliation",
    "invariant",
)
OPERATOR_FAILURE_MARKERS = (
    "credential",
    "authentication",
    "authorization",
    "permission",
    "account number",
    "account configuration",
    "api key",
    "quota",
    "billing",
    "invalid tr",
)


def fresh_scheduler_time(reference=0):
    return max(int(numeric(reference)), int(time.time()))


def scheduler_failure_class(error):
    explicit = str(getattr(error, "failure_class", "")).strip().lower()
    if explicit in ("transient", "hard", "operator"):
        return explicit
    message = str(error or "").strip()
    lowered = message.lower()
    if any(marker in lowered for marker in HARD_FAILURE_MARKERS):
        return "hard"
    if any(marker in lowered for marker in OPERATOR_FAILURE_MARKERS):
        return "operator"
    if any(marker in lowered for marker in TRANSIENT_FAILURE_MARKERS):
        return "transient"
    return "transient"


def reset_scheduler_failures(runtime):
    runtime["consecutiveFailures"] = 0
    runtime["transientFailures"] = 0
    runtime["retryAt"] = 0
    runtime["lastTransientError"] = ""
    runtime["retryScope"] = ""
    runtime["retryTargetId"] = ""
    runtime["retryFailureClass"] = ""


def record_scheduler_failure(policy, runtime, error, now):
    message = str(error or "Automation worker failed")[:240]
    failure_class = scheduler_failure_class(error)
    if failure_class in ("transient", "operator"):
        failures = int(numeric(runtime.get("transientFailures"))) + 1
        delay = min(
            AUTOMATION_TRANSIENT_BACKOFF_MAX_SECONDS,
            AUTOMATION_TRANSIENT_BACKOFF_BASE_SECONDS
            * (2 ** min(4, failures - 1)),
        )
        runtime["transientFailures"] = failures
        runtime["retryAt"] = int(now) + delay
        runtime["lastTransientError"] = message
        runtime["consecutiveFailures"] = 0
        return {
            "failureClass": failure_class,
            "consecutiveFailures": 0,
            "transientFailures": failures,
            "retryAt": runtime["retryAt"],
            "nextRunInSeconds": delay,
            "halted": False,
            "actionRequired": failure_class == "operator",
            "message": message,
        }
    failures = int(numeric(runtime.get("consecutiveFailures"))) + 1
    runtime["consecutiveFailures"] = failures
    runtime["transientFailures"] = 0
    runtime["retryAt"] = 0
    halted = halt_after_scheduler_failures(policy, runtime, message, failure_class)
    return {
        "failureClass": failure_class,
        "consecutiveFailures": failures,
        "transientFailures": 0,
        "retryAt": 0,
        "halted": halted,
        "message": message,
    }


def planning_account_ownership(account, environment, market, symbol, price):
    if environment != "prod":
        return account, {}
    ownership = managed_position_ownership(
        load_execution_records(5000),
        account,
        environment,
        market,
        symbol,
    )
    return managed_account_view(account, ownership, price), ownership


def automation_scheduler_path():
    return os.path.join(state_directory(), "automation-scheduler.json")


@contextmanager
def automation_scheduler_lock():
    descriptor = os.open(automation_scheduler_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def load_automation_scheduler_runtime():
    try:
        with open(automation_scheduler_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def save_automation_scheduler_runtime(runtime):
    path = automation_scheduler_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(runtime, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def normalized_automation_targets(configs):
    targets = []
    seen = set()
    for config in configs:
        if (
            not isinstance(config, dict)
            or config.get("automationTargetEnabled") is not True
            or str(config.get("tradingMode", "manual")).lower() != "automatic"
        ):
            continue
        symbol = str(config.get("symbol", "")).strip().upper()
        market = str(config.get("market", "KRX")).strip().upper()
        mode = str(config.get("mode", "demo")).lower()
        environment = str(config.get("environment", "paper")).lower()
        provider = str(config.get("aiProvider", "none")).lower()
        profile = str(config.get("analysisProfile", "balanced")).lower()
        strategy = str(config.get("backtestStrategy", "trend")).lower()
        identity = ":".join((environment, market, symbol, provider, profile, strategy))
        symbol_valid = (
            bool(re.fullmatch(r"\d{6}", symbol))
            if market == "KRX"
            else market in ("NASDAQ", "NYSE") and bool(re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol))
        )
        if (
            identity in seen
            or not symbol_valid
            or mode != "kis"
            or environment not in ("paper", "prod")
            or provider not in ("openai", "claude", "both")
            or profile not in ("quick", "balanced", "deep")
            or strategy not in ("trend", "momentum", "mean_reversion")
        ):
            continue
        seen.add(identity)
        targets.append({
            "id": identity,
            "sourceId": str(config.get("sourceId", "stock")),
            "symbol": symbol,
            "market": market,
            "mode": mode,
            "environment": environment,
            "aiProvider": provider,
            "analysisProfile": profile,
            "strategy": strategy,
            "language": "en" if config.get("language") == "en" else "ko",
            "allowEntry": True,
            "autopilot": False,
        })
    return targets


def combined_automation_targets(configs, universe_state=None, environment=None):
    state = universe_state if isinstance(universe_state, dict) else load_autopilot_state()
    autopilot_enabled = bool(state.get("enabled"))
    combined = {}
    for target in normalized_automation_targets(configs):
        if environment and target.get("environment") != environment:
            continue
        item = dict(target)
        if autopilot_enabled:
            item["allowEntry"] = False
        combined.setdefault(f"{item['market']}:{item['symbol']}", item)
    if autopilot_enabled:
        for target in autopilot_targets(state):
            if environment and target.get("environment") != environment:
                continue
            combined[f"{target['market']}:{target['symbol']}"] = target
    return list(combined.values())


def automation_scheduler_status():
    policy = load_automation_policy()
    runtime = load_automation_scheduler_runtime()
    return {
        "status": "ok",
        "enabled": bool(policy.get("schedulerEnabled")),
        "mode": policy.get("schedulerMode", "observe"),
        "autoExecution": policy.get("schedulerMode") == "paper_auto",
        "consecutiveFailures": int(numeric(runtime.get("consecutiveFailures"))),
        "transientFailures": int(numeric(runtime.get("transientFailures"))),
        "retryAt": int(numeric(runtime.get("retryAt"))),
        "lastTransientError": str(runtime.get("lastTransientError", "")),
        "lastRun": runtime.get("lastRun", {}),
        "targets": runtime.get("targets", {}),
        "autopilot": autopilot_status(),
        "updatedAt": int(time.time()),
    }


def live_automation_cycle_status(policy, universe_state, configs, runtime, now):
    if policy.get("executionMode") != "live":
        return {"passed": True, "reasons": [], "session": {}}
    reasons = []
    session = live_auto_session_status(policy, now, "prod")
    reasons.extend(session.get("reasons") or [])
    if not policy.get("liveConsent"):
        reasons.append("live_consent_revoked")
    try:
        from .core import load_risk_policy
        if not load_risk_policy().get("productionEnabled"):
            reasons.append("production_risk_locked")
    except Exception:
        reasons.append("production_risk_unavailable")
    try:
        from .automation_live import automation_live_status
        readiness = automation_live_status(int(numeric(
            runtime.get("consecutiveFailures"),
        )))
        if not readiness.get("productionAutomationEligible"):
            reasons.append("live_readiness_revoked")
    except Exception:
        reasons.append("live_readiness_unavailable")
    if (
        (policy.get("autopilotEnabled") or universe_state.get("enabled"))
        and str(universe_state.get("environment", "paper")).lower() != "prod"
    ):
        reasons.append("autopilot_environment_mismatch")
    return {
        "passed": not reasons,
        "reasons": list(dict.fromkeys(reasons)),
        "session": session,
    }


def revoke_live_automation(reason):
    with automation_lock():
        current = load_automation_policy()
        if current.get("executionMode") == "live":
            current.update({
                "enabled": False,
                "halted": True,
                "haltReason": str(reason)[:240],
                "haltClass": "live_session",
                "haltedAt": int(time.time()),
                "haltIncidentId": os.urandom(8).hex(),
                "exitOnlyProtection": False,
                "executionMode": "paper",
                "paperOnly": True,
                "schedulerMode": "observe",
                "autopilotEnabled": False,
            })
            clear_live_auto_session(current)
            current = save_automation_policy(current)
    return {
        "policy": current,
        "reason": str(reason),
    }


def halt_after_scheduler_failures(
    policy,
    runtime,
    reason="Automation worker failed repeatedly",
    halt_class="hard",
):
    if int(numeric(runtime.get("consecutiveFailures"))) < int(policy["maxConsecutiveFailures"]):
        return False
    with automation_lock():
        current = load_automation_policy()
        current["enabled"] = False
        current["halted"] = True
        current["haltReason"] = str(reason)[:240]
        current["haltClass"] = str(halt_class)[:40]
        current["haltedAt"] = int(time.time())
        current["haltIncidentId"] = os.urandom(8).hex()
        current["exitOnlyProtection"] = False
        save_automation_policy(current)
    return True


def scheduler_analysis_evidence(result):
    agreement = result.get("ensembleAgreement") if isinstance(result.get("ensembleAgreement"), dict) else {}
    return {
        "status": result.get("status"),
        "stance": result.get("stance"),
        "confidence": int(numeric(result.get("confidence"))),
        "downProbability": int(numeric(result.get("downProbability"))),
        "generatedAt": int(numeric(result.get("generatedAt"))),
        "models": list(result.get("models") or []),
        "ensembleAgreement": agreement,
        "newsContext": dict(result.get("newsContext") or {}),
        "behaviorContext": dict(result.get("behaviorContext") or {}),
        "behaviorAdjustment": dict(result.get("behaviorAdjustment") or {}),
    }


def choose_due_target(targets, runtime, interval_seconds, now):
    candidates = due_automation_targets(targets, runtime, interval_seconds, now)
    return candidates[0] if candidates else None


def due_automation_targets(targets, runtime, interval_seconds, now):
    states = runtime.get("targets") if isinstance(runtime.get("targets"), dict) else {}
    candidates = []
    for target in targets:
        state = states.get(target["id"]) if isinstance(states.get(target["id"]), dict) else {}
        last_attempt = int(numeric(state.get("attemptedAt")))
        retry_at = int(numeric(state.get("retryAt")))
        if retry_at > now:
            continue
        if retry_at > 0 or now - last_attempt >= interval_seconds:
            candidates.append((last_attempt, target["id"], target))
    candidates.sort(key=lambda item: (item[0], item[1]))
    return [item[2] for item in candidates]


def recover_recoverable_halt(policy, universe_state):
    if (
        not policy.get("halted")
        or policy.get("haltClass") == "manual"
        or not policy.get("schedulerEnabled")
    ):
        return policy, False
    halt_class = str(policy.get("haltClass", ""))
    halt_reason = str(policy.get("haltReason", ""))
    persistent = halt_class in {
        "audit_integrity",
        "accounting_integrity",
        "order_uncertainty",
        "live_consent",
        "live_session",
    }
    if halt_class == "hard" and scheduler_failure_class(halt_reason) == "hard":
        persistent = True
    if persistent or policy.get("executionMode") == "live":
        return policy, False
    with automation_lock():
        current = load_automation_policy()
        if not current.get("halted") or current.get("haltClass") == "manual":
            return current, False
        current.update({
            "enabled": current.get("executionMode") in ("paper", "live"),
            "halted": False,
            "haltReason": "",
            "haltClass": "",
            "haltedAt": 0,
            "haltIncidentId": "",
            "exitOnlyProtection": False,
        })
        if current.get("schedulerEnabled") and universe_state.get("enabled"):
            current["schedulerMode"] = "paper_auto"
            current["autopilotEnabled"] = True
        current = save_automation_policy(current)
    return current, True


def migrate_target_retry(runtime):
    if str(runtime.get("retryScope", "")) != "target":
        return
    target_id = str(runtime.get("retryTargetId", ""))
    retry_at = int(numeric(runtime.get("retryAt")))
    if target_id and retry_at > 0:
        states = runtime.get("targets") if isinstance(runtime.get("targets"), dict) else {}
        state = dict(states.get(target_id, {}))
        state.update({
            "retryAt": retry_at,
            "retryFailureClass": str(runtime.get("retryFailureClass", "transient")),
            "message": str(runtime.get("lastTransientError", ""))[:240],
        })
        states[target_id] = state
        runtime["targets"] = states
    runtime["retryAt"] = 0
    runtime["retryScope"] = ""
    runtime["retryTargetId"] = ""
    runtime["retryFailureClass"] = ""


def record_target_failure(policy, runtime, state, error, now):
    failure_class = scheduler_failure_class(error)
    if failure_class == "hard":
        return record_scheduler_failure(policy, runtime, error, now)
    failures = int(numeric(state.get("transientFailures"))) + 1
    delay = min(
        AUTOMATION_TRANSIENT_BACKOFF_MAX_SECONDS,
        AUTOMATION_TRANSIENT_BACKOFF_BASE_SECONDS
        * (2 ** min(4, failures - 1)),
    )
    state.update({
        "transientFailures": failures,
        "retryAt": int(now) + delay,
        "retryFailureClass": failure_class,
        "message": str(error or "Automation target failed")[:240],
    })
    runtime["consecutiveFailures"] = 0
    return {
        "failureClass": failure_class,
        "consecutiveFailures": 0,
        "transientFailures": failures,
        "retryAt": state["retryAt"],
        "nextRunInSeconds": delay,
        "halted": False,
        "actionRequired": failure_class == "operator",
        "message": state["message"],
    }


def managed_execution_positions(environment, directory=None):
    path = os.path.join(directory or state_directory(), "automation-executions.jsonl")
    records = {}
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(event, dict):
                    continue
                plan_id = str(event.get("planId", ""))
                if not plan_id:
                    continue
                merged = dict(records.get(plan_id, {}))
                merged.update(event)
                records[plan_id] = merged
    except OSError:
        return {}
    positions = {}
    for record in records.values():
        if str(record.get("environment", "paper")).lower() != environment:
            continue
        market = str(record.get("market", "KRX")).upper()
        symbol = str(record.get("symbol", "")).upper()
        quantity = max(0, int(numeric(record.get("filledQuantity"))))
        if market not in ("KRX", "NASDAQ", "NYSE") or not symbol or quantity <= 0:
            continue
        identity = f"{market}:{symbol}"
        direction = 1 if record.get("side") == "buy" else -1
        positions[identity] = positions.get(identity, 0) + direction * quantity
    return {identity: quantity for identity, quantity in positions.items() if quantity > 0}


def tracked_protection_targets(environment, directory=None):
    state = load_position_state(directory)
    targets = []
    seen = set()
    for record in (state.get("positions") or {}).values():
        if not isinstance(record, dict):
            continue
        record_environment = str(record.get("environment", "paper")).lower()
        market = str(record.get("market", "KRX")).upper()
        symbol = str(record.get("symbol", "")).upper()
        identity = f"{market}:{symbol}"
        if (
            record_environment != environment
            or identity in seen
            or int(numeric(record.get("quantity"))) <= 0
            or market not in ("KRX", "NASDAQ", "NYSE")
        ):
            continue
        seen.add(identity)
        targets.append({
            "id": "protect:" + identity,
            "sourceId": "position-risk",
            "symbol": symbol,
            "market": market,
            "mode": "kis",
            "environment": environment,
            "aiProvider": "none",
            "analysisProfile": "balanced",
            "strategy": "trend",
            "language": "ko",
            "allowEntry": False,
            "autopilot": False,
            "protectOnly": True,
        })
    for identity in managed_execution_positions(environment, directory):
        if identity in seen:
            continue
        market, symbol = identity.split(":", 1)
        seen.add(identity)
        targets.append({
            "id": "protect:" + identity,
            "sourceId": "execution-journal",
            "symbol": symbol,
            "market": market,
            "mode": "kis",
            "environment": environment,
            "aiProvider": "none",
            "analysisProfile": "balanced",
            "strategy": "trend",
            "language": "ko",
            "allowEntry": False,
            "autopilot": False,
            "protectOnly": True,
        })
    return targets


def due_protection_targets(targets, runtime, now, interval_seconds=PROTECTION_MONITOR_INTERVAL_SECONDS):
    states = (
        runtime.get("protectionTargets")
        if isinstance(runtime.get("protectionTargets"), dict)
        else {}
    )
    candidates = []
    for target in targets:
        state = states.get(target["id"]) if isinstance(states.get(target["id"]), dict) else {}
        checked_at = int(numeric(state.get("checkedAt")))
        if now - checked_at >= interval_seconds:
            candidates.append((checked_at, target["id"], target))
    candidates.sort(key=lambda item: (item[0], item[1]))
    return [item[2] for item in candidates]


def monitor_protective_positions(policy, environment, now, runtime):
    started_monotonic = time.monotonic()
    targets = tracked_protection_targets(environment, state_directory())
    active_ids = {target["id"] for target in targets}
    protection_states = (
        runtime.get("protectionTargets")
        if isinstance(runtime.get("protectionTargets"), dict)
        else {}
    )
    protection_states = {
        target_id: value
        for target_id, value in protection_states.items()
        if target_id in active_ids and isinstance(value, dict)
    }
    runtime["protectionTargets"] = protection_states
    due_targets = due_protection_targets(targets, runtime, now)
    if not due_targets:
        waits = [
            max(
                0,
                PROTECTION_MONITOR_INTERVAL_SECONDS
                - (now - int(numeric(protection_states.get(target["id"], {}).get("checkedAt")))),
            )
            for target in targets
        ]
        return {
            "status": "ok",
            "state": "throttled" if targets else "no_position",
            "checked": 0,
            "targetCount": len(targets),
            "triggered": False,
            "brokerOrderSent": False,
            "nextRunInSeconds": min(waits) if waits else 0,
            "observations": [],
            "errors": [],
        }

    observations = []
    errors = []
    sessions = {}
    checked = 0
    deferred = 0
    last_target = None
    last_ownership = {}
    for index, target in enumerate(due_targets):
        if (
            checked > 0
            and time.monotonic() - started_monotonic
            >= PROTECTION_MONITOR_BUDGET_SECONDS
        ):
            deferred = len(due_targets) - index
            break
        market = target["market"]
        if market not in sessions:
            try:
                sessions[market] = market_session_gate(
                    environment,
                    market=market,
                    now=fresh_scheduler_time(now),
                )
            except Exception as error:
                sessions[market] = None
                errors.append({
                    "market": market,
                    "symbol": target["symbol"],
                    "message": str(error)[:240],
                })
        session = sessions[market]
        if not session or not session.get("passed"):
            if session:
                observations.append({
                    "market": market,
                    "symbol": target["symbol"],
                    "state": "market_closed",
                })
            continue
        last_target = target
        protection_states[target["id"]] = {
            "checkedAt": fresh_scheduler_time(now),
        }
        runtime["protectionTargets"] = protection_states
        checked += 1
        try:
            snapshot = kis_quote(
                target["symbol"],
                market,
                environment,
                include_orderbook=market == "KRX",
                include_vi=market == "KRX",
            )
            quote_now = fresh_scheduler_time(now)
            source_updated_at = int(numeric(
                snapshot.get(
                    "sourceUpdatedAt",
                    snapshot.get("updatedAt", quote_now),
                ),
            ))
            quote_age = quote_now - source_updated_at
            if (
                source_updated_at <= 0
                or quote_age < -5
                or quote_age > int(policy["maxMarketDataAgeSeconds"])
            ):
                raise StockServiceError(
                    "KIS protective quote is outside the execution freshness window",
                )
            price = numeric(snapshot.get("price"))
            account = kis_account_summary(
                environment,
                target["symbol"],
                price,
                "market" if market == "KRX" else "limit",
                market,
            )
            account, ownership = planning_account_ownership(
                account,
                environment,
                market,
                target["symbol"],
                price,
            )
            last_ownership = ownership
            holding = next((
                item for item in account.get("holdings", [])
                if item.get("symbol") == target["symbol"]
                and str(item.get("market") or market).upper() == market
            ), {})
            risk_now = fresh_scheduler_time(now)
            position_risk = observe_position_risk(
                environment,
                target["symbol"],
                holding,
                price,
                policy,
                risk_now,
                directory=state_directory(),
                market=market,
            )
            observations.append({
                "market": market,
                "symbol": target["symbol"],
                "state": "triggered" if position_risk.get("triggered") else "clear",
                "risk": position_risk,
            })
            if not position_risk.get("triggered"):
                continue
            plan_now = fresh_scheduler_time(risk_now)
            plan = build_automation_plan({
                "symbol": target["symbol"],
                "market": market,
                "allowEntry": False,
                "dataMode": "kis",
                "environment": environment,
                "strategy": target["strategy"],
                "snapshot": {
                    "name": snapshot.get("name"),
                    "price": price,
                    "currency": snapshot.get("currency"),
                    "exchangeRate": numeric(snapshot.get("exchangeRate")),
                    "bid": numeric(snapshot.get("bid")),
                    "ask": numeric(snapshot.get("ask")),
                    "updatedAt": int(numeric(snapshot.get("updatedAt"))),
                    "marketSafety": snapshot.get("marketSafety") or {},
                },
                "analysis": scheduler_analysis_evidence({}),
            }, now=plan_now, trusted_account=account, trusted_position_risk=position_risk)
            shadow = apply_shadow_plan(plan, price, plan_now)
            execution = {}
            if (
                policy.get("schedulerMode") == "paper_auto"
                and plan.get("executionEligible")
            ):
                execution = execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": (
                        f"EXECUTE KIS LIVE {plan['planId']}"
                        if environment == "prod"
                        else f"EXECUTE KIS PAPER {plan['planId']}"
                    ),
                })
            return {
                "status": "ok",
                "state": "triggered",
                "checked": checked,
                "targetCount": len(targets),
                "triggered": True,
                "brokerOrderSent": bool(execution.get("brokerOrderSent")),
                "target": target,
                "plan": plan,
                "managedPositionOwnership": ownership,
                "shadow": shadow,
                "execution": execution,
                "observations": observations,
                "errors": errors,
                "deferred": deferred,
            }
        except Exception as error:
            errors.append({
                "market": market,
                "symbol": target["symbol"],
                "message": str(error)[:240],
            })
    if errors:
        return {
            "status": "error",
            "state": "monitor_error",
            "checked": checked,
            "targetCount": len(targets),
            "triggered": False,
            "brokerOrderSent": False,
            "target": last_target or {},
            "managedPositionOwnership": last_ownership,
            "observations": observations,
            "errors": errors,
            "deferred": deferred,
        }
    return {
        "status": "ok",
        "state": "clear" if checked else "market_closed",
        "checked": checked,
        "targetCount": len(targets),
        "triggered": False,
        "brokerOrderSent": False,
        "target": last_target or {},
        "managedPositionOwnership": last_ownership,
        "observations": observations,
        "errors": [],
        "deferred": deferred,
    }


def run_automation_scheduler(configs, now=None):
    now = int(now if now is not None else time.time())
    with automation_scheduler_lock():
        policy = load_automation_policy()
        runtime = load_automation_scheduler_runtime()
        universe_state = load_autopilot_state()
        migrate_target_retry(runtime)
        policy, recovered_halt = recover_recoverable_halt(
            policy,
            universe_state,
        )
        if recovered_halt:
            reset_scheduler_failures(runtime)
        execution = automation_execution_status()
        unresolved_records = [
            record for record in load_execution_records(limit=None)
            if execution_is_unresolved(record)
        ]
        unresolved_environments = {
            "prod" if str(record.get("environment", "paper")).lower() == "prod"
            else "paper"
            for record in unresolved_records
        }
        had_unresolved = bool(execution.get("uncertaintyLock"))
        if execution.get("uncertaintyLock"):
            last_reconciliation = int(numeric(runtime.get("lastReconciliationAt")))
            if now - last_reconciliation >= 60:
                runtime["lastReconciliationAt"] = fresh_scheduler_time(now)
                try:
                    execution = reconcile_automation_executions(
                        now=fresh_scheduler_time(now),
                    )
                except Exception as error:
                    execution = {
                        "status": "error",
                        "uncertaintyLock": True,
                        "message": str(error)[:240],
                    }
        if had_unresolved and not execution.get("uncertaintyLock"):
            if not unresolved_environments:
                unresolved_environments.add(
                    "prod" if policy.get("executionMode") == "live" else "paper",
                )
            pending = {
                str(value) for value in (
                    runtime.get("accountingPendingEnvironments") or []
                )
                if str(value) in ("paper", "prod")
            }
            pending.update(unresolved_environments)
            runtime["accountingPendingEnvironments"] = sorted(pending)
        if execution.get("uncertaintyLock"):
            result = {
                "status": "degraded",
                "state": "waiting_reconciliation",
                "mode": policy.get("schedulerMode", "observe"),
                "autoExecution": False,
                "brokerOrderSent": False,
                "targetCount": 0,
                "candidateCount": len(universe_state.get("candidates") or []),
                "execution": execution,
                "message": str(
                    execution.get("message")
                    or "Waiting for the final KIS order result"
                ),
                "updatedAt": fresh_scheduler_time(now),
            }
            runtime["lastRun"] = result
            runtime["updatedAt"] = result["updatedAt"]
            save_automation_scheduler_runtime(runtime)
            return result
        accounting_pending = [
            str(value) for value in (
                runtime.get("accountingPendingEnvironments") or []
            )
            if str(value) in ("paper", "prod")
        ]
        if accounting_pending:
            accounting_retry_at = int(numeric(runtime.get("accountingRetryAt")))
            if accounting_retry_at > fresh_scheduler_time(now):
                result = {
                    "status": "degraded",
                    "state": "waiting_accounting",
                    "mode": policy.get("schedulerMode", "observe"),
                    "autoExecution": False,
                    "brokerOrderSent": False,
                    "targetCount": 0,
                    "candidateCount": len(universe_state.get("candidates") or []),
                    "accountingPendingEnvironments": accounting_pending,
                    "retryAt": accounting_retry_at,
                    "nextRunInSeconds": max(
                        0, accounting_retry_at - fresh_scheduler_time(now),
                    ),
                    "message": str(
                        runtime.get("lastAccountingError")
                        or "Waiting for broker position reconciliation"
                    ),
                    "updatedAt": fresh_scheduler_time(now),
                }
                runtime["lastRun"] = result
                runtime["updatedAt"] = result["updatedAt"]
                save_automation_scheduler_runtime(runtime)
                return result
            completed_environments = []
            accounting_results = {}
            try:
                for environment in accounting_pending:
                    accounting = reconcile_automation_accounting(
                        environment,
                        now=fresh_scheduler_time(now),
                    )
                    accounting_results[environment] = accounting
                    if not accounting.get("healthy"):
                        with automation_lock():
                            current = load_automation_policy()
                            current.update({
                                "enabled": False,
                                "halted": True,
                                "haltReason": (
                                    "Broker holdings failed accounting reconciliation"
                                ),
                                "haltClass": "accounting_integrity",
                                "haltedAt": int(time.time()),
                                "haltIncidentId": os.urandom(8).hex(),
                                "exitOnlyProtection": False,
                                "schedulerMode": "observe",
                            })
                            save_automation_policy(current)
                        result = {
                            "status": "error",
                            "state": "accounting_failure",
                            "mode": "observe",
                            "autoExecution": False,
                            "brokerOrderSent": False,
                            "halted": True,
                            "targetCount": 0,
                            "candidateCount": len(
                                universe_state.get("candidates") or [],
                            ),
                            "accounting": accounting,
                            "accountingByEnvironment": accounting_results,
                            "message": (
                                "Broker holdings failed accounting reconciliation; "
                                "the kill switch was engaged"
                            ),
                            "updatedAt": fresh_scheduler_time(now),
                        }
                        runtime["lastRun"] = result
                        runtime["updatedAt"] = result["updatedAt"]
                        save_automation_scheduler_runtime(runtime)
                        return result
                    completed_environments.append(environment)
            except Exception as error:
                failure_time = fresh_scheduler_time(now)
                runtime["accountingRetryAt"] = failure_time + 60
                runtime["lastAccountingError"] = str(error)[:240]
                runtime["accountingPendingEnvironments"] = [
                    environment for environment in accounting_pending
                    if environment not in completed_environments
                ]
                result = {
                    "status": "degraded",
                    "state": "waiting_accounting",
                    "mode": policy.get("schedulerMode", "observe"),
                    "autoExecution": False,
                    "brokerOrderSent": False,
                    "targetCount": 0,
                    "candidateCount": len(universe_state.get("candidates") or []),
                    "accountingPendingEnvironments": runtime[
                        "accountingPendingEnvironments"
                    ],
                    "retryAt": runtime["accountingRetryAt"],
                    "nextRunInSeconds": 60,
                    "message": str(error)[:240],
                    "updatedAt": failure_time,
                }
                runtime["lastRun"] = result
                runtime["updatedAt"] = failure_time
                save_automation_scheduler_runtime(runtime)
                return result
            runtime["accountingPendingEnvironments"] = []
            runtime["accountingRetryAt"] = 0
            runtime["lastAccountingError"] = ""
        if (
            policy.get("halted")
            and policy.get("haltClass") == "order_uncertainty"
            and policy.get("executionMode") == "paper"
            and not execution.get("uncertaintyLock")
            and universe_state.get("enabled")
        ):
            with automation_lock():
                current = load_automation_policy()
                if (
                    current.get("halted")
                    and current.get("haltClass") == "order_uncertainty"
                ):
                    current.update({
                        "enabled": True,
                        "halted": False,
                        "haltReason": "",
                        "haltClass": "",
                        "haltedAt": 0,
                        "haltIncidentId": "",
                        "exitOnlyProtection": False,
                        "schedulerEnabled": True,
                        "schedulerMode": "paper_auto",
                        "autopilotEnabled": True,
                    })
                    save_automation_policy(current)
            policy = load_automation_policy()
        execution_environment = "prod" if policy.get("executionMode") == "live" else "paper"
        exit_only_mode = exit_only_protection_enabled(policy)
        if (
            policy.get("executionMode") == "live"
            and (
                (
                    policy.get("enabled")
                    and not policy.get("halted")
                )
                or exit_only_mode
            )
        ):
            live_cycle = live_automation_cycle_status(
                policy,
                universe_state,
                configs,
                runtime,
                now,
            )
            if not live_cycle.get("passed"):
                revoked = revoke_live_automation(
                    (live_cycle.get("reasons") or ["live_session_invalid"])[0],
                )
                result = {
                    "status": "error",
                    "state": "live_session_revoked",
                    "mode": "observe",
                    "autoExecution": False,
                    "brokerOrderSent": False,
                    "halted": True,
                    "liveRevoked": True,
                    "liveCycle": live_cycle,
                    "revocation": revoked,
                    "targetCount": 0,
                    "updatedAt": now,
                }
                runtime["lastRun"] = result
                runtime["updatedAt"] = now
                save_automation_scheduler_runtime(runtime)
                return result
        retry_at = int(numeric(runtime.get("retryAt")))
        retry_scope = str(runtime.get("retryScope", "target"))
        retry_waiting = retry_at > fresh_scheduler_time(now)
        if retry_waiting and retry_scope == "protection":
            result = {
                "status": "degraded",
                "state": (
                    "protection_retrying"
                    if retry_scope == "protection"
                    else (
                        "operator_action"
                        if runtime.get("retryFailureClass") == "operator"
                        else "retrying"
                    )
                ),
                "mode": policy.get("schedulerMode", "observe"),
                "autoExecution": policy.get("schedulerMode") == "paper_auto",
                "brokerOrderSent": False,
                "targetCount": 0,
                "candidateCount": len(universe_state.get("candidates") or []),
                "failureClass": str(
                    runtime.get("retryFailureClass", "transient"),
                ),
                "actionRequired": (
                    runtime.get("retryFailureClass") == "operator"
                ),
                "retryAt": retry_at,
                "nextRunInSeconds": max(
                    0, retry_at - fresh_scheduler_time(now),
                ),
                "message": str(runtime.get("lastTransientError", "")),
                "updatedAt": fresh_scheduler_time(now),
            }
            runtime["lastRun"] = result
            runtime["updatedAt"] = result["updatedAt"]
            save_automation_scheduler_runtime(runtime)
            return result
        if (
            policy.get("autopilotEnabled")
            and universe_state.get("enabled")
            and not retry_waiting
            and now - int(numeric(universe_state.get("lastScanAt")))
            >= AUTOPILOT_CANDIDATE_MAX_AGE_SECONDS
        ):
            candidates = universe_state.get("candidates") or []
            source = (
                candidates[0]
                if candidates
                else (
                    universe_state.get("research")
                    if isinstance(universe_state.get("research"), dict)
                    else {}
                )
            )
            if str(source.get("aiProvider", "none")).lower() not in (
                "openai",
                "claude",
                "both",
            ):
                source = next((
                    config for config in configs
                    if str(config.get("aiProvider", "none")).lower()
                    in ("openai", "claude", "both")
                ), {})
            provider = str(source.get("aiProvider", "none")).lower()
            if provider in ("openai", "claude", "both"):
                try:
                    discover_autopilot_candidates({
                        "environment": execution_environment,
                        "aiProvider": provider,
                        "analysisProfile": source.get("analysisProfile", "balanced"),
                        "strategy": source.get("strategy", source.get("backtestStrategy", "trend")),
                        "language": source.get("language", "ko"),
                        "universe": universe_state.get("universe") or [],
                    })
                    universe_state = load_autopilot_state()
                    runtime["lastUniverseRefreshAt"] = now
                    runtime["lastUniverseRefreshError"] = ""
                except Exception as error:
                    runtime["lastUniverseRefreshAt"] = now
                    runtime["lastUniverseRefreshError"] = str(error)[:240]
        targets = combined_automation_targets(
            configs,
            universe_state,
            execution_environment,
        )
        autopilot = autopilot_status(universe_state)
        base = {
            "status": "ok",
            "mode": policy.get("schedulerMode", "observe"),
            "autoExecution": (
                policy.get("schedulerMode") == "paper_auto"
                or exit_only_mode
            ),
            "autopilot": {
                "enabled": bool(autopilot.get("enabled")),
                "automaticSelection": bool(autopilot.get("automaticSelection")),
                "selectedCount": int(numeric(autopilot.get("selectedCount"))),
                "phase": str(autopilot.get("phase", "idle")),
            },
            "targetCount": len(targets),
            "candidateCount": len(universe_state.get("candidates") or []),
            "language": targets[0]["language"] if targets else "en",
            "brokerOrderSent": False,
            "updatedAt": now,
        }
        if not policy.get("schedulerEnabled"):
            result = dict(base, state="disabled", execution=execution)
        elif (
            policy.get("halted")
            and policy.get("haltClass") == "live_consent"
        ):
            result = dict(
                base,
                status="error",
                state="live_session_revoked",
                halted=True,
                liveRevoked=True,
                liveCycle={
                    "passed": False,
                    "reasons": ["live_consent_revoked"],
                    "session": {},
                },
                haltReason=str(policy.get("haltReason", "")),
                haltClass=str(policy.get("haltClass", "")),
                message=str(
                    policy.get("haltReason")
                    or "Live automation consent was revoked"
                ),
                execution=execution,
            )
        elif policy.get("halted") and not exit_only_mode:
            result = dict(
                base,
                status="error",
                state="halted",
                halted=True,
                haltReason=str(policy.get("haltReason", "")),
                haltClass=str(policy.get("haltClass", "")),
                haltedAt=int(numeric(policy.get("haltedAt"))),
                haltIncidentId=str(policy.get("haltIncidentId", "")),
                message=str(policy.get("haltReason") or "Automation safety halt"),
                execution=execution,
            )
        elif not policy.get("enabled") and not exit_only_mode:
            result = dict(base, state="paused")
        else:
            if not execution.get("audit", {}).get("healthy"):
                with automation_lock():
                    current = load_automation_policy()
                    current["enabled"] = False
                    current["halted"] = True
                    current["haltReason"] = "Automation audit journal integrity failed"
                    current["haltClass"] = "audit_integrity"
                    current["haltedAt"] = int(time.time())
                    current["haltIncidentId"] = os.urandom(8).hex()
                    current["exitOnlyProtection"] = False
                    current["schedulerMode"] = "observe"
                    save_automation_policy(current)
                result = dict(
                    base,
                    status="error",
                    state="audit_failure",
                    halted=True,
                    autoExecution=False,
                    audit=execution.get("audit", {}),
                    message="Automation audit integrity failed; the kill switch was engaged",
                )
            elif execution.get("uncertaintyLock"):
                last_reconciliation = int(numeric(runtime.get("lastReconciliationAt")))
                if now - last_reconciliation >= 60:
                    runtime["lastReconciliationAt"] = now
                    try:
                        execution = reconcile_automation_executions(now=now)
                    except Exception as error:
                        execution = {"status": "error", "uncertaintyLock": True, "message": str(error)[:240]}
                if execution.get("uncertaintyLock", True):
                    result = dict(base, state="waiting_reconciliation", execution=execution)
                else:
                    try:
                        accounting = reconcile_automation_accounting(execution_environment, now=now)
                    except Exception as error:
                        accounting = {"status": "error", "healthy": False, "message": str(error)[:240]}
                    if not accounting.get("healthy"):
                        with automation_lock():
                            current = load_automation_policy()
                            current["enabled"] = False
                            current["halted"] = True
                            current["haltReason"] = "Broker holdings failed accounting reconciliation"
                            current["haltClass"] = "accounting_integrity"
                            current["haltedAt"] = int(time.time())
                            current["haltIncidentId"] = os.urandom(8).hex()
                            current["exitOnlyProtection"] = False
                            current["schedulerMode"] = "observe"
                            save_automation_policy(current)
                        result = dict(
                            base,
                            status="error",
                            state="accounting_failure",
                            halted=True,
                            autoExecution=False,
                            accounting=accounting,
                            message="Broker holdings failed accounting reconciliation; the kill switch was engaged",
                        )
                    else:
                        result = None
            else:
                result = None
            if result is None:
                try:
                    protection = monitor_protective_positions(
                        (
                            dict(policy, schedulerMode="paper_auto")
                            if exit_only_mode
                            else policy
                        ),
                        execution_environment,
                        now,
                        runtime,
                    )
                except Exception as error:
                    protection = {
                        "status": "error",
                        "checked": 0,
                        "targetCount": 0,
                        "triggered": False,
                        "brokerOrderSent": False,
                        "errors": [{"message": str(error)[:240]}],
                    }
                base["protection"] = {
                    "checked": int(numeric(protection.get("checked"))),
                    "targetCount": int(numeric(protection.get("targetCount"))),
                    "triggered": bool(protection.get("triggered")),
                }
                if protection.get("status") == "error":
                    errors = protection.get("errors") or [{}]
                    failure_time = fresh_scheduler_time(now)
                    failure = record_scheduler_failure(
                        policy,
                        runtime,
                        errors[0].get("message", "Position protection failed"),
                        failure_time,
                    )
                    runtime["retryScope"] = "protection"
                    runtime["retryFailureClass"] = failure["failureClass"]
                    halted = failure["halted"]
                    result = dict(
                        base,
                        status="error" if failure["failureClass"] == "hard" else "degraded",
                        state=(
                            "halted"
                            if halted
                            else (
                                "protection_retrying"
                                if failure["failureClass"] == "transient"
                                else (
                                    "operator_action"
                                    if failure["failureClass"] == "operator"
                                    else "protection_error"
                                )
                            )
                        ),
                        protection=protection,
                        **failure,
                    )
                elif protection.get("triggered"):
                    reset_scheduler_failures(runtime)
                    execution_result = protection.get("execution") or {}
                    plan = protection.get("plan") or {}
                    result = dict(
                        base,
                        state=(
                            "protective_exit_executed"
                            if execution_result.get("brokerOrderSent")
                            else "protective_exit_ready"
                        ),
                        brokerOrderSent=bool(execution_result.get("brokerOrderSent")),
                        target=protection.get("target") or {},
                        plan={
                            "planId": plan.get("planId", ""),
                            "decision": plan.get("decision", ""),
                            "side": plan.get("side", "hold"),
                            "allowEntry": False,
                            "failedGates": list(plan.get("failedGates") or []),
                            "riskExit": plan.get("riskExit", {}),
                        },
                        shadow=protection.get("shadow") or {},
                        execution=execution_result,
                        protection=protection,
                    )
                elif exit_only_mode:
                    result = dict(
                        base,
                        status="degraded",
                        state="exit_only_protection",
                        halted=True,
                        autoExecution=True,
                        haltReason=str(policy.get("haltReason", "")),
                        haltClass=str(policy.get("haltClass", "")),
                        message=(
                            "New entries are halted; open positions remain under automatic loss protection"
                        ),
                        protection=protection,
                    )
                elif retry_waiting:
                    result = dict(
                        base,
                        status="degraded",
                        state=(
                            "operator_action"
                            if runtime.get("retryFailureClass") == "operator"
                            else "retrying"
                        ),
                        failureClass=str(
                            runtime.get("retryFailureClass", "transient"),
                        ),
                        actionRequired=(
                            runtime.get("retryFailureClass") == "operator"
                        ),
                        retryAt=retry_at,
                        nextRunInSeconds=max(
                            0, retry_at - fresh_scheduler_time(now),
                        ),
                        message=str(runtime.get("lastTransientError", "")),
                        protection=protection,
                    )
                elif not targets:
                    result = dict(
                        base,
                        state=(
                            "researching"
                            if policy.get("autopilotEnabled")
                            and universe_state.get("automaticSelection")
                            else "no_target"
                        ),
                        protection=protection,
                        message=(
                            "No candidate currently passes every entry gate; research continues"
                            if policy.get("autopilotEnabled")
                            and universe_state.get("automaticSelection")
                            else ""
                        ),
                    )
            if result is None:
                interval = int(policy["schedulerIntervalMinutes"]) * 60
                work_now = fresh_scheduler_time(now)
                since_work = work_now - int(numeric(runtime.get("lastWorkAt")))
                retry_at = int(numeric(runtime.get("retryAt")))
                retry_due = retry_at > 0 and retry_at <= work_now
                retry_target_id = str(runtime.get("retryTargetId", ""))
                if retry_due and runtime.get("retryScope") == "target":
                    due_targets = [
                        target for target in targets
                        if not retry_target_id or target["id"] == retry_target_id
                    ]
                else:
                    due_targets = due_automation_targets(
                        targets, runtime, interval, work_now,
                    )
                if (
                    since_work < AUTOMATION_GLOBAL_SPACING_SECONDS
                    and not retry_due
                ):
                    result = dict(
                        base,
                        state="throttled",
                        nextRunInSeconds=AUTOMATION_GLOBAL_SPACING_SECONDS - since_work,
                    )
                elif not due_targets:
                    result = dict(base, state="throttled", nextRunInSeconds=interval)
                else:
                    target = None
                    session = None
                    sessions = []
                    session_errors = []
                    for candidate in due_targets:
                        try:
                            candidate_session = market_session_gate(
                                execution_environment,
                                market=candidate["market"],
                                now=fresh_scheduler_time(now),
                            )
                            sessions.append(dict(
                                candidate_session,
                                market=candidate["market"],
                                targetId=candidate["id"],
                            ))
                            if candidate_session.get("passed"):
                                target = candidate
                                session = candidate_session
                                break
                        except Exception as error:
                            session_errors.append({
                                "market": candidate["market"],
                                "targetId": candidate["id"],
                                "message": str(error)[:240],
                            })
                    if target is None and session_errors:
                        failure_time = fresh_scheduler_time(now)
                        states = (
                            runtime.get("targets")
                            if isinstance(runtime.get("targets"), dict)
                            else {}
                        )
                        failed_target_id = str(
                            session_errors[0].get("targetId", ""),
                        )
                        failed_state = dict(states.get(failed_target_id, {}))
                        failure = record_target_failure(
                            policy,
                            runtime,
                            failed_state,
                            session_errors[0]["message"],
                            failure_time,
                        )
                        failed_state.update({
                            "status": (
                                "error"
                                if failure["failureClass"] == "hard"
                                else "degraded"
                            ),
                            "completedAt": failure_time,
                        })
                        if failed_target_id:
                            states[failed_target_id] = failed_state
                            runtime["targets"] = states
                        halted = failure["halted"]
                        result = dict(
                            base,
                            status="error" if failure["failureClass"] == "hard" else "degraded",
                            state=(
                                "halted"
                                if halted
                                else (
                                    "retrying"
                                    if failure["failureClass"] == "transient"
                                    else (
                                        "operator_action"
                                        if failure["failureClass"] == "operator"
                                        else "session_error"
                                    )
                                )
                            ),
                            sessions=sessions,
                            sessionErrors=session_errors,
                            **failure,
                        )
                    elif target is None:
                        result = dict(base, state="market_closed", sessions=sessions)
                    else:
                        states = runtime.get("targets") if isinstance(runtime.get("targets"), dict) else {}
                        state = dict(states.get(target["id"], {}))
                        state["attemptedAt"] = fresh_scheduler_time(now)
                        try:
                            market = target["market"]
                            snapshot = kis_snapshot(target["symbol"], market, "3M", execution_environment)
                            snapshot["language"] = target["language"]
                            price = numeric(snapshot.get("price"))
                            account = kis_account_summary(
                                execution_environment,
                                target["symbol"],
                                price,
                                "market" if market == "KRX" else "limit",
                                market,
                            )
                            account, ownership = planning_account_ownership(
                                account,
                                execution_environment,
                                market,
                                target["symbol"],
                                price,
                            )
                            allow_entry = bool(target.get("allowEntry", True)) and not (
                                execution_environment == "prod"
                                and bool(ownership.get("mixedWithManual"))
                            )
                            holding = next((
                                item for item in account.get("holdings", [])
                                if item.get("symbol") == target["symbol"]
                                and str(item.get("market") or market).upper() == market
                            ), {})
                            risk_now = fresh_scheduler_time(now)
                            position_risk = observe_position_risk(
                                execution_environment,
                                target["symbol"],
                                holding,
                                price,
                                policy,
                                risk_now,
                                directory=state_directory(),
                                market=market,
                            )
                            analysis = ({}) if position_risk.get("triggered") else analyze(
                                target["aiProvider"], target["analysisProfile"], snapshot, force=False,
                            )
                            plan_now = fresh_scheduler_time(risk_now)
                            plan = build_automation_plan({
                                "symbol": target["symbol"],
                                "market": market,
                                "allowEntry": allow_entry,
                                "dataMode": "kis",
                                "environment": execution_environment,
                                "strategy": target["strategy"],
                                "snapshot": {
                                    "name": snapshot.get("name"),
                                    "price": price,
                                    "currency": snapshot.get("currency"),
                                    "exchangeRate": numeric(snapshot.get("exchangeRate")),
                                    "bid": numeric(snapshot.get("bid")),
                                    "ask": numeric(snapshot.get("ask")),
                                    "updatedAt": int(numeric(snapshot.get("updatedAt"))),
                                    "marketSafety": snapshot.get("marketSafety") or {},
                                },
                                "analysis": scheduler_analysis_evidence(analysis),
                            }, now=plan_now, trusted_account=account, trusted_position_risk=position_risk)
                            shadow = apply_shadow_plan(plan, price, plan_now)
                            execution_result = {}
                            promotion_eligible = bool(shadow.get("promotion", {}).get("eligible"))
                            protective_exit = bool((plan.get("riskExit") or {}).get("triggered"))
                            entry_blocked = plan.get("side") == "buy" and not allow_entry
                            live_armed = execution_environment == "prod"
                            paper_autopilot = (
                                execution_environment == "paper"
                                and bool(policy.get("autopilotEnabled"))
                                and bool(universe_state.get("enabled"))
                            )
                            live_cycle = (
                                live_automation_cycle_status(
                                    policy,
                                    universe_state,
                                    configs,
                                    runtime,
                                    fresh_scheduler_time(plan_now),
                                )
                                if live_armed
                                else {"passed": True, "reasons": [], "session": {}}
                            )
                            live_eligible = bool(live_cycle.get("passed"))
                            auto_revoked = (
                                policy.get("schedulerMode") == "paper_auto"
                                and (
                                    (live_armed and not live_eligible)
                                    or (
                                        not protective_exit
                                        and not paper_autopilot
                                        and not promotion_eligible
                                    )
                                )
                            )
                            if auto_revoked:
                                if live_armed and not live_eligible:
                                    revoke_live_automation(
                                        (live_cycle.get("reasons") or ["live_session_invalid"])[0],
                                    )
                                else:
                                    with automation_lock():
                                        current = load_automation_policy()
                                        current["schedulerMode"] = "observe"
                                        save_automation_policy(current)
                                base.update({"mode": "observe", "autoExecution": False, "autoRevoked": True})
                                if live_armed and not live_eligible:
                                    base["liveRevoked"] = True
                                    base["halted"] = True
                                    base["liveCycle"] = live_cycle
                            if (
                                policy.get("schedulerMode") == "paper_auto"
                                and (paper_autopilot or promotion_eligible or protective_exit)
                                and not entry_blocked
                                and not auto_revoked
                                and plan.get("executionEligible")
                            ):
                                execution_result = execute_automation_plan({
                                    "planId": plan["planId"],
                                    "confirmation": (
                                        f"EXECUTE KIS LIVE {plan['planId']}"
                                        if live_armed
                                        else f"EXECUTE KIS PAPER {plan['planId']}"
                                    ),
                                })
                            state.update({
                                "status": "ok",
                                "completedAt": int(time.time()),
                                "planId": plan.get("planId", ""),
                                "decision": plan.get("decision", ""),
                                "failedGates": list(plan.get("failedGates") or []),
                                "executionId": execution_result.get("executionId", ""),
                                "market": market,
                                "allowEntry": allow_entry,
                                "managedPositionOwnership": ownership,
                                "retryAt": 0,
                                "retryFailureClass": "",
                                "transientFailures": 0,
                            })
                            runtime["lastWorkAt"] = fresh_scheduler_time(now)
                            reset_scheduler_failures(runtime)
                            result = dict(
                                base,
                                state=(
                                    "protective_exit_executed"
                                    if execution_result.get("brokerOrderSent") and protective_exit
                                    else ("auto_executed" if execution_result.get("brokerOrderSent") else "observed")
                                ),
                                brokerOrderSent=bool(execution_result.get("brokerOrderSent")),
                                target=target,
                                session=dict(session, market=market),
                                plan={
                                    "planId": plan.get("planId", ""),
                                    "decision": plan.get("decision", ""),
                                    "side": plan.get("side", "hold"),
                                    "allowEntry": allow_entry,
                                    "failedGates": list(plan.get("failedGates") or []),
                                    "riskExit": plan.get("riskExit", {}),
                                },
                                managedPositionOwnership=ownership,
                                shadow={
                                    "metrics": shadow.get("metrics", {}),
                                    "promotion": shadow.get("promotion", {}),
                                    "tradeApplied": bool(shadow.get("tradeApplied")),
                                },
                                execution=execution_result,
                            )
                        except Exception as error:
                            failure_time = fresh_scheduler_time(now)
                            failure = record_target_failure(
                                policy,
                                runtime,
                                state,
                                error,
                                failure_time,
                            )
                            state.update({
                                "status": (
                                    "error"
                                    if failure["failureClass"] == "hard"
                                    else "degraded"
                                ),
                                "completedAt": int(time.time()),
                                "message": str(error)[:240],
                            })
                            halted = failure["halted"]
                            result = dict(
                                base,
                                status=(
                                    "error"
                                    if failure["failureClass"] == "hard"
                                    else "degraded"
                                ),
                                state=(
                                    "halted"
                                    if halted
                                    else (
                                        "retrying"
                                        if failure["failureClass"] == "transient"
                                        else (
                                            "operator_action"
                                            if failure["failureClass"] == "operator"
                                            else "error"
                                        )
                                    )
                                ),
                                target=target,
                                **failure,
                            )
                        states[target["id"]] = state
                        runtime["targets"] = states
        completed_at = fresh_scheduler_time(now)
        result["updatedAt"] = completed_at
        runtime["lastRun"] = result
        runtime["updatedAt"] = completed_at
        save_automation_scheduler_runtime(runtime)
        return result
