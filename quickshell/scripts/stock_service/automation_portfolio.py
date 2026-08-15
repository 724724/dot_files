import math

from .core import StockServiceError, numeric
from .quant import demo_history_points, kis_history_points, normalized_history_points


def percentile(values, probability):
    ordered = sorted(values)
    if not ordered:
        return 0
    position = max(0, min(len(ordered) - 1, math.ceil(len(ordered) * probability) - 1))
    return ordered[position]


def history_returns(points):
    normalized = normalized_history_points(points)
    return {
        normalized[index]["t"]: normalized[index]["v"] / normalized[index - 1]["v"] - 1
        for index in range(1, len(normalized))
        if numeric(normalized[index - 1].get("v")) > 0
    }


def load_portfolio_history(
    symbol,
    target_symbol,
    target_points,
    mode,
    environment,
    market="KRX",
    target_market="KRX",
):
    market = str(market or "KRX").strip().upper()
    target_market = str(target_market or "KRX").strip().upper()
    if symbol == target_symbol and market == target_market:
        return target_points
    return (
        kis_history_points(environment, symbol, 120, market)
        if mode == "kis"
        else demo_history_points(symbol, market, 120)
    )


def portfolio_tail_risk(
    account,
    target_symbol,
    target_points,
    additional_notional,
    total_evaluation,
    mode,
    environment,
    policy,
    minimum_samples=60,
    market="KRX",
):
    market = str(market or "KRX").strip().upper()
    total = numeric(total_evaluation)
    additional = max(0, numeric(additional_notional))
    exposures = {}
    missing = []
    for holding in account.get("holdings", []):
        symbol = str(holding.get("symbol", "")).strip().upper()
        holding_market = str(holding.get("market", market) or market).strip().upper()
        evaluation = max(0, numeric(
            holding.get("evaluation"),
            numeric(holding.get("quantity")) * numeric(holding.get("price")),
        ))
        if symbol and evaluation > 0:
            identity = (holding_market, symbol)
            exposures[identity] = exposures.get(identity, 0) + evaluation
    if target_symbol and additional > 0:
        target_identity = (market, target_symbol)
        exposures[target_identity] = exposures.get(target_identity, 0) + additional
    returns = {}
    for identity in exposures:
        holding_market, symbol = identity
        try:
            values = history_returns(load_portfolio_history(
                symbol,
                target_symbol,
                target_points,
                mode,
                environment,
                holding_market,
                market,
            ))
        except (OSError, TypeError, ValueError, StockServiceError):
            values = {}
        if len(values) < minimum_samples:
            missing.append(identity)
        else:
            returns[identity] = values
    common = sorted(set.intersection(*(set(values) for values in returns.values()))) if returns else []
    common = common[-120:]
    available = total > 0 and not missing and bool(exposures) and len(common) >= minimum_samples
    portfolio_returns = []
    if available:
        for stamp in common:
            portfolio_returns.append(sum(
                returns[identity][stamp] * exposures[identity] / total
                for identity in exposures
            ))
    fifth = percentile(portfolio_returns, 0.05)
    tail = [value for value in portfolio_returns if value <= fifth]
    var95 = max(0, -fifth * 100)
    cvar95 = max(0, -(sum(tail) / len(tail)) * 100) if tail else 0
    worst_day = max(0, -min(portfolio_returns) * 100) if portfolio_returns else 0
    invested_percent = sum(exposures.values()) / total * 100 if total > 0 else 0
    market_shock = invested_percent * 0.10
    single_name_shock = max(exposures.values(), default=0) / total * 20 if total > 0 else 0
    historical_shock = worst_day * 1.5
    stress_loss = max(market_shock, single_name_shock, historical_shock)
    var_limit = numeric(policy.get("maxPortfolioVar95Percent"))
    cvar_limit = numeric(policy.get("maxPortfolioCvar95Percent"))
    stress_limit = numeric(policy.get("maxStressLossPercent"))
    gap_limit = numeric(policy.get("maxSingleDayLossPercent"))
    return {
        "available": available,
        "sampleSessions": len(common),
        "symbols": sorted(
            symbol if identity_market == "KRX" else f"{identity_market}:{symbol}"
            for identity_market, symbol in exposures
        ),
        "missingSymbols": sorted(
            symbol if identity_market == "KRX" else f"{identity_market}:{symbol}"
            for identity_market, symbol in missing
        ),
        "investedPercent": round(invested_percent, 3),
        "var95Percent": round(var95, 3),
        "cvar95Percent": round(cvar95, 3),
        "worstDayPercent": round(worst_day, 3),
        "stressLossPercent": round(stress_loss, 3),
        "scenarios": {
            "marketDown10Percent": round(market_shock, 3),
            "largestPositionDown20Percent": round(single_name_shock, 3),
            "historicalTailAmplified": round(historical_shock, 3),
        },
        "limits": {
            "var95Percent": var_limit,
            "cvar95Percent": cvar_limit,
            "stressLossPercent": stress_limit,
            "singleDayLossPercent": gap_limit,
        },
        "passed": available
        and var95 <= var_limit
        and cvar95 <= cvar_limit
        and stress_loss <= stress_limit
        and worst_day <= gap_limit,
    }
