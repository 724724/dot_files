#!/usr/bin/env python3
import email.utils
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone


UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 QuickshellNews/1.0"

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
    value = html.unescape(value or "")
    value = re.sub(r"<[^>]+>", " ", value)
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
        image = image_from_html(m.group(2))
        if len(title) < 5:
            alt = re.search(r'alt="([^"]+)"', m.group(2), re.I | re.S)
            title = clean_text(alt.group(1)) if alt else ""
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
            records[url] = {"title": "", "desc": "", "pub": "", "image": ""}
            order.append(url)
        record = records[url]
        if len(title) >= 5 and not record["title"]:
            record["title"] = title
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
