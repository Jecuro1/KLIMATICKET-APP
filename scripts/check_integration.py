#!/usr/bin/env python3
"""Static integration checks before a CI build:
 - duplicate top-level (non-private) type names per target (App = App/Sources + Shared, Widgets = Widgets/Sources + Shared)
 - required contract views exist
 - obviously unbalanced braces per file"""
import os, re, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECL = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(public|internal|fileprivate|private|open)\s+)?(?:final\s+)?(struct|class|enum|actor|protocol)\s+([A-Za-z_]\w*)', re.M)
CONTRACT = ["DashboardView", "TripsView", "TripDetailView", "TripEditorView", "StationPickerView", "FavoritesManagerView",
            "StatisticsView", "TicketView", "OnboardingFlow", "AchievementsView", "SettingsView", "UpdateSheet", "WidgetGalleryView"]

def swift_files(*dirs):
    for d in dirs:
        for base, _, files in os.walk(os.path.join(ROOT, d)):
            for f in files:
                if f.endswith(".swift"):
                    yield os.path.join(base, f)

def top_level_decls(path):
    src = open(path, encoding="utf-8").read()
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

problems = 0
for target, dirs in {"App": ["App/Sources", "Shared"], "Widgets": ["Widgets/Sources", "Shared"]}.items():
    seen = collections.defaultdict(list)
    for p in swift_files(*dirs):
        names, src = top_level_decls(p)
        for n in names:
            seen[n].append(os.path.relpath(p, ROOT))
        if src.count("{") != src.count("}"):
            print(f"[braces] {os.path.relpath(p, ROOT)}: {{={src.count('{')} }}={src.count('}')}")
            problems += 1
    for n, files in sorted(seen.items()):
        if len(files) > 1:
            print(f"[dup:{target}] {n}: {', '.join(files)}")
            problems += 1
    if target == "App":
        for c in CONTRACT:
            if c not in seen:
                print(f"[missing] contract type {c}")
                problems += 1
print(f"--- {problems} problem(s)")
sys.exit(1 if problems else 0)
