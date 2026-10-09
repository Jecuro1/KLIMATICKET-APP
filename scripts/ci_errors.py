#!/usr/bin/env python3
"""Extracts unique compiler errors from a saved get_job_logs result file."""
import json, re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
try:
    raw = json.loads(raw).get("logs_content", raw)
except Exception:
    pass
lines = raw.split("\n")
seen = []
for l in lines:
    l = re.sub(r"^\S+Z ", "", l)
    if "error:" in l:
        l = l.replace("/Users/runner/work/KLIMATICKET-APP/KLIMATICKET-APP/", "")
        if l not in seen:
            seen.append(l)
for l in seen:
    print(l[:400])
print(f"--- {len(seen)} unique error lines")
