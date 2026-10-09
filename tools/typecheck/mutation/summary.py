#!/usr/bin/env python3
"""Markdown table + catch rate from run_mutations.py result files (later files override earlier ones).

    tools/typecheck/mutation/summary.py results.json [more.json ...]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mutations, mutations3, mutations4  # noqa: E402,E401

ALL = mutations.M + mutations3.M + mutations4.M
res = {}
for f in sys.argv[1:]:
    for r in json.load(open(f)):
        res[r["id"]] = r
rows, ok_n, total, excluded = [], 0, 0, []
for m in ALL:
    r = res.get(m["id"])
    if not r:
        continue
    ok = r["status"].startswith("caught") or r["status"] == "ok-no-error"
    if m.get("xcode_warning_only"):
        excluded.append(m["id"])
        verdict = "n/a (valid code)"
    else:
        total += 1
        ok_n += ok
        if m.get("control"):
            verdict = "control clean" if ok else "FALSE POSITIVE"
        elif m.get("expect") == "noerror":
            verdict = "no error (correct)" if ok else "FALSE POSITIVE"
        else:
            verdict = "caught" if ok else "MISSED"
    e = r["errors"][0] if r["errors"] else None
    where = ("%s:%d" % (os.path.basename(e[0]), e[1])) if e else ""
    msg = (e[3][:90] if e else "").replace("|", "\\|")
    rows.append("| %s | %s | %s | %s | %s | %s |" % (m["id"], m["cat"], m["desc"].replace("|", "\\|"), verdict, where, msg))
print("| id | category | mutation | result | first error | message |")
print("|---|---|---|---|---|---|")
print("\n".join(rows))
print()
print("%d / %d as expected = %.1f %% (excluded, turned out to be valid code: %s)" % (
    ok_n, total, 100.0 * ok_n / max(1, total), ", ".join(excluded) or "-"))
