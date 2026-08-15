from .broker import *
from zoneinfo import ZoneInfo


KIS_RECONCILIATION_GRACE_SECONDS = 120
KIS_RECONCILIATION_LOOKBACK_DAYS = 7
KIS_ORDER_TIMEZONE = ZoneInfo("Asia/Seoul")


def overseas_price_text(value):
    return f"{max(0, numeric(value)):.8f}".rstrip("0").rstrip(".") or "0"


def overseas_balance_exchange(environment, market, codes):
    if environment == "prod" and market == "NASDAQ":
        return "NAS"
    return codes["order"]


def validate_account_market(account, market):
    expected_currency = "KRW" if market == "KRX" else "USD"
    account_market = str(account.get("market", market)).strip().upper()
    currency = str(account.get("currency") or expected_currency).strip().upper()
    if account_market != market:
        raise StockServiceError("The KIS account snapshot belongs to a different market")
    if currency != expected_currency:
        raise StockServiceError("The KIS account currency does not match the selected market")


def kis_overseas_account_summary(environment, symbol, order_price, market):
    market, codes = overseas_market_codes(market)
    cano, product = kis_account_parts(environment)
    balance = kis_get(
        environment,
        "/uapi/overseas-stock/v1/trading/inquire-balance",
        "VTTS3012R" if environment == "paper" else "TTTS3012R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "OVRS_EXCG_CD": overseas_balance_exchange(environment, market, codes),
            "TR_CRCY_CD": codes["currency"],
            "CTX_AREA_FK200": "",
            "CTX_AREA_NK200": "",
        },
    )
    holdings = []
    balance_rows = balance.get("output1") or []
    if isinstance(balance_rows, dict):
        balance_rows = [balance_rows]
    for row in balance_rows:
        quantity = int(numeric(row.get("ovrs_cblc_qty")))
        if quantity <= 0:
            continue
        holding_market = internal_overseas_market(row.get("ovrs_excg_cd"), market)
        if holding_market != market:
            continue
        holdings.append({
            "symbol": str(row.get("ovrs_pdno", "")),
            "market": holding_market,
            "currency": str(row.get("tr_crcy_cd") or codes["currency"]),
            "name": str(row.get("ovrs_item_name") or row.get("ovrs_pdno", "")),
            "quantity": quantity,
            "sellableQuantity": int(numeric(row.get("ord_psbl_qty"))),
            "averagePrice": numeric(row.get("pchs_avg_pric")),
            "price": numeric(row.get("now_pric2")),
            "evaluation": numeric(row.get("ovrs_stck_evlu_amt")),
            "profitLoss": numeric(row.get("frcr_evlu_pfls_amt")),
            "profitRate": numeric(row.get("evlu_pfls_rt")),
        })
    summary = balance.get("output2") or {}
    if isinstance(summary, list):
        summary = summary[0] if summary else {}
    available_cash = 0
    buying_quantity = 0
    exchange_rate = 0
    if symbol and numeric(order_price) > 0:
        possible = kis_get(
            environment,
            "/uapi/overseas-stock/v1/trading/inquire-psamount",
            "VTTS3007R" if environment == "paper" else "TTTS3007R",
            {
                "CANO": cano,
                "ACNT_PRDT_CD": product,
                "OVRS_EXCG_CD": codes["order"],
                "OVRS_ORD_UNPR": overseas_price_text(order_price),
                "ITEM_CD": symbol,
            },
        ).get("output") or {}
        if isinstance(possible, list):
            possible = possible[0] if possible else {}
        available_cash = numeric(
            possible.get("ord_psbl_frcr_amt")
            or possible.get("frcr_ord_psbl_amt1")
            or possible.get("ovrs_ord_psbl_amt")
        )
        buying_quantity = int(numeric(
            possible.get("max_ord_psbl_qty")
            or possible.get("ovrs_max_ord_psbl_qty")
            or possible.get("ord_psbl_qty")
        ))
        exchange_rate = numeric(possible.get("exrt"))
    current = next((holding for holding in holdings if holding["symbol"] == symbol), {})
    holdings.sort(key=lambda holding: holding["evaluation"], reverse=True)
    stock_evaluation = numeric(summary.get("ovrs_stck_evlu_amt"), sum(item["evaluation"] for item in holdings))
    profit_loss = numeric(summary.get("tot_evlu_pfls_amt"), sum(item["profitLoss"] for item in holdings))
    invested = stock_evaluation - profit_loss
    return {
        "status": "ok",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "currency": codes["currency"],
        "cash": available_cash,
        "buyingPower": available_cash,
        "buyingQuantity": buying_quantity,
        "holdingQuantity": current.get("quantity", 0),
        "sellableQuantity": current.get("sellableQuantity", 0),
        "totalEvaluation": stock_evaluation + available_cash,
        "stockEvaluation": stock_evaluation,
        "profitLoss": profit_loss,
        "profitRate": numeric(summary.get("tot_pftrt"), round(profit_loss / invested * 100, 2) if invested > 0 else 0),
        "exchangeRate": exchange_rate,
        "holdings": holdings,
        "updatedAt": int(time.time()),
    }


def kis_account_summary(environment, symbol="", order_price=0, order_type="market", market="KRX"):
    market = str(market or "KRX").strip().upper()
    if market != "KRX":
        return kis_overseas_account_summary(environment, symbol, order_price, market)
    cano, product = kis_account_parts(environment)
    balance = kis_get(
        environment,
        "/uapi/domestic-stock/v1/trading/inquire-balance",
        "VTTC8434R" if environment == "paper" else "TTTC8434R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "AFHR_FLPR_YN": "N",
            "OFL_YN": "",
            "INQR_DVSN": "02",
            "UNPR_DVSN": "01",
            "FUND_STTL_ICLD_YN": "N",
            "FNCG_AMT_AUTO_RDPT_YN": "N",
            "PRCS_DVSN": "00",
            "CTX_AREA_FK100": "",
            "CTX_AREA_NK100": "",
        },
    )
    holdings = []
    for row in balance.get("output1") or []:
        quantity = int(numeric(row.get("hldg_qty")))
        if quantity <= 0:
            continue
        holdings.append({
            "symbol": str(row.get("pdno", "")),
            "name": str(row.get("prdt_name", "")),
            "quantity": quantity,
            "sellableQuantity": int(numeric(row.get("ord_psbl_qty"))),
            "averagePrice": numeric(row.get("pchs_avg_pric")),
            "price": numeric(row.get("prpr")),
            "evaluation": numeric(row.get("evlu_amt")),
            "profitLoss": numeric(row.get("evlu_pfls_amt")),
            "profitRate": numeric(row.get("evlu_pfls_rt")),
        })
    summary = balance.get("output2") or {}
    if isinstance(summary, list):
        summary = summary[0] if summary else {}
    cash = numeric(summary.get("dnca_tot_amt") or summary.get("nxdy_excc_amt"))
    available_cash = cash
    buying_quantity = 0
    if symbol.isdigit() and len(symbol) == 6 and numeric(order_price) > 0:
        possible = kis_get(
            environment,
            "/uapi/domestic-stock/v1/trading/inquire-psbl-order",
            "VTTC8908R" if environment == "paper" else "TTTC8908R",
            {
                "CANO": cano,
                "ACNT_PRDT_CD": product,
                "PDNO": symbol,
                "ORD_UNPR": str(max(0, int(numeric(order_price)))),
                "ORD_DVSN": "01" if order_type == "market" else "00",
                "CMA_EVLU_AMT_ICLD_YN": "N",
                "OVRS_ICLD_YN": "N",
            },
        ).get("output") or {}
        available_cash = numeric(possible.get("nrcvb_buy_amt"), available_cash)
        buying_quantity = int(numeric(possible.get("nrcvb_buy_qty")))
    current = next((holding for holding in holdings if holding["symbol"] == symbol), {})
    holdings.sort(key=lambda holding: holding["evaluation"], reverse=True)
    stock_evaluation = numeric(summary.get("scts_evlu_amt"))
    profit_loss = numeric(summary.get("evlu_pfls_smtl_amt"))
    invested = stock_evaluation - profit_loss
    return {
        "status": "ok",
        "environment": environment,
        "symbol": symbol,
        "market": "KRX",
        "currency": "KRW",
        "cash": cash,
        "buyingPower": available_cash,
        "buyingQuantity": buying_quantity,
        "holdingQuantity": current.get("quantity", 0),
        "sellableQuantity": current.get("sellableQuantity", 0),
        "totalEvaluation": numeric(summary.get("tot_evlu_amt")),
        "stockEvaluation": stock_evaluation,
        "profitLoss": profit_loss,
        "profitRate": round(profit_loss / invested * 100, 2) if invested > 0 else 0,
        "holdings": holdings,
        "updatedAt": int(time.time()),
    }


def enforce_production_risk(side, symbol, quantity, price, account, market="KRX"):
    policy = load_risk_policy()
    if not policy["productionEnabled"]:
        raise StockServiceError("Production trading is locked by the global risk policy")
    local_notional = quantity * price
    exchange_rate = 1 if market == "KRX" else numeric(account.get("exchangeRate"))
    if market != "KRX" and exchange_rate <= 0:
        raise StockServiceError("The USD/KRW exchange rate is unavailable for the production risk check")
    notional_krw = int(round(local_notional * exchange_rate))
    if notional_krw <= 0:
        raise StockServiceError("Estimated order value is unavailable")
    if notional_krw > policy["maxOrderValueKrw"]:
        raise StockServiceError("Order exceeds the configured per-order value limit")
    buy_count, daily_buy_value = production_buy_usage()
    total_evaluation = numeric(account.get("totalEvaluation"))
    current = next((holding for holding in account.get("holdings", []) if holding.get("symbol") == symbol), {})
    current_value = numeric(current.get("evaluation"))
    if side == "buy":
        if buy_count >= policy["maxBuyOrdersPerDay"]:
            raise StockServiceError("Daily production buy order count limit reached")
        if daily_buy_value + notional_krw > policy["maxDailyBuyValueKrw"]:
            raise StockServiceError("Order exceeds the configured daily production buy value")
        if total_evaluation <= 0:
            raise StockServiceError("Account evaluation is unavailable for the position limit check")
        projected_value = current_value + local_notional
        projected_percent = projected_value / total_evaluation * 100
        if projected_percent > policy["maxPositionPercent"]:
            raise StockServiceError("Order exceeds the configured position concentration limit")
    else:
        projected_percent = max(0, current_value - local_notional) / total_evaluation * 100 if total_evaluation > 0 else 0
    return {
        "estimatedNotional": local_notional,
        "estimatedNotionalKrw": notional_krw,
        "exchangeRate": exchange_rate,
        "dailyBuyOrders": buy_count,
        "dailyBuyValueKrw": daily_buy_value,
        "projectedPositionPercent": round(projected_percent, 2),
        "policy": policy,
    }


def parse_order_request(environment, request):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported trading environment")
    symbol = str(request.get("symbol", "")).strip().upper()
    market = str(request.get("market", "KRX")).strip().upper()
    side = str(request.get("side", ""))
    order_type = str(request.get("orderType", ""))
    quantity = int(numeric(request.get("quantity")))
    price = numeric(request.get("price"))
    if market == "KRX":
        if not symbol.isdigit() or len(symbol) != 6:
            raise StockServiceError("KRX symbols must contain six digits")
    else:
        overseas_market_codes(market)
        if not re.fullmatch(r"[A-Z0-9.-]{1,16}", symbol):
            raise StockServiceError("Overseas symbol is invalid")
    if side not in ("buy", "sell"):
        raise StockServiceError("Order side must be buy or sell")
    if order_type not in ("market", "limit"):
        raise StockServiceError("Order type must be market or limit")
    if market != "KRX" and order_type != "limit":
        raise StockServiceError("KIS overseas orders require a limit price")
    if quantity < 1 or quantity > 999999:
        raise StockServiceError("Order quantity is invalid")
    if order_type == "limit" and price <= 0:
        raise StockServiceError("Limit price is required")
    if price <= 0:
        raise StockServiceError("Estimated order price is unavailable")
    return symbol, market, side, order_type, quantity, price


def kis_order_preflight(environment, request):
    symbol, market, side, order_type, quantity, price = parse_order_request(environment, request)
    guard = production_order_lock() if environment == "prod" else nullcontext()
    with guard:
        account = kis_account_summary(environment, symbol, price, order_type, market)
        validate_account_market(account, market)
        available_quantity = int(account["buyingQuantity"] if side == "buy" else account["sellableQuantity"])
        if quantity > available_quantity:
            label = "buy" if side == "buy" else "sell"
            raise StockServiceError(f"Order exceeds the available {label} quantity")
        notional = quantity * price
        exchange_rate = 1 if market == "KRX" else numeric(account.get("exchangeRate"))
        if market != "KRX" and exchange_rate <= 0:
            raise StockServiceError("The USD/KRW exchange rate is unavailable for the order risk check")
        if environment == "prod":
            risk = enforce_production_risk(side, symbol, quantity, price, account, market)
        else:
            current = next((holding for holding in account.get("holdings", []) if holding.get("symbol") == symbol), {})
            total_evaluation = numeric(account.get("totalEvaluation"))
            projected_value = numeric(current.get("evaluation")) + (notional if side == "buy" else -notional)
            risk = {
                "estimatedNotional": notional,
                "estimatedNotionalKrw": int(round(notional * exchange_rate)),
                "exchangeRate": exchange_rate,
                "dailyBuyOrders": 0,
                "dailyBuyValueKrw": 0,
                "projectedPositionPercent": (
                    round(max(0, projected_value) / total_evaluation * 100, 2)
                    if total_evaluation > 0
                    else 0
                ),
                "policy": None,
            }
        return {
            "status": "ok",
            "environment": environment,
            "symbol": symbol,
            "market": market,
            "currency": account.get("currency", "KRW" if market == "KRX" else "USD"),
            "side": side,
            "orderType": order_type,
            "quantity": quantity,
            "price": price,
            "availableQuantity": available_quantity,
            "buyingPower": numeric(account.get("buyingPower")),
            "sellableQuantity": int(numeric(account.get("sellableQuantity"))),
            "holdingQuantity": int(numeric(account.get("holdingQuantity"))),
            "risk": risk,
            "checkedAt": int(time.time()),
        }


def kis_order(environment, request):
    if environment == "prod" and str(request.get("confirmation", "")) != "LIVE":
        raise StockServiceError("Production orders require the LIVE confirmation")
    symbol, market, side, order_type, quantity, price = parse_order_request(environment, request)
    guard = production_order_lock() if environment == "prod" else nullcontext()
    with guard:
        account = kis_account_summary(environment, symbol, price, order_type, market)
        validate_account_market(account, market)
        available_quantity = int(account["buyingQuantity"] if side == "buy" else account["sellableQuantity"])
        if quantity > available_quantity:
            label = "buy" if side == "buy" else "sell"
            raise StockServiceError(f"Order exceeds the available {label} quantity")
        if environment == "prod":
            risk = enforce_production_risk(side, symbol, quantity, price, account, market)
        else:
            exchange_rate = 1 if market == "KRX" else numeric(account.get("exchangeRate"))
            if market != "KRX" and exchange_rate <= 0:
                raise StockServiceError(
                    "The USD/KRW exchange rate is unavailable for the order risk check",
                )
            estimated_notional = quantity * price
            risk = {
                "estimatedNotional": estimated_notional,
                "estimatedNotionalKrw": int(round(estimated_notional * exchange_rate)),
                "exchangeRate": exchange_rate,
                "policy": None,
            }
        cano, product = kis_account_parts(environment)
        if market == "KRX":
            if environment == "paper":
                transaction_id = "VTTC0012U" if side == "buy" else "VTTC0011U"
            else:
                transaction_id = "TTTC0012U" if side == "buy" else "TTTC0011U"
            path = "/uapi/domestic-stock/v1/trading/order-cash"
            payload = {
                "CANO": cano,
                "ACNT_PRDT_CD": product,
                "PDNO": symbol,
                "ORD_DVSN": "01" if order_type == "market" else "00",
                "ORD_QTY": str(quantity),
                "ORD_UNPR": "0" if order_type == "market" else str(int(price)),
                "EXCG_ID_DVSN_CD": "KRX",
                "SLL_TYPE": "01" if side == "sell" else "",
                "CNDT_PRIC": "",
            }
        else:
            _, codes = overseas_market_codes(market)
            transaction_id = (
                "VTTT1002U" if side == "buy" else "VTTT1001U"
            ) if environment == "paper" else (
                "TTTT1002U" if side == "buy" else "TTTT1006U"
            )
            path = "/uapi/overseas-stock/v1/trading/order"
            payload = {
                "CANO": cano,
                "ACNT_PRDT_CD": product,
                "OVRS_EXCG_CD": codes["order"],
                "PDNO": symbol,
                "ORD_QTY": str(quantity),
                "OVRS_ORD_UNPR": overseas_price_text(price),
                "CTAC_TLNO": "",
                "MGCO_APTM_ODNO": "",
                "SLL_TYPE": "" if side == "buy" else "00",
                "ORD_SVR_DVSN_CD": "0",
                "ORD_DVSN": "00",
            }
        audit = {
            "requestId": str(request.get("requestId") or os.urandom(8).hex()),
            "action": "order",
            "environment": environment,
            "market": market,
            "currency": account.get("currency", "KRW" if market == "KRX" else "USD"),
            "side": side,
            "symbol": symbol,
            "quantity": quantity,
            "orderType": order_type,
            "price": price if order_type == "limit" else 0,
            "estimatedNotional": risk["estimatedNotional"],
            "estimatedNotionalKrw": risk.get("estimatedNotionalKrw", risk["estimatedNotional"]),
        }
        if request.get("automationPlanId"):
            audit["automationPlanId"] = str(request["automationPlanId"])
        trade_audit(dict(audit, status="submitting"))
        try:
            response = kis_post(environment, path, transaction_id, payload)
        except StockServiceError as error:
            try:
                trade_audit(dict(audit, status="failed", message=str(error)))
            except OSError:
                pass
            raise
        output = response.get("output") or {}
        result = {
            "status": "ok",
            "mode": environment,
            "side": side,
            "symbol": symbol,
            "market": market,
            "currency": account.get("currency", "KRW" if market == "KRX" else "USD"),
            "quantity": quantity,
            "orderType": order_type,
            "price": price if order_type == "limit" else 0,
            "orderNumber": str(output.get("ODNO", "")),
            "organizationNumber": str(output.get("KRX_FWDG_ORD_ORGNO", "")),
            "orderTime": str(output.get("ORD_TMD", "")),
            "message": response.get("msg1") or (
                "Paper order accepted"
                if environment == "paper"
                else "Production order accepted"
            ),
            "submittedAt": int(time.time()),
            "risk": risk,
        }
        try:
            trade_audit(dict(audit, status="accepted", orderNumber=result["orderNumber"]))
            result["auditLogged"] = True
        except OSError:
            result["auditLogged"] = False
        return result


def kis_paper_order(request):
    return kis_order("paper", request)


def kis_paper_cancelable_orders():
    # KIS paper accounts reject inquire-psbl-rvsecncl ("없는 서비스 코드");
    # TTTC0084R is production-only, so derive open orders from today's
    # daily order inquiry instead.
    cano, product = kis_account_parts("paper")
    today = datetime.now(KIS_ORDER_TIMEZONE).strftime("%Y%m%d")
    response = kis_get(
        "paper",
        "/uapi/domestic-stock/v1/trading/inquire-daily-ccld",
        "VTTC0081R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "INQR_STRT_DT": today,
            "INQR_END_DT": today,
            "SLL_BUY_DVSN_CD": "00",
            "PDNO": "",
            "CCLD_DVSN": "00",
            "INQR_DVSN": "00",
            "INQR_DVSN_3": "00",
            "ORD_GNO_BRNO": "",
            "ODNO": "",
            "INQR_DVSN_1": "",
            "CTX_AREA_FK100": "",
            "CTX_AREA_NK100": "",
            "EXCG_ID_DVSN_CD": "KRX",
        },
    )
    rows = []
    for row in response.get("output1") or []:
        remaining = int(numeric(row.get("rmn_qty")))
        canceled = int(numeric(row.get("cncl_cfrm_qty"))) > 0 or str(row.get("cncl_yn", "")).upper() == "Y"
        if remaining <= 0 or canceled or int(numeric(row.get("rjct_qty"))) > 0:
            continue
        rows.append({
            "odno": str(row.get("odno", "")),
            "pdno": str(row.get("pdno", "")),
            "psbl_qty": str(remaining),
            "krx_fwdg_ord_orgno": str(row.get("krx_fwdg_ord_orgno") or row.get("ord_gno_brno") or ""),
            "ord_gno_brno": str(row.get("ord_gno_brno") or ""),
            "ord_dvsn_cd": str(row.get("ord_dvsn_cd") or "00"),
        })
    return rows


def kis_cancelable_orders(environment):
    if environment == "paper":
        return kis_paper_cancelable_orders()
    cano, product = kis_account_parts(environment)
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/trading/inquire-psbl-rvsecncl",
        "TTTC0084R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "INQR_DVSN_1": "0",
            "INQR_DVSN_2": "0",
            "CTX_AREA_FK100": "",
            "CTX_AREA_NK100": "",
        },
    )
    return response.get("output") or []


def kis_order_timestamp(date, value):
    digits = "".join(character for character in str(value) if character.isdigit())[:6]
    date_digits = "".join(character for character in str(date) if character.isdigit())[:8]
    if len(date_digits) != 8 or len(digits) < 4:
        return 0
    digits = digits.ljust(6, "0")
    try:
        moment = datetime.strptime(date_digits + digits, "%Y%m%d%H%M%S").replace(tzinfo=KIS_ORDER_TIMEZONE)
    except ValueError:
        return 0
    return int(moment.timestamp())


def kis_overseas_order_history(environment, symbol, limit, days, market):
    market, codes = overseas_market_codes(market)
    cano, product = kis_account_parts(environment)
    end = datetime.now(codes["timezone"])
    start = end - timedelta(days=days)
    response = kis_get(
        environment,
        "/uapi/overseas-stock/v1/trading/inquire-ccnl",
        "VTTS3035R" if environment == "paper" else "TTTS3035R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "PDNO": "" if environment == "paper" else (symbol or "%"),
            "ORD_STRT_DT": start.strftime("%Y%m%d"),
            "ORD_END_DT": end.strftime("%Y%m%d"),
            "SLL_BUY_DVSN": "00",
            "CCLD_NCCS_DVSN": "00",
            "OVRS_EXCG_CD": "" if environment == "paper" else codes["order"],
            "SORT_SQN": "DS",
            "ORD_DT": "",
            "ORD_GNO_BRNO": "",
            "ODNO": "",
            "CTX_AREA_NK200": "",
            "CTX_AREA_FK200": "",
        },
    )
    rows = response.get("output") or []
    if isinstance(rows, dict):
        rows = [rows]
    orders = []
    for row in rows:
        row_symbol = str(row.get("pdno", "")).strip().upper()
        row_market = internal_overseas_market(row.get("ovrs_excg_cd"), market)
        if symbol and row_symbol != symbol:
            continue
        if row_market != market and str(row.get("ovrs_excg_cd", "")).strip():
            continue
        quantity = int(numeric(row.get("ft_ord_qty")))
        filled = int(numeric(row.get("ft_ccld_qty")))
        remaining = int(numeric(row.get("nccs_qty"), max(0, quantity - filled)))
        rejected = bool(str(row.get("rjct_rson") or row.get("rjct_rson_name") or "").strip())
        process_name = str(row.get("prcs_stat_name") or row.get("rvse_cncl_dvsn_name") or "")
        if rejected:
            state = "rejected"
        elif "취소" in process_name:
            state = "canceled"
        elif remaining > 0:
            state = "partial" if filled > 0 else "pending"
        elif quantity > 0 and filled >= quantity:
            state = "filled"
        else:
            state = "submitted"
        side_code = str(row.get("sll_buy_dvsn_cd", ""))
        side_name = str(row.get("sll_buy_dvsn_cd_name", ""))
        side = "sell" if side_code == "01" or "매도" in side_name else "buy"
        date_text = str(row.get("ord_dt") or row.get("dmst_ord_dt") or "")
        time_text = str(row.get("ord_tmd") or row.get("thco_ord_tmd") or "")
        timestamp = 0
        try:
            timestamp = int(datetime.strptime(date_text + time_text[:6], "%Y%m%d%H%M%S").replace(tzinfo=codes["timezone"]).timestamp())
        except ValueError:
            pass
        average_price = numeric(row.get("ft_ccld_unpr3"))
        orders.append({
            "orderNumber": str(row.get("odno", "")),
            "organizationNumber": str(row.get("ord_gno_brno", "")),
            "originalOrderNumber": str(row.get("orgn_odno", "")),
            "symbol": row_symbol,
            "market": market,
            "currency": str(row.get("tr_crcy_cd") or codes["currency"]),
            "name": str(row.get("prdt_name") or row_symbol),
            "side": side,
            "orderType": "limit",
            "orderTypeCode": "00",
            "quantity": quantity,
            "filledQuantity": filled,
            "remainingQuantity": remaining,
            "cancelQuantity": remaining,
            "price": numeric(row.get("ft_ord_unpr3")),
            "averagePrice": average_price,
            "filledNotional": numeric(row.get("ft_ccld_amt3"), average_price * filled),
            "commission": 0,
            "tax": 0,
            "settlementAmount": numeric(row.get("ft_ccld_amt3")),
            "costSource": "estimated",
            "state": state,
            "canCancel": remaining > 0 and not rejected,
            "date": date_text,
            "time": time_text,
            "timestamp": timestamp,
        })
    orders.sort(key=lambda order: order["date"] + order["time"] + order["orderNumber"], reverse=True)
    return {
        "status": "ok",
        "environment": environment,
        "symbol": symbol,
        "market": market,
        "currency": codes["currency"],
        "orders": orders[:limit],
        "pendingCount": sum(1 for order in orders if order["canCancel"]),
        "updatedAt": int(time.time()),
    }


def kis_order_history(environment, symbol="", limit=8, days=KIS_RECONCILIATION_LOOKBACK_DAYS, market="KRX"):
    market = str(market or "KRX").strip().upper()
    if market != "KRX":
        try:
            limit = max(1, min(200, int(limit)))
            days = max(1, min(30, int(days)))
        except (TypeError, ValueError) as error:
            raise StockServiceError("Order history range is invalid") from error
        return kis_overseas_order_history(environment, str(symbol or "").strip().upper(), limit, days, market)
    cano, product = kis_account_parts(environment)
    try:
        limit = max(1, min(200, int(limit)))
        days = max(1, min(30, int(days)))
    except (TypeError, ValueError) as error:
        raise StockServiceError("Order history range is invalid") from error
    end = datetime.now()
    start = end - timedelta(days=days)
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/trading/inquire-daily-ccld",
        "VTTC0081R" if environment == "paper" else "TTTC0081R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "INQR_STRT_DT": start.strftime("%Y%m%d"),
            "INQR_END_DT": end.strftime("%Y%m%d"),
            "SLL_BUY_DVSN_CD": "00",
            "PDNO": symbol if symbol.isdigit() and len(symbol) == 6 else "",
            "CCLD_DVSN": "00",
            "INQR_DVSN": "00",
            "INQR_DVSN_3": "00",
            "ORD_GNO_BRNO": "",
            "ODNO": "",
            "INQR_DVSN_1": "",
            "CTX_AREA_FK100": "",
            "CTX_AREA_NK100": "",
            "EXCG_ID_DVSN_CD": "KRX",
        },
    )
    if environment == "paper":
        # Paper has no cancelable-orders service; cancelability is derived
        # from each row's remaining quantity below.
        cancelable = {}
    else:
        cancelable_rows = kis_cancelable_orders(environment)
        cancelable = {str(row.get("odno", "")): row for row in cancelable_rows if str(row.get("odno", ""))}
    orders = []
    for row in response.get("output1") or []:
        order_number = str(row.get("odno", ""))
        order_quantity = int(numeric(row.get("ord_qty")))
        filled_quantity = int(numeric(row.get("tot_ccld_qty") or row.get("ccld_qty")))
        remaining_quantity = int(numeric(row.get("rmn_qty"), max(0, order_quantity - filled_quantity)))
        cancel_row = cancelable.get(order_number)
        canceled_quantity = int(numeric(row.get("cncl_cfrm_qty")))
        rejected_quantity = int(numeric(row.get("rjct_qty")))
        if cancel_row:
            cancel_quantity = int(numeric(cancel_row.get("psbl_qty")))
        elif (
            environment == "paper"
            and remaining_quantity > 0
            and rejected_quantity == 0
            and canceled_quantity == 0
            and str(row.get("cncl_yn", "")).upper() != "Y"
        ):
            cancel_quantity = remaining_quantity
        else:
            cancel_quantity = 0
        if cancel_quantity > 0:
            state = "pending" if filled_quantity == 0 else "partial"
        elif rejected_quantity > 0:
            state = "rejected"
        elif canceled_quantity > 0 or str(row.get("cncl_yn", "")).upper() == "Y":
            state = "canceled"
        elif order_quantity > 0 and filled_quantity >= order_quantity:
            state = "filled"
        elif filled_quantity > 0:
            state = "partial"
        else:
            state = "submitted"
        side_code = str(row.get("sll_buy_dvsn_cd", ""))
        side_name = str(row.get("sll_buy_dvsn_cd_name") or row.get("sll_buy_dvsn_name") or "")
        side = "sell" if side_code == "01" or "매도" in side_name else "buy"
        organization = ""
        if cancel_row:
            organization = str(cancel_row.get("krx_fwdg_ord_orgno") or cancel_row.get("ord_gno_brno") or "")
        order_date = str(row.get("ord_dt", ""))
        order_time = str(row.get("ord_tmd", ""))
        average_price = numeric(row.get("avg_prvs"))
        filled_notional = numeric(
            row.get("tot_ccld_amt"), average_price * filled_quantity,
        )
        commission = numeric(row.get("fee") or row.get("ord_fee"))
        tax = numeric(row.get("tl_tax") or row.get("tot_tltx"))
        broker_costs = any(key in row for key in ("fee", "ord_fee", "tl_tax", "tot_tltx"))
        orders.append({
            "orderNumber": order_number,
            "organizationNumber": organization or str(row.get("krx_fwdg_ord_orgno") or row.get("ord_gno_brno") or ""),
            "originalOrderNumber": str(row.get("orgn_odno", "")),
            "symbol": str(row.get("pdno", "")),
            "market": "KRX",
            "currency": "KRW",
            "name": str(row.get("prdt_name", "")),
            "side": side,
            "orderType": str(row.get("ord_dvsn_name") or row.get("ord_dvsn_cd") or ""),
            "orderTypeCode": str(row.get("ord_dvsn_cd") or "00"),
            "quantity": order_quantity,
            "filledQuantity": filled_quantity,
            "remainingQuantity": remaining_quantity,
            "cancelQuantity": cancel_quantity,
            "price": numeric(row.get("ord_unpr")),
            "averagePrice": average_price,
            "filledNotional": filled_notional,
            "commission": commission,
            "tax": tax,
            "settlementAmount": numeric(row.get("excc_amt") or row.get("tot_excc_amt")),
            "costSource": "broker" if broker_costs else "estimated",
            "state": state,
            "canCancel": cancel_quantity > 0,
            "date": order_date,
            "time": order_time,
            "timestamp": kis_order_timestamp(order_date, order_time),
        })
    orders.sort(key=lambda order: order["date"] + order["time"] + order["orderNumber"], reverse=True)
    return {
        "status": "ok",
        "environment": environment,
        "symbol": symbol,
        "orders": orders[:limit],
        "pendingCount": sum(1 for order in orders if order["canCancel"]),
        "updatedAt": int(time.time()),
    }


def broker_order_match(event, orders, used=None):
    used = used if used is not None else set()
    order_number = str(event.get("orderNumber", ""))
    original_number = str(event.get("originalOrderNumber", ""))
    if order_number:
        for index, order in enumerate(orders):
            if (str(order.get("orderNumber", "")) == order_number
                    and str(order.get("market", "KRX")) == str(event.get("market", "KRX"))):
                return index, order, "order_number"
    if event.get("action") == "cancel" and original_number:
        for index, order in enumerate(orders):
            if (str(order.get("orderNumber", "")) == original_number
                    and str(order.get("market", "KRX")) == str(event.get("market", "KRX"))):
                return index, order, "original_order_number"
    if event.get("action") != "order" or order_number:
        return None
    timestamp = int(numeric(event.get("timestamp")))
    candidates = []
    for index, order in enumerate(orders):
        if index in used:
            continue
        if str(order.get("market", "KRX")) != str(event.get("market", "KRX")):
            continue
        if str(order.get("symbol", "")) != str(event.get("symbol", "")):
            continue
        if str(order.get("side", "")) != str(event.get("side", "")):
            continue
        if int(numeric(order.get("quantity"))) != int(numeric(event.get("quantity"))):
            continue
        broker_timestamp = int(numeric(order.get("timestamp")))
        if not timestamp or not broker_timestamp or abs(broker_timestamp - timestamp) > 600:
            continue
        candidates.append((abs(broker_timestamp - timestamp), index, order))
    if len(candidates) != 1:
        return None
    _, index, order = candidates[0]
    return index, order, "request_signature"


def reconciliation_fields(event, order, match_type, reconciled_at):
    fields = {
        "reconciliation": "matched",
        "reconciliationMatch": match_type,
        "brokerState": str(order.get("state", "submitted")),
        "filledQuantity": int(numeric(order.get("filledQuantity"))),
        "remainingQuantity": int(numeric(order.get("remainingQuantity"))),
        "cancelQuantity": int(numeric(order.get("cancelQuantity"))),
        "averagePrice": numeric(order.get("averagePrice")),
        "filledNotional": numeric(order.get("filledNotional")),
        "commission": numeric(order.get("commission")),
        "tax": numeric(order.get("tax")),
        "settlementAmount": numeric(order.get("settlementAmount")),
        "costSource": str(order.get("costSource", "estimated")),
        "reconciledAt": reconciled_at,
    }
    if not event.get("orderNumber") and order.get("orderNumber"):
        fields["orderNumber"] = str(order["orderNumber"])
    return fields


def append_reconciliation(event, fields):
    material = {key: value for key, value in fields.items() if key != "reconciledAt"}
    if all(event.get(key) == value for key, value in material.items()):
        return False
    merged = dict(event)
    merged.pop("sequence", None)
    merged.update(fields)
    trade_audit(merged)
    return True


def kis_reconcile_activity(environment, days=KIS_RECONCILIATION_LOOKBACK_DAYS):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported reconciliation environment")
    try:
        days = max(1, min(30, int(days)))
    except (TypeError, ValueError) as error:
        raise StockServiceError("Reconciliation range must be a number") from error
    now = int(time.time())
    requests = list(load_trade_requests(environment).values())
    requests.sort(key=lambda event: (int(numeric(event.get("timestamp"))), event.get("sequence", 0)), reverse=True)
    orders = []
    markets = {str(event.get("market", "KRX")).strip().upper() for event in requests} or {"KRX"}
    for market in sorted(markets):
        history = kis_order_history(environment, "", 200, days, market)
        orders.extend(history.get("orders", []))
    used = set()
    counts = {"checked": 0, "matched": 0, "unmatched": 0, "pending": 0, "updated": 0}
    cutoff = now - days * 24 * 60 * 60
    for event in requests:
        timestamp = int(numeric(event.get("timestamp")))
        if timestamp < cutoff or event.get("status") == "failed":
            continue
        counts["checked"] += 1
        match = broker_order_match(event, orders, used)
        if match:
            index, order, match_type = match
            if match_type == "request_signature":
                used.add(index)
            counts["matched"] += 1
            fields = reconciliation_fields(event, order, match_type, now)
        else:
            age = max(0, now - timestamp)
            reconciliation = "pending" if age < KIS_RECONCILIATION_GRACE_SECONDS else "unmatched"
            counts[reconciliation] += 1
            fields = {
                "reconciliation": reconciliation,
                "reconciliationMatch": "",
                "brokerState": "",
                "reconciledAt": now,
            }
        if append_reconciliation(event, fields):
            counts["updated"] += 1
    return {
        "status": "ok",
        "environment": environment,
        **counts,
        "brokerOrders": len(orders),
        "updatedAt": now,
    }


def reconciled_trade_activity(broker_environment, activity_environment="all", limit=50):
    try:
        reconciliation = kis_reconcile_activity(broker_environment)
    except Exception as error:
        reconciliation = {
            "status": "error",
            "environment": broker_environment,
            "message": str(error)[:240],
            "updatedAt": int(time.time()),
        }
    result = trade_activity(activity_environment, limit)
    result["reconciliation"] = reconciliation
    return result


def kis_period_trade_profit(environment, start_date, end_date, symbol=""):
    if environment != "prod":
        return {
            "status": "ok",
            "environment": environment,
            "exact": False,
            "rows": [],
            "totals": {},
            "message": "KIS period profit accounting is available on production accounts only",
            "updatedAt": int(time.time()),
        }
    start = "".join(character for character in str(start_date) if character.isdigit())[:8]
    end = "".join(character for character in str(end_date) if character.isdigit())[:8]
    if len(start) != 8 or len(end) != 8 or start > end:
        raise StockServiceError("Profit inquiry dates must be valid YYYYMMDD values")
    cano, product = kis_account_parts(environment)
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/trading/inquire-period-trade-profit",
        "TTTC8715R",
        {
            "CANO": cano,
            "ACNT_PRDT_CD": product,
            "SORT_DVSN": "02",
            "INQR_STRT_DT": start,
            "INQR_END_DT": end,
            "SLL_BUY_DVSN_CD": "00",
            "PDNO": symbol if symbol.isdigit() and len(symbol) == 6 else "",
            "CBLC_DVSN": "00",
            "INQR_DVSN": "00",
            "PNL_INQR_DVSN": "0",
            "PRCS_DVSN": "00",
            "CTX_AREA_FK100": "",
            "CTX_AREA_NK100": "",
        },
    )
    rows = []
    for row in response.get("output1") or []:
        rows.append({
            "date": str(row.get("trad_dt", "")),
            "symbol": str(row.get("pdno", "")),
            "name": str(row.get("prdt_name", "")),
            "buyQuantity": int(numeric(row.get("buy_qty"))),
            "buyAmount": numeric(row.get("buy_amt")),
            "sellQuantity": int(numeric(row.get("sll_qty"))),
            "sellAmount": numeric(row.get("sll_amt")),
            "sellPrice": numeric(row.get("sll_pric")),
            "realizedProfitLoss": numeric(row.get("rlzt_pfls")),
            "profitRate": numeric(row.get("pfls_rt")),
            "fee": numeric(row.get("fee")),
            "tax": numeric(row.get("tl_tax")),
            "loanInterest": numeric(row.get("loan_int")),
        })
    totals_row = response.get("output2") or {}
    if isinstance(totals_row, list):
        totals_row = totals_row[0] if totals_row else {}
    totals = {
        "sellFee": numeric(totals_row.get("sll_fee_smtl")),
        "sellTax": numeric(totals_row.get("sll_tltx_smtl")),
        "buyFee": numeric(totals_row.get("buy_fee_smtl")),
        "buyTax": numeric(totals_row.get("buy_tax_smtl")),
        "tradeAmount": numeric(totals_row.get("tot_tr_amt")),
        "fee": numeric(totals_row.get("tot_fee")),
        "tax": numeric(totals_row.get("tot_tltx")),
        "settlementAmount": numeric(totals_row.get("tot_excc_amt")),
        "realizedProfitLoss": numeric(totals_row.get("tot_rlzt_pfls")),
        "profitRate": numeric(totals_row.get("tot_pftrt")),
    }
    return {
        "status": "ok",
        "environment": environment,
        "exact": True,
        "rows": rows,
        "totals": totals,
        "updatedAt": int(time.time()),
    }


def kis_overseas_cancel(environment, request, market):
    if environment == "prod" and str(request.get("confirmation", "")) != "LIVE":
        raise StockServiceError("Production cancellations require the LIVE confirmation")
    order_number = str(request.get("orderNumber", "")).strip()
    symbol = str(request.get("symbol", "")).strip().upper()
    if not order_number or not symbol:
        raise StockServiceError("Order number and symbol are required")
    history = kis_overseas_order_history(environment, symbol, 200, KIS_RECONCILIATION_LOOKBACK_DAYS, market)
    cancelable = next((row for row in history["orders"] if row["orderNumber"] == order_number and row["canCancel"]), None)
    if not cancelable:
        raise StockServiceError("This overseas order is no longer cancelable")
    cancel_quantity = int(numeric(cancelable.get("cancelQuantity")))
    cano, product = kis_account_parts(environment)
    _, codes = overseas_market_codes(market)
    payload = {
        "CANO": cano,
        "ACNT_PRDT_CD": product,
        "OVRS_EXCG_CD": codes["order"],
        "PDNO": symbol,
        "ORGN_ODNO": order_number,
        "RVSE_CNCL_DVSN_CD": "02",
        "ORD_QTY": str(cancel_quantity),
        "OVRS_ORD_UNPR": "0",
        "MGCO_APTM_ODNO": "",
        "ORD_SVR_DVSN_CD": "0",
    }
    audit = {
        "requestId": os.urandom(8).hex(),
        "action": "cancel",
        "environment": environment,
        "market": market,
        "currency": cancelable.get("currency", "USD"),
        "symbol": symbol,
        "originalOrderNumber": order_number,
        "quantity": cancel_quantity,
    }
    trade_audit(dict(audit, status="submitting"))
    try:
        response = kis_post(
            environment,
            "/uapi/overseas-stock/v1/trading/order-rvsecncl",
            "VTTT1004U" if environment == "paper" else "TTTT1004U",
            payload,
        )
    except StockServiceError as error:
        try:
            trade_audit(dict(audit, status="failed", message=str(error)))
        except OSError:
            pass
        raise
    output = response.get("output") or {}
    result = {
        "status": "ok",
        "mode": environment,
        "market": market,
        "symbol": symbol,
        "originalOrderNumber": order_number,
        "orderNumber": str(output.get("ODNO", "")),
        "canceledQuantity": cancel_quantity,
        "message": response.get("msg1") or ("Paper order canceled" if environment == "paper" else "Production order canceled"),
        "submittedAt": int(time.time()),
    }
    try:
        trade_audit(dict(audit, status="accepted", orderNumber=result["orderNumber"]))
        result["auditLogged"] = True
    except OSError:
        result["auditLogged"] = False
    return result


def kis_cancel(environment, request):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported trading environment")
    market = str(request.get("market", "KRX")).strip().upper()
    if market != "KRX":
        overseas_market_codes(market)
        return kis_overseas_cancel(environment, request, market)
    if environment == "prod" and str(request.get("confirmation", "")) != "LIVE":
        raise StockServiceError("Production cancellations require the LIVE confirmation")
    order_number = str(request.get("orderNumber", "")).strip()
    if not order_number:
        raise StockServiceError("Order number is required")
    cancelable = next(
        (
            row
            for row in kis_cancelable_orders(environment)
            if str(row.get("odno", "")) == order_number
        ),
        None,
    )
    if not cancelable:
        raise StockServiceError("This order is no longer cancelable")
    cancel_quantity = int(numeric(cancelable.get("psbl_qty")))
    if cancel_quantity <= 0:
        raise StockServiceError("This order has no cancelable quantity")
    organization = str(cancelable.get("krx_fwdg_ord_orgno") or cancelable.get("ord_gno_brno") or "")
    if not organization:
        raise StockServiceError("KIS did not return the original order organization number")
    cano, product = kis_account_parts(environment)
    payload = {
        "CANO": cano,
        "ACNT_PRDT_CD": product,
        "KRX_FWDG_ORD_ORGNO": organization,
        "ORGN_ODNO": order_number,
        "ORD_DVSN": str(cancelable.get("ord_dvsn_cd") or "00"),
        "RVSE_CNCL_DVSN_CD": "02",
        "ORD_QTY": str(cancel_quantity),
        "ORD_UNPR": "0",
        "QTY_ALL_ORD_YN": "Y",
        "EXCG_ID_DVSN_CD": "KRX",
    }
    audit = {
        "requestId": os.urandom(8).hex(),
        "action": "cancel",
        "environment": environment,
        "originalOrderNumber": order_number,
        "quantity": cancel_quantity,
    }
    trade_audit(dict(audit, status="submitting"))
    try:
        response = kis_post(
            environment,
            "/uapi/domestic-stock/v1/trading/order-rvsecncl",
            "VTTC0013U" if environment == "paper" else "TTTC0013U",
            payload,
        )
    except StockServiceError as error:
        try:
            trade_audit(dict(audit, status="failed", message=str(error)))
        except OSError:
            pass
        raise
    output = response.get("output") or {}
    result = {
        "status": "ok",
        "mode": environment,
        "originalOrderNumber": order_number,
        "orderNumber": str(output.get("ODNO", "")),
        "canceledQuantity": cancel_quantity,
        "message": response.get("msg1") or (
            "Paper order canceled"
            if environment == "paper"
            else "Production order canceled"
        ),
        "submittedAt": int(time.time()),
    }
    try:
        trade_audit(dict(audit, status="accepted", orderNumber=result["orderNumber"]))
        result["auditLogged"] = True
    except OSError:
        result["auditLogged"] = False
    return result


def kis_paper_cancel(request):
    return kis_cancel("paper", request)
