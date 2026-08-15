import fcntl
import hashlib
import json
import os
import time
from contextlib import contextmanager

from .core import StockServiceError, numeric, state_directory


def automation_position_path(directory=None):
    return os.path.join(directory or state_directory(), "automation-positions.json")


@contextmanager
def automation_position_lock(directory=None):
    descriptor = os.open(automation_position_path(directory) + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def position_state_hash(value):
    payload = {key: item for key, item in value.items() if key != "integrityHash"}
    try:
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise StockServiceError("Position risk state contains a non-canonical value") from error
    return hashlib.sha256(encoded).hexdigest()


def position_risk_audit_status(directory=None):
    path = automation_position_path(directory)
    if not os.path.exists(path):
        return {"healthy": True, "trackedPositions": 0, "reason": ""}
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict) or not isinstance(value.get("positions"), dict):
            raise ValueError("invalid state")
        expected = position_state_hash(value)
        if str(value.get("integrityHash", "")) != expected:
            return {"healthy": False, "trackedPositions": 0, "reason": "integrity_hash_mismatch"}
        return {
            "healthy": numeric(value.get("version")) == 1,
            "trackedPositions": len(value["positions"]),
            "reason": "" if numeric(value.get("version")) == 1 else "unsupported_version",
        }
    except (OSError, ValueError, TypeError, json.JSONDecodeError, StockServiceError):
        return {"healthy": False, "trackedPositions": 0, "reason": "invalid_state"}


def load_position_state(directory=None):
    audit = position_risk_audit_status(directory)
    if not audit["healthy"]:
        raise StockServiceError("Position risk state integrity check failed")
    if not os.path.exists(automation_position_path(directory)):
        return {"version": 1, "positions": {}}
    with open(automation_position_path(directory), encoding="utf-8") as handle:
        value = json.load(handle)
    return {"version": 1, "positions": dict(value.get("positions", {}))}


def save_position_state(value, directory=None):
    path = automation_position_path(directory)
    payload = {"version": 1, "positions": dict(value.get("positions", {}))}
    payload["integrityHash"] = position_state_hash(payload)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return payload


def observe_position_risk(
    environment, symbol, holding, price, policy, now=None, directory=None, market="KRX",
):
    now = int(now if now is not None else time.time())
    quantity = int(numeric(holding.get("quantity"))) if isinstance(holding, dict) else 0
    sellable = int(numeric(holding.get("sellableQuantity"))) if isinstance(holding, dict) else 0
    price = numeric(price)
    market = str(market or "KRX").strip().upper()
    key = f"{environment}:{market}:{symbol}"
    legacy_key = f"{environment}:{symbol}"
    with automation_position_lock(directory):
        state = load_position_state(directory)
        positions = state["positions"]
        if quantity <= 0 or price <= 0:
            if key in positions or legacy_key in positions:
                positions.pop(key, None)
                positions.pop(legacy_key, None)
                save_position_state(state, directory)
            return {
                "triggered": False,
                "reason": "",
                "symbol": symbol,
                "quantity": 0,
                "sellableQuantity": 0,
            }
        average = numeric(holding.get("averagePrice"), price)
        if average <= 0:
            average = price
        previous_value = positions.get(key, positions.get(legacy_key))
        previous = previous_value if isinstance(previous_value, dict) else {}
        previous_average = numeric(previous.get("averagePrice"))
        added = quantity > int(numeric(previous.get("quantity")))
        basis_changed = previous_average <= 0 or abs(previous_average / average - 1) > 0.001
        high_water = max(price, average) if added or basis_changed else max(
            price,
            average,
            numeric(previous.get("highWaterPrice")),
        )
        profit_percent = (price / average - 1) * 100
        peak_gain_percent = (high_water / average - 1) * 100
        drawdown_from_peak_percent = (price / high_water - 1) * 100
        hard_stop = profit_percent <= -numeric(policy.get("maxPositionLossPercent"), 3)
        trailing_armed = peak_gain_percent >= numeric(policy.get("trailingActivationPercent"), 5)
        trailing_stop = trailing_armed and drawdown_from_peak_percent <= -numeric(
            policy.get("trailingStopPercent"), 2,
        )
        reason = "hard_stop" if hard_stop else ("trailing_stop" if trailing_stop else "")
        record = {
            "environment": environment,
            "market": market,
            "symbol": symbol,
            "quantity": quantity,
            "sellableQuantity": sellable,
            "averagePrice": round(average, 4),
            "currentPrice": round(price, 4),
            "highWaterPrice": round(high_water, 4),
            "profitPercent": round(profit_percent, 4),
            "peakGainPercent": round(peak_gain_percent, 4),
            "drawdownFromPeakPercent": round(drawdown_from_peak_percent, 4),
            "trailingArmed": trailing_armed,
            "triggered": bool(reason and sellable > 0),
            "reason": reason if sellable > 0 else "",
            "updatedAt": now,
        }
        positions[key] = record
        positions.pop(legacy_key, None)
        save_position_state(state, directory)
        return record
