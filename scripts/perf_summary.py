#!/usr/bin/env python3
"""Readable summary of the KlimaBilanzPerfTests run (CI job "perf").

Usage: perf_summary.py <xcodebuild-test.log> [--diagnostics <app Diagnostics dir>] [--json out.json]

Parses the "measured [Metric, unit] average: …" lines xcodebuild prints for every XCTest metric and renders Markdown
(launch time, scroll hitch ratios per screen, tab tour clock/CPU/memory) for $GITHUB_STEP_SUMMARY. With
--diagnostics it also reports what the app's own DiagnosticsService recorded during the run (watchdog hangs,
Analytics.make timings) – the same data a user exports from Einstellungen › Diagnose & Stabilität.
"""
import argparse
import json
import os
import re
import sys

MEASURED = re.compile(
    r"Test Case '-\[(?P<cls>[\w.]+) (?P<test>\w+)\]' measured "
    r"\[(?P<name>.+), (?P<unit>[^,\]]+)\] average: (?P<avg>-?[\d.]+), "
    r"relative standard deviation: (?P<rsd>[\d.]+)%, values: \[(?P<values>[^\]]*)\]")
RESULT = re.compile(r"Test Case '-\[(?P<cls>[\w.]+) (?P<test>\w+)\]' (?P<status>passed|failed) \((?P<secs>[\d.]+) seconds\)")

SCREENS = {
    "Overview": "Übersicht",
    "Trips": "Fahrten",
    "Statistics": "Statistik",
    "Ticket": "Ticket",
    "Gipfelbuch": "Gipfelbuch",
}


def parse_log(text):
    """{test: {"class", "metrics": {name: {...}}, "status", "seconds"}} in log order."""
    tests = {}
    for m in MEASURED.finditer(text):
        entry = tests.setdefault(m["test"], {"class": m["cls"].split(".")[-1], "metrics": {}})
        values = [float(v) for v in m["values"].split(",") if v.strip()]
        entry["metrics"][m["name"].strip()] = {
            "unit": m["unit"].strip(), "average": float(m["avg"]), "rsd": float(m["rsd"]), "values": values}
    for m in RESULT.finditer(text):
        entry = tests.setdefault(m["test"], {"class": m["cls"].split(".")[-1], "metrics": {}})
        entry["status"] = m["status"]
        entry["seconds"] = float(m["secs"])
    return tests


def metric(entry, *prefixes):
    for name, value in entry.get("metrics", {}).items():
        if any(name.startswith(p) for p in prefixes):
            return value
    return None


def screen_label(test):
    heavy = test.endswith("Heavy")
    core = test[len("testScroll"):] if test.startswith("testScroll") else test
    if heavy:
        core = core[: -len("Heavy")]
    label = SCREENS.get(core, core)
    return f"{label} (+1 500 Fahrten)" if heavy else label


def rating(ratio):
    """Apple's guidance for hitch time ratios: < 5 ms/s good, 5–10 noticeable, ≥ 10 critical."""
    if ratio is None:
        return "–"
    if ratio < 5:
        return "gut"
    if ratio < 10:
        return "spürbar"
    return "kritisch"


def fmt(value, digits=1):
    if value is None:
        return "–"
    return f"{value:.{digits}f}"


def summarize(tests):
    """Structured summary (also written as JSON)."""
    out = {"launch": None, "scroll": [], "tabTour": [], "failed": [], "testCount": len(tests)}
    for test, entry in tests.items():
        if entry.get("status") == "failed":
            out["failed"].append(test)
        launch = metric(entry, "Duration (AppLaunch)")
        if launch:
            out["launch"] = {"test": test, "seconds": launch["average"], "rsd": launch["rsd"], "values": launch["values"]}
        if test.startswith("testScroll"):
            drag = metric(entry, "Hitch Time Ratio (Scroll_DraggingAndDeceleration)")
            decel = metric(entry, "Hitch Time Ratio (Scroll_Deceleration)")
            hitches = metric(entry, "Number of Hitches (Scroll_DraggingAndDeceleration)", "Hitch Count (Scroll_DraggingAndDeceleration)")
            fps = metric(entry, "Frame Rate (Scroll_DraggingAndDeceleration)")
            total = metric(entry, "Hitches Total Duration (Scroll_DraggingAndDeceleration)")
            out["scroll"].append({
                "test": test, "screen": screen_label(test),
                "hitchRatio": drag and drag["average"], "hitchRatioRSD": drag and drag["rsd"],
                "decelerationHitchRatio": decel and decel["average"],
                "hitches": hitches and hitches["average"], "hitchesTotalMs": total and total["average"],
                "frameRate": fps and fps["average"], "rating": rating(drag and drag["average"]),
            })
        if test.startswith("testTabSwitching"):
            clock = metric(entry, "Clock Monotonic Time")
            cpu = metric(entry, "CPU Time")
            peak = metric(entry, "Memory Peak Physical")
            mem = metric(entry, "Memory Physical")
            out["tabTour"].append({
                "test": test, "label": "+1 500 Fahrten" if test.endswith("Heavy") else "Demo-Jahr",
                "clockSeconds": clock and clock["average"], "cpuSeconds": cpu and cpu["average"],
                "peakMemoryMB": peak and peak["average"] / 1024, "memoryDeltaMB": mem and mem["average"] / 1024,
            })
    return out


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def app_diagnostics(directory):
    """Watchdog hangs and timings the app recorded during the run (DiagnosticsService files)."""
    if not directory or not os.path.isdir(directory):
        return None
    events = read_json(os.path.join(directory, "events.json")) or []
    sessions = read_json(os.path.join(directory, "sessions.json")) or {}
    all_sessions = list(sessions.get("history") or []) + ([sessions["current"]] if sessions.get("current") else [])
    hangs = [e for e in events if e.get("kind") == "watchdogHang"]
    timings = {}
    launches = []
    for s in all_sessions:
        for name, stat in (s.get("timings") or {}).items():
            agg = timings.setdefault(name, {"count": 0, "totalMs": 0.0, "maxMs": 0.0})
            agg["count"] += stat.get("count", 0)
            agg["totalMs"] += stat.get("totalMs", 0.0)
            agg["maxMs"] = max(agg["maxMs"], stat.get("maxMs", 0.0))
        if s.get("launch"):
            launches.append(s["launch"].get("initToFirstFrameMs"))
    by_screen = {}
    for h in hangs:
        key = h.get("screen") or "?"
        slot = by_screen.setdefault(key, {"count": 0, "longestMs": 0.0, "totalMs": 0.0})
        slot["count"] += 1
        slot["longestMs"] = max(slot["longestMs"], h.get("durationMs") or 0)
        slot["totalMs"] += h.get("durationMs") or 0
    return {"sessions": len(all_sessions), "hangs": len(hangs), "hangsByScreen": by_screen, "timings": timings,
            "initToFirstFrameMs": [x for x in launches if x is not None]}


def markdown(summary, diag=None):
    lines = ["## KlimaBilanz – Performance (Simulator, Release)", ""]
    if summary["testCount"] == 0:
        lines += ["Keine Messwerte im Log gefunden – siehe Artefakt `perf-*` (test.log, xcresult).", ""]
        return "\n".join(lines)
    if summary["failed"]:
        lines += [f"**Fehlgeschlagen:** {', '.join(summary['failed'])}", ""]
    launch = summary["launch"]
    if launch:
        lines += [f"**App-Start** (XCTApplicationLaunchMetric, bis bedienbar): **{launch['seconds']:.3f} s** "
                  f"(± {launch['rsd']:.1f} %, Werte {', '.join(f'{v:.3f}' for v in launch['values'])})", ""]
    if summary["scroll"]:
        lines += ["### Scrollen (Hitch Time Ratio, ms Ruckeln pro s Scrollen; < 5 gut, 5–10 spürbar, ≥ 10 kritisch)", "",
                  "| Bildschirm | Ziehen + Auslaufen | nur Auslaufen | Hitches | Hitch-Dauer | Bildrate | Bewertung |",
                  "|---|---:|---:|---:|---:|---:|---|"]
        for s in summary["scroll"]:
            lines.append(f"| {s['screen']} | {fmt(s['hitchRatio'])} ms/s | {fmt(s['decelerationHitchRatio'])} ms/s | "
                         f"{fmt(s['hitches'])} | {fmt(s['hitchesTotalMs'], 0)} ms | {fmt(s['frameRate'], 0)} fps | {s['rating']} |")
        lines.append("")
    if summary["tabTour"]:
        lines += ["### Tab-Runde (Fahrten → Statistik → Ticket → Übersicht)", "",
                  "| Daten | Dauer | CPU | Speicher-Spitze |", "|---|---:|---:|---:|"]
        for t in summary["tabTour"]:
            lines.append(f"| {t['label']} | {fmt(t['clockSeconds'], 2)} s | {fmt(t['cpuSeconds'], 2)} s | {fmt(t['peakMemoryMB'], 0)} MB |")
        lines.append("")
    if diag:
        lines += [f"### Von der App selbst erfasst (DiagnosticsService, {diag['sessions']} Sitzungen)", ""]
        if diag["hangs"]:
            lines.append(f"Hänger > 250 ms (Watchdog): **{diag['hangs']}**")
            lines += ["", "| Bildschirm | Anzahl | längster | gesamt |", "|---|---:|---:|---:|"]
            for screen, h in sorted(diag["hangsByScreen"].items(), key=lambda kv: -kv[1]["totalMs"]):
                lines.append(f"| {screen} | {h['count']} | {h['longestMs']:.0f} ms | {h['totalMs']:.0f} ms |")
        else:
            lines.append("Hänger > 250 ms (Watchdog): keine")
        lines.append("")
        if diag["timings"]:
            lines += ["| Messpunkt | Aufrufe | Ø | max |", "|---|---:|---:|---:|"]
            for name, t in sorted(diag["timings"].items()):
                avg = t["totalMs"] / t["count"] if t["count"] else 0
                lines.append(f"| `{name}` | {t['count']} | {avg:.1f} ms | {t['maxMs']:.1f} ms |")
            lines.append("")
        if diag["initToFirstFrameMs"]:
            values = diag["initToFirstFrameMs"]
            lines += [f"Start bis erste Ansicht (App-Code): Ø {sum(values) / len(values):.0f} ms über {len(values)} Starts", ""]
    lines.append("_Simulator auf dem CI-Mac – absolute Werte weichen vom iPhone ab, Vergleiche zwischen Builds sind aussagekräftig._")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log")
    parser.add_argument("--diagnostics")
    parser.add_argument("--json")
    args = parser.parse_args(argv)
    try:
        with open(args.log, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as error:
        print(f"## KlimaBilanz – Performance\n\nLog nicht lesbar: {error}")
        return 0
    summary = summarize(parse_log(text))
    diag = app_diagnostics(args.diagnostics)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"summary": summary, "appDiagnostics": diag}, f, indent=2, ensure_ascii=False)
    print(markdown(summary, diag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
