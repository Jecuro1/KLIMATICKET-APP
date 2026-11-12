#!/usr/bin/env python3
"""Screen-by-screen comparison of two perf runs (perf-summary.json of the CI job "perf", scripts/perf_summary.py).

Usage: perf_compare.py <before perf-summary.json> <after perf-summary.json> [--tolerance 0.15] [--fail-on-regress]

Prints Markdown (for docs/PERF_BASELINE.md): hitch time ratio of every screen and source, the time to the first frame
when a screen opens, the longest frame, the launch and the memory peak – before, after, difference and a verdict.

Verdict rules (the simulator is noisy, a run differs from the next one): a figure counts as *worse* / *better* only when it
moved by more than the tolerance (default 15 %) AND by more than a floor in absolute terms (hitch ratio 1 ms/s, frame times
20 ms, memory 5 MB); everything else is *gleich*. A screen that is only in one of the runs is listed as new / entfernt.
--fail-on-regress exits 1 when any figure is worse (the acceptance rule: no screen worse than the baseline).
"""
import argparse
import json
import sys

# (key of the figure, label, unit, absolute floor)
HITCH_FLOOR = 1.0     # ms/s
FRAME_FLOOR = 20.0    # ms
MEMORY_FLOOR = 5.0    # MB


def load(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return (data.get("appDiagnostics") or {}).get("inApp") or {}


def verdict(before, after, floor, tolerance):
    """'besser', 'schlechter', 'gleich' or '–' (no number on one side)."""
    if before is None or after is None:
        return "–"
    delta = after - before
    if abs(delta) <= floor or abs(delta) <= abs(before) * tolerance:
        return "gleich"
    return "schlechter" if delta > 0 else "besser"


def fmt(value, digits=1):
    return "–" if value is None else f"{value:.{digits}f}"


def diff(before, after, digits=1):
    if before is None or after is None:
        return "–"
    delta = after - before
    return f"{delta:+.{digits}f}"


def index(rows, key_fields):
    return {tuple(row.get(k) for k in key_fields): row for row in rows or []}


def rows_for(before, after, key_fields, figure, floor, tolerance, label_of):
    """Comparison rows for one table: [(label, before, after, verdict)] in the order of `after`, then removed ones."""
    old, new = index(before, key_fields), index(after, key_fields)
    out = []
    for key in list(new) + [k for k in old if k not in new]:
        b = old.get(key, {}).get(figure)
        a = new.get(key, {}).get(figure)
        status = verdict(b, a, floor, tolerance)
        if key not in old:
            status = "neu"
        elif key not in new:
            status = "entfernt"
        out.append((label_of(key), b, a, status))
    return out


def table(title, header, rows, digits=1, unit=""):
    lines = [f"### {title}", "", f"| {header} | vorher | nachher | Differenz | Urteil |", "|---|---:|---:|---:|---|"]
    for label, b, a, status in rows:
        lines.append(f"| {label} | {fmt(b, digits)}{unit if b is not None else ''} | {fmt(a, digits)}{unit if a is not None else ''} | "
                     f"{diff(b, a, digits)} | {status} |")
    lines.append("")
    return lines


def compare(before, after, tolerance=0.15):
    """Markdown lines and the list of worse figures."""
    lines = []
    worse = []
    sections = [
        ("Scrollen: Hitch Time Ratio (ms Ruckeln pro s Scrollen, kleiner ist besser)", "Bildschirm · Daten · Quelle",
         rows_for(before.get("scroll"), after.get("scroll"), ("screen", "variant", "source"), "hitchRatio", HITCH_FLOOR,
                  tolerance, lambda k: f"{k[0]} · {k[1]} · {k[2]}"), 1, " ms/s"),
        ("Bildschirmwechsel: Zeit bis zum ersten Bild", "nach · Daten",
         rows_for(before.get("transitions"), after.get("transitions"), ("to", "variant"), "firstFrameMs", FRAME_FLOOR,
                  tolerance, lambda k: f"{k[0]} · {k[1]}"), 0, " ms"),
        ("Bildschirmwechsel: längster Frame danach", "nach · Daten",
         rows_for(before.get("transitions"), after.get("transitions"), ("to", "variant"), "longestFrameMs", FRAME_FLOOR,
                  tolerance, lambda k: f"{k[0]} · {k[1]}"), 0, " ms"),
        ("Start: App.init bis erstes Bild", "Daten",
         rows_for(before.get("launch"), after.get("launch"), ("variant",), "initToFirstFrameMs", FRAME_FLOOR, tolerance,
                  lambda k: k[0]), 0, " ms"),
        ("Speicher: Spitze je Bildschirm", "Bildschirm · Daten",
         rows_for(before.get("memory"), after.get("memory"), ("screen", "variant"), "peakMB", MEMORY_FLOOR, tolerance,
                  lambda k: f"{k[0]} · {k[1]}"), 0, " MB"),
        ("Hänger über 250 ms (Watchdog): Gesamtdauer", "Bildschirm · Daten",
         rows_for(before.get("hangs"), after.get("hangs"), ("screen", "variant"), "totalMs", FRAME_FLOOR, tolerance,
                  lambda k: f"{k[0]} · {k[1]}"), 0, " ms"),
    ]
    for title, header, rows, digits, unit in sections:
        if not rows:
            continue
        lines += table(title, header, rows, digits, unit)
        worse += [f"{title}: {label}" for label, _, _, status in rows if status == "schlechter"]
    return lines, worse


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--tolerance", type=float, default=0.15)
    parser.add_argument("--fail-on-regress", action="store_true")
    args = parser.parse_args(argv)
    lines, worse = compare(load(args.before), load(args.after), args.tolerance)
    print("\n".join(lines))
    print(f"{len(worse)} Wert(e) schlechter als vorher" + (":" if worse else "."))
    for item in worse:
        print(f"- {item}")
    return 1 if (worse and args.fail_on_regress) else 0


if __name__ == "__main__":
    sys.exit(main())
