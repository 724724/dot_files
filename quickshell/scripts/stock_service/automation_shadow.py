import fcntl
import json
import math
import os
import time
from contextlib import contextmanager

from .automation import load_automation_policy
from .automation_execution import (
    automation_execution_status,
    load_execution_records,
    market_session_date,
)
from .core import StockServiceError, numeric, state_directory
from .automation_accounting import automation_accounting_status
from .automation_costs import automation_transaction_costs
from .automation_resilience import automation_resilience_status


SHADOW_STARTING_CAPITAL_KRW = 10_000_000
PROMOTION_THRESHOLDS = {
    "observations": 100,
    "sessions": 60,
    "closedTrades": 30,
    "netReturnPercent": 0,
    "excessReturnPercent": 0,
    "maxDrawdownPercent": 5,
    "profitFactor": 1.2,
    "winRatePercent": 45,
    "manualPaperFills": 20,
    "paperFillRatePercent": 80,
    "averageAdverseSlippageBps": 10,
    "p90AdverseSlippageBps": 25,
}


def automation_shadow_path():
    return os.path.join(state_directory(), "automation-shadow.json")


@contextmanager
def automation_shadow_lock():
    descriptor = os.open(automation_shadow_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def default_shadow_state(now=None):
    now = int(now if now is not None else time.time())
    return {
        "version": 1,
        "startingCapitalKrw": SHADOW_STARTING_CAPITAL_KRW,
        "cashKrw": SHADOW_STARTING_CAPITAL_KRW,
        "positions": {},
        "benchmarks": {},
        "processedPlanIds": [],
        "observations": [],
        "equityCurve": [],
        "trades": [],
        "observationCount": 0,
        "peakEquityKrw": SHADOW_STARTING_CAPITAL_KRW,
        "maxDrawdownPercent": 0,
        "realizedPnlKrw": 0,
        "totalCostsKrw": 0,
        "turnoverKrw": 0,
        "createdAt": now,
        "updatedAt": now,
    }


def normalized_shadow_state(value):
    state = default_shadow_state()
    if isinstance(value, dict):
        state.update(value)
    for key in ("positions", "benchmarks"):
        if not isinstance(state.get(key), dict):
            state[key] = {}
    for key in ("processedPlanIds", "observations", "equityCurve", "trades"):
        if not isinstance(state.get(key), list):
            state[key] = []
    return state


def load_shadow_state():
    try:
        with open(automation_shadow_path(), encoding="utf-8") as handle:
            return normalized_shadow_state(json.load(handle))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_shadow_state()


def save_shadow_state(state):
    path = automation_shadow_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, separators=(",", ":"))
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def shadow_position_key(plan):
    market = str(plan.get("market", "KRX")).strip().upper()
    symbol = str(plan.get("symbol", "")).strip().upper()
    return symbol if market == "KRX" else f"{market}:{symbol}"


def shadow_exchange_rate(plan):
    market = str(plan.get("market", "KRX")).strip().upper()
    if market == "KRX":
        return 1
    exchange_rate = numeric(plan.get("exchangeRate"))
    if exchange_rate <= 0:
        raise StockServiceError("Shadow portfolio requires a positive USD/KRW exchange rate")
    return exchange_rate


def shadow_transaction_costs(plan):
    costs = plan.get("transactionCosts")
    if isinstance(costs, dict) and costs:
        return {
            "commissionBps": max(0, numeric(costs.get("commissionBps"))),
            "slippageBps": max(0, numeric(costs.get("slippageBps"))),
            "sellTaxBps": max(0, numeric(costs.get("sellTaxBps"))),
            "sellCostLabel": str(costs.get("sellCostLabel", "")),
        }
    return automation_transaction_costs(
        plan.get("market", "KRX"), load_automation_policy(),
    )


def mark_shadow_positions(state, position_key, price_krw):
    if position_key in state["positions"] and price_krw > 0:
        state["positions"][position_key]["lastPrice"] = price_krw
    stock_value = 0
    invested_cost = 0
    for position in state["positions"].values():
        quantity = int(numeric(position.get("quantity")))
        stock_value += quantity * numeric(position.get("lastPrice"))
        invested_cost += quantity * numeric(position.get("averageCost"))
    equity = numeric(state.get("cashKrw")) + stock_value
    return equity, stock_value, stock_value - invested_cost


def record_shadow_benchmark(state, position_key, price_krw):
    benchmark = state["benchmarks"].get(position_key)
    if not isinstance(benchmark, dict) or numeric(benchmark.get("startPrice")) <= 0:
        benchmark = {"startPrice": price_krw, "lastPrice": price_krw}
    benchmark["lastPrice"] = price_krw
    state["benchmarks"][position_key] = benchmark


def shadow_benchmark_return(state):
    returns = []
    for benchmark in state["benchmarks"].values():
        start = numeric(benchmark.get("startPrice"))
        last = numeric(benchmark.get("lastPrice"))
        if start > 0 and last > 0:
            returns.append((last / start - 1) * 100)
    return round(sum(returns) / len(returns), 3) if returns else 0


def shadow_buy(state, plan, market_price, policy, now):
    market = str(plan.get("market", "KRX")).strip().upper()
    currency = str(plan.get("currency") or ("KRW" if market == "KRX" else "USD"))
    position_key = shadow_position_key(plan)
    exchange_rate = shadow_exchange_rate(plan)
    costs = shadow_transaction_costs(plan)
    slippage_bps = numeric(costs.get("slippageBps"))
    commission_bps = numeric(costs.get("commissionBps"))
    execution_price = market_price * (1 + slippage_bps / 10000)
    market_price_krw = market_price * exchange_rate
    execution_price_krw = execution_price * exchange_rate
    requested = int(numeric(plan.get("quantity")))
    equity, _, _ = mark_shadow_positions(state, position_key, market_price_krw)
    reserve = equity * numeric(policy["cashReservePercent"]) / 100
    cash_budget = max(0, numeric(state["cashKrw"]) - reserve)
    unit_cost = execution_price_krw * (1 + commission_bps / 10000)
    quantity = min(
        requested,
        int(math.floor(numeric(policy["maxOrderValueKrw"]) / market_price_krw)),
        int(math.floor(cash_budget / unit_cost)),
    )
    if quantity < 1:
        return None
    notional = quantity * execution_price_krw
    commission = notional * commission_bps / 10000
    total = notional + commission
    position = dict(state["positions"].get(position_key, {}))
    old_quantity = int(numeric(position.get("quantity")))
    old_cost = old_quantity * numeric(position.get("averageCost"))
    new_quantity = old_quantity + quantity
    position.update({
        "symbol": plan["symbol"],
        "market": market,
        "currency": currency,
        "exchangeRate": exchange_rate,
        "quantity": new_quantity,
        "averageCost": (old_cost + total) / new_quantity,
        "lastPrice": market_price_krw,
        "lastMarketPrice": market_price,
        "updatedAt": now,
    })
    state["positions"][position_key] = position
    state["cashKrw"] = numeric(state["cashKrw"]) - total
    slippage = quantity * market_price_krw * slippage_bps / 10000
    state["totalCostsKrw"] = numeric(state["totalCostsKrw"]) + commission + slippage
    state["turnoverKrw"] = numeric(state["turnoverKrw"]) + notional
    return {
        "planId": plan["planId"],
        "symbol": plan["symbol"],
        "market": market,
        "currency": currency,
        "exchangeRate": exchange_rate,
        "side": "buy",
        "quantity": quantity,
        "marketPrice": market_price,
        "executionPrice": execution_price,
        "notionalKrw": notional,
        "costsKrw": commission + slippage,
        "realizedPnlKrw": 0,
        "timestamp": now,
    }


def shadow_sell(state, plan, market_price, now):
    market = str(plan.get("market", "KRX")).strip().upper()
    currency = str(plan.get("currency") or ("KRW" if market == "KRX" else "USD"))
    position_key = shadow_position_key(plan)
    exchange_rate = shadow_exchange_rate(plan)
    costs = shadow_transaction_costs(plan)
    slippage_bps = numeric(costs.get("slippageBps"))
    commission_bps = numeric(costs.get("commissionBps"))
    sell_tax_bps = numeric(costs.get("sellTaxBps"))
    position = dict(state["positions"].get(position_key, {}))
    held = int(numeric(position.get("quantity")))
    quantity = min(held, int(numeric(plan.get("quantity"))))
    if quantity < 1:
        return None
    execution_price = market_price * (1 - slippage_bps / 10000)
    market_price_krw = market_price * exchange_rate
    execution_price_krw = execution_price * exchange_rate
    notional = quantity * execution_price_krw
    commission = notional * commission_bps / 10000
    tax = notional * sell_tax_bps / 10000
    proceeds = notional - commission - tax
    cost_basis = quantity * numeric(position.get("averageCost"))
    realized = proceeds - cost_basis
    remaining = held - quantity
    state["cashKrw"] = numeric(state["cashKrw"]) + proceeds
    state["realizedPnlKrw"] = numeric(state["realizedPnlKrw"]) + realized
    state["totalCostsKrw"] = (
        numeric(state["totalCostsKrw"])
        + commission
        + tax
        + quantity * market_price_krw * slippage_bps / 10000
    )
    state["turnoverKrw"] = numeric(state["turnoverKrw"]) + notional
    if remaining > 0:
        position.update({
            "quantity": remaining,
            "lastPrice": market_price_krw,
            "lastMarketPrice": market_price,
            "exchangeRate": exchange_rate,
            "updatedAt": now,
        })
        state["positions"][position_key] = position
    else:
        state["positions"].pop(position_key, None)
    slippage = quantity * market_price_krw * slippage_bps / 10000
    return {
        "planId": plan["planId"],
        "symbol": plan["symbol"],
        "market": market,
        "currency": currency,
        "exchangeRate": exchange_rate,
        "side": "sell",
        "quantity": quantity,
        "marketPrice": market_price,
        "executionPrice": execution_price,
        "notionalKrw": notional,
        "costsKrw": commission + tax + slippage,
        "realizedPnlKrw": realized,
        "timestamp": now,
    }


def shadow_metrics(state):
    equity, stock_value, unrealized = mark_shadow_positions(state, "", 0)
    starting = numeric(state.get("startingCapitalKrw"), SHADOW_STARTING_CAPITAL_KRW)
    benchmark_return = shadow_benchmark_return(state)
    sells = [trade for trade in state["trades"] if trade.get("side") == "sell"]
    wins = [trade for trade in sells if numeric(trade.get("realizedPnlKrw")) > 0]
    losses = [trade for trade in sells if numeric(trade.get("realizedPnlKrw")) < 0]
    gross_profit = sum(numeric(trade.get("realizedPnlKrw")) for trade in wins)
    gross_loss = abs(sum(numeric(trade.get("realizedPnlKrw")) for trade in losses))
    net_return = (equity / starting - 1) * 100 if starting > 0 else 0
    sessions = len({str(item.get("date", "")) for item in state["observations"] if item.get("date")})
    return {
        "startingCapitalKrw": int(round(starting)),
        "cashKrw": int(round(numeric(state.get("cashKrw")))),
        "stockValueKrw": int(round(stock_value)),
        "totalEquityKrw": int(round(equity)),
        "realizedPnlKrw": int(round(numeric(state.get("realizedPnlKrw")))),
        "unrealizedPnlKrw": int(round(unrealized)),
        "netReturnPercent": round(net_return, 3),
        "benchmarkReturnPercent": benchmark_return,
        "excessReturnPercent": round(net_return - benchmark_return, 3),
        "maxDrawdownPercent": round(numeric(state.get("maxDrawdownPercent")), 3),
        "totalCostsKrw": int(round(numeric(state.get("totalCostsKrw")))),
        "turnoverKrw": int(round(numeric(state.get("turnoverKrw")))),
        "observations": int(numeric(state.get("observationCount"))),
        "sessions": sessions,
        "trades": len(state["trades"]),
        "closedTrades": len(sells),
        "wins": len(wins),
        "losses": len(losses),
        "winRatePercent": round(len(wins) / len(sells) * 100, 2) if sells else 0,
        "profitFactor": round(gross_profit / gross_loss, 3) if gross_loss > 0 else (999 if gross_profit > 0 else 0),
        "openPositions": len(state["positions"]),
    }


def execution_quality(records):
    terminal = [
        record for record in records
        if str(record.get("brokerState")) in ("filled", "rejected", "canceled")
    ]
    fills = [record for record in terminal if str(record.get("brokerState")) == "filled"]
    adverse_slippage = []
    for record in fills:
        reference = numeric(record.get("price"))
        average = numeric(record.get("averagePrice"))
        side = str(record.get("side"))
        if reference <= 0 or average <= 0 or side not in ("buy", "sell"):
            continue
        direction = 1 if side == "buy" else -1
        adverse_slippage.append((average / reference - 1) * direction * 10000)
    ordered = sorted(adverse_slippage)
    percentile_index = max(0, math.ceil(len(ordered) * 0.9) - 1) if ordered else 0
    return {
        "terminalOrders": len(terminal),
        "filledOrders": len(fills),
        "qualifiedFills": len(adverse_slippage),
        "fillRatePercent": round(len(fills) / len(terminal) * 100, 2) if terminal else 0,
        "averageAdverseSlippageBps": round(
            sum(adverse_slippage) / len(adverse_slippage), 2,
        ) if adverse_slippage else 0,
        "p90AdverseSlippageBps": round(ordered[percentile_index], 2) if ordered else 0,
        "worstAdverseSlippageBps": round(max(ordered), 2) if ordered else 0,
    }


def shadow_promotion(metrics, scheduler_failures=0):
    execution = automation_execution_status()
    records = load_execution_records()
    audit = execution.get("audit", {})
    quality = execution_quality(records)
    manual_fills = quality["filledOrders"]
    accounting = automation_accounting_status("paper")
    resilience = automation_resilience_status()
    gates = [
        {"code": "shadow_observations", "passed": metrics["observations"] >= PROMOTION_THRESHOLDS["observations"],
         "message": "Shadow observation sample is sufficient", "value": metrics["observations"], "threshold": PROMOTION_THRESHOLDS["observations"]},
        {"code": "shadow_sessions", "passed": metrics["sessions"] >= PROMOTION_THRESHOLDS["sessions"],
         "message": "Shadow test spans enough trading sessions", "value": metrics["sessions"], "threshold": PROMOTION_THRESHOLDS["sessions"]},
        {"code": "shadow_trades", "passed": metrics["closedTrades"] >= PROMOTION_THRESHOLDS["closedTrades"],
         "message": "Closed shadow trade sample is sufficient", "value": metrics["closedTrades"], "threshold": PROMOTION_THRESHOLDS["closedTrades"]},
        {"code": "shadow_return", "passed": metrics["netReturnPercent"] > PROMOTION_THRESHOLDS["netReturnPercent"],
         "message": "Cost-adjusted shadow return is positive", "value": metrics["netReturnPercent"], "threshold": PROMOTION_THRESHOLDS["netReturnPercent"]},
        {"code": "shadow_excess", "passed": metrics["excessReturnPercent"] > PROMOTION_THRESHOLDS["excessReturnPercent"],
         "message": "Shadow portfolio beats its observed benchmark", "value": metrics["excessReturnPercent"], "threshold": PROMOTION_THRESHOLDS["excessReturnPercent"]},
        {"code": "shadow_drawdown", "passed": abs(metrics["maxDrawdownPercent"]) <= PROMOTION_THRESHOLDS["maxDrawdownPercent"],
         "message": "Shadow drawdown stays inside the promotion limit", "value": abs(metrics["maxDrawdownPercent"]), "threshold": PROMOTION_THRESHOLDS["maxDrawdownPercent"]},
        {"code": "shadow_profit_factor", "passed": metrics["profitFactor"] >= PROMOTION_THRESHOLDS["profitFactor"],
         "message": "Shadow profit factor clears the promotion floor", "value": metrics["profitFactor"], "threshold": PROMOTION_THRESHOLDS["profitFactor"]},
        {"code": "shadow_win_rate", "passed": metrics["winRatePercent"] >= PROMOTION_THRESHOLDS["winRatePercent"],
         "message": "Shadow win rate clears the promotion floor", "value": metrics["winRatePercent"], "threshold": PROMOTION_THRESHOLDS["winRatePercent"]},
        {"code": "paper_fills", "passed": manual_fills >= PROMOTION_THRESHOLDS["manualPaperFills"],
         "message": "Manual KIS paper fills are sufficient", "value": manual_fills, "threshold": PROMOTION_THRESHOLDS["manualPaperFills"]},
        {"code": "paper_fill_rate", "passed": quality["fillRatePercent"] >= PROMOTION_THRESHOLDS["paperFillRatePercent"],
         "message": "Paper order fill rate clears the promotion floor", "value": quality["fillRatePercent"], "threshold": PROMOTION_THRESHOLDS["paperFillRatePercent"]},
        {"code": "execution_slippage", "passed": (
            quality["qualifiedFills"] >= PROMOTION_THRESHOLDS["manualPaperFills"]
            and quality["averageAdverseSlippageBps"] <= PROMOTION_THRESHOLDS["averageAdverseSlippageBps"]
            and quality["p90AdverseSlippageBps"] <= PROMOTION_THRESHOLDS["p90AdverseSlippageBps"]
         ), "message": "Paper execution slippage stays inside the promotion limits",
         "value": quality["p90AdverseSlippageBps"], "threshold": PROMOTION_THRESHOLDS["p90AdverseSlippageBps"]},
        {"code": "execution_resolved", "passed": not execution.get("uncertaintyLock"),
         "message": "No paper execution is unresolved"},
        {"code": "audit_integrity", "passed": bool(audit.get("healthy")),
         "message": "Automation plans and execution journals pass integrity verification"},
        {"code": "scheduler_health", "passed": int(scheduler_failures) == 0,
         "message": "Observer has no consecutive operational failures", "value": int(scheduler_failures), "threshold": 0},
        {"code": "accounting_reconciliation", "passed": bool(accounting.get("eligible")),
         "message": "Paper holdings pass repeated accounting reconciliation"},
        {"code": "resilience_validation", "passed": bool(resilience.get("eligible")),
         "message": "Recent failure-recovery validation passes"},
    ]
    eligible = all(gate["passed"] for gate in gates)
    return {
        "eligible": eligible,
        "autoExecutionLocked": not eligible,
        "productionLocked": True,
        "gates": gates,
        "passed": sum(1 for gate in gates if gate["passed"]),
        "total": len(gates),
        "manualPaperFills": manual_fills,
        "executionQuality": quality,
        "audit": audit,
        "accounting": accounting,
        "resilience": resilience,
    }


def shadow_status(scheduler_failures=0):
    state = load_shadow_state()
    metrics = shadow_metrics(state)
    return {
        "status": "ok",
        "metrics": metrics,
        "promotion": shadow_promotion(metrics, scheduler_failures),
        "positions": list(state["positions"].values()),
        "recentTrades": list(reversed(state["trades"][-20:])),
        "equityCurve": state["equityCurve"][-180:],
        "updatedAt": int(numeric(state.get("updatedAt"))),
    }


def apply_shadow_plan(plan, market_price=None, now=None):
    if not isinstance(plan, dict) or not plan.get("planId"):
        raise StockServiceError("Shadow portfolio requires a valid automation plan")
    now = int(now if now is not None else time.time())
    price = numeric(market_price, numeric(plan.get("price")))
    if price <= 0:
        raise StockServiceError("Shadow portfolio requires a positive market price")
    with automation_shadow_lock():
        state = load_shadow_state()
        if plan["planId"] in state["processedPlanIds"]:
            return dict({"duplicate": True}, **shadow_status())
        symbol = str(plan.get("symbol", ""))
        market = str(plan.get("market", "KRX")).strip().upper()
        currency = str(plan.get("currency") or ("KRW" if market == "KRX" else "USD"))
        exchange_rate = shadow_exchange_rate(plan)
        position_key = shadow_position_key(plan)
        price_krw = price * exchange_rate
        date = market_session_date(now, market)
        record_shadow_benchmark(state, position_key, price_krw)
        mark_shadow_positions(state, position_key, price_krw)
        trade = None
        if plan.get("decision") == "ready":
            if plan.get("side") == "buy":
                trade = shadow_buy(state, plan, price, load_automation_policy(), now)
            elif plan.get("side") == "sell":
                trade = shadow_sell(state, plan, price, now)
        if trade:
            state["trades"].append(trade)
            state["trades"] = state["trades"][-1000:]
        state["processedPlanIds"].append(plan["planId"])
        state["processedPlanIds"] = state["processedPlanIds"][-5000:]
        state["observationCount"] = int(numeric(state.get("observationCount"))) + 1
        state["observations"].append({
            "planId": plan["planId"],
            "date": date,
            "timestamp": now,
            "symbol": symbol,
            "market": market,
            "currency": currency,
            "exchangeRate": exchange_rate,
            "decision": str(plan.get("decision", "")),
            "side": str(plan.get("side", "hold")),
            "price": price,
            "priceKrw": price_krw,
            "tradeApplied": bool(trade),
        })
        state["observations"] = state["observations"][-5000:]
        equity, _, _ = mark_shadow_positions(state, position_key, price_krw)
        state["peakEquityKrw"] = max(numeric(state.get("peakEquityKrw")), equity)
        peak = numeric(state.get("peakEquityKrw"))
        drawdown = (equity / peak - 1) * 100 if peak > 0 else 0
        state["maxDrawdownPercent"] = min(numeric(state.get("maxDrawdownPercent")), drawdown)
        point = {"date": date, "timestamp": now, "equityKrw": int(round(equity))}
        if state["equityCurve"] and state["equityCurve"][-1].get("date") == date:
            state["equityCurve"][-1] = point
        else:
            state["equityCurve"].append(point)
        state["equityCurve"] = state["equityCurve"][-1000:]
        state["updatedAt"] = now
        save_shadow_state(state)
        return dict({"duplicate": False, "tradeApplied": bool(trade)}, **shadow_status())


def reset_shadow_portfolio(payload):
    if not isinstance(payload, dict) or payload.get("confirmation") != "RESET SHADOW PORTFOLIO":
        raise StockServiceError("Shadow reset requires RESET SHADOW PORTFOLIO confirmation")
    with automation_shadow_lock():
        save_shadow_state(default_shadow_state())
    return shadow_status()
