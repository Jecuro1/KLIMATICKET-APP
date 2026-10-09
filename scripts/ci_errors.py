#!/usr/bin/env python3
"""Extracts unique compiler errors from a saved get_job_logs result file."""
import json, re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
try:
    data = json.loads(raw)
    if "logs" in data:
        raw = "\n".join(j.get("logs_content", "") for j in data["logs"])
    else:
        raw = data.get("logs_content", raw)
except Exception:
    pass
lines = raw.split("\n")
seen = []
for l in lines:
    l = re.sub(r"^\S+Z ", "", l)
    if "error:" in l and "NSConcreteFileHandle" not in l and "grep -E" not in l:
        l = l.replace("/Users/runner/work/KLIMATICKET-APP/KLIMATICKET-APP/", "")
        if l not in seen:
            seen.append(l)
for l in seen:
    print(l[:400])
print(f"--- {len(seen)} unique error lines")
