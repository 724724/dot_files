from .forecasting import *

def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    snap = subparsers.add_parser("snapshot")
    snap.add_argument("symbol")
    snap.add_argument("market")
    snap.add_argument("period")
    snap.add_argument("mode", nargs="?", default="demo", choices=["demo", "kis"])
    snap.add_argument("environment", nargs="?", default="paper", choices=["paper", "prod"])
    watchlist = subparsers.add_parser("watchlist")
    watchlist.add_argument("mode", choices=["demo", "kis"])
    watchlist.add_argument("environment", choices=["paper", "prod"])
    screener = subparsers.add_parser("screen")
    screener.add_argument("mode", choices=["demo", "kis"])
    screener.add_argument("environment", choices=["paper", "prod"])
    search = subparsers.add_parser("search")
    search.add_argument("query")
    search.add_argument("limit", nargs="?", default="8")
    search.add_argument("market", nargs="?", default="ALL", choices=["ALL", "KRX", "NASDAQ", "NYSE"])
    stream = subparsers.add_parser("stream")
    stream.add_argument("symbol")
    stream.add_argument("environment", choices=["paper", "prod"])
    account = subparsers.add_parser("account")
    account.add_argument("environment", choices=["paper", "prod"])
    account.add_argument("symbol", nargs="?", default="")
    account.add_argument("price", nargs="?", default="0")
    account.add_argument("order_type", nargs="?", default="market", choices=["market", "limit"])
    order = subparsers.add_parser("order")
    order.add_argument("environment", choices=["paper", "prod"])
    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("environment", choices=["paper", "prod"])
    orders = subparsers.add_parser("orders")
    orders.add_argument("environment", choices=["paper", "prod"])
    orders.add_argument("symbol", nargs="?", default="")
    cancel = subparsers.add_parser("cancel")
    cancel.add_argument("environment", choices=["paper", "prod"])
    activity = subparsers.add_parser("activity")
    activity.add_argument("environment", nargs="?", default="all", choices=["all", "paper", "prod"])
    activity.add_argument("limit", nargs="?", default="50")
    risk = subparsers.add_parser("risk")
    risk.add_argument("action", choices=["get", "set"])
    analysis = subparsers.add_parser("analyze")
    analysis.add_argument("provider", choices=["openai", "claude", "both"])
    analysis.add_argument("profile", nargs="?", default="balanced", choices=["quick", "balanced", "deep"])
    analysis.add_argument("refresh", nargs="?", default="cache", choices=["cache", "force"])
    forecasts = subparsers.add_parser("forecasts")
    forecasts.add_argument("action", choices=["list", "evaluate", "delete"])
    forecasts.add_argument("value", nargs="?", default="")
    forecasts.add_argument("limit", nargs="?", default="50")
    ai_validation_parser = subparsers.add_parser("validate-ai")
    ai_validation_parser.add_argument("symbol", nargs="?", default="")
    ai_validation_parser.add_argument("threshold", nargs="?", default=str(AI_CONFIDENCE_FLOOR))
    ai_validation_parser.add_argument("limit", nargs="?", default="200")
    ai_usage_parser = subparsers.add_parser("ai-usage")
    ai_usage_parser.add_argument("days", nargs="?", default="30")
    ai_usage_parser.add_argument("limit", nargs="?", default="100")
    backtest = subparsers.add_parser("backtest")
    backtest.add_argument("symbol")
    backtest.add_argument("market")
    backtest.add_argument("mode", choices=["demo", "kis"])
    backtest.add_argument("environment", choices=["paper", "prod"])
    backtest.add_argument("strategy", choices=list(BACKTEST_STRATEGIES))
    backtest.add_argument("commission_bps", nargs="?", default="1.5")
    backtest.add_argument("slippage_bps", nargs="?", default="5")
    backtest.add_argument("sell_tax_bps", nargs="?", default="15")
    compare = subparsers.add_parser("compare")
    compare.add_argument("symbol")
    compare.add_argument("market")
    compare.add_argument("mode", choices=["demo", "kis"])
    compare.add_argument("environment", choices=["paper", "prod"])
    compare.add_argument("commission_bps", nargs="?", default="1.5")
    compare.add_argument("slippage_bps", nargs="?", default="5")
    compare.add_argument("sell_tax_bps", nargs="?", default="15")
    models = subparsers.add_parser("models")
    models.add_argument("provider", nargs="?", default="both", choices=["openai", "claude", "both"])
    models.add_argument("refresh", nargs="?", default="cache", choices=["cache", "force"])
    credentials = subparsers.add_parser("credentials")
    credentials.add_argument("action", choices=["status", "set"])
    credentials.add_argument("key", nargs="?")
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            result = (
                kis_snapshot(
                    args.symbol.strip().upper(),
                    args.market.strip().upper(),
                    args.period,
                    args.environment,
                )
                if args.mode == "kis"
                else demo_snapshot(args.symbol, args.market, args.period)
            )
            emit(result)
        elif args.command == "watchlist":
            emit(watchlist_quotes(json.loads(sys.stdin.readline()), args.mode, args.environment))
        elif args.command == "screen":
            emit(screen_watchlist(json.loads(sys.stdin.readline()), args.mode, args.environment))
        elif args.command == "search":
            emit(search_symbols(args.query, args.limit, args.market))
        elif args.command == "stream":
            stream_ticks(args.symbol.strip().upper(), args.environment)
        elif args.command == "account":
            emit(kis_account_summary(args.environment, args.symbol.strip().upper(), args.price, args.order_type))
        elif args.command == "order":
            emit(kis_order(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "preflight":
            emit(kis_order_preflight(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "orders":
            emit(kis_order_history(args.environment, args.symbol.strip().upper()))
        elif args.command == "cancel":
            emit(kis_cancel(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "activity":
            emit(trade_activity(args.environment, args.limit))
        elif args.command == "risk" and args.action == "get":
            emit(dict({"status": "ok"}, **load_risk_policy()))
        elif args.command == "risk" and args.action == "set":
            emit(dict({"status": "ok"}, **save_risk_policy(json.loads(sys.stdin.readline()))))
        elif args.command == "analyze":
            payload = json.loads(sys.stdin.readline())
            emit(analyze(args.provider, args.profile, payload, args.refresh == "force"))
        elif args.command == "forecasts" and args.action == "list":
            emit(forecast_history(args.value, args.limit))
        elif args.command == "forecasts" and args.action == "evaluate":
            emit(evaluate_forecasts(json.loads(sys.stdin.readline())))
        elif args.command == "forecasts" and args.action == "delete":
            emit(delete_forecast(args.value))
        elif args.command == "validate-ai":
            emit(ai_validation(args.symbol, args.threshold, args.limit))
        elif args.command == "ai-usage":
            emit(ai_usage_summary(args.days, args.limit))
        elif args.command == "backtest":
            emit(run_backtest(args.symbol, args.market, args.mode, args.environment, args.strategy,
                              args.commission_bps, args.slippage_bps, args.sell_tax_bps))
        elif args.command == "compare":
            emit(strategy_comparison(args.symbol, args.market, args.mode, args.environment,
                                     args.commission_bps, args.slippage_bps, args.sell_tax_bps))
        elif args.command == "models":
            emit(model_catalog_summary(build_model_catalog(args.provider, args.refresh == "force")))
        elif args.command == "credentials" and args.action == "status":
            emit(credential_status())
        elif args.command == "credentials" and args.action == "set":
            value = sys.stdin.readline().rstrip("\r\n")
            secret_store(args.key, value)
            if args.key and args.key.startswith("kis_prod_app_"):
                for key in (
                    "kis_prod_access_token",
                    "kis_prod_token_expiry",
                    "kis_prod_ws_approval",
                    "kis_prod_ws_expiry",
                ):
                    secret_clear(key)
            elif args.key and args.key.startswith("kis_paper_app_"):
                for key in (
                    "kis_paper_access_token",
                    "kis_paper_token_expiry",
                    "kis_paper_ws_approval",
                    "kis_paper_ws_expiry",
                ):
                    secret_clear(key)
            emit({"status": "ok", "saved": args.key})
    except (StockServiceError, json.JSONDecodeError) as error:
        emit({"status": "error", "message": str(error)})


if __name__ == "__main__":
    main()
