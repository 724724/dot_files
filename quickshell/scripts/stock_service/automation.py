import fcntl
import hashlib
import json
import math
import os
import re
import time
from contextlib import contextmanager
from datetime import datetime
from zoneinfo import ZoneInfo

from .core import StockServiceError, numeric, state_directory
from .quant import (
    BACKTEST_STRATEGIES,
    demo_history_points,
    kis_history_points,
    normalized_history_points,
    run_backtest,
    technical_screen_metrics,
)
from .trading import kis_account_summary
from .automation_positions import observe_position_risk
from .automation_portfolio import portfolio_tail_risk
from .automation_costs import automation_transaction_costs


AUTOMATION_TIMEZONE = ZoneInfo("Asia/Seoul")
MARKET_DATA_FUTURE_SKEW_SECONDS = 5
LIVE_AUTO_SESSION_MAX_SECONDS = 8 * 60 * 60
LIVE_AUTO_SESSION_MIN_SECONDS = 15 * 60
STOCK_PROFILE_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "stock-news-profiles.json")
DEFAULT_AUTOMATION_POLICY = {
    "version": 23,
    "enabled": False,
    "halted": False,
    "haltReason": "",
    "haltClass": "",
    "haltedAt": 0,
    "haltIncidentId": "",
    "exitOnlyProtection": False,
    "executionMode": "dry_run",
    "paperOnly": True,
    "liveConsent": False,
    "schedulerEnabled": False,
    "schedulerMode": "observe",
    "autopilotEnabled": False,
    "liveSessionId": "",
    "liveSessionEnvironment": "",
    "liveSessionStartedAt": 0,
    "liveSessionExpiresAt": 0,
    "liveSessionTtlSeconds": LIVE_AUTO_SESSION_MAX_SECONDS,
    "schedulerIntervalMinutes": 30,
    "maxConsecutiveFailures": 3,
    "maxOrderValueKrw": 100000,
    "maxDailyNewExposureKrw": 200000,
    "maxOrdersPerDay": 2,
    "maxPositionPercent": 5,
    "maxSectorExposurePercent": 15,
    "maxCorrelationCoefficient": 0.85,
    "maxMarketParticipationPercent": 0.1,
    "maxBidAskSpreadBps": 20,
    "maxPendingOrderSeconds": 120,
    "maxRiskPerTradePercent": 0.25,
    "volatilityRiskMultiplier": 2,
    "cashReservePercent": 70,
    "maxDailyLossPercent": 0.5,
    "maxPortfolioDrawdownPercent": 2,
    "maxPortfolioVar95Percent": 2,
    "maxPortfolioCvar95Percent": 3,
    "maxStressLossPercent": 8,
    "maxSingleDayLossPercent": 5,
    "maxBacktestDrawdownPercent": 12,
    "cooldownMinutes": 240,
    "minTechnicalScore": 55,
    "minAiConfidence": 75,
    "minAgreementScore": 70,
    "maxAiDownProbability": 20,
    "minNewsQualityScore": 50,
    "minVerifiedDirectNews": 1,
    "maxBehaviorRiskScore": 65,
    "maxAnalysisAgeMinutes": 30,
    "maxMarketDataAgeSeconds": 30,
    "maxPlanAgeSeconds": 90,
    "maxPriceDriftPercent": 0.5,
    "maxPositionLossPercent": 3,
    "trailingActivationPercent": 5,
    "trailingStopPercent": 2,
    "krxCommissionBps": 1.5,
    "krxSellTaxBps": 15,
    "usCommissionBps": 25,
    "usSellFeeBps": 1,
    "assumedSlippageBps": 5,
    "requireAi": True,
    "requireTwoModels": True,
    "requireRobustBacktest": True,
    "notificationsEnabled": True,
}
AUTOMATION_POLICY_FIELDS = {
    "maxOrderValueKrw": (10000, 10000000),
    "maxDailyNewExposureKrw": (10000, 50000000),
    "maxOrdersPerDay": (1, 20),
    "maxPositionPercent": (1, 25),
    "maxSectorExposurePercent": (5, 50),
    "maxCorrelationCoefficient": (0.5, 0.99),
    "maxMarketParticipationPercent": (0.01, 1),
    "maxBidAskSpreadBps": (5, 100),
    "maxPendingOrderSeconds": (60, 600),
    "maxRiskPerTradePercent": (0.05, 2),
    "volatilityRiskMultiplier": (1, 5),
    "cashReservePercent": (20, 95),
    "maxDailyLossPercent": (0.1, 5),
    "maxPortfolioDrawdownPercent": (0.5, 15),
    "maxPortfolioVar95Percent": (0.25, 10),
    "maxPortfolioCvar95Percent": (0.5, 15),
    "maxStressLossPercent": (1, 25),
    "maxSingleDayLossPercent": (1, 20),
    "maxBacktestDrawdownPercent": (1, 30),
    "cooldownMinutes": (15, 1440),
    "minTechnicalScore": (20, 95),
    "minAiConfidence": (50, 95),
    "minAgreementScore": (50, 100),
    "maxAiDownProbability": (5, 45),
    "minNewsQualityScore": (20, 90),
    "minVerifiedDirectNews": (1, 5),
    "maxBehaviorRiskScore": (20, 90),
    "maxAnalysisAgeMinutes": (5, 120),
    "maxMarketDataAgeSeconds": (5, 120),
    "maxPlanAgeSeconds": (30, 300),
    "maxPriceDriftPercent": (0.1, 3),
    "maxPositionLossPercent": (0.5, 15),
    "trailingActivationPercent": (1, 30),
    "trailingStopPercent": (0.5, 15),
    "krxCommissionBps": (0, 100),
    "krxSellTaxBps": (0, 100),
    "usCommissionBps": (0, 100),
    "usSellFeeBps": (0, 20),
    "assumedSlippageBps": (0, 100),
    "schedulerIntervalMinutes": (15, 240),
    "maxConsecutiveFailures": (1, 10),
    "liveSessionTtlSeconds": (
        LIVE_AUTO_SESSION_MIN_SECONDS,
        LIVE_AUTO_SESSION_MAX_SECONDS,
    ),
}


def automation_policy_path():
    return os.path.join(state_directory(), "automation-policy.json")


def automation_plan_path():
    return os.path.join(state_directory(), "automation-plans.jsonl")


def automation_risk_path():
    return os.path.join(state_directory(), "automation-risk.json")


def clear_live_auto_session(policy):
    policy["liveSessionId"] = ""
    policy["liveSessionEnvironment"] = ""
    policy["liveSessionStartedAt"] = 0
    policy["liveSessionExpiresAt"] = 0
    return policy


def exit_only_protection_enabled(policy):
    return bool(
        policy.get("exitOnlyProtection")
        and policy.get("halted")
        and policy.get("haltClass") == "capital_loss"
        and policy.get("schedulerEnabled")
        and policy.get("executionMode") in ("paper", "live")
    )


def live_auto_session_status(policy, now=None, expected_environment="prod"):
    now = int(now if now is not None else time.time())
    session_id = str(policy.get("liveSessionId", "")).strip().lower()
    environment = str(policy.get("liveSessionEnvironment", "")).strip().lower()
    started_at = int(numeric(policy.get("liveSessionStartedAt")))
    expires_at = int(numeric(policy.get("liveSessionExpiresAt")))
    ttl = max(
        LIVE_AUTO_SESSION_MIN_SECONDS,
        min(
            LIVE_AUTO_SESSION_MAX_SECONDS,
            int(numeric(
                policy.get("liveSessionTtlSeconds"),
                LIVE_AUTO_SESSION_MAX_SECONDS,
            )),
        ),
    )
    reasons = []
    if not re.fullmatch(r"[0-9a-f]{32}", session_id):
        reasons.append("live_session_id_invalid")
    if environment != str(expected_environment).strip().lower():
        reasons.append("live_session_environment_mismatch")
    if started_at <= 0 or started_at > now + MARKET_DATA_FUTURE_SKEW_SECONDS:
        reasons.append("live_session_start_invalid")
    if expires_at <= now:
        reasons.append("live_session_expired")
    if expires_at <= started_at:
        reasons.append("live_session_expiry_invalid")
    if (
        started_at > 0
        and expires_at > started_at
        and expires_at - started_at > min(ttl, LIVE_AUTO_SESSION_MAX_SECONDS)
    ):
        reasons.append("live_session_ttl_exceeded")
    return {
        "valid": not reasons,
        "sessionId": session_id,
        "environment": environment,
        "startedAt": started_at,
        "expiresAt": expires_at,
        "expiresInSeconds": max(0, expires_at - now),
        "ttlSeconds": ttl,
        "reasons": reasons,
    }


def open_live_auto_session(policy, now=None):
    now = int(now if now is not None else time.time())
    result = dict(policy)
    ttl = max(
        LIVE_AUTO_SESSION_MIN_SECONDS,
        min(
            LIVE_AUTO_SESSION_MAX_SECONDS,
            int(numeric(
                result.get("liveSessionTtlSeconds"),
                LIVE_AUTO_SESSION_MAX_SECONDS,
            )),
        ),
    )
    expires_at = now + ttl
    if expires_at <= now:
        raise StockServiceError("A live automation session cannot be opened")
    result.update({
        "liveSessionId": os.urandom(16).hex(),
        "liveSessionEnvironment": "prod",
        "liveSessionStartedAt": now,
        "liveSessionExpiresAt": expires_at,
        "liveSessionTtlSeconds": ttl,
    })
    return result


@contextmanager
def automation_plan_lock():
    descriptor = os.open(automation_plan_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


@contextmanager
def automation_lock():
    descriptor = os.open(automation_policy_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def normalized_automation_policy(value):
    policy = dict(DEFAULT_AUTOMATION_POLICY)
    if isinstance(value, dict):
        for key in policy:
            if key in value:
                policy[key] = value[key]
    policy["enabled"] = bool(policy["enabled"])
    policy["halted"] = bool(policy["halted"])
    policy["haltReason"] = str(policy.get("haltReason", ""))[:240]
    policy["haltClass"] = str(policy.get("haltClass", ""))[:40]
    policy["haltedAt"] = max(0, int(numeric(policy.get("haltedAt"))))
    policy["haltIncidentId"] = str(policy.get("haltIncidentId", ""))[:64]
    policy["exitOnlyProtection"] = bool(
        policy.get("exitOnlyProtection")
    )
    policy["schedulerEnabled"] = bool(policy["schedulerEnabled"])
    policy["schedulerMode"] = "paper_auto" if policy.get("schedulerMode") == "paper_auto" else "observe"
    policy["version"] = DEFAULT_AUTOMATION_POLICY["version"]
    policy["liveConsent"] = bool(policy.get("liveConsent"))
    policy["autopilotEnabled"] = bool(policy.get("autopilotEnabled"))
    policy["liveSessionId"] = str(policy.get("liveSessionId", "")).strip().lower()[:64]
    policy["liveSessionEnvironment"] = (
        "prod" if str(policy.get("liveSessionEnvironment", "")).lower() == "prod" else ""
    )
    policy["liveSessionStartedAt"] = max(0, int(numeric(policy.get("liveSessionStartedAt"))))
    policy["liveSessionExpiresAt"] = max(0, int(numeric(policy.get("liveSessionExpiresAt"))))
    mode = policy.get("executionMode")
    policy["executionMode"] = mode if mode in ("paper", "live") else "dry_run"
    for key, (minimum, maximum) in AUTOMATION_POLICY_FIELDS.items():
        number = numeric(policy[key], DEFAULT_AUTOMATION_POLICY[key])
        policy[key] = max(minimum, min(maximum, number))
        if key in (
            "maxOrderValueKrw",
            "maxDailyNewExposureKrw",
            "maxOrdersPerDay",
            "maxPositionPercent",
            "cashReservePercent",
            "cooldownMinutes",
            "minTechnicalScore",
            "minAiConfidence",
            "minAgreementScore",
            "maxAiDownProbability",
            "minNewsQualityScore",
            "minVerifiedDirectNews",
            "maxBehaviorRiskScore",
            "maxAnalysisAgeMinutes",
            "maxMarketDataAgeSeconds",
            "maxPlanAgeSeconds",
            "schedulerIntervalMinutes",
            "maxConsecutiveFailures",
            "maxBidAskSpreadBps",
            "maxPendingOrderSeconds",
            "liveSessionTtlSeconds",
        ):
            policy[key] = int(policy[key])
    if policy["executionMode"] == "live" and not policy["liveConsent"]:
        policy["enabled"] = False
        policy["halted"] = True
        if not policy["haltReason"]:
            policy["haltReason"] = "Live automation consent was revoked"
        if not policy["haltClass"]:
            policy["haltClass"] = "live_consent"
        if not policy["haltedAt"]:
            policy["haltedAt"] = int(time.time())
        policy["exitOnlyProtection"] = False
        clear_live_auto_session(policy)
    if policy["executionMode"] != "live":
        clear_live_auto_session(policy)
    if policy["executionMode"] not in ("paper", "live") or not policy["enabled"] or policy["halted"]:
        policy["schedulerMode"] = "observe"
    live_session_valid = (
        policy["executionMode"] == "live"
        and live_auto_session_status(policy)["valid"]
    )
    if (
        not policy["enabled"]
        or policy["halted"]
        or not policy["schedulerEnabled"]
        or policy["schedulerMode"] != "paper_auto"
        or (
            policy["executionMode"] != "paper"
            and not live_session_valid
        )
    ):
        policy["autopilotEnabled"] = False
    policy["paperOnly"] = policy["executionMode"] != "live"
    for key in (
        "requireAi", "requireTwoModels", "requireRobustBacktest", "notificationsEnabled",
        "liveConsent", "autopilotEnabled",
    ):
        policy[key] = bool(policy[key])
    return policy


def load_automation_policy():
    try:
        with open(automation_policy_path(), encoding="utf-8") as handle:
            return normalized_automation_policy(json.load(handle))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return dict(DEFAULT_AUTOMATION_POLICY)


def save_automation_policy(policy):
    policy = normalized_automation_policy(policy)
    path = automation_policy_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(policy, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return policy


def update_automation_policy(patch):
    configurable = set(AUTOMATION_POLICY_FIELDS) | {
        "notificationsEnabled", "requireTwoModels", "liveConsent",
    }
    if not isinstance(patch, dict) or any(key not in configurable for key in patch):
        raise StockServiceError("Unsupported automation policy field")
    with automation_lock():
        policy = load_automation_policy()
        policy.update(patch)
        if (
            patch.get("liveConsent") is False
            and policy.get("executionMode") == "live"
        ):
            policy.update({
                "enabled": False,
                "halted": True,
                "haltReason": "Live automation consent was revoked",
                "haltClass": "live_consent",
                "haltedAt": int(time.time()),
                "haltIncidentId": os.urandom(8).hex(),
                "exitOnlyProtection": False,
                "executionMode": "paper",
                "schedulerMode": "observe",
                "autopilotEnabled": False,
            })
            clear_live_auto_session(policy)
        return save_automation_policy(policy)


def canonical_record_hash(value, excluded=()):
    payload = {key: item for key, item in value.items() if key not in set(excluded)}
    try:
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise StockServiceError("Automation record contains a non-canonical value") from error
    return hashlib.sha256(encoded).hexdigest()


def automation_plan_integrity_key(plan):
    return canonical_record_hash(plan, ("executionKey", "previousHash", "recordHash"))


def automation_plan_record_hash(plan):
    return canonical_record_hash(plan, ("recordHash",))


def automation_plan_audit_status():
    verified = 0
    legacy = 0
    invalid = 0
    first_error = None
    previous_hash = ""
    chain_started = False
    try:
        with open(automation_plan_path(), encoding="utf-8") as handle:
            lines = list(handle)
    except OSError:
        lines = []
    for index, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            plan = json.loads(line)
        except json.JSONDecodeError:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "invalid_json"}
            continue
        if not isinstance(plan, dict):
            invalid += 1
            first_error = first_error or {"line": index, "reason": "invalid_record"}
            continue
        record_hash = str(plan.get("recordHash", ""))
        if not record_hash:
            legacy += 1
            if chain_started:
                invalid += 1
                first_error = first_error or {"line": index, "reason": "missing_record_hash"}
            continue
        try:
            expected_hash = automation_plan_record_hash(plan)
        except StockServiceError:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "non_canonical_record"}
            expected_hash = record_hash
        if record_hash != expected_hash:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "record_hash_mismatch"}
        if str(plan.get("previousHash", "")) != previous_hash:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "chain_link_mismatch"}
        if numeric(plan.get("integrityVersion")) != 2:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "unsupported_integrity_version"}
        elif str(plan.get("executionKey", "")) != automation_plan_integrity_key(plan):
            invalid += 1
            first_error = first_error or {"line": index, "reason": "plan_integrity_mismatch"}
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


def append_automation_plan(plan):
    with automation_plan_lock():
        audit = automation_plan_audit_status()
        if not audit["healthy"]:
            raise StockServiceError("Automation plan journal integrity check failed")
        payload = dict(plan)
        payload.pop("previousHash", None)
        payload.pop("recordHash", None)
        payload["previousHash"] = audit["latestHash"]
        payload["recordHash"] = automation_plan_record_hash(payload)
        descriptor = os.open(automation_plan_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(descriptor, (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    return payload


def load_automation_plans(limit=500):
    items = []
    try:
        with open(automation_plan_path(), encoding="utf-8") as handle:
            for line in handle:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(item, dict):
                    items.append(item)
    except OSError:
        pass
    return items[-max(1, min(2000, int(limit))):]


def load_automation_risk():
    try:
        with open(automation_risk_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def save_automation_risk(value):
    path = automation_risk_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def automation_risk_snapshot(environment, total_evaluation, now=None, market="KRX"):
    now = int(now if now is not None else time.time())
    today = datetime.fromtimestamp(now, AUTOMATION_TIMEZONE).date().isoformat()
    total_evaluation = numeric(total_evaluation)
    state = load_automation_risk()
    market = str(market or "KRX").strip().upper()
    state_key = environment if market == "KRX" else f"{environment}:{market}"
    account = state.get(state_key, {}) if isinstance(state.get(state_key), dict) else {}
    if account.get("date") != today or numeric(account.get("dayStartEvaluation")) <= 0:
        account = {
            "date": today,
            "dayStartEvaluation": total_evaluation,
            "peakEvaluation": total_evaluation,
        }
    account["peakEvaluation"] = max(numeric(account.get("peakEvaluation")), total_evaluation)
    account["lastEvaluation"] = total_evaluation
    account["updatedAt"] = now
    start = numeric(account.get("dayStartEvaluation"))
    peak = numeric(account.get("peakEvaluation"))
    account["dailyReturnPercent"] = round((total_evaluation / start - 1) * 100, 3) if start > 0 else 0
    account["drawdownPercent"] = round((total_evaluation / peak - 1) * 100, 3) if peak > 0 else 0
    account["market"] = market
    state[state_key] = account
    save_automation_risk(state)
    return account


def automation_history(limit=50):
    items = list(reversed(load_automation_plans(limit)))
    today = datetime.now(AUTOMATION_TIMEZONE).date().isoformat()
    return {
        "status": "ok",
        "items": items,
        "counts": {
            "ready": sum(1 for item in items if item.get("decision") == "ready"),
            "blocked": sum(1 for item in items if item.get("decision") == "blocked"),
            "hold": sum(1 for item in items if item.get("decision") == "hold"),
            "today": sum(1 for item in items if item.get("date") == today),
        },
        "updatedAt": int(time.time()),
    }


def automation_status():
    history = automation_history(100)
    policy = load_automation_policy()
    return {
        "status": "ok",
        "policy": policy,
        "liveSession": live_auto_session_status(policy),
        "risk": load_automation_risk(),
        "history": history,
        "planAudit": automation_plan_audit_status(),
        "guarantees": {
            "noLossGuaranteed": False,
            "productionExecutionAvailable": True,
            "paperExecutionAvailable": True,
            "promotionGatedPaperAutoAvailable": True,
            "promotionGatedLiveAutoAvailable": True,
            "liveSessionSafetyAvailable": True,
            "portfolioTailRiskAvailable": True,
            "accountingReconciliationAvailable": True,
            "resilienceValidationAvailable": True,
            "stagedLiveReadinessAvailable": True,
            "onlineOperationsValidationAvailable": True,
            "tamperEvidentSoakEvidenceAvailable": True,
            "automaticFailureBudgetHaltAvailable": True,
            "featureImplementationComplete": True,
            "operationalReadinessRuntimeGated": True,
            "principle": "Preserve capital first; abstain whenever evidence or operational state is uncertain.",
        },
        "updatedAt": int(time.time()),
    }


def automation_control(action, payload=None):
    payload = payload if isinstance(payload, dict) else {}
    with automation_lock():
        policy = load_automation_policy()
        if action == "arm":
            if str(payload.get("confirmation", "")) != "ARM PAPER DRY RUN":
                raise StockServiceError("Arming requires ARM PAPER DRY RUN confirmation")
            policy["enabled"] = True
            policy["halted"] = False
            policy["haltReason"] = ""
            policy["haltClass"] = ""
            policy["haltedAt"] = 0
            policy["haltIncidentId"] = ""
            policy["exitOnlyProtection"] = False
            policy["executionMode"] = "dry_run"
            policy["schedulerMode"] = "observe"
            clear_live_auto_session(policy)
        elif action == "arm-paper":
            if str(payload.get("confirmation", "")) != "ARM KIS PAPER EXECUTION":
                raise StockServiceError("Arming requires ARM KIS PAPER EXECUTION confirmation")
            policy["enabled"] = True
            policy["halted"] = False
            policy["haltReason"] = ""
            policy["haltClass"] = ""
            policy["haltedAt"] = 0
            policy["haltIncidentId"] = ""
            policy["exitOnlyProtection"] = False
            policy["executionMode"] = "paper"
            policy["schedulerMode"] = "observe"
            clear_live_auto_session(policy)
        elif action == "arm-live":
            if str(payload.get("confirmation", "")) != "ARM KIS LIVE EXECUTION":
                raise StockServiceError("Arming requires ARM KIS LIVE EXECUTION confirmation")
            if not policy.get("liveConsent"):
                raise StockServiceError("Accept the live automation risk consent in Settings first")
            from .core import load_risk_policy
            if not load_risk_policy().get("productionEnabled"):
                raise StockServiceError("Unlock production trading in the global risk policy first")
            from .automation_live import automation_live_status
            from .automation_scheduler import load_automation_scheduler_runtime
            failures = int(numeric(load_automation_scheduler_runtime().get("consecutiveFailures")))
            if not automation_live_status(failures).get("productionAutomationEligible"):
                raise StockServiceError("Live automation is locked until every live-readiness gate passes")
            policy["enabled"] = True
            policy["halted"] = False
            policy["haltReason"] = ""
            policy["haltClass"] = ""
            policy["haltedAt"] = 0
            policy["haltIncidentId"] = ""
            policy["exitOnlyProtection"] = False
            policy["executionMode"] = "live"
            policy["schedulerMode"] = "observe"
            policy = open_live_auto_session(policy)
        elif action == "pause":
            policy["enabled"] = False
            policy["exitOnlyProtection"] = False
            policy["schedulerMode"] = "observe"
            policy["autopilotEnabled"] = False
            clear_live_auto_session(policy)
        elif action == "scheduler-enable":
            if str(payload.get("confirmation", "")) != "ENABLE OBSERVE SCHEDULER":
                raise StockServiceError("Scheduler requires ENABLE OBSERVE SCHEDULER confirmation")
            policy["schedulerEnabled"] = True
        elif action == "scheduler-disable":
            policy["schedulerEnabled"] = False
            policy["exitOnlyProtection"] = False
            policy["schedulerMode"] = "observe"
            if policy.get("executionMode") == "live":
                clear_live_auto_session(policy)
        elif action == "scheduler-auto-enable":
            live = policy.get("executionMode") == "live"
            required = "ENABLE PROMOTION-GATED LIVE AUTO" if live else "ENABLE PROMOTION-GATED PAPER AUTO"
            if str(payload.get("confirmation", "")) != required:
                raise StockServiceError("Automatic execution requires explicit confirmation")
            if not policy.get("enabled") or policy.get("halted") or policy.get("executionMode") not in ("paper", "live"):
                raise StockServiceError("Arm KIS paper or live execution before enabling automatic orders")
            from .automation_shadow import shadow_status
            from .automation_scheduler import load_automation_scheduler_runtime
            failures = int(numeric(load_automation_scheduler_runtime().get("consecutiveFailures")))
            promotion = shadow_status(failures).get("promotion", {})
            if not promotion.get("eligible"):
                raise StockServiceError("Automatic execution is locked until every promotion gate passes")
            if live:
                from .automation_live import automation_live_status
                if not automation_live_status(failures).get("productionAutomationEligible"):
                    raise StockServiceError("Automatic live execution is locked until live readiness is verified")
                if not live_auto_session_status(policy).get("valid"):
                    raise StockServiceError("Re-arm KIS live execution to open a fresh live session")
            policy["schedulerMode"] = "paper_auto"
            policy["schedulerEnabled"] = True
        elif action == "scheduler-auto-disable":
            policy["schedulerMode"] = "observe"
            if policy.get("executionMode") == "live":
                clear_live_auto_session(policy)
        elif action == "kill":
            policy["enabled"] = False
            policy["halted"] = True
            policy["haltReason"] = "Manual emergency stop"
            policy["haltClass"] = "manual"
            policy["haltedAt"] = int(time.time())
            policy["haltIncidentId"] = os.urandom(8).hex()
            policy["exitOnlyProtection"] = False
            policy["schedulerMode"] = "observe"
            policy["autopilotEnabled"] = False
            clear_live_auto_session(policy)
        elif action == "reset-kill":
            if str(payload.get("confirmation", "")) != "RESET PAPER KILL SWITCH":
                raise StockServiceError("Reset requires RESET PAPER KILL SWITCH confirmation")
            policy["enabled"] = False
            policy["halted"] = False
            policy["haltReason"] = ""
            policy["haltClass"] = ""
            policy["haltedAt"] = 0
            policy["haltIncidentId"] = ""
            policy["exitOnlyProtection"] = False
            policy["schedulerMode"] = "observe"
            clear_live_auto_session(policy)
        else:
            raise StockServiceError("Unsupported automation control action")
        save_automation_policy(policy)
    return automation_status()


def plan_gate(code, passed, message, value=None, threshold=None):
    result = {"code": code, "passed": bool(passed), "message": message}
    if value is not None:
        result["value"] = value
    if threshold is not None:
        result["threshold"] = threshold
    return result


def automation_account(payload, price, trusted_account=None):
    if isinstance(trusted_account, dict):
        return trusted_account
    mode = str(payload.get("dataMode", "demo"))
    environment = str(payload.get("environment", "paper"))
    symbol = str(payload.get("symbol", ""))
    market = str(payload.get("market", "KRX")).upper()
    if mode == "kis":
        return kis_account_summary(
            environment, symbol, price, "market" if market == "KRX" else "limit", market,
        )
    snapshot = payload.get("snapshot") if isinstance(payload.get("snapshot"), dict) else {}
    buying_power = numeric(snapshot.get("buyingPower"), 10000000)
    return {
        "status": "ok",
        "environment": "paper",
        "market": market,
        "currency": "KRW" if market == "KRX" else "USD",
        "exchangeRate": 1 if market == "KRX" else numeric(snapshot.get("exchangeRate"), 1350),
        "buyingPower": buying_power,
        "cash": buying_power,
        "totalEvaluation": buying_power,
        "holdingQuantity": 0,
        "sellableQuantity": 0,
        "stockEvaluation": 0,
    }


def automation_ai_evidence(payload):
    analysis = payload.get("analysis") if isinstance(payload.get("analysis"), dict) else {}
    agreement = analysis.get("ensembleAgreement") if isinstance(analysis.get("ensembleAgreement"), dict) else {}
    news = analysis.get("newsContext") if isinstance(analysis.get("newsContext"), dict) else {}
    behavior = analysis.get("behaviorContext") if isinstance(analysis.get("behaviorContext"), dict) else {}
    return {
        "available": analysis.get("status") == "ok",
        "stance": str(analysis.get("stance", "neutral")),
        "confidence": int(numeric(analysis.get("confidence"))),
        "agreementScore": int(numeric(agreement.get("agreementScore"))),
        "agreementStatus": str(agreement.get("status", "unavailable")),
        "modelCount": int(numeric(agreement.get("modelCount"), len(analysis.get("models") or []))),
        "directConflict": bool(agreement.get("directConflict")),
        "downProbability": int(numeric(analysis.get("downProbability"))),
        "newsStatus": str(news.get("status", "insufficient")),
        "newsQualityScore": int(numeric(news.get("qualityScore"))),
        "verifiedDirectNews": int(numeric(news.get("verifiedDirectCount"))),
        "independentNewsEvents": int(numeric(news.get("independentEventCount"))),
        "sourceQualityScore": int(numeric(news.get("sourceQualityScore"))),
        "behaviorStatus": str(behavior.get("status", "insufficient")),
        "behaviorRiskScore": int(numeric(behavior.get("riskPenalty"), 100)),
        "behaviorEvidenceConfidence": int(numeric(behavior.get("evidenceConfidence"))),
        "generatedAt": int(numeric(analysis.get("generatedAt"))),
    }


def volatility_risk_sizing(total_evaluation, technical, policy, exchange_rate=1):
    annualized = max(0, numeric(technical.get("annualizedVolatilityPct")))
    daily = annualized / math.sqrt(252) if annualized > 0 else 0
    hard_stop = numeric(policy["maxPositionLossPercent"])
    distance = max(hard_stop, daily * numeric(policy["volatilityRiskMultiplier"]))
    loss_budget = total_evaluation * numeric(policy["maxRiskPerTradePercent"]) / 100
    position_limit = loss_budget / (distance / 100) if distance > 0 else 0
    exchange_rate = max(0, numeric(exchange_rate))
    return {
        "available": annualized > 0,
        "annualizedVolatilityPercent": round(annualized, 2),
        "dailyVolatilityPercent": round(daily, 3),
        "riskDistancePercent": round(distance, 3),
        "lossBudget": round(loss_budget, 4),
        "positionLimit": round(position_limit, 4),
        "lossBudgetKrw": int(round(loss_budget * exchange_rate)),
        "positionLimitKrw": int(round(position_limit * exchange_rate)),
    }


def stock_primary_sector(symbol, market="KRX"):
    try:
        with open(STOCK_PROFILE_PATH, encoding="utf-8") as handle:
            profile = (json.load(handle).get("companies") or {}).get(f"{market}:{symbol}", {})
        sectors = profile.get("sectors") if isinstance(profile, dict) else []
        return str(sectors[0]) if isinstance(sectors, list) and sectors else ""
    except (OSError, TypeError, ValueError, json.JSONDecodeError):
        return ""


def portfolio_sector_risk(
    account, symbol, additional_notional, total_evaluation, policy, market="KRX", exchange_rate=1,
):
    market = str(market or "KRX").strip().upper()
    sector = stock_primary_sector(symbol, market)
    current = 0
    unknown = []
    for holding in account.get("holdings", []):
        evaluation = max(0, numeric(holding.get("evaluation")))
        if evaluation <= 0:
            continue
        holding_symbol = str(holding.get("symbol", "")).strip().upper()
        holding_market = str(holding.get("market", market)).strip().upper()
        holding_sector = stock_primary_sector(holding_symbol, holding_market)
        if not holding_sector:
            unknown.append(holding_symbol)
        elif holding_sector == sector:
            current += evaluation
    limit = total_evaluation * numeric(policy["maxSectorExposurePercent"]) / 100
    projected = current + max(0, numeric(additional_notional))
    exchange_rate = max(0, numeric(exchange_rate))
    return {
        "available": bool(sector) and not unknown,
        "sector": sector,
        "unknownSymbols": unknown,
        "currentExposure": round(current, 4),
        "additionalExposure": round(max(0, numeric(additional_notional)), 4),
        "projectedExposure": round(projected, 4),
        "exposureLimit": round(limit, 4),
        "currentExposureKrw": int(round(current * exchange_rate)),
        "additionalExposureKrw": int(round(max(0, numeric(additional_notional)) * exchange_rate)),
        "projectedExposureKrw": int(round(projected * exchange_rate)),
        "exposureLimitKrw": int(round(limit * exchange_rate)),
        "projectedExposurePercent": round(projected / total_evaluation * 100, 2) if total_evaluation > 0 else 0,
        "limitPercent": numeric(policy["maxSectorExposurePercent"]),
    }


def return_correlation(left_points, right_points, minimum_samples=40):
    left = {point["t"]: point["v"] for point in normalized_history_points(left_points)}
    right = {point["t"]: point["v"] for point in normalized_history_points(right_points)}
    common = sorted(set(left) & set(right))[-91:]
    if len(common) < minimum_samples + 1:
        return None
    left_returns = [left[common[index]] / left[common[index - 1]] - 1 for index in range(1, len(common))]
    right_returns = [right[common[index]] / right[common[index - 1]] - 1 for index in range(1, len(common))]
    left_mean = sum(left_returns) / len(left_returns)
    right_mean = sum(right_returns) / len(right_returns)
    covariance = sum(
        (left_returns[index] - left_mean) * (right_returns[index] - right_mean)
        for index in range(len(left_returns))
    )
    left_variance = sum((value - left_mean) ** 2 for value in left_returns)
    right_variance = sum((value - right_mean) ** 2 for value in right_returns)
    denominator = math.sqrt(left_variance * right_variance)
    if denominator <= 0:
        return None
    return max(-1, min(1, covariance / denominator))


def portfolio_correlation_risk(
    account, symbol, target_points, mode, environment, policy, market="KRX", exchange_rate=1,
):
    market = str(market or "KRX").strip().upper()
    exchange_rate = max(0, numeric(exchange_rate))
    pairs = []
    missing = []
    evaluated = []
    for holding in account.get("holdings", []):
        holding_symbol = str(holding.get("symbol", "")).strip().upper()
        holding_market = str(holding.get("market", market)).strip().upper()
        evaluation = max(0, numeric(
            holding.get("evaluation"),
            numeric(holding.get("quantity")) * numeric(holding.get("price")),
        ))
        if not holding_symbol or (
            holding_symbol == symbol and holding_market == market
        ) or evaluation <= 0:
            continue
        identity = f"{holding_market}:{holding_symbol}"
        evaluated.append(identity)
        try:
            history = (
                kis_history_points(environment, holding_symbol, 90, holding_market)
                if mode == "kis"
                else demo_history_points(holding_symbol, holding_market, 90)
            )
            correlation = return_correlation(target_points, history)
        except (OSError, TypeError, ValueError, StockServiceError):
            correlation = None
        if correlation is None:
            missing.append(identity)
            continue
        pairs.append({
            "symbol": holding_symbol,
            "market": holding_market,
            "key": identity,
            "correlation": round(correlation, 4),
            "evaluationKrw": int(round(evaluation * exchange_rate)),
        })
    strongest = max(pairs, key=lambda item: item["correlation"]) if pairs else {}
    maximum = numeric(strongest.get("correlation"))
    return {
        "available": not missing,
        "evaluatedSymbols": sorted(evaluated),
        "missingSymbols": sorted(missing),
        "pairs": sorted(pairs, key=lambda item: item["correlation"], reverse=True),
        "strongestSymbol": str(strongest.get("symbol", "")),
        "maxCorrelation": round(maximum, 4),
        "limit": numeric(policy["maxCorrelationCoefficient"]),
        "passed": not missing and maximum <= numeric(policy["maxCorrelationCoefficient"]),
    }


def liquidity_risk(points, order_notional, policy, minimum_samples=15, exchange_rate=1):
    turnovers = sorted(
        numeric(point.get("v")) * numeric(point.get("volume"))
        for point in points[-20:]
        if numeric(point.get("v")) > 0 and numeric(point.get("volume")) > 0
    )
    available = len(turnovers) >= minimum_samples
    if available:
        middle = len(turnovers) // 2
        median_turnover = (
            turnovers[middle]
            if len(turnovers) % 2
            else (turnovers[middle - 1] + turnovers[middle]) / 2
        )
    else:
        median_turnover = 0
    limit = numeric(policy["maxMarketParticipationPercent"])
    capacity = median_turnover * limit / 100
    participation = numeric(order_notional) / median_turnover * 100 if median_turnover > 0 else 0
    exchange_rate = max(0, numeric(exchange_rate))
    return {
        "available": available,
        "sampleSessions": len(turnovers),
        "medianDailyTurnover": round(median_turnover, 4),
        "orderCapacity": round(capacity, 4),
        "medianDailyTurnoverKrw": int(round(median_turnover * exchange_rate)),
        "orderCapacityKrw": int(round(capacity * exchange_rate)),
        "orderParticipationPercent": round(participation, 4),
        "limitPercent": limit,
        "passed": available and capacity > 0 and participation <= limit,
    }


def daily_automation_usage(plans, now):
    today = datetime.fromtimestamp(now, AUTOMATION_TIMEZONE).date().isoformat()
    ready = [item for item in plans if item.get("date") == today and item.get("decision") == "ready"]
    strategy_ready = [
        item for item in ready
        if not bool((item.get("riskExit") or {}).get("triggered"))
    ]
    return {
        "orders": len(ready),
        "strategyOrders": len(strategy_ready),
        "protectiveExits": len(ready) - len(strategy_ready),
        "buyOrders": sum(1 for item in ready if item.get("side") == "buy"),
        "newExposureKrw": int(sum(
            numeric(item.get("estimatedNotionalKrw"), item.get("estimatedNotional"))
            for item in ready
            if item.get("side") == "buy"
        )),
    }


def build_automation_plan(payload, now=None, trusted_account=None, trusted_position_risk=None):
    if not isinstance(payload, dict):
        raise StockServiceError("Automation plan payload must be an object")
    now = int(now if now is not None else time.time())
    policy = load_automation_policy()
    symbol = str(payload.get("symbol", "")).strip().upper()
    market = str(payload.get("market", "KRX")).strip().upper()
    mode = str(payload.get("dataMode", "demo")).lower()
    environment = str(payload.get("environment", "paper")).lower()
    strategy = str(payload.get("strategy", "trend"))
    allow_entry = bool(payload.get("allowEntry", True))
    snapshot = payload.get("snapshot") if isinstance(payload.get("snapshot"), dict) else {}
    price = numeric(snapshot.get("price"))
    snapshot_updated_at = int(numeric(snapshot.get("updatedAt")))
    snapshot_age_seconds = now - snapshot_updated_at if snapshot_updated_at > 0 else 10 ** 9
    market_safety = snapshot.get("marketSafety") if isinstance(snapshot.get("marketSafety"), dict) else {}
    market_safety_checked_at = int(numeric(market_safety.get("checkedAt")))
    market_safety_age_seconds = (
        now - market_safety_checked_at if market_safety_checked_at > 0 else 10 ** 9
    )
    valid_symbol = (
        bool(re.fullmatch(r"\d{6}", symbol))
        if market == "KRX"
        else market in ("NASDAQ", "NYSE") and bool(re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol))
    )
    if not valid_symbol:
        raise StockServiceError("Automation symbol or market is invalid")
    if mode not in ("demo", "kis") or environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported automation data source")
    if strategy not in BACKTEST_STRATEGIES:
        raise StockServiceError("Unsupported automation strategy")
    if price <= 0:
        raise StockServiceError("A current positive price is required")
    live_armed = policy["executionMode"] == "live"
    if environment != "paper" and not live_armed:
        raise StockServiceError("Automation is hard-locked to paper accounts while live execution is not armed")
    if live_armed:
        # An armed live policy always plans against the production account so
        # sizing and exposure checks reflect the money that would move.
        environment = "prod"
        payload = dict(payload, environment="prod")

    account = automation_account(payload, price, trusted_account)
    expected_currency = "KRW" if market == "KRX" else "USD"
    account_market = str(account.get("market", market)).strip().upper()
    currency = str(account.get("currency") or ("KRW" if market == "KRX" else "USD"))
    if account_market != market:
        raise StockServiceError("The KIS account snapshot belongs to a different market")
    if currency.upper() != expected_currency:
        raise StockServiceError("The KIS account currency does not match the selected market")
    exchange_rate = 1 if market == "KRX" else numeric(
        account.get("exchangeRate"), snapshot.get("exchangeRate")
    )
    if market != "KRX" and exchange_rate <= 0:
        raise StockServiceError("The USD/KRW exchange rate is unavailable")
    total_evaluation = numeric(account.get("totalEvaluation")) or (
        numeric(account.get("cash")) + numeric(account.get("stockEvaluation"))
    )
    if total_evaluation <= 0:
        raise StockServiceError("Account evaluation is unavailable")
    total_evaluation_krw = total_evaluation * exchange_rate
    risk = automation_risk_snapshot(environment, total_evaluation_krw, now, market)
    current_holding = next((
        item for item in account.get("holdings", [])
        if item.get("symbol") == symbol
        and str(item.get("market", market)).upper() == market
    ), {})
    position_risk = trusted_position_risk if isinstance(trusted_position_risk, dict) else (
        observe_position_risk(
            environment,
            symbol,
            current_holding,
            price,
            policy,
            now,
            state_directory(),
            market,
        ) if mode == "kis" else {"triggered": False, "reason": ""}
    )
    protective_exit = bool(position_risk.get("triggered"))
    exit_only_protection = (
        protective_exit and exit_only_protection_enabled(policy)
    )
    history_adjusted = mode != "kis"
    transaction_costs = automation_transaction_costs(market, policy)
    if protective_exit:
        technical = {"score": 0, "stance": "risk_exit", "signalStrength": 0}
        backtest = {"status": "skipped", "walkForward": {"status": "risk_exit"}}
    else:
        if mode == "kis":
            points = kis_history_points(environment, symbol, 260, market)
            history_adjusted = True
        else:
            points = demo_history_points(symbol, market)
        technical = technical_screen_metrics(normalized_history_points(points))
        backtest = run_backtest(
            symbol,
            market,
            mode,
            environment,
            strategy,
            transaction_costs["commissionBps"],
            transaction_costs["slippageBps"],
            transaction_costs["sellTaxBps"],
        )
    ai = automation_ai_evidence(payload)
    analysis_age = now - ai["generatedAt"] if ai["generatedAt"] > 0 else 10 ** 9
    score = int(numeric(technical.get("score")))
    threshold = int(policy["minTechnicalScore"])
    side = "sell" if protective_exit else (
        "buy" if score >= threshold else ("sell" if score <= -threshold else "hold")
    )
    expected_stance = "bullish" if side == "buy" else ("bearish" if side == "sell" else "neutral")
    validation = backtest.get("walkForward") if isinstance(backtest.get("walkForward"), dict) else {}
    plans = load_automation_plans(1000)
    if policy["executionMode"] in ("paper", "live"):
        from .automation_execution import execution_usage, load_execution_records
        execution_records = load_execution_records()
        usage = execution_usage(now)
        latest_same_side = next((
            item for item in reversed(execution_records)
            if item.get("symbol") == symbol
            and str(item.get("market", "KRX")).upper() == market
            and str(item.get("environment", "paper")).lower() == environment
            and item.get("side") == side
            and str(item.get("brokerState") or item.get("state"))
            not in ("rejected", "canceled", "preflight_failed")
        ), None)
        latest_protective_exit = next((
            item for item in reversed(execution_records)
            if side == "buy"
            and item.get("symbol") == symbol
            and str(item.get("market", "KRX")).upper() == market
            and str(item.get("environment", "paper")).lower() == environment
            and item.get("side") == "sell"
            and bool(item.get("protectiveExit"))
            and str(item.get("brokerState") or item.get("state"))
            not in ("rejected", "canceled", "preflight_failed")
        ), None)
    else:
        usage = daily_automation_usage(plans, now)
        latest_same_side = next((
            item for item in reversed(plans)
            if item.get("symbol") == symbol
            and str(item.get("market", "KRX")).upper() == market
            and item.get("side") == side and item.get("decision") == "ready"
        ), None)
        latest_protective_exit = next((
            item for item in reversed(plans)
            if side == "buy"
            and item.get("symbol") == symbol
            and str(item.get("market", "KRX")).upper() == market
            and item.get("side") == "sell"
            and item.get("decision") == "ready"
            and bool((item.get("riskExit") or {}).get("triggered"))
        ), None)
    cooldown_seconds = int(policy["cooldownMinutes"]) * 60
    same_side_timestamp = (
        numeric(
            latest_same_side.get("createdAt"),
            numeric(latest_same_side.get("timestamp")),
        )
        if latest_same_side else 0
    )
    protective_exit_timestamp = (
        numeric(
            latest_protective_exit.get("createdAt"),
            numeric(latest_protective_exit.get("timestamp")),
        )
        if latest_protective_exit else 0
    )
    latest_timestamp = max(same_side_timestamp, protective_exit_timestamp)
    cooldown_ready = latest_timestamp <= 0 or now - int(latest_timestamp) >= cooldown_seconds
    cooldown_until = int(latest_timestamp) + cooldown_seconds if latest_timestamp > 0 else 0
    gates = [
        plan_gate(
            "paper_only",
            environment == ("prod" if live_armed else "paper"),
            "Verified production account with standing risk consent" if live_armed else "Paper account only",
        ),
        plan_gate(
            "execution_mode",
            policy["executionMode"] in ("dry_run", "paper", "live"),
            "Dry Run records a hypothetical plan" if policy["executionMode"] == "dry_run"
            else ("KIS live execution is explicitly armed" if live_armed
                  else "KIS paper execution is explicitly armed"),
        ),
        plan_gate(
            "armed",
            policy["enabled"] and not policy["halted"]
            or exit_only_protection,
            "KIS live automation is armed" if live_armed
            else ("KIS paper automation is armed" if policy["executionMode"] == "paper" else "Dry Run automation is armed"),
        ),
        plan_gate(
            "market_data_freshness",
            snapshot_updated_at > 0
            and -MARKET_DATA_FUTURE_SKEW_SECONDS <= snapshot_age_seconds
            <= int(policy["maxMarketDataAgeSeconds"]),
            "Market data is inside the freshness window",
            max(0, snapshot_age_seconds),
            policy["maxMarketDataAgeSeconds"],
        ),
        plan_gate(
            "market_safety_freshness",
            mode != "kis" or market_safety_checked_at > 0
            and -MARKET_DATA_FUTURE_SKEW_SECONDS <= market_safety_age_seconds
            <= int(policy["maxMarketDataAgeSeconds"]),
            "Market safety status is inside the freshness window",
            max(0, market_safety_age_seconds),
            policy["maxMarketDataAgeSeconds"],
        ),
        plan_gate(
            "market_status",
            mode != "kis" or bool(market_safety.get("available")) and bool(market_safety.get("tradable")),
            "The security is in a normal tradable state",
        ),
        plan_gate(
            "vi_clear",
            mode != "kis" or market != "KRX"
            or bool(market_safety.get("viAvailable")) and not bool(market_safety.get("viActive")),
            "No volatility interruption is active",
        ),
        plan_gate(
            "price_limit_clear",
            mode != "kis" or market != "KRX"
            or not bool(market_safety.get("atUpperLimit")) and not bool(market_safety.get("atLowerLimit")),
            "The price is away from its daily limits",
        ),
        plan_gate(
            "instrument_restrictions",
            protective_exit or mode != "kis" or not bool(market_safety.get("restricted")),
            "No caution, warning, managed, overheated, or liquidation flag is active",
        ),
        plan_gate(
            "corporate_action_adjustment",
            protective_exit or history_adjusted,
            "Historical prices are adjusted for corporate actions",
        ),
    ]
    gates.append(
        plan_gate("protective_exit", True, "Position loss protection requires a full paper exit")
        if protective_exit
        else plan_gate("technical", side != "hold", "Technical score clears the abstention band", score, threshold)
    )
    if side == "buy":
        gates.append(plan_gate(
            "candidate_selected",
            allow_entry,
            "The candidate is selected for autonomous entry",
        ))
    if policy["executionMode"] in ("paper", "live"):
        gates.append(plan_gate("kis_data", mode == "kis", "Live KIS market data is required for execution"))
    if policy["requireAi"] and not protective_exit:
        gates.extend([
            plan_gate("ai_available", ai["available"], "Fresh AI scenario is available"),
            plan_gate("ai_freshness", 0 <= analysis_age <= policy["maxAnalysisAgeMinutes"] * 60,
                      "AI scenario is inside the freshness window",
                      max(0, int(analysis_age / 60)), policy["maxAnalysisAgeMinutes"]),
            plan_gate("ai_confidence", ai["confidence"] >= policy["minAiConfidence"],
                      "AI confidence clears the quality floor", ai["confidence"], policy["minAiConfidence"]),
            plan_gate("ai_agreement", ai["agreementScore"] >= policy["minAgreementScore"] and not ai["directConflict"],
                      "AI providers do not conflict", ai["agreementScore"], policy["minAgreementScore"]),
            plan_gate("ai_models", not policy["requireTwoModels"] or ai["modelCount"] >= 2,
                      "Two-model confirmation is present", ai["modelCount"], 2),
            plan_gate("signal_alignment", side != "hold" and ai["stance"] == expected_stance,
                      "Technical and AI directions agree"),
            plan_gate("ai_tail_risk", side != "buy" or ai["downProbability"] <= policy["maxAiDownProbability"],
                      "AI downside probability stays below the buy limit",
                      ai["downProbability"], policy["maxAiDownProbability"]),
            plan_gate("news_status", side != "buy" or ai["newsStatus"] in ("limited", "usable"),
                      "News evidence passed relevance validation", ai["newsStatus"], "limited_or_usable"),
            plan_gate("news_quality", side != "buy" or ai["newsQualityScore"] >= policy["minNewsQualityScore"],
                      "Source-adjusted news quality clears the entry floor",
                      ai["newsQualityScore"], policy["minNewsQualityScore"]),
            plan_gate("verified_direct_news", side != "buy" or ai["verifiedDirectNews"] >= policy["minVerifiedDirectNews"],
                      "At least one reliable company-specific event supports entry",
                      ai["verifiedDirectNews"], policy["minVerifiedDirectNews"]),
            plan_gate("behavior_status", side != "buy" or ai["behaviorStatus"] in ("limited", "usable"),
                      "Behavioral evidence passed relevance and recency validation",
                      ai["behaviorStatus"], "limited_or_usable"),
            plan_gate("behavior_risk", side != "buy" or ai["behaviorRiskScore"] <= policy["maxBehaviorRiskScore"],
                      "Attention, crowding, and overreaction risk stay below the entry limit",
                      ai["behaviorRiskScore"], policy["maxBehaviorRiskScore"]),
        ])
    if not protective_exit:
        robust = validation.get("status") == "robust"
        gates.extend([
            plan_gate("walk_forward", (not policy["requireRobustBacktest"]) or robust,
                      "Walk-forward validation is robust"),
            plan_gate("oos_edge", numeric(validation.get("oosReturnPct")) > 0 and numeric(validation.get("excessReturnPct")) > 0,
                      "Out-of-sample return and excess return are positive"),
            plan_gate("backtest_drawdown", abs(numeric(validation.get("maxDrawdownPct"))) <= policy["maxBacktestDrawdownPercent"],
                      "Backtest drawdown stays inside the research limit",
                      abs(numeric(validation.get("maxDrawdownPct"))), policy["maxBacktestDrawdownPercent"]),
            plan_gate("daily_loss", side != "buy" or numeric(risk.get("dailyReturnPercent")) > -numeric(policy["maxDailyLossPercent"]),
                      "Daily loss circuit breaker is clear",
                      numeric(risk.get("dailyReturnPercent")), -numeric(policy["maxDailyLossPercent"])),
            plan_gate("portfolio_drawdown", side != "buy" or numeric(risk.get("drawdownPercent")) > -numeric(policy["maxPortfolioDrawdownPercent"]),
                      "Portfolio drawdown circuit breaker is clear",
                      numeric(risk.get("drawdownPercent")), -numeric(policy["maxPortfolioDrawdownPercent"])),
            plan_gate("daily_orders", side != "buy" or usage["buyOrders"] < policy["maxOrdersPerDay"],
                      "Daily entry order count is below the limit", usage["buyOrders"], policy["maxOrdersPerDay"]),
            plan_gate("cooldown", cooldown_ready, "Symbol re-entry cooldown has elapsed"),
        ])

    buying_power = numeric(account.get("buyingPower"), account.get("cash"))
    holding_quantity = int(numeric(account.get("holdingQuantity")))
    sellable_quantity = int(numeric(account.get("sellableQuantity")))
    position_value = holding_quantity * price
    position_limit = total_evaluation * numeric(policy["maxPositionPercent"]) / 100
    cash_reserve = total_evaluation * numeric(policy["cashReservePercent"]) / 100
    daily_exposure_left_krw = max(
        0, numeric(policy["maxDailyNewExposureKrw"]) - usage["newExposureKrw"],
    )
    daily_exposure_left = daily_exposure_left_krw / exchange_rate
    max_order_value = numeric(policy["maxOrderValueKrw"]) / exchange_rate
    risk_sizing = (
        volatility_risk_sizing(total_evaluation, technical, policy, exchange_rate)
        if not protective_exit else {}
    )
    sector_risk = (
        portfolio_sector_risk(
            account, symbol, 0, total_evaluation, policy, market, exchange_rate,
        )
        if not protective_exit else {}
    )
    correlation_risk = {}
    liquidity = (
        liquidity_risk(points, 0, policy, exchange_rate=exchange_rate)
        if not protective_exit else {}
    )
    if side == "buy":
        correlation_risk = portfolio_correlation_risk(
            account, symbol, points, mode, environment, policy, market, exchange_rate,
        )
        sector_capacity = (
            numeric(sector_risk.get("exposureLimit"))
            - numeric(sector_risk.get("currentExposure"))
        )
        budget = max(0, min(
            max_order_value,
            daily_exposure_left,
            position_limit - position_value,
            numeric(risk_sizing.get("positionLimit")) - position_value,
            sector_capacity,
            numeric(liquidity.get("orderCapacity")),
            buying_power - cash_reserve,
        ))
        quantity = int(math.floor(budget / price))
        sector_risk = portfolio_sector_risk(
            account, symbol, quantity * price, total_evaluation, policy, market, exchange_rate,
        )
        liquidity = liquidity_risk(
            points, quantity * price, policy, exchange_rate=exchange_rate,
        )
        gates.extend([
            plan_gate(
                "sector_data",
                bool(sector_risk.get("available")),
                "Every holding has sector classification data",
            ),
            plan_gate(
                "sector_concentration",
                bool(sector_risk.get("available")) and sector_capacity >= price,
                "Projected sector exposure stays inside the portfolio limit",
                sector_risk.get("projectedExposurePercent", 0),
                policy["maxSectorExposurePercent"],
            ),
        ])
        gates.extend([
            plan_gate(
                "liquidity_data",
                bool(liquidity.get("available")),
                "Recent market turnover is available for liquidity sizing",
            ),
            plan_gate(
                "market_participation",
                bool(liquidity.get("available"))
                and numeric(liquidity.get("orderCapacity")) >= price
                and bool(liquidity.get("passed")),
                "Order size stays below the market participation limit",
                liquidity.get("orderParticipationPercent", 0),
                policy["maxMarketParticipationPercent"],
            ),
        ])
        gates.extend([
            plan_gate(
                "correlation_data",
                bool(correlation_risk.get("available")),
                "Return correlation data is available for every holding",
            ),
            plan_gate(
                "portfolio_correlation",
                bool(correlation_risk.get("passed")),
                "No holding exceeds the return correlation limit",
                correlation_risk.get("maxCorrelation", 0),
                policy["maxCorrelationCoefficient"],
            ),
        ])
        gates.append(plan_gate(
            "volatility_data",
            bool(risk_sizing.get("available")),
            "Recent volatility evidence is available for position sizing",
        ))
        gates.append(plan_gate(
            "risk_sizing",
            quantity > 0,
            "Volatility-adjusted loss budget allows at least one share",
            int(round(max(0, budget) * exchange_rate)),
            int(risk_sizing.get("positionLimitKrw", 0)),
        ))
    elif side == "sell":
        quantity = sellable_quantity
        gates.append(plan_gate("sizing", quantity > 0, "A sellable paper position exists"))
    else:
        quantity = 0
    estimated_notional = round(quantity * price, 8)
    estimated_notional_krw = int(round(estimated_notional * exchange_rate))
    tail_risk = {}
    if side == "buy" and not protective_exit:
        tail_risk = portfolio_tail_risk(
            account,
            symbol,
            points,
            estimated_notional,
            total_evaluation,
            mode,
            environment,
            policy,
            market=market,
        )
        gates.extend([
            plan_gate(
                "portfolio_tail_data",
                bool(tail_risk.get("available")),
                "Portfolio tail-risk history is complete",
            ),
            plan_gate(
                "portfolio_var",
                bool(tail_risk.get("available"))
                and numeric(tail_risk.get("var95Percent")) <= numeric(policy["maxPortfolioVar95Percent"]),
                "Portfolio 95% historical VaR stays inside the limit",
                tail_risk.get("var95Percent", 0),
                policy["maxPortfolioVar95Percent"],
            ),
            plan_gate(
                "portfolio_cvar",
                bool(tail_risk.get("available"))
                and numeric(tail_risk.get("cvar95Percent")) <= numeric(policy["maxPortfolioCvar95Percent"]),
                "Portfolio expected shortfall stays inside the limit",
                tail_risk.get("cvar95Percent", 0),
                policy["maxPortfolioCvar95Percent"],
            ),
            plan_gate(
                "portfolio_stress",
                bool(tail_risk.get("available"))
                and numeric(tail_risk.get("stressLossPercent")) <= numeric(policy["maxStressLossPercent"])
                and numeric(tail_risk.get("worstDayPercent")) <= numeric(policy["maxSingleDayLossPercent"]),
                "Portfolio stress and single-day loss stay inside the limits",
                tail_risk.get("stressLossPercent", 0),
                policy["maxStressLossPercent"],
            ),
        ])
    all_passed = all(gate["passed"] for gate in gates)
    decision = "hold" if side == "hold" else ("ready" if all_passed else "blocked")
    created = datetime.fromtimestamp(now, AUTOMATION_TIMEZONE)
    plan = {
        "kind": "plan",
        "status": "ok",
        "planId": os.urandom(8).hex(),
        "createdAt": now,
        "date": created.date().isoformat(),
        "symbol": symbol,
        "market": market,
        "currency": currency,
        "exchangeRate": exchange_rate,
        "dataMode": mode,
        "environment": environment,
        "executionMode": "dry_run",
        "decision": decision,
        "side": side,
        "quantity": quantity,
        "price": price,
        "marketData": {
            "updatedAt": snapshot_updated_at,
            "ageSeconds": max(0, snapshot_age_seconds),
            "maxAgeSeconds": policy["maxMarketDataAgeSeconds"],
        },
        "marketSafety": market_safety,
        "marketSafetyAgeSeconds": max(0, market_safety_age_seconds),
        "historyAdjustedForCorporateActions": history_adjusted,
        "estimatedNotional": estimated_notional,
        "estimatedNotionalKrw": estimated_notional_krw,
        "transactionCosts": transaction_costs,
        "strategy": strategy,
        "technical": technical,
        "ai": ai,
        "validation": {
            "status": validation.get("status", ""),
            "oosReturnPct": numeric(validation.get("oosReturnPct")),
            "excessReturnPct": numeric(validation.get("excessReturnPct")),
            "maxDrawdownPct": numeric(validation.get("maxDrawdownPct")),
            "sharpe": numeric(validation.get("sharpe")),
        },
        "risk": risk,
        "riskSizing": risk_sizing,
        "sectorRisk": sector_risk,
        "correlationRisk": correlation_risk,
        "liquidityRisk": liquidity,
        "portfolioTailRisk": tail_risk,
        "riskExit": position_risk,
        "account": {
            "totalEvaluation": total_evaluation,
            "totalEvaluationKrw": int(round(total_evaluation_krw)),
            "buyingPower": buying_power,
            "holdingQuantity": holding_quantity,
            "sellableQuantity": sellable_quantity,
            "positionLimit": round(position_limit, 8),
            "positionLimitKrw": int(round(position_limit * exchange_rate)),
            "cashReserve": round(cash_reserve, 8),
            "cashReserveKrw": int(round(cash_reserve * exchange_rate)),
        },
        "dailyUsage": usage,
        "reentryCooldown": {
            "active": not cooldown_ready,
            "until": cooldown_until,
            "remainingSeconds": max(0, cooldown_until - now),
            "reason": (
                "protective_exit"
                if protective_exit_timestamp >= same_side_timestamp
                and protective_exit_timestamp > 0
                else ("duplicate_side" if latest_timestamp > 0 else "")
            ),
        },
        "gates": gates,
        "failedGates": [gate["code"] for gate in gates if not gate["passed"]],
        "brokerOrderSent": False,
        "policy": policy,
        "principle": "Preserve capital first. If any required evidence is missing, abstain.",
        "integrityVersion": 2,
        "journalVersion": 1,
    }
    plan["executionMode"] = policy["executionMode"]
    plan["executionEligible"] = decision == "ready" and policy["executionMode"] in ("paper", "live")
    plan["executionKey"] = automation_plan_integrity_key(plan)
    return append_automation_plan(plan)
