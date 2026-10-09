#!/usr/bin/env python3
"""Prints the UDID of the best available iPhone simulator (prefers newest iOS + Pro model)."""
import json, re, subprocess, sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
candidates = []
for runtime, devices in data["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ios = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        name = d["name"]
        if not name.startswith("iPhone"):
            continue
        num = re.search(r"iPhone (\d+)", name)
        score = (ios, int(num.group(1)) if num else 0, "Pro" in name and "Max" not in name, name)
        candidates.append((score, d["udid"], name, runtime))
if not candidates:
    sys.exit("No iPhone simulator available")
candidates.sort(reverse=True)
best = candidates[0]
print(f"Using {best[2]} ({best[3]})", file=sys.stderr)
print(best[1])
