#!/usr/bin/env python3
"""Build the stub modules of the Linux type-check harness.

    build_stubs.py [--build DIR] [--upto Module] [--only Module] [-q]

Two kinds of stub modules live in Stubs/<Module>/:
  * <Module>.swiftinterface  generated from the iOS SDK by gen/transform.py.
                             Built with `swift-frontend -compile-module-from-interface`.
  * *.swift                  hand-written stand-ins (mostly Objective-C / C frameworks).
                             Built with `swiftc -emit-module -parse-as-library`.
Plus the Clang module Stubs/KBAvailability (availability domains, see README).

Modules are rebuilt only when their inputs (or a dependency) changed; the
cache key is stored next to the module in .build/modules/<Module>.key.
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
STUBS = os.path.join(HERE, "Stubs")
DEFAULT_BUILD = os.path.join(HERE, ".build")

# (module, dependencies). Order matters: every module after its deps.
# Cross-import overlays: (declaring module, bystander) -> overlay module.
MODULES = [
    ("Combine", []),
    ("FoundationShim_ObjC", []),
    ("FoundationShim", ["FoundationShim_ObjC", "Combine"]),
    ("CoreGraphics", ["FoundationShim"]),
    ("Symbols", []),
    ("os_C", []),
    ("os", ["os_C"]),
    ("OSLog", ["os"]),
    ("Accessibility_ObjC", ["FoundationShim"]),
    ("Accessibility", ["Accessibility_ObjC"]),
    ("UniformTypeIdentifiers", ["FoundationShim"]),
    ("CoreTransferable", ["Combine", "UniformTypeIdentifiers", "FoundationShim"]),
    ("DeveloperToolsSupport", ["CoreGraphics", "FoundationShim"]),
    ("SwiftUICore", ["Combine", "CoreTransferable", "DeveloperToolsSupport", "Symbols",
                     "UniformTypeIdentifiers", "CoreGraphics", "FoundationShim"]),
    ("UIKit", ["CoreGraphics", "FoundationShim", "UniformTypeIdentifiers", "Symbols", "Accessibility"]),
    ("SwiftUI", ["SwiftUICore", "UIKit", "Combine", "CoreTransferable", "DeveloperToolsSupport",
                 "Symbols", "UniformTypeIdentifiers"]),
    ("Charts", ["SwiftUI"]),
    ("SwiftData", ["FoundationShim"]),
    ("_SwiftData_SwiftUI", ["SwiftData", "SwiftUI"]),
    ("Security", ["FoundationShim"]),
    ("CryptoKit", ["Security", "FoundationShim"]),
    ("CoreLocation", ["FoundationShim"]),
    ("CoreSpotlight", ["FoundationShim", "UniformTypeIdentifiers"]),
    ("AppIntents", ["CoreLocation", "CoreSpotlight", "CoreTransferable", "UniformTypeIdentifiers", "FoundationShim"]),
    ("_AppIntents_SwiftUI", ["AppIntents", "SwiftUI"]),
    ("ActivityKit", ["Combine", "FoundationShim"]),
    ("WidgetKit", ["AppIntents", "_AppIntents_SwiftUI", "SwiftUI", "DeveloperToolsSupport", "ActivityKit"]),
    ("UserNotifications", ["FoundationShim", "CoreLocation"]),
    ("CoreMotion", ["FoundationShim"]),
    ("MetricKit", ["FoundationShim"]),
    ("ImageIO", ["CoreGraphics", "FoundationShim"]),
    ("MapKit", ["CoreLocation", "UIKit", "FoundationShim"]),
    ("_MapKit_SwiftUI", ["MapKit", "SwiftUI", "CoreLocation"]),
    ("AuthenticationServices", ["UIKit", "FoundationShim"]),
    ("_AuthenticationServices_SwiftUI", ["AuthenticationServices", "SwiftUI"]),
    ("StoreKit_ObjC", ["UIKit", "FoundationShim"]),
    ("StoreKit", ["StoreKit_ObjC", "Combine", "CryptoKit", "UIKit", "DeveloperToolsSupport"]),
    ("_StoreKit_SwiftUI", ["StoreKit", "SwiftUI"]),
    ("PDFKit", ["UIKit", "CoreGraphics", "FoundationShim"]),
    ("PhotosUI_ObjC", ["UIKit", "FoundationShim"]),
    ("PhotosUI", ["PhotosUI_ObjC"]),
    ("_PhotosUI_SwiftUI", ["PhotosUI", "SwiftUI", "CoreTransferable"]),
]

CROSS_IMPORTS = {
    ("SwiftData", "SwiftUI"): "_SwiftData_SwiftUI",
    ("AppIntents", "SwiftUI"): "_AppIntents_SwiftUI",
    ("MapKit", "SwiftUI"): "_MapKit_SwiftUI",
    ("AuthenticationServices", "SwiftUI"): "_AuthenticationServices_SwiftUI",
    ("StoreKit", "SwiftUI"): "_StoreKit_SwiftUI",
    ("PhotosUI", "SwiftUI"): "_PhotosUI_SwiftUI",
}

DEPS = dict(MODULES)


def swift_files(d):
    out = []
    for root, _, files in os.walk(d):
        for f in sorted(files):
            if f.endswith(".swift"):
                out.append(os.path.join(root, f))
    return sorted(out)


def kind(m):
    d = os.path.join(STUBS, m)
    if not os.path.isdir(d):
        return None
    if os.path.exists(os.path.join(d, m + ".swiftinterface")):
        return "iface"
    if swift_files(d):
        return "swift"
    return None


def inputs(m):
    d = os.path.join(STUBS, m)
    k = kind(m)
    if k == "iface":
        return [os.path.join(d, m + ".swiftinterface")]
    if k == "swift":
        return swift_files(d)
    return []


def swiftc():
    return os.environ.get("SWIFTC", "swiftc")


def common_flags(build):
    mods = os.path.join(build, "modules")
    return ["-I", mods, "-I", os.path.join(STUBS, "KBAvailability"),
            "-module-cache-path", os.path.join(build, "module-cache")]


def key_for(m, build, keys):
    h = hashlib.sha256()
    h.update(m.encode())
    h.update(keys["swiftc_version"])
    for p in inputs(m):
        h.update(p.encode())
        h.update(open(p, "rb").read())
    h.update(open(os.path.join(STUBS, "KBAvailability", "KBAvailability.h"), "rb").read())
    h.update(open(os.path.abspath(__file__), "rb").read())
    for d in DEPS.get(m, []):
        h.update(keys.get(d, "").encode())
    return h.hexdigest()


def build_module(m, build, quiet=False):
    mods = os.path.join(build, "modules")
    os.makedirs(mods, exist_ok=True)
    out = os.path.join(mods, m + ".swiftmodule")
    k = kind(m)
    t0 = time.time()
    if k == "iface":
        cmd = [swiftc(), "-frontend", "-compile-module-from-interface", inputs(m)[0],
               "-module-name", m, "-o", out] + common_flags(build)
    else:
        cmd = [swiftc(), "-emit-module", "-parse-as-library", "-swift-version", "5",
               "-enable-library-evolution", "-module-name", m, "-emit-module-path", out,
               "-enable-experimental-feature", "CustomAvailability",
               "-Xfrontend", "-disable-availability-checking",
               "-suppress-warnings"] + common_flags(build) + inputs(m)
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stdout)
        sys.stderr.write("\nerror: building stub module %s failed\n" % m)
        return False
    if not quiet:
        print("  built stub module %-32s (%.1fs)" % (m, time.time() - t0), flush=True)
    return True


def write_cross_imports(build):
    """Declare the cross-import overlays (`import SwiftData` + `import SwiftUI`
    implicitly imports _SwiftData_SwiftUI, as on iOS). The compiler looks for
    <Module>.swiftcrossimport/ next to the file that *defines* the module: the
    .swiftinterface for generated stubs, the built .swiftmodule otherwise."""
    mods = os.path.join(build, "modules")
    for (decl, bystander), overlay in CROSS_IMPORTS.items():
        if kind(overlay) is None:
            continue
        if kind(decl) == "iface":
            d = os.path.join(STUBS, decl, decl + ".swiftcrossimport")
        else:
            d = os.path.join(mods, decl + ".swiftcrossimport")
        os.makedirs(d, exist_ok=True)
        f = os.path.join(d, bystander + ".swiftoverlay")
        text = "---\nversion: 1\nmodules:\n  - name: %s\n" % overlay
        if not os.path.exists(f) or open(f).read() != text:
            with open(f, "w") as fh:
                fh.write(text)


MACROS = os.path.join(HERE, "Macros")


def host_lib_dir():
    """<toolchain>/usr/lib/swift/host: swift-syntax libraries the compiler itself uses."""
    exe = shutil.which(swiftc())
    if not exe:
        raise SystemExit("swiftc not found")
    d = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(exe))), "lib", "swift", "host")
    if not os.path.isdir(d):
        raise SystemExit("swift-syntax host libraries not found at %s (needed for macro plugins)" % d)
    return d


def build_macros(build=DEFAULT_BUILD, quiet=False):
    """Compile Macros/<Name>/*.swift into .build/plugins/lib<Name>.so (compiler plugin
    libraries, loaded with -load-plugin-library). Returns the list of .so paths."""
    out_dir = os.path.join(build, "plugins")
    os.makedirs(out_dir, exist_ok=True)
    host = host_lib_dir()
    ver = subprocess.run([swiftc(), "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
    libs = []
    for name in sorted(os.listdir(MACROS)):
        srcs = swift_files(os.path.join(MACROS, name))
        if not srcs:
            continue
        h = hashlib.sha256(ver.encode())
        for p in srcs:
            h.update(open(p, "rb").read())
        key = h.hexdigest()
        lib = os.path.join(out_dir, "lib%s.so" % name)
        kf = lib + ".key"
        if not (os.path.exists(lib) and os.path.exists(kf) and open(kf).read() == key):
            t0 = time.time()
            cmd = [swiftc(), "-emit-library", "-module-name", name, "-I", host, "-L", host,
                   "-lSwiftSyntax", "-lSwiftSyntaxMacros", "-lSwiftSyntaxBuilder", "-lSwiftDiagnostics",
                   "-lSwiftParser", "-lSwiftBasicFormat", "-Xlinker", "-rpath", "-Xlinker", host,
                   "-module-cache-path", os.path.join(build, "module-cache"), "-suppress-warnings",
                   "-o", lib] + srcs
            p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=out_dir)
            if p.returncode != 0:
                sys.stderr.write(p.stdout + "\nerror: building macro plugin %s failed\n" % name)
                raise SystemExit(1)
            open(kf, "w").write(key)
            if not quiet:
                print("  built macro plugin %-33s (%.1fs)" % (name, time.time() - t0), flush=True)
        libs.append(lib)
    return libs


def build_all(build=DEFAULT_BUILD, upto=None, only=None, quiet=False, exclusive=False):
    mods = os.path.join(build, "modules")
    os.makedirs(mods, exist_ok=True)
    keys = {"swiftc_version": subprocess.run([swiftc(), "--version"], stdout=subprocess.PIPE,
                                             stderr=subprocess.STDOUT, text=True).stdout.encode()}
    ok = True
    for m, _ in MODULES:
        if upto and m == upto and exclusive:
            break
        if kind(m) is None:
            if upto and m == upto:
                break
            continue
        k = key_for(m, build, keys)
        keys[m] = k
        kf = os.path.join(mods, m + ".key")
        out = os.path.join(mods, m + ".swiftmodule")
        if (only is None or m == only) and not (os.path.exists(out) and os.path.exists(kf)
                                                 and open(kf).read() == k):
            if os.path.exists(kf):
                os.remove(kf)
            if not build_module(m, build, quiet):
                ok = False
                break
            open(kf, "w").write(k)
        if upto and m == upto:
            break
    write_cross_imports(build)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=DEFAULT_BUILD)
    ap.add_argument("--upto")
    ap.add_argument("--only")
    ap.add_argument("-q", action="store_true")
    ap.add_argument("--macros", action="store_true", help="also build the macro plugins")
    a = ap.parse_args()
    ok = build_all(a.build, a.upto, a.only, a.q)
    if ok and a.macros:
        build_macros(a.build, a.q)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
