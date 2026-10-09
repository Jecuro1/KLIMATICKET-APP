#!/usr/bin/env python3
"""Generate a Linux-buildable stub .swiftinterface from an Apple SDK interface.

    gen/transform.py <Module> [--sdk <iPhoneOSxx.sdk>] [--no-prune] [-v]

Reads   <sdk>/.../<Module>.swiftmodule/arm64e-apple-ios.swiftinterface
Writes  Stubs/<Module>/<Module>.swiftinterface   (generated, committed)
        Stubs/<Module>/PRUNED.txt                (what had to be dropped)

Every declaration is kept verbatim (labels, generics, defaults, attributes,
isolation) except for these mechanical, semantics-preserving rewrites:
  * bodies of @inlinable/@_alwaysEmitIntoClient/@_transparent declarations are
    removed (clients only need the signature);
  * internal / @usableFromInline / private declarations are removed;
  * @objc & friends are removed (no ObjC runtime on Linux);
  * @available for iOS is mapped to Linux-checkable forms:
      iOS <= 26.0 (deployment target)  -> dropped (always available)
      iOS 26.1 ... 26.5                -> @available(iOS_26_x) custom domain
      iOS unavailable / obsoleted      -> @available(*, unavailable)
      iOSApplicationExtension unavail. -> @available(KBAppOnly) custom domain
      other platforms                  -> dropped
  * a few type names that live in another module on Linux are re-qualified
    (CoreFoundation.CGFloat -> Foundation.CGFloat, Foundation.X -> FoundationShim.X ...).
Declarations that still do not compile on Linux (because they mention a type
from a framework we do not stub, e.g. CoreData or RealityKit) are pruned one by
one by compiling the interface and dropping the declaration an error points at.
PRUNED.txt lists every pruned declaration with the compiler error.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swiftiface as si  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build_stubs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # tools/typecheck
STUBS = os.path.join(ROOT, "Stubs")
DEFAULT_SDK = os.environ.get("KB_IOS_SDK_REF", "")

# iOS deployment target and SDK used by CI (Xcode 26.6 = iOS 26.5 SDK)
DEPLOYMENT = (26, 0)
SDK_VERSION = (26, 5)
DOMAINS = ["iOS_26_1", "iOS_26_2", "iOS_26_3", "iOS_26_4", "iOS_26_5"]
APP_ONLY_DOMAIN = "KBAppOnly"

LINUX_MODULES = {
    "Swift", "_Concurrency", "_StringProcessing", "Foundation", "Dispatch",
    "Observation", "Glibc", "Synchronization", "RegexBuilder", "Distributed",
    "FoundationEssentials", "FoundationInternationalization", "FoundationNetworking",
}

# Modules of the stub set (generated or hand written). An import of a module
# that is neither on Linux nor in the stub set is dropped (and everything that
# needs it is pruned).
STUB_MODULES = {m for m, _ in build_stubs.MODULES} | {"KBAvailability"}

# Foundation API that Darwin has and Linux Foundation lacks; provided by the
# FoundationShim module (Stubs/FoundationShim). Interfaces refer to them as
# `Foundation.X`, which would not find a shim type, so they are re-qualified.
SHIM_TYPES = set()
_shim_list = os.path.join(STUBS, "FoundationShim", "types.txt")
if os.path.exists(_shim_list):
    SHIM_TYPES = {l.strip() for l in open(_shim_list) if l.strip() and not l.startswith("#")}

CG_IN_FOUNDATION = {"CGFloat", "CGPoint", "CGSize", "CGRect"}
# Darwin Foundation types that live in FoundationNetworking on Linux.
NETWORKING_TYPES = ("CachedURLResponse HTTPCookie HTTPCookiePropertyKey HTTPCookieStorage HTTPURLResponse "
                    "NSMutableURLRequest NSURLRequest URLAuthenticationChallenge URLAuthenticationChallengeSender "
                    "URLCache URLCredential URLCredentialStorage URLProtectionSpace URLProtocol URLProtocolClient "
                    "URLRequest URLResponse URLSession URLSessionConfiguration URLSessionDataDelegate "
                    "URLSessionDataTask URLSessionDelegate URLSessionDownloadDelegate URLSessionDownloadTask "
                    "URLSessionStreamDelegate URLSessionStreamTask URLSessionTask URLSessionTaskDelegate "
                    "URLSessionTaskMetrics URLSessionTaskTransactionMetrics URLSessionUploadTask "
                    "URLSessionWebSocketDelegate URLSessionWebSocketTask").split()

# Module specific configuration ------------------------------------------------
MODULES = {
    # name: dict(src=<SDK module to read>, objc=<hand-written module re-exported in
    #            place of the framework's own Clang module>, extra_imports=[...],
    #            select=<selection list, see FoundationShim/select.txt>)
    "FoundationShim": dict(src="Foundation", select="FoundationShim/select.txt",
                           extra_imports=["@_exported import FoundationShim_ObjC",
                                          "@_exported import FoundationNetworking"]),
    "Combine": dict(),
    "Symbols": dict(),
    "os": dict(objc="os_C"),
    "OSLog": dict(objc="os"),
    "Accessibility": dict(objc="Accessibility_ObjC"),
    "UniformTypeIdentifiers": dict(),
    "CoreTransferable": dict(),
    "DeveloperToolsSupport": dict(),
    # objc: what the framework's own Clang module re-exports (its umbrella header):
    # SwiftUICore.h imports Foundation + CoreGraphics, SwiftUI.h imports UIKit.
    "SwiftUICore": dict(objc="CoreGraphics"),
    "SwiftUI": dict(objc="UIKit"),
    "Charts": dict(),
    "SwiftData": dict(),
    "_SwiftData_SwiftUI": dict(),
    "CryptoKit": dict(),
    "AppIntents": dict(objc="Foundation"),
    "_AppIntents_SwiftUI": dict(),
    "ActivityKit": dict(),
    "WidgetKit": dict(objc="Foundation"),
    "_MapKit_SwiftUI": dict(),
    "_AuthenticationServices_SwiftUI": dict(),
    "StoreKit": dict(objc="StoreKit_ObjC"),
    "_StoreKit_SwiftUI": dict(),
    "PhotosUI": dict(objc="PhotosUI_ObjC"),
    "_PhotosUI_SwiftUI": dict(),
    "TipKit": dict(),
}
GENERATED_ORDER = [m for m, _ in build_stubs.MODULES if m in MODULES]

DROP_ATTRS = re.compile(
    r"@(?:(?:inlinable|_alwaysEmitIntoClient|_transparent|nonobjc|objcMembers|_noAllocation|_noLocks"
    r"|_weakLinked|_unsafeInheritExecutor|IBAction|IBOutlet|IBInspectable|NSManaged)\b"
    r"|(?:_effects|_semantics|inline|_specialize|export|_objcRuntimeName|_originallyDefinedIn|backDeployed"
    r"|_dynamicReplacement|_spi)\([^)]*\)"
    r"|(?:objc|_objcImplementation)\b(?:\([^)]*\))?)\s*"
)


def ver(s):
    parts = [int(x) for x in s.split(".")[:3]]
    while len(parts) < 2:
        parts.append(0)
    return tuple(parts[:2])


def domains_for(v):
    """custom availability domain for an iOS version > deployment target."""
    if v <= DEPLOYMENT:
        return None
    minor = v[1] if v[0] == 26 else 99
    if v[0] > 26 or minor > 5:
        minor = 99  # newer than the SDK -> can not exist
    if minor == 99:
        return "UNAVAILABLE"
    return "iOS_26_%d" % minor


def split_args(s):
    out, d, cur, instr = [], 0, "", False
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"' and (i == 0 or s[i - 1] != "\\"):
            instr = not instr
        if not instr:
            if c in "([":
                d += 1
            elif c in ")]":
                d -= 1
            elif c == "," and d == 0:
                out.append(cur.strip())
                cur = ""
                i += 1
                continue
        cur += c
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def rewrite_available(args_text):
    """Return replacement attribute text ('' to drop)."""
    args = split_args(args_text)
    if not args:
        return ""
    first = args[0]
    m = re.match(r"^([A-Za-z_]+)\s+(\d+(?:\.\d+)*)$", first)
    if m or first == "*" and len(args) == 1:
        # shorthand: platform versions..., *
        ios = None
        for a in args:
            mm = re.match(r"^(iOS)\s+(\d+(?:\.\d+)*)$", a)
            if mm:
                ios = ver(mm.group(2))
            if re.match(r"^swift\s", a):
                return "@available(%s)" % args_text
        if ios is None:
            return ""   # not restricted on iOS
        d = domains_for(ios)
        if d is None:
            return ""
        if d == "UNAVAILABLE":
            return "@available(*, unavailable)"
        return "@available(%s)" % d
    plat = first
    rest = args[1:]
    kv = {}
    flags = set()
    for a in rest:
        if ":" in a:
            k, v = a.split(":", 1)
            kv[k.strip()] = v.strip()
        else:
            flags.add(a.strip())
    msg = kv.get("message")
    msgp = (", message: %s" % msg) if msg else ""
    if plat == "*" or plat == "swift":
        return "@available(%s)" % args_text
    if plat == "iOSApplicationExtension":
        if "unavailable" in flags:
            return "@available(%s)" % APP_ONLY_DOMAIN
        return ""
    if plat != "iOS":
        return ""
    if "unavailable" in flags:
        return "@available(*, unavailable%s)" % msgp
    if "obsoleted" in kv and ver(kv["obsoleted"]) <= DEPLOYMENT:
        return "@available(*, unavailable%s)" % msgp
    out = []
    if "introduced" in kv:
        d = domains_for(ver(kv["introduced"]))
        if d == "UNAVAILABLE":
            return "@available(*, unavailable)"
        if d:
            out.append("@available(%s)" % d)
    if "deprecated" in flags or ("deprecated" in kv and ver(kv["deprecated"]) <= DEPLOYMENT):
        out.append("@available(*, deprecated%s)" % msgp)
    return " ".join(out)


AVAIL_RE = re.compile(r"@(available|_spi_available)\(")


def rewrite_attrs(line, code):
    """Rewrite attributes on one physical line (code-only twin given for
    locating parentheses outside strings)."""
    out = []
    i = 0
    n = len(line)
    while i < n:
        m = AVAIL_RE.match(code, i)
        if m:
            # find matching paren in code
            j = m.end()
            d = 1
            while j < n and d:
                if code[j] == "(":
                    d += 1
                elif code[j] == ")":
                    d -= 1
                j += 1
            inner = line[m.end():j - 1]
            if m.group(1) == "_spi_available":
                rep = "@available(*, unavailable)"
            else:
                rep = rewrite_available(inner)
            out.append(rep)
            # swallow following spaces if we dropped it
            if not rep:
                while j < n and line[j] == " ":
                    j += 1
            i = j
            continue
        if code[i] == "@":
            m = DROP_ATTRS.match(line, i)
            if m:
                i = m.end()
                continue
        out.append(line[i])
        i += 1
    return "".join(out)


def _requalify_rules():
    rules = [
        # CoreGraphics geometry lives in Foundation on Linux
        (r"\b(?:CoreFoundation|CoreGraphics)\.(CGFloat|CGSize|CGPoint|CGRect)\b", r"Foundation.\1"),
        (r"\bCoreFoundation\.(CGAffineTransform|CGVector)\b", r"CoreGraphics.\1"),
        (r"\bDarwin\.", "Glibc."),
        (r"\bObjectiveC\.(NSObject|NSObjectProtocol)\b", r"Foundation.\1"),
        (r"\bObjectiveC\.(Selector)\b", r"FoundationShim.\1"),
        # CoreLocation's C types live in the private _LocationEssentials module on Darwin
        (r"\b_LocationEssentials\.", "CoreLocation."),
        (r"\bFoundation\.(%s)\b" % "|".join(sorted(map(re.escape, NETWORKING_TYPES))), r"FoundationNetworking.\1"),
    ]
    if SHIM_TYPES:
        rules.append((r"\bFoundation\.(%s)\b" % "|".join(sorted(map(re.escape, SHIM_TYPES))), r"FoundationShim.\1"))
    return [(re.compile(p), r) for p, r in rules]


_RULES = None


def requalify(line, code):
    """Re-qualify type names that live elsewhere on Linux. Matches are searched
    in the code-only twin of the line (so strings/comments are untouched); the
    replacement is applied to both so that their offsets stay aligned."""
    global _RULES
    if _RULES is None:
        _RULES = _requalify_rules()
    for rx, repl in _RULES:
        res_l, res_c, last = [], [], 0
        for m in rx.finditer(code):
            rep = m.expand(repl)
            res_l.append(line[last:m.start()])
            res_c.append(code[last:m.start()])
            res_l.append(rep)
            res_c.append(rep)
            last = m.end()
        if last:
            res_l.append(line[last:])
            res_c.append(code[last:])
            line, code = "".join(res_l), "".join(res_c)
    return line, code


# --------------------------------------------------------------------------- selection (FoundationShim)

MODULE_PREFIXES = ("Swift.", "Foundation.", "_Concurrency.", "Combine.", "Observation.")


def ext_path(f, u):
    code = f.code_lines[u.hdr]
    m = re.search(r"\bextension\s+([A-Za-z_][A-Za-z0-9_.]*(?:<[^{:]*?>)?(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", code)
    if not m:
        return ""
    p = re.sub(r"<[^>]*>", "", m.group(1))
    changed = True
    while changed:
        changed = False
        for pre in MODULE_PREFIXES:
            if p.startswith(pre):
                p = p[len(pre):]
                changed = True
    return p


def load_select(path):
    types, members = set(), []
    conforms = set()
    for line in open(path):
        line = line.split("#", 1)[0].strip() if not line.strip().startswith("member") else line.strip()
        if not line:
            continue
        kind, rest = line.split(None, 1)
        if kind == "type":
            types.add(rest.strip())
        elif kind == "member":
            owner, rx = rest.split(None, 1)
            members.append((owner, re.compile(rx)))
        elif kind == "conform":
            conforms.add(rest.strip())
    members.append(("__conforms__", conforms))
    return types, members


def select(f, types, members, log):
    conforms = set()
    for o, rx in members:
        if o == "__conforms__":
            conforms = rx
    members = [(o, rx) for o, rx in members if o != "__conforms__"]

    def member_ok(owner, u):
        attrs, rest, _ = si.strip_attrs(f.code_lines[u.hdr])
        for o, rx in members:
            if o == owner and rx.search(rest):
                return True
        return False

    def conforms_ok(u):
        hdr = f.code_lines[u.hdr]
        return any(re.search(r"[:,]\s*(?:[A-Za-z_]+\.)*" + re.escape(c) + r"\b", hdr) for c in conforms)

    for u in f.units:
        if u.kw == "import":
            continue
        if u.is_container() and u.kw != "extension":
            if u.name in types:
                continue
            # members of a type that Linux Foundation already declares: copy the
            # selected members into an extension of that type
            kept = 0
            for c in u.children:
                if not c.is_container() and member_ok(u.name, c):
                    kept += 1
                else:
                    c.pruned = True
            if kept:
                u.forced_header = ["extension Foundation.%s {" % u.name]
            else:
                u.pruned = True
            continue
        if u.kw == "extension":
            p = ext_path(f, u)
            if any(p == t or p.startswith(t + ".") for t in types) or conforms_ok(u):
                continue
            kept = 0
            for c in u.children:
                if c.is_container() and c.kw != "extension" and (p + "." + c.name) in types:
                    kept += 1
                elif member_ok(p, c):
                    kept += 1
                else:
                    c.pruned = True
            if not kept:
                u.pruned = True
            continue
        if not member_ok("", u):
            u.pruned = True


# --------------------------------------------------------------------------- body stripping

def body_brace(code_text):
    """Index of the '{' that opens a function body / accessor block: the first
    '{' at paren/bracket depth 0."""
    d = 0
    for i, c in enumerate(code_text):
        if c in "([":
            d += 1
        elif c in ")]":
            d -= 1
        elif c == "{" and d == 0:
            return i
    return -1


def accessor_summary(block_code):
    """block_code: text between the braces of a property accessor block."""
    d = 0
    toks = []
    for m in re.finditer(r"[{}]|[A-Za-z_][A-Za-z0-9_]*|\S", block_code):
        t = m.group(0)
        if t == "{":
            d += 1
            continue
        if t == "}":
            d -= 1
            continue
        if d == 0:
            toks.append(t)
    has_get = has_set = False
    get_mods, set_mods, get_eff = [], [], []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in ("get", "_read", "unsafeAddress", "read", "borrow"):
            has_get = True
            if t != "get":
                pass
            j = i - 1
            while j >= 0 and toks[j] in ("mutating", "nonmutating", "__consuming", "borrowing", "consuming"):
                get_mods.insert(0, toks[j])
                j -= 1
            k = i + 1
            while k < len(toks) and toks[k] in ("async", "throws"):
                get_eff.append(toks[k])
                k += 1
            if k < len(toks) and toks[k] == "(":
                # typed throws: throws(E)
                pass
        elif t in ("set", "_modify", "unsafeMutableAddress", "modify", "mutate"):
            has_set = True
            j = i - 1
            while j >= 0 and toks[j] in ("mutating", "nonmutating", "__consuming"):
                if toks[j] not in set_mods:
                    set_mods.insert(0, toks[j])
                j -= 1
        i += 1
    if not has_get and not has_set:
        return "{ get }"
    # de-dup (get + _read)
    gm = " ".join(dict.fromkeys(get_mods))
    sm = " ".join(dict.fromkeys(set_mods))
    s = "{ " + (gm + " " if gm else "") + "get" + ((" " + " ".join(get_eff)) if get_eff else "")
    if has_set:
        s += " " + (sm + " " if sm else "") + "set"
    return s + " }"


def strip_unit(f, u):
    """Rewrite a leaf unit: drop bodies, normalise accessor blocks, rewrite
    attributes. Returns list of output lines."""
    raw = f.raw_lines[u.start:u.end + 1]
    code = f.code_lines[u.start:u.end + 1]
    # attribute + availability rewrite line by line (keeps strings intact)
    new_raw, new_code = [], []
    for r, c in zip(raw, code):
        r2 = rewrite_attrs(r, c)
        c2 = si.code_only(r2)
        r3, c3 = requalify(r2, c2)
        new_raw.append(r3)
        new_code.append(c3)
    hdr_idx = u.hdr - u.start
    attr_lines = [l for l in new_raw[:hdr_idx] if l.strip()]
    decl_raw = "\n".join(new_raw[hdr_idx:])
    decl_code = "\n".join(new_code[hdr_idx:])
    if u.kw in ("func", "init", "deinit", "subscript", "var", "let", "macro"):
        b = body_brace(decl_code)
        if u.kw == "macro":
            b = -1
        if b >= 0:
            # matching close
            d = 0
            e = -1
            for i in range(b, len(decl_code)):
                if decl_code[i] == "{":
                    d += 1
                elif decl_code[i] == "}":
                    d -= 1
                    if d == 0:
                        e = i
                        break
            head = decl_raw[:b].rstrip()
            tail = decl_raw[e + 1:].strip() if e >= 0 else ""
            if u.kw in ("var", "subscript"):
                summ = accessor_summary(decl_code[b + 1:e])
                decl_raw = head + " " + summ + ((" " + tail) if tail else "")
            elif u.kw == "let":
                decl_raw = head
            else:
                decl_raw = head + ((" " + tail) if tail else "")
    # collapse multi-line headers that were bodies into one line
    lines = attr_lines + [l for l in decl_raw.split("\n")]
    return lines


def rewrite_container_header(f, u):
    raw = f.raw_lines[u.start:u.hdr + 1]
    code = f.code_lines[u.start:u.hdr + 1]
    out = []
    for r, c in zip(raw, code):
        r = re.sub(r",\s*Swift\.BitwiseCopyable\b", "", r)
        r = re.sub(r":\s*Swift\.BitwiseCopyable\s*,", ":", r)
        r = re.sub(r"\s*:\s*Swift\.BitwiseCopyable\b(?=\s*(\{|where))", "", r)
        c = si.code_only(r)
        r2 = rewrite_attrs(r, c)
        c2 = si.code_only(r2)
        r3, _ = requalify(r2, c2)
        if r3.strip() or not r.strip():
            out.append(r3)
    return out


def is_internal(u):
    m = u.mods
    if "@usableFromInline" in m or "internal" in m or "private" in m or "fileprivate" in m or "package" in m:
        return True
    if "@usableFromInline" in (u.attrs or ""):
        return True
    return False


def transform(f, module, cfg, log):
    """Apply the static rewrites to the parsed interface."""
    for u in list(f.walk()):
        if u.kw == "import":
            continue
        if is_internal(u) and not (u.parent is not None and u.parent.kw == "protocol"):
            u.pruned = True
            continue
        if u.kw == "extension" and re.search(r":\s*Swift\.BitwiseCopyable\s*\{", f.code_lines[u.hdr]):
            # BitwiseCopyable depends on the stored layout of Darwin CG types; irrelevant for clients
            u.pruned = True
            continue
        if u.is_container():
            u.lines = None
            hdr = getattr(u, "forced_header", None) or rewrite_container_header(f, u)
            u.hdr_override = hdr
        else:
            u.lines = strip_unit(f, u)
    # imports
    for u in f.units:
        if u.kw != "import":
            continue
        line = f.raw_lines[u.hdr]
        m = re.match(r"^(\s*)(@_exported\s+)?(@preconcurrency\s+)?(public\s+|internal\s+)?import\s+(?:(?:struct|class|enum|protocol|func|var|typealias)\s+)?([A-Za-z_][A-Za-z0-9_]*)", line)
        if not m:
            continue
        name = m.group(5)
        exported = bool(m.group(2))
        acc = (m.group(4) or "")
        if name == module:
            if cfg.get("objc"):
                u.lines = ["@_exported %simport %s" % (acc, cfg["objc"])]
            else:
                u.pruned = True
            continue
        if name == "Darwin":
            u.lines = ["%simport Glibc" % acc]
            continue
        if name in LINUX_MODULES or (name in STUB_MODULES and build_stubs.kind(name)):
            # strip submodule / declaration import detail, keep the access level
            u.lines = ["%s%simport %s" % ("@_exported " if exported else "", acc, name)]
            continue
        log.append("import dropped: %s" % name)
        u.pruned = True
    extra = cfg.get("extra_imports", [])
    if extra:
        f.extra_imports = extra


# --------------------------------------------------------------------------- render with header overrides

def render(f, module):
    out = []
    owners = []
    flags = ["-enable-library-evolution", "-swift-version", "5", "-enforce-exclusivity=checked",
             "-module-name", module, "-enable-bare-slash-regex",
             "-enable-experimental-feature", "CustomAvailability"]
    m = None
    for h in f.header:
        mm = re.search(r"swift-module-flags: (.*)", h)
        if mm:
            m = mm.group(1)
    if m:
        for up in re.findall(r"-enable-upcoming-feature (\S+)", m):
            flags += ["-enable-upcoming-feature", up]
        for ex in re.findall(r"-enable-experimental-feature (\S+)", m):
            if ex in ("Macros", "ExtensionMacros", "IsolatedAny2", "DebugDescriptionMacro",
                      "VariadicGenerics", "NoncopyableGenerics", "NonescapableTypes",
                      "LifetimeDependence", "Lifetimes", "AddressableParameters", "AddressableTypes",
                      "AllowUnsafeAttribute", "BuiltinModule"):
                continue
            flags += ["-enable-experimental-feature", ex]
    out.append("// swift-interface-format-version: 1.0")
    for h in f.header:
        if h.startswith("// swift-compiler-version"):
            out.append(h)
    out.append("// swift-module-flags: " + " ".join(flags))
    out.append("// GENERATED by tools/typecheck/gen/transform.py from the iOS SDK interface of %s." % module)
    out.append("// Do not edit by hand: change gen/transform.py or the hand-written stubs and regenerate.")
    # `public import`: some SDK interfaces enable InternalImportsByDefault, where a
    # plain import would make everything reached through it internal.
    out.append("public import KBAvailability")
    if module not in ("FoundationShim", "FoundationShim_ObjC", "Combine"):
        out.append("public import FoundationShim")
    owners += [[] for _ in out]
    for imp in getattr(f, "extra_imports", []):
        out.append(imp if " " in imp else "public import %s" % imp)
        owners.append([])

    def emit(units, path):
        for u in units:
            if u.pruned:
                continue
            p = path + [u]
            if u.is_container() and u.end > u.hdr:
                for ln in getattr(u, "hdr_override", None) or f.raw_lines[u.start:u.hdr + 1]:
                    out.append(ln)
                    owners.append(p)
                emit(u.children, p)
                out.append(f.raw_lines[u.end])
                owners.append(p)
                continue
            if u.is_container():
                for ln in getattr(u, "hdr_override", None) or f.raw_lines[u.start:u.end + 1]:
                    out.append(ln)
                    owners.append(p)
                continue
            lines = u.lines if u.lines is not None else f.raw_lines[u.start:u.end + 1]
            for ln in lines:
                out.append(ln)
                owners.append(p)

    emit(f.units, [])
    return "\n".join(out) + "\n", owners


# --------------------------------------------------------------------------- prune loop

ERR_RE = re.compile(r"^(.*?):(\d+):(\d+): error: (.*)$")


def build_cmd(iface, module, outdir, mc):
    return ["swiftc", "-frontend", "-compile-module-from-interface", iface,
            "-module-name", module, "-o", os.path.join(outdir, module + ".swiftmodule"),
            "-I", outdir, "-I", os.path.join(STUBS, "KBAvailability"), "-module-cache-path", mc]


def compile_iface(path, module, outdir, mc):
    cmd = build_cmd(path, module, outdir, mc)
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    errs = []
    other = []
    for line in p.stdout.split("\n"):
        m = ERR_RE.match(line)
        if m:
            if "failed to build module" in m.group(4):
                continue
            if os.path.abspath(m.group(1)) == os.path.abspath(path):
                errs.append((int(m.group(2)), int(m.group(3)), m.group(4)))
            elif "failed to build module" not in m.group(4):
                other.append(line)
    return p.returncode, errs, other, p.stdout


def describe(f, u):
    return f.raw_lines[u.hdr].strip()[:1000]


def prune_loop(f, module, out_path, outdir, mc, log, protect, max_iter=80, verbose=False):
    pruned = []
    for it in range(max_iter):
        text, owners = render(f, module)
        open(out_path, "w").write(text)
        t0 = time.time()
        rc, errs, other, full = compile_iface(out_path, module, outdir, mc)
        dt = time.time() - t0
        print("  [%s] iteration %d: %d errors (%.1fs)" % (module, it, len(errs), dt), flush=True)
        if rc == 0 and not errs:
            return pruned, True
        if not errs:
            print(full[-4000:])
            if other:
                print("\n".join(other[:30]))
            return pruned, False
        victims = {}
        conf_errs = []
        for (ln, col, msg) in errs:
            path = owners[ln - 1] if 0 < ln <= len(owners) else []
            if not path:
                print("    unowned error line %d: %s" % (ln, msg))
                continue
            v = path[-1]
            # conformance failure on a container header: drop only the conformance,
            # but only once nothing else inside the container is broken (the
            # conformance error is often a consequence of a broken member).
            mc_ = re.match(r"type '([^']+)' does not conform to protocol '([^']+)'", msg)
            if mc_ and v.is_container():
                conf_errs.append((v, mc_.group(2), msg))
                continue
            victims.setdefault(id(v), (v, msg))
        busy = set()
        for v, _ in victims.values():
            p = v.parent
            while p is not None:
                busy.add(id(p))
                p = p.parent
        if not victims:
            for v, proto, msg in conf_errs:
                if id(v) in busy:
                    continue
                if drop_conformance(f, v, proto):
                    log.append("conformance %s dropped from %s: %s" % (proto, describe(f, v), msg))
                else:
                    victims.setdefault(id(v), (v, msg))
        for v, msg in victims.values():
            if v.pruned:
                continue
            v.pruned = True
            d = describe(f, v)
            tag = "PROTECTED " if v.name in protect else ""
            pruned.append("%s%s\n      -> %s" % (tag, d, msg))
            if verbose:
                print("    prune %s%s :: %s" % (tag, d[:120], msg[:160]))
    return pruned, False


def drop_conformance(f, u, proto):
    hdr = list(getattr(u, "hdr_override", None) or f.raw_lines[u.start:u.hdr + 1])
    last = hdr[-1]
    short = proto.split(".")[-1]
    # remove ", X.proto" or ": X.proto," patterns from the inheritance clause
    pat_mid = re.compile(r",\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)*" + re.escape(short) + r"\b(?![.<])")
    pat_first = re.compile(r":\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)*" + re.escape(short) + r"\b(?![.<])\s*,")
    pat_only = re.compile(r"\s*:\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)*" + re.escape(short) + r"\b(?![.<])(?=\s*(\{|where))")
    for pat, rep in ((pat_mid, ""), (pat_first, ":"), (pat_only, "")):
        new, n = pat.subn(rep, last, count=1)
        if n:
            hdr[-1] = new
            u.hdr_override = hdr
            return True
    return False


def find_src(sdk, module):
    for base in ("System/Library/Frameworks", "System/Cryptexes/OS/System/Library/Frameworks", "usr/lib/swift"):
        if base.endswith("Frameworks"):
            p = os.path.join(sdk, base, module + ".framework", "Modules", module + ".swiftmodule",
                             "arm64e-apple-ios.swiftinterface")
        else:
            p = os.path.join(sdk, base, module + ".swiftmodule", "arm64e-apple-ios.swiftinterface")
        if os.path.exists(p):
            return p
    raise SystemExit("interface for %s not found in %s" % (module, sdk))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("--sdk", default=DEFAULT_SDK)
    ap.add_argument("--build", default=os.path.join(ROOT, ".build"))
    ap.add_argument("--no-prune", action="store_true")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    module = a.module
    cfg = MODULES.get(module, {})
    src = find_src(a.sdk, cfg.get("src", module))
    text = si.resolve_ifs(open(src).read())
    f = si.Iface(text)
    log = []
    if cfg.get("select"):
        types, members = load_select(os.path.join(STUBS, cfg["select"]))
        select(f, types, members, log)
    transform(f, module, cfg, log)
    os.makedirs(os.path.join(STUBS, module), exist_ok=True)
    if not build_stubs.build_all(a.build, upto=module, exclusive=True):
        sys.exit("dependencies of %s failed to build" % module)
    out_path = os.path.join(STUBS, module, module + ".swiftinterface")
    mc = os.path.join(a.build, "module-cache")
    a.build = os.path.join(a.build, "modules")
    protect = set(cfg.get("protect", []))
    if a.no_prune:
        text, _ = render(f, module)
        open(out_path, "w").write(text)
        return
    pruned, ok = prune_loop(f, module, out_path, a.build, mc, log, protect, verbose=a.v)
    with open(os.path.join(STUBS, module, "PRUNED.txt"), "w") as fh:
        fh.write("# Declarations of the iOS SDK interface of %s that were dropped because they\n" % module)
        fh.write("# do not compile on Linux with the stub set (mostly: they mention a type from a\n")
        fh.write("# framework that is not stubbed). Generated by gen/transform.py.\n")
        for l in log:
            fh.write("# %s\n" % l)
        for p in pruned:
            fh.write(p + "\n")
    print("%s: %s, %d pruned -> %s" % (module, "OK" if ok else "FAILED", len(pruned), out_path))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
