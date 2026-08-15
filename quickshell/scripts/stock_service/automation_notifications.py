import fcntl
import hashlib
import json
import os
import subprocess
import time
from contextlib import contextmanager

from .automation import load_automation_policy
from .core import numeric, state_directory


NOTIFICATION_HISTORY_LIMIT = 64


def automation_notification_path():
    return os.path.join(state_directory(), "automation-notifications.json")


@contextmanager
def automation_notification_lock():
    descriptor = os.open(automation_notification_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def load_automation_notifications():
    try:
        with open(automation_notification_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def save_automation_notifications(value):
    path = automation_notification_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def automation_notification_event(result):
    if not isinstance(result, dict):
        return None
    state = str(result.get("state", ""))
    target = result.get("target") if isinstance(result.get("target"), dict) else {}
    plan = result.get("plan") if isinstance(result.get("plan"), dict) else {}
    execution = result.get("execution") if isinstance(result.get("execution"), dict) else {}
    symbol = str(target.get("symbol") or plan.get("symbol") or execution.get("symbol") or "Stock")
    language = "ko" if target.get("language") == "ko" or result.get("language") == "ko" else "en"
    plan_id = str(plan.get("planId") or execution.get("planId") or "")
    execution_id = str(execution.get("executionId") or "")
    side = str(execution.get("side") or plan.get("side") or "")
    quantity = int(numeric(execution.get("quantity")))
    urgency = "normal"
    kind = ""

    if state == "protective_exit_executed":
        kind = "protective_exit"
        urgency = "critical"
        title = "보호 매도 주문 접수" if language == "ko" else "Protective sell submitted"
        body = (
            f"{symbol} · {quantity}주 · KIS 모의투자 · 체결 확인 중"
            if language == "ko"
            else f"{symbol} · {quantity} shares · KIS paper · reconciling"
        )
    elif state == "auto_executed":
        kind = "paper_execution"
        title = "자동 모의주문 접수" if language == "ko" else "Automated paper order submitted"
        action = "매수" if side == "buy" else "매도"
        if language == "ko":
            body = f"{symbol} · {action} {quantity}주 · 체결 여부 확인 대기"
        else:
            body = f"{symbol} · {side or 'order'} {quantity} shares · awaiting reconciliation"
    elif result.get("autoRevoked"):
        kind = "auto_revoked"
        urgency = "critical"
        title = "자동 모의주문 해제" if language == "ko" else "Paper auto execution revoked"
        body = (
            "승격 조건이 해제되어 관찰 모드로 안전 전환했습니다."
            if language == "ko"
            else "Promotion gates no longer pass; switched safely to observe mode."
        )
    elif state in ("audit_failure", "halted"):
        kind = "kill_switch"
        urgency = "critical"
        title = "주식 자동화 긴급 중지" if language == "ko" else "Stock automation halted"
        body = str(result.get("message") or (
            "안전성 검사 실패로 긴급 중지 스위치가 작동했습니다."
            if language == "ko"
            else "The kill switch engaged after an operational safety failure."
        ))
    elif state == "waiting_reconciliation":
        kind = "reconciliation"
        urgency = "critical"
        title = "모의주문 확인 필요" if language == "ko" else "Paper order needs reconciliation"
        body = (
            "주문 결과가 확정되지 않아 자동화를 중지했습니다. KIS 거래내역을 확인하세요."
            if language == "ko"
            else "Order outcome is unresolved. Automation is locked until KIS reconciliation."
        )
    elif state == "waiting_accounting":
        kind = "reconciliation"
        urgency = "critical"
        title = "보유자산 대조 중" if language == "ko" else "Reconciling holdings"
        body = (
            "주문 후 KIS 보유자산 대조가 끝날 때까지 신규 주문을 차단합니다."
            if language == "ko"
            else "New orders stay blocked until post-trade broker holdings reconcile."
        )
    elif state == "operator_action":
        kind = "operator_action"
        title = "자동매매 설정 확인 필요" if language == "ko" else "Autopilot needs attention"
        body = str(result.get("message") or (
            "API 키·계좌·요금제 설정을 확인한 뒤 자동으로 다시 시도합니다."
            if language == "ko"
            else "Check API credentials, account settings, or billing; retry is automatic."
        ))
    elif state == "exit_only_protection":
        kind = "capital_protection"
        urgency = "critical"
        title = "자본 보호 모드" if language == "ko" else "Capital protection mode"
        body = (
            "신규 매수는 중지했고 기존 포지션의 보호 매도 감시는 계속합니다."
            if language == "ko"
            else "New entries are stopped; protective exit monitoring remains active."
        )
    elif state in (
        "error",
        "session_error",
        "protection_error",
        "protection_retrying",
        "retrying",
    ):
        failures = int(numeric(result.get("consecutiveFailures"), 1))
        kind = "scheduler_error"
        retrying = state in ("protection_retrying", "retrying")
        title = (
            "자동화 데이터 지연" if retrying else "자동화 점검 실패"
        ) if language == "ko" else (
            "Automation data delayed" if retrying else "Automation check failed"
        )
        body = (
            (
                f"자동 복구 대기 · {str(result.get('message') or '다음 주기에 다시 시도합니다.')[:180]}"
                if retrying
                else f"연속 실패 {failures}회 · {str(result.get('message') or '다음 주기에 다시 시도합니다.')[:180]}"
            )
            if language == "ko"
            else (
                f"Automatic retry pending · {str(result.get('message') or 'Will retry next cycle.')[:180]}"
                if retrying
                else f"{failures} consecutive failure(s) · {str(result.get('message') or 'Will retry next cycle.')[:180]}"
            )
        )
    else:
        return None

    identity = execution_id or plan_id or str(result.get("haltIncidentId") or "")
    if not identity:
        cause = (
            f"{kind}:{symbol}:{str(result.get('failureClass', ''))}:"
            f"{str(result.get('message', ''))[:180]}"
        )
        identity = hashlib.sha256(cause.encode("utf-8")).hexdigest()[:20]
    return {
        "kind": kind,
        "fingerprint": f"{kind}:{identity}",
        "title": title,
        "body": body,
        "urgency": urgency,
        "symbol": symbol,
    }


def notify_automation_event(event):
    try:
        result = subprocess.run(
            [
                "notify-send", "-a", "QS Stocks", "-u", event["urgency"], "-t", "12000",
                event["title"], event["body"],
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def process_automation_notification(result, notifier=notify_automation_event, now=None, enabled=None):
    enabled = load_automation_policy().get("notificationsEnabled", True) if enabled is None else bool(enabled)
    event = automation_notification_event(result)
    if not enabled:
        return {"status": "ok", "enabled": enabled, "triggered": 0, "delivered": 0}
    if event is None:
        with automation_notification_lock():
            runtime = load_automation_notifications()
            if runtime.get("activeIncident"):
                runtime["activeIncident"] = ""
                save_automation_notifications(runtime)
        return {"status": "ok", "enabled": True, "triggered": 0, "delivered": 0}
    timestamp = int(now if now is not None else time.time())
    with automation_notification_lock():
        runtime = load_automation_notifications()
        events = runtime.get("events") if isinstance(runtime.get("events"), list) else []
        incident = event["kind"] in (
            "scheduler_error",
            "kill_switch",
            "reconciliation",
            "operator_action",
            "capital_protection",
        )
        duplicate = (
            runtime.get("activeIncident") == event["fingerprint"]
            if incident
            else any(item.get("fingerprint") == event["fingerprint"] for item in events)
        )
        if duplicate:
            return {"status": "ok", "enabled": True, "triggered": 0, "delivered": 0, "duplicate": True}
        delivered = bool(notifier(event))
        record = dict(event, createdAt=timestamp, delivered=delivered)
        events.append(record)
        runtime = {
            "version": 1,
            "events": events[-NOTIFICATION_HISTORY_LIMIT:],
            "last": record,
            "activeIncident": event["fingerprint"] if incident else "",
            "updatedAt": timestamp,
        }
        save_automation_notifications(runtime)
    return {
        "status": "ok" if delivered else "unavailable",
        "enabled": True,
        "triggered": 1,
        "delivered": int(delivered),
        "event": record,
    }


def automation_notification_status():
    runtime = load_automation_notifications()
    events = runtime.get("events") if isinstance(runtime.get("events"), list) else []
    enabled = bool(load_automation_policy().get("notificationsEnabled", True))
    return {
        "status": "ok",
        "enabled": enabled,
        "events": list(reversed(events[-20:])),
        "delivered": sum(1 for event in events if event.get("delivered")),
        "failed": sum(1 for event in events if not event.get("delivered")),
        "last": runtime.get("last", {}),
        "updatedAt": int(numeric(runtime.get("updatedAt"))),
    }
