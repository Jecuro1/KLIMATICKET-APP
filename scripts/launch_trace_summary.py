#!/usr/bin/env python3
"""Job summary and blank-launch detector for LaunchTrace files (App/Sources/Core/LaunchTrace.swift).

Usage: launch_trace_summary.py <launch-trace.txt> [--summary-file <file>] [--json <file>]

The screenshot run (scripts/capture_screenshots.sh) copies Documents/launch-trace.txt next to the screenshots. Every
launch writes a block that starts with "launch <screen> pid <pid>" followed by timestamped marks ("app.ready",
"screen.appear", "auth.loaded", …) and, for screenshot launches, one "stall <ms> ms from +<ms> ms" line for every time
the main thread was unresponsive for more than 250 ms.

* Markdown with one row per launch (marks, stalls, verdict) goes to --summary-file (ios.yml passes
  $GITHUB_STEP_SUMMARY), or to stdout without it.
* A launch with neither a "stall" nor an "auth.loaded" line is stuck before its first frame: the screenshot shows the
  launch screen. It gets a ::warning:: line on stdout (GitHub Actions turns it into an annotation) – the same rule as
  sample_if_stuck in capture_screenshots.sh, which samples the stuck process. The script never fails the build
  (exit 0) unless its arguments are wrong: a blank screenshot is a finding, not a reason to lose the artifact.
"""
import argparse
import json
import re
import sys

LINE = re.compile(r"^(?P<wall>\d+(?:\.\d+)?) \+(?P<ms>\d+) ms\s+(?P<text>.*?)\s*$")
LAUNCH = re.compile(r"^launch (?P<run>.*?) pid (?P<pid>\d+)$")
STALL = re.compile(r"^stall (?P<ms>\d+) ms from \+(?P<from>\d+) ms$")

# Marks shown as columns, in launch order.
MARKS = ("app.ready", "screen.appear", "root.appear", "auth.loaded")
BLANK_RULE = "kein „stall“ und kein „auth.loaded“ – der Hauptthread hat vor dem ersten Bild nicht geantwortet"


def parse(text):
    """[{run, pid, marks: {name: ms}, stalls: [{ms, from}], lines}] – one entry per "launch" line, in file order.
    Lines before the first "launch" line and lines that are not trace lines are ignored."""
    launches = []
    for raw in text.splitlines():
        m = LINE.match(raw)
        if not m:
            continue
        body = m["text"]
        head = LAUNCH.match(body)
        if head:
            launches.append({"run": head["run"], "pid": int(head["pid"]), "marks": {}, "stalls": [], "lines": 1})
            continue
        if not launches:
            continue
        current = launches[-1]
        current["lines"] += 1
        stall = STALL.match(body)
        if stall:
            current["stalls"].append({"ms": int(stall["ms"]), "from": int(stall["from"])})
        elif body and " " not in body:
            current["marks"].setdefault(body, int(m["ms"]))
    return launches


def is_blank(launch):
    """The blank-launch rule: neither a stall line nor the Keychain read."""
    return not launch["stalls"] and "auth.loaded" not in launch["marks"]


def summarize(launches):
    rows = []
    for launch in launches:
        longest = max((s["ms"] for s in launch["stalls"]), default=None)
        rows.append({
            "run": launch["run"], "pid": launch["pid"],
            "marks": {name: launch["marks"].get(name) for name in MARKS},
            "stalls": len(launch["stalls"]), "longestStallMs": longest,
            "blank": is_blank(launch),
        })
    return {
        "launches": rows,
        "blank": [r["run"] for r in rows if r["blank"]],
        "slowestStall": max(rows, key=lambda r: r["longestStallMs"] or 0)["run"] if any(r["longestStallMs"] for r in rows) else None,
    }


def cell(value, suffix=""):
    return "–" if value is None else f"{value}{suffix}"


def warnings(summary):
    return [f"::warning title=Leerer Start::{r['run']} (pid {r['pid']}): {BLANK_RULE}" for r in summary["launches"] if r["blank"]]


def markdown(summary):
    rows = summary["launches"]
    out = ["### Start-Trace der Screenshot-Läufe", ""]
    if not rows:
        return "\n".join(out + ["Keine Starts im Trace gefunden."]) + "\n"
    out.append(f"{len(rows)} Starts, {len(summary['blank'])} ohne Lebenszeichen vor dem ersten Bild.")
    out += ["", "| Start | app.ready | screen.appear | root.appear | auth.loaded | Stalls | längster Stall | Urteil |",
            "|---|---:|---:|---:|---:|---:|---:|---|"]
    for r in rows:
        marks = r["marks"]
        verdict = "**leer?**" if r["blank"] else "ok"
        out.append(f"| {r['run']} | {cell(marks['app.ready'], ' ms')} | {cell(marks['screen.appear'], ' ms')} | "
                   f"{cell(marks['root.appear'], ' ms')} | {cell(marks['auth.loaded'], ' ms')} | {r['stalls']} | "
                   f"{cell(r['longestStallMs'], ' ms')} | {verdict} |")
    if summary["blank"]:
        out += ["", f"Leer: {', '.join(summary['blank'])} – {BLANK_RULE}."]
    out += ["", "Zeiten ab `App.init` (LaunchTrace). Ein Stall ist eine Antwortzeit des Hauptthreads über 250 ms; der erste "
            "enthält alles bis zum ersten Bild."]
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("trace", help="launch-trace.txt")
    parser.add_argument("--summary-file", help="append the Markdown here ($GITHUB_STEP_SUMMARY); stdout when absent")
    parser.add_argument("--json", help="write the summary as JSON")
    args = parser.parse_args(argv)
    try:
        with open(args.trace, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        print(f"::notice::Kein Start-Trace ({args.trace}) – nichts zusammenzufassen.")
        return 0
    summary = summarize(parse(text))
    for line in warnings(summary):
        print(line)
    report = markdown(summary)
    if args.summary_file:
        with open(args.summary_file, "a", encoding="utf-8") as f:
            f.write(report)
    else:
        print(report)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
