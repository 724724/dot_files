import hashlib
import json
import os
import time
from contextlib import ExitStack
from datetime import datetime

from .automation import (
    AUTOMATION_TIMEZONE,
    DEFAULT_AUTOMATION_POLICY,
    automation_lock,
    automation_plan_lock,
    load_automation_policy,
    save_automation_policy,
)
from .automation_execution import automation_audit_status, automation_execution_lock
from .automation_scheduler import automation_scheduler_lock
from .automation_shadow import automation_shadow_lock
from .automation_positions import automation_position_lock
from .automation_universe import automation_universe_lock
from .automation_accounting import automation_accounting_lock
from .automation_resilience import automation_resilience_lock
from .automation_live import automation_live_lock
from .automation_operations import automation_operations_lock
from .automation_soak import automation_soak_lock
from .core import StockServiceError, state_directory


AUTOMATION_RECOVERY_CONFIRMATION = "ARCHIVE AND RESET AUTOMATION"
AUTOMATION_RECOVERY_FILES = (
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
    "automation-operations.json",
    "automation-incidents.jsonl",
    "automation-soak.json",
    "automation-operations-part2-report.json",
)


def automation_recovery_path():
    return os.path.join(state_directory(), "automation-recovery-last.json")


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def write_durable_json(path, value):
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def automation_recovery_status():
    try:
        with open(automation_recovery_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        if isinstance(value, dict):
            return dict({"available": True}, **value)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return {"available": False}


def recover_automation_audit(payload=None, now=None):
    payload = payload if isinstance(payload, dict) else {}
    if str(payload.get("confirmation", "")) != AUTOMATION_RECOVERY_CONFIRMATION:
        raise StockServiceError(f"Audit recovery requires {AUTOMATION_RECOVERY_CONFIRMATION} confirmation")
    now = int(now if now is not None else time.time())
    directory = state_directory()
    with ExitStack() as stack:
        stack.enter_context(automation_scheduler_lock())
        stack.enter_context(automation_execution_lock())
        stack.enter_context(automation_shadow_lock())
        stack.enter_context(automation_position_lock(directory))
        stack.enter_context(automation_universe_lock(directory))
        stack.enter_context(automation_accounting_lock())
        stack.enter_context(automation_resilience_lock())
        stack.enter_context(automation_live_lock())
        stack.enter_context(automation_operations_lock())
        stack.enter_context(automation_soak_lock())
        stack.enter_context(automation_plan_lock())
        stack.enter_context(automation_lock())
        before = automation_audit_status()
        if before["healthy"]:
            raise StockServiceError("Automation audit is healthy; recovery is not required")
        stamp = datetime.fromtimestamp(now, AUTOMATION_TIMEZONE).strftime("%Y%m%dT%H%M%S")
        archive_name = f"automation-recovery-{stamp}-{os.urandom(3).hex()}"
        archive_path = os.path.join(directory, archive_name)
        os.mkdir(archive_path, 0o700)
        files = []
        for name in AUTOMATION_RECOVERY_FILES:
            source = os.path.join(directory, name)
            if not os.path.lexists(source):
                continue
            destination = os.path.join(archive_path, name)
            stat = os.lstat(source)
            item = {"name": name, "size": stat.st_size}
            if os.path.islink(source):
                item["sha256"] = ""
                item["symlink"] = os.readlink(source)
            else:
                item["sha256"] = file_sha256(source)
            os.replace(source, destination)
            files.append(item)
        policy = dict(DEFAULT_AUTOMATION_POLICY)
        policy["enabled"] = False
        policy["halted"] = True
        policy["schedulerEnabled"] = False
        policy["schedulerMode"] = "observe"
        policy = save_automation_policy(policy)
        after = automation_audit_status()
        manifest = {
            "status": "ok",
            "recovered": True,
            "recoveredAt": now,
            "archiveName": archive_name,
            "archiveDirectory": archive_path,
            "files": files,
            "auditBefore": before,
            "auditAfter": after,
            "policy": policy,
            "requiresKillSwitchReset": True,
        }
        write_durable_json(os.path.join(archive_path, "manifest.json"), manifest)
        write_durable_json(automation_recovery_path(), {
            "recoveredAt": now,
            "archiveName": archive_name,
            "archiveDirectory": archive_path,
            "fileCount": len(files),
            "auditAfter": after,
            "requiresKillSwitchReset": True,
        })
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    return manifest
