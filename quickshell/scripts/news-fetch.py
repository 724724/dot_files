#!/usr/bin/env python3
import email.utils
import difflib
import html
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone


UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 QuickshellNews/1.0"
STOCK_NEWS_WINDOW = 3 * 24 * 60 * 60
STOCK_CACHE_DIR = pathlib.Path(
    os.environ.get("XDG_CACHE_HOME") or pathlib.Path.home() / ".cache"
) / "quickshell" / "stock-news"
STOCK_PROFILE_PATH = pathlib.Path(__file__).with_name("stock-news-profiles.json")


def load_stock_profiles():
    try:
        value = json.loads(STOCK_PROFILE_PATH.read_text(encoding="utf-8"))
        if isinstance(value.get("sectors"), dict) and isinstance(value.get("companies"), dict):
            return value
    except Exception:
        pass
    return {"version": 1, "sectors": {}, "companies": {}}


STOCK_PROFILES = load_stock_profiles()
STOCK_CACHE_VERSION = int(STOCK_PROFILES.get("version", 1))

CATEGORY_LABELS = {
    "politics": "Politics",
    "economy": "Economics",
    "society": "Society",
    "culture": "Culture",
    "it": "Science",
    "world": "World",
}

SOURCE_LABELS = {
    "chosun": "CHOSUN.COM",
    "joongang": "JOONGANG.CO.KR",
    "donga": "DONGA.COM",
}

CHO_RSS = "https://www.chosun.com/arc/outboundfeeds/rss/category/{}/?outputType=xml"
CHO_ALL = "https://www.chosun.com/arc/outboundfeeds/rss/?outputType=xml"

# Category RSS/HTML feeds from these outlets are not pure: they routinely embed
# "most read" / related-article widgets from other sections, so an item fetched
# from e.g. donga's economy.xml can actually be a politics or society story.
# The article URL itself encodes the outlet's own section, which is a more
# reliable signal than "which feed did this come from", so we use it to
# correct the category instead of trusting the feed blindly.
DONGA_SECTION_CATEGORY = {
    "Politics": "politics",
    "Economy": "economy",
    "Society": "society",
    "Culture": "culture",
    "It": "it",
    "Inter": "world",
}

CHOSUN_SEGMENT_CATEGORY = {
    "politics": "politics",
    "economy": "economy",
    "national": "society",
    "medical": "society",
    "culture-life": "culture",
    "international": "world",
}


def infer_category(source, url):
    url = url or ""
    if source == "donga":
        m = re.search(r"donga\.com/news/([A-Za-z]+)/article", url)
        return DONGA_SECTION_CATEGORY.get(m.group(1)) if m else None
    if source == "chosun":
        if "/economy/tech_it/" in url or "/economy/science/" in url:
            return "it"
        m = re.search(r"chosun\.com/([a-z_-]+)/", url)
        return CHOSUN_SEGMENT_CATEGORY.get(m.group(1)) if m else None
    return None

FEEDS = {
    "chosun": {
        "politics": [("rss", CHO_RSS.format("politics"), None)],
        "economy": [("rss", CHO_RSS.format("economy"), None)],
        "society": [("rss", CHO_RSS.format("national"), None)],
        "culture": [("rss", CHO_RSS.format("culture-life"), None)],
        "it": [("rss", CHO_ALL, ("/economy/tech_it/", "/economy/science/"))],
        "world": [("rss", CHO_RSS.format("international"), None)],
    },
    "joongang": {
        "politics": [("html", "https://www.joongang.co.kr/politics", None)],
        "economy": [("html", "https://www.joongang.co.kr/money", None)],
        "society": [("html", "https://www.joongang.co.kr/society", None)],
        "culture": [("html", "https://www.joongang.co.kr/culture", None)],
        "it": [("html", "https://www.joongang.co.kr/factpl", None)],
        "world": [("html", "https://www.joongang.co.kr/world", None)],
    },
    "donga": {
        "politics": [("rss", "https://rss.donga.com/politics.xml", None)],
        "economy": [("rss", "https://rss.donga.com/economy.xml", None)],
        "society": [("rss", "https://rss.donga.com/national.xml", None)],
        "culture": [("rss", "https://rss.donga.com/culture.xml", None)],
        "it": [("rss", "https://rss.donga.com/science.xml", None)],
        "world": [("rss", "https://rss.donga.com/international.xml", None)],
    },
}


def clean_text(value):
    value = re.sub(r"(?is)<!--.*?-->|<!DOCTYPE[^>]*>|<\?[^>]*\?>|</?[A-Za-z][^>]*>", " ", value or "")
    value = html.unescape(value)
    value = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", value)
    value = re.sub(r"\x9b[0-?]*[ -/]*[@-~]", "", value)
    value = re.sub(r"\ufffd(?:\[[0-?]*[ -/]*[@-~]|[A-Za-z])?", "", value)
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def image_from_html(value):
    m = re.search(r'<img\b[^>]*\bsrc=["\']([^"\']+)["\']', value or "", re.I | re.S)
    if not m:
        return ""
    return html.unescape(m.group(1))


def fetch_url(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=8) as res:
        raw = res.read()
        charset = res.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, "replace")


def json_article_text(value):
    best = ""

    def walk(obj):
        nonlocal best
        if isinstance(obj, dict):
            for key in ("articleBody", "description"):
                text = clean_text(str(obj.get(key, "")))
                if len(text) > len(best):
                    best = text
            for child in obj.values():
                walk(child)
        elif isinstance(obj, list):
            for child in obj:
                walk(child)

    for raw in re.findall(r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', value or "", re.I | re.S):
        try:
            walk(json.loads(html.unescape(raw).strip()))
        except Exception:
            continue
    return best


def paragraph_article_text(value):
    page = re.sub(r"(?is)<(script|style|noscript|svg|header|footer|nav|aside)\b.*?</\1>", " ", value or "")
    parts = []
    seen = set()
    for raw in re.findall(r"<p\b[^>]*>(.*?)</p>", page, re.I | re.S):
        text = clean_text(raw)
        if len(text) < 25:
            continue
        if any(token in text for token in ("글자크기 설정", "무단 전재", "재배포 금지", "구독", "Copyright", "ⓒ", "기자", "캡쳐")) and len(text) < 120:
            continue
        key = text[:80]
        if key in seen:
            continue
        seen.add(key)
        parts.append(text)
    return " ".join(parts)


def article_text_from_html(value):
    candidates = [json_article_text(value), paragraph_article_text(value)]
    return max(candidates, key=len).strip()


def fetch_article_text(url):
    if not url or not url.startswith("http"):
        return ""
    try:
        return article_text_from_html(fetch_url(url))[:4800]
    except Exception:
        return ""


def iso_from_rfc(value):
    if not value:
        return ""
    try:
        dt = email.utils.parsedate_to_datetime(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone().isoformat(timespec="minutes")
    except Exception:
        return ""


def ts_from_iso(value):
    if not value:
        return 0
    try:
        return int(datetime.fromisoformat(value).timestamp())
    except Exception:
        return 0


def published_text(value):
    if not value:
        return ""
    try:
        return datetime.fromisoformat(value).strftime("%H:%M")
    except Exception:
        return ""


def rss_items(text, source, category, filters):
    root = ET.fromstring(text.encode("utf-8"))
    ns = {
        "content": "http://purl.org/rss/1.0/modules/content/",
        "media": "http://search.yahoo.com/mrss/",
    }
    out = []
    for item in root.findall(".//item"):
        title = clean_text(item.findtext("title"))
        link = clean_text(item.findtext("link"))
        if filters and not any(f in link for f in filters):
            continue
        raw_desc = item.findtext("description") or item.findtext("content:encoded", namespaces=ns) or ""
        desc = clean_text(raw_desc)
        pub = iso_from_rfc(clean_text(item.findtext("pubDate")))
        image = image_from_html(raw_desc)
        media = item.find("media:content", ns)
        if media is not None:
            image = media.attrib.get("url", "") or image
        if title and link:
            out.append(make_item(source, category, title, link, desc, pub, image))
    return out


def html_items(text, source, category):
    records = {}
    order = []
    pattern = re.compile(r'<a\b[^>]*href="(https://www\.joongang\.co\.kr/article/\d+)"[^>]*>(.*?)</a>', re.I | re.S)
    for m in pattern.finditer(text):
        url = html.unescape(m.group(1))
        title = clean_text(m.group(2))
        title_rank = 2 if len(title) >= 5 else 0
        image = image_from_html(m.group(2))
        if len(title) < 5:
            alt = re.search(r'alt="([^"]+)"', m.group(2), re.I | re.S)
            title = clean_text(alt.group(1)) if alt else ""
            title = re.sub(r"^[^\s<>]+\.(?:jpe?g|png|webp|gif)(?=[\"'“”‘’])", "", title, flags=re.I)
            title_rank = 1 if len(title) >= 5 else 0
        window = text[m.end():m.end() + 1600]
        desc = ""
        dm = re.search(r'<p\s+class="description"[^>]*>(.*?)</p>', window, re.I | re.S)
        if dm:
            desc = clean_text(dm.group(1))
        pub = ""
        tm = re.search(r'<p\s+class="date"[^>]*>(.*?)</p>', window, re.I | re.S)
        if tm:
            pub = parse_joongang_date(clean_text(tm.group(1)))
        if url not in records:
            records[url] = {"title": "", "titleRank": 0, "desc": "", "pub": "", "image": ""}
            order.append(url)
        record = records[url]
        if len(title) >= 5 and title_rank > record["titleRank"]:
            record["title"] = title
            record["titleRank"] = title_rank
        if image and not record["image"]:
            record["image"] = image
        if desc and not record["desc"]:
            record["desc"] = desc
        if pub and not record["pub"]:
            record["pub"] = pub
    return [make_item(source, category, records[url]["title"], url,
                      records[url]["desc"], records[url]["pub"], records[url]["image"])
            for url in order if len(records[url]["title"]) >= 5]


def parse_joongang_date(value):
    m = re.search(r"(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})", value or "")
    if not m:
        return ""
    try:
        dt = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))).astimezone()
        return dt.isoformat(timespec="minutes")
    except Exception:
        return ""


def make_item(source, category, title, url, desc, pub, image):
    category = infer_category(source, url) or category
    return {
        "sourceId": source,
        "source": SOURCE_LABELS.get(source, source),
        "categoryId": category,
        "category": CATEGORY_LABELS.get(category, category),
        "title": title,
        "summary": desc[:2400],
        "url": url,
        "image": image,
        "published": pub,
        "publishedText": published_text(pub),
        "_ts": ts_from_iso(pub),
    }


def split_arg(value, fallback):
    items = [x.strip() for x in (value or "").split(",") if x.strip()]
    return items or fallback


def fetch_news(args):
    sources = split_arg(args[0] if len(args) > 0 else "", list(SOURCE_LABELS.keys()))
    categories = split_arg(args[1] if len(args) > 1 else "", list(CATEGORY_LABELS.keys()))
    category_set = set(categories)
    limit = int(args[2]) if len(args) > 2 and args[2].isdigit() else 36
    items = []
    errors = []
    for source in sources:
        for category in categories:
            for kind, url, filters in FEEDS.get(source, {}).get(category, []):
                try:
                    text = fetch_url(url)
                    part = rss_items(text, source, category, filters) if kind == "rss" else html_items(text, source, category)
                    # Items may get reclassified above (see infer_category) once we
                    # learn their real section, so drop ones that no longer belong
                    # to any category the caller actually asked for.
                    items.extend(p for p in part[:18] if p["categoryId"] in category_set)
                except Exception as e:
                    errors.append(f"{SOURCE_LABELS.get(source, source)} {CATEGORY_LABELS.get(category, category)}: {e}")
    deduped = []
    seen = set()
    for item in items:
        key = item["url"]
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    deduped.sort(key=lambda x: x.get("_ts", 0), reverse=True)
    for item in deduped:
        item.pop("_ts", None)
    print(json.dumps({"ok": True, "updatedAt": int(time.time()), "items": deduped[:limit], "errors": errors}, ensure_ascii=False))


def stock_profile(market, symbol):
    return STOCK_PROFILES.get("companies", {}).get(f"{market.upper()}:{symbol.upper()}", {})


def stock_canonical_name(name, symbol, market="KRX"):
    aliases = stock_profile(market, symbol).get("aliases", [])
    return clean_text(aliases[0] if aliases else name) or clean_text(symbol)


def stock_company_terms(name, symbol, market="KRX"):
    raw = clean_text(name)
    compact = re.sub(r"(?:주식회사|\(주\)|㈜)", "", raw, flags=re.I).strip()
    compact = re.sub(r"\s+(?:inc\.?|corp\.?|corporation|co\.?|ltd\.?)$", "", compact, flags=re.I).strip()
    terms = []
    aliases = stock_profile(market, symbol).get("aliases", [])
    for value in (compact, raw, *aliases, clean_text(symbol)):
        lowered = value.casefold().strip()
        if len(lowered) >= 2 and lowered not in terms:
            terms.append(lowered)
    return terms


def stock_profile_values(profile, key):
    values = profile.get(key, []) if isinstance(profile, dict) else []
    return tuple(
        value for value in (clean_text(str(item)).casefold() for item in values)
        if value
    )


def stock_source_quality(source):
    value = clean_text(source).casefold()
    tiers = STOCK_PROFILES.get("relevance", {}).get("sourceQuality", {})
    weights = {
        "authoritative": 1.0,
        "established": 0.9,
        "aggregator": 0.68,
        "low": 0.5,
    }
    for tier in ("authoritative", "established", "low", "aggregator"):
        if any(clean_text(term).casefold() in value for term in tiers.get(tier, []) if clean_text(term)):
            return {"tier": tier, "weight": weights[tier], "score": round(weights[tier] * 100)}
    return {"tier": "standard", "weight": 0.78, "score": 78}


KOREAN_PARTICLES = r"(?:으로부터|로부터|에게서|께서는|에서는|와의|과의|으로|에서|에게|께서|은|는|이|가|을|를|의|에|도|만|와|과|로|서|측)"


def stock_term_pattern(term):
    escaped = re.escape(term)
    if re.search(r"[가-힣]", term):
        return r"(?<![0-9a-z가-힣])" + escaped + r"(?=$|[^0-9a-z가-힣]|" + KOREAN_PARTICLES + r"(?:$|[^0-9a-z가-힣]))"
    if re.fullmatch(r"[a-z]+", term, re.I):
        forms = {term}
        if term.endswith("y") and len(term) > 2 and term[-2] not in "aeiou":
            forms.update((term + "ing", term[:-1] + "ies", term[:-1] + "ied"))
        elif term.endswith("e"):
            forms.update((term + "s", term + "d", term[:-1] + "ing"))
        else:
            forms.update((term + "s", term + "es", term + "ed", term + "ing"))
        escaped = "(?:" + "|".join(re.escape(value) for value in sorted(forms, key=len, reverse=True)) + ")"
    return r"(?<![a-z0-9])" + escaped + r"(?![a-z0-9])"


def stock_term_spans(text, terms):
    value = clean_text(text).casefold()
    matches = []
    for raw in terms:
        term = clean_text(str(raw)).casefold()
        if not term:
            continue
        for occurrence in re.finditer(stock_term_pattern(term), value, re.I):
            matches.append((term, occurrence.start(), occurrence.end()))
    return matches


def stock_term_matches(text, terms):
    matches = []
    for term, _, _ in stock_term_spans(text, terms):
        if term not in matches:
            matches.append(term)
    return matches


def stock_alias_pattern(alias):
    escaped = re.escape(alias)
    if re.search(r"[가-힣]", alias):
        return r"(?<![0-9a-z가-힣])" + escaped + r"(?=$|[^0-9a-z가-힣]|" + KOREAN_PARTICLES + r"(?:$|[^0-9a-z가-힣]))"
    return r"(?<![a-z0-9])" + escaped + r"(?![a-z0-9])"


def stock_alias_spans(text, aliases):
    value = clean_text(text).casefold()
    spans = []
    for raw in aliases:
        alias = clean_text(str(raw)).casefold()
        if not alias:
            continue
        spans.extend((alias, match.start(), match.end()) for match in re.finditer(stock_alias_pattern(alias), value, re.I))
    return spans


def stock_alias_matches(text, aliases):
    matches = []
    for alias, _, _ in stock_alias_spans(text, aliases):
        if alias not in matches:
            matches.append(alias)
    return matches


def stock_company_material_events(text, target_aliases, symbol, market):
    normalized_text = clean_text(text)
    event_terms = (
        STOCK_PROFILES.get("relevance", {}).get("corporateEvents", [])
        + STOCK_PROFILES.get("relevance", {}).get("materialityEvents", [])
    )
    event_spans = stock_term_spans(text, event_terms)
    target_spans = [
        {"start": start, "end": end, "target": True}
        for _, start, end in stock_alias_spans(normalized_text, target_aliases)
    ]
    ticker = clean_text(symbol).casefold()
    if ticker:
        ticker_pattern = r"(?:\$|(?:nasdaq|nyse|krx)\s*[:：]\s*)" + re.escape(ticker) + r"(?![a-z0-9])"
        target_spans.extend(
            {"start": match.start(), "end": match.end(), "target": True}
            for match in re.finditer(ticker_pattern, normalized_text.casefold(), re.I)
        )

    entity_spans = list(target_spans)
    target_key = f"{market.upper()}:{symbol.upper()}"
    for key, profile in STOCK_PROFILES.get("companies", {}).items():
        if key == target_key:
            continue
        for _, start, end in stock_alias_spans(normalized_text, stock_profile_values(profile, "aliases")):
            entity_spans.append({"start": start, "end": end, "target": False})

    subject_pattern = re.compile(
        r"(?:^|[,;:]\s*|\b(?:as|while|after|before|following)\s+)"
        r"([A-Z][A-Za-z0-9&.'-]*(?:\s+[A-Z][A-Za-z0-9&.'-]*){0,3})\s+"
        r"(?=(?:reports?|announces?|unveils?|launches?|posts?|records?|forecasts?|expects?|approves?|declares?)\b)"
    )
    for match in subject_pattern.finditer(normalized_text):
        start, end = match.span(1)
        if not any(span["start"] < end and span["end"] > start for span in target_spans):
            entity_spans.append({"start": start, "end": end, "target": False})

    accepted = []
    for term, start, end in event_spans:
        nearby = []
        for entity in entity_spans:
            distance = start - entity["end"] if entity["end"] <= start else entity["start"] - end if entity["start"] >= end else 0
            between_start = min(end, entity["end"])
            between_end = max(start, entity["start"])
            if re.search(r"[;；|。!?␞]", normalized_text[between_start:between_end]):
                continue
            if 0 <= distance <= 160:
                nearby.append((distance, 0 if entity["target"] else 1, entity))
        if nearby and min(nearby, key=lambda value: (value[0], value[1]))[2]["target"] and term not in accepted:
            accepted.append(term)
    return accepted


def stock_sector_signal_terms(market, symbol, signal):
    values = []
    for sector_id in stock_profile(market, symbol).get("sectors", []):
        sector = STOCK_PROFILES.get("sectorSignals", {}).get(sector_id, {})
        for term in sector.get(signal, []):
            cleaned = clean_text(str(term)).casefold()
            if cleaned and cleaned not in values:
                values.append(cleaned)
    return tuple(values)


def stock_sector_theme_terms(market, sector_id):
    sector = STOCK_PROFILES.get("sectors", {}).get(sector_id, {})
    locale = "ko" if market.upper() == "KRX" else "en"
    alternate = "en" if locale == "ko" else "ko"
    values = []
    query_terms = sector.get("queryTerms", {})
    for value in (
        query_terms.get(locale, [])
        + sector.get(locale, [])
        + query_terms.get(alternate, [])
        + sector.get(alternate, [])
    ):
        cleaned = clean_text(str(value)).casefold()
        if cleaned and cleaned not in values:
            values.append(cleaned)
    return tuple(values)


def stock_sector_query_terms(market, symbol, sector_id):
    sector = STOCK_PROFILES.get("sectors", {}).get(sector_id, {})
    locale = "ko" if market.upper() == "KRX" else "en"
    values = []

    def append(items):
        for value in items:
            cleaned = clean_text(str(value)).casefold()
            if cleaned and cleaned not in values:
                values.append(cleaned)

    append(sector.get("queryTerms", {}).get(locale, []))
    signals = STOCK_PROFILES.get("sectorSignals", {}).get(sector_id, {})
    for signal in ("supplyChain", "regulation", "macro"):
        localized = [
            value for value in signals.get(signal, [])
            if bool(re.search(r"[가-힣]", value)) == (locale == "ko")
        ]
        append(localized[:2])
    append(stock_sector_theme_terms(market, sector_id))
    return tuple(values[:8])


def stock_ticker_matches(text, symbol, market):
    value = clean_text(text).casefold()
    ticker = clean_text(symbol).casefold()
    if not ticker:
        return False
    escaped = re.escape(ticker)
    if re.search(r"(?:\$|(?:nasdaq|nyse|krx)\s*[:：]\s*)" + escaped + r"(?![a-z0-9])", value, re.I):
        return True
    contexts = STOCK_PROFILES.get("relevance", {}).get("stockContexts", [])
    if not stock_term_matches(value, contexts):
        return False
    return re.search(r"(?<![a-z0-9])" + escaped + r"(?![a-z0-9])", value, re.I) is not None


def stock_competitor_matches(text, market, symbol):
    own_key = f"{market.upper()}:{symbol.upper()}"
    own_sectors = set(stock_profile(market, symbol).get("sectors", []))
    if not own_sectors:
        return []
    matches = []
    for key, profile in STOCK_PROFILES.get("companies", {}).items():
        if key == own_key or not own_sectors.intersection(profile.get("sectors", [])):
            continue
        aliases = stock_profile_values(profile, "aliases")
        hits = stock_alias_matches(text, aliases)
        if hits:
            matches.append((key, hits[0]))
    return matches


def competitor_is_headline_subject(title, target_aliases, competitor_hits):
    value = clean_text(title).casefold()
    action = r"(?:expects?|forecasts?|reports?|says?|launches?|announces?|warns?|예상|전망|발표|출시|경고)"
    for _, competitor_alias in competitor_hits:
        competitor = re.escape(competitor_alias)
        for target_alias in target_aliases:
            target = re.escape(target_alias)
            if re.search(
                r"^.{0,30}" + competitor + r".{0,100}" + action + r".{0,100}" + target,
                value,
                re.I,
            ):
                return competitor_alias
    return ""


def incidental_company_mention(text, aliases, profile=None):
    value = clean_text(text).casefold()
    if not stock_alias_matches(value, aliases):
        return False
    if re.search(r"(?:증정|경품|이벤트|giveaway|sweepstakes).{0,50}(?:주식|주|shares?)|(?:주식|주|shares?).{0,50}(?:증정|경품|이벤트|giveaway|sweepstakes)", value, re.I):
        return True
    if re.search(r"(?:연예인|방송인|유튜버|인플루언서|개미|직장인|초고수).{0,60}(?:보유|샀|매수|팔았|매도|투자)", value, re.I):
        return True
    for alias in aliases:
        escaped = re.escape(alias)
        if re.search(r"(?:former|ex-)\s+" + escaped + r"\b|" + escaped + r".{0,18}(?:출신|전직)", value, re.I):
            return True
        if re.search(r"(?:중국판|제2의)\s*" + escaped + r"|" + escaped + r".{0,35}(?:배후수요|인근\s+아파트|부동산)", value, re.I):
            return True
        if alias in ("네이버", "naver") and re.search(
            escaped + r"(?:에서|서)?\s*.{0,45}(?:할인|특가|판매|구매|최저가)",
            value,
            re.I,
        ):
            return True
    for alias in aliases:
        escaped = re.escape(alias)
        if re.search(
            escaped + r".{0,55}(?:raises?|lowers?|cuts?|sets?|adjusts?|reiterates?|upgrades?|downgrades?|forecasts?|predicts?|estimates?).{0,60}(?:price target|rating|outlook|\bfor\b)",
            value,
            re.I,
        ):
            return True
        if re.search(
            escaped + r".{0,55}(?:has|owns?|buys?|sells?|holds?|boosts?|cuts?|trims?|reduces?|increases?|decreases?|acquires?|purchases?).{0,55}(?:shares?|stock holdings?|stock position|stake|position|holdings?)(?:\s+(?:in|of)\b|\s*$)",
            value,
            re.I,
        ):
            return True
    if "finance" in (profile or {}).get("sectors", []):
        roles = STOCK_PROFILES.get("relevance", {}).get("incidentalRoles", [])
        if stock_term_matches(value, roles):
            return True
        if re.search(r"\b(?:form\s+(?:8-k|10-k|10-q|424b\d*|fwp)|indenture|prospectus)\b", value, re.I):
            return True
        if re.search(r"\b(?:tr|trust)\s+plc\b|\bstock\s+data(?:,|\s)+(?:price|news)\b", value, re.I):
            return True
        for alias in aliases:
            escaped = re.escape(alias)
            if re.search(
                escaped + r".{0,70}(?:analysts?\s+says?|predicts?|forecasts?|thinks?|recommends?|picks?|worth\s+watching|target(?:\s+valuation)?|rating|price\s+objective)",
                value,
                re.I,
            ):
                return True
            if re.search(
                escaped + r".{0,45}(?:buys?|sells?|trims?|boosts?|cuts?|reduces?|increases?|acquires?)\s+.{1,55}(?:\([a-z]{1,6}\)|\b(?:inc|corp|plc|ltd)\b)",
                value,
                re.I,
            ):
                return True
    return False


def external_market_commentary(text, aliases):
    value = clean_text(text).casefold()
    for alias in aliases:
        escaped = re.escape(alias)
        if re.search(
            r"(?:analysts?|broker|bank|research|증권사?|애널리스트|리포트|목표주가|투자의견).{0,80}" + escaped,
            value,
            re.I,
        ):
            return True
        if re.search(
            escaped + r".{0,90}(?:실적\s*발표\s*후|after\s+(?:the\s+)?earnings).{0,90}(?:우려|전망|비중|매수|매도|buy|sell|rating|weight)"
            + r"|(?:비중\s*(?:유지|확대|축소)|투자의견).{0,60}" + escaped,
            value,
            re.I,
        ):
            return True
        if re.search(
            escaped + r".{0,80}(?:price\s+target|analyst\s+rating|stock\s+(?:looks|rated)|ahead\s+of\s+(?:its\s+)?earnings|목표주가|투자의견|주가\s+전망)",
            value,
            re.I,
        ):
            return True
        if re.search(
            r"(?:earnings\s+(?:preview|on\s+deck)|what\s+to\s+(?:look\s+for|expect)|expected\s+to|rumou?r|실적\s+(?:전망|예상)|관전\s+포인트|루머).{0,90}" + escaped
            + r"|" + escaped + r".{0,90}(?:earnings\s+(?:preview|on\s+deck)|what\s+to\s+(?:look\s+for|expect)|expected\s+to|rumou?r|실적\s+(?:전망|예상)|관전\s+포인트|루머)",
            value,
            re.I,
        ):
            return True
    return False


def stock_relevance(item, name, symbol, market="KRX"):
    title = clean_text(item.get("title", ""))
    source = clean_text(item.get("source", ""))
    if source:
        title = re.sub(
            r"\s*(?:[-–—:|]\s*)" + re.escape(source) + r"\s*$",
            "",
            title,
            flags=re.I,
        ).strip()
    summary = clean_text(item.get("summary", ""))
    if summary.casefold().startswith(title.casefold()):
        summary = summary[len(title):].strip(" -–—:|")
    combined = f"{title} ␞ {summary}".strip(" ␞")
    empty = {
        "score": 0,
        "relationType": "theme",
        "relationClass": "unrelated",
        "topic": "",
        "reason": "No relevant company or industry evidence",
        "evidence": [],
        "materialEvent": False,
    }
    if not title or low_information_stock_title(title):
        return empty

    profile = stock_profile(market, symbol)
    aliases = []
    compact_name = re.sub(r"(?:주식회사|\(주\)|㈜)", "", clean_text(name), flags=re.I).strip()
    for value in (compact_name, *profile.get("aliases", [])):
        cleaned = clean_text(str(value)).casefold()
        if len(cleaned) >= 2 and cleaned != clean_text(symbol).casefold() and cleaned not in aliases:
            aliases.append(cleaned)
    products = stock_profile_values(profile, "products")
    title_aliases = stock_alias_matches(title, aliases)
    summary_aliases = stock_alias_matches(summary, aliases)
    title_products = stock_term_matches(title, products)
    summary_products = stock_term_matches(summary, products)
    exclusions = stock_term_matches(combined, stock_profile_values(profile, "exclusions"))
    ambiguous = set(stock_profile_values(profile, "ambiguousAliases"))
    ambiguous.update(
        alias for alias in aliases
        if re.fullmatch(r"[a-z]{1,3}", alias, re.I)
    )
    only_ambiguous = bool(title_aliases or summary_aliases) and all(
        value in ambiguous for value in title_aliases + summary_aliases
    )
    if exclusions and only_ambiguous and not (title_products or summary_products):
        return dict(empty, reason=f"Ambiguous company name conflicts with: {exclusions[0]}")
    company_clauses = [
        clause for clause in re.split(r"[;；|。!?␞]\s*", combined)
        if stock_alias_matches(clause, aliases)
        or stock_ticker_matches(clause, symbol, market)
    ]
    corporate_events = stock_company_material_events(combined, aliases, symbol, market)
    if re.search(
        r"(?:ai|인공지능|개인|retail|investor)\s*(?:investment|투자)|(?:investment|투자)\s*(?:과열|열풍|심리|경고|버블|거품|sentiment|warning|boom|bubble)",
        " ".join(company_clauses),
        re.I,
    ):
        corporate_events = [
            term for term in corporate_events if term not in ("investment", "투자")
        ]
    if external_market_commentary(combined, title_aliases + summary_aliases):
        corporate_events = []
    mention_context = stock_term_matches(
        combined,
        STOCK_PROFILES.get("relevance", {}).get("corporateEvents", [])
        + STOCK_PROFILES.get("relevance", {}).get("materialityEvents", [])
        + STOCK_PROFILES.get("relevance", {}).get("stockContexts", []),
    )
    if only_ambiguous and not mention_context and not (title_products or summary_products):
        return dict(empty, reason="Short or ambiguous company name lacks corporate context")
    if incidental_company_mention(combined, title_aliases + summary_aliases, profile):
        return dict(empty, reason="Company name is incidental to a promotion, anecdote, analyst note, or fund holding")

    early_competitors = stock_competitor_matches(title, market, symbol)
    competitor_subject = competitor_is_headline_subject(
        title,
        title_aliases,
        early_competitors,
    )
    if competitor_subject:
        return {
            "score": 64,
            "relationType": "theme",
            "relationClass": "competitor",
            "topic": competitor_subject,
            "reason": "Another company is the headline subject and the selected company is affected indirectly",
            "evidence": [
                {"kind": "competitor", "term": competitor_subject, "location": "title"},
                {"kind": "company", "term": title_aliases[0], "location": "title"},
            ],
            "materialEvent": False,
        }

    evidence = []
    if title_aliases:
        evidence.append({"kind": "company", "term": title_aliases[0], "location": "title"})
        if corporate_events:
            evidence.append({"kind": "corporate_event", "term": corporate_events[0], "location": "title-summary"})
        return {
            "score": (100 if not only_ambiguous else 96) if corporate_events else (76 if not only_ambiguous else 70),
            "relationType": "direct",
            "relationClass": "company",
            "topic": title_aliases[0],
            "reason": "A material company event appears in the headline" if corporate_events else "Company is central to the headline but no material event is confirmed",
            "evidence": evidence,
            "materialEvent": bool(corporate_events),
        }
    if stock_ticker_matches(combined, symbol, market):
        evidence.append({"kind": "ticker", "term": symbol.upper(), "location": "title-summary"})
        return {
            "score": 92 if corporate_events else 72,
            "relationType": "direct",
            "relationClass": "company",
            "topic": symbol.upper(),
            "reason": "Ticker appears with a material company event" if corporate_events else "Ticker appears with market context but no material event is confirmed",
            "evidence": evidence,
            "materialEvent": bool(corporate_events),
        }
    if summary_aliases:
        evidence.append({"kind": "company", "term": summary_aliases[0], "location": "summary"})
        if corporate_events:
            evidence.append({"kind": "corporate_event", "term": corporate_events[0], "location": "title-summary"})
        return {
            "score": (90 if not only_ambiguous else 86) if corporate_events else (68 if not only_ambiguous else 62),
            "relationType": "direct",
            "relationClass": "company",
            "topic": summary_aliases[0],
            "reason": "A material company event appears in the article description" if corporate_events else "Company appears in the description but no material event is confirmed",
            "evidence": evidence,
            "materialEvent": bool(corporate_events),
        }
    product_events = stock_term_matches(combined, STOCK_PROFILES.get("relevance", {}).get("productEvents", []))
    if (title_products or summary_products) and product_events:
        term = (title_products or summary_products)[0]
        location = "title" if title_products else "summary"
        evidence.extend((
            {"kind": "product", "term": term, "location": location},
            {"kind": "product_event", "term": product_events[0], "location": "title-summary"},
        ))
        return {
            "score": 88 if title_products else 80,
            "relationType": "direct",
            "relationClass": "product",
            "topic": term,
            "reason": "A company-specific product or service is discussed",
            "evidence": evidence,
            "materialEvent": True,
        }

    supply_hits = stock_term_matches(combined, stock_sector_signal_terms(market, symbol, "supplyChain"))
    if supply_hits:
        evidence.append({"kind": "supply_chain", "term": supply_hits[0], "location": "title-summary"})
        return {
            "score": 76 if stock_term_matches(title, supply_hits) else 68,
            "relationType": "theme",
            "relationClass": "supply_chain",
            "topic": supply_hits[0],
            "reason": "A sector supply, demand, pricing, or capacity driver is discussed",
            "evidence": evidence,
        }

    event_terms = STOCK_PROFILES.get("relevance", {}).get("competitiveEvents", [])
    competitor_hits = stock_competitor_matches(combined, market, symbol)
    competitive_events = stock_term_matches(combined, event_terms)
    if competitor_hits and competitive_events:
        evidence.extend((
            {"kind": "competitor", "term": competitor_hits[0][1], "location": "title-summary"},
            {"kind": "competitive_event", "term": competitive_events[0], "location": "title-summary"},
        ))
        return {
            "score": 64,
            "relationType": "theme",
            "relationClass": "competitor",
            "topic": competitor_hits[0][1],
            "reason": "A direct competitor has a potentially market-moving event",
            "evidence": evidence,
        }

    regulation_hits = stock_term_matches(combined, stock_sector_signal_terms(market, symbol, "regulation"))
    if regulation_hits:
        evidence.append({"kind": "regulation", "term": regulation_hits[0], "location": "title-summary"})
        return {
            "score": 62,
            "relationType": "theme",
            "relationClass": "regulation",
            "topic": regulation_hits[0],
            "reason": "A regulation or policy directly affecting the company's sector is discussed",
            "evidence": evidence,
        }

    macro_hits = stock_term_matches(combined, stock_sector_signal_terms(market, symbol, "macro"))
    if macro_hits:
        evidence.append({"kind": "macro", "term": macro_hits[0], "location": "title-summary"})
        return {
            "score": 56,
            "relationType": "theme",
            "relationClass": "macro",
            "topic": macro_hits[0],
            "reason": "A macro driver with a defined link to the company's sector is discussed",
            "evidence": evidence,
        }

    theme_hits = stock_term_matches(combined, stock_theme_terms(market, symbol))
    precise_hits = [term for term in theme_hits if re.search(r"\s", term)]
    if len(theme_hits) >= 2 or precise_hits:
        term = (precise_hits or theme_hits)[0]
        evidence.append({"kind": "industry", "term": term, "location": "title-summary"})
        return {
            "score": 54 if len(theme_hits) >= 2 else 50,
            "relationType": "theme",
            "relationClass": "industry",
            "topic": term,
            "reason": "Specific industry evidence is relevant but not company-confirmed",
            "evidence": evidence,
        }
    return empty


def stock_item_matches(item, name, symbol, market="KRX"):
    return stock_relevance(item, name, symbol, market)["relationClass"] == "company"


def stock_theme_terms(market, symbol):
    profile = stock_profile(market, symbol)
    terms = []
    for sector_id in profile.get("sectors", []):
        for value in stock_sector_theme_terms(market, sector_id):
            if value not in terms:
                terms.append(value)
    return tuple(terms)


def stock_theme_matches(item, market, symbol):
    haystack = " ".join((
        clean_text(item.get("title", "")),
        clean_text(item.get("summary", "")),
    )).casefold()
    return bool(stock_term_matches(haystack, stock_theme_terms(market, symbol)))


# Aggregator listicles, market-recap spam, and retail/celebrity gambling
# stories drown out actual company news in Google News results.
STOCK_NOISE_PATTERNS = tuple(re.compile(pattern, re.IGNORECASE) for pattern in (
    r"^\d{4}-\d{2}-\d{2}",
    r"인기\s*종목",
    r"주식\s*시황|시황\s*알아보기",
    r"장\s*마감\s*리포트",
    r"급등주|급락주|테마주\s*(정리|모음)",
    r"추천주|매수\s*추천",
    r"투자\s*대박|몰빵|전\s*재산\b|근황|반응\s*터진",
    r"초고수",
    r"일하고\s+싶은\s+기업|취업\s*선호|꿈의\s+직장|구직자\s+픽",
    r"jersey\s+patch|sponsorship|community\s+event",
    r"price\s+breakout",
    r"trending\s+stock",
    r"stocks?\s+to\s+(buy|watch)\b",
    r"buy\s*,?\s*sell\s+or\s+hold|if\s+you(?:'d|\s+had)\s+(?:put|invested)|outpacing\s+its\s+.+peers",
    r"stocks?\s+(?:rises?|falls?)\s+.+(?:outperforms?|underperforms?)\s+(?:the\s+)?market",
    r"\bcfds?\b",
))


def low_information_stock_title(title):
    value = clean_text(title)
    return any(pattern.search(value) for pattern in STOCK_NOISE_PATTERNS)


STORY_STOP_WORDS = {
    "관련", "대한", "위한", "통해", "따라", "발표", "공개", "news", "says", "said",
    "with", "from", "that", "this", "will", "after", "amid", "into", "대한민국",
}
STORY_TOKEN_ALIASES = {
    "괴리율": "premium", "웃돈": "premium", "고평가": "premium", "프리미엄": "premium",
    "버블": "overheat", "거품": "overheat", "과열": "overheat",
    "영업익": "earnings", "영업이익": "earnings", "순이익": "earnings", "실적": "earnings",
}


def stock_story_tokens(value):
    words = re.findall(r"[0-9a-z가-힣]{2,}", clean_text(value).casefold())
    return {
        STORY_TOKEN_ALIASES.get(word, word)
        for word in words if word not in STORY_STOP_WORDS
    }


def stock_story_similarity(first, second):
    first_title = re.sub(r"[^0-9a-z가-힣]+", " ", clean_text(first.get("title", "")).casefold()).strip()
    second_title = re.sub(r"[^0-9a-z가-힣]+", " ", clean_text(second.get("title", "")).casefold()).strip()
    if not first_title or not second_title:
        return 0
    sequence = difflib.SequenceMatcher(None, first_title, second_title).ratio()
    first_tokens = stock_story_tokens(first_title)
    second_tokens = stock_story_tokens(second_title)
    union = first_tokens | second_tokens
    title_jaccard = len(first_tokens & second_tokens) / len(union) if union else 0
    containment = len(first_tokens & second_tokens) / min(len(first_tokens), len(second_tokens)) if first_tokens and second_tokens else 0
    if sequence >= 0.84 or (len(first_tokens) >= 3 and len(second_tokens) >= 3 and title_jaccard >= 0.66) or containment >= 0.82:
        return max(sequence, title_jaccard, containment)
    first_summary = stock_story_tokens(first.get("summary", ""))
    second_summary = stock_story_tokens(second.get("summary", ""))
    summary_union = first_summary | second_summary
    summary_jaccard = len(first_summary & second_summary) / len(summary_union) if summary_union else 0
    if summary_jaccard >= 0.72 and containment >= 0.34:
        return summary_jaccard
    return max(sequence, title_jaccard)


def stock_material_event_bucket(item):
    if not item.get("materialEvent"):
        return ""
    event_terms = [
        str(evidence.get("term", "")).casefold()
        for evidence in item.get("relevanceEvidence", [])
        if evidence.get("kind") == "corporate_event"
    ]
    earnings_terms = {
        "실적", "매출", "영업이익", "순이익", "earnings", "revenue", "profit", "guidance",
    }
    if not earnings_terms.intersection(event_terms):
        return ""
    published = datetime.fromtimestamp(ts_from_iso(item.get("published", ""))).astimezone()
    company = str(item.get("stockSymbol") or item.get("relationTopic") or "").casefold()
    return f"earnings:{company}:{published.date().isoformat()}"


def cluster_stock_items(items):
    clusters = []
    for item in sorted(items, key=lambda value: ts_from_iso(value.get("published", "")), reverse=True):
        timestamp = ts_from_iso(item.get("published", ""))
        event_bucket = stock_material_event_bucket(item)
        target = None
        for cluster in clusters:
            representative = cluster[0]
            other_timestamp = ts_from_iso(representative.get("published", ""))
            if timestamp and other_timestamp and abs(timestamp - other_timestamp) > 36 * 60 * 60:
                continue
            if (
                event_bucket
                and event_bucket == stock_material_event_bucket(representative)
            ) or any(stock_story_similarity(item, member) >= 0.66 for member in cluster):
                target = cluster
                break
        if target is None:
            clusters.append([item])
        else:
            target.append(item)

    output = []
    for cluster in clusters:
        representative = max(
            cluster,
            key=lambda value: (
                int(value.get("relevanceScore", 0)),
                float(value.get("sourceWeight", 0)),
                value.get("relationType") == "direct",
                bool(value.get("image")),
                len(clean_text(value.get("summary", ""))),
                ts_from_iso(value.get("published", "")),
            ),
        )
        result = dict(representative)
        sources = []
        source_details = []
        for member in cluster:
            source = clean_text(member.get("source", ""))
            if source and source not in sources:
                sources.append(source)
                source_details.append({
                    "source": source,
                    "tier": str(member.get("sourceTier", "standard")),
                    "weight": float(member.get("sourceWeight", 0.78)),
                })
        signature = re.sub(r"[^0-9a-z가-힣]+", " ", clean_text(result.get("title", "")).casefold()).strip()
        result["clusterId"] = hashlib.sha1(signature.encode("utf-8")).hexdigest()[:12]
        result["duplicateCount"] = len(cluster)
        result["duplicateSources"] = sources
        result["sourceDetails"] = source_details
        result["verifiedSourceCount"] = sum(
            1 for detail in source_details if detail["weight"] >= 0.85
        )
        query_sectors = []
        for member in cluster:
            for sector_id in member.get("querySectors", []) or [member.get("querySector", "")]:
                if sector_id and sector_id not in query_sectors:
                    query_sectors.append(sector_id)
        result["querySectors"] = query_sectors
        result["querySector"] = query_sectors[0] if query_sectors else ""
        result["clusterLatestPublished"] = max(
            (member.get("published", "") for member in cluster),
            key=ts_from_iso,
            default=result.get("published", ""),
        )
        output.append(result)
    output.sort(key=lambda value: ts_from_iso(value.get("clusterLatestPublished", value.get("published", ""))), reverse=True)
    return output


def balanced_stock_items(items, limit, sector_ids=()):
    if len(items) <= limit:
        return items
    connected = [item for item in items if item.get("relationType") == "theme"]
    direct = [item for item in items if item.get("relationType") != "theme"]
    if not connected or not direct:
        return items[:limit]

    sector_ids = tuple(sector_ids)
    sector_floor = min(len(sector_ids), max(1, limit // 3))
    reserve = min(
        len(connected),
        max(sector_floor, limit // 3),
        max(1, limit // 2),
    )
    buckets = {}
    for item in connected:
        sector_id = item.get("querySector") or "other"
        buckets.setdefault(sector_id, []).append(item)
    ordered_buckets = [
        buckets[sector_id]
        for sector_id in (*sector_ids, "other")
        if sector_id in buckets
    ]
    ordered_buckets.extend(
        bucket for sector_id, bucket in buckets.items()
        if sector_id not in set((*sector_ids, "other"))
    )
    balanced_connected = []
    while len(balanced_connected) < reserve and any(ordered_buckets):
        for bucket in ordered_buckets:
            if bucket and len(balanced_connected) < reserve:
                balanced_connected.append(bucket.pop(0))

    selected = direct[:limit - len(balanced_connected)] + balanced_connected
    selected_ids = {id(item) for item in selected}
    if len(selected) < limit:
        selected.extend(item for item in items if id(item) not in selected_ids)
    selected = selected[:limit]
    selected.sort(
        key=lambda value: ts_from_iso(value.get("clusterLatestPublished", value.get("published", ""))),
        reverse=True,
    )
    return selected


def recent_stock_items(items, name, symbol, market="KRX", limit=30, now=None):
    current = datetime.fromtimestamp(int(now or time.time())).astimezone()
    cutoff = int((current.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=2)).timestamp())
    output = []
    seen = set()
    for item in items:
        timestamp = ts_from_iso(item.get("published", ""))
        url = item.get("url", "")
        if timestamp < cutoff or timestamp > int(current.timestamp()) + 10 * 60 or not url or url in seen:
            continue
        relevance = stock_relevance(item, name, symbol, market)
        minimum_score = int(STOCK_PROFILES.get("relevance", {}).get("minimumScore", 50))
        if relevance["score"] < minimum_score:
            continue
        source_quality = stock_source_quality(item.get("source", ""))
        if source_quality["tier"] == "low" and not relevance.get("materialEvent"):
            continue
        seen.add(url)
        ranked = dict(item)
        ranked["relationType"] = relevance["relationType"]
        ranked["relationClass"] = relevance["relationClass"]
        ranked["relationTopic"] = relevance["topic"]
        ranked["relevanceScore"] = relevance["score"]
        ranked["relevanceWeight"] = round(relevance["score"] / 100, 2)
        ranked["relevanceReason"] = relevance["reason"]
        ranked["relevanceEvidence"] = relevance["evidence"]
        ranked["materialEvent"] = bool(relevance.get("materialEvent"))
        ranked["sourceTier"] = source_quality["tier"]
        ranked["sourceWeight"] = source_quality["weight"]
        ranked["sourceQualityScore"] = source_quality["score"]
        output.append(ranked)
    clustered = cluster_stock_items(output)
    return balanced_stock_items(
        clustered,
        limit,
        stock_profile(market, symbol).get("sectors", []),
    )


def stock_cache_path(market, symbol, name):
    identity = f"{STOCK_CACHE_VERSION}|{market.upper()}|{symbol.upper()}"
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:20]
    return STOCK_CACHE_DIR / f"{digest}.json"


def stock_attention_snapshot(items, now):
    recent_items = [
        item for item in items
        if 0 <= now - ts_from_iso(item.get("published", "")) <= 6 * 60 * 60
    ]
    recent_weight = sum(
        float(item.get("relevanceWeight", 0)) * float(item.get("sourceWeight", 0))
        for item in recent_items
    )
    return {
        "hour": int(now // 3600),
        "eventWeight6h": round(recent_weight, 3),
        "eventCount": len(recent_items),
    }


def stock_attention_history(cached, items, now):
    current_hour = int(now // 3600)
    history_by_hour = {
        int(entry.get("hour", 0)): entry
        for entry in ((cached or {}).get("attentionHistory") or [])
        if isinstance(entry, dict)
        and current_hour - 24 * 14 < int(entry.get("hour", 0)) < current_hour
    }
    cached_hour = int((cached or {}).get("updatedAt", 0)) // 3600
    if cached_hour > 0 and cached_hour < current_hour:
        previous_items = (cached or {}).get("items") or []
        start_hour = max(
            current_hour - 24 * 7,
            min(history_by_hour) + 1 if history_by_hour else cached_hour + 1,
        )
        for hour in range(start_hour, current_hour):
            if hour not in history_by_hour:
                history_by_hour[hour] = stock_attention_snapshot(previous_items, hour * 3600 + 3599)
    history = [
        history_by_hour[hour]
        for hour in sorted(history_by_hour)
    ][-167:]
    samples = [
        float(entry.get("eventWeight6h", 0))
        for entry in history[-48:]
        if "eventWeight6h" in entry and float(entry.get("eventWeight6h", 0)) >= 0
    ]
    baseline = {
        "expectedEventWeight6h": round(sum(samples) / len(samples), 3) if samples else 0,
        "sampleWindowCount": len(samples),
        "method": "mean_of_prior_hourly_rolling_6h_windows",
    }
    history.append(stock_attention_snapshot(items, now))
    return history[-168:], baseline


def load_stock_cache(path, name, symbol, market, limit):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    if int(payload.get("relevanceVersion", 0)) != STOCK_CACHE_VERSION:
        return None
    payload["items"] = recent_stock_items(payload.get("items", []), name, symbol, market, limit)
    return payload


def save_stock_cache(path, payload):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        os.replace(temporary, path)
    except Exception:
        pass


def fetch_google_stock_feed(query, market, relation_type, relation_topic):
    locale = market.upper() == "KRX"
    params = urllib.parse.urlencode({
        "q": query,
        "hl": "ko" if locale else "en-US",
        "gl": "KR" if locale else "US",
        "ceid": "KR:ko" if locale else "US:en",
    })
    text = fetch_url("https://news.google.com/rss/search?" + params)
    root = ET.fromstring(text.encode("utf-8"))
    items = []
    for node in root.findall("./channel/item")[:60]:
        title = clean_text(node.findtext("title"))
        source = clean_text(node.findtext("source"))
        if source and title.endswith(" - " + source):
            title = title[:-(len(source) + 3)].strip()
        link = clean_text(node.findtext("link"))
        summary = clean_text(node.findtext("description"))
        if title and summary.casefold().startswith(title.casefold()):
            summary = summary[len(title):].strip(" -–—:|")
        if source and summary.casefold() == source.casefold():
            summary = ""
        if source.casefold() == "naver blog":
            title = re.sub(
                r"\s*[:|]\s*네이버\s*블로그\s*$",
                "",
                title,
                flags=re.I,
            ).strip()
        published = iso_from_rfc(clean_text(node.findtext("pubDate")))
        if not title or not link or not published:
            continue
        items.append({
            "sourceId": "stock-search",
            "source": source or "Google News",
            "categoryId": "economy",
            "category": CATEGORY_LABELS["economy"],
            "title": title,
            "summary": summary,
            "url": link,
            "image": image_from_html(node.findtext("description") or ""),
            "published": published,
            "publishedText": published_text(published),
            "relationType": relation_type,
            "relationTopic": relation_topic,
            "querySector": relation_topic.removeprefix("sector:") if relation_topic.startswith("sector:") else "",
        })
    return items


def stock_feed_queries(name, symbol, market):
    canonical_name = stock_canonical_name(name, symbol, market)
    company_terms = stock_company_terms(canonical_name, symbol, market)
    company = company_terms[0]
    locale = market.upper() == "KRX"
    profile = stock_profile(market, symbol)
    aliases = [term for term in company_terms if term != symbol.casefold()][:4]
    company_query = " OR ".join(f'"{term}"' for term in aliases or [company])
    market_query = f'({company_query}) 주식 when:3d' if locale else f'({company_query}) stock when:3d'
    # The company-only feed catches product and business news (launches,
    # earnings) that never contain the word 주식/stock and would otherwise
    # be invisible to the anchored market feed.
    company_news_query = f'({company_query}) when:2d'
    queries = []
    seen = set()

    def append(query, relation_type, topic):
        key = clean_text(query).casefold()
        if key and key not in seen:
            seen.add(key)
            queries.append((query, relation_type, topic))

    append(company_news_query, "direct", company)
    append(market_query, "direct", company)
    material_terms = (
        STOCK_PROFILES.get("relevance", {}).get("corporateEvents", [])
        + STOCK_PROFILES.get("relevance", {}).get("materialityEvents", [])
    )
    if locale:
        material_terms = [term for term in material_terms if re.search(r"[가-힣]", term)]
    else:
        material_terms = [term for term in material_terms if re.search(r"[a-z]", term, re.I)]
    if material_terms:
        joined = " OR ".join(f'"{term}"' for term in material_terms[:24])
        append(
            f"({company_query}) ({joined}) when:3d",
            "direct",
            "material-company-event",
        )
    products = stock_profile_values(profile, "products")
    for offset in range(0, len(products), 6):
        joined = " OR ".join(f'"{term}"' for term in products[offset:offset + 6])
        append(f"({joined}) when:3d", "direct", "product")

    for sector_id in profile.get("sectors", []):
        terms = stock_sector_query_terms(market, symbol, sector_id)
        if not terms:
            continue
        joined = " OR ".join(f'"{term}"' for term in terms)
        append(f"({joined}) when:3d", "theme", f"sector:{sector_id}")
    return queries


def fetch_stock_feed(name, symbol, market):
    queries = stock_feed_queries(name, symbol, market)
    company = stock_canonical_name(name, symbol, market).casefold()
    items = []
    errors = []
    with ThreadPoolExecutor(max_workers=min(6, len(queries))) as executor:
        futures = {
            executor.submit(fetch_google_stock_feed, query, market, relation_type, topic): query
            for query, relation_type, topic in queries
        }
        for future in as_completed(futures):
            try:
                items.extend(future.result())
            except Exception as error:
                errors.append(str(error))
    if not items and errors:
        raise RuntimeError(errors[0])
    for item in items:
        if stock_item_matches(item, name, symbol, market):
            item["relationType"] = "direct"
            item["relationTopic"] = company
    return items


def fetch_stock_news(args):
    symbol = clean_text(args[0] if len(args) > 0 else "").upper()
    market = clean_text(args[1] if len(args) > 1 else "KRX").upper() or "KRX"
    requested_name = clean_text(args[2] if len(args) > 2 else symbol) or symbol
    name = stock_canonical_name(requested_name, symbol, market)
    limit = int(args[3]) if len(args) > 3 and args[3].isdigit() else 30
    refresh_mode = args[4].lower() if len(args) > 4 else "cache"
    force = refresh_mode in ("1", "true", "force")
    path = stock_cache_path(market, symbol, name)
    cached = load_stock_cache(path, name, symbol, market, limit)
    now = int(time.time())
    same_hour = cached and int(cached.get("updatedAt", 0)) // 3600 == now // 3600
    if cached and not force and same_hour:
        print(json.dumps(dict(cached, ok=True, cached=True, stale=False), ensure_ascii=False))
        return
    try:
        items = recent_stock_items(fetch_stock_feed(name, symbol, market), name, symbol, market, limit, now)
        for item in items:
            item["stockSymbol"] = symbol
            item["stockMarket"] = market
            item["stockName"] = name
        attention_history, attention_baseline = stock_attention_history(cached, items, now)
        payload = {
            "ok": True,
            "symbol": symbol,
            "market": market,
            "name": name,
            "updatedAt": now,
            "cacheVersion": STOCK_CACHE_VERSION,
            "relevanceVersion": STOCK_CACHE_VERSION,
            "cached": False,
            "stale": False,
            "attentionHistory": attention_history,
            "attentionBaseline": attention_baseline,
            "items": items,
        }
        save_stock_cache(path, payload)
        print(json.dumps(payload, ensure_ascii=False))
    except Exception as error:
        if cached:
            print(json.dumps(dict(cached, ok=True, cached=True, stale=True, warning=str(error)), ensure_ascii=False))
            return
        print(json.dumps({
            "ok": False,
            "symbol": symbol,
            "market": market,
            "name": name,
            "error": str(error),
        }, ensure_ascii=False))


def ollama_models():
    if not shutil.which("ollama"):
        return []
    try:
        proc = subprocess.run(["ollama", "list"], text=True, capture_output=True, timeout=6)
    except Exception:
        return []
    if proc.returncode != 0:
        return []
    names = []
    for line in proc.stdout.splitlines()[1:]:
        parts = line.split()
        if parts:
            names.append(parts[0])
    return names


def print_models():
    models = ollama_models()
    print(json.dumps({"ok": True, "models": models, "default": models[0] if models else "qwen2.5:3b"}, ensure_ascii=False))


def clean_model_output(value):
    value = (value or "").strip()
    value = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", value)
    value = re.sub(r"\x9b[0-?]*[ -/]*[@-~]", "", value)
    value = re.sub(r"\ufffd(?:\[[0-?]*[ -/]*[@-~]|[A-Za-z])?", "", value)
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", value)
    value = re.sub(r"(?is)<think>.*?</think>", "", value)
    value = re.sub(r"(?is)```(?:json)?", "", value)
    value = re.sub(r"(?im)^(>>>|\.\.\.)\s?.*$", "", value)
    value = re.sub(r"(?is)^.*?thinking\.\.\.", "", value)
    value = re.sub(r"(?is)^.*?\.\.\.done thinking\.", "", value)
    value = re.sub(r"(?im)^thinking\.\.\.$", "", value)
    value = re.sub(r"(?im)^\.\.\.done thinking\.$", "", value)
    value = re.sub(r"(?is)<think>.*?</think>", "", value).strip()
    return value


def clean_summary_value(value):
    text = clean_text(str(value or ""))
    text = re.sub(r"^\s*(?:요약|summary|결과|answer)\s*[:：-]\s*", "", text, flags=re.I)
    text = re.sub(r"^\s*(?:[-*•]+|\d+\s*[|:：.)-]|기사\s*\d+\s*[:：.)|-]?|id\s*\d+\s*[:：.)|-]?)\s*", "", text, flags=re.I)
    text = re.sub(r"(?<=[.!?。])\s*[12]\s*[.)|:：-]?\s*(?=[가-힣])", " ", text)
    text = re.sub(r"\s*\([^)]*(?:approx|character|char|글자)[^)]*\)\s*$", "", text, flags=re.I)
    text = re.sub(r"\s*\([^)]*[A-Za-z][^)]*\)\s*$", "", text)
    text = text.lstrip(" \t\r\n\"'`“”‘’.,;:·…-")
    text = text.strip(" \t\r\n\"'`")
    if not text:
        return ""
    if not re.search(r"[가-힣]", text):
        return ""
    lowered = text.lower()
    if text[0] in "[{" or "https://" in lowered or '"id"' in lowered or "'id'" in lowered:
        return ""
    if len(re.findall(r"\b[A-Za-z]{3,}\b", text)) > 1:
        return ""
    if lowered in {"summary", "요약", "none", "null"}:
        return ""
    if any(marker in lowered for marker in (
        "thinking process",
        "desired output",
        "final output",
        "self-check",
        "analyze the request",
        "deconstruct",
        "draft the summary",
        "language:",
        "korean",
        "approx",
        "character",
        "slightly over",
        "role:",
        "do not",
        "core noun",
        "from the title",
        "fragment",
        "like just",
        "output",
        "the ",
    )):
        return ""
    if any(marker in text for marker in ("뉴스 요약기", "요약 형식", "출력 형식", "사고 과정")):
        return ""
    return text[:520]


def signal_len(value):
    return len(re.findall(r"[0-9A-Za-z가-힣]", value or ""))


def keyword_set(value):
    text = clean_text(value)
    words = set()
    for word in re.findall(r"[A-Za-z0-9가-힣]{2,}", text):
        if len(word) < 2:
            continue
        if word in {"뉴스", "기사", "관련", "이번", "대한", "위해", "통해", "따라", "밝혔다", "전했다", "했습니다", "있습니다"}:
            continue
        words.add(word.lower())
    return words


def title_overlap(summary, title):
    title_words = keyword_set(title)
    if not title_words:
        return 0
    summary_words = keyword_set(summary)
    return len(title_words & summary_words)


def fragmentary_summary(value):
    text = clean_summary_value(value)
    if not text:
        return True
    compact = re.sub(r"\s+", "", text)
    first = re.split(r"\s+", text, maxsplit=1)[0].strip(".,;:·…!?\"'“”‘’")
    if signal_len(text) < 18:
        return True
    if text.startswith(("며", "으며", "면서", "했고", "하고 ", "고 ", "했다", "됐다", "있다", "없다", "운용할 것을", "운용하기로", "추진하기로", "전장보다", "전날보다", "전일보다", "관련 ", "라고", "라는")):
        return True
    if re.fullmatch(r"[가-힣]{1,2}(?:은|는|이|가|을|를|의|에|도|만|로|으로)?", first):
        return True
    if re.fullmatch(r"[가-힣]{1,8}(?:했다|됐다|였다|밝혔다|전했다|말했다|설명했다|마무리했다|했습니다|됐습니다|였습니다|밝혔습니다|전했습니다)", first):
        return True
    if re.fullmatch(r"[가-힣\s]*(?:했다|됐다|있다|없다)\.?", compact) and signal_len(compact) < 18:
        return True
    return False


def has_sentence_ending(value):
    return bool(re.search(r"(다|했다|된다|됐다|있다|없다|이다|냈다|밝혔다|전했다|제기됐다|이어졌다)[.!?。]?$", value or ""))


def complete_summary_value(value):
    text = clean_summary_value(value)
    if not text:
        return ""
    if not has_sentence_ending(text):
        return ""
    return text if text.endswith((".", "!", "?", "。")) else text + "."


def usable_summary_value(value):
    text = complete_summary_value(value)
    if not text or fragmentary_summary(text):
        return ""
    return text


def usable_for_item(summary, item):
    text = usable_summary_value(summary)
    if not text:
        return ""
    title = clean_title_value(item.get("title", ""))
    body = clean_text(str(item.get("summary", "")))
    if len(body) >= 80 and signal_len(text) < 45:
        return ""
    if title and title_overlap(text, title) == 0:
        body_words = keyword_set(body[:900])
        text_words = keyword_set(text)
        if len(body_words & text_words) < 2:
            return ""
    return text


def row_summary_value(row):
    for key in ("summary", "요약", "text", "result", "content"):
        if key in row:
            text = usable_summary_value(row.get(key))
            if text:
                return text
    return ""


def summary_rows(value):
    if isinstance(value, dict):
        if all(isinstance(k, str) for k in value.keys()) and all(isinstance(v, str) for v in value.values()):
            value = [{"id": k, "summary": v} for k, v in value.items()]
        else:
            value = value.get("items") or value.get("summaries") or value.get("results") or []
    if not isinstance(value, list):
        return []
    rows = []
    for idx, row in enumerate(value):
        if isinstance(row, dict) and row.get("id") is not None and row_summary_value(row):
            rows.append(row)
        elif isinstance(row, str):
            text = usable_summary_value(row)
            if text:
                rows.append({"id": str(idx), "summary": text})
    return rows


def extract_json(value):
    value = clean_model_output(value)
    decoder = json.JSONDecoder()
    best = None
    for idx, ch in enumerate(value):
        if ch not in "[{":
            continue
        try:
            obj, _ = decoder.raw_decode(value[idx:])
        except Exception:
            continue
        if summary_rows(obj):
            best = obj
    if best is not None:
        return best
    raise ValueError("json not found")


def plain_summary_lines(value):
    cleaned = clean_model_output(value)
    lines = []
    for line in cleaned.splitlines():
        line = line.strip()
        if not line:
            continue
        if (
            line[0] in "[{"
            or "https://" in line
            or any(ch in line for ch in "{}[]")
            or "\\\"" in line
            or '":' in line
            or '"title"' in line
            or '"body"' in line
            or '"source"' in line
        ):
            continue
        text = usable_summary_value(line)
        if text:
            lines.append(text)
    if not lines:
        text = usable_summary_value(cleaned)
        if text:
            lines.append(text)
    return lines


def add_numbered_rows(rows, pairs, limit):
    if not pairs:
        return
    indexes = [idx for idx, _ in pairs]
    one_based = 0 not in indexes and min(indexes) >= 1 and max(indexes) <= limit
    for raw_idx, raw in pairs:
        idx = raw_idx - 1 if one_based else raw_idx
        if idx < 0 or idx >= limit:
            continue
        text = usable_summary_value(raw)
        if text:
            rows[str(idx)] = text


def numbered_summary_rows(value, limit):
    cleaned = clean_model_output(value)
    rows = {}
    pairs = []
    for line in cleaned.splitlines():
        line = line.strip()
        m = re.match(r"^(\d+)\s*[|:：.)-]\s*(.+)$", line)
        if not m:
            continue
        pairs.append((int(m.group(1)), m.group(2)))
    add_numbered_rows(rows, pairs, limit)
    if rows:
        return rows
    pairs = [(int(idx_s), raw) for idx_s, raw in re.findall(r"(\d+)\s*\|\s*([^|\n]+?)(?=\s+\d+\s*\||$)", cleaned)]
    add_numbered_rows(rows, pairs, limit)
    return rows


def ensure_sentence(value):
    text = clean_summary_value(value)
    if not text:
        return ""
    text = re.sub(r"\s*(관련\s*)?기사$", "", text).strip()
    text = text.rstrip(".,;:·- ")
    if has_sentence_ending(text):
        return text if text.endswith((".", "!", "?", "。")) else text + "."
    if re.search(r"하자[\"'”’]?$", text):
        return text + "고 제안했다."
    if text.endswith(("에 대한", "와 관련한", "과 관련한", "를 둘러싼", "을 둘러싼")):
        return text + " 논의가 이어지고 있다."
    if text.endswith(("논란", "의혹", "쟁점", "우려", "검토", "논의")):
        return text + "이 이어지고 있다."
    return text + "라고 전했다."


def clean_title_value(value):
    text = clean_text(str(value or ""))
    text = re.sub(r"^\s*(?:\[[^\]]+\]|【[^】]+】)\s*", "", text)
    text = re.sub(r"\s+", " ", text).strip(" -·|")
    return text


def fallback_summary(item):
    body = clean_text(str(item.get("summary", "")))
    title = clean_title_value(item.get("title", ""))
    candidates = []
    if body:
        parts = re.split(r"(?<=[.!?。])\s+|[。]", body)
        joined = " ".join([p.strip() for p in parts[:2] if p.strip()])
        if not fragmentary_summary(joined):
            candidates.append(joined)
    if title:
        candidates.append(title)
    for candidate in candidates:
        text = ensure_sentence(candidate)
        if text and not fragmentary_summary(text):
            return text[:420]
    return ""


def fallback_results(items, id_map):
    results = []
    for idx, item in enumerate(items):
        original_id = id_map.get(str(idx), str(idx))
        summary = fallback_summary(item)
        if not summary:
            title = clean_title_value(item.get("title", ""))
            if title:
                summary = ensure_sentence(title)
        if summary:
            results.append({"id": original_id, "summary": summary[:520]})
    return results


def summarize(args):
    model = args[0].strip() if args else "qwen2.5:3b"
    text = args[1] if len(args) > 1 else ""
    if not shutil.which("ollama"):
        print("ollama 명령을 찾을 수 없습니다.")
        return 1
    prompt = (
        "아래 사용자가 선택한 기사만 한국어로 요약해줘.\n"
        "핵심 사실과 맥락을 3~5개 bullet로 짧게 정리해.\n"
        "추측하지 말고 기사 목록에 있는 내용만 사용해.\n"
        "사고 과정을 출력하지 마.\n\n"
        f"{text[:6000]}"
    )
    env = os.environ.copy()
    env["OLLAMA_KEEP_ALIVE"] = "0"
    try:
        proc = subprocess.run(["ollama", "run", model], input=prompt, text=True, capture_output=True, timeout=120, env=env)
    except subprocess.TimeoutExpired:
        print("요약 시간이 초과되었습니다.")
        return 1
    except Exception as e:
        print(str(e))
        return 1
    output = clean_model_output(proc.stdout or proc.stderr or "")
    print(output if output else "요약 결과가 비어 있습니다.")
    return 0 if proc.returncode == 0 else proc.returncode


def summarize_batch(args):
    model = args[0].strip() if args else "qwen2.5:3b"
    raw = args[1] if len(args) > 1 else "[]"
    if not shutil.which("ollama"):
        print(json.dumps({"ok": False, "error": "ollama 명령을 찾을 수 없습니다."}, ensure_ascii=False))
        return 1
    try:
        items = json.loads(raw)
        if not isinstance(items, list) or len(items) == 0:
            raise ValueError("empty")
    except Exception:
        print(json.dumps({"ok": False, "error": "요약할 기사 데이터가 없습니다."}, ensure_ascii=False))
        return 2
    compact = []
    id_map = {}
    prepared_items = []
    for item in items[:8]:
        short_id = str(len(compact))
        body = clean_text(str(item.get("summary", "")))
        article_body = fetch_article_text(str(item.get("url", "")))
        if len(article_body) > len(body) + 120:
            body = article_body
        prepared = dict(item)
        prepared["summary"] = body
        prepared_items.append(prepared)
        id_map[short_id] = str(item.get("id", ""))[:500]
        compact.append({
            "id": short_id,
            "source": str(item.get("source", ""))[:60],
            "category": str(item.get("category", ""))[:60],
            "title": str(item.get("title", ""))[:220],
            "body": body[:4800],
        })
    article_lines = []
    for row in compact:
        article_lines.append(
            f"{row['id']}\n"
            f"제목: {row['title']}\n"
            f"내용: {row['body'] or row['title']}"
        )
    if len(compact) == 1:
        prompt = (
            "다음 뉴스를 한국어 두 문장으로 요약하세요.\n"
            "핵심 사실과 중요한 배경 또는 후속 상황을 자연스럽게 담으세요.\n"
            "제목을 그대로 반복하지 말고 본문에 없는 내용은 쓰지 마세요.\n\n"
            + article_lines[0]
        )
    else:
        prompt = (
            "다음 뉴스를 각각 한국어 두 문장으로 요약하세요.\n"
            "형식: 번호|요약\n"
            "핵심 사실과 중요한 배경 또는 후속 상황을 자연스럽게 담으세요.\n"
            "제목을 그대로 반복하지 말고 본문에 없는 내용은 쓰지 마세요.\n\n"
            + "\n\n".join(article_lines)
        )
    env = os.environ.copy()
    env["OLLAMA_KEEP_ALIVE"] = "0"
    try:
        proc = subprocess.run(["ollama", "run", model], input=prompt, text=True, capture_output=True, timeout=90, env=env)
    except subprocess.TimeoutExpired:
        results = fallback_results(prepared_items, id_map)
        print(json.dumps({"ok": True, "items": results} if results else {"ok": False, "error": "요약 시간이 초과되었습니다."}, ensure_ascii=False))
        return 0 if results else 1
    except Exception as e:
        results = fallback_results(prepared_items, id_map)
        print(json.dumps({"ok": True, "items": results} if results else {"ok": False, "error": str(e)}, ensure_ascii=False))
        return 0 if results else 1
    output = proc.stdout or proc.stderr or ""
    try:
        if len(compact) == 1:
            direct = usable_for_item(output, prepared_items[0])
            if direct:
                print(json.dumps({"ok": True, "items": [{"id": id_map.get("0", "0"), "summary": direct}]}, ensure_ascii=False))
                return 0
        candidates = {}

        def candidate_index(rid):
            rid = str(rid)
            if rid in id_map:
                return int(rid)
            for key, original in id_map.items():
                if rid == original:
                    return int(key)
            return None

        numbered = numbered_summary_rows(output, len(compact))
        for rid, summary in numbered.items():
            idx = candidate_index(rid)
            if idx is not None:
                candidates[idx] = summary
        if not candidates:
            try:
                parsed = summary_rows(extract_json(output))
                for row in parsed:
                    rid = str(row.get("id", ""))
                    summary = row_summary_value(row)
                    idx = candidate_index(rid)
                    if idx is not None and summary:
                        candidates[idx] = summary
            except Exception:
                lines = plain_summary_lines(output)
                for idx, summary in enumerate(lines[:len(compact)]):
                    candidates[idx] = summary
        results = []
        for idx, item in enumerate(prepared_items):
            original_id = id_map.get(str(idx), str(idx))
            summary = usable_for_item(candidates.get(idx, ""), item) or fallback_summary(item)
            if summary:
                results.append({"id": original_id, "summary": summary})
        if not results:
            results = fallback_results(prepared_items, id_map)
        if not results:
            raise ValueError("empty summary")
        print(json.dumps({"ok": True, "items": results}, ensure_ascii=False))
        return 0
    except Exception:
        results = fallback_results(prepared_items, id_map)
        if results:
            print(json.dumps({"ok": True, "items": results}, ensure_ascii=False))
            return 0
        error = clean_summary_value(output)
        print(json.dumps({"ok": False, "error": error or "Summary unavailable."}, ensure_ascii=False))
        return 1


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    if cmd == "fetch":
        fetch_news(sys.argv[2:])
        return 0
    if cmd == "stock-fetch":
        fetch_stock_news(sys.argv[2:])
        return 0
    if cmd == "models":
        print_models()
        return 0
    if cmd == "summarize":
        return summarize(sys.argv[2:])
    if cmd == "summarize-batch":
        return summarize_batch(sys.argv[2:])
    print(json.dumps({"ok": False, "error": "unknown command"}, ensure_ascii=False))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
