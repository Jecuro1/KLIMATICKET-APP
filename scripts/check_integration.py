#!/usr/bin/env python3
"""Static integration checks before a CI build (ios.yml runs this before anything is compiled):
 - duplicate top-level (non-private) type names per target (App = App/Sources + Shared, Widgets = Widgets/Sources + Shared)
 - required contract views exist
 - obviously unbalanced braces per file
 - sideload compatibility (docs/SETUP.md, docs/EXIT_ALARM.md §7): the app is re-signed by AltStore/SideStore with a free Apple ID,
   so the entitlements it is signed with (App/Supporting/*-Sideload.entitlements) may hold nothing that needs a paid account,
   UIBackgroundModes stay on a short list that needs no entitlement, and a framework that wants a usage string in Info.plist
   (AlarmKit, location, background location) finds it in project.yml
 - the widget extension and the code it shares with the app never reach the network: no URLSession, URLRequest,
   HafasClient or LiveDataService in Widgets/ or Shared/ (docs/WIDGETS.md §1 – widgets only read the App Group cache;
   Shared/ is compiled into the extension too, so a network call there would run inside it). Comments and the text of string
   literals do not count (code inside a \\( ) interpolation does). A file that genuinely needs one of these names goes into NETWORK_ALLOW with a reason."""
import os, re, sys, collections, glob, plistlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECL = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(public|internal|fileprivate|private|open)\s+)?(?:final\s+)?(struct|class|enum|actor|protocol)\s+([A-Za-z_]\w*)', re.M)
CONTRACT = ["DashboardView", "TripsView", "TripDetailView", "TripEditorView", "StationPickerView", "FavoritesManagerView",
            "StatisticsView", "TicketView", "OnboardingFlow", "AchievementsView", "SettingsView", "UpdateSheet", "WidgetGalleryView", "PlannerRootView"]

# Targets that must stay network-free and the names that mean "talks to the network".
NETWORK_FREE_DIRS = ["Widgets", "Shared"]
NETWORK_NAMES = re.compile(r'\b(URLSession|URLRequest|HafasClient|LiveDataService)\b')
# {repo-relative path: (names that file may use, reason)} – empty on purpose: today nothing in Widgets/ or Shared/ needs one.
NETWORK_ALLOW = {}


# Sideload compatibility. Everything outside these lists breaks the install with a free Apple ID (or is a decision the owner takes
# on purpose: add it here with the reason, not silently in project.yml).
ALLOWED_SIDELOAD_ENTITLEMENTS = {
    "com.apple.security.application-groups": "App Group of the widgets; AltStore/SideStore rewrite it for the free account",
}
ALLOWED_BACKGROUND_MODES = {
    "fetch": "background refresh of Live verfolgen (needs no entitlement)",
    "location": "Aussteige-Wecker and Fahrt aufzeichnen (needs no entitlement, the user's permission)",
}
# (what the code uses, the Info.plist key that must be in project.yml)
USAGE_STRINGS = [
    (re.compile(r'\bimport\s+AlarmKit\b'), "NSAlarmKitUsageDescription"),
    (re.compile(r'\bCLLocationManager\b'), "NSLocationWhenInUseUsageDescription"),
    (re.compile(r'\brequestAlwaysAuthorization\b'), "NSLocationAlwaysAndWhenInUseUsageDescription"),
]


def swift_files(*dirs, root=ROOT):
    for d in dirs:
        for base, _, files in os.walk(os.path.join(root, d)):
            for f in sorted(files):
                if f.endswith(".swift"):
                    yield os.path.join(base, f)


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def top_level_decls(path):
    src = read_text(path)
    # only consider declarations at column 0 (top level)
    out = []
    for m in DECL.finditer(src):
        line_start = src.rfind("\n", 0, m.start()) + 1
        if m.start() != line_start:
            continue
        access = m.group(1) or ""
        if access in ("private", "fileprivate"):
            continue
        out.append(m.group(3))
    return out, src


RAW_START = re.compile(r'#+"')


def _scan_string(src, i):
    """`src[i]` starts a string literal (single-line, triple-quoted, or either one behind `#`s). Returns the index after
    the literal and its code: what sits inside an interpolation is code (an interpolation with URLSession.shared in it
    uses the network), the rest is text. Newlines are kept in both, so line numbers stay."""
    n = len(src)
    hashes = 0
    while src[i] == "#":
        hashes += 1
        i += 1
    multiline = src.startswith('"""', i)
    quote = '"""' if multiline else '"'
    end = quote + "#" * hashes
    marker = "\\" + "#" * hashes   # the backslash of an escape or interpolation (`\#(` in a raw string)
    i += len(quote)
    code = []
    while i < n and not src.startswith(end, i):
        if src.startswith(marker + "(", i):
            start = i + len(marker)   # at the "("
            k, depth = start, 0
            while k < n:
                ch = src[k]
                if ch == '"' or (ch == "#" and RAW_START.match(src, k)):
                    k = _scan_string(src, k)[0]
                    continue
                k += 1
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        break
            code.append(" " + code_only(src[start + 1:k - 1] if depth == 0 else src[start + 1:k]) + " ")
            i = k
            continue
        if src.startswith(marker, i) and i + len(marker) < n:   # an escape: the next character is not the end
            if src[i + len(marker)] == "\n":
                code.append("\n")
            i += len(marker) + 1
            continue
        if src[i] == "\n":
            if not multiline:
                break   # an unterminated single-line string: stop at the line end
            code.append("\n")
        i += 1
    if src.startswith(end, i):
        i += len(end)
    return i, "".join(code)


def code_only(src):
    """`src` with comments and the text of string literals blanked out (newlines kept, so line numbers stay): what is left
    is code a compiler would act on, including the code inside string interpolations. Handles //, nested /* */, "…" with
    escapes, raw #"…"# and multi-line triple-quoted strings."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                i += 1
        elif two == "/*":
            depth = 1
            i += 2
            while i < n and depth:
                if src[i:i + 2] == "/*":
                    depth += 1
                    i += 2
                elif src[i:i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
        elif c == '"' or (c == "#" and RAW_START.match(src, i)):
            i, inner = _scan_string(src, i)
            out.append(" " + inner)
        else:
            out.append(c)
            i += 1
    return "".join(out)


def network_problems(root=ROOT, allow=None):
    """One message per use of a network type in Widgets/ or Shared/ (outside NETWORK_ALLOW)."""
    allow = NETWORK_ALLOW if allow is None else allow
    problems = []
    for path in swift_files(*NETWORK_FREE_DIRS, root=root):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        permitted = set(allow.get(rel, ((), ""))[0])
        code = code_only(read_text(path))
        for number, line in enumerate(code.split("\n"), 1):
            for m in NETWORK_NAMES.finditer(line):
                if m.group(1) not in permitted:
                    problems.append(f"[network] {rel}:{number}: {m.group(1)} – Widgets and Shared/ never touch the network (docs/WIDGETS.md §1)")
    return problems


def _background_modes(yml):
    """The `- value` lines under UIBackgroundModes in project.yml (the key of the app target's Info.plist)."""
    modes = []
    lines = yml.split("\n")
    for i, line in enumerate(lines):
        if re.match(r'\s*UIBackgroundModes:\s*$', line):
            indent = len(line) - len(line.lstrip())
            for follow in lines[i + 1:]:
                item = re.match(r'(\s*)-\s*([\w-]+)\s*(?:#.*)?$', follow)
                if item and len(item.group(1)) > indent:
                    modes.append(item.group(2))
                elif follow.strip() and not follow.lstrip().startswith("#"):
                    break
    return modes


def sideload_problems(root=ROOT, allowed_entitlements=None, allowed_modes=None):
    """One message per entitlement, background mode or missing usage string that a sideloaded build cannot carry. Skipped for a tree
    without project.yml (the unit tests build small trees)."""
    allowed_entitlements = ALLOWED_SIDELOAD_ENTITLEMENTS if allowed_entitlements is None else allowed_entitlements
    allowed_modes = ALLOWED_BACKGROUND_MODES if allowed_modes is None else allowed_modes
    yml_path = os.path.join(root, "project.yml")
    if not os.path.exists(yml_path):
        return []
    problems = []
    yml = read_text(yml_path)
    # 1. What the IPA is signed with: nothing that needs a paid Apple Developer account.
    for path in sorted(glob.glob(os.path.join(root, "App", "Supporting", "*.entitlements"))):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        if "-Sideload." not in rel:
            continue
        try:
            with open(path, "rb") as f:
                keys = list(plistlib.load(f))
        except Exception as error:   # an unreadable file would sign nothing: say so instead of passing
            problems.append(f"[sideload] {rel}: not a property list ({error})")
            continue
        for key in keys:
            if key not in allowed_entitlements:
                problems.append(f"[sideload] {rel}: entitlement {key} needs a paid Apple Developer account – AltStore/SideStore could not install the app")
    # 2. Background modes: only the ones that need no entitlement and are in use.
    for mode in _background_modes(yml):
        if mode not in allowed_modes:
            problems.append(f"[sideload] project.yml: UIBackgroundModes {mode} is not on the reviewed list (scripts/check_integration.py)")
    # 3. A framework that asks for a usage string must find it, or the app crashes at the first call.
    code = {}
    for path in swift_files("App/Sources", "Shared", "Widgets/Sources", root=root):
        code[path] = code_only(read_text(path))
    for pattern, key in USAGE_STRINGS:
        users = [os.path.relpath(p, root).replace(os.sep, "/") for p, text in code.items() if pattern.search(text)]
        if users and not re.search(rf'^\s*{key}:', yml, re.M):
            problems.append(f"[sideload] project.yml: {key} is missing, but {users[0]} needs it (iOS ends the app at the first use without it)")
    if any(re.search(r'\ballowsBackgroundLocationUpdates\s*=\s*true\b', text) for text in code.values()) and "location" not in _background_modes(yml):
        problems.append("[sideload] project.yml: UIBackgroundModes lacks location, but the code sets allowsBackgroundLocationUpdates = true")
    return problems


def run_checks(root=ROOT, contract=None, allow=None):
    """All problems as printable lines."""
    contract = CONTRACT if contract is None else contract
    problems = []
    for target, dirs in {"App": ["App/Sources", "Shared"], "Widgets": ["Widgets/Sources", "Shared"]}.items():
        seen = collections.defaultdict(list)
        for p in swift_files(*dirs, root=root):
            names, src = top_level_decls(p)
            for n in names:
                seen[n].append(os.path.relpath(p, root))
            if src.count("{") != src.count("}"):
                problems.append(f"[braces] {os.path.relpath(p, root)}: {{={src.count('{')} }}={src.count('}')}")
        for n, files in sorted(seen.items()):
            if len(files) > 1:
                problems.append(f"[dup:{target}] {n}: {', '.join(files)}")
        if target == "App":
            for c in contract:
                if c not in seen:
                    problems.append(f"[missing] contract type {c}")
    problems += network_problems(root, allow)
    problems += sideload_problems(root)
    return problems


def main(argv=None):
    root = ROOT
    if argv:
        root = os.path.abspath(argv[0])
    problems = run_checks(root)
    for line in problems:
        print(line)
    print(f"--- {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
