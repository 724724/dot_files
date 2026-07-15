import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from stock_service.ai_usage import (
    ai_usage_summary,
    append_ai_usage,
    load_ai_usage,
    normalize_ai_usage,
)


class StockAiUsageTests(unittest.TestCase):
    def test_openai_usage_does_not_double_count_cached_input(self):
        usage = normalize_ai_usage("openai", {
            "input_tokens": 2000,
            "output_tokens": 600,
            "total_tokens": 2600,
            "input_tokens_details": {"cached_tokens": 800},
            "output_tokens_details": {"reasoning_tokens": 120},
        })

        self.assertEqual(usage["billableInputTokens"], 2000)
        self.assertEqual(usage["cachedInputTokens"], 800)
        self.assertEqual(usage["reasoningTokens"], 120)
        self.assertEqual(usage["totalTokens"], 2600)

    def test_claude_usage_includes_cache_components(self):
        usage = normalize_ai_usage("claude", {
            "input_tokens": 1000,
            "output_tokens": 400,
            "cache_creation_input_tokens": 200,
            "cache_read_input_tokens": 300,
        })

        self.assertEqual(usage["billableInputTokens"], 1500)
        self.assertEqual(usage["totalTokens"], 1900)

    def test_usage_summary_filters_window_and_groups_models(self):
        events = [
            {
                "timestamp": 1_000_000,
                "provider": "openai",
                "model": "gpt-test",
                "inputTokens": 1000,
                "billableInputTokens": 1000,
                "outputTokens": 200,
                "totalTokens": 1200,
                "cachedInputTokens": 0,
                "cacheWriteTokens": 0,
                "reasoningTokens": 0,
            },
            {
                "timestamp": 999_000,
                "provider": "openai",
                "model": "gpt-test",
                "inputTokens": 800,
                "billableInputTokens": 800,
                "outputTokens": 200,
                "totalTokens": 1000,
                "cachedInputTokens": 200,
                "cacheWriteTokens": 0,
                "reasoningTokens": 0,
            },
            {
                "timestamp": 100,
                "provider": "claude",
                "model": "claude-old",
                "inputTokens": 5000,
                "billableInputTokens": 5000,
                "outputTokens": 1000,
                "totalTokens": 6000,
                "cachedInputTokens": 0,
                "cacheWriteTokens": 0,
                "reasoningTokens": 0,
            },
        ]

        result = ai_usage_summary(1, 10, now=1_000_000, events=events)

        self.assertEqual(result["summary"]["calls"], 2)
        self.assertEqual(result["summary"]["totalTokens"], 2200)
        self.assertEqual(len(result["models"]), 1)
        self.assertEqual(result["models"][0]["model"], "gpt-test")

    def test_usage_ledger_stores_metadata_without_prompt_content(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("stock_service.ai_usage.state_directory", return_value=directory):
                event = append_ai_usage(
                    "openai",
                    "gpt-test",
                    "balanced",
                    "005930",
                    {"input_tokens": 1000, "output_tokens": 250, "total_tokens": 1250},
                    timestamp=1_000_000,
                )
                loaded = load_ai_usage()

        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0]["id"], event["id"])
        self.assertNotIn("prompt", loaded[0])
        self.assertNotIn("response", loaded[0])


if __name__ == "__main__":
    unittest.main()
