import fcntl
import hashlib
import json
import math
import os
import time
from contextlib import contextmanager
from datetime import datetime, timedelta

from .automation import AUTOMATION_TIMEZONE, automation_lock, load_automation_policy, save_automation_policy
from .automation_accounting import automation_accounting_status
from .automation_execution import automation_execution_status
from .automation_shadow import shadow_status
from .core import StockServiceError, credential_status, numeric, state_directory


SOAK_MIN_WORKER_CYCLES = 500
SOAK_MIN_BROKER_OBSERVATIONS = 100
SOAK_MIN_HEALTHY_SESSIONS = 60
SOAK_MIN_SUCCESS_PERCENT = 99.0
SOAK_MAX_P95_DURATION_MS = 60_000
SOAK_SLO_WINDOW_DAYS = 20
SOAK_MAX_CONSECUTIVE_FAILURES = 3
SOAK_DAY_RETENTION = 180
SOAK_DURATION_SAMPLE_LIMIT = 2_000
SOAK_CYCLE_ID_LIMIT = 4_096


def automation_soak_path():
    return os.path.join(state_directory(), "automation-soak.json")


def automation_soak_report_path():
    return os.path.join(state_directory(), "automation-operations-part2-report.json")


@contextmanager
def automation_soak_lock():
    descriptor = os.open(automation_soak_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def soak_hash(value):
    payload = dict(value)
    payload.pop("stateHash", None)
    payload.pop("reportHash", None)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def default_soak_state():
    return {
        "version": 1,
        "enabled": False,
        "startedAt": 0,
        "updatedAt": 0,
        "pausedAt": 0,
        "haltedAt": 0,
        "haltReason": "",
        "cycles": 0,
        "successfulCycles": 0,
        "partialCycles": 0,
        "failedCycles": 0,
        "brokerAttempts": 0,
        "brokerSuccesses": 0,
        "brokerFailures": 0,
        "rateLimitEvents": 0,
        "observations": 0,
        "plansReady": 0,
        "brokerOrdersSent": 0,
        "consecutiveFailures": 0,
        "maxConsecutiveFailures": 0,
        "automaticHalts": 0,
        "days": {},
        "durationSamplesMs": [],
        "recentCycleIds": [],
        "lastCycle": {},
    }


def normalized_soak_state(value):
    state = default_soak_state()
    if isinstance(value, dict):
        state.update(value)
    if not isinstance(state.get("days"), dict):
        state["days"] = {}
    for key in ("durationSamplesMs", "recentCycleIds"):
        if not isinstance(state.get(key), list):
            state[key] = []
    if not isinstance(state.get("lastCycle"), dict):
        state["lastCycle"] = {}
    return state


def load_soak_state():
    try:
        with open(automation_soak_path(), encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return default_soak_state(), True
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_soak_state(), False
    valid = isinstance(state, dict) and int(numeric(state.get("version"))) == 1
    return normalized_soak_state(state), valid and state.get("stateHash") == soak_hash(state)


def save_soak_state(state):
    payload = normalized_soak_state(state)
    payload["stateHash"] = soak_hash(payload)
    path = automation_soak_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return payload


def percentile(values, fraction):
    ordered = sorted(max(0, int(numeric(value))) for value in values)
    if not ordered:
        return 0
    index = max(0, min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1))
    return ordered[index]


def cycle_identifier(result):
    automation = result.get("automation") if isinstance(result.get("automation"), dict) else {}
    identity = {
        "startedAt": int(numeric(result.get("startedAt"))),
        "updatedAt": int(numeric(result.get("updatedAt"))),
        "state": str(automation.get("state", "")),
        "planId": str((automation.get("plan") or {}).get("planId", "")),
    }
    return hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:24]


def contains_rate_limit(result):
    payload = json.dumps(result, ensure_ascii=False).lower()
    return any(token in payload for token in (
        "egw00201", "초당 거래건수", "rate limit", "too many requests", "429",
    ))


def classify_soak_cycle(result):
    automation = result.get("automation") if isinstance(result.get("automation"), dict) else {}
    operations = result.get("operationsPart1") if isinstance(result.get("operationsPart1"), dict) else {}
    reconciliation = result.get("reconciliation") if isinstance(result.get("reconciliation"), dict) else {}
    state = str(automation.get("state", ""))
    target_count = int(numeric(automation.get("targetCount")))
    broker_attempt = target_count > 0 and state in {
        "observed", "auto_executed", "protective_exit_executed", "error", "halted",
        "session_error", "audit_failure", "accounting_failure", "waiting_reconciliation",
    }
    broker_success = broker_attempt and state in {"observed", "auto_executed", "protective_exit_executed"}
    rate_limited = contains_rate_limit(result)
    immediate_halt = state in {"audit_failure", "accounting_failure"} or bool(automation.get("halted"))
    critical = immediate_halt or not bool(operations.get("eligible")) or (
        broker_attempt and not broker_success
    ) or rate_limited
    successful = result.get("status") == "ok" and automation.get("status") != "error" and not critical
    plan = automation.get("plan") if isinstance(automation.get("plan"), dict) else {}
    return {
        "status": "ok" if successful else ("partial" if result.get("status") == "partial" else "error"),
        "automationState": state,
        "targetCount": target_count,
        "brokerAttempt": broker_attempt,
        "brokerSuccess": broker_success,
        "rateLimited": rate_limited,
        "critical": critical,
        "immediateHalt": immediate_halt,
        "observation": broker_success and bool(plan.get("planId")),
        "planReady": plan.get("decision") == "ready",
        "brokerOrderSent": bool(automation.get("brokerOrderSent")),
        "reconciliationStatus": str(reconciliation.get("status", "unavailable")),
        "durationMs": max(0, int(numeric(result.get("durationMs")))),
        "timestamp": int(numeric(result.get("updatedAt"), time.time())),
    }


def halt_soak_automation(reason):
    with automation_lock():
        policy = load_automation_policy()
        policy.update({
            "enabled": False,
            "halted": True,
            "schedulerEnabled": False,
            "schedulerMode": "observe",
            "exitOnlyProtection": False,
        })
        save_automation_policy(policy)
    return reason


def daily_soak_record(state, evidence):
    date = datetime.fromtimestamp(evidence["timestamp"], AUTOMATION_TIMEZONE).date().isoformat()
    day = dict((state.get("days") or {}).get(date) or {})
    if not day:
        day = {
            "date": date,
            "firstAt": evidence["timestamp"],
            "lastAt": evidence["timestamp"],
            "cycles": 0,
            "successfulCycles": 0,
            "failedCycles": 0,
            "brokerAttempts": 0,
            "brokerSuccesses": 0,
            "brokerFailures": 0,
            "rateLimitEvents": 0,
            "criticalFailures": 0,
            "observations": 0,
            "maxDurationMs": 0,
        }
    day["lastAt"] = evidence["timestamp"]
    day["cycles"] += 1
    day["successfulCycles"] += int(evidence["status"] == "ok")
    day["failedCycles"] += int(evidence["status"] != "ok")
    day["brokerAttempts"] += int(evidence["brokerAttempt"])
    day["brokerSuccesses"] += int(evidence["brokerSuccess"])
    day["brokerFailures"] += int(evidence["brokerAttempt"] and not evidence["brokerSuccess"])
    day["rateLimitEvents"] += int(evidence["rateLimited"])
    day["criticalFailures"] += int(evidence["critical"])
    day["observations"] += int(evidence["observation"])
    day["maxDurationMs"] = max(int(numeric(day.get("maxDurationMs"))), evidence["durationMs"])
    state["days"][date] = day
    retained = sorted(state["days"], reverse=True)[:SOAK_DAY_RETENTION]
    state["days"] = {key: state["days"][key] for key in retained}


def record_soak_cycle(result):
    if not isinstance(result, dict):
        raise StockServiceError("Online validation requires a worker result")
    should_halt = False
    halt_reason = ""
    with automation_soak_lock():
        state, integrity = load_soak_state()
        if not integrity:
            raise StockServiceError("Online-validation evidence integrity check failed")
        if not state.get("enabled"):
            return {
                "status": "ok",
                "part": 2,
                "enabled": False,
                "phase": "paused" if state.get("startedAt") else "not_started",
                "updatedAt": int(numeric(state.get("updatedAt"))),
            }
        identity = cycle_identifier(result)
        if identity in state["recentCycleIds"]:
            return operations_part2_status(state=state, integrity=True)
        evidence = classify_soak_cycle(result)
        state["cycles"] += 1
        state["successfulCycles"] += int(evidence["status"] == "ok")
        state["partialCycles"] += int(evidence["status"] == "partial")
        state["failedCycles"] += int(evidence["status"] == "error")
        state["brokerAttempts"] += int(evidence["brokerAttempt"])
        state["brokerSuccesses"] += int(evidence["brokerSuccess"])
        state["brokerFailures"] += int(evidence["brokerAttempt"] and not evidence["brokerSuccess"])
        state["rateLimitEvents"] += int(evidence["rateLimited"])
        state["observations"] += int(evidence["observation"])
        state["plansReady"] += int(evidence["planReady"])
        state["brokerOrdersSent"] += int(evidence["brokerOrderSent"])
        state["consecutiveFailures"] = (
            int(numeric(state.get("consecutiveFailures"))) + 1 if evidence["critical"] else 0
        )
        state["maxConsecutiveFailures"] = max(
            int(numeric(state.get("maxConsecutiveFailures"))), state["consecutiveFailures"],
        )
        state["durationSamplesMs"] = (
            state["durationSamplesMs"] + [evidence["durationMs"]]
        )[-SOAK_DURATION_SAMPLE_LIMIT:]
        state["recentCycleIds"] = (state["recentCycleIds"] + [identity])[-SOAK_CYCLE_ID_LIMIT:]
        state["lastCycle"] = dict(evidence, cycleId=identity)
        state["updatedAt"] = evidence["timestamp"]
        daily_soak_record(state, evidence)
        should_halt = evidence["immediateHalt"] or state["consecutiveFailures"] >= SOAK_MAX_CONSECUTIVE_FAILURES
        if should_halt:
            halt_reason = "critical_online_validation_failure"
            state["enabled"] = False
            state["haltedAt"] = evidence["timestamp"]
            state["haltReason"] = halt_reason
            state["automaticHalts"] += 1
        save_soak_state(state)
    if should_halt:
        halt_soak_automation(halt_reason)
    status = operations_part2_status(state=state, integrity=True)
    status["killSwitchEngaged"] = should_halt
    return status


def recent_soak_totals(state, now):
    cutoff = datetime.fromtimestamp(now, AUTOMATION_TIMEZONE).date() - timedelta(days=SOAK_SLO_WINDOW_DAYS - 1)
    totals = {
        "cycles": 0,
        "successfulCycles": 0,
        "failedCycles": 0,
        "brokerAttempts": 0,
        "brokerSuccesses": 0,
        "brokerFailures": 0,
        "rateLimitEvents": 0,
        "criticalFailures": 0,
    }
    for date, day in (state.get("days") or {}).items():
        try:
            if datetime.fromisoformat(date).date() < cutoff:
                continue
        except ValueError:
            continue
        for key in totals:
            totals[key] += int(numeric(day.get(key)))
    return totals


def success_percent(successes, attempts):
    return round(successes * 100 / attempts, 3) if attempts > 0 else 0


def operations_part2_status(now=None, state=None, integrity=None, include_live=True):
    now = int(now if now is not None else time.time())
    if not isinstance(state, dict):
        state, loaded_integrity = load_soak_state()
        integrity = loaded_integrity if integrity is None else integrity
    integrity = bool(integrity)
    try:
        from .automation_operations import operations_part1_status
        part1 = operations_part1_status(now)
    except Exception as error:
        part1 = {"status": "error", "eligible": False, "message": str(error)[:240]}
    try:
        from .scheduler import background_control_status
        worker = background_control_status()
    except Exception as error:
        worker = {"status": "error", "enabled": False, "message": str(error)[:240]}
    execution = automation_execution_status()
    accounting = automation_accounting_status("paper")
    scheduler_failures = int(numeric((part1.get("scheduler") or {}).get("consecutiveFailures")))
    promotion = shadow_status(scheduler_failures).get("promotion", {})
    recent = recent_soak_totals(state, now)
    worker_success = success_percent(recent["successfulCycles"], recent["cycles"])
    broker_success = success_percent(recent["brokerSuccesses"], recent["brokerAttempts"])
    healthy_sessions = sum(
        1 for day in (state.get("days") or {}).values()
        if int(numeric(day.get("brokerSuccesses"))) > 0
        and int(numeric(day.get("brokerFailures"))) == 0
        and int(numeric(day.get("criticalFailures"))) == 0
    )
    duration_p95 = percentile(state.get("durationSamplesMs", []), 0.95)
    worker_healthy = bool(worker.get("enabled")) and bool(worker.get("timerActive")) and (
        worker.get("workerStatus") in ("active", "running")
    )
    paper_gates = [
        {"code": "soak_integrity", "passed": integrity,
         "message": "Online-validation evidence checksum is valid"},
        {"code": "soak_started", "passed": int(numeric(state.get("startedAt"))) > 0,
         "message": "KIS paper online validation has started"},
        {"code": "soak_worker", "passed": worker_healthy,
         "message": "Background worker is active for online validation"},
        {"code": "soak_worker_cycles", "passed": int(numeric(state.get("cycles"))) >= SOAK_MIN_WORKER_CYCLES,
         "message": "The required worker-cycle sample is recorded",
         "value": int(numeric(state.get("cycles"))), "threshold": SOAK_MIN_WORKER_CYCLES},
        {"code": "soak_broker_observations", "passed": int(numeric(state.get("observations"))) >= SOAK_MIN_BROKER_OBSERVATIONS,
         "message": "The required KIS paper observation sample is recorded",
         "value": int(numeric(state.get("observations"))), "threshold": SOAK_MIN_BROKER_OBSERVATIONS},
        {"code": "soak_healthy_sessions", "passed": healthy_sessions >= SOAK_MIN_HEALTHY_SESSIONS,
         "message": "Sixty healthy market sessions are recorded",
         "value": healthy_sessions, "threshold": SOAK_MIN_HEALTHY_SESSIONS},
        {"code": "soak_worker_slo", "passed": recent["cycles"] > 0 and worker_success >= SOAK_MIN_SUCCESS_PERCENT,
         "message": "Recent worker success rate stays at or above 99%",
         "value": worker_success, "threshold": SOAK_MIN_SUCCESS_PERCENT},
        {"code": "soak_broker_slo", "passed": recent["brokerAttempts"] > 0 and broker_success >= SOAK_MIN_SUCCESS_PERCENT,
         "message": "Recent KIS paper success rate stays at or above 99%",
         "value": broker_success, "threshold": SOAK_MIN_SUCCESS_PERCENT},
        {"code": "soak_rate_limit", "passed": recent["brokerAttempts"] > 0 and recent["rateLimitEvents"] == 0,
         "message": "No KIS rate-limit event occurred in the recent SLO window",
         "value": recent["rateLimitEvents"], "threshold": 0},
        {"code": "soak_latency", "passed": bool(state.get("durationSamplesMs")) and duration_p95 <= SOAK_MAX_P95_DURATION_MS,
         "message": "Worker p95 duration stays below 60 seconds",
         "value": duration_p95, "threshold": SOAK_MAX_P95_DURATION_MS},
        {"code": "soak_failure_budget", "passed": int(numeric(state.get("consecutiveFailures"))) == 0
         and not bool(state.get("haltedAt")),
         "message": "Online validation has no active failure-budget halt"},
        {"code": "soak_operations_part_one", "passed": bool(part1.get("eligible")),
         "message": "Local operational-hardening checks remain healthy"},
        {"code": "soak_execution_certainty", "passed": not bool(execution.get("uncertaintyLock"))
         and bool((execution.get("audit") or {}).get("healthy")),
         "message": "Order outcomes and automation journals remain certain"},
        {"code": "soak_accounting", "passed": bool(accounting.get("eligible")),
         "message": "Repeated paper-account reconciliation remains healthy"},
        {"code": "soak_promotion", "passed": bool(promotion.get("eligible")),
         "message": "Shadow and paper promotion evidence passes every gate"},
    ]
    paper_eligible = all(gate["passed"] for gate in paper_gates)
    live = {"stage": "locked", "integrity": True, "canary": {"fills": 0, "requiredFills": 10, "passed": False}}
    gates = list(paper_gates)
    if include_live:
        try:
            from .automation_live import load_live_state, production_canary_status
            live_state, live_integrity = load_live_state()
            live = {
                "stage": str(live_state.get("stage", "locked")) if live_integrity else "locked",
                "integrity": live_integrity,
                "canary": production_canary_status(),
            }
        except Exception as error:
            live = {"stage": "locked", "integrity": False,
                    "canary": {"fills": 0, "requiredFills": 10, "passed": False},
                    "message": str(error)[:240]}
        gates.extend([
            {"code": "soak_live_integrity", "passed": bool(live.get("integrity")),
             "message": "Live-canary readiness state checksum is valid"},
            {"code": "soak_live_canary", "passed": bool((live.get("canary") or {}).get("passed")),
             "message": "Manual live canary fills are reconciled without uncertainty",
             "value": int(numeric((live.get("canary") or {}).get("fills"))),
             "threshold": int(numeric((live.get("canary") or {}).get("requiredFills"), 10))},
            {"code": "soak_live_verified", "passed": live.get("stage") == "verified",
             "message": "Manual live canary evidence is explicitly verified"},
        ])
    eligible = all(gate["passed"] for gate in gates)
    if eligible:
        phase = "complete"
    elif state.get("haltedAt"):
        phase = "halted"
    elif paper_eligible:
        phase = "live_canary"
    elif state.get("enabled"):
        phase = "collecting"
    elif state.get("startedAt"):
        phase = "paused"
    else:
        phase = "not_started"
    return {
        "status": "ok" if integrity else "error",
        "part": 2,
        "phase": phase,
        "enabled": bool(state.get("enabled")),
        "eligible": eligible,
        "paperEligible": paper_eligible,
        "passed": sum(1 for gate in gates if gate["passed"]),
        "total": len(gates),
        "progressPercent": round(sum(1 for gate in gates if gate["passed"]) * 100 / len(gates), 1),
        "gates": gates,
        "metrics": {
            "workerCycles": int(numeric(state.get("cycles"))),
            "brokerObservations": int(numeric(state.get("observations"))),
            "healthySessions": healthy_sessions,
            "workerSuccessPercent": worker_success,
            "brokerSuccessPercent": broker_success,
            "p95DurationMs": duration_p95,
            "recentRateLimitEvents": recent["rateLimitEvents"],
            "consecutiveFailures": int(numeric(state.get("consecutiveFailures"))),
            "automaticHalts": int(numeric(state.get("automaticHalts"))),
        },
        "thresholds": {
            "workerCycles": SOAK_MIN_WORKER_CYCLES,
            "brokerObservations": SOAK_MIN_BROKER_OBSERVATIONS,
            "healthySessions": SOAK_MIN_HEALTHY_SESSIONS,
            "successPercent": SOAK_MIN_SUCCESS_PERCENT,
            "p95DurationMs": SOAK_MAX_P95_DURATION_MS,
            "sloWindowDays": SOAK_SLO_WINDOW_DAYS,
        },
        "partOne": part1,
        "worker": worker,
        "execution": {"uncertaintyLock": bool(execution.get("uncertaintyLock"))},
        "accounting": accounting,
        "promotion": promotion,
        "live": live,
        "lastCycle": state.get("lastCycle", {}),
        "startedAt": int(numeric(state.get("startedAt"))),
        "updatedAt": int(numeric(state.get("updatedAt"))),
        "haltedAt": int(numeric(state.get("haltedAt"))),
        "haltReason": str(state.get("haltReason", "")),
    }


def operations_part2_start_readiness(now=None, widgets_path=""):
    now = int(now if now is not None else time.time())
    from .automation_operations import operations_part1_status
    from .automation_scheduler import normalized_automation_targets
    from .scheduler import background_control_status, stock_widget_configs

    credentials = credential_status()
    part1 = operations_part1_status(now)
    worker = background_control_status()
    widgets = stock_widget_configs(widgets_path)
    targets = normalized_automation_targets(widgets.get("items", [])) if widgets.get("found") else []
    policy = load_automation_policy()
    gates = [
        {"code": "start_part_one", "passed": bool(part1.get("eligible")),
         "message": "Operations Part One is healthy"},
        {"code": "start_paper_credentials", "passed": bool(credentials.get("kisPaper")),
         "message": "KIS paper API credentials are stored"},
        {"code": "start_paper_account", "passed": bool(credentials.get("kisPaperAccount")),
         "message": "KIS paper account is stored"},
        {"code": "start_worker", "passed": bool(worker.get("enabled")) and bool(worker.get("timerActive")),
         "message": "Background worker is installed and enabled"},
        {"code": "start_target", "passed": bool(targets),
         "message": "At least one valid KIS paper observation target is selected"},
        {"code": "start_scheduler", "passed": bool(policy.get("enabled"))
         and bool(policy.get("schedulerEnabled")) and not bool(policy.get("halted")),
         "message": "The guarded observer is armed and scheduled"},
    ]
    return {
        "eligible": all(gate["passed"] for gate in gates),
        "gates": gates,
        "credentials": credentials,
        "worker": worker,
        "targetCount": len(targets),
        "policy": policy,
    }


def run_operations_part2(payload, now=None, widgets_path=""):
    if not isinstance(payload, dict) or payload.get("confirmation") != "START KIS PAPER SOAK":
        raise StockServiceError("Operations Part Two requires exact confirmation")
    now = int(now if now is not None else time.time())
    readiness = operations_part2_start_readiness(now, widgets_path)
    if not readiness["eligible"]:
        failed = ", ".join(gate["code"] for gate in readiness["gates"] if not gate["passed"])
        raise StockServiceError(f"Operations Part Two prerequisites are incomplete: {failed}")
    with automation_soak_lock():
        state, integrity = load_soak_state()
        if not integrity:
            raise StockServiceError("Online-validation evidence integrity check failed")
        if not state.get("startedAt"):
            state["startedAt"] = now
        state.update({
            "enabled": True,
            "pausedAt": 0,
            "haltedAt": 0,
            "haltReason": "",
            "consecutiveFailures": 0,
            "updatedAt": now,
        })
        save_soak_state(state)
    try:
        from .automation_operations import create_automation_snapshot
        snapshot = create_automation_snapshot({
            "confirmation": "CREATE AUTOMATION SNAPSHOT",
        }, now=now, reason="operations_part2_start")
    except Exception:
        with automation_soak_lock():
            state, integrity = load_soak_state()
            if integrity:
                state.update({"enabled": False, "pausedAt": now, "updatedAt": now})
                save_soak_state(state)
        raise
    result = operations_part2_status(now)
    result["startReadiness"] = readiness
    result["snapshotCreated"] = snapshot
    return result


def pause_operations_part2(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "PAUSE KIS PAPER SOAK":
        raise StockServiceError("Pausing Operations Part Two requires exact confirmation")
    now = int(now if now is not None else time.time())
    with automation_soak_lock():
        state, integrity = load_soak_state()
        if not integrity:
            raise StockServiceError("Online-validation evidence integrity check failed")
        state.update({"enabled": False, "pausedAt": now, "updatedAt": now})
        save_soak_state(state)
    return operations_part2_status(now)


def reset_operations_part2(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RESET KIS PAPER SOAK EVIDENCE":
        raise StockServiceError("Resetting Operations Part Two requires exact confirmation")
    now = int(now if now is not None else time.time())
    with automation_soak_lock():
        state = default_soak_state()
        state["updatedAt"] = now
        save_soak_state(state)
    return operations_part2_status(now)


def create_operations_part2_report(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "CREATE VERIFIED OPERATIONS REPORT":
        raise StockServiceError("Operations report requires exact confirmation")
    now = int(now if now is not None else time.time())
    with automation_soak_lock():
        state, integrity = load_soak_state()
        status = operations_part2_status(now, state, integrity)
        if not status.get("eligible"):
            raise StockServiceError("Operations Part Two evidence is incomplete")
        report = {
            "version": 1,
            "status": "ok",
            "eligible": True,
            "createdAt": now,
            "part": 2,
            "sourceStateHash": str(state.get("stateHash", "")),
            "metrics": status["metrics"],
            "thresholds": status["thresholds"],
            "gates": status["gates"],
            "principle": "Preserve capital first; abstain whenever evidence or operational state is uncertain.",
        }
        report["reportHash"] = soak_hash(report)
        path = automation_soak_report_path()
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    return dict(report, path=path)
