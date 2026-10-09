#!/usr/bin/env python3
"""Linux type-check harness for the KlimaBilanz iOS app (see README.md).

    run.py [--src <repo-root>] [--target app|widgets|all] [--warnings] [--notes]
           [--jobs N] [--keep-going] [--verbose]

Builds the stub SDK (Stubs/, cached in .build/), compiles the local Swift
packages listed in project.yml (KlimaCore, KlimaCloud, ...) from the checkout,
preprocesses the target sources (preprocess.py, line-preserving) and runs `swiftc -typecheck` for the app target (App/Sources + Shared) and the
widget extension (Widgets/Sources + Shared) the way Xcode would compile them
(Swift 5 mode, minimal concurrency checking, -parse-as-library).

Prints `path:line:col: error: message` with paths relative to the checkout and
exits 1 if there is any error.
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_stubs  # noqa: E402
import preprocess  # noqa: E402

BUILD = os.path.join(HERE, ".build")
DIAG_RX = re.compile(r"^(?P<path>/[^:]+):(?P<line>\d+):(?P<col>\d+): (?P<kind>error|warning|note|remark): (?P<msg>.*)$")

# Xcode target layout (project.yml)
TARGETS = {
    "app": dict(module="KlimaBilanz", dirs=["App/Sources", "Shared"], extension=False),
    "widgets": dict(module="KlimaBilanzWidgets", dirs=["Widgets/Sources", "Shared"], extension=True),
}


def swift_sources(root, dirs):
    out = []
    for d in dirs:
        base = os.path.join(root, d)
        for r, _, files in os.walk(base):
            for f in files:
                if f.endswith(".swift"):
                    out.append(os.path.relpath(os.path.join(r, f), root))
    return sorted(out)


def run(cmd, cwd=None):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=cwd)
    return p.returncode, p.stdout


def common_flags(extension, swift_version=5):
    mods = os.path.join(BUILD, "modules")
    lang = ["-swift-version", "5", "-strict-concurrency=minimal"] if swift_version < 6 else ["-swift-version", "6"]
    flags = lang + [
             "-I", mods, "-I", os.path.join(HERE, "Stubs", "KBAvailability"),
             "-module-cache-path", os.path.join(BUILD, "module-cache"),
             "-enable-experimental-feature", "CustomAvailability",
             "-Xfrontend", "-enable-cross-import-overlays",
             "-continue-building-after-errors",
             "-diagnostic-style", "llvm"]
    if extension:
        flags += ["-application-extension", "-Xcc", "-DKB_APP_EXTENSION"]
    return flags


def parse_diags(output, path_map):
    """Return list of (kind, relpath, line, col, msg, notes)."""
    diags = []
    for line in output.split("\n"):
        m = DIAG_RX.match(line)
        if not m:
            continue
        path = os.path.realpath(m.group("path"))
        rel = path_map(path)
        d = (m.group("kind"), rel, int(m.group("line")), int(m.group("col")), m.group("msg"))
        if d[0] == "note":
            if diags:
                diags[-1][5].append(d)
            continue
        diags.append(list(d) + [[]])
    return diags


def _call_args(text, start):
    """Text between the bracket at text[start] ("(" or "[") and its matching close bracket."""
    open_c = text[start]
    close_c = {"(": ")", "[": "]"}[open_c]
    depth, i = 0, start
    while i < len(text):
        c = text[i]
        if c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
        elif c == '"':
            i = text.index('"', i + 1)
        i += 1
    return text[start + 1:]


def project_packages(src):
    """Local Swift packages of project.yml: ({package: abs dir}, {Xcode target: [package, ...]})."""
    path = os.path.join(src, "project.yml")
    pkgs, deps = {}, {}
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    try:
        import yaml
        spec = yaml.safe_load(text) or {}
        for n, p in (spec.get("packages") or {}).items():
            if isinstance(p, dict) and p.get("path"):
                pkgs[n] = os.path.normpath(os.path.join(src, p["path"]))
        for tn, t in (spec.get("targets") or {}).items():
            deps[tn] = [d["package"] for d in ((t or {}).get("dependencies") or [])
                        if isinstance(d, dict) and "package" in d]
    except ImportError:
        # minimal fallback for the two blocks we need (2-space indented XcodeGen YAML)
        section, pkg, target = None, None, None
        for line in text.split("\n"):
            if re.match(r"^\S", line):
                section = line.split(":")[0].strip()
                continue
            m = re.match(r"^  (\S[^:]*):\s*$", line)
            if m:
                pkg = target = None
                if section == "packages":
                    pkg = m.group(1)
                elif section == "targets":
                    target = m.group(1)
                    deps[target] = []
                continue
            m = re.match(r"^\s+path:\s*(\S+)", line)
            if section == "packages" and pkg and m:
                pkgs[pkg] = os.path.normpath(os.path.join(src, m.group(1).strip("\"'")))
            m = re.match(r"^\s+-\s*package:\s*(\S+)", line)
            if section == "targets" and target and m:
                deps[target].append(m.group(1).strip("\"'"))
    if not pkgs and os.path.isdir(os.path.join(src, "Packages", "KlimaCore")):
        pkgs["KlimaCore"] = os.path.join(src, "Packages", "KlimaCore")
    return pkgs, deps


def package_modules(pkg_dir):
    """Parse Package.swift: [{name, dir, deps (module names), swift (5|6)}] for the regular
    (non-test) targets, plus {library product: [targets]}."""
    manifest = open(os.path.join(pkg_dir, "Package.swift"), encoding="utf-8").read()
    m = re.search(r"swift-tools-version:\s*(\d+)", manifest)
    tools = int(m.group(1)) if m else 5
    m = re.search(r"swift(?:LanguageModes|LanguageVersions)\s*:\s*\[\s*\.(?:v|version\(\s*\")(\d)", manifest)
    pkg_mode = int(m.group(1)) if m else (6 if tools >= 6 else 5)
    mods, consumed = [], 0
    for m in re.finditer(r"\.(target|executableTarget|testTarget|macro|plugin|binaryTarget|systemLibrary)\(", manifest):
        if m.start() < consumed:      # e.g. .target(name:) inside another target's dependencies
            continue
        args = _call_args(manifest, m.end() - 1)
        consumed = m.end() + len(args)
        if m.group(1) != "target":
            continue
        name = re.search(r'name:\s*"([^"]+)"', args).group(1)
        pm = re.search(r'\bpath:\s*"([^"]+)"', args)
        d = os.path.join(pkg_dir, pm.group(1) if pm else os.path.join("Sources", name))
        dm = re.search(r"dependencies:\s*\[", args)
        tdeps = []
        if dm:
            dtext = _call_args(args, dm.end() - 1)
            dtext = re.sub(r'package:\s*"[^"]*"', "", dtext)     # .product(name: "X", package: "Y") -> X
            dtext = re.sub(r"condition:\s*\.when\([^)]*\)", "", dtext)
            tdeps = re.findall(r'"([^"]+)"', dtext)
        lm = re.search(r"swiftLanguageMode\(\s*\.v(\d)", args) or \
            re.search(r'swiftLanguageVersion\(\s*\.v(\d)', args)
        mods.append(dict(name=name, dir=d, deps=tdeps, swift=int(lm.group(1)) if lm else pkg_mode))
    products = {}
    for m in re.finditer(r"\.library\(", manifest):
        args = _call_args(manifest, m.end() - 1)
        n = re.search(r'name:\s*"([^"]+)"', args)
        t = re.search(r"targets:\s*\[([^\]]*)\]", args)
        if n and t:
            products[n.group(1)] = re.findall(r'"([^"]+)"', t.group(1))
    return mods, products


def build_packages(src, work, verbose):
    """Compile every non-test target of the local packages listed in project.yml into a module
    (dependency order, cached by content hash). Returns ({Xcode target: [module dirs]},
    {Xcode target: [failed modules]}, diagnostics)."""
    pkgs, target_deps = project_packages(src)
    modules, products = {}, {}
    for pname, pdir in sorted(pkgs.items()):
        if not os.path.exists(os.path.join(pdir, "Package.swift")):
            continue
        mods, prods = package_modules(pdir)
        for mo in mods:
            modules[mo["name"]] = mo
        products[pname] = prods.get(pname) or [mo["name"] for mo in mods]
        for k, v in prods.items():
            products.setdefault(k, v)
    for mo in modules.values():     # a dependency may name a library product of another package
        mo["deps"] = [t for d in mo["deps"]
                      for t in (products[d] if d not in modules and d in products else [d])]
    shim_key = open(os.path.join(BUILD, "modules", "FoundationShim.key")).read()
    built, failed, diags = {}, set(), []

    def build(name, stack=()):
        if name in built or name in failed:
            return
        mo = modules.get(name)
        if mo is None or name in stack:
            return
        for d in mo["deps"]:
            build(d, stack + (name,))
        if any(d in failed for d in mo["deps"]):
            failed.add(name)
            return
        files = []
        for r, _, fs in os.walk(mo["dir"]):
            files += [os.path.join(r, f) for f in fs if f.endswith(".swift")]
        files.sort()
        h = hashlib.sha256()
        for f in files:
            h.update(f.encode())
            h.update(open(f, "rb").read())
        h.update(shim_key.encode())
        h.update(str(mo["swift"]).encode())
        for d in mo["deps"]:
            if d in built:
                h.update(built[d][1].encode())
        key = h.hexdigest()
        out_dir = os.path.join(work, "packages", name)
        os.makedirs(out_dir, exist_ok=True)
        kf = os.path.join(out_dir, name + ".key")
        out = os.path.join(out_dir, name + ".swiftmodule")
        if not (os.path.exists(out) and os.path.exists(kf) and open(kf).read() == key):
            cmd = ["swiftc", "-emit-module", "-parse-as-library", "-module-name", name,
                   "-emit-module-path", out, "-suppress-warnings",
                   "-Xfrontend", "-import-module", "-Xfrontend", "FoundationShim",
                   ] + common_flags(False, swift_version=mo["swift"])
            for d in mo["deps"]:
                if d in built:
                    cmd += ["-I", built[d][0]]
            t0 = time.time()
            rc, output = run(cmd + files)
            if verbose:
                print("  %s module: rc=%d (%.1fs)" % (name, rc, time.time() - t0))
            if rc != 0:
                ds = parse_diags(output, lambda p: os.path.relpath(p, src) if p.startswith(src) else p)
                diags.extend(ds or [["error", os.path.relpath(mo["dir"], src), 0, 0, output[-3000:], []]])
                failed.add(name)
                return
            open(kf, "w").write(key)
        built[name] = (out_dir, key)

    def closure(names):
        seen, todo = [], list(names)
        while todo:
            n = todo.pop()
            if n in seen or n not in modules:
                continue
            seen.append(n)
            todo += modules[n]["deps"]
        return seen

    target_dirs, target_failed = {}, {}
    for tname in sorted(target_deps):
        mods = closure([m for p in target_deps[tname] for m in products.get(p, [p])])
        for m in mods:
            build(m)
        target_dirs[tname] = [built[m][0] for m in mods if m in built]
        target_failed[tname] = [m for m in mods if m in failed]
    return target_dirs, target_failed, diags


def typecheck_target(name, src, work, pkg_dirs, plugins, args):
    t = TARGETS[name]
    rels = swift_sources(src, t["dirs"])
    tdir = os.path.join(work, "src")
    for rel in rels:
        text = open(os.path.join(src, rel), encoding="utf-8").read()
        out = os.path.join(tdir, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        new = preprocess.rewrite(text)
        if not os.path.exists(out) or open(out, encoding="utf-8").read() != new:
            open(out, "w", encoding="utf-8").write(new)
    if args.fast:
        mode = ["-typecheck", "-j%d" % args.jobs]
    else:
        # -emit-sil runs SILGen + the mandatory diagnostic passes (definite
        # initialization, missing return, exclusivity, unreachable code, ...),
        # which -typecheck alone does not reach. Whole-module, single job.
        mode = ["-emit-sil", "-wmo", "-o", os.devnull]
    cmd = ["swiftc"] + mode + ["-parse-as-library", "-module-name", t["module"]]
    for d in pkg_dirs:
        cmd += ["-I", d]
    cmd += ["-Xfrontend", "-import-module", "-Xfrontend", "FoundationShim",
           "-Xfrontend", "-import-module", "-Xfrontend", "KBAvailability",
           ] + common_flags(t["extension"])
    for p in plugins:
        cmd += ["-load-plugin-library", p]
    if not args.warnings:
        cmd.append("-suppress-warnings")
    cmd += [os.path.join(tdir, r) for r in rels]
    t0 = time.time()
    rc, output = run(cmd)
    dt = time.time() - t0
    real_tdir = os.path.realpath(tdir)

    def path_map(p):
        if p.startswith(real_tdir + os.sep):
            return os.path.relpath(p, real_tdir)
        if p.startswith(os.path.realpath(src) + os.sep):
            return os.path.relpath(p, os.path.realpath(src))
        if p.startswith(HERE + os.sep):
            return os.path.join("tools/typecheck", os.path.relpath(p, HERE))
        return p
    diags = parse_diags(output, path_map)
    if rc != 0 and not any(d[0] == "error" for d in diags):
        # driver / frontend failure without a parsable diagnostic
        diags.append(["error", "<%s>" % name, 0, 0, "swiftc failed:\n" + output[-3000:], []])
    return diags, dt, len(rels)


def die(msg):
    sys.stderr.write(msg.rstrip() + "\n")
    sys.exit(2)


def generator_key():
    """Everything the generated stubs depend on (besides the SDK, which is pinned)."""
    h = hashlib.sha256()
    h.update(subprocess.run(["swiftc", "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True).stdout.encode())
    paths = [os.path.join(HERE, "build_stubs.py"), os.path.join(HERE, "Stubs", "KBAvailability", "KBAvailability.h")]
    for d in ("gen", "Stubs"):
        for r, _, files in os.walk(os.path.join(HERE, d)):
            for f in files:
                if f.endswith((".py", ".sh", ".txt", ".swift")) and f != "PRUNED.txt":
                    paths.append(os.path.join(r, f))
    for p in sorted(paths):
        h.update(p[len(HERE):].encode())
        h.update(open(p, "rb").read())
    return h.hexdigest()


def ensure_generated(verbose, force=False):
    """The SDK-derived stubs (Stubs/<M>/<M>.swiftinterface) are generated locally
    from the iOS SDK's Swift interfaces and not committed. (Re)generate them when
    missing or when the generator / hand-written stubs changed."""
    sys.path.insert(0, os.path.join(HERE, "gen"))
    import transform
    stamp = os.path.join(BUILD, "generated.stamp")
    key = generator_key()
    missing = [m for m in transform.GENERATED_ORDER
               if not os.path.exists(os.path.join(HERE, "Stubs", m, m + ".swiftinterface"))]
    if not force and not missing and os.path.exists(stamp) and open(stamp).read() == key:
        return
    sdk = os.environ.get("KB_IOS_SDK_REF")
    if not sdk:
        sys.stderr.write("typecheck: SDK stubs missing or out of date, preparing iOS SDK interfaces ...\n")
        p = subprocess.run([os.path.join(HERE, "gen", "fetch_sdk.sh")], stdout=subprocess.PIPE, text=True)
        if p.returncode != 0:
            die("error: could not fetch the iOS SDK interfaces; set KB_IOS_SDK_REF (see README)")
        sdk = p.stdout.strip().split("\n")[-1]
    sys.stderr.write("typecheck: generating SDK stubs from %s (takes ~2 min) ...\n" % sdk)
    env = dict(os.environ, KB_IOS_SDK_REF=sdk)
    p = subprocess.run([os.path.join(HERE, "gen", "regen_all.sh")], env=env,
                       stdout=None if verbose else subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        sys.stderr.write((p.stdout or "")[-5000:])
        die("error: generating the SDK stubs failed")
    os.makedirs(BUILD, exist_ok=True)
    open(stamp, "w").write(generator_key())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=os.path.dirname(os.path.dirname(HERE)),
                    help="repository root to check (default: the checkout containing this tool)")
    ap.add_argument("--target", choices=["app", "widgets", "all"], default="all")
    ap.add_argument("--warnings", action="store_true", help="also print warnings")
    ap.add_argument("--notes", action="store_true", help="print the notes attached to each error")
    ap.add_argument("--jobs", "-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--fast", action="store_true",
                    help="type-check only (parallel, ~2x faster); skips the SIL diagnostics "
                         "(definite initialization, missing return, exclusivity)")
    ap.add_argument("--regen", action="store_true", help="force regeneration of the SDK-derived stubs")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()
    src = os.path.realpath(args.src)
    if not os.path.isdir(os.path.join(src, "App", "Sources")):
        die("error: %s does not look like the KlimaBilanz repository (no App/Sources)" % src)

    t_start = time.time()
    ensure_generated(args.verbose, force=args.regen)
    if not build_stubs.build_all(BUILD, quiet=not args.verbose):
        sys.exit(2)
    plugins = build_stubs.build_macros(BUILD, quiet=not args.verbose)
    work = os.path.join(BUILD, "work", hashlib.sha1(src.encode()).hexdigest()[:12])

    all_diags = []
    pkg_dirs, pkg_failed, pkg_diags = build_packages(src, work, args.verbose)
    all_diags += pkg_diags
    targets = ["app", "widgets"] if args.target == "all" else [args.target]
    for name in targets:
        xt = TARGETS[name]["module"]
        if pkg_failed.get(xt):
            sys.stderr.write("typecheck: %s target not checked: package module %s has errors\n"
                             % (name, ", ".join(pkg_failed[xt])))
            continue
        tw = os.path.join(work, name)
        diags, dt, nfiles = typecheck_target(name, src, tw, pkg_dirs.get(xt, []), plugins, args)
        if args.verbose:
            print("  %-8s %3d files, %d diagnostics (%.1fs)" % (name, nfiles, len(diags), dt))
        for d in diags:
            d.append(name)
        all_diags += diags

    # de-duplicate (Shared/ is compiled into both targets)
    seen = {}
    for d in all_diags:
        k = (d[0], d[1], d[2], d[3], d[4])
        if k in seen:
            if len(d) > 6 and d[6] not in seen[k][6]:
                seen[k][6] += "," + d[6]
            continue
        seen[k] = d
    shown = [d for d in seen.values() if d[0] == "error" or (args.warnings and d[0] == "warning")]
    shown.sort(key=lambda d: (d[1], d[2], d[3]))
    for d in shown:
        only_one = len(d) > 6 and "," not in d[6]
        tgt = (" [%s]" % d[6]) if only_one and args.target == "all" and d[1].startswith("Shared/") else ""
        print("%s:%d:%d: %s: %s%s" % (d[1], d[2], d[3], d[0], d[4], tgt))
        if args.notes:
            for n in d[5]:
                print("    %s:%d:%d: note: %s" % (n[1], n[2], n[3], n[4]))
    nerr = sum(1 for d in seen.values() if d[0] == "error")
    nwarn = sum(1 for d in seen.values() if d[0] == "warning")
    sys.stderr.write("typecheck: %d error(s)%s in %.0fs\n" % (
        nerr, (", %d warning(s)" % nwarn) if args.warnings else "", time.time() - t_start))
    sys.exit(1 if nerr else 0)


if __name__ == "__main__":
    main()
