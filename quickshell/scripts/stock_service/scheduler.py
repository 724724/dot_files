import fcntl
import glob
import hashlib
import json
import os
import subprocess
import time
from contextlib import contextmanager

from .core import StockServiceError, numeric, state_directory
from .forecasting import evaluate_all_forecasts
from .quant import watchlist_quotes


BACKGROUND_SERVICE = "quickshell-stock-worker.service"
BACKGROUND_TIMER = "quickshell-stock-worker.timer"


def alert_runtime_path():
    return os.path.join(state_directory(), "price-alert-runtime.json")


def background_status_path():
    return os.path.join(state_directory(), "background-worker.json")


@contextmanager
def alert_runtime_lock():
    descriptor = os.open(alert_runtime_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def load_alert_runtime():
    try:
        with open(alert_runtime_path(), encoding="utf-8") as handle:
            value = json.load(handle)
        alerts = value.get("alerts") if isinstance(value, dict) else None
        return alerts if isinstance(alerts, dict) else {}
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {}


def save_alert_runtime(alerts, updated_at):
    path = alert_runtime_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(
            {"version": 1, "updatedAt": updated_at, "alerts": alerts},
            handle,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def save_background_status(result):
    path = background_status_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, separators=(",", ":"))
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def background_status():
    now = int(time.time())
    try:
        with open(background_status_path(), encoding="utf-8") as handle:
            last = json.load(handle)
        updated_at = int(numeric(last.get("updatedAt")))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return {"status": "ok", "workerStatus": "never_run", "ageSeconds": 0, "last": {}}
    age = max(0, now - updated_at)
    return {
        "status": "ok",
        "workerStatus": "active" if age <= 150 else "stale",
        "ageSeconds": age,
        "last": last,
    }


def systemctl_user(*arguments):
    try:
        return subprocess.run(
            ["systemctl", "--user", *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise StockServiceError(f"Could not control the background worker: {error}") from error


def background_control_status():
    enabled_result = systemctl_user("is-enabled", BACKGROUND_TIMER)
    active_result = systemctl_user("is-active", BACKGROUND_TIMER)
    enabled_state = enabled_result.stdout.strip()
    active_state = active_result.stdout.strip()
    enabled_detail = (enabled_result.stdout + enabled_result.stderr).lower()
    installed = (
        enabled_state not in ("", "not-found")
        and "not found" not in enabled_detail
        and "no such file" not in enabled_detail
    )
    enabled = enabled_state in ("enabled", "enabled-runtime", "linked", "linked-runtime")
    timer_active = active_state == "active"
    heartbeat = background_status()
    if not installed:
        message = "Background worker is not installed"
    elif enabled and timer_active:
        message = "Runs every minute while enabled"
    elif enabled:
        message = "Enabled, but the timer is not active"
    else:
        message = "Off · no periodic CPU or network wake-ups"
    return {
        "status": "ok",
        "installed": installed,
        "enabled": enabled,
        "timerActive": timer_active,
        "workerStatus": "disabled" if not enabled else heartbeat.get("workerStatus", "never_run"),
        "lastRunAgeSeconds": heartbeat.get("ageSeconds", 0),
        "message": message,
    }


def background_control(action):
    if action not in ("enable", "disable"):
        raise StockServiceError("Background action must be enable or disable")
    if action == "enable":
        result = systemctl_user("enable", "--now", BACKGROUND_TIMER)
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "Could not enable the background worker"
            raise StockServiceError(message[:240])
        result = systemctl_user("start", "--no-block", BACKGROUND_SERVICE)
        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "Could not start the background worker"
            raise StockServiceError(message[:240])
    else:
        result = systemctl_user("disable", "--now", BACKGROUND_TIMER)
        if result.returncode != 0 and "not loaded" not in result.stderr.lower():
            message = result.stderr.strip() or result.stdout.strip() or "Could not disable the background worker"
            raise StockServiceError(message[:240])
        result = systemctl_user("stop", BACKGROUND_SERVICE)
        if result.returncode != 0 and "not loaded" not in result.stderr.lower():
            message = result.stderr.strip() or result.stdout.strip() or "Could not stop the background worker"
            raise StockServiceError(message[:240])
    status = background_control_status()
    status["message"] = (
        "Background forecasts and alerts are running"
        if action == "enable"
        else "Background work stopped · no periodic CPU or network wake-ups"
    )
    return status


def discover_widgets_state_path(explicit_path=""):
    requested = explicit_path or os.environ.get("QS_STOCK_WIDGETS_STATE", "")
    if requested:
        path = os.path.expanduser(requested)
        return path if os.path.isfile(path) else ""
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    candidates = glob.glob(os.path.join(base, "quickshell", "by-shell", "*", "widgets.json"))
    candidates.extend(glob.glob(os.path.join(base, "quickshell", "*", "widgets.json")))
    candidates = list({path for path in candidates if os.path.isfile(path)})
    return max(candidates, key=os.path.getmtime) if candidates else ""


def stock_widget_configs(path=""):
    state_path = discover_widgets_state_path(path)
    if not state_path:
        return {"found": False, "path": "", "items": []}
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        return {"found": False, "path": state_path, "items": [], "error": str(error)}
    if isinstance(state, list):
        boards = {"legacy": state}
    else:
        boards = state.get("boards") if isinstance(state, dict) else {}
    if not isinstance(boards, dict):
        boards = {}
    items = []
    for board, rows in boards.items():
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict) or row.get("type") != "stock":
                continue
            payload = row.get("payload", {})
            try:
                config = json.loads(payload) if isinstance(payload, str) else dict(payload)
            except (ValueError, TypeError, json.JSONDecodeError):
                continue
            alerts = config.get("priceAlerts") if isinstance(config.get("priceAlerts"), list) else []
            items.append({
                "sourceId": f"{board}:{row.get('wid', 'stock')}",
                "mode": str(config.get("dataMode", "demo")).lower(),
                "environment": str(config.get("kisEnvironment", "paper")).lower(),
                "alerts": alerts[:16],
            })
    return {"found": True, "path": state_path, "items": items}


def alert_id(source_id, alert):
    value = str(alert.get("id", "")).strip()
    if value:
        return value
    identity = ":".join([
        source_id,
        str(alert.get("market", "KRX")),
        str(alert.get("symbol", "")),
        str(alert.get("direction", "above")),
        str(alert.get("target", "")),
    ])
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]


def normalized_alerts(configs):
    result = []
    for config in configs:
        source_id = str(config.get("sourceId", "stock"))
        mode = str(config.get("mode", "demo")).lower()
        environment = str(config.get("environment", "paper")).lower()
        if mode not in ("demo", "kis"):
            mode = "demo"
        if environment not in ("paper", "prod"):
            environment = "paper"
        for raw in config.get("alerts", [])[:16]:
            if not isinstance(raw, dict):
                continue
            symbol = str(raw.get("symbol", "")).strip().upper()
            market = str(raw.get("market", "KRX")).strip().upper()
            target = numeric(raw.get("target"))
            if not symbol or target <= 0:
                continue
            item = dict(raw)
            item.update({
                "id": alert_id(source_id, raw),
                "sourceId": source_id,
                "runtimeKey": source_id + ":" + alert_id(source_id, raw),
                "mode": mode,
                "environment": environment,
                "symbol": symbol,
                "market": market,
                "direction": "below" if raw.get("direction") == "below" else "above",
                "target": target,
            })
            result.append(item)
    return result


def quote_key(mode, environment, market, symbol):
    return ":".join((mode, environment, market, symbol))


def fetch_alert_quotes(configs):
    alerts = normalized_alerts(configs)
    grouped = {}
    for alert in alerts:
        if alert.get("enabled") is False:
            continue
        key = (alert["mode"], alert["environment"])
        grouped.setdefault(key, {})[(alert["market"], alert["symbol"])] = {
            "market": alert["market"],
            "symbol": alert["symbol"],
        }
    quotes = {}
    errors = []
    for (mode, environment), symbols in grouped.items():
        values = list(symbols.values())
        for offset in range(0, len(values), 8):
            try:
                response = watchlist_quotes(values[offset:offset + 8], mode, environment)
            except (OSError, TypeError, ValueError, StockServiceError) as error:
                errors.append({"mode": mode, "environment": environment, "message": str(error)[:240]})
                continue
            for quote in response.get("items", []):
                market = str(quote.get("market", "KRX")).upper()
                symbol = str(quote.get("symbol", "")).upper()
                quotes[quote_key(mode, environment, market, symbol)] = quote
                if quote.get("status") == "error":
                    errors.append({
                        "market": market,
                        "symbol": symbol,
                        "message": str(quote.get("message", "Quote unavailable"))[:240],
                    })
    return quotes, errors


def price_text(value, currency):
    if currency == "KRW":
        return f"₩{value:,.0f}"
    return f"${value:,.2f}"


def notify_price_alert(event):
    direction = "Falls below" if event["direction"] == "below" else "Rises above"
    title = f"{event['name']} price alert"
    body = (
        f"{direction} {price_text(event['target'], event['currency'])}"
        f" · Now {price_text(event['price'], event['currency'])}"
    )
    try:
        result = subprocess.run(
            ["notify-send", "-a", "Stocks", "-t", "10000", title, body],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def evaluate_alert_configs(configs, quotes, prune=False, notifier=notify_price_alert, now_ms=None):
    alerts = normalized_alerts(configs)
    timestamp = int(now_ms if now_ms is not None else time.time() * 1000)
    active_keys = {alert["runtimeKey"] for alert in alerts}
    notifications = []
    output = []
    with alert_runtime_lock():
        runtime = load_alert_runtime()
        for alert in alerts:
            key = alert["runtimeKey"]
            state = dict(runtime.get(key) or {})
            enabled = alert.get("enabled") is not False
            configured_triggered_at = int(numeric(alert.get("lastTriggeredAt")))
            configured_revision = int(numeric(alert.get("stateRevision")))
            if not state:
                state = {
                    "armed": alert.get("armed") is not False,
                    "lastTriggeredAt": configured_triggered_at,
                    "enabled": enabled,
                    "configRevision": configured_revision,
                }
            elif configured_revision > int(numeric(state.get("configRevision"))):
                state["armed"] = alert.get("armed") is not False
                state["enabled"] = enabled
                state["configRevision"] = configured_revision
            elif configured_triggered_at > int(numeric(state.get("lastTriggeredAt"))):
                state["armed"] = alert.get("armed") is not False
                state["lastTriggeredAt"] = configured_triggered_at
            if state.get("enabled") is False and enabled:
                state["armed"] = True
            state.update({
                "id": alert["id"],
                "sourceId": alert["sourceId"],
                "enabled": enabled,
                "symbol": alert["symbol"],
                "market": alert["market"],
                "direction": alert["direction"],
                "target": alert["target"],
                "updatedAt": timestamp,
            })
            quote = quotes.get(quote_key(
                alert["mode"],
                alert["environment"],
                alert["market"],
                alert["symbol"],
            ))
            price = numeric(quote.get("price")) if isinstance(quote, dict) and quote.get("status") != "error" else 0
            if enabled and price > 0:
                target = alert["target"]
                armed = state.get("armed") is not False
                crossed = price <= target if alert["direction"] == "below" else price >= target
                hysteresis = max(target * 0.002, 1 if alert["market"] == "KRX" else 0.01)
                rearmed = price >= target + hysteresis if alert["direction"] == "below" else price <= target - hysteresis
                if armed and crossed:
                    state["armed"] = False
                    state["lastTriggeredAt"] = timestamp
                    event = {
                        "name": str(quote.get("name") or alert["symbol"]),
                        "symbol": alert["symbol"],
                        "direction": alert["direction"],
                        "target": target,
                        "price": price,
                        "currency": str(quote.get("currency") or ("KRW" if alert["market"] == "KRX" else "USD")),
                    }
                    notifications.append(event)
                elif not armed and rearmed:
                    state["armed"] = True
                state["lastPrice"] = price
                state["quoteObservedAt"] = int(numeric(quote.get("updatedAt"), timestamp // 1000))
                state["quoteStatus"] = "ok"
            elif enabled:
                state["quoteStatus"] = "unavailable"
            else:
                state["quoteStatus"] = "paused"
            runtime[key] = state
            output.append(dict(state))
        if prune:
            runtime = {key: value for key, value in runtime.items() if key in active_keys}
        save_alert_runtime(runtime, timestamp)
    delivered = 0
    for event in notifications:
        try:
            delivered += int(bool(notifier(event)))
        except Exception:
            pass
    return {
        "status": "ok",
        "checked": len(alerts),
        "triggered": len(notifications),
        "delivered": delivered,
        "states": output,
        "updatedAt": timestamp,
    }


def evaluate_alert_payload(payload):
    if not isinstance(payload, dict):
        raise StockServiceError("Alert evaluation requires an object")
    source_id = str(payload.get("sourceId", "stock")).strip() or "stock"
    mode = str(payload.get("mode", "demo")).lower()
    environment = str(payload.get("environment", "paper")).lower()
    alerts = payload.get("alerts") if isinstance(payload.get("alerts"), list) else []
    quotes = {}
    for quote in payload.get("quotes", []):
        if not isinstance(quote, dict):
            continue
        market = str(quote.get("market", "KRX")).upper()
        symbol = str(quote.get("symbol", "")).upper()
        quotes[quote_key(mode, environment, market, symbol)] = quote
    return evaluate_alert_configs([{
        "sourceId": source_id,
        "mode": mode,
        "environment": environment,
        "alerts": alerts,
    }], quotes)


def run_background_cycle(widgets_path=""):
    started_at = time.monotonic()
    try:
        forecasts = evaluate_all_forecasts()
    except Exception as error:
        forecasts = {"status": "error", "message": str(error)[:240]}
    widget_state = stock_widget_configs(widgets_path)
    if widget_state["found"]:
        quotes, quote_errors = fetch_alert_quotes(widget_state["items"])
        try:
            alerts = evaluate_alert_configs(widget_state["items"], quotes, prune=True)
        except Exception as error:
            alerts = {"status": "error", "message": str(error)[:240]}
    else:
        quote_errors = []
        alerts = {"status": "unavailable", "checked": 0, "triggered": 0, "delivered": 0}
    failures = int(forecasts.get("status") == "error") + int(alerts.get("status") == "error")
    result = {
        "status": "ok" if failures == 0 and not quote_errors else "partial",
        "forecasts": forecasts,
        "alerts": {key: value for key, value in alerts.items() if key != "states"},
        "quoteErrors": quote_errors[:8],
        "widgetsState": widget_state.get("path", ""),
        "durationMs": max(0, int((time.monotonic() - started_at) * 1000)),
        "updatedAt": int(time.time()),
    }
    save_background_status(result)
    return result
