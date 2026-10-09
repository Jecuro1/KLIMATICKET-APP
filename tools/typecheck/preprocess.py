#!/usr/bin/env python3
"""Line-preserving source preprocessor for the Linux type-check harness.

    preprocess.py <src-root> <out-root> <relative/path.swift>...

Copies each file from <src-root> to <out-root> (same relative path) and rewrites
the few constructs that cannot be type-checked on Linux as written. Every
rewrite stays on the same line, so `file:line` of every diagnostic is the line
in the real file (columns after a rewritten token on that line may shift).
Only code is touched - string literals and comments are left alone.

Rewrites:
  #available(iOS 26.N, *)    -> #available(iOS_26_1), ..., #available(iOS_26_N)
  #unavailable(iOS 26.N)     -> #unavailable(iOS_26_N)
  @available(iOS 26.N, *)    -> @available(iOS_26_1) ... @available(iOS_26_N)
      (versions <= 26.0, the deployment target, are left alone: always true on
       Linux). See Stubs/KBAvailability/KBAvailability.h.
  #selector(X)               -> __kbSelector(X)   (no Objective-C runtime on Linux;
                                 the method reference is still type-checked)
  @objc / @objc(name) / @objcMembers / @IBAction / @IBOutlet / @IBInspectable /
  @NSManaged                 -> blanked (Objective-C interop is disabled on Linux)
Macros (@Model, @Query, #Predicate, #Preview, @Observable, ...) are NOT
rewritten: they are expanded by real compiler plugins (see Macros/).
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen"))
import swiftiface as si  # noqa: E402

DEPLOYMENT = (26, 0)
MAX_MINOR = 5  # iOS 26.5 SDK (Xcode 26.6)


def _domains(version):
    parts = [int(x) for x in version.split(".")]
    while len(parts) < 2:
        parts.append(0)
    major, minor = parts[0], parts[1]
    if (major, minor) <= DEPLOYMENT:
        return None
    if major != 26 or minor > MAX_MINOR:
        return []  # newer than the SDK: leave a never-satisfiable marker below
    return ["iOS_26_%d" % m for m in range(1, minor + 1)]


AVAIL_RX = re.compile(r"#available\(\s*([^)]*)\)")
UNAVAIL_RX = re.compile(r"#unavailable\(\s*([^)]*)\)")
ATTR_AVAIL_RX = re.compile(r"@available\(\s*([^)]*)\)")
SELECTOR_RX = re.compile(r"#selector\(")
OBJC_RX = re.compile(r"@(?:objc(?:\([^)]*\))?|objcMembers|IBAction|IBOutlet|IBInspectable|NSManaged)\b(?!\()"
                     r"|@objc\([^)]*\)")


def _ios_version(args):
    m = re.search(r"\biOS\s+(\d+(?:\.\d+)*)", args)
    if m:
        return m.group(1)
    m = re.search(r"\biOS\s*,\s*introduced:\s*(\d+(?:\.\d+)*)", args)
    return m.group(1) if m else None


def _rewrite_available(m):
    v = _ios_version(m.group(1))
    if not v:
        return m.group(0)
    d = _domains(v)
    if d is None:
        return m.group(0)
    if not d:
        return "#available(iOS_26_99_unknown_SDK_version)"
    return ", ".join("#available(%s)" % x for x in d)


def _rewrite_unavailable(m):
    v = _ios_version(m.group(1))
    if not v:
        return m.group(0)
    d = _domains(v)
    if d is None:
        return m.group(0)
    if not d:
        return m.group(0)
    return "#unavailable(%s)" % d[-1]


def _rewrite_attr(m):
    args = m.group(1)
    if not re.match(r"\s*iOS\b", args):
        return m.group(0)
    v = _ios_version(args)
    if not v:
        return m.group(0)
    d = _domains(v)
    if d is None or not d:
        return m.group(0)
    return " ".join("@available(%s)" % x for x in d)


def _blank(m):
    return " " * len(m.group(0))


def rewrite(text):
    mask = si.code_mask(text)
    out = []
    i = 0
    n = len(text)
    rules = [(AVAIL_RX, _rewrite_available), (UNAVAIL_RX, _rewrite_unavailable),
             (ATTR_AVAIL_RX, _rewrite_attr), (SELECTOR_RX, lambda m: "__kbSelector("),
             (OBJC_RX, _blank)]
    while i < n:
        c = text[i]
        if mask[i] and c in "#@":
            for rx, fn in rules:
                m = rx.match(text, i)
                if m and all(mask[k] or text[k] == "\n" for k in range(m.start(), m.end())):
                    out.append(fn(m))
                    i = m.end()
                    break
            else:
                out.append(c)
                i += 1
            continue
        out.append(c)
        i += 1
    res = "".join(out)
    assert res.count("\n") == text.count("\n"), "preprocessor changed the number of lines"
    return res


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    rels = sys.argv[3:]
    if rels == ["-"]:
        rels = [l.strip() for l in sys.stdin if l.strip()]
    for rel in rels:
        text = open(os.path.join(src, rel), encoding="utf-8").read()
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        new = rewrite(text)
        if not os.path.exists(out) or open(out, encoding="utf-8").read() != new:
            with open(out, "w", encoding="utf-8") as fh:
                fh.write(new)


if __name__ == "__main__":
    main()
