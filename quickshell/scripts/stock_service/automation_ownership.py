from .core import StockServiceError, numeric


CONFIRMED_FILL_STATES = {"filled", "partial", "canceled"}
SUPPORTED_ENVIRONMENTS = {"paper", "prod"}
SUPPORTED_MARKETS = {"KRX", "NASDAQ", "NYSE"}


def ownership_identity(environment, market, symbol):
    environment = str(environment).strip().lower()
    market = str(market or "KRX").strip().upper()
    symbol = str(symbol).strip().upper()
    if environment not in SUPPORTED_ENVIRONMENTS:
        raise StockServiceError("Managed-position environment is invalid")
    if market not in SUPPORTED_MARKETS or not symbol:
        raise StockServiceError("Managed-position instrument is invalid")
    return f"{environment}:{market}:{symbol}"


def managed_position_ledger(records, environment):
    environment = str(environment).strip().lower()
    if environment not in SUPPORTED_ENVIRONMENTS:
        raise StockServiceError("Managed-position environment is invalid")
    quantities = {}
    fills = {}
    for record in records if isinstance(records, list) else []:
        if not isinstance(record, dict) or str(record.get("environment", "")).lower() != environment:
            continue
        state = str(record.get("brokerState") or record.get("state") or "").lower()
        quantity = max(0, int(numeric(record.get("filledQuantity"))))
        if quantity <= 0 or state not in CONFIRMED_FILL_STATES:
            continue
        market = str(record.get("market", "KRX")).strip().upper()
        symbol = str(record.get("symbol", "")).strip().upper()
        if market not in SUPPORTED_MARKETS or not symbol:
            continue
        identity = ownership_identity(environment, market, symbol)
        direction = 1 if record.get("side") == "buy" else (
            -1 if record.get("side") == "sell" else 0
        )
        if direction == 0:
            continue
        quantities[identity] = quantities.get(identity, 0) + direction * quantity
        fills[identity] = fills.get(identity, 0) + 1
    negative = {
        identity: quantity for identity, quantity in quantities.items() if quantity < 0
    }
    return {
        "environment": environment,
        "quantities": {
            identity: max(0, quantity) for identity, quantity in quantities.items()
        },
        "fillCounts": fills,
        "negativePositions": negative,
        "healthy": not negative,
    }


def account_holding(account, market, symbol):
    market = str(market or "KRX").strip().upper()
    symbol = str(symbol).strip().upper()
    return next((
        item for item in account.get("holdings", [])
        if str(item.get("symbol", "")).strip().upper() == symbol
        and str(item.get("market", market)).strip().upper() == market
    ), {})


def managed_position_ownership(records, account, environment, market, symbol):
    ledger = managed_position_ledger(records, environment)
    identity = ownership_identity(environment, market, symbol)
    if identity in ledger["negativePositions"]:
        raise StockServiceError("Managed-position journal has a negative net quantity")
    holding = account_holding(account, market, symbol)
    account_quantity = max(0, int(numeric(
        holding.get("quantity"),
        account.get("holdingQuantity"),
    )))
    sellable_quantity = max(0, int(numeric(
        holding.get("sellableQuantity"),
        account.get("sellableQuantity"),
    )))
    journal_quantity = max(0, int(numeric(ledger["quantities"].get(identity))))
    managed_quantity = min(journal_quantity, account_quantity)
    managed_sellable = min(managed_quantity, sellable_quantity)
    manual_quantity = max(0, account_quantity - journal_quantity)
    return {
        "identity": identity,
        "environment": str(environment).lower(),
        "market": str(market).upper(),
        "symbol": str(symbol).upper(),
        "journalQuantity": journal_quantity,
        "accountQuantity": account_quantity,
        "sellableQuantity": sellable_quantity,
        "managedQuantity": managed_quantity,
        "managedSellableQuantity": managed_sellable,
        "manualQuantity": manual_quantity,
        "mixedWithManual": manual_quantity > 0,
        "accountBelowJournal": account_quantity < journal_quantity,
        "fillCount": int(numeric(ledger["fillCounts"].get(identity))),
    }


def managed_account_view(account, ownership, current_price=0):
    result = dict(account)
    holdings = []
    market = ownership["market"]
    symbol = ownership["symbol"]
    managed_quantity = int(ownership["managedQuantity"])
    managed_sellable = int(ownership["managedSellableQuantity"])
    price = numeric(current_price)
    for source in account.get("holdings", []):
        item = dict(source)
        if (
            str(item.get("symbol", "")).strip().upper() == symbol
            and str(item.get("market", market)).strip().upper() == market
        ):
            item["quantity"] = managed_quantity
            item["sellableQuantity"] = managed_sellable
            holding_price = price or numeric(item.get("price"))
            item["evaluation"] = managed_quantity * holding_price
        holdings.append(item)
    result["holdings"] = holdings
    result["holdingQuantity"] = managed_quantity
    result["sellableQuantity"] = managed_sellable
    result["managedPositionOwnership"] = dict(ownership)
    return result
