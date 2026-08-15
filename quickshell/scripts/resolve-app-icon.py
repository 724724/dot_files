#!/usr/bin/env python3
import configparser
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

IMAGE_SUFFIXES = {".png", ".svg", ".svgz", ".xpm", ".ico", ".jpg", ".jpeg", ".webp"}
INDEX_CACHE_VERSION = 1
INDEX_RECHECK_SECONDS = 1.0
_MEMORY_THEME_INDICES = {}
_MEMORY_DESKTOP_ENTRIES = {"signature": None, "entries": []}


def usable(path):
    try:
        return path.is_file() and path.stat().st_size > 0 and path.suffix.lower() in IMAGE_SUFFIXES
    except OSError:
        return False


def direct_path(value):
    if not value:
        return None
    if value.startswith("file://"):
        path = Path(unquote(urlparse(value).path))
        return path if usable(path) else None
    if value.startswith("image://icon/"):
        return None
    path = Path(os.path.expanduser(value))
    return path if path.is_absolute() and usable(path) else None


def clean_icon_name(value):
    if value.startswith("image://icon/"):
        value = value[len("image://icon/"):]
        value = value.split("?", 1)[0]
    if value.startswith("file://") or value.startswith("/"):
        return ""
    return unquote(value).strip()


def desktop_dirs():
    home = Path.home()
    return [
        home / ".local/share/applications",
        home / ".local/share/flatpak/exports/share/applications",
        Path("/var/lib/flatpak/exports/share/applications"),
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
    ]


def read_desktop(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
        return parser["Desktop Entry"] if parser.has_section("Desktop Entry") else None
    except (OSError, UnicodeError, configparser.Error):
        return None


def cached_desktop_entries():
    directories = desktop_dirs()
    signature = []
    for directory in directories:
        try:
            stat = directory.stat()
            signature.append((str(directory), stat.st_mtime_ns))
        except OSError:
            signature.append((str(directory), None))
    if _MEMORY_DESKTOP_ENTRIES["signature"] == signature:
        return _MEMORY_DESKTOP_ENTRIES["entries"]

    entries = []
    seen = set()
    for directory in directories:
        if not directory.is_dir():
            continue
        for path in directory.glob("*.desktop"):
            if path in seen:
                continue
            seen.add(path)
            entry = read_desktop(path)
            if entry is None:
                continue
            try:
                command = shlex.split(entry.get("Exec", ""))
            except ValueError:
                command = []
            entries.append({
                "path": path,
                "icon": entry.get("Icon", "").strip(),
                "startup": entry.get("StartupWMClass", "").lower().strip(),
                "name": entry.get("Name", "").lower().strip(),
                "command": command,
                "executable": Path(command[0]).name.lower() if command else "",
            })
    _MEMORY_DESKTOP_ENTRIES["signature"] = signature
    _MEMORY_DESKTOP_ENTRIES["entries"] = entries
    return entries


def matching_desktop(desktop_id, app_class, icon_name):
    wanted_id = desktop_id.removesuffix(".desktop").lower()
    wanted_class = app_class.lower().strip()
    wanted_icon = clean_icon_name(icon_name).lower()
    best = None
    best_score = -1
    for entry in cached_desktop_entries():
        path = entry["path"]
        entry_icon = entry["icon"]
        stem = path.stem.lower()
        startup = entry["startup"]
        name = entry["name"]
        command = entry["command"]
        executable = entry["executable"]
        score = 0
        if wanted_id and stem == wanted_id:
            score += 100
        if wanted_class and wanted_class in {startup, name, stem, executable}:
            score += 80
        if wanted_class and (wanted_class in stem or stem in wanted_class):
            score += 30
        if wanted_icon and clean_icon_name(entry_icon).lower() == wanted_icon:
            score += 20
        if score > best_score:
            best_score = score
            best = (entry_icon, command)
    return best if best_score > 0 else ("", [])


def size_score(path):
    score = 0
    fixed_size = False
    for part in path.parts:
        if part == "scalable":
            score = max(score, 8192)
        match = re.fullmatch(r"(\d+)x(\d+)(?:@\d+x)?", part)
        if match:
            fixed_size = True
            score = max(score, min(int(match.group(1)), int(match.group(2))))
        elif re.fullmatch(r"\d+", part):
            fixed_size = True
            score = max(score, int(part))
    # An SVG stored in a fixed-size directory is still the artwork designed
    # for that size. Do not tie places/16/user-trash.svg with the theme's
    # detailed places/scalable/user-trash.svg merely because both are vectors.
    if path.suffix.lower() in {".svg", ".svgz"} and not fixed_size:
        score = max(score, 4096)
    return score


def find_named(name, roots):
    if not name:
        return None
    target_names = {name.lower() + suffix for suffix in IMAGE_SUFFIXES}
    matches = []
    for root in roots:
        if not root.is_dir():
            continue
        try:
            for path in root.rglob("*"):
                if path.name.lower() in target_names and usable(path):
                    matches.append(path)
        except OSError:
            continue
        if matches:
            return max(matches, key=size_score)
    return None


def find_in_roots(names, roots):
    """Prefer a theme root before trying the next root's exact name."""
    for root in roots:
        for name in names:
            match = find_named(name, [root])
            if match:
                return match
    return None


def theme_directory_names(root):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(root / "index.theme", encoding="utf-8")
    except (OSError, UnicodeError, configparser.Error):
        return []
    if not parser.has_section("Icon Theme"):
        return []
    names = []
    for option in ("Directories", "ScaledDirectories"):
        value = parser.get("Icon Theme", option, fallback="")
        for item in value.split(","):
            item = item.strip()
            if item and item not in names:
                names.append(item)
    return names


def theme_signature(roots):
    """Cheaply notice installs/removals without walking every icon file."""
    signature = {}
    for root in roots:
        paths = [root, root / "index.theme"]
        paths.extend(root / name for name in theme_directory_names(root))
        for path in paths:
            try:
                stat = path.stat()
                signature[str(path)] = [stat.st_mtime_ns, stat.st_size]
            except OSError:
                signature[str(path)] = None
    return signature


def icon_key(path):
    lower = path.name.casefold()
    for suffix in IMAGE_SUFFIXES:
        if lower.endswith(suffix):
            return lower[:-len(suffix)]
    return ""


def build_theme_index(roots):
    icons = {}
    # Preserve XDG root priority. Inside one root, prefer scalable/high-resolution
    # art using the same scoring rules as the uncached resolver.
    for root in roots:
        if not root.is_dir():
            continue
        local = {}
        try:
            paths = root.rglob("*")
            for path in paths:
                key = icon_key(path)
                if not key or not usable(path):
                    continue
                current = local.get(key)
                if current is None or size_score(path) > size_score(current):
                    local[key] = path
        except OSError:
            continue
        for key, path in local.items():
            if key not in icons:
                icons[key] = str(path)
    return icons


def theme_cache_path(theme_name, roots):
    override = os.environ.get("QS_ICON_CACHE_DIR", "").strip()
    cache_root = Path(override) if override else Path(
        os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
    ) / "quickshell" / "app-icon-index"
    identity = theme_name + "\0" + "\0".join(str(root) for root in roots)
    digest = hashlib.sha256(identity.encode("utf-8", errors="surrogatepass")).hexdigest()[:16]
    return cache_root / (digest + ".json")


def write_theme_cache(path, payload):
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
            os.replace(temporary, path)
        except Exception:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise
    except (OSError, TypeError, ValueError):
        # A read-only cache must never prevent the icon from resolving.
        pass


def load_theme_index(theme_name, roots, force_rebuild=False):
    memory_key = (theme_name, tuple(str(root) for root in roots))
    memory = _MEMORY_THEME_INDICES.get(memory_key)
    now = time.monotonic()
    if (not force_rebuild and memory
            and now - memory.get("checkedAt", 0) < INDEX_RECHECK_SECONDS):
        return memory["icons"]
    signature = theme_signature(roots)
    if (not force_rebuild and memory
            and memory.get("signature") == signature):
        memory["checkedAt"] = now
        return memory["icons"]
    path = theme_cache_path(theme_name, roots)
    if not force_rebuild:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if (payload.get("version") == INDEX_CACHE_VERSION
                    and payload.get("signature") == signature
                    and isinstance(payload.get("icons"), dict)):
                _MEMORY_THEME_INDICES[memory_key] = {
                    "signature": signature,
                    "icons": payload["icons"],
                    "checkedAt": now,
                }
                return payload["icons"]
        except (OSError, UnicodeError, json.JSONDecodeError, AttributeError):
            pass
    icons = build_theme_index(roots)
    write_theme_cache(path, {
        "version": INDEX_CACHE_VERSION,
        "theme": theme_name,
        "signature": signature,
        "icons": icons,
    })
    _MEMORY_THEME_INDICES[memory_key] = {
        "signature": signature,
        "icons": icons,
        "checkedAt": now,
    }
    return icons


def find_theme_icon(names, theme_name, roots):
    icons = load_theme_index(theme_name, roots)
    stale = False
    for name in names:
        value = icons.get(name.casefold())
        if value:
            path = Path(value)
            if usable(path):
                return path
            stale = True
    if stale:
        icons = load_theme_index(theme_name, roots, force_rebuild=True)
        for name in names:
            value = icons.get(name.casefold())
            if value and usable(Path(value)):
                return Path(value)
    return None


def configured_icon_theme():
    override = os.environ.get("QS_ICON_THEME", "").strip()
    if override:
        return override
    try:
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            check=False,
            capture_output=True,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    value = result.stdout.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value.strip()


def icon_bases():
    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    bases = [data_home / "icons"]
    bases.extend(Path(item) / "icons" for item in data_dirs.split(":") if item)
    bases.extend([
        home / ".local/share/flatpak/exports/share/icons",
        Path("/var/lib/flatpak/exports/share/icons"),
    ])
    unique = []
    for path in bases:
        if path not in unique:
            unique.append(path)
    return unique


def theme_roots(theme_name, bases):
    if not theme_name:
        return []
    return [base / theme_name for base in bases if (base / theme_name).is_dir()]


def inherited_themes(roots):
    for root in roots:
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.optionxform = str
        try:
            parser.read(root / "index.theme", encoding="utf-8")
            value = parser.get("Icon Theme", "Inherits", fallback="")
        except (OSError, UnicodeError, configparser.Error):
            continue
        if value:
            return [item.strip() for item in value.split(",") if item.strip()]
    return []


def theme_chain(theme_name, bases):
    queue = [theme_name] if theme_name else []
    seen = set()
    chain = []
    while queue:
        current = queue.pop(0)
        key = current.casefold()
        if not current or key in seen:
            continue
        seen.add(key)
        roots = theme_roots(current, bases)
        if roots:
            chain.append((current, roots))
            queue.extend(inherited_themes(roots))
    if "hicolor" not in seen:
        roots = theme_roots("hicolor", bases)
        if roots:
            chain.append(("hicolor", roots))
    return chain


def resolve_icon(icon_name, desktop_id, app_class, theme_name=None, chain=None):
    direct = direct_path(icon_name)
    if direct:
        return direct.resolve().as_uri()
    names = []
    for value in (icon_name, desktop_id.removesuffix(".desktop"), app_class):
        name = clean_icon_name(value)
        if name and name.lower() not in {item.lower() for item in names}:
            names.append(name)
    bases = icon_bases()
    if chain is None:
        chain = theme_chain(
            configured_icon_theme() if theme_name is None else theme_name,
            bases,
        )

    # Match aliases from the selected theme before accepting an exact hicolor
    # icon. For example, a dock item may advertise "vscode" while WhiteSur's
    # preferred artwork is reached through another application/class alias.
    selected_theme, selected_roots = chain[0] if chain else ("", [])
    match = find_theme_icon(names, selected_theme, selected_roots) if selected_roots else None
    if match:
        return match.resolve().as_uri()

    # Only inspect desktop files when the application's advertised names were
    # absent from the active theme. Most Dock/Launchpad requests now stay on the
    # cached O(1) path.
    desktop_icon, command = matching_desktop(desktop_id, app_class, icon_name)
    desktop_name = clean_icon_name(desktop_icon)
    if desktop_name and desktop_name.lower() not in {item.lower() for item in names}:
        names.append(desktop_name)
        match = find_theme_icon(names, selected_theme, selected_roots) if selected_roots else None
        if match:
            return match.resolve().as_uri()

    # An explicitly pinned file was handled above. A desktop entry's absolute
    # icon is weaker than the active theme, but stronger than inherited themes.
    direct = direct_path(desktop_icon)
    if direct:
        return direct.resolve().as_uri()

    for theme_name, roots in chain[1:]:
        match = find_theme_icon(names, theme_name, roots)
        if match:
            return match.resolve().as_uri()

    extra_roots = [
        Path("/var/lib/snapd/desktop/icons"),
        Path("/usr/share/pixmaps"),
    ]
    match = find_in_roots(names, extra_roots)
    if match:
        return match.resolve().as_uri()
    if command:
        executable = Path(command[0]).expanduser()
        if executable.is_absolute():
            match = find_in_roots(names, [executable.parent])
            if match:
                return match.resolve().as_uri()

    # Keep the QML side entirely off Quickshell's QIcon-backed image provider,
    # even when an application advertises a missing or malformed icon name.
    # A normal file URL gives QtQuick an ordinary image decode with well-defined
    # ownership across monitor teardown.
    fallback = None
    for theme_name, roots in chain:
        fallback = find_theme_icon(["application-x-executable"], theme_name, roots)
        if fallback:
            break
    if not fallback:
        fallback = find_in_roots(["application-x-executable"], extra_roots)
    if fallback:
        return fallback.resolve().as_uri()
    return ""


def serve():
    current_revision = None
    current_theme = ""
    current_chain = []
    for raw in sys.stdin:
        request_key = ""
        try:
            request = json.loads(raw)
            if not isinstance(request, dict):
                raise ValueError("request must be an object")
            request_key = str(request.get("key", ""))
            revision = request.get("themeRevision", 0)
            if revision != current_revision:
                current_theme = configured_icon_theme()
                current_chain = theme_chain(current_theme, icon_bases())
                current_revision = revision
            value = resolve_icon(
                str(request.get("iconName", "")),
                str(request.get("desktopId", "")),
                str(request.get("appClass", "")),
                theme_name=current_theme,
                chain=current_chain,
            )
            response = {"key": request_key, "value": value}
        except Exception as error:
            # Keep the long-lived resolver healthy if a single malformed desktop
            # entry or theme file fails. The caller can safely cache an empty
            # result for only that request and continue with the queue.
            response = {"key": request_key, "value": "", "error": str(error)}
        print(json.dumps(response, ensure_ascii=False, separators=(",", ":")), flush=True)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--server":
        serve()
        return
    icon_name = sys.argv[1] if len(sys.argv) > 1 else ""
    desktop_id = sys.argv[2] if len(sys.argv) > 2 else ""
    app_class = sys.argv[3] if len(sys.argv) > 3 else ""
    value = resolve_icon(icon_name, desktop_id, app_class)
    if value:
        print(value)


if __name__ == "__main__":
    main()
