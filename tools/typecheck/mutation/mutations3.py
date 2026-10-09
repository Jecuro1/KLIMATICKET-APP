# Wave-3 catalogue built from wave3.P: one mutation per bad variant, plus the control run "Y00"
# (every good variant at once, must report 0 errors).
import wave3

M = [dict(id="Y00", cat="control", desc="all good variants of wave 3 together (expect 0 errors)",
          edits=[(p["path"], None, p["good"]) for p in wave3.P], anyfile=False, control=True)]
for p in wave3.P:
    M.append(dict(id=p["id"], cat=p["cat"], desc=p["desc"], edits=[(p["path"], None, p["bad"])],
                  anyfile=False, expect=p.get("expect", "error")))
