from .core import *
from zoneinfo import ZoneInfo


KIS_REST_INTERVAL = {"paper": 0.65, "prod": 0.15}
KRX_TIMEZONE = ZoneInfo("Asia/Seoul")
OVERSEAS_MARKETS = {
    "NASDAQ": {"quote": "NAS", "order": "NASD", "currency": "USD", "timezone": ZoneInfo("America/New_York")},
    "NYSE": {"quote": "NYS", "order": "NYSE", "currency": "USD", "timezone": ZoneInfo("America/New_York")},
}


class KisPostError(StockServiceError):
    def __init__(
        self,
        message,
        *,
        request_sent=False,
        outcome_ambiguous=False,
        broker_code="",
        failure_class="operator",
    ):
        super().__init__(message)
        self.request_sent = bool(request_sent)
        self.outcome_ambiguous = bool(outcome_ambiguous)
        self.broker_code = str(broker_code or "")
        self.failure_class = str(failure_class or "operator")


def overseas_market_codes(market):
    code = str(market or "").strip().upper()
    if code not in OVERSEAS_MARKETS:
        raise StockServiceError("Unsupported overseas market")
    return code, OVERSEAS_MARKETS[code]


def internal_overseas_market(exchange, fallback="NASDAQ"):
    code = str(exchange or "").strip().upper()
    if code in ("NYSE", "NYS"):
        return "NYSE"
    if code in ("NASD", "NAS"):
        return "NASDAQ"
    return fallback


def kis_rate_limit_path(environment):
    return os.path.join(state_directory(), f"kis-{environment}-rest-rate")


@contextmanager
def kis_credential_refresh_lock(environment, kind):
    path = os.path.join(state_directory(), f"kis-{environment}-{kind}-refresh.lock")
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def kis_wait_for_slot(environment):
    path = kis_rate_limit_path(environment)
    descriptor = os.open(path + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        try:
            with open(path, encoding="utf-8") as handle:
                previous = numeric(handle.read())
        except OSError:
            previous = 0
        delay = KIS_REST_INTERVAL["paper" if environment == "paper" else "prod"] - (time.time() - previous)
        if delay > 0:
            time.sleep(delay)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(time.time()))
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def kis_rate_limited_message(message):
    value = str(message or "")
    return "EGW00201" in value or "초당 거래건수" in value


def kis_http_json(environment, url, **kwargs):
    for attempt in range(3):
        kis_wait_for_slot(environment)
        try:
            response = http_json(url, **kwargs)
        except StockServiceError as error:
            if not kis_rate_limited_message(error) or attempt == 2:
                raise
            time.sleep(0.75 * (attempt + 1))
            continue
        if str(response.get("rt_cd", "0")) == "0" or not kis_rate_limited_message(response.get("msg1")):
            return response
        if attempt == 2:
            return response
        time.sleep(0.75 * (attempt + 1))
    raise StockServiceError("KIS request retry failed")

def kis_config(environment):
    env = "paper" if environment == "paper" else "prod"
    app_key = secret_lookup(f"kis_{env}_app_key")
    app_secret = secret_lookup(f"kis_{env}_app_secret")
    if not app_key or not app_secret:
        raise StockServiceError(f"KIS {env} credentials are not saved")
    base_url = (
        "https://openapivts.koreainvestment.com:29443"
        if env == "paper"
        else "https://openapi.koreainvestment.com:9443"
    )
    return env, base_url, app_key, app_secret


def kis_token(environment):
    env, base_url, app_key, app_secret = kis_config(environment)
    with kis_credential_refresh_lock(env, "token"):
        token = secret_lookup(f"kis_{env}_access_token")
        expiry_raw = secret_lookup(f"kis_{env}_token_expiry")
        try:
            expiry = float(expiry_raw)
        except ValueError:
            expiry = 0
        if token and expiry > time.time() + 90:
            return base_url, app_key, app_secret, token
        response = kis_http_json(
            env,
            base_url + "/oauth2/tokenP",
            method="POST",
            headers={"Content-Type": "application/json", "Accept": "text/plain"},
            payload={"grant_type": "client_credentials", "appkey": app_key, "appsecret": app_secret},
        )
        token = response.get("access_token", "")
        if not token:
            raise StockServiceError("KIS did not return an access token")
        expires_in = int(response.get("expires_in", 86400))
        secret_store(f"kis_{env}_access_token", token)
        secret_store(f"kis_{env}_token_expiry", str(time.time() + max(300, expires_in - 120)))
        return base_url, app_key, app_secret, token


def kis_ws_approval(environment):
    env, base_url, app_key, app_secret = kis_config(environment)
    with kis_credential_refresh_lock(env, "websocket"):
        approval = secret_lookup(f"kis_{env}_ws_approval")
        expiry_raw = secret_lookup(f"kis_{env}_ws_expiry")
        try:
            expiry = float(expiry_raw)
        except ValueError:
            expiry = 0
        if approval and expiry > time.time() + 90:
            return env, approval
        response = kis_http_json(
            env,
            base_url + "/oauth2/Approval",
            method="POST",
            headers={"Content-Type": "application/json", "Accept": "text/plain"},
            payload={"grant_type": "client_credentials", "appkey": app_key, "secretkey": app_secret},
        )
        approval = response.get("approval_key", "")
        if not approval:
            raise StockServiceError("KIS did not return a WebSocket approval key")
        secret_store(f"kis_{env}_ws_approval", approval)
        secret_store(f"kis_{env}_ws_expiry", str(time.time() + 20 * 60 * 60))
        return env, approval


def recv_exact(connection, size):
    data = bytearray()
    while len(data) < size:
        chunk = connection.recv(size - len(data))
        if not chunk:
            raise StockServiceError("KIS WebSocket closed")
        data.extend(chunk)
    return bytes(data)


def websocket_send(connection, payload, opcode=1):
    raw = payload.encode("utf-8") if isinstance(payload, str) else payload
    mask = os.urandom(4)
    length = len(raw)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    header.extend(mask)
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(raw))
    connection.sendall(bytes(header) + masked)


def websocket_receive(connection):
    first, second = recv_exact(connection, 2)
    opcode = first & 0x0F
    masked = bool(second & 0x80)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(connection, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(connection, 8))[0]
    mask = recv_exact(connection, 4) if masked else None
    payload = recv_exact(connection, length)
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return opcode, payload


def websocket_connect(host, port):
    connection = socket.create_connection((host, port), timeout=12)
    connection.settimeout(70)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        "GET /tryitout HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    connection.sendall(request.encode("ascii"))
    response = bytearray()
    while b"\r\n\r\n" not in response and len(response) < 16384:
        response.extend(connection.recv(4096))
    status_line = bytes(response).split(b"\r\n", 1)[0]
    if b" 101 " not in status_line:
        connection.close()
        raise StockServiceError("KIS WebSocket upgrade failed")
    return connection


def realtime_tick(values):
    if len(values) < 46:
        return None
    date_text = values[33]
    time_text = values[1]
    timestamp = int(time.time())
    if len(date_text) == 8 and len(time_text) == 6:
        try:
            timestamp = int(datetime.strptime(date_text + time_text, "%Y%m%d%H%M%S").timestamp())
        except ValueError:
            pass
    return {
        "status": "tick",
        "symbol": values[0],
        "time": timestamp,
        "price": numeric(values[2]),
        "change": numeric(values[4]),
        "changePct": numeric(values[5]),
        "high": numeric(values[8]),
        "low": numeric(values[9]),
        "ask": numeric(values[10]),
        "bid": numeric(values[11]),
        "tradeVolume": int(numeric(values[12])),
        "volume": int(numeric(values[13])),
    }


def stream_ticks(symbol, environment):
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("KRX symbols must contain six digits")
    env, approval = kis_ws_approval(environment)
    host = "ops.koreainvestment.com"
    port = 31000 if env == "paper" else 21000
    emit({"status": "connecting", "transport": "websocket"})
    connection = websocket_connect(host, port)
    subscription = {
        "header": {"approval_key": approval, "custtype": "P", "tr_type": "1", "content-type": "utf-8"},
        "body": {"input": {"tr_id": "H0STCNT0", "tr_key": symbol}},
    }
    websocket_send(connection, json.dumps(subscription, separators=(",", ":")))
    columns_per_record = 46
    try:
        while True:
            opcode, payload = websocket_receive(connection)
            if opcode == 8:
                raise StockServiceError("KIS WebSocket closed")
            if opcode == 9:
                websocket_send(connection, payload, 10)
                continue
            if opcode not in (1, 2):
                continue
            text = payload.decode("utf-8", errors="replace")
            if text.startswith("0|H0STCNT0|"):
                parts = text.split("|", 3)
                count = int(parts[2])
                values = parts[3].split("^")
                for index in range(count):
                    tick = realtime_tick(values[index * columns_per_record:(index + 1) * columns_per_record])
                    if tick:
                        emit(tick)
                continue
            try:
                message = json.loads(text)
            except json.JSONDecodeError:
                continue
            header = message.get("header") or {}
            body = message.get("body") or {}
            if header.get("tr_id") == "PINGPONG":
                websocket_send(connection, payload, 10)
            elif str(body.get("rt_cd", "0")) == "0":
                emit({"status": "connected", "transport": "websocket", "message": body.get("msg1", "")})
            else:
                secret_clear(f"kis_{env}_ws_approval")
                secret_clear(f"kis_{env}_ws_expiry")
                raise StockServiceError(body.get("msg1") or "KIS WebSocket subscription failed")
    finally:
        connection.close()


def kis_get(environment, path, tr_id, params):
    base_url, app_key, app_secret, token = kis_token(environment)
    response = kis_http_json(
        environment,
        base_url + path,
        headers={
            "Content-Type": "application/json",
            "Accept": "text/plain",
            "User-Agent": "Quickshell Stocks/1.0",
            "authorization": f"Bearer {token}",
            "appkey": app_key,
            "appsecret": app_secret,
            "tr_id": tr_id,
            "custtype": "P",
        },
        params=params,
    )
    if str(response.get("rt_cd", "0")) != "0":
        raise StockServiceError(response.get("msg1") or "KIS returned an error")
    return response


def kis_post(environment, path, tr_id, payload):
    try:
        base_url, app_key, app_secret, token = kis_token(environment)
    except Exception as error:
        raise KisPostError(
            str(error),
            request_sent=False,
            outcome_ambiguous=False,
            failure_class="operator",
        ) from error
    try:
        response = kis_http_json(
            environment,
            base_url + path,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Accept": "text/plain",
                "User-Agent": "Quickshell Stocks/1.0",
                "authorization": f"Bearer {token}",
                "appkey": app_key,
                "appsecret": app_secret,
                "tr_id": tr_id,
                "custtype": "P",
            },
            payload=payload,
        )
    except Exception as error:
        raise KisPostError(
            str(error),
            request_sent=True,
            outcome_ambiguous=True,
            failure_class="hard",
        ) from error
    if str(response.get("rt_cd", "0")) != "0":
        message = response.get("msg1") or "KIS returned an error"
        raise KisPostError(
            message,
            request_sent=True,
            outcome_ambiguous=False,
            broker_code=str(response.get("msg_cd") or response.get("rt_cd") or ""),
            failure_class=(
                "transient" if kis_rate_limited_message(message) else "operator"
            ),
        )
    return response


def kis_account_parts(environment):
    env = "paper" if environment == "paper" else "prod"
    account = re.sub(r"[^0-9]", "", secret_lookup(f"kis_{env}_account"))
    if len(account) != 10:
        raise StockServiceError(f"KIS {env} account is not saved")
    return account[:8], account[8:]


def overseas_history_points(environment, symbol, market, count=260):
    market, codes = overseas_market_codes(market)
    symbol = str(symbol or "").strip().upper()
    if not re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol):
        raise StockServiceError("Overseas symbol is invalid")
    count = max(2, min(500, int(count)))
    cursor = ""
    points = {}
    for _ in range(max(1, math.ceil(count / 90)) + 1):
        response = kis_get(
            environment,
            "/uapi/overseas-price/v1/quotations/dailyprice",
            "HHDFS76240000",
            {
                "AUTH": "",
                "EXCD": codes["quote"],
                "SYMB": symbol,
                "GUBN": "0",
                "BYMD": cursor,
                "MODP": "1",
            },
        )
        rows = response.get("output2") or []
        if isinstance(rows, dict):
            rows = [rows]
        oldest = None
        before = len(points)
        for row in rows:
            date_text = str(row.get("xymd", ""))
            value = numeric(row.get("clos"))
            if len(date_text) != 8 or value <= 0:
                continue
            try:
                point_date = datetime.strptime(date_text, "%Y%m%d").date()
            except ValueError:
                continue
            stamp = int(datetime.combine(point_date, datetime.min.time(), tzinfo=codes["timezone"]).timestamp())
            points[stamp] = {
                "t": stamp,
                "v": value,
                "volume": int(numeric(row.get("tvol"))),
                "high": numeric(row.get("high")),
                "low": numeric(row.get("low")),
                "open": numeric(row.get("open")),
                "bid": numeric(row.get("pbid")),
                "ask": numeric(row.get("pask")),
            }
            oldest = point_date if oldest is None or point_date < oldest else oldest
        if len(points) >= count or oldest is None or len(points) == before:
            break
        cursor = (oldest - timedelta(days=1)).strftime("%Y%m%d")
    return sorted(points.values(), key=lambda point: point["t"])[-count:]


def overseas_intraday_points(environment, symbol, market, period):
    market, codes = overseas_market_codes(market)
    interval = "1" if period == "30M" else "5"
    response = kis_get(
        environment,
        "/uapi/overseas-price/v1/quotations/inquire-time-itemchartprice",
        "HHDFS76950200",
        {
            "AUTH": "",
            "EXCD": codes["quote"],
            "SYMB": symbol,
            "NMIN": interval,
            "PINC": "1",
            "NEXT": "",
            "NREC": "120",
            "FILL": "",
            "KEYB": "",
        },
    )
    rows = response.get("output2") or []
    if isinstance(rows, dict):
        rows = [rows]
    points = {}
    for row in rows:
        date_text = str(row.get("xymd") or row.get("kymd") or "")
        time_text = str(row.get("xhms") or row.get("khms") or "")
        value = numeric(row.get("last"))
        if len(date_text) != 8 or len(time_text) != 6 or value <= 0:
            continue
        try:
            moment = datetime.strptime(date_text + time_text, "%Y%m%d%H%M%S").replace(tzinfo=codes["timezone"])
        except ValueError:
            continue
        stamp = int(moment.timestamp())
        points[stamp] = {"t": stamp, "v": value, "volume": int(numeric(row.get("evol")))}
    result = sorted(points.values(), key=lambda point: point["t"])
    return result[-30:] if period == "30M" else result


def overseas_quote_timestamp(value, timezone, fallback=0):
    date_text = str(value.get("dymd") or value.get("xymd") or value.get("kymd") or "")
    time_text = str(value.get("dhms") or value.get("xhms") or value.get("khms") or "")
    if len(date_text) == 8 and len(time_text) == 6:
        try:
            return int(datetime.strptime(date_text + time_text, "%Y%m%d%H%M%S").replace(
                tzinfo=timezone,
            ).timestamp())
        except ValueError:
            pass
    return int(fallback)


def kis_overseas_orderbook(symbol, market, environment):
    market, codes = overseas_market_codes(market)
    response = kis_get(
        environment,
        "/uapi/overseas-price/v1/quotations/inquire-asking-price",
        "HHDFS76200100",
        {"AUTH": "", "EXCD": codes["quote"], "SYMB": symbol},
    )
    values = {}
    for key in ("output1", "output2", "output3"):
        output = response.get(key) or {}
        if isinstance(output, list):
            output = output[0] if output else {}
        if isinstance(output, dict):
            values.update(output)
    checked_at = overseas_quote_timestamp(values, codes["timezone"])
    return {
        "ask": numeric(values.get("pask1")),
        "bid": numeric(values.get("pbid1")),
        "askQuantity": int(numeric(values.get("vask1"))),
        "bidQuantity": int(numeric(values.get("vbid1"))),
        "orderbookUpdatedAt": checked_at,
        "orderbookDate": str(values.get("dymd", "")),
        "orderbookTime": str(values.get("dhms", "")),
    }


def kis_overseas_quote(symbol, market, environment, include_orderbook=False):
    market, codes = overseas_market_codes(market)
    symbol = str(symbol or "").strip().upper()
    if not re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol):
        raise StockServiceError("Overseas symbol is invalid")
    response = kis_get(
        environment,
        "/uapi/overseas-price/v1/quotations/price-detail",
        "HHDFS76200200",
        {"AUTH": "", "EXCD": codes["quote"], "SYMB": symbol},
    )
    quote = response.get("output") or {}
    if isinstance(quote, list):
        quote = quote[0] if quote else {}
    price = numeric(quote.get("last"))
    previous = numeric(quote.get("base"))
    change = price - previous
    orderable = str(quote.get("e_ordyn", "")).strip().upper()
    available = price > 0
    checked_at = int(time.time())
    source_updated_at = overseas_quote_timestamp(
        quote,
        codes["timezone"],
    )
    tick_size = numeric(quote.get("e_hogau"))
    if tick_size <= 0:
        decimals = max(0, min(8, int(numeric(quote.get("zdiv"), 2))))
        tick_size = 10 ** -decimals
    result = {
        "status": "ok",
        "mode": "kis",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "name": SECURITIES.get((market, symbol), (symbol, 0, codes["currency"]))[0],
        "currency": str(quote.get("curr") or codes["currency"]),
        "price": price,
        "previousClose": previous,
        "change": change,
        "changePct": numeric(quote.get("rate"), change / previous * 100 if previous else 0),
        "high": numeric(quote.get("high")),
        "low": numeric(quote.get("low")),
        "open": numeric(quote.get("open")),
        "volume": int(numeric(quote.get("tvol"))),
        "exchangeRate": numeric(quote.get("t_rate")),
        "priceKrw": numeric(quote.get("t_xprc")),
        "tickSize": tick_size,
        "marketSafety": {
            "checkedAt": checked_at,
            "available": available,
            "tradable": available and orderable not in ("N", "0"),
            "restricted": orderable in ("N", "0"),
            "restrictionReasons": ["not_orderable"] if orderable in ("N", "0") else [],
        },
        "receivedAt": checked_at,
        "sourceUpdatedAt": source_updated_at,
        "updatedAt": checked_at,
    }
    if include_orderbook:
        result.update(kis_overseas_orderbook(symbol, market, environment))
    return result


def daily_points(environment, symbol, period):
    end = datetime.now(KRX_TIMEZONE)
    days = {"1W": 10, "1M": 45, "3M": 110}.get(period, 10)
    start = end - timedelta(days=days)
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
    points = []
    for row in reversed(response.get("output2") or []):
        date_text = str(row.get("stck_bsop_date", ""))
        value = numeric(row.get("stck_clpr"))
        if len(date_text) == 8 and value > 0:
            stamp = int(datetime.strptime(date_text, "%Y%m%d").replace(tzinfo=KRX_TIMEZONE).timestamp())
            points.append({"t": stamp, "v": value})
    return points


def intraday_response(environment, symbol):
    now = datetime.now(KRX_TIMEZONE)
    return kis_get(
        environment,
        "/uapi/domestic-stock/v1/quotations/inquire-time-itemchartprice",
        "FHKST03010200",
        {
            "FID_COND_MRKT_DIV_CODE": "J",
            "FID_INPUT_ISCD": symbol,
            "FID_INPUT_HOUR_1": now.strftime("%H%M%S"),
            "FID_PW_DATA_INCU_YN": "Y",
            "FID_ETC_CLS_CODE": "",
        },
    )


def intraday_points(response):
    now = datetime.now(KRX_TIMEZONE)
    quote = response.get("output1") or {}
    if isinstance(quote, list):
        quote = quote[0] if quote else {}
    business_date = str(quote.get("stck_bsop_date", ""))
    point_date = now.date()
    if len(business_date) == 8:
        try:
            point_date = datetime.strptime(business_date, "%Y%m%d").date()
        except ValueError:
            pass
    points = []
    for row in reversed(response.get("output2") or []):
        row_date = str(row.get("stck_bsop_date", ""))
        if len(row_date) == 8:
            try:
                point_date = datetime.strptime(row_date, "%Y%m%d").date()
            except ValueError:
                pass
        time_text = str(row.get("stck_cntg_hour", ""))
        value = numeric(row.get("stck_prpr"))
        if len(time_text) == 6 and value > 0:
            point_time = datetime.combine(
                point_date, datetime.strptime(time_text, "%H%M%S").time(), tzinfo=KRX_TIMEZONE
            )
            points.append({"t": int(point_time.timestamp()), "v": value})
    return points


def kis_vi_status(symbol, environment, now=None):
    current = now if isinstance(now, datetime) else datetime.now(KRX_TIMEZONE)
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/quotations/inquire-vi-status",
        "FHPST01390000",
        {
            "FID_DIV_CLS_CODE": "0",
            "FID_COND_SCR_DIV_CODE": "20139",
            "FID_MRKT_CLS_CODE": "0",
            "FID_INPUT_ISCD": symbol,
            "FID_RANK_SORT_CLS_CODE": "0",
            "FID_INPUT_DATE_1": current.strftime("%Y%m%d"),
            "FID_TRGT_CLS_CODE": "0",
            "FID_TRGT_EXLS_CLS_CODE": "",
        },
    )
    rows = response.get("output") or []
    if isinstance(rows, dict):
        rows = [rows]
    rows = [
        row for row in rows
        if not str(row.get("mksc_shrn_iscd", "")).strip()
        or str(row.get("mksc_shrn_iscd", "")).strip() == symbol
    ]
    latest = max(
        rows,
        key=lambda row: str(row.get("bsop_date", "")) + str(row.get("cntg_vi_hour", "")),
        default={},
    )
    activation = int(numeric(latest.get("cntg_vi_hour")))
    cancellation = int(numeric(latest.get("vi_cncl_hour")))
    current_time = int(current.strftime("%H%M%S"))
    active = activation > 0 and (cancellation <= 0 or current_time < cancellation)
    return {
        "available": True,
        "active": active,
        "kindCode": str(latest.get("vi_kind_code", "")).strip(),
        "triggeredAt": str(latest.get("cntg_vi_hour", "")).strip(),
        "releaseAt": str(latest.get("vi_cncl_hour", "")).strip(),
    }


def quote_market_safety(quote, price, vi_status=None):
    normal_codes = ("", "0", "00", "N")
    # iscd_stat_cls_code: 51 관리, 52 투자위험, 53 투자경고, 54 투자주의,
    # 55 신용가능, 57 증거금 100%, 58 거래정지, 59 단기과열. Only 58 (and a
    # temporary halt) makes the security untradable; 55/57 are normal states.
    status_risk_codes = {
        "51": "managed_issue",
        "52": "investment_risk",
        "53": "market_warning",
        "54": "investment_caution",
        "59": "short_overheated",
    }
    status_code = str(quote.get("iscd_stat_cls_code", "")).strip().upper()
    warning_code = str(quote.get("mrkt_warn_cls_code", "")).strip().upper()
    managed_code = str(quote.get("mang_issu_cls_code", "")).strip().upper()
    upper_limit = numeric(quote.get("stck_mxpr"))
    lower_limit = numeric(quote.get("stck_llam"))
    temporary_halt = str(quote.get("temp_stop_yn", "")).strip().upper() == "Y"
    restrictions = []
    if str(quote.get("invt_caful_yn", "")).strip().upper() == "Y":
        restrictions.append("investment_caution")
    if warning_code not in normal_codes:
        restrictions.append("market_warning")
    if str(quote.get("short_over_yn", "")).strip().upper() == "Y":
        restrictions.append("short_overheated")
    if str(quote.get("sltr_yn", "")).strip().upper() == "Y":
        restrictions.append("liquidation_trading")
    if managed_code not in normal_codes:
        restrictions.append("managed_issue")
    status_risk = status_risk_codes.get(status_code)
    if status_risk and status_risk not in restrictions:
        restrictions.append(status_risk)
    vi = vi_status if isinstance(vi_status, dict) else {"available": False, "active": False}
    return {
        "checkedAt": int(time.time()),
        "available": bool(status_code) and upper_limit > 0 and lower_limit > 0,
        "statusCode": status_code,
        "tradable": bool(status_code) and status_code != "58" and not temporary_halt,
        "temporaryHalt": temporary_halt,
        "viAvailable": bool(vi.get("available")),
        "viActive": bool(vi.get("active")),
        "viKindCode": str(vi.get("kindCode", "")),
        "upperLimit": upper_limit,
        "lowerLimit": lower_limit,
        "atUpperLimit": upper_limit > 0 and numeric(price) >= upper_limit,
        "atLowerLimit": lower_limit > 0 and numeric(price) <= lower_limit,
        "restricted": bool(restrictions),
        "restrictionReasons": restrictions,
    }


def intraday_quote(response, symbol, market, environment):
    quote = response.get("output1") or {}
    if isinstance(quote, list):
        quote = quote[0] if quote else {}
    price = numeric(quote.get("stck_prpr"))
    change = numeric(quote.get("prdy_vrss"))
    previous = numeric(quote.get("stck_prdy_clpr")) or price - change
    return {
        "status": "ok",
        "mode": "kis",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "name": quote.get("hts_kor_isnm") or SECURITIES.get((market, symbol), (symbol, 0, "KRW"))[0],
        "currency": "KRW",
        "price": price,
        "ask": numeric(quote.get("askp") or quote.get("askp1")),
        "bid": numeric(quote.get("bidp") or quote.get("bidp1")),
        "previousClose": previous,
        "change": change,
        "changePct": numeric(quote.get("prdy_ctrt")),
        "high": numeric(quote.get("stck_hgpr")),
        "low": numeric(quote.get("stck_lwpr")),
        "volume": int(numeric(quote.get("acml_vol"))),
        "updatedAt": int(time.time()),
    }


def kis_orderbook(symbol, market, environment):
    if market != "KRX":
        raise StockServiceError("KIS live data currently supports KRX symbols only")
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("KRX symbols must contain six digits")
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/quotations/inquire-asking-price-exp-ccn",
        "FHKST01010200",
        {"FID_COND_MRKT_DIV_CODE": "J", "FID_INPUT_ISCD": symbol},
    )
    orderbook = response.get("output1") or {}
    time_text = str(orderbook.get("aspr_acpt_hour", "")).strip()[:6]
    updated_at = 0
    if len(time_text) == 6:
        try:
            moment = datetime.now(KRX_TIMEZONE)
            updated_at = int(datetime.combine(
                moment.date(),
                datetime.strptime(time_text, "%H%M%S").time(),
                tzinfo=KRX_TIMEZONE,
            ).timestamp())
        except ValueError:
            updated_at = 0
    return {
        "ask": numeric(orderbook.get("askp1")),
        "bid": numeric(orderbook.get("bidp1")),
        "askQuantity": int(numeric(orderbook.get("askp_rsqn1"))),
        "bidQuantity": int(numeric(orderbook.get("bidp_rsqn1"))),
        "orderbookUpdatedAt": updated_at,
        "orderbookTime": time_text,
    }


def kis_quote(symbol, market, environment, include_orderbook=False, include_vi=False):
    if market != "KRX":
        return kis_overseas_quote(symbol, market, environment, include_orderbook)
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("KRX symbols must contain six digits")
    quote_response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/quotations/inquire-price",
        "FHKST01010100",
        {"FID_COND_MRKT_DIV_CODE": "J", "FID_INPUT_ISCD": symbol},
    )
    quote = quote_response.get("output") or {}
    price = numeric(quote.get("stck_prpr"))
    change = numeric(quote.get("prdy_vrss"))
    previous = price - change
    received_at = int(time.time())
    source_updated_at = 0
    business_date = str(quote.get("stck_bsop_date", "")).strip()
    trade_time = str(
        quote.get("stck_cntg_hour")
        or quote.get("stck_prpr_hour")
        or "",
    ).strip()[:6]
    if len(business_date) == 8 and len(trade_time) == 6:
        try:
            source_updated_at = int(datetime.strptime(
                business_date + trade_time,
                "%Y%m%d%H%M%S",
            ).replace(tzinfo=KRX_TIMEZONE).timestamp())
        except ValueError:
            source_updated_at = 0
    result = {
        "status": "ok",
        "mode": "kis",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "name": quote.get("hts_kor_isnm") or SECURITIES.get((market, symbol), (symbol, 0, "KRW"))[0],
        "currency": "KRW",
        "price": price,
        "ask": numeric(quote.get("askp") or quote.get("askp1")),
        "bid": numeric(quote.get("bidp") or quote.get("bidp1")),
        "previousClose": previous,
        "change": change,
        "changePct": numeric(quote.get("prdy_ctrt")),
        "high": numeric(quote.get("stck_hgpr")),
        "low": numeric(quote.get("stck_lwpr")),
        "volume": int(numeric(quote.get("acml_vol"))),
        "receivedAt": received_at,
        "sourceUpdatedAt": source_updated_at,
        "updatedAt": received_at,
    }
    if include_orderbook:
        result.update(kis_orderbook(symbol, market, environment))
        if source_updated_at <= 0:
            result["sourceUpdatedAt"] = int(numeric(
                result.get("orderbookUpdatedAt"),
            ))
    vi_status = None
    if include_vi:
        try:
            vi_status = kis_vi_status(symbol, environment)
        except StockServiceError as error:
            vi_status = {"available": False, "active": False, "message": str(error)}
    result["marketSafety"] = quote_market_safety(quote, result["price"], vi_status)
    return result


def kis_snapshot(symbol, market, period, environment):
    if market != "KRX":
        result = kis_overseas_quote(symbol, market, environment)
        price = result["price"]
        previous = result["previousClose"]
        points = (
            overseas_intraday_points(environment, symbol, market, period)
            if period in ("30M", "1D")
            else overseas_history_points(environment, symbol, market, {"1W": 10, "1M": 35, "3M": 90}.get(period, 35))
        )
        if len(points) < 2:
            points = [
                {"t": int(time.time()) - (60 if period in ("30M", "1D") else 86400), "v": previous or price},
                {"t": int(time.time()), "v": price},
            ]
        values = [point["v"] for point in points]
        result.update({
            "range": period,
            "high": result["high"] or max(values),
            "low": result["low"] or min(values),
            "buyingPower": 0,
            "points": points,
        })
        return result
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("KRX symbols must contain six digits")
    intraday = period in ("30M", "1D")
    response = intraday_response(environment, symbol) if intraday else None
    result = kis_quote(symbol, market, environment, include_vi=True)
    price = result["price"]
    previous = result["previousClose"]
    points = intraday_points(response) if intraday else daily_points(environment, symbol, period)
    point_limits = {"30M": 30}
    if period in point_limits and len(points) > point_limits[period]:
        points = points[-point_limits[period]:]
    if len(points) < 2:
        points = [
            {"t": int(time.time()) - (1 if intraday else 86400), "v": price or previous},
            {"t": int(time.time()), "v": price},
        ]
    values = [point["v"] for point in points]
    result.update({
        "range": period,
        "high": result["high"] or max(values),
        "low": result["low"] or min(values),
        "buyingPower": 0,
        "points": points,
    })
    return result
