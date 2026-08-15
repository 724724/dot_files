from .forecasting import *
from .automation import *
from .automation_execution import *
from .automation_scheduler import *
from .automation_universe import *
from .automation_shadow import *
from .automation_recovery import *
from .automation_notifications import automation_notification_status
from .automation_accounting import *
from .automation_resilience import *
from .automation_live import *
from .automation_operations import *
from .automation_soak import *
from .scheduler import background_control, background_control_status, evaluate_alert_payload, run_background_cycle


def start_autopilot_with_worker(payload):
    result = start_autopilot(payload)
    try:
        worker = background_control_status()
        if not worker.get("installed"):
            raise StockServiceError("Install the stock background worker before starting AI Autopilot")
        worker = background_control("enable")
    except Exception as error:
        try:
            environment = str(result.get("environment") or payload.get("environment", "paper"))
            stop_autopilot({
                "confirmation": (
                    "STOP KIS LIVE AUTOPILOT"
                    if environment == "prod"
                    else "STOP KIS PAPER AUTOPILOT"
                ),
            })
        except Exception:
            pass
        if isinstance(error, StockServiceError):
            raise
        raise StockServiceError(f"Could not enable the stock background worker: {error}") from error
    result["worker"] = worker
    return result


def stop_autopilot_with_worker(payload):
    result = stop_autopilot(payload)
    execution = automation_execution_status()
    keep_reconciling = bool(execution.get("uncertaintyLock"))
    try:
        worker = background_control("enable" if keep_reconciling else "disable")
    except Exception as error:
        worker = {
            "status": "error",
            "enabled": keep_reconciling,
            "message": str(error)[:240],
        }
    worker = dict(worker)
    worker["reconciliationOnly"] = keep_reconciling
    result["worker"] = worker
    return result


def refresh_autopilot_with_worker(payload=None):
    payload = payload if isinstance(payload, dict) else {}
    policy = load_automation_policy()
    if policy.get("halted"):
        return dict(
            autopilot_status(),
            refreshQueued=False,
            refreshBlocked=True,
            message=str(policy.get("haltReason") or "Automation is stopped"),
        )
    with automation_scheduler_lock():
        runtime = load_automation_scheduler_runtime()
        reset_scheduler_failures(runtime)
        runtime["lastWorkAt"] = 0
        runtime["lastUniverseRefreshAt"] = 0
        runtime["lastUniverseRefreshError"] = ""
        save_automation_scheduler_runtime(runtime)
    with automation_universe_lock():
        state = load_autopilot_state()
        state["lastScanAt"] = 0
        state["lastError"] = ""
        if state.get("enabled"):
            state["phase"] = "researching"
        save_autopilot_state(state)
    worker = background_control("enable") if policy.get("autopilotEnabled") else background_control_status()
    return dict(
        autopilot_status(),
        refreshQueued=bool(policy.get("autopilotEnabled")),
        refreshBlocked=False,
        message=(
            "A fresh market and candidate check has been queued"
            if policy.get("autopilotEnabled")
            else "Automatic trading is off"
        ),
        worker=worker,
    )


def emergency_stop_autopilot_with_worker(payload):
    result = stop_autopilot(payload, emergency=True)
    keep_reconciling = bool(automation_execution_status().get("uncertaintyLock"))
    worker = {}
    try:
        worker = background_control_status()
        if keep_reconciling and not worker.get("installed"):
            result["worker"] = {
                "status": "unavailable",
                "severity": "critical",
                "availability": "unavailable",
                "installed": False,
                "enabled": False,
                "timerActive": False,
                "reconciliationAvailable": False,
                "message": (
                    "Trading is stopped, but broker reconciliation is unavailable because "
                    "the stock background worker is not installed"
                ),
            }
            return result
        if keep_reconciling:
            if not worker.get("enabled") or not worker.get("timerActive"):
                worker = background_control("enable")
        elif worker.get("installed"):
            worker = background_control("disable")
        if keep_reconciling and (
            not worker.get("enabled") or not worker.get("timerActive")
        ):
            raise StockServiceError(
                "The stock background worker could not be activated for broker reconciliation",
            )
        worker = dict(worker)
        worker.update({
            "status": "ok",
            "severity": "info",
            "availability": "available",
            "reconciliationAvailable": keep_reconciling,
            "reconciliationOnly": keep_reconciling,
            "message": (
                "Trading is stopped; the worker remains active for broker reconciliation"
                if keep_reconciling
                else "Trading and background work are stopped"
            ),
        })
        result["worker"] = worker
    except Exception as error:
        result["worker"] = {
            "status": "unavailable",
            "severity": "critical",
            "availability": "unavailable",
            "installed": bool(worker.get("installed")),
            "enabled": False,
            "timerActive": False,
            "reconciliationAvailable": False,
            "message": (
                "Trading is stopped, but broker reconciliation is unavailable: "
                f"{error}"
            )[:240],
        }
    return result


def active_automation_environment(result=None):
    source = result if isinstance(result, dict) else {}
    policy = source.get("policy") if isinstance(source.get("policy"), dict) else None
    policy = policy if policy is not None else load_automation_policy()
    return "prod" if policy.get("executionMode") == "live" else "paper"


def full_automation_status(result=None):
    result = result if isinstance(result, dict) else automation_status()
    result["execution"] = automation_execution_status()
    result["audit"] = result["execution"]["audit"]
    result["recovery"] = automation_recovery_status()
    result["scheduler"] = automation_scheduler_status()
    failures = result["scheduler"].get("consecutiveFailures", 0)
    result["shadow"] = shadow_status(failures)
    result["notifications"] = automation_notification_status()
    accounting_environment = active_automation_environment(result)
    result["accountingEnvironment"] = accounting_environment
    result["accountingByEnvironment"] = {
        "paper": automation_accounting_status("paper"),
        "prod": automation_accounting_status("prod"),
    }
    result["accounting"] = result["accountingByEnvironment"][accounting_environment]
    result["resilience"] = automation_resilience_status()
    result["liveReadiness"] = automation_live_status(failures)
    result["operationsPart1"] = operations_part1_status()
    result["operationsPart2"] = operations_part2_status()
    result["autopilot"] = autopilot_status()
    try:
        result["background"] = background_control_status()
    except Exception as error:
        result["background"] = {"status": "error", "enabled": False, "message": str(error)[:240]}
    return result


def reconcile_automation_with_accounting():
    environment = active_automation_environment()
    result = reconcile_automation_executions()
    result["accountingEnvironment"] = environment
    try:
        result["accounting"] = reconcile_automation_accounting(environment)
    except Exception as error:
        result["accounting"] = {
            "status": "error",
            "healthy": False,
            "message": str(error)[:240],
        }
    return result


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
    account.add_argument("market", nargs="?", default="KRX", choices=["KRX", "NASDAQ", "NYSE"])
    order = subparsers.add_parser("order")
    order.add_argument("environment", choices=["paper", "prod"])
    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("environment", choices=["paper", "prod"])
    orders = subparsers.add_parser("orders")
    orders.add_argument("environment", choices=["paper", "prod"])
    orders.add_argument("symbol", nargs="?", default="")
    orders.add_argument("market", nargs="?", default="KRX", choices=["KRX", "NASDAQ", "NYSE"])
    cancel = subparsers.add_parser("cancel")
    cancel.add_argument("environment", choices=["paper", "prod"])
    activity = subparsers.add_parser("activity")
    activity.add_argument("environment", nargs="?", default="all", choices=["all", "paper", "prod"])
    activity.add_argument("limit", nargs="?", default="50")
    activity.add_argument("reconcile_environment", nargs="?", default="none", choices=["none", "paper", "prod"])
    reconcile = subparsers.add_parser("reconcile")
    reconcile.add_argument("environment", choices=["paper", "prod"])
    reconcile.add_argument("days", nargs="?", default=str(KIS_RECONCILIATION_LOOKBACK_DAYS))
    risk = subparsers.add_parser("risk")
    risk.add_argument("action", choices=["get", "set"])
    analysis = subparsers.add_parser("analyze")
    analysis.add_argument("provider", choices=["openai", "claude", "both"])
    analysis.add_argument("profile", nargs="?", default="balanced", choices=["quick", "balanced", "deep"])
    analysis.add_argument("refresh", nargs="?", default="cache", choices=["cache", "force"])
    forecasts = subparsers.add_parser("forecasts")
    forecasts.add_argument("action", choices=["list", "evaluate", "evaluate-all", "delete"])
    forecasts.add_argument("value", nargs="?", default="")
    forecasts.add_argument("limit", nargs="?", default="50")
    alerts = subparsers.add_parser("alerts")
    alerts.add_argument("action", choices=["evaluate"])
    background = subparsers.add_parser("background")
    background.add_argument("action", choices=["run", "status", "enable", "disable"])
    background.add_argument("widgets_path", nargs="?", default="")
    automation = subparsers.add_parser("automation")
    automation.add_argument("action", choices=[
        "status", "arm", "arm-paper", "arm-live", "pause", "kill", "reset-kill", "scheduler-enable",
        "scheduler-disable", "scheduler-auto-enable", "scheduler-auto-disable",
        "configure", "plan", "execute", "reconcile", "history",
        "shadow-status", "shadow-reset", "audit-recover", "accounting-reconcile",
        "accounting-reset", "resilience-test", "live-evaluate", "live-arm-canary",
        "live-verify-canary", "live-lock", "ops-verify",
        "ops-status", "ops-part1", "ops-snapshot", "ops-restore",
        "ops-part2-status", "ops-part2-start", "ops-part2-pause", "ops-part2-reset",
        "ops-part2-report", "autopilot-status", "autopilot-scan", "autopilot-configure",
        "autopilot-refresh",
        "autopilot-start", "autopilot-stop", "autopilot-emergency-stop",
    ])
    automation.add_argument("limit", nargs="?", default="50")
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
            emit(kis_account_summary(args.environment, args.symbol.strip().upper(), args.price, args.order_type, args.market))
        elif args.command == "order":
            emit(kis_order(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "preflight":
            emit(kis_order_preflight(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "orders":
            emit(kis_order_history(args.environment, args.symbol.strip().upper(), market=args.market))
        elif args.command == "cancel":
            emit(kis_cancel(args.environment, json.loads(sys.stdin.readline())))
        elif args.command == "activity":
            emit(
                reconciled_trade_activity(args.reconcile_environment, args.environment, args.limit)
                if args.reconcile_environment != "none"
                else trade_activity(args.environment, args.limit)
            )
        elif args.command == "reconcile":
            emit(kis_reconcile_activity(args.environment, args.days))
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
        elif args.command == "forecasts" and args.action == "evaluate-all":
            emit(evaluate_all_forecasts())
        elif args.command == "forecasts" and args.action == "delete":
            emit(delete_forecast(args.value))
        elif args.command == "alerts" and args.action == "evaluate":
            emit(evaluate_alert_payload(json.loads(sys.stdin.readline())))
        elif args.command == "background" and args.action == "run":
            emit(run_background_cycle(args.widgets_path))
        elif args.command == "background" and args.action == "status":
            emit(background_control_status())
        elif args.command == "background" and args.action in ("enable", "disable"):
            emit(background_control(args.action))
        elif args.command == "automation" and args.action == "status":
            emit(full_automation_status())
        elif args.command == "automation" and args.action == "history":
            emit(automation_history(args.limit))
        elif args.command == "automation" and args.action == "autopilot-status":
            emit(autopilot_status())
        elif args.command == "automation" and args.action == "autopilot-scan":
            emit(discover_autopilot_candidates(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "autopilot-configure":
            emit(configure_autopilot(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "autopilot-refresh":
            emit(refresh_autopilot_with_worker(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "autopilot-start":
            emit(start_autopilot_with_worker(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "autopilot-stop":
            emit(stop_autopilot_with_worker(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "autopilot-emergency-stop":
            emit(emergency_stop_autopilot_with_worker(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "configure":
            update_automation_policy(json.loads(sys.stdin.readline()))
            emit(automation_status())
        elif args.command == "automation" and args.action == "plan":
            emit(build_automation_plan(json.loads(sys.stdin.readline())))
        elif args.command == "automation" and args.action == "execute":
            emit(execute_automation_plan(json.loads(sys.stdin.readline())))
        elif args.command == "automation" and args.action == "reconcile":
            emit(reconcile_automation_with_accounting())
        elif args.command == "automation" and args.action == "shadow-status":
            scheduler = automation_scheduler_status()
            emit(shadow_status(scheduler.get("consecutiveFailures", 0)))
        elif args.command == "automation" and args.action == "shadow-reset":
            emit(reset_shadow_portfolio(json.loads(sys.stdin.readline())))
        elif args.command == "automation" and args.action == "audit-recover":
            emit(recover_automation_audit(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "accounting-reconcile":
            payload = json.loads(sys.stdin.readline() or "{}")
            emit(reconcile_automation_accounting(str(payload.get("environment", "paper"))))
        elif args.command == "automation" and args.action == "accounting-reset":
            emit(reset_automation_accounting(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "resilience-test":
            emit(run_resilience_self_test(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-verify":
            payload = json.loads(sys.stdin.readline() or "{}")
            if payload.get("confirmation") != "VERIFY PAPER OPERATIONS":
                raise StockServiceError("Operational verification requires exact confirmation")
            reconciliation = reconcile_automation_executions()
            accounting = reconcile_automation_accounting("paper")
            resilience = run_resilience_self_test({
                "confirmation": "RUN AUTOMATION RESILIENCE TEST",
            })
            result = full_automation_status()
            result["operationalVerification"] = {
                "status": "ok",
                "reconciliation": reconciliation,
                "accounting": accounting,
                "resilience": resilience,
            }
            emit(result)
        elif args.command == "automation" and args.action == "ops-status":
            emit(operations_part1_status())
        elif args.command == "automation" and args.action == "ops-part1":
            emit(run_operations_part1(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-snapshot":
            emit(create_automation_snapshot(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-restore":
            emit(restore_automation_snapshot(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-part2-status":
            emit(operations_part2_status())
        elif args.command == "automation" and args.action == "ops-part2-start":
            emit(run_operations_part2(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-part2-pause":
            emit(pause_operations_part2(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-part2-reset":
            emit(reset_operations_part2(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action == "ops-part2-report":
            emit(create_operations_part2_report(json.loads(sys.stdin.readline() or "{}")))
        elif args.command == "automation" and args.action.startswith("live-"):
            action = {
                "live-evaluate": "evaluate",
                "live-arm-canary": "arm-canary",
                "live-verify-canary": "verify-canary",
                "live-lock": "lock",
            }[args.action]
            scheduler = automation_scheduler_status()
            emit(automation_live_control(
                action,
                json.loads(sys.stdin.readline() or "{}"),
                scheduler.get("consecutiveFailures", 0),
            ))
        elif args.command == "automation":
            emit(full_automation_status(automation_control(
                args.action, json.loads(sys.stdin.readline() or "{}"),
            )))
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
