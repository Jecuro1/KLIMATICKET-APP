#!/usr/bin/env python3
"""Static integration checks before a CI build (ios.yml runs this before anything is compiled):
 - duplicate top-level (non-private) type names per target (App = App/Sources + Shared, Widgets = Widgets/Sources + Shared)
 - required contract views exist
 - obviously unbalanced braces per file
 - the widget extension and the code it shares with the app never reach the network: no URLSession, URLRequest,
   HafasClient or LiveDataService in Widgets/ or Shared/ (docs/WIDGETS.md §1 – widgets only read the App Group cache;
   Shared/ is compiled into the extension too, so a network call there would run inside it). Comments and string
   literals do not count. A file that genuinely needs one of these names goes into NETWORK_ALLOW with a reason."""
import os, re, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECL = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(public|internal|fileprivate|private|open)\s+)?(?:final\s+)?(struct|class|enum|actor|protocol)\s+([A-Za-z_]\w*)', re.M)
CONTRACT = ["DashboardView", "TripsView", "TripDetailView", "TripEditorView", "StationPickerView", "FavoritesManagerView",
            "StatisticsView", "TicketView", "OnboardingFlow", "AchievementsView", "SettingsView", "UpdateSheet", "WidgetGalleryView", "PlannerRootView"]

# Targets that must stay network-free and the names that mean "talks to the network".
NETWORK_FREE_DIRS = ["Widgets", "Shared"]
NETWORK_NAMES = re.compile(r'\b(URLSession|URLRequest|HafasClient|LiveDataService)\b')
# {repo-relative path: (names that file may use, reason)} – empty on purpose: today nothing in Widgets/ or Shared/ needs one.
NETWORK_ALLOW = {}


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
