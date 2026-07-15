#!/usr/bin/env python3
"""Calendar widget backend — fetch ICS subscriptions, expand recurrences,
print upcoming events as one JSON line.

Usage: calendar-fetch.py '<sources-json>' [days]
  sources-json: [{"name": "...", "url": "https://... or webcal://...", "color": "purple"}]
  days: window size from today (default 42)

stdout (exactly one line):
  {"status":"ok","events":[...],"failed":[{"name":..,"error":..}]}
  event: {src, cal, color, title, location, allDay, startMs, endMs}

Works with Google Calendar's "Secret address in iCal format" and iCloud's
public-share (webcal://) links — anything that serves an ICS file. Recurrence
(RRULE/EXDATE/RECURRENCE-ID overrides) is expanded with dateutil. Always exits
0 and reports problems via the JSON so the QML side never parses exit codes.
"""
import json
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None
from dateutil import rrule as du_rrule

LOCAL = datetime.now().astimezone().tzinfo
MAX_OCCURRENCES = 120   # per recurring event, within the window
MAX_EVENTS = 400        # total, after sorting


def out(obj):
    print(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))
    sys.exit(0)


def fetch(url, timeout=15):
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-calendar/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def unfold(text):
    """ICS line unfolding: continuation lines start with a space or tab."""
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    res = []
    for ln in lines:
        if ln[:1] in (" ", "\t") and res:
            res[-1] += ln[1:]
        else:
            res.append(ln)
    return res


def split_prop(line):
    """'NAME;P=V;Q=W:value' -> (NAME, {P: V}, value), colon-in-quotes safe."""
    inq = False
    for i, ch in enumerate(line):
        if ch == '"':
            inq = not inq
        elif ch == ":" and not inq:
            head, value = line[:i], line[i + 1:]
            break
    else:
        return None
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def unescape(s):
    return (s.replace("\\n", "\n").replace("\\N", "\n")
             .replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\"))


def parse_dt(value, params):
    """One ICS date/date-time -> (aware local datetime, is_all_day)."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d.replace(tzinfo=LOCAL), True
    is_utc = value.endswith("Z")
    dt = datetime.strptime(value.rstrip("Z"), "%Y%m%dT%H%M%S")
    if is_utc:
        dt = dt.replace(tzinfo=timezone.utc)
    elif "TZID" in params and ZoneInfo is not None:
        try:
            dt = dt.replace(tzinfo=ZoneInfo(params["TZID"]))
        except Exception:
            dt = dt.replace(tzinfo=LOCAL)
    else:
        dt = dt.replace(tzinfo=LOCAL)
    return dt.astimezone(LOCAL), False


def parse_duration(s):
    m = re.fullmatch(r"([+-]?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", s.strip())
    if not m:
        return timedelta(0)
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, se = (int(x) if x else 0 for x in m.groups()[1:])
    return sign * timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=se)


def normalize_until(rule):
    """Make UNTIL timezone-aware so it can't clash with an aware DTSTART."""
    rule = re.sub(r"(UNTIL=\d{8}T\d{6})(?![Z\d])", r"\1Z", rule)
    rule = re.sub(r"(UNTIL=\d{8})(?![TZ\d])", r"\1T235959Z", rule)
    return rule


def parse_vevents(text):
    """All VEVENT blocks as raw property lists [(name, params, value), ...]."""
    events, cur = [], None
    for line in unfold(text):
        if line == "BEGIN:VEVENT":
            cur = []
        elif line == "END:VEVENT":
            if cur is not None:
                events.append(cur)
            cur = None
        elif cur is not None:
            p = split_prop(line)
            if p:
                cur.append(p)
    return events


def expand(props, win_start, win_end):
    """One VEVENT -> occurrence dicts within the window (before overrides)."""
    ev = {"summary": "", "location": "", "status": "", "uid": "",
          "dtstart": None, "allday": False, "dtend": None, "duration": None,
          "rrule": None, "exdates": [], "recurrence_id": None}
    for name, params, value in props:
        if name == "SUMMARY":
            ev["summary"] = unescape(value).strip()
        elif name == "LOCATION":
            ev["location"] = unescape(value).strip()
        elif name == "STATUS":
            ev["status"] = value.strip().upper()
        elif name == "UID":
            ev["uid"] = value.strip()
        elif name == "DTSTART":
            ev["dtstart"], ev["allday"] = parse_dt(value, params)
        elif name == "DTEND":
            ev["dtend"] = parse_dt(value, params)[0]
        elif name == "DURATION":
            ev["duration"] = parse_duration(value)
        elif name == "RRULE":
            ev["rrule"] = value.strip()
        elif name == "EXDATE":
            for v in value.split(","):
                try:
                    ev["exdates"].append(parse_dt(v, params)[0])
                except Exception:
                    pass
        elif name == "RECURRENCE-ID":
            try:
                ev["recurrence_id"] = parse_dt(value, params)[0]
            except Exception:
                pass

    if ev["dtstart"] is None:
        return ev, []
    if ev["dtend"] is not None:
        dur = ev["dtend"] - ev["dtstart"]
    elif ev["duration"] is not None:
        dur = ev["duration"]
    else:
        dur = timedelta(days=1) if ev["allday"] else timedelta(0)
    if ev["allday"] and dur < timedelta(days=1):
        dur = timedelta(days=1)
    ev["dur"] = dur

    if ev["status"] == "CANCELLED":
        return ev, []

    if not ev["rrule"]:
        s = ev["dtstart"]
        if s + dur > win_start and s < win_end:
            return ev, [s]
        return ev, []

    try:
        rset = du_rrule.rruleset()
        rset.rrule(du_rrule.rrulestr(normalize_until(ev["rrule"]), dtstart=ev["dtstart"]))
        for x in ev["exdates"]:
            rset.exdate(x)
        occs = rset.between(win_start - dur, win_end, inc=True)
        return ev, occs[:MAX_OCCURRENCES]
    except Exception:
        # Exotic rule dateutil can't take — fall back to the first instance.
        s = ev["dtstart"]
        if s + dur > win_start and s < win_end:
            return ev, [s]
        return ev, []


def main():
    try:
        sources = json.loads(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].strip() else []
    except Exception:
        out({"status": "error", "message": "bad sources JSON"})
    days = 42
    if len(sys.argv) > 2:
        try:
            days = max(1, min(120, int(sys.argv[2])))
        except ValueError:
            pass
    if not isinstance(sources, list) or not sources:
        out({"status": "ok", "events": [], "failed": []})

    today = datetime.now(LOCAL).replace(hour=0, minute=0, second=0, microsecond=0)
    win_start = today - timedelta(days=1)
    win_end = today + timedelta(days=days)

    events, failed = [], []
    for si, src in enumerate(sources):
        name = str(src.get("name", "Calendar"))
        color = str(src.get("color", "blue"))
        url = str(src.get("url", "")).strip()
        if not url:
            continue
        try:
            text = fetch(url)
        except Exception as e:
            failed.append({"name": name, "error": type(e).__name__})
            continue

        overridden = set()   # (uid, instant-epoch) replaced by RECURRENCE-ID events
        parsed = []
        for props in parse_vevents(text):
            ev, occs = expand(props, win_start, win_end)
            parsed.append((ev, occs))
            if ev["recurrence_id"] is not None and ev["uid"]:
                overridden.add((ev["uid"], ev["recurrence_id"].timestamp()))

        for ev, occs in parsed:
            for s in occs:
                if ev["recurrence_id"] is None and ev["rrule"] and \
                        (ev["uid"], s.timestamp()) in overridden:
                    continue
                e = s + ev["dur"]
                if e <= win_start or s >= win_end:
                    continue
                events.append({
                    "src": si, "cal": name, "color": color,
                    "title": ev["summary"] or "Untitled",
                    "location": ev["location"],
                    "allDay": ev["allday"],
                    "startMs": int(s.timestamp() * 1000),
                    "endMs": int(e.timestamp() * 1000),
                })

    events.sort(key=lambda e: (e["startMs"], e["endMs"]))
    out({"status": "ok", "events": events[:MAX_EVENTS], "failed": failed})


if __name__ == "__main__":
    main()
