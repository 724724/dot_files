import json
import tempfile
import unittest
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    AUTOMATION_TIMEZONE,
    automation_control,
    build_automation_plan,
    load_automation_policy,
    save_automation_policy,
    update_automation_policy,
)
from stock_service.automation_execution import (
    append_execution_event,
    automation_execution_status,
    execution_journal_audit_status,
    execution_preflight,
    execution_usage,
    execute_automation_plan,
    kis_business_day,
    market_session_date,
    market_session_gate,
    reconcile_automation_executions,
)
from stock_service.broker import KisPostError
from stock_service.core import StockServiceError


class StockAutomationExecutionTests(unittest.TestCase):
    PLAN_TIME = 1_800_018_000

    def market_safety(self, **values):
        result = {
            "checkedAt": self.PLAN_TIME,
            "available": True,
            "tradable": True,
            "viAvailable": True,
            "viActive": False,
            "upperLimit": 91000,
            "lowerLimit": 49000,
            "atUpperLimit": False,
            "atLowerLimit": False,
            "restricted": False,
            "restrictionReasons": [],
        }
        result.update(values)
        return result

    def quote(self, **values):
        result = {
            "status": "ok",
            "price": 70000,
            "ask": 70010,
            "bid": 69990,
            "updatedAt": self.PLAN_TIME + 20,
            "sourceUpdatedAt": self.PLAN_TIME + 20,
            "orderbookUpdatedAt": self.PLAN_TIME + 20,
            "marketSafety": self.market_safety(),
        }
        result.update(values)
        return result

    def payload(self):
        return {
            "symbol": "005930",
            "market": "KRX",
            "dataMode": "kis",
            "environment": "paper",
            "strategy": "trend",
            "snapshot": {
                "price": 70000,
                "updatedAt": self.PLAN_TIME,
                "marketSafety": self.market_safety(),
            },
            "analysis": {
                "status": "ok",
                "stance": "bullish",
                "confidence": 88,
                "generatedAt": self.PLAN_TIME,
                "downProbability": 10,
                "models": ["model-a", "model-b"],
                "ensembleAgreement": {
                    "status": "high",
                    "agreementScore": 90,
                    "modelCount": 2,
                    "directConflict": False,
                },
                "newsContext": {
                    "status": "usable",
                    "qualityScore": 82,
                    "verifiedDirectCount": 2,
                    "independentEventCount": 4,
                    "sourceQualityScore": 85,
                },
                "behaviorContext": {
                    "status": "usable",
                    "riskPenalty": 20,
                    "evidenceConfidence": 78,
                },
            },
        }

    def account(self):
        return {
            "status": "ok",
            "environment": "paper",
            "buyingPower": 10000000,
            "buyingQuantity": 100,
            "cash": 10000000,
            "totalEvaluation": 10000000,
            "stockEvaluation": 0,
            "holdingQuantity": 0,
            "sellableQuantity": 0,
            "holdings": [],
        }

    def test_protective_exits_do_not_consume_strategy_order_budget(self):
        records = [
            {
                "planId": "protective",
                "sessionDate": "2027-01-15",
                "market": "KRX",
                "side": "sell",
                "protectiveExit": True,
                "brokerState": "filled",
                "estimatedNotionalKrw": 200000,
            },
            {
                "planId": "entry",
                "sessionDate": "2027-01-15",
                "market": "KRX",
                "side": "buy",
                "protectiveExit": False,
                "brokerState": "filled",
                "estimatedNotionalKrw": 100000,
            },
            {
                "planId": "not-sent",
                "sessionDate": "2027-01-15",
                "market": "KRX",
                "side": "buy",
                "protectiveExit": False,
                "brokerState": "preflight_failed",
                "estimatedNotionalKrw": 100000,
            },
        ]
        with patch(
            "stock_service.automation_execution.load_execution_records",
            return_value=records,
        ), patch(
            "stock_service.automation_execution.market_session_date",
            return_value="2027-01-15",
        ):
            usage = execution_usage(self.PLAN_TIME)

        self.assertEqual(usage["orders"], 2)
        self.assertEqual(usage["strategyOrders"], 1)
        self.assertEqual(usage["protectiveExits"], 1)
        self.assertEqual(usage["buyOrders"], 1)

    def make_plan(self, directory, market_safety=None):
        technical = {
            "score": 80,
            "stance": "bullish",
            "signalStrength": 80,
            "annualizedVolatilityPct": 18,
        }
        backtest = {
            "status": "ok",
            "walkForward": {
                "status": "robust",
                "oosReturnPct": 8,
                "excessReturnPct": 3,
                "maxDrawdownPct": -6,
                "sharpe": 1.2,
            },
        }
        with patch("stock_service.automation.state_directory", return_value=directory), patch(
            "stock_service.automation.kis_history_points", return_value=[{"t": i, "v": 100 + i, "volume": 1000000} for i in range(200)],
        ), patch(
            "stock_service.automation.technical_screen_metrics", return_value=technical,
        ), patch(
            "stock_service.automation.run_backtest", return_value=backtest,
        ), patch(
            "stock_service.automation.automation_account", return_value=self.account(),
        ):
            automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})
            payload = self.payload()
            if market_safety is not None:
                payload["snapshot"]["marketSafety"] = market_safety
            return build_automation_plan(payload, now=self.PLAN_TIME)

    def protective_account(self):
        result = self.account()
        result.update({
            "buyingPower": 0,
            "cash": 9000000,
            "stockEvaluation": 1000000,
            "holdingQuantity": 3,
            "sellableQuantity": 3,
            "holdings": [{
                "symbol": "005930",
                "quantity": 3,
                "sellableQuantity": 3,
                "averagePrice": 73000,
                "price": 70000,
                "evaluation": 210000,
            }],
        })
        return result

    def make_protective_plan(self, directory):
        with patch("stock_service.automation.state_directory", return_value=directory), patch(
            "stock_service.automation.automation_account", return_value=self.protective_account(),
        ), patch(
            "stock_service.automation.kis_history_points",
        ) as history, patch(
            "stock_service.automation.run_backtest",
        ) as backtest:
            automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})
            plan = build_automation_plan(self.payload(), now=self.PLAN_TIME)
        history.assert_not_called()
        backtest.assert_not_called()
        return plan

    def execution_context(self, directory):
        return (
            patch("stock_service.automation.state_directory", return_value=directory),
            patch("stock_service.automation_execution.state_directory", return_value=directory),
            patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ),
            patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ),
            patch("stock_service.automation_execution.kis_account_summary", return_value=self.account()),
        )

    def test_paper_execution_requires_explicit_arming(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            with self.assertRaises(StockServiceError):
                automation_control("arm-paper", {})
            result = automation_control("arm-paper", {"confirmation": "ARM KIS PAPER EXECUTION"})

        self.assertTrue(result["policy"]["enabled"])
        self.assertEqual(result["policy"]["executionMode"], "paper")

    def test_active_vi_blocks_plan_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory, self.market_safety(viActive=True))

        self.assertEqual(plan["decision"], "blocked")
        self.assertIn("vi_clear", plan["failedGates"])

    def test_stale_market_safety_status_blocks_plan_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(
                directory,
                self.market_safety(checkedAt=self.PLAN_TIME - 31),
            )

        self.assertEqual(plan["decision"], "blocked")
        self.assertIn("market_safety_freshness", plan["failedGates"])

    def test_qualified_plan_submits_one_kis_paper_order(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ) as order:
                result = execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)

        self.assertTrue(plan["executionEligible"])
        self.assertTrue(result["brokerOrderSent"])
        self.assertEqual(result["environment"], "paper")
        self.assertEqual(result["orderNumber"], "12345")
        self.assertEqual(order.call_count, 1)
        self.assertEqual(order.call_args.args[1]["orderType"], "limit")
        self.assertEqual(order.call_args.args[1]["price"], 70010)

    def arm_live(self, directory):
        with patch("stock_service.automation.state_directory", return_value=directory), patch(
            "stock_service.automation.time.time",
            return_value=self.PLAN_TIME,
        ), patch(
            "stock_service.core.load_risk_policy",
            return_value={"productionEnabled": True},
        ), patch(
            "stock_service.automation_live.automation_live_status",
            return_value={"productionAutomationEligible": True},
        ):
            update_automation_policy({"liveConsent": True})
            return automation_control("arm-live", {"confirmation": "ARM KIS LIVE EXECUTION"})

    def make_live_plan(self, directory):
        technical = {
            "score": 80,
            "stance": "bullish",
            "signalStrength": 80,
            "annualizedVolatilityPct": 18,
        }
        backtest = {
            "status": "ok",
            "walkForward": {
                "status": "robust",
                "oosReturnPct": 8,
                "excessReturnPct": 3,
                "maxDrawdownPct": -6,
                "sharpe": 1.2,
            },
        }
        self.arm_live(directory)
        with patch("stock_service.automation.state_directory", return_value=directory), patch(
            "stock_service.automation.kis_history_points", return_value=[{"t": i, "v": 100 + i, "volume": 1000000} for i in range(200)],
        ), patch(
            "stock_service.automation.technical_screen_metrics", return_value=technical,
        ), patch(
            "stock_service.automation.run_backtest", return_value=backtest,
        ), patch(
            "stock_service.automation.automation_account", return_value=self.account(),
        ):
            return build_automation_plan(self.payload(), now=self.PLAN_TIME)

    def make_live_protective_plan(self, directory):
        self.arm_live(directory)
        with patch(
            "stock_service.automation.state_directory",
            return_value=directory,
        ):
            return build_automation_plan(
                self.payload(),
                now=self.PLAN_TIME,
                trusted_account=self.protective_account(),
                trusted_position_risk={
                    "triggered": True,
                    "reason": "stop_loss",
                },
            )

    def test_paper_business_day_check_routes_through_production_calendar(self):
        response = {"output": [{"bass_dt": "20260723", "opnd_yn": "Y"}]}
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.kis_get", return_value=response,
        ) as request:
            opened, source = kis_business_day("paper", datetime(2026, 7, 23, 10, 0))

        self.assertTrue(opened)
        self.assertEqual(source, "kis")
        self.assertEqual(request.call_args.args[0], "prod")

    def test_paper_business_day_check_degrades_without_production_credentials(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.kis_get",
            side_effect=StockServiceError("KIS prod credentials are not saved"),
        ):
            opened, source = kis_business_day("paper", datetime(2026, 7, 23, 10, 0))

        self.assertTrue(opened)
        self.assertEqual(source, "weekday_fallback")

    def test_production_business_day_check_still_propagates_errors(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.kis_get",
            side_effect=StockServiceError("KIS unavailable"),
        ), self.assertRaisesRegex(StockServiceError, "KIS unavailable"):
            kis_business_day("prod", datetime(2026, 7, 23, 10, 0))

    def test_live_arming_requires_consent_risk_unlock_and_verified_readiness(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation.state_directory", return_value=directory,
        ):
            with self.assertRaisesRegex(StockServiceError, "risk consent"):
                automation_control("arm-live", {"confirmation": "ARM KIS LIVE EXECUTION"})
            update_automation_policy({"liveConsent": True})
            with patch(
                "stock_service.core.load_risk_policy",
                return_value={"productionEnabled": False},
            ), self.assertRaisesRegex(StockServiceError, "global risk policy"):
                automation_control("arm-live", {"confirmation": "ARM KIS LIVE EXECUTION"})
            with patch(
                "stock_service.core.load_risk_policy",
                return_value={"productionEnabled": True},
            ), patch(
                "stock_service.automation_live.automation_live_status",
                return_value={"productionAutomationEligible": False},
            ), self.assertRaisesRegex(StockServiceError, "live-readiness"):
                automation_control("arm-live", {"confirmation": "ARM KIS LIVE EXECUTION"})

    def test_live_armed_policy_downgrades_when_consent_is_revoked(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.arm_live(directory)
            self.assertEqual(result["policy"]["executionMode"], "live")
            self.assertFalse(result["policy"]["paperOnly"])
            with patch("stock_service.automation.state_directory", return_value=directory):
                revoked = update_automation_policy({"liveConsent": False})

        self.assertEqual(revoked["executionMode"], "paper")
        self.assertTrue(revoked["paperOnly"])

    def test_live_qualified_plan_submits_prod_order_with_live_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_live_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.load_risk_policy",
                return_value={"productionEnabled": True},
            ), patch(
                "stock_service.automation_execution.time.time",
                return_value=self.PLAN_TIME + 20,
            ), patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "77777", "organizationNumber": "001"},
            ) as order:
                with self.assertRaisesRegex(StockServiceError, "exact plan confirmation"):
                    execute_automation_plan({
                        "planId": plan["planId"],
                        "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                    }, now=self.PLAN_TIME + 20)
                result = execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS LIVE {plan['planId']}",
                }, now=self.PLAN_TIME + 20)

        self.assertEqual(plan["environment"], "prod")
        self.assertTrue(plan["executionEligible"])
        self.assertTrue(result["brokerOrderSent"])
        self.assertEqual(result["environment"], "prod")
        self.assertEqual(order.call_count, 1)
        self.assertEqual(order.call_args.args[0], "prod")
        self.assertEqual(order.call_args.args[1]["confirmation"], "LIVE")

    def test_live_buy_is_blocked_when_manual_holding_would_mix(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_live_plan(directory)
            account = self.account()
            account.update({
                "holdingQuantity": 2,
                "sellableQuantity": 2,
                "holdings": [{
                    "market": "KRX",
                    "symbol": "005930",
                    "quantity": 2,
                    "sellableQuantity": 2,
                    "price": 70000,
                    "evaluation": 140000,
                }],
            })
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory",
                return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ), patch(
                "stock_service.automation_execution.kis_account_summary",
                return_value=account,
            ), patch(
                "stock_service.automation_execution.load_execution_records",
                return_value=[],
            ), patch(
                "stock_service.automation_execution.load_risk_policy",
                return_value={"productionEnabled": True},
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "manual holding"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_live_sell_is_capped_to_confirmed_managed_quantity(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_live_protective_plan(directory)
            record = {
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "brokerState": "filled",
                "filledQuantity": 1,
            }
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory",
                return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ), patch(
                "stock_service.automation_execution.kis_account_summary",
                return_value=self.protective_account(),
            ), patch(
                "stock_service.automation_execution.load_execution_records",
                return_value=[record],
            ), patch(
                "stock_service.automation_execution.load_risk_policy",
                return_value={"productionEnabled": True},
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "confirmed managed position"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_paper_preflight_does_not_apply_live_position_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.managed_position_ownership",
            ) as ownership:
                policy = load_automation_policy()
                result = execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

        ownership.assert_not_called()
        self.assertEqual(result["managedPositionOwnership"], {})

    def test_execution_rechecks_market_safety_flags(self):
        unsafe_quotes = (
            (self.market_safety(tradable=False, temporaryHalt=True), "normal tradable state"),
            (self.market_safety(viActive=True), "volatility interruption is active"),
            (self.market_safety(restricted=True), "risk flags block"),
            (self.market_safety(upperLimit=70010), "upper price limit"),
        )
        for market_safety, message in unsafe_quotes:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                plan = self.make_plan(directory)
                with patch(
                    "stock_service.automation.state_directory", return_value=directory,
                ), patch(
                    "stock_service.automation_execution.state_directory", return_value=directory,
                ), patch(
                    "stock_service.automation_execution.market_session_gate",
                    return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
                ), patch(
                    "stock_service.automation_execution.kis_quote",
                    return_value=self.quote(marketSafety=market_safety),
                ):
                    policy = load_automation_policy()
                    with self.assertRaisesRegex(StockServiceError, message):
                        execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_same_plan_can_never_be_submitted_twice(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            payload = {
                "planId": plan["planId"],
                "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
            }
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ):
                execute_automation_plan(payload, now=self.PLAN_TIME + 20)
                with self.assertRaisesRegex(StockServiceError, "already has an execution attempt"):
                    execute_automation_plan(payload, now=self.PLAN_TIME + 21)

    def test_protective_exit_bypasses_buy_limits_and_reconciles_without_global_halt(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_protective_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3] as quote, contexts[4], patch(
                "stock_service.automation_execution.kis_account_summary",
                return_value=self.protective_account(),
            ), patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "exit-1", "organizationNumber": "001"},
            ) as order:
                quote.return_value.pop("orderbookUpdatedAt", None)
                quote.return_value.update({
                    "price": 49000,
                    "ask": 0,
                    "bid": 0,
                    "marketSafety": self.market_safety(
                        lowerLimit=49000,
                        atLowerLimit=True,
                    ),
                })
                result = execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertEqual(plan["side"], "sell")
        self.assertGreater(plan["estimatedNotional"], 100000)
        self.assertTrue(result["protectiveExit"])
        self.assertTrue(result["brokerOrderSent"])
        self.assertEqual(order.call_args.args[1]["orderType"], "market")
        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])
        self.assertTrue(quote.call_args.kwargs["include_orderbook"])
        order.assert_called_once()

    def test_capital_loss_halt_allows_only_a_prebuilt_protective_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_protective_plan(directory)
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                policy = load_automation_policy()
                policy.update({
                    "enabled": False,
                    "halted": True,
                    "haltReason": "Capital-loss circuit breaker triggered",
                    "haltClass": "capital_loss",
                    "exitOnlyProtection": True,
                    "schedulerEnabled": True,
                })
                save_automation_policy(policy)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_account_summary",
                return_value=self.protective_account(),
            ), patch(
                "stock_service.automation_execution.kis_order",
                return_value={
                    "status": "ok",
                    "orderNumber": "exit-only-1",
                    "organizationNumber": "001",
                },
            ) as order:
                result = execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)

        self.assertTrue(result["protectiveExit"])
        self.assertTrue(result["brokerOrderSent"])
        order.assert_called_once()

    def test_crash_after_durable_claim_blocks_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch("stock_service.automation_execution.state_directory", return_value=directory):
                append_execution_event({
                    "kind": "execution",
                    "executionId": "crashed-process",
                    "planId": plan["planId"],
                    "state": "claimed",
                    "brokerState": "claimed",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "timestamp": self.PLAN_TIME + 10,
                })
                with patch("stock_service.automation_execution.kis_order") as order, self.assertRaisesRegex(
                    StockServiceError, "already has an execution attempt",
                ):
                    execute_automation_plan({
                        "planId": plan["planId"],
                        "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                    }, now=self.PLAN_TIME + 20)

        order.assert_not_called()

    def test_expired_plan_is_blocked_before_order_submission(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
            ) as order, self.assertRaisesRegex(StockServiceError, "expired"):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 120)
            order.assert_not_called()

    def test_execution_rechecks_volatility_loss_budget_against_current_equity(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            reduced = self.account()
            reduced.update({"cash": 500000, "totalEvaluation": 500000})
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ), patch(
                "stock_service.automation_execution.kis_account_summary", return_value=reduced,
            ), patch(
                "stock_service.automation_execution.automation_risk_snapshot",
                return_value={"dailyReturnPercent": 0, "drawdownPercent": 0},
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "volatility-adjusted loss budget"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_rechecks_sector_concentration(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            concentrated = self.account()
            concentrated.update({
                "cash": 8510000,
                "stockEvaluation": 1490000,
                "holdings": [{
                    "symbol": "000660",
                    "evaluation": 1490000,
                    "quantity": 20,
                    "sellableQuantity": 20,
                }],
            })
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ), patch(
                "stock_service.automation_execution.kis_account_summary", return_value=concentrated,
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "sector concentration"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_rejects_plan_after_holdings_change(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            changed = self.account()
            changed.update({
                "cash": 9500000,
                "stockEvaluation": 500000,
                "holdings": [{
                    "symbol": "005380",
                    "evaluation": 500000,
                    "quantity": 2,
                    "sellableQuantity": 2,
                }],
            })
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(),
            ), patch(
                "stock_service.automation_execution.kis_account_summary", return_value=changed,
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "Portfolio holdings changed"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_rechecks_current_market_participation_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ):
                policy = update_automation_policy({"maxMarketParticipationPercent": 0.01})
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], self.assertRaisesRegex(
                StockServiceError, "market participation",
            ):
                execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_requires_a_complete_bid_ask_quote(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(ask=0, bid=0),
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "valid KIS bid-ask quote"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_rejects_a_stale_kis_quote(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(
                    updatedAt=self.PLAN_TIME + 20,
                    sourceUpdatedAt=self.PLAN_TIME - 20,
                ),
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "freshness window"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_execution_accepts_quote_received_after_cycle_timestamp(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.time.time",
                return_value=self.PLAN_TIME + 32,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME + 32},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(
                    updatedAt=self.PLAN_TIME + 32,
                    orderbookUpdatedAt=self.PLAN_TIME + 32,
                ),
            ), patch(
                "stock_service.automation_execution.kis_account_summary",
                return_value=self.account(),
            ):
                policy = load_automation_policy()
                result = execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

        self.assertEqual(result["checkedAt"], self.PLAN_TIME + 32)

    def test_execution_rejects_a_wide_bid_ask_spread(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.market_session_gate",
                return_value={"passed": True, "message": "open", "checkedAt": self.PLAN_TIME},
            ), patch(
                "stock_service.automation_execution.kis_quote",
                return_value=self.quote(ask=70100, bid=69900),
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "bid-ask spread"):
                    execution_preflight(plan, policy, now=self.PLAN_TIME + 20)

    def test_full_plan_integrity_blocks_safety_gate_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            tampered = deepcopy(plan)
            tampered["gates"][0]["passed"] = not tampered["gates"][0]["passed"]
            with patch("stock_service.automation.state_directory", return_value=directory), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ):
                policy = load_automation_policy()
                with self.assertRaisesRegex(StockServiceError, "plan integrity"):
                    execution_preflight(tampered, policy, now=self.PLAN_TIME + 20)

    def test_execution_journal_is_hash_chained_and_detects_tampering(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ):
            append_execution_event({"planId": "plan-1", "state": "claimed", "quantity": 1})
            append_execution_event({"planId": "plan-1", "state": "accepted", "quantity": 1})
            healthy = execution_journal_audit_status()
            path = Path(directory) / "automation-executions.jsonl"
            lines = path.read_text(encoding="utf-8").splitlines()
            changed = json.loads(lines[1])
            changed["quantity"] = 99
            lines[1] = json.dumps(changed, ensure_ascii=False, separators=(",", ":"))
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            damaged = execution_journal_audit_status()

        self.assertTrue(healthy["healthy"])
        self.assertFalse(damaged["healthy"])
        self.assertEqual(damaged["firstError"]["reason"], "record_hash_mismatch")

    def test_uncertain_order_halts_automation_and_blocks_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            payload = {
                "planId": plan["planId"],
                "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
            }
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                side_effect=KisPostError(
                    "timeout",
                    request_sent=True,
                    outcome_ambiguous=True,
                    failure_class="hard",
                ),
            ) as order:
                with self.assertRaisesRegex(StockServiceError, "outcome is uncertain"):
                    execute_automation_plan(payload, now=self.PLAN_TIME + 20)
                with self.assertRaisesRegex(StockServiceError, "uncertain|unresolved"):
                    execute_automation_plan(payload, now=self.PLAN_TIME + 21)
                self.assertEqual(order.call_count, 1)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()
            with patch("stock_service.automation_execution.state_directory", return_value=directory):
                status = automation_execution_status()

        self.assertTrue(policy["halted"])
        self.assertFalse(policy["enabled"])
        self.assertTrue(status["uncertaintyLock"])

    def test_explicit_broker_rejection_does_not_halt_automation(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                side_effect=KisPostError(
                    "order rejected",
                    request_sent=True,
                    outcome_ambiguous=False,
                    broker_code="REJECTED",
                    failure_class="operator",
                ),
            ), self.assertRaisesRegex(StockServiceError, "order rejected"):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                policy = load_automation_policy()
            with patch(
                "stock_service.automation_execution.state_directory",
                return_value=directory,
            ):
                status = automation_execution_status()

        self.assertFalse(policy["halted"])
        self.assertTrue(policy["enabled"])
        self.assertEqual(status["latest"]["state"], "rejected")
        self.assertFalse(status["uncertaintyLock"])

    def test_local_order_preflight_error_does_not_create_uncertainty(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                side_effect=StockServiceError("KIS paper account is not saved"),
            ), self.assertRaisesRegex(StockServiceError, "account is not saved"):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            with patch(
                "stock_service.automation.state_directory",
                return_value=directory,
            ):
                policy = load_automation_policy()
            with patch(
                "stock_service.automation_execution.state_directory",
                return_value=directory,
            ):
                status = automation_execution_status()

        self.assertFalse(policy["halted"])
        self.assertEqual(status["latest"]["state"], "preflight_failed")
        self.assertFalse(status["uncertaintyLock"])

    def test_policy_change_before_submission_prevents_broker_io(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.validate_execution_policy",
                side_effect=[
                    None,
                    StockServiceError(
                        "Automation was paused before order submission"
                    ),
                ],
            ), patch(
                "stock_service.automation_execution.kis_order",
            ) as order, self.assertRaisesRegex(
                StockServiceError,
                "paused before order submission",
            ):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            with patch(
                "stock_service.automation_execution.state_directory",
                return_value=directory,
            ):
                status = automation_execution_status()

        order.assert_not_called()
        self.assertEqual(status["latest"]["state"], "preflight_failed")
        self.assertFalse(status["uncertaintyLock"])

    def test_status_and_reconciliation_include_unresolved_order_older_than_ui_limit(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ):
            append_execution_event({
                "planId": "old-unresolved",
                "state": "accepted",
                "brokerState": "accepted",
                "environment": "paper",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "quantity": 1,
                "orderNumber": "12345",
                "sessionDate": datetime.now(AUTOMATION_TIMEZONE).date().isoformat(),
            })
            for index in range(21):
                append_execution_event({
                    "planId": f"new-final-{index}",
                    "state": "reconciled",
                    "brokerState": "filled",
                    "environment": "paper",
                    "market": "KRX",
                    "symbol": f"{index:06d}",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 1,
                    "sessionDate": datetime.now(AUTOMATION_TIMEZONE).date().isoformat(),
                })
            with patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                status = automation_execution_status(limit=20)

            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "12345",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 1,
                    "remainingQuantity": 0,
                    "averagePrice": 70000,
                    "state": "filled",
                }],
            }
            with patch(
                "stock_service.automation_execution.kis_order_history",
                return_value=history,
            ), patch(
                "stock_service.automation_execution.automation_audit_status",
                return_value={"healthy": True},
            ):
                reconciliation = reconcile_automation_executions()

        self.assertEqual(len(status["records"]), 20)
        self.assertNotIn(
            "old-unresolved",
            {record["planId"] for record in status["records"]},
        )
        self.assertEqual(status["unresolved"], 1)
        self.assertEqual(status["unresolvedCount"], 1)
        self.assertTrue(status["uncertaintyLock"])
        self.assertEqual(status["today"], 22)
        self.assertEqual(reconciliation["matched"], 1)
        self.assertEqual(reconciliation["unresolved"], 0)
        self.assertEqual(reconciliation["unresolvedCount"], 0)
        self.assertFalse(reconciliation["uncertaintyLock"])

    def test_reconciliation_matches_broker_order_without_resubmitting(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "12345",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 1,
                    "remainingQuantity": 0,
                    "averagePrice": 70000,
                    "state": "filled",
                }],
            }
            with patch("stock_service.automation_execution.state_directory", return_value=directory), patch(
                "stock_service.automation_execution.kis_order_history", return_value=history,
            ):
                result = reconcile_automation_executions()

        self.assertEqual(result["matched"], 1)
        self.assertFalse(result["uncertaintyLock"])
        self.assertEqual(result["latest"]["brokerState"], "filled")

    def test_live_reconciliation_never_claims_a_manual_order_by_signature(self):
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory",
            return_value=directory,
        ):
            append_execution_event({
                "kind": "execution",
                "executionId": "live-uncertain",
                "planId": "live-plan",
                "state": "uncertain",
                "brokerState": "uncertain",
                "environment": "prod",
                "market": "KRX",
                "symbol": "005930",
                "side": "buy",
                "quantity": 1,
                "timestamp": self.PLAN_TIME,
                "sessionDate": market_session_date(self.PLAN_TIME, "KRX"),
            })
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "manual-123",
                    "market": "KRX",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 1,
                    "remainingQuantity": 0,
                    "timestamp": self.PLAN_TIME + 1,
                    "state": "filled",
                }],
            }
            with patch(
                "stock_service.automation_execution.kis_order_history",
                return_value=history,
            ):
                result = reconcile_automation_executions(
                    now=self.PLAN_TIME + 30,
                )

        self.assertEqual(result["matched"], 0)
        self.assertEqual(result["pending"], 1)
        self.assertTrue(result["uncertaintyLock"])
        self.assertEqual(
            result["latest"]["reconciliationMatch"],
            "manual_confirmation_required",
        )

    def test_partial_fill_keeps_serial_execution_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "12345",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 0,
                    "remainingQuantity": 1,
                    "averagePrice": 0,
                    "state": "partial",
                }],
            }
            with patch("stock_service.automation_execution.state_directory", return_value=directory), patch(
                "stock_service.automation_execution.kis_order_history", return_value=history,
            ):
                result = reconcile_automation_executions()

        self.assertEqual(result["latest"]["brokerState"], "partial")
        self.assertTrue(result["uncertaintyLock"])

    def test_stale_limit_order_cancels_its_unfilled_remainder(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "12345",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 0,
                    "remainingQuantity": 1,
                    "averagePrice": 0,
                    "state": "submitted",
                }],
            }
            with patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.kis_order_history", return_value=history,
            ), patch(
                "stock_service.automation_execution.kis_cancel",
                return_value={"status": "ok", "orderNumber": "cancel-1", "canceledQuantity": 1},
            ) as cancel:
                result = reconcile_automation_executions(now=self.PLAN_TIME + 141)

        cancel.assert_called_once_with("paper", {"orderNumber": "12345"})
        self.assertEqual(result["cancelRequested"], 1)
        self.assertEqual(result["latest"]["state"], "cancel_requested")
        self.assertTrue(result["uncertaintyLock"])

    def test_uncertain_stale_cancellation_trips_kill_switch(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = self.make_plan(directory)
            contexts = self.execution_context(directory)
            with contexts[0], contexts[1], contexts[2], contexts[3], contexts[4], patch(
                "stock_service.automation_execution.kis_order",
                return_value={"status": "ok", "orderNumber": "12345", "organizationNumber": "001"},
            ):
                execute_automation_plan({
                    "planId": plan["planId"],
                    "confirmation": f"EXECUTE KIS PAPER {plan['planId']}",
                }, now=self.PLAN_TIME + 20)
            history = {
                "status": "ok",
                "orders": [{
                    "orderNumber": "12345",
                    "symbol": "005930",
                    "side": "buy",
                    "quantity": 1,
                    "filledQuantity": 0,
                    "remainingQuantity": 1,
                    "averagePrice": 0,
                    "state": "submitted",
                }],
            }
            with patch(
                "stock_service.automation.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.state_directory", return_value=directory,
            ), patch(
                "stock_service.automation_execution.kis_order_history", return_value=history,
            ), patch(
                "stock_service.automation_execution.kis_cancel", side_effect=StockServiceError("timeout"),
            ), self.assertRaisesRegex(StockServiceError, "cancellation outcome is uncertain"):
                reconcile_automation_executions(now=self.PLAN_TIME + 141)
            with patch("stock_service.automation.state_directory", return_value=directory):
                policy = load_automation_policy()

        self.assertTrue(policy["halted"])
        self.assertFalse(policy["enabled"])

    def test_kis_business_day_is_verified_once_and_cached(self):
        moment = datetime(2027, 1, 4, 10, 0, tzinfo=AUTOMATION_TIMEZONE)
        with tempfile.TemporaryDirectory() as directory, patch(
            "stock_service.automation_execution.state_directory", return_value=directory,
        ), patch(
            "stock_service.automation_execution.kis_get",
            return_value={"output": [{"bass_dt": "20270104", "opnd_yn": "Y"}]},
        ) as request:
            first = market_session_gate("paper", int(moment.timestamp()))
            second = market_session_gate("paper", int(moment.timestamp()))

        self.assertTrue(first["passed"])
        self.assertTrue(second["passed"])
        self.assertEqual(request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
