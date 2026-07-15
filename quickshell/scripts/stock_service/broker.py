from .core import *

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
    token = secret_lookup(f"kis_{env}_access_token")
    expiry_raw = secret_lookup(f"kis_{env}_token_expiry")
    try:
        expiry = float(expiry_raw)
    except ValueError:
        expiry = 0
    if token and expiry > time.time() + 90:
        return base_url, app_key, app_secret, token
    response = http_json(
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
    approval = secret_lookup(f"kis_{env}_ws_approval")
    expiry_raw = secret_lookup(f"kis_{env}_ws_expiry")
    try:
        expiry = float(expiry_raw)
    except ValueError:
        expiry = 0
    if approval and expiry > time.time() + 90:
        return env, approval
    response = http_json(
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
    response = http_json(
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
    base_url, app_key, app_secret, token = kis_token(environment)
    response = http_json(
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
    if str(response.get("rt_cd", "0")) != "0":
        raise StockServiceError(response.get("msg1") or "KIS returned an error")
    return response


def kis_account_parts(environment):
    env = "paper" if environment == "paper" else "prod"
    account = re.sub(r"[^0-9]", "", secret_lookup(f"kis_{env}_account"))
    if len(account) != 10:
        raise StockServiceError(f"KIS {env} account is not saved")
    return account[:8], account[8:]


def daily_points(environment, symbol, period):
    end = datetime.now()
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
            "FID_ORG_ADJ_PRC": "0",
        },
    )
    points = []
    for row in reversed(response.get("output2") or []):
        date_text = str(row.get("stck_bsop_date", ""))
        value = numeric(row.get("stck_clpr"))
        if len(date_text) == 8 and value > 0:
            stamp = int(datetime.strptime(date_text, "%Y%m%d").timestamp())
            points.append({"t": stamp, "v": value})
    return points


def intraday_points(environment, symbol):
    now = datetime.now()
    response = kis_get(
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
    points = []
    for row in reversed(response.get("output2") or []):
        time_text = str(row.get("stck_cntg_hour", ""))
        value = numeric(row.get("stck_prpr"))
        if len(time_text) == 6 and value > 0:
            point_time = datetime.combine(now.date(), datetime.strptime(time_text, "%H%M%S").time())
            points.append({"t": int(point_time.timestamp()), "v": value})
    return points


def kis_quote(symbol, market, environment):
    if market != "KRX":
        raise StockServiceError("KIS live data currently supports KRX symbols only")
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
    return {
        "status": "ok",
        "mode": "kis",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "name": quote.get("hts_kor_isnm") or SECURITIES.get((market, symbol), (symbol, 0, "KRW"))[0],
        "currency": "KRW",
        "price": price,
        "previousClose": previous,
        "change": change,
        "changePct": numeric(quote.get("prdy_ctrt")),
        "high": numeric(quote.get("stck_hgpr")),
        "low": numeric(quote.get("stck_lwpr")),
        "volume": int(numeric(quote.get("acml_vol"))),
        "updatedAt": int(time.time()),
    }


def kis_snapshot(symbol, market, period, environment):
    result = kis_quote(symbol, market, environment)
    price = result["price"]
    previous = result["previousClose"]
    points = intraday_points(environment, symbol) if period == "1D" else daily_points(environment, symbol, period)
    if len(points) < 2:
        points = [
            {"t": int(time.time()) - 86400, "v": previous or price},
            {"t": int(time.time()), "v": price},
        ]
    values = [point["v"] for point in points]
    result.update({
        "high": result["high"] or max(values),
        "low": result["low"] or min(values),
        "buyingPower": 0,
        "points": points,
    })
    return result
