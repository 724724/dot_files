import fcntl
import hashlib
import json
import os
import shutil
import time
from contextlib import ExitStack, contextmanager

from .automation import (
    automation_lock,
    automation_plan_lock,
    clear_live_auto_session,
    live_auto_session_status,
    load_automation_policy,
    normalized_automation_policy,
    save_automation_policy,
)
from .automation_accounting import automation_accounting_lock
from .automation_execution import automation_audit_status, automation_execution_lock, automation_execution_status
from .automation_live import automation_live_lock
from .automation_notifications import automation_notification_lock
from .automation_positions import automation_position_lock
from .automation_universe import automation_universe_lock
from .automation_resilience import (
    automation_resilience_lock,
    automation_resilience_status,
    run_resilience_self_test,
)
from .automation_scheduler import automation_scheduler_lock, automation_scheduler_status
from .automation_shadow import automation_shadow_lock
from .automation_soak import automation_soak_lock
from .core import StockServiceError, numeric, state_directory


AUTOMATION_STATE_FILES = (
    "automation-policy.json",
    "automation-plans.jsonl",
    "automation-executions.jsonl",
    "automation-risk.json",
    "automation-market-calendar.json",
    "automation-scheduler.json",
    "automation-shadow.json",
    "automation-positions.json",
    "automation-universe.json",
    "automation-notifications.json",
    "automation-accounting.json",
    "automation-resilience.json",
    "automation-live-readiness.json",
    "automation-soak.json",
    "automation-operations-part2-report.json",
)
SNAPSHOT_LIMIT = 10
MINIMUM_FREE_BYTES = 100 * 1024 * 1024


def automation_operations_path():
    return os.path.join(state_directory(), "automation-operations.json")


def automation_incident_path():
    return os.path.join(state_directory(), "automation-incidents.jsonl")


def automation_snapshot_root():
    return os.path.join(state_directory(), "automation-snapshots")


@contextmanager
def automation_operations_lock():
    descriptor = os.open(automation_operations_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


@contextmanager
def automation_snapshot_lock():
    root = automation_snapshot_root()
    os.makedirs(root, mode=0o700, exist_ok=True)
    descriptor = os.open(root + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def stable_hash(value):
    payload = dict(value)
    payload.pop("stateHash", None)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def incident_hash(value):
    payload = dict(value)
    payload.pop("recordHash", None)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path, value):
    payload = dict(value)
    payload["stateHash"] = stable_hash(payload)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return payload


def state_locks(stack):
    stack.enter_context(automation_scheduler_lock())
    stack.enter_context(automation_execution_lock())
    stack.enter_context(automation_shadow_lock())
    stack.enter_context(automation_position_lock(state_directory()))
    stack.enter_context(automation_universe_lock(state_directory()))
    stack.enter_context(automation_notification_lock())
    stack.enter_context(automation_accounting_lock())
    stack.enter_context(automation_resilience_lock())
    stack.enter_context(automation_live_lock())
    stack.enter_context(automation_soak_lock())
    stack.enter_context(automation_plan_lock())
    stack.enter_context(automation_lock())


def copy_snapshot_files(destination):
    directory = state_directory()
    files = []
    for name in AUTOMATION_STATE_FILES:
        source = os.path.join(directory, name)
        if not os.path.exists(source):
            continue
        if os.path.islink(source) or not os.path.isfile(source):
            raise StockServiceError(f"Unsafe automation state path: {name}")
        target = os.path.join(destination, name)
        with open(source, "rb") as input_handle, open(target, "xb") as output_handle:
            shutil.copyfileobj(input_handle, output_handle)
            output_handle.flush()
            os.fsync(output_handle.fileno())
        os.chmod(target, 0o600)
        files.append({
            "name": name,
            "size": os.path.getsize(target),
            "sha256": file_hash(target),
        })
    return files


def write_snapshot(now, reason, preserve_paths=()):
    root = automation_snapshot_root()
    os.makedirs(root, mode=0o700, exist_ok=True)
    identity = f"{now}-{os.urandom(4).hex()}"
    staging = os.path.join(root, "." + identity + ".tmp")
    destination = os.path.join(root, identity)
    os.mkdir(staging, 0o700)
    try:
        files = copy_snapshot_files(staging)
        manifest = atomic_json(os.path.join(staging, "manifest.json"), {
            "version": 1,
            "snapshotId": identity,
            "createdAt": now,
            "reason": reason,
            "files": files,
        })
        os.replace(staging, destination)
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    snapshots = sorted(
        (entry for entry in os.scandir(root) if entry.is_dir() and not entry.name.startswith(".")),
        key=lambda entry: entry.name,
        reverse=True,
    )
    retained = 0
    preserve = {os.path.realpath(path) for path in preserve_paths}
    for stale in snapshots:
        if os.path.realpath(stale.path) in preserve or retained < SNAPSHOT_LIMIT:
            retained += 1
            continue
        shutil.rmtree(stale.path)
    return dict(manifest, path=destination)


def create_automation_snapshot(payload=None, now=None, reason="manual"):
    payload = payload if isinstance(payload, dict) else {}
    if payload.get("confirmation") != "CREATE AUTOMATION SNAPSHOT":
        raise StockServiceError("Automation snapshot requires exact confirmation")
    now = int(now if now is not None else time.time())
    with automation_snapshot_lock(), ExitStack() as stack:
        state_locks(stack)
        return write_snapshot(now, reason)


def verify_snapshot(path):
    try:
        with open(os.path.join(path, "manifest.json"), encoding="utf-8") as handle:
            manifest = json.load(handle)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {"healthy": False, "reason": "manifest_unreadable", "path": path}
    if not isinstance(manifest, dict) or manifest.get("stateHash") != stable_hash(manifest):
        return {"healthy": False, "reason": "manifest_hash_mismatch", "path": path}
    invalid = []
    for item in manifest.get("files", []):
        name = str(item.get("name", ""))
        target = os.path.join(path, name)
        if name not in AUTOMATION_STATE_FILES or not os.path.isfile(target):
            invalid.append(name)
        elif os.path.getsize(target) != int(numeric(item.get("size"))):
            invalid.append(name)
        elif file_hash(target) != item.get("sha256"):
            invalid.append(name)
    return {
        "healthy": not invalid,
        "reason": "" if not invalid else "file_hash_mismatch",
        "invalidFiles": invalid,
        "snapshotId": str(manifest.get("snapshotId", "")),
        "createdAt": int(numeric(manifest.get("createdAt"))),
        "fileCount": len(manifest.get("files", [])),
        "path": path,
    }


def latest_snapshot_status():
    root = automation_snapshot_root()
    try:
        snapshots = sorted(
            (entry.path for entry in os.scandir(root) if entry.is_dir() and not entry.name.startswith(".")),
            reverse=True,
        )
    except OSError:
        snapshots = []
    return verify_snapshot(snapshots[0]) if snapshots else {
        "healthy": False, "reason": "missing", "snapshotId": "", "createdAt": 0, "fileCount": 0,
    }


def restore_automation_snapshot(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RESTORE HALTED AUTOMATION SNAPSHOT":
        raise StockServiceError("Automation restore requires exact confirmation")
    snapshot_id = str(payload.get("snapshotId", "")).strip()
    if not snapshot_id or "/" in snapshot_id or snapshot_id.startswith("."):
        raise StockServiceError("A valid automation snapshot ID is required")
    now = int(now if now is not None else time.time())
    source = os.path.join(automation_snapshot_root(), snapshot_id)
    with automation_snapshot_lock(), ExitStack() as stack:
        state_locks(stack)
        verified = verify_snapshot(source)
        if not verified.get("healthy"):
            raise StockServiceError("Automation snapshot integrity verification failed")
        emergency = write_snapshot(now, "pre_restore", (source,))
        manifest_path = os.path.join(source, "manifest.json")
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        available = {str(item.get("name", "")) for item in manifest.get("files", [])}
        manifest_files = {str(item.get("name", "")): item for item in manifest.get("files", [])}
        directory = state_directory()
        staged = {}
        try:
            for name in available:
                target = os.path.join(directory, name)
                temporary = target + f".restore.{os.urandom(4).hex()}.tmp"
                flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                if hasattr(os, "O_NOFOLLOW"):
                    flags |= os.O_NOFOLLOW
                descriptor = os.open(temporary, flags, 0o600)
                with open(os.path.join(source, name), "rb") as input_handle, os.fdopen(descriptor, "wb") as output_handle:
                    shutil.copyfileobj(input_handle, output_handle)
                    output_handle.flush()
                    os.fsync(output_handle.fileno())
                if file_hash(temporary) != manifest_files[name].get("sha256"):
                    raise StockServiceError("Staged automation restore checksum failed")
                staged[name] = temporary
            for name in AUTOMATION_STATE_FILES:
                target = os.path.join(directory, name)
                if name in staged:
                    os.replace(staged.pop(name), target)
                    os.chmod(target, 0o600)
                else:
                    try:
                        os.unlink(target)
                    except FileNotFoundError:
                        pass
            descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            for temporary in staged.values():
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
        policy = normalized_automation_policy(load_automation_policy())
        policy.update({
            "enabled": False,
            "halted": True,
            "executionMode": "paper",
            "paperOnly": True,
            "schedulerEnabled": False,
            "schedulerMode": "observe",
            "autopilotEnabled": False,
            "exitOnlyProtection": False,
        })
        clear_live_auto_session(policy)
        save_automation_policy(policy)
    return {
        "status": "ok",
        "restored": True,
        "snapshotId": snapshot_id,
        "restoredAt": now,
        "emergencySnapshotId": emergency["snapshotId"],
        "requiresKillSwitchReset": True,
    }


def state_permission_status():
    directory = state_directory()
    directory_private = os.stat(directory).st_mode & 0o077 == 0
    exposed = []
    for name in AUTOMATION_STATE_FILES:
        path = os.path.join(directory, name)
        if os.path.isfile(path) and os.stat(path).st_mode & 0o077:
            exposed.append(name)
    return {"healthy": directory_private and not exposed, "directoryPrivate": directory_private, "exposed": exposed}


def stale_temporary_files(now):
    directory = state_directory()
    result = []
    for entry in os.scandir(directory):
        if entry.is_file() and (entry.name.endswith(".tmp") or ".restore.tmp" in entry.name):
            age = max(0, now - int(entry.stat().st_mtime))
            if age > 300:
                result.append({"name": entry.name, "ageSeconds": age})
    return result


def automation_policy_coherent(policy, now=None):
    mode = str(policy.get("executionMode", "dry_run"))
    enabled = bool(policy.get("enabled"))
    halted = bool(policy.get("halted"))
    scheduler_enabled = bool(policy.get("schedulerEnabled"))
    auto_mode = policy.get("schedulerMode") == "paper_auto"
    autopilot_enabled = bool(policy.get("autopilotEnabled"))
    if mode not in ("dry_run", "paper", "live"):
        return False
    if bool(policy.get("paperOnly")) != (mode != "live"):
        return False
    if halted and enabled:
        return False
    if auto_mode and (
        not enabled
        or halted
        or not scheduler_enabled
        or mode not in ("paper", "live")
    ):
        return False
    if autopilot_enabled and (
        not auto_mode
        or not scheduler_enabled
        or mode not in ("paper", "live")
    ):
        return False
    if mode == "live":
        return (
            bool(policy.get("liveConsent"))
            and live_auto_session_status(policy, now, "prod").get("valid")
        )
    return not any((
        str(policy.get("liveSessionId", "")),
        str(policy.get("liveSessionEnvironment", "")),
        int(numeric(policy.get("liveSessionStartedAt"))),
        int(numeric(policy.get("liveSessionExpiresAt"))),
    ))


def operations_part1_status(now=None, record=False):
    now = int(now if now is not None else time.time())
    policy = load_automation_policy()
    execution = automation_execution_status()
    audit = execution.get("audit") or automation_audit_status()
    resilience = automation_resilience_status(now)
    scheduler = automation_scheduler_status()
    snapshot = latest_snapshot_status()
    permissions = state_permission_status()
    stale_files = stale_temporary_files(now)
    free_bytes = shutil.disk_usage(state_directory()).free
    incidents = automation_incident_audit_status()
    scheduler_required = bool(policy.get("schedulerEnabled"))
    worker = {"enabled": False, "timerActive": False, "workerStatus": "not_required"}
    if scheduler_required:
        try:
            from .scheduler import background_control_status
            worker = background_control_status()
        except Exception as error:
            worker = {"status": "error", "message": str(error)[:240]}
    policy_coherent = automation_policy_coherent(policy, now)
    gates = [
        {"code": "operations_audit", "passed": bool(audit.get("healthy")),
         "message": "Automation journals and position state are intact"},
        {"code": "operations_execution_resolution", "passed": not execution.get("uncertaintyLock"),
         "message": "No order requires broker reconciliation"},
        {"code": "operations_policy", "passed": policy_coherent,
         "message": "Automation policy state is internally consistent"},
        {"code": "operations_resilience", "passed": bool(resilience.get("eligible")),
         "message": "The local failure-recovery suite is current"},
        {"code": "operations_snapshot", "passed": bool(snapshot.get("healthy")),
         "message": "A verified automation rollback snapshot is available"},
        {"code": "operations_permissions", "passed": bool(permissions.get("healthy")),
         "message": "Automation state is private to the current user"},
        {"code": "operations_storage", "passed": free_bytes >= MINIMUM_FREE_BYTES,
         "message": "State storage has at least 100 MB free",
         "value": int(free_bytes / 1024 / 1024), "threshold": 100},
        {"code": "operations_temporary_files", "passed": not stale_files,
         "message": "No interrupted automation state write is stale"},
        {"code": "operations_incident_integrity", "passed": incidents["healthy"],
         "message": "Operational incident history is intact"},
        {"code": "operations_scheduler_failures", "passed": int(numeric(
            scheduler.get("consecutiveFailures"),
        )) == 0, "message": "The scheduler has no consecutive failures"},
        {"code": "operations_worker", "passed": not scheduler_required or (
            worker.get("enabled") and worker.get("timerActive")
            and worker.get("workerStatus") in ("active", "running")
        ), "message": "The required background worker heartbeat is healthy"},
    ]
    eligible = all(gate["passed"] for gate in gates)
    result = {
        "status": "ok",
        "part": 1,
        "eligible": eligible,
        "passed": sum(1 for gate in gates if gate["passed"]),
        "total": len(gates),
        "gates": gates,
        "audit": audit,
        "execution": {"unresolved": execution.get("unresolved", 0)},
        "resilience": resilience,
        "snapshot": snapshot,
        "permissions": permissions,
        "storage": {"freeBytes": free_bytes},
        "staleTemporaryFiles": stale_files,
        "incidents": incidents,
        "scheduler": scheduler,
        "worker": worker,
        "updatedAt": now,
    }
    if record:
        record_operations_health(result)
    return result


def load_operations_health():
    try:
        with open(automation_operations_path(), encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError:
        return {}, True
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}, False
    return value, isinstance(value, dict) and value.get("stateHash") == stable_hash(value)


def append_incident(event):
    audit = automation_incident_audit_status()
    if not audit["healthy"]:
        raise StockServiceError("Operational incident history integrity check failed")
    previous_hash = audit["latestHash"]
    payload = dict(event, previousHash=previous_hash)
    payload["recordHash"] = incident_hash(payload)
    descriptor = os.open(automation_incident_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode())
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def automation_incident_audit_status():
    previous_hash = ""
    verified = 0
    invalid = 0
    first_error = {}
    try:
        with open(automation_incident_path(), encoding="utf-8") as handle:
            lines = list(handle)
    except FileNotFoundError:
        lines = []
    except OSError as error:
        return {"healthy": False, "verifiedRecords": 0, "invalidRecords": 1,
                "latestHash": "", "firstError": {"reason": str(error)[:120]}}
    for index, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except (TypeError, json.JSONDecodeError):
            invalid += 1
            first_error = first_error or {"line": index, "reason": "invalid_json"}
            continue
        if not isinstance(value, dict) or value.get("recordHash") != incident_hash(value):
            invalid += 1
            first_error = first_error or {"line": index, "reason": "record_hash_mismatch"}
        if str(value.get("previousHash", "")) != previous_hash:
            invalid += 1
            first_error = first_error or {"line": index, "reason": "chain_link_mismatch"}
        previous_hash = str(value.get("recordHash", ""))
        verified += 1
    return {
        "healthy": invalid == 0,
        "verifiedRecords": verified,
        "invalidRecords": invalid,
        "latestHash": previous_hash,
        "firstError": first_error,
    }


def record_operations_health(result):
    with automation_operations_lock():
        previous, integrity = load_operations_health()
        current_healthy = bool(result.get("eligible"))
        previous_healthy = previous.get("eligible") if integrity else None
        if previous_healthy is not None and previous_healthy != current_healthy:
            failed = [gate["code"] for gate in result.get("gates", []) if not gate.get("passed")]
            append_incident({
                "kind": "recovered" if current_healthy else "degraded",
                "timestamp": int(numeric(result.get("updatedAt"))),
                "failedGates": failed,
            })
        atomic_json(automation_operations_path(), {
            "version": 1,
            "eligible": current_healthy,
            "passed": int(numeric(result.get("passed"))),
            "total": int(numeric(result.get("total"))),
            "updatedAt": int(numeric(result.get("updatedAt"))),
        })


def run_operations_part1(payload, now=None):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RUN OPERATIONS PART ONE":
        raise StockServiceError("Operations Part One requires exact confirmation")
    now = int(now if now is not None else time.time())
    directory = state_directory()
    os.chmod(directory, 0o700)
    for name in AUTOMATION_STATE_FILES:
        path = os.path.join(directory, name)
        if os.path.isfile(path) and not os.path.islink(path):
            os.chmod(path, 0o600)
    resilience = run_resilience_self_test({
        "confirmation": "RUN AUTOMATION RESILIENCE TEST",
    }, now=now)
    snapshot = create_automation_snapshot({
        "confirmation": "CREATE AUTOMATION SNAPSHOT",
    }, now=now, reason="operations_part1")
    result = operations_part1_status(now, record=True)
    result["resilienceRun"] = resilience
    result["snapshotCreated"] = snapshot
    return result
