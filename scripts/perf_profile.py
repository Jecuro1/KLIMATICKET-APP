#!/usr/bin/env python3
"""Main-thread hotspots of the app's own tour (CI job "perf", scripts/perf_profile.sh).

Usage: perf_profile.py --sample <tour> <phase>=<sample report> [<phase>=<report> …] [--json out.json]
       perf_profile.py <prefix> [--json out.json]            (Instruments export, see below)

Input 1 – `/usr/bin/sample` reports (what CI records: one per tour phase, e.g. open=stats.open.sample.txt
scroll=stats.scroll.sample.txt). The main thread's call tree is read from the "Call graph:" section; every sample
(1 ms) goes to the leaf-most frame in the app binary, i.e. the app code that – directly or through SwiftUI / SwiftData /
Foundation – did the work. Run-loop waits (mach_msg, …) count as idle.

Input 2 – an Instruments Time Profiler export: <prefix>.time-profile.xml (`xctrace export --xpath
'…/table[@schema="time-profile"]'`), optional <prefix>.signpost-*.xml and <prefix>.tour.json for the phase windows.

Per phase it ranks app functions by attributed time and by inclusive time (on the stack at all), the leaf symbols
(where the CPU actually was) and the binaries.
"""
import argparse
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

APP_BINARIES = ("KlimaBilanz", "KlimaBilanz.debug.dylib")


def _int(text):
    try:
        return int(text)
    except (TypeError, ValueError):
        return None


def iter_rows(path):
    """Yields (columns, row) for every <row>: columns = schema mnemonics, row = list of resolved cell values.

    xctrace writes every distinct value once with an id (anywhere, also nested inside another value) and refers to it
    later with ref="id"; values are resolved to small Python objects so the element tree can be dropped as it is read."""
    values = {}
    columns = []
    depth = 0

    def resolve(el):
        ref = el.get("ref")
        if ref is not None:
            return values.get(ref)
        # Post-order: nested definitions (a thread's process, a frame's binary) are registered first.
        children = [(child, resolve(child)) for child in el]
        tag = el.tag
        if tag == "frame":
            binary = next((v for c, v in children if c.tag == "binary"), None)
            value = (el.get("name") or el.get("addr") or "?", binary)
        elif tag == "binary":
            value = el.get("name") or "?"
        elif tag in ("backtrace", "tagged-backtrace"):
            frames = []
            for c, v in children:
                if c.tag == "frame" and v is not None:
                    frames.append(v)
                elif c.tag in ("backtrace", "tagged-backtrace") and isinstance(v, tuple):
                    frames.extend(v)
            value = tuple(frames)
        elif tag in ("sample-time", "weight", "duration", "start-time", "event-time", "start", "uint64", "duration-on-core"):
            value = _int(el.text)
            if value is None:
                value = el.get("fmt")
        else:
            value = el.get("fmt") if el.get("fmt") is not None else (el.text or "").strip()
        if el.get("id") is not None:
            values[el.get("id")] = value
        return value

    for event, el in ET.iterparse(path, events=("start", "end")):
        if event == "start":
            if el.tag == "row":
                depth += 1
            continue
        if el.tag == "mnemonic" and depth == 0:
            columns.append((el.text or "").strip())
        elif el.tag == "row":
            depth -= 1
            cells = [resolve(child) for child in el]
            yield columns, cells
            el.clear()


def load_samples(path, app=APP_BINARIES[0]):
    """[(time_ns, weight_ns, is_main_thread, frames)] of the app process."""
    samples = []
    for columns, cells in iter_rows(path):
        row = dict(zip(columns, cells))
        thread = row.get("thread") or ""
        process = row.get("process") or thread
        if not isinstance(thread, str):
            thread = str(thread)
        if app not in (process if isinstance(process, str) else str(process)) and app not in thread:
            continue
        stack = row.get("stack") or row.get("backtrace") or ()
        if not isinstance(stack, tuple):
            stack = ()
        time = row.get("time") if isinstance(row.get("time"), int) else row.get("sample-time")
        weight = row.get("weight") if isinstance(row.get("weight"), int) else 1_000_000
        if not isinstance(time, int):
            continue
        samples.append((time, weight, "Main Thread" in thread, stack))
    samples.sort(key=lambda s: s[0])
    return samples


def load_signpost_phases(paths):
    """[(name, start_ns, end_ns)] of the app's "Tour" intervals."""
    phases = []
    begins = {}
    for path in paths:
        try:
            for columns, cells in iter_rows(path):
                row = dict(zip(columns, cells))
                name = str(row.get("name") or "")
                subsystem = str(row.get("subsystem") or "")
                if name != "Tour" or (subsystem and "klimabilanz" not in subsystem):
                    continue
                message = str(row.get("message") or row.get("start-message") or row.get("format-string") or "")
                start = row.get("start") if isinstance(row.get("start"), int) else row.get("time")
                duration = row.get("duration")
                if isinstance(start, int) and isinstance(duration, int):
                    phases.append((message, start, start + duration))
                    continue
                kind = str(row.get("event-type") or "")
                ident = str(row.get("identifier") or row.get("signpost-id") or "")
                if kind.lower().startswith("begin") and isinstance(start, int):
                    begins[ident] = (message, start)
                elif kind.lower().startswith("end") and ident in begins and isinstance(start, int):
                    msg, begin = begins.pop(ident)
                    phases.append((msg, begin, start))
        except ET.ParseError:
            continue
    # Dedupe (interval + event tables can both be present).
    seen = set()
    unique = []
    for p in sorted(phases, key=lambda p: p[1]):
        key = (p[0], p[1] // 10_000_000)
        if key not in seen:
            seen.add(key)
            unique.append(p)
    return unique


def load_tour_phases(path, samples):
    """Fallback: tour.json phases (seconds since process start), aligned to the first sample of the app."""
    try:
        with open(path, encoding="utf-8") as f:
            tour = json.load(f)
    except (OSError, ValueError):
        return []
    if not samples:
        return []
    offset = samples[0][0]
    return [(p["name"], offset + int(p["start"] * 1e9), offset + int(p["end"] * 1e9)) for p in tour]


def short(name, limit=110):
    name = re.sub(r"\s+", " ", name)
    return name if len(name) <= limit else name[: limit - 1] + "…"


def is_app(binary):
    return binary in APP_BINARIES


def is_entry(symbol):
    """`main` / `KlimaBilanzApp.$main()`: on every main-thread stack – not an owner of the work below it."""
    return symbol == "main" or symbol.endswith(".$main()") or symbol.endswith("$main()")


def aggregate(samples, start=None, end=None, top=20):
    attributed, inclusive, leaf, binaries = {}, {}, {}, {}
    busy = 0
    count = 0
    for time, weight, main, stack in samples:
        if not main:
            continue
        if start is not None and not (start <= time <= end):
            continue
        busy += weight
        count += 1
        if stack:
            name, binary = stack[0]
            key = f"{short(name)}  [{binary or '?'}]"
            leaf[key] = leaf.get(key, 0) + weight
            binaries[binary or "?"] = binaries.get(binary or "?", 0) + weight
        owner = next((f for f in stack if is_app(f[1])), None)
        if owner:
            attributed[short(owner[0])] = attributed.get(short(owner[0]), 0) + weight
        else:
            attributed["(nur System-Frameworks)"] = attributed.get("(nur System-Frameworks)", 0) + weight
        seen = set()
        for name, binary in stack:
            if is_app(binary):
                key = short(name)
                if key not in seen:
                    seen.add(key)
                    inclusive[key] = inclusive.get(key, 0) + weight

    def ranked(d):
        return [{"name": k, "ms": round(v / 1e6, 1)} for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:top]]

    window = (end - start) / 1e9 if start is not None else None
    return {"mainThreadBusyMs": round(busy / 1e6, 1), "samples": count, "windowSeconds": window and round(window, 2),
            "attributed": ranked(attributed), "inclusive": ranked(inclusive), "leaf": ranked(leaf),
            "binaries": ranked(binaries)}



# MARK: - /usr/bin/sample reports

SAMPLE_LINE = re.compile(r"^(?P<indent>[ +!:|]*)(?P<count>\d+) (?P<rest>.+)$")
IDLE_LEAVES = {"mach_msg2_trap", "mach_msg_trap", "__psynch_cvwait", "__semwait_signal", "__workq_kernreturn",
               "semaphore_wait_trap", "__select", "kevent_id", "__ulock_wait", "__ulock_wait2"}


class Node:
    __slots__ = ("symbol", "binary", "count", "children")

    def __init__(self, symbol, binary, count):
        self.symbol, self.binary, self.count, self.children = symbol, binary, count, []


def parse_sample(path):
    """Root node of the main thread's call tree in a `sample` report (None if there is none)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("Call graph:"))
    except StopIteration:
        return None
    threads = []
    stack = []
    for line in lines[start + 1:]:
        if not line.strip():
            if threads:
                break
            continue
        if not line.startswith(" "):
            break
        m = SAMPLE_LINE.match(line)
        if not m:
            continue
        depth = (len(m["indent"]) - 4) // 2
        count = int(m["count"])
        rest = m["rest"]
        if depth <= 0 and rest.startswith("Thread_"):
            root = Node(rest.strip(), "thread", count)
            threads.append(root)
            stack = [root]
            continue
        if not stack:
            continue
        sm = re.match(r"(.*?)  \(in ([^)]+)\)", rest)
        symbol, binary = (sm[1].strip(), sm[2]) if sm else (rest.split("  [")[0].strip(), "?")
        node = Node(symbol, binary, count)
        while len(stack) > depth:
            stack.pop()
        if not stack:
            continue
        stack[-1].children.append(node)
        stack.append(node)
    if not threads:
        return None
    return next((t for t in threads if "main-thread" in t.symbol), threads[0])


def aggregate_tree(root, top=20):
    attributed, inclusive, leaf, binaries = {}, {}, {}, {}
    idle = 0

    def walk(node, owner, path):
        nonlocal idle
        is_app_node = is_app(node.binary) and not is_entry(node.symbol)
        own = node if is_app_node else owner
        added = False
        if is_app_node and node.symbol not in path:
            key = short(node.symbol)
            inclusive[key] = inclusive.get(key, 0) + node.count
            path.add(node.symbol)
            added = True
        child_total = sum(c.count for c in node.children)
        self_count = node.count - child_total
        if self_count > 0 and node is not root:
            if node.symbol in IDLE_LEAVES:
                idle += self_count
            else:
                name = short(own.symbol) if own else "(ohne App-Frame: SwiftUI/UIKit/CA)"
                attributed[name] = attributed.get(name, 0) + self_count
                key = f"{short(node.symbol)}  [{node.binary}]"
                leaf[key] = leaf.get(key, 0) + self_count
                binaries[node.binary] = binaries.get(node.binary, 0) + self_count
        for child in node.children:
            walk(child, own, path)
        if added:
            path.discard(node.symbol)

    walk(root, None, set())

    def ranked(d):
        return [{"name": k, "ms": float(v)} for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:top]]

    total = root.count
    return {"mainThreadBusyMs": float(total - idle), "samples": total, "windowSeconds": round(total / 1000, 2),
            "attributed": ranked(attributed), "inclusive": ranked(inclusive), "leaf": ranked(leaf),
            "binaries": ranked(binaries)}


def analyse_samples(tour, phases):
    """phases: [(name, report path)]"""
    result = {"tour": tour, "phaseSource": "sample", "sampleCount": 0, "phases": []}
    for name, path in phases:
        root = parse_sample(path)
        if root is None:
            continue
        entry = aggregate_tree(root)
        entry["phase"] = name
        result["sampleCount"] += entry["samples"]
        result["phases"].append(entry)
    result["whole"] = result["phases"][0] if result["phases"] else aggregate_tree(Node("empty", "thread", 0))
    return result

def analyse(prefix, app=APP_BINARIES[0]):
    profile = prefix + ".time-profile.xml"
    samples = load_samples(profile, app)
    phases = load_signpost_phases(sorted(glob.glob(prefix + ".signpost-*.xml")))
    source = "signposts"
    if not phases:
        phases = load_tour_phases(prefix + ".tour.json", samples)
        source = "tour.json"
    result = {"tour": os.path.basename(prefix), "phaseSource": source if phases else None,
              "sampleCount": len(samples), "whole": aggregate(samples), "phases": []}
    for name, start, end in phases:
        entry = aggregate(samples, start, end)
        entry["phase"] = name
        result["phases"].append(entry)
    return result


def markdown(results, top=8):
    lines = []
    for r in results:
        lines.append(f"#### Tour `{r['tour']}` – {r['sampleCount']} Samples"
                     + (f", Phasen aus {r['phaseSource']}" if r.get("phaseSource") else ", keine Phasen gefunden (ganze Aufnahme)"))
        lines.append("")
        blocks = r["phases"] or [dict(r["whole"], phase="ganze Aufnahme")]
        for p in blocks:
            window = f" in {p['windowSeconds']} s" if p.get("windowSeconds") else ""
            lines.append(f"**{p['phase']}** – Hauptthread belegt {p['mainThreadBusyMs']:.0f} ms{window}")
            lines.append("")
            if p["attributed"]:
                lines += ["| App-Funktion (inkl. Framework-Arbeit darunter) | ms |", "|---|---:|"]
                for item in p["attributed"][:top]:
                    lines.append(f"| `{item['name']}` | {item['ms']:.0f} |")
                lines.append("")
            if p["leaf"]:
                lines.append("Wo die CPU war: " + ", ".join(f"`{i['name']}` {i['ms']:.0f} ms" for i in p["leaf"][:4]))
                lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("prefix", nargs="+", help="<dir>/<tour> (expects <prefix>.time-profile.xml); with --sample: "
                                                  "<tour> <phase>=<report> …")
    parser.add_argument("--sample", action="store_true", help="read /usr/bin/sample reports")
    parser.add_argument("--app", default=APP_BINARIES[0])
    parser.add_argument("--json")
    args = parser.parse_args(argv)
    results = []
    if args.sample:
        tour, specs = args.prefix[0], args.prefix[1:]
        phases = [tuple(spec.split("=", 1)) for spec in specs if "=" in spec]
        result = analyse_samples(tour, phases)
        if result["phases"]:
            results.append(result)
        else:
            print(f"_{tour}: keine sample-Daten_\n")
        args.prefix = []
    for prefix in args.prefix:
        if not os.path.exists(prefix + ".time-profile.xml"):
            print(f"_{os.path.basename(prefix)}: keine Time-Profiler-Daten_\n")
            continue
        try:
            results.append(analyse(prefix, args.app))
        except (ET.ParseError, OSError) as error:
            print(f"_{os.path.basename(prefix)}: Export nicht lesbar ({error})_\n")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
    print(markdown(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
