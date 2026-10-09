#!/usr/bin/env python3
"""Mutation tests for the type-check harness (see tools/typecheck/README.md, "Mutation testing").

    tools/typecheck/mutation/run_mutations.py [--catalog mutations|mutations3|mutations4|all]
        [--only ID,ID] [--jobs N] [--repo <git checkout>] [--base-commit 26aec96] [--out results.json]

Every mutation is one realistic mistake (wrong label, iOS 26.1+ API without #available, Binding passed
for a closure, missing try/await, ...) applied to a pristine copy of the calibration commit (26aec96,
compiled green in Xcode CI). The harness must report an error in the mutated file for each of them.
Catalogues:
  mutations.py   edits of existing app/widget files (waves 1-2)
  mutations3.py  new-file mutations as good/bad pairs (wave 3); id *00 is the control run that
  mutations4.py  compiles every good variant together and must report 0 errors (wave 4: the API
                 added to the hand-written stubs in the mutation round)
A mutation with expect="noerror" is valid code (Xcode only warns) and must NOT produce an error;
`xcode_warning_only` marks entries that turned out to be valid code and are excluded from the rate.

The base snapshot is extracted with `git archive` into tools/typecheck/.build/mutation/base; mutated
copies are hard-link copies (edited files are rewritten, never modified in place).
"""
import argparse
import concurrent.futures as cf
import importlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.dirname(HERE)
sys.path.insert(0, HERE)
BUILD = os.path.join(TOOL, ".build", "mutation")
ERR_RX = re.compile(r"^(?P<path>[^:]+):(?P<line>\d+):(?P<col>\d+): error: (?P<msg>.*)$")
CATALOGS = ["mutations", "mutations3", "mutations4"]


def ensure_base(repo, commit):
    base = os.path.join(BUILD, "base-" + commit)
    if os.path.isdir(os.path.join(base, "App", "Sources")):
        return base
    tmp = base + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    archive = subprocess.run(["git", "-C", repo, "archive", commit], stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", tmp], input=archive, check=True)
    os.rename(tmp, base)
    return base


def apply(m, base, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.check_call(["cp", "-al", base, dst])
    locs = []
    for path, old, new in m["edits"]:
        p = os.path.join(dst, path)
        if old is None:
            text = new
            line0, nlines = 1, new.count("\n") + 1
        else:
            cur = open(p, encoding="utf-8").read()
            n = cur.count(old)
            if n != 1:
                raise SystemExit("%s: anchor occurs %d times in %s: %r" % (m["id"], n, path, old[:80]))
            i = cur.index(old)
            line0 = cur[:i].count("\n") + 1
            nlines = max(1, new.count("\n") + 1)
            text = cur.replace(old, new)
        if os.path.exists(p):
            os.unlink(p)  # break the hard link
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w", encoding="utf-8").write(text)
        locs.append((path, line0, line0 + nlines))
    return locs


def target_for(m):
    dirs = {e[0].split("/")[0] for e in m["edits"]}
    if dirs == {"App"}:
        return "app"
    if dirs == {"Widgets"}:
        return "widgets"
    return "all"


def run_one(m, base, harness):
    dst = os.path.join(BUILD, "w", m["id"])
    locs = apply(m, base, dst)
    p = subprocess.run([harness, "--src", dst, "--target", target_for(m)], stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True)
    errs = [(e.group("path"), int(e.group("line")), int(e.group("col")), e.group("msg"))
            for e in map(ERR_RX.match, p.stdout.split("\n")) if e]
    files = {l[0] for l in locs}
    in_file = [e for e in errs if e[0] in files]
    near = [e for e in in_file if any(e[0] == f and a - 2 <= e[1] <= b + 2 for f, a, b in locs)]
    if p.returncode == 2:
        status = "HARNESS-FAIL"
    elif m.get("control") or m.get("expect") == "noerror":
        status = "FALSE-POSITIVE" if errs else "ok-no-error"
    elif m.get("anyfile") and errs:
        status = "caught"
    elif near:
        status = "caught"
    elif in_file:
        status = "caught(elsewhere-in-file)"   # e.g. the switch statement of a removed case
    elif errs:
        status = "other-file-only"
    else:
        status = "MISSED"
    shutil.rmtree(dst, ignore_errors=True)
    return dict(id=m["id"], cat=m["cat"], desc=m["desc"], status=status, rc=p.returncode,
                errors=errs[:6], nerr=len(errs), tail=p.stdout[-1500:] if p.returncode == 2 else "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", default="all", help="mutations | mutations3 | mutations4 | all")
    ap.add_argument("--only", default="", help="comma separated mutation ids")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4)))
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(TOOL)),
                    help="git checkout that contains the base commit (default: this checkout)")
    ap.add_argument("--base-commit", default="26aec96")
    ap.add_argument("--harness", default=os.path.join(TOOL, "run.sh"))
    ap.add_argument("--out", default=os.path.join(BUILD, "results.json"))
    args = ap.parse_args()
    base = ensure_base(args.repo, args.base_commit)
    ms = []
    for c in (CATALOGS if args.catalog == "all" else [args.catalog]):
        ms += importlib.import_module(c).M
    if args.only:
        want = set(args.only.split(","))
        ms = [m for m in ms if m["id"] in want]
    for m in ms:   # validate every anchor before spending minutes on compiles
        apply(m, base, os.path.join(BUILD, "w", "_validate"))
    shutil.rmtree(os.path.join(BUILD, "w", "_validate"), ignore_errors=True)
    # warm the stub cache once so parallel runs do not regenerate concurrently
    subprocess.run([args.harness, "--src", base, "--target", "widgets"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    results = []
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        for f in cf.as_completed([ex.submit(run_one, m, base, os.path.abspath(args.harness)) for m in ms]):
            r = f.result()
            results.append(r)
            e = r["errors"][0] if r["errors"] else None
            print("%-5s %-26s %-18s %s" % (r["id"], r["status"], r["cat"],
                  ("%s:%d: %s" % (os.path.basename(e[0]), e[1], e[3][:110])) if e else ""), flush=True)
    order = {m["id"]: i for i, m in enumerate(ms)}
    results.sort(key=lambda r: order[r["id"]])
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(results, open(args.out, "w"), indent=1, ensure_ascii=False)
    meta = {m["id"]: m for m in ms}
    scored = [r for r in results if not meta[r["id"]].get("xcode_warning_only")]
    good = sum(1 for r in scored if r["status"].startswith("caught") or r["status"] == "ok-no-error")
    print("%d / %d as expected (%.1f %%); results in %s" % (good, len(scored), 100.0 * good / max(1, len(scored)), args.out))
    sys.exit(0 if good == len(scored) else 1)


if __name__ == "__main__":
    main()
