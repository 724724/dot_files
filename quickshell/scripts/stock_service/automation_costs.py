from .core import numeric


DEFAULT_TRANSACTION_COSTS = {
    "KRX": {
        "commissionBps": 1.5,
        "slippageBps": 5,
        "sellTaxBps": 15,
        "sellCostLabel": "estimated_transaction_tax",
    },
    "US": {
        "commissionBps": 25,
        "slippageBps": 5,
        "sellTaxBps": 1,
        "sellCostLabel": "estimated_regulatory_fees",
    },
}


def automation_transaction_costs(market, policy=None):
    market = str(market or "KRX").strip().upper()
    policy = policy if isinstance(policy, dict) else {}
    defaults = DEFAULT_TRANSACTION_COSTS["KRX" if market == "KRX" else "US"]
    if market == "KRX":
        commission = numeric(
            policy.get("krxCommissionBps"), defaults["commissionBps"],
        )
        sell_cost = numeric(
            policy.get("krxSellTaxBps"), defaults["sellTaxBps"],
        )
    else:
        commission = numeric(
            policy.get("usCommissionBps"), defaults["commissionBps"],
        )
        sell_cost = numeric(
            policy.get("usSellFeeBps"), defaults["sellTaxBps"],
        )
    return {
        "market": market,
        "commissionBps": max(0, commission),
        "slippageBps": max(
            0,
            numeric(policy.get("assumedSlippageBps"), defaults["slippageBps"]),
        ),
        "sellTaxBps": max(0, sell_cost),
        "sellCostLabel": defaults["sellCostLabel"],
        "estimated": True,
    }
