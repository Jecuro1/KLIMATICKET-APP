#!/usr/bin/env python3
"""Readable summary of the KlimaBilanzPerfTests run (CI job "perf").

Usage: perf_summary.py <xcodebuild-test.log> [--diagnostics <app Diagnostics dir>] [--launch-trace <file>]
                       [--profiles <dir>] [--json out.json]

Renders Markdown for $GITHUB_STEP_SUMMARY from
  • the "measured [Metric, unit] average: …" lines xcodebuild prints for every XCTest metric (tab tour clock / CPU /
    memory; launch and hitch metrics only where the simulator reports them – it reports none for hitches);
  • the app's own measurements (--diagnostics): `perf-*.json` of PerfFrameMonitor – launch, hitch time ratio per
    screen while scrolling (XCUITest swipes = "touch", the in-app tour = "tour"), tab / sheet transitions, memory –
    plus what DiagnosticsService recorded (watchdog hangs per screen and data set, Analytics.make timings);
  • the LaunchTrace marks of the perf launches (--launch-trace, Documents/launch-trace.txt);
  • the main-thread hotspots per tour phase (--profiles, scripts/perf_profile.sh → *.profile.json).
"""
import argparse
import glob
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
        # Xcode 26 names it "Duration (ApplicationFirstFramePresentationResponsive)", older ones "Duration (AppLaunch)".
        launch = metric(entry, "Duration (AppLaunch)", "Duration (ApplicationFirstFramePresentation")
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


def median(values):
    values = sorted(v for v in values if v is not None)
    if not values:
        return None
    mid = len(values) // 2
    return values[mid] if len(values) % 2 else (values[mid - 1] + values[mid]) / 2


def variant_label(extra_trips):
    return "Demo-Jahr" if not extra_trips else f"+{extra_trips:,} Fahrten".replace(",", " ")


SOURCE_LABELS = {"touch": "Wischen (XCUITest)", "tour": "Tour (2 400 pt/s)", "other": "programmatisch"}


def perf_reports(directory):
    """PerfFrameMonitor files (one per app launch)."""
    if not directory or not os.path.isdir(directory):
        return []
    reports = []
    for name in sorted(os.listdir(directory)):
        if name.startswith("perf-") and name.endswith(".json") and name != "perf-tour.json":
            data = read_json(os.path.join(directory, name))
            if isinstance(data, dict) and "scroll" in data:
                reports.append(data)
    return reports


def in_app(reports, events=None):
    """Aggregates PerfFrameMonitor reports: scroll per (screen, data set, source), transitions, launch, memory, hangs."""
    scroll, transitions, memory = {}, {}, {}
    launches = []
    session_variant = {}
    for r in reports:
        variant = variant_label(r.get("extraTrips") or 0)
        if r.get("session"):
            session_variant[r["session"][:8]] = variant
        for rec in r.get("scroll") or []:
            key = (rec["screen"], variant, rec["source"])
            agg = scroll.setdefault(key, {"segments": 0, "frames": 0, "seconds": 0.0, "hitches": 0, "hitchMs": 0.0,
                                          "severeHitches": 0, "longestFrameMs": 0.0, "distancePt": 0.0})
            for field in ("segments", "frames", "seconds", "hitches", "hitchMs", "severeHitches", "distancePt"):
                agg[field] += rec.get(field) or 0
            agg["longestFrameMs"] = max(agg["longestFrameMs"], rec.get("longestFrameMs") or 0)
        for t in r.get("transitions") or []:
            transitions.setdefault((t["to"], variant), []).append(t)
        for screen, mb in (r.get("footprintByScreenMB") or {}).items():
            key = (screen, variant)
            memory[key] = max(memory.get(key, 0), mb)
        if not r.get("tour"):
            launch = r.get("launch") or {}
            frames = r.get("launchFrames") or {}
            launches.append({"variant": variant, "processMs": launch.get("processToFirstFrameMs"),
                             "initMs": launch.get("initToFirstFrameMs"), "firstTickMs": frames.get("firstFrameMs"),
                             "longestAfterMs": frames.get("longestFrameMs"), "hitchAfterMs": frames.get("hitchMs"),
                             "screen": frames.get("to")})
    scroll_rows = []
    for (screen, variant, source), a in sorted(scroll.items()):
        ratio = a["hitchMs"] / a["seconds"] if a["seconds"] > 0 else None
        scroll_rows.append({"screen": screen, "variant": variant, "source": source, "hitchRatio": ratio,
                            "rating": rating(ratio), "fps": a["frames"] / a["seconds"] if a["seconds"] > 0 else None,
                            **a})
    transition_rows = []
    for (to, variant), items in sorted(transitions.items()):
        transition_rows.append({"to": to, "variant": variant, "count": len(items),
                                "firstFrameMs": median([t.get("firstFrameMs") for t in items]),
                                "firstFrameMaxMs": max((t.get("firstFrameMs") or 0) for t in items),
                                "longestFrameMs": max((t.get("longestFrameMs") or 0) for t in items),
                                "hitchMs": median([t.get("hitchMs") for t in items])})
    launch_rows = []
    for variant in sorted({l["variant"] for l in launches}):
        items = [l for l in launches if l["variant"] == variant]
        launch_rows.append({"variant": variant, "count": len(items),
                            "processToFirstFrameMs": median([l["processMs"] for l in items]),
                            "initToFirstFrameMs": median([l["initMs"] for l in items]),
                            "longestFrameAfterMs": median([l["longestAfterMs"] for l in items]),
                            "hitchAfterMs": median([l["hitchAfterMs"] for l in items])})
    hangs = {}
    for e in events or []:
        if e.get("kind") != "watchdogHang":
            continue
        parts = str(e.get("id", "")).split("-")
        variant = session_variant.get(parts[1] if len(parts) > 2 else "", "?")
        slot = hangs.setdefault((e.get("screen") or "?", variant), {"count": 0, "longestMs": 0.0, "totalMs": 0.0})
        slot["count"] += 1
        slot["longestMs"] = max(slot["longestMs"], e.get("durationMs") or 0)
        slot["totalMs"] += e.get("durationMs") or 0
    return {"scroll": scroll_rows, "transitions": transition_rows, "launch": launch_rows,
            "memory": [{"screen": k[0], "variant": k[1], "peakMB": v} for k, v in sorted(memory.items())],
            "hangs": [{"screen": k[0], "variant": k[1], **v} for k, v in sorted(hangs.items(), key=lambda kv: -kv[1]["totalMs"])]}


LAUNCH_LINE = re.compile(r"^[\d.]+ \+(?P<ms>\d+) ms  (?P<event>.+)$")


def launch_trace(path):
    """Median ms since App.init of every LaunchTrace mark, per perf data set ("launch perf+<n> pid …" blocks)."""
    if not path or not os.path.isfile(path):
        return None
    runs = []
    current = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LAUNCH_LINE.match(line.strip())
            if not m:
                continue
            event = m["event"]
            if event.startswith("launch "):
                run = event.split()[1]
                current = {"run": run, "marks": {}} if run.startswith("perf") else None
                if current:
                    runs.append(current)
            elif current is not None and not event.startswith("stall"):
                current["marks"].setdefault(event, int(m["ms"]))
    out = {}
    for run in sorted({r["run"] for r in runs}):
        items = [r for r in runs if r["run"] == run]
        names = []
        for r in items:
            for name in r["marks"]:
                if name not in names:
                    names.append(name)
        out[run] = {"launches": len(items),
                    "marks": {n: median([r["marks"].get(n) for r in items]) for n in names}}
    return out


def profiles(directory):
    if not directory or not os.path.isdir(directory):
        return []
    found = []
    for path in sorted(glob.glob(os.path.join(directory, "*.profile.json"))):
        data = read_json(path)
        if isinstance(data, list):
            found += data
    return found


def in_app_markdown(app, trace=None):
    lines = []
    if app["launch"]:
        lines += ["### Start (von der App gemessen)", "",
                  "| Daten | Starts | Prozessstart → erstes Bild | App.init → erstes Bild | längster Frame danach (4 s) | Ruckeln danach |",
                  "|---|---:|---:|---:|---:|---:|"]
        for l in app["launch"]:
            lines.append(f"| {l['variant']} | {l['count']} | {fmt(l['processToFirstFrameMs'], 0)} ms | {fmt(l['initToFirstFrameMs'], 0)} ms | "
                         f"{fmt(l['longestFrameAfterMs'], 0)} ms | {fmt(l['hitchAfterMs'], 0)} ms |")
        lines.append("")
    if trace:
        for run, data in trace.items():
            marks = " → ".join(f"{name} {ms:.0f}" for name, ms in sorted(data["marks"].items(), key=lambda kv: kv[1] or 0) if ms is not None)
            lines += [f"LaunchTrace `{run}` ({data['launches']} Starts, Median ms seit App.init): {marks}", ""]
    if app["scroll"]:
        lines += ["### Scrollen (von der App gemessen: Hitch Time Ratio = ms Ruckeln pro s Scrollen; < 5 gut, 5–10 spürbar, ≥ 10 kritisch)", "",
                  "| Bildschirm | Daten | Quelle | Hitch-Ratio | Hitches (≥ 3 Frames) | längster Frame | Bildrate | Scrollzeit | Bewertung |",
                  "|---|---|---|---:|---:|---:|---:|---:|---|"]
        for r in app["scroll"]:
            lines.append(f"| {r['screen']} | {r['variant']} | {SOURCE_LABELS.get(r['source'], r['source'])} | {fmt(r['hitchRatio'])} ms/s | "
                         f"{r['hitches']} ({r['severeHitches']}) | {fmt(r['longestFrameMs'], 0)} ms | {fmt(r['fps'], 0)} fps | "
                         f"{fmt(r['seconds'])} s | {r['rating']} |")
        lines.append("")
    if app["transitions"]:
        lines += ["### Bildschirmwechsel (Auswahl → erstes Bild; dann 1,5 s Frames)", "",
                  "| nach | Daten | Wechsel | erstes Bild (Median / max) | längster Frame | Ruckeln (Median) |",
                  "|---|---|---:|---:|---:|---:|"]
        for t in app["transitions"]:
            lines.append(f"| {t['to']} | {t['variant']} | {t['count']} | {fmt(t['firstFrameMs'], 0)} / {fmt(t['firstFrameMaxMs'], 0)} ms | "
                         f"{fmt(t['longestFrameMs'], 0)} ms | {fmt(t['hitchMs'], 0)} ms |")
        lines.append("")
    if app["memory"]:
        lines += ["### Speicher (phys_footprint, Spitze je Bildschirm)", "", "| Bildschirm | Daten | Spitze |", "|---|---|---:|"]
        for m in app["memory"]:
            lines.append(f"| {m['screen']} | {m['variant']} | {m['peakMB']:.0f} MB |")
        lines.append("")
    if app["hangs"]:
        lines += ["### Hänger > 250 ms je Bildschirm und Datensatz (Watchdog)", "",
                  "_Enthält auch die Zeit, in der XCUITest den Accessibility-Baum der App abfragt (läuft auf dem Hauptthread)._", "",
                  "| Bildschirm | Daten | Anzahl | längster | gesamt |", "|---|---|---:|---:|---:|"]
        for h in app["hangs"]:
            lines.append(f"| {h['screen']} | {h['variant']} | {h['count']} | {h['longestMs']:.0f} ms | {h['totalMs']:.0f} ms |")
        lines.append("")
    return lines


def markdown(summary, diag=None):
    lines = ["## KlimaBilanz – Performance (Simulator, Release)", ""]
    app = (diag or {}).get("inApp")
    has_app = bool(app and (app["scroll"] or app["launch"] or app["transitions"]))
    if summary["testCount"] == 0 and not has_app:
        lines += ["Keine Messwerte im Log gefunden – siehe Artefakt `perf-*` (test.log, xcresult).", ""]
        return "\n".join(lines)
    if summary["failed"]:
        lines += [f"**Fehlgeschlagen:** {', '.join(summary['failed'])}", ""]
    launch = summary["launch"]
    if launch:
        lines += [f"**App-Start laut XCTest** (XCTApplicationLaunchMetric, Start-Anfrage bis erstes bedienbares Bild): "
                  f"**{launch['seconds']:.3f} s** "
                  f"(± {launch['rsd']:.1f} %, Werte {', '.join(f'{v:.3f}' for v in launch['values'])})", ""]
    if has_app:
        lines += in_app_markdown(app, (diag or {}).get("launchTrace"))
    if any(s["hitchRatio"] is not None for s in summary["scroll"]):
        lines += ["### Scrollen laut XCTest (Hitch Time Ratio, ms Ruckeln pro s Scrollen; < 5 gut, 5–10 spürbar, ≥ 10 kritisch)", "",
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
    if diag and diag.get("profiles"):
        import perf_profile
        lines += ["### Profil (sample, 1 ms): Hauptthread-Hotspots je Tour-Phase (+1 500 Fahrten)", "",
                  "_Jedes Sample zählt für die innerste App-Funktion auf dem Stack – inklusive der SwiftUI-/SwiftData-/"
                  "Foundation-Arbeit, die sie auslöst._", "", perf_profile.markdown(diag["profiles"]), ""]
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
    parser.add_argument("--launch-trace")
    parser.add_argument("--profiles")
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
    if diag is not None or args.launch_trace or args.profiles:
        diag = diag or {"sessions": 0, "hangs": 0, "hangsByScreen": {}, "timings": {}, "initToFirstFrameMs": []}
        events = read_json(os.path.join(args.diagnostics, "events.json")) if args.diagnostics else None
        diag["inApp"] = in_app(perf_reports(args.diagnostics), events if isinstance(events, list) else [])
        diag["launchTrace"] = launch_trace(args.launch_trace)
        diag["profiles"] = profiles(args.profiles)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"summary": summary, "appDiagnostics": diag}, f, indent=2, ensure_ascii=False)
    print(markdown(summary, diag))
    return 0


if __name__ == "__main__":
    sys.exit(main())
