import wave4

M = [dict(id="V00", cat="control", desc="all good variants of wave 4 together (expect 0 errors)",
          edits=[(p["path"], None, p["good"]) for p in wave4.P], anyfile=False, control=True)]
for p in wave4.P:
    M.append(dict(id=p["id"], cat=p["cat"], desc=p["desc"], edits=[(p["path"], None, p["bad"])],
                  anyfile=False, expect=p["expect"]))
