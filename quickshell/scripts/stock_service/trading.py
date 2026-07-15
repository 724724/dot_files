from .broker import *

def kis_account_summary(environment, symbol="", order_price=0, order_type="market"):
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


def enforce_production_risk(side, symbol, quantity, price, account):
    policy = load_risk_policy()
    if not policy["productionEnabled"]:
        raise StockServiceError("Production trading is locked by the global risk policy")
    notional = int(round(quantity * price))
    if notional <= 0:
        raise StockServiceError("Estimated order value is unavailable")
    if notional > policy["maxOrderValueKrw"]:
        raise StockServiceError("Order exceeds the configured per-order value limit")
    buy_count, daily_buy_value = production_buy_usage()
    total_evaluation = numeric(account.get("totalEvaluation"))
    current = next((holding for holding in account.get("holdings", []) if holding.get("symbol") == symbol), {})
    current_value = numeric(current.get("evaluation"))
    if side == "buy":
        if buy_count >= policy["maxBuyOrdersPerDay"]:
            raise StockServiceError("Daily production buy order count limit reached")
        if daily_buy_value + notional > policy["maxDailyBuyValueKrw"]:
            raise StockServiceError("Order exceeds the configured daily production buy value")
        if total_evaluation <= 0:
            raise StockServiceError("Account evaluation is unavailable for the position limit check")
        projected_value = current_value + notional
        projected_percent = projected_value / total_evaluation * 100
        if projected_percent > policy["maxPositionPercent"]:
            raise StockServiceError("Order exceeds the configured position concentration limit")
    else:
        projected_percent = max(0, current_value - notional) / total_evaluation * 100 if total_evaluation > 0 else 0
    return {
        "estimatedNotional": notional,
        "dailyBuyOrders": buy_count,
        "dailyBuyValueKrw": daily_buy_value,
        "projectedPositionPercent": round(projected_percent, 2),
        "policy": policy,
    }


def parse_order_request(environment, request):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported trading environment")
    symbol = str(request.get("symbol", "")).strip()
    side = str(request.get("side", ""))
    order_type = str(request.get("orderType", ""))
    quantity = int(numeric(request.get("quantity")))
    price = numeric(request.get("price"))
    if not symbol.isdigit() or len(symbol) != 6:
        raise StockServiceError("Orders currently support six-digit KRX symbols only")
    if side not in ("buy", "sell"):
        raise StockServiceError("Order side must be buy or sell")
    if order_type not in ("market", "limit"):
        raise StockServiceError("Order type must be market or limit")
    if quantity < 1 or quantity > 999999:
        raise StockServiceError("Order quantity is invalid")
    if order_type == "limit" and price <= 0:
        raise StockServiceError("Limit price is required")
    if price <= 0:
        raise StockServiceError("Estimated order price is unavailable")
    return symbol, side, order_type, quantity, price


def kis_order_preflight(environment, request):
    symbol, side, order_type, quantity, price = parse_order_request(environment, request)
    guard = production_order_lock() if environment == "prod" else nullcontext()
    with guard:
        account = kis_account_summary(environment, symbol, price, order_type)
        available_quantity = int(account["buyingQuantity"] if side == "buy" else account["sellableQuantity"])
        if quantity > available_quantity:
            label = "buy" if side == "buy" else "sell"
            raise StockServiceError(f"Order exceeds the available {label} quantity")
        notional = int(round(quantity * price))
        if environment == "prod":
            risk = enforce_production_risk(side, symbol, quantity, price, account)
        else:
            current = next((holding for holding in account.get("holdings", []) if holding.get("symbol") == symbol), {})
            total_evaluation = numeric(account.get("totalEvaluation"))
            projected_value = numeric(current.get("evaluation")) + (notional if side == "buy" else -notional)
            risk = {
                "estimatedNotional": notional,
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
    symbol, side, order_type, quantity, price = parse_order_request(environment, request)
    guard = production_order_lock() if environment == "prod" else nullcontext()
    with guard:
        account = kis_account_summary(environment, symbol, price, order_type)
        available_quantity = int(account["buyingQuantity"] if side == "buy" else account["sellableQuantity"])
        if quantity > available_quantity:
            label = "buy" if side == "buy" else "sell"
            raise StockServiceError(f"Order exceeds the available {label} quantity")
        risk = enforce_production_risk(side, symbol, quantity, price, account) if environment == "prod" else {
            "estimatedNotional": int(round(quantity * price)),
            "policy": None,
        }
        cano, product = kis_account_parts(environment)
        if environment == "paper":
            transaction_id = "VTTC0012U" if side == "buy" else "VTTC0011U"
        else:
            transaction_id = "TTTC0012U" if side == "buy" else "TTTC0011U"
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
        audit = {
            "requestId": os.urandom(8).hex(),
            "action": "order",
            "environment": environment,
            "side": side,
            "symbol": symbol,
            "quantity": quantity,
            "orderType": order_type,
            "price": price if order_type == "limit" else 0,
            "estimatedNotional": risk["estimatedNotional"],
        }
        trade_audit(dict(audit, status="submitting"))
        try:
            response = kis_post(environment, "/uapi/domestic-stock/v1/trading/order-cash", transaction_id, payload)
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


def kis_cancelable_orders(environment):
    cano, product = kis_account_parts(environment)
    response = kis_get(
        environment,
        "/uapi/domestic-stock/v1/trading/inquire-psbl-rvsecncl",
        "VTTC0084R" if environment == "paper" else "TTTC0084R",
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


def kis_order_history(environment, symbol=""):
    cano, product = kis_account_parts(environment)
    end = datetime.now()
    start = end - timedelta(days=7)
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
    cancelable_rows = kis_cancelable_orders(environment)
    cancelable = {str(row.get("odno", "")): row for row in cancelable_rows if str(row.get("odno", ""))}
    orders = []
    for row in response.get("output1") or []:
        order_number = str(row.get("odno", ""))
        order_quantity = int(numeric(row.get("ord_qty")))
        filled_quantity = int(numeric(row.get("tot_ccld_qty") or row.get("ccld_qty")))
        remaining_quantity = int(numeric(row.get("rmn_qty"), max(0, order_quantity - filled_quantity)))
        cancel_row = cancelable.get(order_number)
        cancel_quantity = int(numeric(cancel_row.get("psbl_qty"))) if cancel_row else 0
        canceled_quantity = int(numeric(row.get("cncl_cfrm_qty")))
        rejected_quantity = int(numeric(row.get("rjct_qty")))
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
        orders.append({
            "orderNumber": order_number,
            "organizationNumber": organization or str(row.get("krx_fwdg_ord_orgno") or row.get("ord_gno_brno") or ""),
            "originalOrderNumber": str(row.get("orgn_odno", "")),
            "symbol": str(row.get("pdno", "")),
            "name": str(row.get("prdt_name", "")),
            "side": side,
            "orderType": str(row.get("ord_dvsn_name") or row.get("ord_dvsn_cd") or ""),
            "orderTypeCode": str(row.get("ord_dvsn_cd") or "00"),
            "quantity": order_quantity,
            "filledQuantity": filled_quantity,
            "remainingQuantity": remaining_quantity,
            "cancelQuantity": cancel_quantity,
            "price": numeric(row.get("ord_unpr")),
            "averagePrice": numeric(row.get("avg_prvs")),
            "state": state,
            "canCancel": cancel_quantity > 0,
            "date": str(row.get("ord_dt", "")),
            "time": str(row.get("ord_tmd", "")),
        })
    orders.sort(key=lambda order: order["date"] + order["time"] + order["orderNumber"], reverse=True)
    return {
        "status": "ok",
        "environment": environment,
        "symbol": symbol,
        "orders": orders[:8],
        "pendingCount": sum(1 for order in orders if order["canCancel"]),
        "updatedAt": int(time.time()),
    }


def kis_cancel(environment, request):
    if environment not in ("paper", "prod"):
        raise StockServiceError("Unsupported trading environment")
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

