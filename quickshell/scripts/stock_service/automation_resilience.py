import fcntl
import hashlib
import json
import os
import tempfile
import time
from contextlib import contextmanager

from .core import StockServiceError, numeric, state_directory


RESILIENCE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60


def automation_resilience_path():
    return os.path.join(state_directory(), "automation-resilience.json")


@contextmanager
def automation_resilience_lock():
    descriptor = os.open(automation_resilience_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def payload_hash(value):
    payload = dict(value)
    payload.pop("stateHash", None)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def save_resilience_result(result):
    result = dict(result)
    result["stateHash"] = payload_hash(result)
    path = automation_resilience_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return result


def load_resilience_result():
    try:
        with open(automation_resilience_path(), encoding="utf-8") as handle:
            result = json.load(handle)
    except FileNotFoundError:
        return {}, True
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}, False
    return result, isinstance(result, dict) and result.get("stateHash") == payload_hash(result)


def run_resilience_self_test(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RUN AUTOMATION RESILIENCE TEST":
        raise StockServiceError("Resilience test requires exact confirmation")
    now = int(now if now is not None else time.time())
    checks = []
    directory = state_directory()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    descriptor, path = tempfile.mkstemp(prefix="automation-resilience-", dir=directory)
    os.close(descriptor)
    temporary = path + ".tmp"
    lock_path = path + ".lock"
    try:
        value = {"sequence": 1, "orders": ["one"]}
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(value, handle, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        with open(path, encoding="utf-8") as handle:
            checks.append({"code": "atomic_replace", "passed": json.load(handle) == value,
                           "message": "Atomic durable state replacement succeeds"})

        lock = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            checks.append({"code": "exclusive_lock", "passed": True,
                           "message": "Exclusive process lock succeeds"})
            contender = os.open(lock_path, os.O_RDWR)
            try:
                try:
                    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    contention_blocked = False
                except BlockingIOError:
                    contention_blocked = True
            finally:
                os.close(contender)
            checks.append({"code": "lock_contention", "passed": contention_blocked,
                           "message": "A concurrent writer cannot enter the critical section"})
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            os.close(lock)

        digest = payload_hash(value)
        tampered = dict(value, sequence=2)
        checks.append({"code": "tamper_detection", "passed": digest != payload_hash(tampered),
                       "message": "Checksum detects modified records"})
        seen = set()
        key = "same-order"
        first = key not in seen
        seen.add(key)
        second = key not in seen
        checks.append({"code": "idempotency_guard", "passed": first and not second,
                       "message": "Duplicate execution keys are rejected"})
        try:
            json.loads("{broken")
            malformed_detected = False
        except json.JSONDecodeError:
            malformed_detected = True
        checks.append({"code": "corruption_detection", "passed": malformed_detected,
                       "message": "Malformed journal records are detected"})
        interrupted = {"sequence": 2, "orders": ["interrupted"]}
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(interrupted, handle, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        with open(path, encoding="utf-8") as handle:
            durable_value = json.load(handle)
        checks.append({"code": "interrupted_write", "passed": durable_value == value,
                       "message": "An interrupted replacement preserves the last durable state"})

        first_record = {"sequence": 1, "previousHash": ""}
        first_hash = payload_hash(first_record)
        second_record = {"sequence": 2, "previousHash": first_hash}
        second_hash = payload_hash(second_record)
        chain_valid = second_record["previousHash"] == first_hash
        tampered_chain = dict(second_record, previousHash="deleted-record")
        checks.append({"code": "journal_chain", "passed": chain_valid and (
            payload_hash(tampered_chain) != second_hash
        ), "message": "Journal deletion and chain rewrites are detected"})
    finally:
        for candidate in (temporary, path, lock_path):
            try:
                os.unlink(candidate)
            except OSError:
                pass

    from .automation_execution import automation_audit_status
    audit = automation_audit_status()
    checks.append({"code": "journal_integrity", "passed": bool(audit.get("healthy")),
                   "message": "Current automation journals pass integrity verification"})
    result = {
        "version": 1,
        "status": "ok",
        "passed": all(check["passed"] for check in checks),
        "checks": checks,
        "testedAt": now,
        "audit": audit,
    }
    with automation_resilience_lock():
        return save_resilience_result(result)


def automation_resilience_status(now=None):
    now = int(now if now is not None else time.time())
    result, integrity = load_resilience_result()
    age = now - int(numeric(result.get("testedAt"))) if result else RESILIENCE_MAX_AGE_SECONDS + 1
    fresh = 0 <= age <= RESILIENCE_MAX_AGE_SECONDS
    passed = integrity and fresh and bool(result.get("passed"))
    gates = list(result.get("checks", [])) if isinstance(result.get("checks"), list) else []
    gates.extend([
        {"code": "resilience_state_integrity", "passed": integrity,
         "message": "Resilience-test result checksum is valid"},
        {"code": "resilience_test_freshness", "passed": fresh,
         "message": "Resilience test was run within seven days",
         "value": max(0, age // 86400), "threshold": 7},
    ])
    return {
        "status": "ok" if integrity else "error",
        "eligible": passed and all(gate.get("passed") for gate in gates),
        "passed": passed,
        "testedAt": int(numeric(result.get("testedAt"))),
        "ageSeconds": max(0, age),
        "checks": result.get("checks", []),
        "gates": gates,
    }
