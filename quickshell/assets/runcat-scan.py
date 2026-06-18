#!/usr/bin/env python3
# Lists RunCat asset sets for SysUsageService.
# For each subfolder of the given dir, prints:  name|frame1,frame2,...|colored
# where `colored` is 1 if the first frame has real colour (so it should be shown
# as-is) or 0 if it's a monochrome silhouette (so it gets tinted to the bar fg).
import os, re, sys

base = sys.argv[1] if len(sys.argv) > 1 else "."
EXT = (".png", ".svg", ".jpg", ".jpeg", ".gif", ".webp")


def nat(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def is_colored(path):
    # SVG silhouettes are always treated as tintable.
    if path.lower().endswith(".svg"):
        return False
    try:
        from PIL import Image
        im = Image.open(path).convert("RGBA")
        w, h = im.size
        px = im.load()
        buckets = set()
        maxsat = 0.0
        for y in range(0, h, max(1, h // 40)):
            for x in range(0, w, max(1, w // 40)):
                r, g, b, a = px[x, y]
                if a > 40:
                    buckets.add((r // 40, g // 40, b // 40))
                    mx, mn = max(r, g, b), min(r, g, b)
                    if mx > 0:
                        s = (mx - mn) / mx
                        if s > maxsat:
                            maxsat = s
        return len(buckets) > 3 or maxsat > 0.25
    except Exception:
        return False


def mtime(n):
    try:
        return os.path.getmtime(os.path.join(base, n))
    except Exception:
        return 0.0

try:
    # By modification time so user-added sets keep their add order; the service
    # pins the built-ins (cat, horse) to the front regardless.
    names = sorted(os.listdir(base), key=mtime)
except Exception:
    sys.exit(0)

for name in names:
    d = os.path.join(base, name)
    if not os.path.isdir(d):
        continue
    files = sorted([f for f in os.listdir(d) if f.lower().endswith(EXT)], key=nat)
    if not files:
        continue
    colored = 1 if is_colored(os.path.join(d, files[0])) else 0
    print("%s|%s|%d" % (name, ",".join(files), colored))
