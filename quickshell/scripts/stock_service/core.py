import argparse
import base64
import fcntl
import hashlib
import io
import json
import math
import os
import random
import re
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from contextlib import contextmanager, nullcontext
from datetime import datetime, timedelta
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree


APP_ID = "quickshell-stock-widget"
DEFAULT_RISK_POLICY = {
    "productionEnabled": False,
    "maxOrderValueKrw": 1000000,
    "maxDailyBuyValueKrw": 3000000,
    "maxBuyOrdersPerDay": 5,
    "maxPositionPercent": 25,
}
ALLOWED_SECRETS = {
    "kis_prod_app_key",
    "kis_prod_app_secret",
    "kis_prod_account",
    "kis_paper_app_key",
    "kis_paper_app_secret",
    "kis_paper_account",
    "openai_api_key",
    "anthropic_api_key",
    "kis_prod_access_token",
    "kis_prod_token_expiry",
    "kis_paper_access_token",
    "kis_paper_token_expiry",
    "kis_prod_ws_approval",
    "kis_prod_ws_expiry",
    "kis_paper_ws_approval",
    "kis_paper_ws_expiry",
}
SECURITIES = {
    ("KRX", "005930"): ("Samsung Electronics", 72100.0, "KRW"),
    ("KRX", "000660"): ("SK hynix", 183400.0, "KRW"),
    ("KRX", "035420"): ("NAVER", 214500.0, "KRW"),
    ("KRX", "035720"): ("Kakao", 48350.0, "KRW"),
    ("NASDAQ", "AAPL"): ("Apple", 228.45, "USD"),
    ("NASDAQ", "NVDA"): ("NVIDIA", 139.62, "USD"),
    ("NASDAQ", "MSFT"): ("Microsoft", 477.31, "USD"),
    ("NASDAQ", "TSLA"): ("Tesla", 301.18, "USD"),
    ("NYSE", "BRK.B"): ("Berkshire Hathaway", 493.12, "USD"),
}
SYMBOL_CATALOG_MAX_AGE = 7 * 24 * 60 * 60
SYMBOL_MASTER_URLS = (
    ("KRX", "KOSPI", "https://new.real.download.dws.co.kr/common/master/kospi_code.mst.zip", "kospi_code.mst", 228),
    ("KRX", "KOSDAQ", "https://new.real.download.dws.co.kr/common/master/kosdaq_code.mst.zip", "kosdaq_code.mst", 222),
    ("NASDAQ", "NASDAQ", "https://new.real.download.dws.co.kr/common/master/nasmst.cod.zip", "nasmst.cod", 0),
    ("NYSE", "NYSE", "https://new.real.download.dws.co.kr/common/master/nysmst.cod.zip", "nysmst.cod", 0),
)
BACKTEST_STRATEGIES = {
    "trend": ("MA Trend", "Long when the 5-day moving average is above the 20-day moving average."),
    "momentum": ("20D Momentum", "Long when the trailing 20-session return is positive."),
    "mean_reversion": ("RSI Reversion", "Enter below RSI 35 and return to cash above RSI 55."),
}


class StockServiceError(RuntimeError):
    pass


def numeric(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)


def state_directory():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    directory = os.path.join(base, "quickshell-stock-widget")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    return directory


def symbol_catalog_path():
    return os.path.join(state_directory(), "symbol-catalog.json")


def static_symbol_catalog():
    return [
        {"symbol": symbol, "market": market, "exchange": market, "name": values[0]}
        for (market, symbol), values in SECURITIES.items()
    ]


def parse_domestic_master(payload, filename, exchange, tail_width):
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        member = next(name for name in archive.namelist() if name.lower() == filename.lower())
        raw = archive.read(member).decode("cp949", errors="replace")
    items = []
    for row in raw.splitlines():
        prefix = row[:-tail_width] if len(row) > tail_width else ""
        symbol = prefix[:9].strip()
        name = prefix[21:].strip()
        if len(symbol) == 6 and symbol.isdigit() and name:
            items.append({"symbol": symbol, "market": "KRX", "exchange": exchange, "name": name})
    return items


def parse_overseas_master(payload, filename, market):
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        member = next(name for name in archive.namelist() if name.lower() == filename.lower())
        raw = archive.read(member).decode("cp949", errors="replace")
    items = []
    for row in raw.splitlines():
        fields = row.split("\t")
        if len(fields) < 9 or fields[8].strip() not in ("2", "3"):
            continue
        symbol = fields[4].strip().upper()
        name = fields[7].strip() or fields[6].strip()
        if symbol and name:
            items.append({"symbol": symbol, "market": market, "exchange": market, "name": name})
    return items


def download_symbol_catalog():
    items = []
    for market, exchange, url, filename, tail_width in SYMBOL_MASTER_URLS:
        request = urllib.request.Request(url, headers={"User-Agent": "Quickshell Stocks/1.0"})
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = response.read()
        if market == "KRX":
            items.extend(parse_domestic_master(payload, filename, exchange, tail_width))
        else:
            items.extend(parse_overseas_master(payload, filename, market))
    unique = {}
    for item in static_symbol_catalog() + items:
        unique[(item["market"], item["symbol"])] = item
    catalog = {"updatedAt": int(time.time()), "items": list(unique.values())}
    path = symbol_catalog_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, separators=(",", ":"))
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return catalog


def load_symbol_catalog():
    try:
        with open(symbol_catalog_path(), encoding="utf-8") as handle:
            catalog = json.load(handle)
        if not isinstance(catalog.get("items"), list):
            raise ValueError("Invalid symbol catalog")
        stale = int(time.time()) - int(catalog.get("updatedAt", 0)) > SYMBOL_CATALOG_MAX_AGE
        if not stale:
            return catalog, False
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        catalog = None
    try:
        return download_symbol_catalog(), False
    except (OSError, ValueError, StopIteration, zipfile.BadZipFile, urllib.error.URLError):
        if catalog:
            return catalog, True
        return {"updatedAt": 0, "items": static_symbol_catalog()}, True


def search_symbols(query, limit=8, market="ALL"):
    query = str(query).strip()
    if not query:
        return {"status": "ok", "query": "", "items": [], "stale": False}
    try:
        limit = max(1, min(20, int(limit)))
    except (TypeError, ValueError):
        limit = 8
    market = str(market).strip().upper() or "ALL"
    if market not in ("ALL", "KRX", "NASDAQ", "NYSE"):
        raise StockServiceError("Unsupported search market")
    catalog, stale = load_symbol_catalog()
    needle = query.casefold()
    matches = []
    for item in catalog["items"]:
        if market != "ALL" and item.get("market") != market:
            continue
        symbol = str(item.get("symbol", ""))
        name = str(item.get("name", ""))
        symbol_key = symbol.casefold()
        name_key = name.casefold()
        if needle not in symbol_key and needle not in name_key:
            continue
        if symbol_key == needle:
            rank = 0
        elif symbol_key.startswith(needle):
            rank = 1
        elif name_key.startswith(needle):
            rank = 2
        else:
            rank = 3
        matches.append((rank, len(name), symbol, item))
    matches.sort(key=lambda match: (match[0], match[1], match[2]))
    return {
        "status": "ok",
        "query": query,
        "items": [match[3] for match in matches[:limit]],
        "stale": stale,
        "updatedAt": int(catalog.get("updatedAt", 0)),
    }


def trade_audit(event):
    path = os.path.join(state_directory(), "trades.jsonl")
    payload = dict(event)
    payload["timestamp"] = int(time.time())
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
    finally:
        os.close(descriptor)


def risk_policy_path():
    return os.path.join(state_directory(), "risk-policy.json")


@contextmanager
def production_order_lock():
    path = os.path.join(state_directory(), "production-order.lock")
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def load_risk_policy():
    policy = dict(DEFAULT_RISK_POLICY)
    try:
        with open(risk_policy_path(), encoding="utf-8") as handle:
            stored = json.load(handle)
        for key in policy:
            if key in stored:
                policy[key] = stored[key]
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    policy["productionEnabled"] = bool(policy["productionEnabled"])
    for key in ("maxOrderValueKrw", "maxDailyBuyValueKrw", "maxBuyOrdersPerDay", "maxPositionPercent"):
        policy[key] = int(numeric(policy[key], DEFAULT_RISK_POLICY[key]))
    return policy


def save_risk_policy(patch):
    allowed = set(DEFAULT_RISK_POLICY)
    if not isinstance(patch, dict) or any(key not in allowed for key in patch):
        raise StockServiceError("Unsupported risk policy field")
    policy = load_risk_policy()
    policy.update(patch)
    policy["productionEnabled"] = bool(policy["productionEnabled"])
    for key in ("maxOrderValueKrw", "maxDailyBuyValueKrw"):
        value = int(numeric(policy[key]))
        if value < 1 or value > 1000000000000:
            raise StockServiceError("Risk value limits must be between 1 and 1,000,000,000,000 KRW")
        policy[key] = value
    policy["maxBuyOrdersPerDay"] = int(numeric(policy["maxBuyOrdersPerDay"]))
    if policy["maxBuyOrdersPerDay"] < 1 or policy["maxBuyOrdersPerDay"] > 1000:
        raise StockServiceError("Daily buy order limit must be between 1 and 1000")
    policy["maxPositionPercent"] = int(numeric(policy["maxPositionPercent"]))
    if policy["maxPositionPercent"] < 1 or policy["maxPositionPercent"] > 100:
        raise StockServiceError("Position limit must be between 1 and 100 percent")
    if policy["maxDailyBuyValueKrw"] < policy["maxOrderValueKrw"]:
        raise StockServiceError("Daily buy value must be at least the per-order value")
    path = risk_policy_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(policy, handle, ensure_ascii=False, separators=(",", ":"))
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    return policy


def production_buy_usage():
    path = os.path.join(state_directory(), "trades.jsonl")
    today = datetime.now().date()
    requests = {}
    legacy = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                stamp = numeric(event.get("timestamp"))
                if not stamp or datetime.fromtimestamp(stamp).date() != today:
                    continue
                if event.get("action") != "order" or event.get("environment") != "prod" or event.get("side") != "buy":
                    continue
                request_id = str(event.get("requestId", ""))
                if request_id:
                    requests[request_id] = event
                elif event.get("status") == "accepted":
                    legacy.append(event)
    except OSError:
        pass
    effective = legacy + [event for event in requests.values() if event.get("status") in ("submitting", "accepted")]
    return len(effective), sum(int(numeric(event.get("estimatedNotional"))) for event in effective)


def trade_activity(environment="all", limit=50):
    if environment not in ("all", "paper", "prod"):
        raise StockServiceError("Unsupported activity environment")
    try:
        limit = int(limit)
    except (TypeError, ValueError) as error:
        raise StockServiceError("Activity limit must be a number") from error
    path = os.path.join(state_directory(), "trades.jsonl")
    requests = {}
    sequence = 0
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                sequence += 1
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("action") not in ("order", "cancel"):
                    continue
                if environment != "all" and event.get("environment") != environment:
                    continue
                request_id = str(event.get("requestId") or f"legacy-{sequence}")
                event["requestId"] = request_id
                event["sequence"] = sequence
                requests[request_id] = event
    except OSError:
        pass
    now = int(time.time())
    activity = []
    for event in requests.values():
        status = str(event.get("status", "submitting"))
        timestamp = int(numeric(event.get("timestamp")))
        if status == "submitting" and now - timestamp > 300:
            status = "uncertain"
        activity.append({
            "requestId": event["requestId"],
            "action": str(event.get("action", "")),
            "environment": str(event.get("environment", "")),
            "status": status,
            "timestamp": timestamp,
            "side": str(event.get("side", "")),
            "symbol": str(event.get("symbol", "")),
            "quantity": int(numeric(event.get("quantity"))),
            "orderType": str(event.get("orderType", "")),
            "price": numeric(event.get("price")),
            "estimatedNotional": int(numeric(event.get("estimatedNotional"))),
            "orderNumber": str(event.get("orderNumber", "")),
            "originalOrderNumber": str(event.get("originalOrderNumber", "")),
            "message": str(event.get("message", "")),
            "sequence": event["sequence"],
        })
    activity.sort(key=lambda event: (event["timestamp"], event["sequence"]), reverse=True)
    capped = activity[:max(1, min(100, limit))]
    return {
        "status": "ok",
        "environment": environment,
        "activity": capped,
        "counts": {
            "accepted": sum(1 for event in activity if event["status"] == "accepted"),
            "failed": sum(1 for event in activity if event["status"] == "failed"),
            "pending": sum(1 for event in activity if event["status"] == "submitting"),
            "uncertain": sum(1 for event in activity if event["status"] == "uncertain"),
        },
        "updatedAt": now,
    }


def secret_lookup(key):
    if key not in ALLOWED_SECRETS:
        raise StockServiceError("Unsupported credential key")
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "application", APP_ID, "key", key],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise StockServiceError("System keychain is unavailable") from error
    return result.stdout.rstrip("\r\n") if result.returncode == 0 else ""


def secret_store(key, value):
    if key not in ALLOWED_SECRETS:
        raise StockServiceError("Unsupported credential key")
    if not value:
        raise StockServiceError("Credential cannot be empty")
    if key.endswith("_account"):
        value = re.sub(r"[^0-9]", "", value)
        if len(value) != 10:
            raise StockServiceError("KIS account must contain 8 account digits and a 2-digit product code")
    try:
        result = subprocess.run(
            [
                "secret-tool",
                "store",
                f"--label=Quickshell Stocks · {key}",
                "application",
                APP_ID,
                "key",
                key,
            ],
            input=value + "\n",
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise StockServiceError("System keychain is unavailable") from error
    if result.returncode != 0:
        raise StockServiceError("Could not save credential to the system keychain")


def secret_clear(key):
    if key not in ALLOWED_SECRETS:
        raise StockServiceError("Unsupported credential key")
    try:
        subprocess.run(
            ["secret-tool", "clear", "application", APP_ID, "key", key],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return


def credential_status():
    prod = bool(secret_lookup("kis_prod_app_key") and secret_lookup("kis_prod_app_secret"))
    paper = bool(secret_lookup("kis_paper_app_key") and secret_lookup("kis_paper_app_secret"))
    risk = load_risk_policy()
    return {
        "status": "ok",
        "keychain": True,
        "kisProd": prod,
        "kisPaper": paper,
        "kisProdAccount": bool(secret_lookup("kis_prod_account")),
        "kisPaperAccount": bool(secret_lookup("kis_paper_account")),
        "openai": bool(secret_lookup("openai_api_key")),
        "claude": bool(secret_lookup("anthropic_api_key")),
        "productionTradingEnabled": risk["productionEnabled"],
        "riskPolicy": risk,
    }


def http_json(url, method="GET", headers=None, payload=None, params=None, timeout=12):
    if params:
        url += "?" + urllib.parse.urlencode(params)
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        try:
            detail = json.loads(error.read().decode("utf-8"))
            nested = detail.get("error") if isinstance(detail.get("error"), dict) else {}
            message = (
                detail.get("msg1")
                or detail.get("error_description")
                or detail.get("message")
                or nested.get("message")
            )
        except Exception:
            message = None
        raise StockServiceError(message or f"Request failed ({error.code})") from error
    except urllib.error.URLError as error:
        raise StockServiceError("Could not reach the remote API") from error
