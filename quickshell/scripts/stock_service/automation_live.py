import fcntl
import hashlib
import json
import os
import time
from contextlib import contextmanager

from .automation_accounting import automation_accounting_status
from .automation_resilience import automation_resilience_status
from .automation_shadow import shadow_status
from .core import StockServiceError, credential_status, load_risk_policy, numeric, state_directory, trade_activity


LIVE_CANARY_FILLS_REQUIRED = 10
LIVE_CANARY_MAX_NOTIONAL_KRW = 100_000


def automation_live_path():
    return os.path.join(state_directory(), "automation-live-readiness.json")


@contextmanager
def automation_live_lock():
    descriptor = os.open(automation_live_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def state_hash(value):
    payload = dict(value)
    payload.pop("stateHash", None)
    return hashlib.sha256(json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode()).hexdigest()


def default_live_state():
    return {"version": 1, "stage": "locked", "updatedAt": 0}


def load_live_state():
    try:
        with open(automation_live_path(), encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return default_live_state(), True
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_live_state(), False
    return state, isinstance(state, dict) and state.get("stateHash") == state_hash(state)


def save_live_state(state):
    state = dict(state)
    state["stateHash"] = state_hash(state)
    path = automation_live_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return state


def live_readiness_evidence(scheduler_failures=0):
    from .automation_execution import automation_execution_status
    from .automation_operations import operations_part1_status

    shadow = shadow_status(scheduler_failures).get("promotion", {})
    accounting = automation_accounting_status("paper")
    resilience = automation_resilience_status()
    execution = automation_execution_status()
    operations = operations_part1_status()
    from .automation_soak import operations_part2_status
    operations_part2 = operations_part2_status(include_live=False)
    risk = load_risk_policy()
    from .automation import load_automation_policy
    automation_policy = load_automation_policy()
    try:
        credentials = credential_status()
    except Exception as error:
        credentials = {"status": "error", "message": str(error)[:240]}
    gates = [
        {"code": "live_consent", "passed": bool(automation_policy.get("liveConsent")),
         "message": "Live automation risk consent is accepted in Settings"},
        {"code": "paper_promotion", "passed": bool(shadow.get("eligible")),
         "message": "Every shadow and paper promotion gate passes"},
        {"code": "accounting_reconciliation", "passed": bool(accounting.get("eligible")),
         "message": "Paper holdings pass repeated accounting reconciliation"},
        {"code": "resilience_validation", "passed": bool(resilience.get("eligible")),
         "message": "Recent failure-recovery validation passes"},
        {"code": "operations_part_one", "passed": bool(operations.get("eligible")),
         "message": "Local operational-hardening checks pass"},
        {"code": "operations_part_two_paper", "passed": bool(operations_part2.get("paperEligible")),
         "message": "KIS paper online validation passes every operational SLO"},
        {"code": "production_credentials", "passed": bool(credentials.get("kisProd")),
         "message": "KIS production API credentials are stored"},
        {"code": "production_account", "passed": bool(credentials.get("kisProdAccount")),
         "message": "KIS production account is stored"},
        {"code": "production_risk_policy", "passed": bool(risk.get("productionEnabled")),
         "message": "Production trading is explicitly unlocked in the global risk policy"},
        {"code": "execution_certainty", "passed": not bool(execution.get("uncertaintyLock")),
         "message": "No automation execution outcome is uncertain"},
        {"code": "audit_health", "passed": bool((execution.get("audit") or {}).get("healthy")),
         "message": "All automation journals pass integrity verification"},
    ]
    return {
        "gates": gates,
        "eligible": all(gate["passed"] for gate in gates),
        "shadow": shadow,
        "accounting": accounting,
        "resilience": resilience,
        "execution": execution,
        "operationsPart1": operations,
        "operationsPart2": operations_part2,
        "credentials": credentials,
        "riskPolicy": risk,
    }


def production_canary_status(armed_at=None):
    if armed_at is None:
        state, integrity = load_live_state()
        armed_at = int(numeric(state.get("armedAt"))) if integrity else 0
    armed_at = int(numeric(armed_at))
    activity = trade_activity("prod", 100)
    eligible = [
        item for item in activity.get("activity", [])
        if armed_at > 0
        and item.get("action") == "order"
        and item.get("environment") == "prod"
        and not item.get("automationPlanId")
        and int(numeric(item.get("timestamp"))) >= armed_at
        and 0 < numeric(item.get("estimatedNotionalKrw")) <= LIVE_CANARY_MAX_NOTIONAL_KRW
    ]
    fills = [
        item for item in eligible
        if item.get("brokerState") == "filled"
        and item.get("reconciliation") == "matched"
    ]
    uncertain = [
        item for item in eligible
        if item.get("status") == "uncertain" or item.get("reconciliation") == "unmatched"
    ]
    return {
        "fills": len(fills),
        "requiredFills": LIVE_CANARY_FILLS_REQUIRED,
        "uncertain": len(uncertain),
        "passed": len(fills) >= LIVE_CANARY_FILLS_REQUIRED and not uncertain,
        "armedAt": armed_at,
        "maxNotionalKrw": LIVE_CANARY_MAX_NOTIONAL_KRW,
    }


def automation_live_status(scheduler_failures=0):
    state, integrity = load_live_state()
    evidence = live_readiness_evidence(scheduler_failures)
    canary = production_canary_status(state.get("armedAt"))
    stage = str(state.get("stage", "locked")) if integrity else "locked"
    verified = stage == "verified" and canary["passed"] and evidence["eligible"]
    gates = list(evidence["gates"])
    gates.extend([
        {"code": "live_state_integrity", "passed": integrity,
         "message": "Live-readiness state checksum is valid"},
        {"code": "manual_live_canary", "passed": canary["passed"],
         "message": "Reconciled manual live canary fills are sufficient",
         "value": canary["fills"], "threshold": LIVE_CANARY_FILLS_REQUIRED},
    ])
    return {
        "status": "ok" if integrity else "error",
        "stage": stage,
        "preLiveEligible": evidence["eligible"] and integrity,
        "productionAutomationEligible": verified,
        "productionAutomationLocked": not verified,
        "canary": canary,
        "gates": gates,
        "passed": sum(1 for gate in gates if gate["passed"]),
        "total": len(gates),
        "updatedAt": int(numeric(state.get("updatedAt"))),
    }


def automation_live_control(action, payload=None, scheduler_failures=0, now=None):
    payload = payload if isinstance(payload, dict) else {}
    now = int(now if now is not None else time.time())
    with automation_live_lock():
        state, integrity = load_live_state()
        if not integrity:
            raise StockServiceError("Live-readiness state integrity check failed")
        status = automation_live_status(scheduler_failures)
        if action == "evaluate":
            pass
        elif action == "arm-canary":
            if payload.get("confirmation") != "ARM MANUAL LIVE CANARY":
                raise StockServiceError("Manual live canary requires exact confirmation")
            if not status["preLiveEligible"]:
                raise StockServiceError("Manual live canary is locked until every pre-live gate passes")
            state["stage"] = "manual_canary"
            state["armedAt"] = now
        elif action == "verify-canary":
            if payload.get("confirmation") != "VERIFY LIVE CANARY":
                raise StockServiceError("Live canary verification requires exact confirmation")
            if state.get("stage") != "manual_canary" or not status["canary"]["passed"]:
                raise StockServiceError("Manual live canary evidence is incomplete")
            state["stage"] = "verified"
            state["verifiedAt"] = now
        elif action == "lock":
            if payload.get("confirmation") != "LOCK LIVE AUTOMATION":
                raise StockServiceError("Live automation lock requires exact confirmation")
            state = default_live_state()
            state["lockedAt"] = now
        else:
            raise StockServiceError("Unsupported live-readiness action")
        state["updatedAt"] = now
        save_live_state(state)
    return automation_live_status(scheduler_failures)
