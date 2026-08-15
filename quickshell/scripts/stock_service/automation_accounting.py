import fcntl
import hashlib
import json
import os
import time
from contextlib import contextmanager
from datetime import datetime, timedelta

from .core import StockServiceError, numeric, state_directory
from .trading import kis_account_summary, kis_period_trade_profit
from .automation_costs import automation_transaction_costs


def automation_accounting_path():
    return os.path.join(state_directory(), "automation-accounting.json")


@contextmanager
def automation_accounting_lock():
    descriptor = os.open(automation_accounting_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def canonical_hash(value):
    payload = dict(value)
    payload.pop("stateHash", None)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def default_accounting_state():
    return {"version": 1, "environments": {}, "updatedAt": 0}


def load_accounting_state():
    try:
        with open(automation_accounting_path(), encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return default_accounting_state(), True
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_accounting_state(), False
    if not isinstance(state, dict) or numeric(state.get("version")) != 1:
        return default_accounting_state(), False
    return state, str(state.get("stateHash", "")) == canonical_hash(state)


def save_accounting_state(state):
    state = dict(state)
    state["stateHash"] = canonical_hash(state)
    path = automation_accounting_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return state


def position_identity(market, symbol):
    market = str(market or "KRX").strip().upper()
    symbol = str(symbol or "").strip().upper()
    return symbol if market == "KRX" else f"{market}:{symbol}"


def account_positions(account, default_market="KRX"):
    result = {}
    for holding in account.get("holdings", []):
        symbol = str(holding.get("symbol", "")).strip().upper()
        quantity = int(numeric(holding.get("quantity")))
        if not symbol or quantity <= 0:
            continue
        key = position_identity(holding.get("market", default_market), symbol)
        result[key] = result.get(key, 0) + quantity
    return result


def execution_fill_snapshot(records, environment):
    result = {}
    for record in records:
        if str(record.get("environment")) != environment:
            continue
        filled = max(0, int(numeric(record.get("filledQuantity"))))
        if filled <= 0:
            continue
        result[str(record.get("planId", ""))] = {
            "symbol": str(record.get("symbol", "")),
            "market": str(record.get("market", "KRX")).upper(),
            "positionKey": position_identity(
                record.get("market", "KRX"), record.get("symbol", ""),
            ),
            "currency": str(record.get("currency", "KRW")),
            "exchangeRate": numeric(record.get("exchangeRate"), 1),
            "side": str(record.get("side", "")),
            "quantity": filled,
            "averagePrice": numeric(record.get("averagePrice"), numeric(record.get("price"))),
            "commission": numeric(record.get("commission")),
            "tax": numeric(record.get("tax")),
            "costSource": str(record.get("costSource", "estimated")),
            "transactionCosts": dict(record.get("transactionCosts") or {}),
        }
    return result


def fill_economics(fill, quantity=None):
    filled = int(numeric(fill.get("quantity"))) if quantity is None else int(quantity)
    average = numeric(fill.get("averagePrice"))
    exchange_rate = max(0, numeric(fill.get("exchangeRate"), 1))
    if str(fill.get("currency", "KRW")).upper() == "KRW":
        exchange_rate = 1
    notional = max(0, filled * average)
    exact = fill.get("costSource") == "broker"
    costs = dict(fill.get("transactionCosts") or {})
    if not costs:
        costs = automation_transaction_costs(fill.get("market", "KRX"))
    commission = numeric(fill.get("commission")) if exact else (
        notional * numeric(costs.get("commissionBps")) / 10000
    )
    tax = numeric(fill.get("tax")) if exact else (
        notional * numeric(costs.get("sellTaxBps")) / 10000
        if fill.get("side") == "sell" else 0
    )
    cash_delta = notional - commission - tax if fill.get("side") == "sell" else -notional - commission
    return {
        "notional": notional * exchange_rate,
        "commission": commission * exchange_rate,
        "tax": tax * exchange_rate,
        "cashDelta": cash_delta * exchange_rate,
        "exchangeRate": exchange_rate,
        "exact": exact,
    }


def accounting_summary(fills):
    result = {
        "filledOrders": len(fills),
        "filledQuantity": 0,
        "turnoverKrw": 0,
        "commissionKrw": 0,
        "taxKrw": 0,
        "netCashFlowKrw": 0,
        "brokerCostFills": 0,
        "estimatedCostFills": 0,
        "realizedProfitLossKrw": 0,
        "unmatchedSellQuantity": 0,
    }
    inventory = {}
    for fill in fills.values():
        economics = fill_economics(fill)
        symbol = str(fill.get("positionKey") or fill.get("symbol", ""))
        quantity = int(numeric(fill.get("quantity")))
        result["filledQuantity"] += int(numeric(fill.get("quantity")))
        result["turnoverKrw"] += economics["notional"]
        result["commissionKrw"] += economics["commission"]
        result["taxKrw"] += economics["tax"]
        result["netCashFlowKrw"] += economics["cashDelta"]
        result["brokerCostFills" if economics["exact"] else "estimatedCostFills"] += 1
        position = inventory.get(symbol, {"quantity": 0, "cost": 0})
        if fill.get("side") == "buy":
            position["quantity"] += quantity
            position["cost"] += economics["notional"] + economics["commission"]
        else:
            matched = min(quantity, position["quantity"])
            average_cost = position["cost"] / position["quantity"] if position["quantity"] > 0 else 0
            proceeds = matched * numeric(fill.get("averagePrice")) * economics["exchangeRate"]
            allocated_costs = (
                economics["commission"] + economics["tax"]
            ) * matched / quantity if quantity > 0 else 0
            result["realizedProfitLossKrw"] += proceeds - allocated_costs - average_cost * matched
            position["quantity"] -= matched
            position["cost"] -= average_cost * matched
            result["unmatchedSellQuantity"] += quantity - matched
        inventory[symbol] = position
    for key in ("turnoverKrw", "commissionKrw", "taxKrw", "netCashFlowKrw", "realizedProfitLossKrw"):
        result[key] = int(round(result[key]))
    return result


def expected_positions(baseline, baseline_fills, current_fills):
    expected = dict(baseline)
    invalid = []
    for plan_id, fill in current_fills.items():
        previous = int(numeric((baseline_fills.get(plan_id) or {}).get("quantity")))
        quantity = int(numeric(fill.get("quantity")))
        delta = quantity - previous
        if delta < 0:
            invalid.append(plan_id)
            continue
        symbol = fill.get("positionKey") or fill.get("symbol", "")
        direction = 1 if fill.get("side") == "buy" else -1
        expected[symbol] = expected.get(symbol, 0) + direction * delta
        if expected[symbol] <= 0:
            expected.pop(symbol, None)
    return expected, invalid


def broker_accounts(environment):
    accounts = []
    for market in ("KRX", "NASDAQ", "NYSE"):
        account = kis_account_summary(
            environment, "", 0, "market" if market == "KRX" else "limit", market,
        )
        accounts.append((market, account))
    return accounts


def reconcile_automation_accounting(environment="paper", now=None, trusted_account=None):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported accounting environment")
    from .automation_execution import load_execution_records

    now = int(now if now is not None else time.time())
    accounts = (
        [(str(trusted_account.get("market", "KRX")).upper(), trusted_account)]
        if isinstance(trusted_account, dict)
        else broker_accounts(environment)
    )
    actual = {}
    for market, account in accounts:
        for key, quantity in account_positions(account, market).items():
            actual[key] = actual.get(key, 0) + quantity
    fills = execution_fill_snapshot(load_execution_records(5000), environment)
    with automation_accounting_lock():
        state, integrity = load_accounting_state()
        if not integrity:
            raise StockServiceError("Automation accounting state integrity check failed")
        environments = state.setdefault("environments", {})
        stored = environments.get(environment)
        calibrated = isinstance(stored, dict) and isinstance(stored.get("baselinePositions"), dict)
        if not calibrated:
            stored = {
                "baselinePositions": actual,
                "baselineFills": fills,
                "successfulReconciliations": 1,
                "calibratedAt": now,
                "lastSuccessfulAt": now,
            }
            expected = actual
            invalid = []
        else:
            expected, invalid = expected_positions(
                stored.get("baselinePositions", {}), stored.get("baselineFills", {}), fills,
            )
            if expected == actual and not invalid:
                if now - int(numeric(stored.get("lastSuccessfulAt"))) >= 60:
                    stored["successfulReconciliations"] = int(numeric(
                        stored.get("successfulReconciliations"),
                    )) + 1
                    stored["lastSuccessfulAt"] = now
        symbols = sorted(set(expected) | set(actual))
        mismatches = [
            {"symbol": symbol, "expected": expected.get(symbol, 0), "actual": actual.get(symbol, 0)}
            for symbol in symbols if expected.get(symbol, 0) != actual.get(symbol, 0)
        ]
        summary = accounting_summary(fills)
        if environment == "prod":
            end = datetime.fromtimestamp(now).date()
            start = end - timedelta(days=30)
            profit = kis_period_trade_profit(
                "prod", start.strftime("%Y%m%d"), end.strftime("%Y%m%d"),
            )
            summary["brokerPeriodProfit"] = profit
            summary["brokerKrxPeriodRealizedProfitLossKrw"] = int(round(numeric(
                (profit.get("totals") or {}).get("realizedProfitLoss"),
            )))
        healthy = not mismatches and not invalid
        if not healthy:
            stored["successfulReconciliations"] = 0
        stored.update({
            "environment": environment,
            "actualPositions": actual,
            "expectedPositions": expected,
            "fillSnapshot": fills,
            "mismatches": mismatches,
            "invalidFillRegressions": invalid,
            "summary": summary,
            "healthy": healthy,
            "lastReconciledAt": now,
        })
        environments[environment] = stored
        state["updatedAt"] = now
        save_accounting_state(state)
    return accounting_environment_status(stored, True)


def accounting_environment_status(stored, integrity):
    calibrated = bool(stored.get("calibratedAt"))
    checks = int(numeric(stored.get("successfulReconciliations")))
    healthy = integrity and calibrated and bool(stored.get("healthy"))
    gates = [
        {"code": "accounting_integrity", "passed": integrity, "message": "Accounting state checksum is valid"},
        {"code": "accounting_calibrated", "passed": calibrated, "message": "Broker positions have an accounting baseline"},
        {"code": "position_reconciliation", "passed": healthy,
         "message": "Expected and broker holding quantities reconcile"},
        {"code": "reconciliation_sample", "passed": checks >= 5,
         "message": "Five consecutive accounting reconciliations have passed", "value": checks, "threshold": 5},
    ]
    return {
        "status": "ok" if integrity else "error",
        "healthy": healthy,
        "eligible": all(gate["passed"] for gate in gates),
        "successfulReconciliations": checks,
        "mismatches": stored.get("mismatches", []),
        "summary": stored.get("summary", {}),
        "gates": gates,
        "updatedAt": int(numeric(stored.get("lastReconciledAt"))),
    }


def automation_accounting_status(environment="paper"):
    state, integrity = load_accounting_state()
    stored = (state.get("environments") or {}).get(environment, {})
    return accounting_environment_status(stored if isinstance(stored, dict) else {}, integrity)


def reset_automation_accounting(payload):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RESET AUTOMATION ACCOUNTING":
        raise StockServiceError("Accounting reset requires exact confirmation")
    with automation_accounting_lock():
        save_accounting_state(default_accounting_state())
    return automation_accounting_status()
