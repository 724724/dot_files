from .trading import *
from zoneinfo import ZoneInfo


KRX_TIMEZONE = ZoneInfo("Asia/Seoul")
MARKET_TIMEZONES = {
    "KRX": KRX_TIMEZONE,
    "NASDAQ": ZoneInfo("America/New_York"),
    "NYSE": ZoneInfo("America/New_York"),
}

def demo_snapshot(symbol, market, period):
    symbol = symbol.strip().upper() or "005930"
    market = market.strip().upper() or "KRX"
    name, base, currency = SECURITIES.get(
        (market, symbol),
        (
            symbol,
            50000.0 if market == "KRX" else 100.0,
            "KRW" if market == "KRX" else "USD",
        ),
    )
    bucket = int(time.time() // 3600)
    seed = int(hashlib.sha256(f"{market}:{symbol}:{period}:{bucket}".encode()).hexdigest()[:16], 16)
    rng = random.Random(seed)
    count = {"30M": 30, "1D": 78, "1W": 70, "1M": 76, "3M": 90}.get(period, 78)
    volatility = {"30M": 0.0015, "1D": 0.0025, "1W": 0.004, "1M": 0.006, "3M": 0.009}.get(period, 0.003)
    direction = rng.uniform(-0.035, 0.055)
    value = base * (1.0 - direction)
    points = []
    now = int(time.time())
    step = {"30M": 60, "1D": 300, "1W": 3600, "1M": 14400, "3M": 86400}.get(period, 300)
    for i in range(count):
        progress = i / max(1, count - 1)
        drift = direction / count
        wave = math.sin(progress * math.pi * rng.uniform(2.5, 5.0)) * volatility * 0.22
        value *= 1.0 + drift + rng.gauss(0, volatility) + wave / count
        points.append({"t": now - (count - i - 1) * step, "v": round(max(value, base * 0.55), 2)})
    last = points[-1]["v"]
    change = last - base
    values = [point["v"] for point in points]
    return {
        "status": "ok",
        "mode": "demo",
        "range": period,
        "symbol": symbol,
        "market": market,
        "name": name,
        "currency": currency,
        "price": round(last, 2),
        "previousClose": round(base, 2),
        "change": round(change, 2),
        "changePct": round(change / base * 100.0, 2),
        "high": round(max(values), 2),
        "low": round(min(values), 2),
        "volume": rng.randint(850000, 18500000),
        "buyingPower": 10000000 if currency == "KRW" else 10000,
        "points": points,
        "updatedAt": now,
    }


def demo_history_points(symbol, market, count=260):
    symbol = symbol.strip().upper() or "005930"
    market = market.strip().upper() or "KRX"
    _, base, _ = SECURITIES.get(
        (market, symbol),
        (
            symbol,
            50000.0 if market == "KRX" else 100.0,
            "KRW" if market == "KRX" else "USD",
        ),
    )
    sessions = []
    timezone = MARKET_TIMEZONES.get(market, KRX_TIMEZONE)
    day = datetime.now(timezone).date()
    while len(sessions) < count:
        if day.weekday() < 5:
            sessions.append(day)
        day -= timedelta(days=1)
    sessions.reverse()
    seed = int(hashlib.sha256(f"backtest:{market}:{symbol}:{sessions[-1].isoformat()}".encode()).hexdigest()[:16], 16)
    rng = random.Random(seed)
    daily_drift = rng.uniform(-0.00015, 0.00065)
    daily_volatility = rng.uniform(0.009, 0.021)
    value = base * rng.uniform(0.72, 1.08)
    raw = []
    for index, session in enumerate(sessions):
        cycle = math.sin(index / 18.0) * daily_volatility * 0.12
        value *= max(0.72, 1 + daily_drift + cycle + rng.gauss(0, daily_volatility))
        stamp = int(datetime.combine(session, datetime.min.time(), tzinfo=timezone).timestamp())
        raw.append({"t": stamp, "v": value, "volume": rng.randint(850000, 18500000)})
    scale = base / raw[-1]["v"]
    return [{
        "t": point["t"],
        "v": round(point["v"] * scale, 2),
        "volume": point["volume"],
    } for point in raw]


def kis_history_points(environment, symbol, count=260, market="KRX"):
    market = str(market or "KRX").strip().upper()
    if market != "KRX":
        now = datetime.now(MARKET_TIMEZONES.get(market, KRX_TIMEZONE))
        cache_ttl = 15 * 60 if now.weekday() < 5 else 4 * 60 * 60
        cache_path = os.path.join(state_directory(), f"history-{environment}-{market}-{symbol}.json")
        try:
            if time.time() - os.path.getmtime(cache_path) < cache_ttl:
                with open(cache_path, encoding="utf-8") as handle:
                    cached = json.load(handle)
                cached_points = cached.get("points") if isinstance(cached, dict) else None
                if isinstance(cached_points, list) and len(cached_points) >= min(160, count):
                    return cached_points[-count:]
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            pass
        result = overseas_history_points(environment, symbol, market, count)
        if len(result) >= min(160, count):
            temporary = cache_path + ".tmp"
            with open(temporary, "w", encoding="utf-8") as handle:
                json.dump({"updatedAt": int(time.time()), "adjusted": True, "adjustmentMode": "1", "points": result}, handle, separators=(",", ":"))
            os.replace(temporary, cache_path)
        return result
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("KRX symbols must contain six digits")
    now = datetime.now(KRX_TIMEZONE)
    cache_ttl = 15 * 60 if now.weekday() < 5 and int(now.strftime("%H%M")) < 1540 else 4 * 60 * 60
    cache_path = os.path.join(state_directory(), f"history-{environment}-{symbol}.json")
    try:
        cache_modified_at = os.path.getmtime(cache_path)
        if time.time() - cache_modified_at < cache_ttl:
            with open(cache_path, encoding="utf-8") as handle:
                cached = json.load(handle)
            cached_points = cached.get("points") if isinstance(cached, dict) else None
            cached_at = numeric(cached.get("updatedAt"), cache_modified_at) if isinstance(cached, dict) else cache_modified_at
            adjustment_mode = cached.get("adjustmentMode") if isinstance(cached, dict) else ""
            close_ready_at = now.replace(hour=15, minute=40, second=0, microsecond=0).timestamp()
            needs_completed_close_refresh = (
                now.weekday() < 5
                and now.timestamp() >= close_ready_at
                and cached_at < close_ready_at
                and (
                    not cached_points
                    or datetime.fromtimestamp(int(cached_points[-1].get("t", 0)), KRX_TIMEZONE).date() < now.date()
                )
            )
            if (
                adjustment_mode == "1"
                and not needs_completed_close_refresh
                and isinstance(cached_points, list)
                and len(cached_points) >= min(160, count)
                and all(numeric(point.get("volume")) > 0 for point in cached_points[-min(20, len(cached_points)):])
            ):
                return cached_points[-count:]
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    end = now
    points = {}
    for _ in range(4):
        start = end - timedelta(days=540)
        response = kis_get(
            environment,
            "/uapi/domestic-stock/v1/quotations/inquire-daily-itemchartprice",
            "FHKST03010100",
            {
                "FID_COND_MRKT_DIV_CODE": "J",
                "FID_INPUT_ISCD": symbol,
                "FID_INPUT_DATE_1": start.strftime("%Y%m%d"),
                "FID_INPUT_DATE_2": end.strftime("%Y%m%d"),
                "FID_PERIOD_DIV_CODE": "D",
                "FID_ORG_ADJ_PRC": "1",
            },
        )
        dates = []
        for row in response.get("output2") or []:
            date_text = str(row.get("stck_bsop_date", ""))
            value = numeric(row.get("stck_clpr"))
            volume = int(numeric(row.get("acml_vol")))
            if date_text == now.strftime("%Y%m%d") and now.weekday() < 5 and int(now.strftime("%H%M")) < 1540:
                continue
            if len(date_text) == 8 and value > 0 and volume > 0:
                dates.append(date_text)
                points[date_text] = {"value": value, "volume": volume}
        if len(points) >= count or not dates:
            break
        next_end = datetime.strptime(min(dates), "%Y%m%d").replace(tzinfo=KRX_TIMEZONE) - timedelta(days=1)
        if next_end >= end:
            break
        end = next_end
        time.sleep(0.55 if environment == "paper" else 0.12)
    ordered = sorted(points.items())[-count:]
    result = [
        {
            "t": int(datetime.strptime(date_text, "%Y%m%d").replace(tzinfo=KRX_TIMEZONE).timestamp()),
            "v": item["value"],
            "volume": item["volume"],
        }
        for date_text, item in ordered
    ]
    if len(result) >= min(160, count):
        temporary = cache_path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "updatedAt": int(time.time()),
                    "adjusted": True,
                    "adjustmentMode": "1",
                    "points": result,
                },
                handle,
                separators=(",", ":"),
            )
        os.chmod(temporary, 0o600)
        os.replace(temporary, cache_path)
    return result


def backtest_rsi(values, index, period=14):
    start = max(1, index - period + 1)
    deltas = [values[position] - values[position - 1] for position in range(start, index + 1)]
    gains = sum(max(0, value) for value in deltas) / max(1, len(deltas))
    losses = sum(max(0, -value) for value in deltas) / max(1, len(deltas))
    if losses == 0:
        return 100 if gains > 0 else 50
    return 100 - 100 / (1 + gains / losses)


def compact_equity(points, limit=180):
    if len(points) <= limit:
        return points
    step = (len(points) - 1) / (limit - 1)
    indexes = sorted(set(round(index * step) for index in range(limit)))
    return [points[index] for index in indexes]


def normalized_history_points(points):
    unique = {
        int(point["t"]): {
            "t": int(point["t"]),
            "v": numeric(point["v"]),
        }
        for point in points
        if numeric(point.get("v")) > 0
    }
    return sorted(unique.values(), key=lambda point: point["t"])


def bounded(value, minimum, maximum):
    return max(minimum, min(maximum, value))


def technical_screen_metrics(points):
    points = normalized_history_points(points)
    if len(points) < 61:
        raise StockServiceError("At least 61 completed daily closes are required for screening")
    values = [point["v"] for point in points]
    current = values[-1]
    sma20 = sum(values[-20:]) / 20
    sma60 = sum(values[-60:]) / 60
    momentum20 = (current / values[-21] - 1) * 100
    momentum60 = (current / values[-61] - 1) * 100
    rsi14 = backtest_rsi(values, len(values) - 1, 14)
    daily_returns = [values[index] / values[index - 1] - 1 for index in range(len(values) - 59, len(values))]
    mean_return = sum(daily_returns) / len(daily_returns)
    variance = sum((value - mean_return) ** 2 for value in daily_returns) / max(1, len(daily_returns) - 1)
    volatility = math.sqrt(variance) * math.sqrt(252) * 100
    peak60 = max(values[-60:])
    drawdown60 = (current / peak60 - 1) * 100
    trend_spread = (sma20 / sma60 - 1) * 100
    components = {
        "trend": bounded(trend_spread * 5, -35, 35),
        "momentum20": bounded(momentum20 * 1.5, -25, 25),
        "momentum60": bounded(momentum60 * 0.5, -15, 15),
        "rsi": bounded((rsi14 - 50) * 0.3, -15, 15),
        "drawdown": bounded(drawdown60 * 0.5, -10, 0),
    }
    score = round(bounded(sum(components.values()), -100, 100))
    stance = "bullish" if score >= 20 else ("bearish" if score <= -20 else "neutral")
    return {
        "score": score,
        "stance": stance,
        "signalStrength": abs(score),
        "close": round(current, 4),
        "sma20": round(sma20, 4),
        "sma60": round(sma60, 4),
        "trendSpreadPct": round(trend_spread, 2),
        "momentum20Pct": round(momentum20, 2),
        "momentum60Pct": round(momentum60, 2),
        "rsi14": round(rsi14, 1),
        "annualizedVolatilityPct": round(volatility, 1),
        "drawdown60Pct": round(drawdown60, 2),
        "sampleCount": len(points),
        "asOf": points[-1]["t"],
        "components": {key: round(value, 2) for key, value in components.items()},
    }


def backtest_variants(strategy):
    if strategy == "trend":
        return [
            {"short": 5, "long": 20, "label": "MA 5/20"},
            {"short": 10, "long": 30, "label": "MA 10/30"},
            {"short": 20, "long": 60, "label": "MA 20/60"},
        ]
    if strategy == "momentum":
        return [
            {"lookback": 20, "label": "20 sessions"},
            {"lookback": 10, "label": "10 sessions"},
            {"lookback": 60, "label": "60 sessions"},
        ]
    return [
        {"period": 14, "enter": 35, "exit": 55, "label": "RSI 35/55"},
        {"period": 14, "enter": 30, "exit": 50, "label": "RSI 30/50"},
        {"period": 14, "enter": 40, "exit": 60, "label": "RSI 40/60"},
    ]


def backtest_positions(values, strategy, variant):
    positions = [0] * len(values)
    if strategy == "trend":
        short = int(variant["short"])
        long = int(variant["long"])
        for index in range(long - 1, len(values) - 1):
            short_average = sum(values[index - short + 1:index + 1]) / short
            long_average = sum(values[index - long + 1:index + 1]) / long
            positions[index] = int(short_average > long_average)
    elif strategy == "momentum":
        lookback = int(variant["lookback"])
        for index in range(lookback, len(values) - 1):
            positions[index] = int(values[index] > values[index - lookback])
    else:
        period = int(variant["period"])
        position = 0
        for index in range(period, len(values) - 1):
            rsi = backtest_rsi(values, index, period)
            if position == 0 and rsi < numeric(variant["enter"]):
                position = 1
            elif position == 1 and rsi > numeric(variant["exit"]):
                position = 0
            positions[index] = position
    return positions


def simulate_backtest(points, positions, start_index, end_index, costs):
    start_index = max(1, int(start_index))
    end_index = min(int(end_index), len(points) - 1)
    strategy_equity = 1.0
    benchmark_equity = 1.0
    previous_position = 0
    changes = 0
    invested = 0
    positive = 0
    accumulated_cost = 0.0
    strategy_returns = []
    benchmark_returns = []
    equity = [{"t": points[start_index]["t"], "strategy": 100.0, "benchmark": 100.0, "position": 0}]
    commission_rate = costs["commissionBps"] / 10000
    slippage_rate = costs["slippageBps"] / 10000
    tax_rate = costs["sellTaxBps"] / 10000
    for index in range(start_index, end_index):
        position = int(positions[index])
        market_return = points[index + 1]["v"] / points[index]["v"] - 1
        switching_cost = abs(position - previous_position) * (commission_rate + slippage_rate)
        if previous_position == 1 and position == 0:
            switching_cost += tax_rate
        strategy_return = max(-0.999, position * market_return - switching_cost)
        strategy_equity *= 1 + strategy_return
        benchmark_equity *= 1 + market_return
        strategy_returns.append(strategy_return)
        benchmark_returns.append(market_return)
        accumulated_cost += switching_cost
        if position != previous_position:
            changes += 1
        if position:
            invested += 1
            positive += int(market_return > 0)
        equity.append({
            "t": points[index + 1]["t"],
            "strategy": round(strategy_equity * 100, 4),
            "benchmark": round(benchmark_equity * 100, 4),
            "position": position,
        })
        previous_position = position
    peak = 0
    max_drawdown = 0
    for point in equity:
        peak = max(peak, point["strategy"])
        max_drawdown = min(max_drawdown, point["strategy"] / peak - 1 if peak else 0)
    mean_return = sum(strategy_returns) / max(1, len(strategy_returns))
    variance = sum((value - mean_return) ** 2 for value in strategy_returns) / max(1, len(strategy_returns) - 1)
    daily_volatility = math.sqrt(variance)
    gross_profit = sum(max(0, value) for value in strategy_returns)
    gross_loss = sum(max(0, -value) for value in strategy_returns)
    return {
        "sampleCount": len(strategy_returns),
        "from": points[start_index]["t"],
        "to": points[end_index]["t"],
        "strategyReturnPct": round((strategy_equity - 1) * 100, 2),
        "benchmarkReturnPct": round((benchmark_equity - 1) * 100, 2),
        "excessReturnPct": round((strategy_equity - benchmark_equity) * 100, 2),
        "maxDrawdownPct": round(max_drawdown * 100, 2),
        "annualizedVolatilityPct": round(daily_volatility * math.sqrt(252) * 100, 2),
        "sharpe": round(mean_return / daily_volatility * math.sqrt(252), 2) if daily_volatility > 0 else 0,
        "trades": changes,
        "turnoverAnnualized": round(changes / max(1, len(strategy_returns)) * 252, 1),
        "profitFactor": round(gross_profit / gross_loss, 2) if gross_loss > 0 else (99.99 if gross_profit > 0 else 0),
        "hitRate": round(positive / invested * 100, 1) if invested else 0,
        "investedPct": round(invested / max(1, len(strategy_returns)) * 100, 1),
        "estimatedCostPct": round(accumulated_cost * 100, 3),
        "equity": compact_equity(equity),
        "_strategyReturns": strategy_returns,
        "_benchmarkReturns": benchmark_returns,
    }


def walk_forward_backtest(points, strategy, costs):
    values = [point["v"] for point in points]
    variants = backtest_variants(strategy)
    positions = [(variant, backtest_positions(values, strategy, variant)) for variant in variants]
    final_period = len(points) - 1
    test_sessions = 30
    fold_count = min(4, max(2, (final_period - 80) // test_sessions))
    first_test = final_period - fold_count * test_sessions
    folds = []
    combined_strategy_returns = []
    combined_benchmark_returns = []
    for fold_index in range(fold_count):
        test_start = first_test + fold_index * test_sessions
        test_end = min(final_period, test_start + test_sessions)
        train_start = max(59, test_start - 80)
        candidates = []
        for variant, variant_positions in positions:
            training = simulate_backtest(points, variant_positions, train_start, test_start, costs)
            score = numeric(training["sharpe"]) + numeric(training["strategyReturnPct"]) / 100
            candidates.append((score, numeric(training["strategyReturnPct"]), variant, variant_positions))
        score, train_return, selected, selected_positions = max(candidates, key=lambda item: (item[0], item[1]))
        testing = simulate_backtest(points, selected_positions, test_start, test_end, costs)
        combined_strategy_returns.extend(testing["_strategyReturns"])
        combined_benchmark_returns.extend(testing["_benchmarkReturns"])
        folds.append({
            "fold": fold_index + 1,
            "from": testing["from"],
            "to": testing["to"],
            "trainSessions": test_start - train_start,
            "parameter": selected["label"],
            "trainScore": round(score, 2),
            "trainReturnPct": round(train_return, 2),
            "returnPct": testing["strategyReturnPct"],
            "benchmarkReturnPct": testing["benchmarkReturnPct"],
            "excessReturnPct": testing["excessReturnPct"],
            "maxDrawdownPct": testing["maxDrawdownPct"],
            "outperformed": testing["excessReturnPct"] > 0,
        })
    strategy_equity = 1.0
    benchmark_equity = 1.0
    peak = 1.0
    max_drawdown = 0.0
    for strategy_return, benchmark_return in zip(combined_strategy_returns, combined_benchmark_returns):
        strategy_equity *= 1 + strategy_return
        benchmark_equity *= 1 + benchmark_return
        peak = max(peak, strategy_equity)
        max_drawdown = min(max_drawdown, strategy_equity / peak - 1)
    mean_return = sum(combined_strategy_returns) / max(1, len(combined_strategy_returns))
    variance = sum(
        (value - mean_return) ** 2
        for value in combined_strategy_returns
    ) / max(1, len(combined_strategy_returns) - 1)
    volatility = math.sqrt(variance)
    wins = sum(1 for fold in folds if fold["outperformed"])
    win_rate = round(wins / max(1, len(folds)) * 100, 1)
    excess_return = (strategy_equity - benchmark_equity) * 100
    if win_rate >= 75 and excess_return > 0:
        status = "robust"
    elif win_rate >= 50 or excess_return > 0:
        status = "mixed"
    else:
        status = "weak"
    return {
        "status": status,
        "statusLabel": {"robust": "Robust", "mixed": "Mixed", "weak": "Weak"}[status],
        "trainSessions": min((fold["trainSessions"] for fold in folds), default=0),
        "testSessions": test_sessions,
        "foldCount": len(folds),
        "outperformedFolds": wins,
        "foldWinRate": win_rate,
        "oosReturnPct": round((strategy_equity - 1) * 100, 2),
        "benchmarkReturnPct": round((benchmark_equity - 1) * 100, 2),
        "excessReturnPct": round(excess_return, 2),
        "maxDrawdownPct": round(max_drawdown * 100, 2),
        "sharpe": round(mean_return / volatility * math.sqrt(252), 2) if volatility > 0 else 0,
        "folds": folds,
        "methodology": (
            "Each fold selects one parameter set on the prior 80 sessions, then freezes it "
            "for the next 30-session out-of-sample window."
        ),
    }


def run_backtest(symbol, market, mode, environment, strategy, commission_bps=1.5, slippage_bps=5, sell_tax_bps=15):
    symbol = symbol.strip().upper()
    market = market.strip().upper()
    if strategy not in BACKTEST_STRATEGIES:
        raise StockServiceError("Unsupported backtest strategy")
    if mode not in ("demo", "kis") or environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported backtest data source")
    costs = {
        "commissionBps": numeric(commission_bps, 1.5),
        "slippageBps": numeric(slippage_bps, 5),
        "sellTaxBps": numeric(sell_tax_bps, 15),
    }
    if any(value < 0 or value > 100 for value in costs.values()):
        raise StockServiceError("Each execution cost must be between 0 and 100 bps")
    points = kis_history_points(environment, symbol, market=market) if mode == "kis" else demo_history_points(symbol, market)
    points = normalized_history_points(points)
    if len(points) < 160:
        raise StockServiceError("At least 160 completed daily closes are required for walk-forward validation")
    values = [point["v"] for point in points]
    default_variant = backtest_variants(strategy)[0]
    default_positions = backtest_positions(values, strategy, default_variant)
    full = simulate_backtest(points, default_positions, 60, len(points) - 1, costs)
    walk_forward = walk_forward_backtest(points, strategy, costs)
    label, description = BACKTEST_STRATEGIES[strategy]
    result = {
        "status": "ok",
        "symbol": symbol,
        "market": market,
        "dataMode": mode,
        "environment": environment,
        "strategy": strategy,
        "strategyLabel": label,
        "description": description,
        "parameter": default_variant["label"],
        "costs": {key: round(value, 1) for key, value in costs.items()},
        "priceBasis": (
            "KIS adjusted completed daily closes"
            if mode == "kis"
            else "Synthetic adjusted completed daily closes"
        ),
        "walkForward": walk_forward,
        "methodology": (
            "Signals use only completed adjusted closes available at each session and apply "
            "to the next session. Long/cash only; commission and slippage apply on every "
            "switch, with tax on exits."
        ),
        "disclaimer": "Historical simulation only. It is not investment advice, a prediction, or an order signal.",
    }
    result.update({key: value for key, value in full.items() if not key.startswith("_")})
    return result


def annualized_return(return_pct, sessions):
    multiple = max(0, 1 + numeric(return_pct) / 100)
    if multiple == 0:
        return -100.0
    return (multiple ** (252 / max(1, int(sessions))) - 1) * 100


def strategy_comparison(symbol, market, mode, environment, commission_bps=1.5, slippage_bps=5, sell_tax_bps=15):
    symbol = symbol.strip().upper()
    market = market.strip().upper()
    if mode not in ("demo", "kis") or environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported comparison data source")
    costs = {
        "commissionBps": numeric(commission_bps, 1.5),
        "slippageBps": numeric(slippage_bps, 5),
        "sellTaxBps": numeric(sell_tax_bps, 15),
    }
    if any(value < 0 or value > 100 for value in costs.values()):
        raise StockServiceError("Each execution cost must be between 0 and 100 bps")
    points = kis_history_points(environment, symbol, market=market) if mode == "kis" else demo_history_points(symbol, market)
    points = normalized_history_points(points)
    if len(points) < 160:
        raise StockServiceError("At least 160 completed daily closes are required for strategy comparison")
    values = [point["v"] for point in points]
    items = []
    for strategy, (label, description) in BACKTEST_STRATEGIES.items():
        default_variant = backtest_variants(strategy)[0]
        positions = backtest_positions(values, strategy, default_variant)
        full = simulate_backtest(points, positions, 60, len(points) - 1, costs)
        validation = walk_forward_backtest(points, strategy, costs)
        full_annual = annualized_return(full["strategyReturnPct"], full["sampleCount"])
        full_benchmark_annual = annualized_return(full["benchmarkReturnPct"], full["sampleCount"])
        oos_sessions = validation["foldCount"] * validation["testSessions"]
        oos_annual = annualized_return(validation["oosReturnPct"], oos_sessions)
        oos_benchmark_annual = annualized_return(validation["benchmarkReturnPct"], oos_sessions)
        decay = full_annual - oos_annual
        unique_parameters = len(set(fold["parameter"] for fold in validation["folds"]))
        reasons = []
        risk_points = 0
        if full_annual - full_benchmark_annual > 0 and oos_annual - oos_benchmark_annual <= 0:
            reasons.append("In-sample edge disappears OOS")
            risk_points += 2
        if validation["foldWinRate"] <= 25:
            reasons.append("Outperforms in at most one fold")
            risk_points += 2
        if decay > 20:
            reasons.append("Large OOS performance decay")
            risk_points += 2
        elif decay > 10:
            reasons.append("Moderate OOS performance decay")
            risk_points += 1
        if unique_parameters > 2:
            reasons.append("Parameter selection is unstable")
            risk_points += 1
        if validation["sharpe"] < 0:
            reasons.append("OOS risk-adjusted return is negative")
            risk_points += 1
        overfit_risk = "high" if risk_points >= 3 else ("moderate" if risk_points >= 1 else "low")
        if not reasons:
            reasons.append("OOS behavior is comparatively consistent")
        fold_score = validation["foldWinRate"] * 0.35
        excess_score = max(0, min(25, (validation["excessReturnPct"] + 10) / 20 * 25))
        sharpe_score = max(0, min(20, (validation["sharpe"] + 0.5) / 2 * 20))
        drawdown_score = max(0, min(20, (1 - abs(validation["maxDrawdownPct"]) / 30) * 20))
        risk_penalty = 10 if overfit_risk == "high" else (4 if overfit_risk == "moderate" else 0)
        robustness_score = round(max(
            0,
            min(
                100,
                fold_score
                + excess_score
                + sharpe_score
                + drawdown_score
                - risk_penalty,
            ),
        ))
        items.append({
            "strategy": strategy,
            "label": label,
            "description": description,
            "parameter": default_variant["label"],
            "fullReturnPct": full["strategyReturnPct"],
            "fullExcessReturnPct": full["excessReturnPct"],
            "maxDrawdownPct": full["maxDrawdownPct"],
            "sharpe": full["sharpe"],
            "hitRate": full["hitRate"],
            "profitFactor": full["profitFactor"],
            "turnoverAnnualized": full["turnoverAnnualized"],
            "estimatedCostPct": full["estimatedCostPct"],
            "oosReturnPct": validation["oosReturnPct"],
            "oosExcessReturnPct": validation["excessReturnPct"],
            "oosMaxDrawdownPct": validation["maxDrawdownPct"],
            "oosSharpe": validation["sharpe"],
            "foldWins": validation["outperformedFolds"],
            "foldCount": validation["foldCount"],
            "foldWinRate": validation["foldWinRate"],
            "fullAnnualizedReturnPct": round(full_annual, 2),
            "oosAnnualizedReturnPct": round(oos_annual, 2),
            "performanceDecayPct": round(decay, 2),
            "uniqueParameters": unique_parameters,
            "overfitRisk": overfit_risk,
            "overfitReasons": reasons[:3],
            "robustnessScore": robustness_score,
        })
    items.sort(key=lambda item: (item["robustnessScore"], item["oosExcessReturnPct"], item["oosSharpe"]), reverse=True)
    for index, item in enumerate(items):
        item["rank"] = index + 1
    best = items[0]
    return {
        "status": "ok",
        "symbol": symbol,
        "market": market,
        "dataMode": mode,
        "environment": environment,
        "from": points[60]["t"],
        "to": points[-1]["t"],
        "sampleCount": len(points) - 61,
        "priceBasis": (
            "KIS adjusted completed daily closes"
            if mode == "kis"
            else "Synthetic adjusted completed daily closes"
        ),
        "costs": {key: round(value, 1) for key, value in costs.items()},
        "bestStrategy": best["strategy"],
        "bestLabel": best["label"],
        "bestScore": best["robustnessScore"],
        "highRiskCount": sum(1 for item in items if item["overfitRisk"] == "high"),
        "items": items,
        "methodology": (
            "Strategies share identical adjusted closes and execution costs. Ranking "
            "emphasizes out-of-sample fold wins, excess return, Sharpe, drawdown, and "
            "overfit warnings."
        ),
        "disclaimer": "This heuristic comparison is not investment advice, a prediction, or an order signal.",
    }


def watchlist_quotes(items, mode="demo", environment="paper"):
    if mode not in ("demo", "kis"):
        raise StockServiceError("Unsupported watchlist data mode")
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported watchlist environment")
    if not isinstance(items, list):
        raise StockServiceError("Watchlist must be an array")
    normalized = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        symbol = str(item.get("symbol", "")).strip().upper()
        market = str(item.get("market", "KRX")).strip().upper()
        identity = (market, symbol)
        if not symbol or identity in seen:
            continue
        seen.add(identity)
        normalized.append(identity)
    quotes = []
    for market, symbol in normalized:
        try:
            quote = kis_quote(symbol, market, environment) if mode == "kis" else demo_snapshot(symbol, market, "1D")
            quotes.append({key: value for key, value in quote.items() if key != "points"})
        except StockServiceError as error:
            quotes.append({
                "status": "error",
                "symbol": symbol,
                "market": market,
                "name": symbol,
                "currency": "KRW" if market == "KRX" else "USD",
                "message": str(error),
            })
    return {
        "status": "ok",
        "mode": mode,
        "environment": environment,
        "items": quotes,
        "updatedAt": int(time.time()),
    }


def screen_watchlist(items, mode="demo", environment="paper"):
    if mode not in ("demo", "kis"):
        raise StockServiceError("Unsupported screener data mode")
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported screener environment")
    if not isinstance(items, list):
        raise StockServiceError("Watchlist must be an array")
    normalized = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        symbol = str(item.get("symbol", "")).strip().upper()
        market = str(item.get("market", "KRX")).strip().upper()
        identity = (market, symbol)
        if not symbol or identity in seen:
            continue
        seen.add(identity)
        normalized.append(identity)
    results = []
    for market, symbol in normalized:
        try:
            quote = kis_quote(symbol, market, environment) if mode == "kis" else demo_snapshot(symbol, market, "1D")
            history = kis_history_points(environment, symbol, 120, market) if mode == "kis" else demo_history_points(symbol, market, 120)
            metrics = technical_screen_metrics(history)
            results.append(dict(metrics, **{
                "status": "ok",
                "symbol": symbol,
                "market": market,
                "name": quote.get("name") or symbol,
                "currency": quote.get("currency") or ("KRW" if market == "KRX" else "USD"),
                "price": numeric(quote.get("price")),
                "changePct": numeric(quote.get("changePct")),
            }))
        except StockServiceError as error:
            results.append({
                "status": "error",
                "symbol": symbol,
                "market": market,
                "name": symbol,
                "message": str(error),
            })
    results.sort(key=lambda item: (item.get("status") == "ok", numeric(item.get("score"), -101)), reverse=True)
    rank = 0
    for item in results:
        if item.get("status") == "ok":
            rank += 1
            item["rank"] = rank
    valid = [item for item in results if item.get("status") == "ok"]
    return {
        "status": "ok",
        "mode": mode,
        "environment": environment,
        "items": results,
        "counts": {
            "screened": len(valid),
            "total": len(results),
            "bullish": sum(1 for item in valid if item["stance"] == "bullish"),
            "neutral": sum(1 for item in valid if item["stance"] == "neutral"),
            "bearish": sum(1 for item in valid if item["stance"] == "bearish"),
        },
        "updatedAt": int(time.time()),
        "methodology": "Ranks 20/60-session trend, momentum, RSI, volatility, and drawdown from completed daily closes.",
        "disclaimer": "Technical ranking only. It is not investment advice, a prediction, or an order signal.",
    }
