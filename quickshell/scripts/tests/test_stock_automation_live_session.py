import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.automation import (
    DEFAULT_AUTOMATION_POLICY,
    LIVE_AUTO_SESSION_MAX_SECONDS,
    automation_control,
    live_auto_session_status,
    load_automation_policy,
    normalized_automation_policy,
    open_live_auto_session,
    save_automation_policy,
)
from stock_service.automation_operations import automation_policy_coherent
from stock_service.automation_scheduler import run_automation_scheduler


class StockAutomationLiveSessionTests(unittest.TestCase):
    TIMEZONE = ZoneInfo("Asia/Seoul")
    NOW = int(datetime(2027, 1, 12, 12, 0, tzinfo=TIMEZONE).timestamp())

    def live_policy(self, now=None):
        now = self.NOW if now is None else now
        return open_live_auto_session(dict(
            DEFAULT_AUTOMATION_POLICY,
            enabled=True,
            halted=False,
            liveConsent=True,
            executionMode="live",
            paperOnly=False,
            schedulerEnabled=True,
            schedulerMode="paper_auto",
            autopilotEnabled=True,
        ), now)

    def universe(self, environment="prod", enabled=True):
        return {
            "enabled": enabled,
            "environment": environment,
            "automaticSelection": False,
            "selectedKeys": ["KRX:005930"],
            "lastScanAt": self.NOW,
            "candidates": [{
                "market": "KRX",
                "symbol": "005930",
                "key": "KRX:005930",
                "aiProvider": "both",
                "analysisProfile": "balanced",
                "strategy": "trend",
                "language": "ko",
            }],
        }

    def paths(self, directory):
        return (
            patch("stock_service.automation.state_directory", return_value=directory),
            patch("stock_service.automation_scheduler.state_directory", return_value=directory),
            patch("stock_service.automation.time.time", return_value=self.NOW),
        )

    def live_dependencies(self):
        return (
            patch(
                "stock_service.core.load_risk_policy",
                return_value={"productionEnabled": True},
            ),
            patch(
                "stock_service.automation_live.automation_live_status",
                return_value={"productionAutomationEligible": True},
            ),
        )

    def test_live_session_is_bounded_to_eight_hours_across_us_market_midnight(self):
        daytime = self.live_policy()
        late = int(datetime(2027, 1, 12, 22, 0, tzinfo=self.TIMEZONE).timestamp())
        late_policy = self.live_policy(late)

        self.assertLessEqual(
            daytime["liveSessionExpiresAt"] - daytime["liveSessionStartedAt"],
            LIVE_AUTO_SESSION_MAX_SECONDS,
        )
        self.assertEqual(
            late_policy["liveSessionExpiresAt"] - late,
            LIVE_AUTO_SESSION_MAX_SECONDS,
        )
        self.assertNotEqual(
            datetime.fromtimestamp(
                late_policy["liveSessionExpiresAt"] - 1,
                self.TIMEZONE,
            ).date(),
            datetime.fromtimestamp(late, self.TIMEZONE).date(),
        )

    def test_normalizer_allows_live_autopilot_only_during_valid_session(self):
        with patch("stock_service.automation.time.time", return_value=self.NOW):
            valid = normalized_automation_policy(self.live_policy())
            expired_input = dict(self.live_policy(), liveSessionExpiresAt=self.NOW)
            expired = normalized_automation_policy(expired_input)

        self.assertTrue(valid["autopilotEnabled"])
        self.assertTrue(live_auto_session_status(valid, self.NOW)["valid"])
        self.assertFalse(expired["autopilotEnabled"])
        self.assertIn(
            "live_session_expired",
            live_auto_session_status(expired, self.NOW)["reasons"],
        )

    def test_arm_live_opens_a_fresh_session(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.paths(directory)
            dependencies = self.live_dependencies()
            with paths[0], paths[1], paths[2], dependencies[0], dependencies[1]:
                policy = load_automation_policy()
                policy["liveConsent"] = True
                save_automation_policy(policy)
                result = automation_control(
                    "arm-live",
                    {"confirmation": "ARM KIS LIVE EXECUTION"},
                )

        self.assertEqual(result["policy"]["executionMode"], "live")
        self.assertTrue(result["liveSession"]["valid"])
        self.assertRegex(result["policy"]["liveSessionId"], r"^[0-9a-f]{32}$")

    def test_expired_live_session_revokes_and_halts_before_market_io(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.paths(directory)
            dependencies = self.live_dependencies()
            with paths[0], paths[1], paths[2], dependencies[0], dependencies[1]:
                policy = self.live_policy()
                policy["liveSessionExpiresAt"] = self.NOW
                save_automation_policy(policy)
                with patch(
                    "stock_service.automation_scheduler.load_autopilot_state",
                    return_value=self.universe(enabled=False),
                ), patch(
                    "stock_service.automation_scheduler.discover_autopilot_candidates",
                ) as discover, patch(
                    "stock_service.automation_scheduler.kis_snapshot",
                ) as snapshot, patch(
                    "stock_service.automation_scheduler.kis_quote",
                ) as quote:
                    result = run_automation_scheduler([], now=self.NOW)
                revoked = load_automation_policy()

        self.assertEqual(result["state"], "live_session_revoked")
        self.assertTrue(result["halted"])
        self.assertFalse(result["brokerOrderSent"])
        self.assertEqual(revoked["executionMode"], "paper")
        self.assertTrue(revoked["halted"])
        self.assertFalse(revoked["enabled"])
        self.assertEqual(revoked["liveSessionId"], "")
        discover.assert_not_called()
        snapshot.assert_not_called()
        quote.assert_not_called()

    def test_environment_mismatch_revokes_before_candidate_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.paths(directory)
            dependencies = self.live_dependencies()
            with paths[0], paths[1], paths[2], dependencies[0], dependencies[1]:
                save_automation_policy(self.live_policy())
                with patch(
                    "stock_service.automation_scheduler.load_autopilot_state",
                    return_value=self.universe(environment="paper"),
                ), patch(
                    "stock_service.automation_scheduler.discover_autopilot_candidates",
                ) as discover:
                    result = run_automation_scheduler([], now=self.NOW)

        self.assertEqual(result["state"], "live_session_revoked")
        self.assertIn(
            "autopilot_environment_mismatch",
            result["liveCycle"]["reasons"],
        )
        discover.assert_not_called()

    def test_dynamic_live_gates_revoke_before_any_market_io(self):
        cases = (
            ("risk", True, False, "production_risk_locked"),
            ("readiness", True, True, "live_readiness_revoked"),
            ("consent", False, True, "live_consent_revoked"),
        )
        for name, consent, risk_unlocked, expected_reason in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                paths = self.paths(directory)
                with paths[0], paths[1], paths[2], patch(
                    "stock_service.core.load_risk_policy",
                    return_value={"productionEnabled": risk_unlocked},
                ), patch(
                    "stock_service.automation_live.automation_live_status",
                    return_value={
                        "productionAutomationEligible": name != "readiness",
                    },
                ):
                    policy = self.live_policy()
                    policy["liveConsent"] = consent
                    save_automation_policy(policy)
                    with patch(
                        "stock_service.automation_scheduler.load_autopilot_state",
                        return_value=self.universe(),
                    ), patch(
                        "stock_service.automation_scheduler.discover_autopilot_candidates",
                    ) as discover, patch(
                        "stock_service.automation_scheduler.kis_snapshot",
                    ) as snapshot, patch(
                        "stock_service.automation_scheduler.kis_quote",
                    ) as quote:
                        result = run_automation_scheduler([], now=self.NOW)

                self.assertEqual(result["state"], "live_session_revoked")
                self.assertIn(expected_reason, result["liveCycle"]["reasons"])
                discover.assert_not_called()
                snapshot.assert_not_called()
                quote.assert_not_called()

    def test_widget_target_environment_mismatch_is_ignored_for_live_session(self):
        target = {
            "sourceId": "stock",
            "mode": "kis",
            "environment": "paper",
            "symbol": "005930",
            "market": "KRX",
            "language": "ko",
            "aiProvider": "both",
            "analysisProfile": "balanced",
            "backtestStrategy": "trend",
            "tradingMode": "automatic",
            "automationTargetEnabled": True,
        }
        with tempfile.TemporaryDirectory() as directory:
            paths = self.paths(directory)
            dependencies = self.live_dependencies()
            with paths[0], paths[1], paths[2], dependencies[0], dependencies[1]:
                save_automation_policy(self.live_policy())
                with patch(
                    "stock_service.automation_scheduler.load_autopilot_state",
                    return_value=self.universe(enabled=False),
                ):
                    result = run_automation_scheduler([target], now=self.NOW)

        self.assertEqual(result["state"], "no_target")
        self.assertFalse(result.get("liveRevoked", False))

    def test_live_candidate_refresh_uses_production_environment(self):
        stale = self.universe()
        stale["automaticSelection"] = True
        stale["lastScanAt"] = self.NOW - (6 * 60 * 60) - 1
        with tempfile.TemporaryDirectory() as directory:
            paths = self.paths(directory)
            dependencies = self.live_dependencies()
            with paths[0], paths[1], paths[2], dependencies[0], dependencies[1]:
                save_automation_policy(self.live_policy())
                with patch(
                    "stock_service.automation_scheduler.load_autopilot_state",
                    return_value=stale,
                ), patch(
                    "stock_service.automation_scheduler.discover_autopilot_candidates",
                    return_value={},
                ) as discover, patch(
                    "stock_service.automation_scheduler.automation_execution_status",
                    return_value={
                        "status": "ok",
                        "uncertaintyLock": False,
                        "audit": {"healthy": True},
                    },
                ), patch(
                    "stock_service.automation_scheduler.monitor_protective_positions",
                    return_value={
                        "status": "ok",
                        "state": "no_position",
                        "checked": 0,
                        "targetCount": 0,
                        "triggered": False,
                        "brokerOrderSent": False,
                    },
                ), patch(
                    "stock_service.automation_scheduler.load_automation_scheduler_runtime",
                    return_value={"lastWorkAt": self.NOW},
                ):
                    run_automation_scheduler([], now=self.NOW)

        self.assertEqual(
            discover.call_args.args[0]["environment"],
            "prod",
        )

    def test_operations_policy_coherence_accepts_valid_live_mode(self):
        policy = self.live_policy()
        with patch("stock_service.automation.time.time", return_value=self.NOW):
            policy = normalized_automation_policy(policy)

        self.assertTrue(automation_policy_coherent(policy, self.NOW))
        policy["liveSessionExpiresAt"] = self.NOW
        self.assertFalse(automation_policy_coherent(policy, self.NOW))


if __name__ == "__main__":
    unittest.main()
