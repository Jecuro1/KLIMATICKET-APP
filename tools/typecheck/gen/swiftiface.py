"""Tiny structural parser for Apple .swiftinterface files.

Interfaces printed by the Swift compiler are very regular: one declaration per
line, attributes on the lines before it, members indented inside `{ }` of the
enclosing type / extension, bodies only for @inlinable / @_alwaysEmitIntoClient
/ @_transparent declarations. This module turns such a file into a tree of
`Unit`s (one per declaration) so that gen/transform.py can rewrite or drop
single declarations and re-render the file.

It is NOT a Swift parser. It only needs to know which characters are code
(not string / comment), how braces nest, and where a declaration starts.
"""

import re

# --------------------------------------------------------------------------- lexing

_STR_START = re.compile(r'(#*)("""|")')


def code_mask(text):
    """Return a list of booleans, True where text[i] is code (not inside a
    string literal or comment). String interpolations count as code."""
    n = len(text)
    mask = [True] * n
    i = 0
    # stack of states: ('code', paren_depth) | ('str', hashes, multiline)
    stack = [("code", 0)]
    while i < n:
        st = stack[-1]
        c = text[i]
        if st[0] == "code":
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                j = text.find("\n", i)
                j = n if j < 0 else j
                for k in range(i, j):
                    mask[k] = False
                i = j
                continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                depth = 0
                j = i
                while j < n:
                    if text.startswith("/*", j):
                        depth += 1
                        j += 2
                        continue
                    if text.startswith("*/", j):
                        depth -= 1
                        j += 2
                        if depth == 0:
                            break
                        continue
                    j += 1
                for k in range(i, min(j, n)):
                    mask[k] = False
                i = j
                continue
            # raw / normal string start
            if c == '"' or c == "#":
                m = _STR_START.match(text, i)
                if m:
                    hashes = len(m.group(1))
                    multiline = m.group(2) == '"""'
                    for k in range(i, m.end()):
                        mask[k] = False
                    stack.append(("str", hashes, multiline))
                    i = m.end()
                    continue
            if c == "(":
                stack[-1] = ("code", st[1] + 1)
            elif c == ")":
                if st[1] == 0 and len(stack) > 1:
                    # end of interpolation
                    stack.pop()
                    mask[i] = False
                    i += 1
                    continue
                stack[-1] = ("code", st[1] - 1)
            i += 1
            continue
        # inside string
        _, hashes, multiline = st
        mask[i] = False
        if c == "\\":
            # escape: \#*( starts interpolation when hash count matches
            j = i + 1
            h = 0
            while j < n and text[j] == "#":
                h += 1
                j += 1
            if h == hashes and j < n and text[j] == "(":
                for k in range(i, j + 1):
                    mask[k] = False
                stack.append(("code", 0))
                i = j + 1
                continue
            i = j + 1 if h == hashes else i + 1
            continue
        close = ('"""' if multiline else '"') + "#" * hashes
        if text.startswith(close, i):
            for k in range(i, i + len(close)):
                mask[k] = False
            stack.pop()
            i += len(close)
            continue
        if c == "\n" and not multiline:
            # unterminated (should not happen) - bail out of string
            stack.pop()
        i += 1
    return mask


def code_only(text):
    m = code_mask(text)
    return "".join(ch if m[i] or ch == "\n" else " " for i, ch in enumerate(text))


# --------------------------------------------------------------------------- units

DECL_KW = (
    "struct", "class", "enum", "protocol", "extension", "actor",
    "func", "init", "deinit", "subscript", "var", "let", "typealias",
    "associatedtype", "case", "macro", "operator", "precedencegroup", "import",
)
CONTAINER_KW = {"struct", "class", "enum", "protocol", "extension", "actor"}
MODIFIERS = {
    "public", "open", "internal", "private", "fileprivate", "package", "final",
    "static", "override", "required", "convenience", "mutating", "nonmutating",
    "dynamic", "indirect", "lazy", "weak", "unowned", "optional", "prefix",
    "postfix", "infix", "nonisolated", "consuming", "borrowing", "__consuming",
    "distributed", "isolated", "unowned(safe)", "unowned(unsafe)", "__owned",
    "nonisolated(unsafe)", "@usableFromInline",
}

ATTR_RE = re.compile(r"@[A-Za-z_][A-Za-z0-9_.]*")


def strip_attrs(code):
    """Strip leading attributes (with balanced parens, generic args) from a
    code-only line. Returns (attrs_text, rest)."""
    s = code.lstrip()
    lead = len(code) - len(s)
    pos = 0
    while True:
        while pos < len(s) and s[pos] in " \t":
            pos += 1
        m = ATTR_RE.match(s, pos)
        if not m:
            break
        p = m.end()
        # generic args like @SwiftUI.PreviewMacroBodyBuilder<UIView>
        if p < len(s) and s[p] == "<":
            d = 0
            while p < len(s):
                if s[p] == "<":
                    d += 1
                elif s[p] == ">":
                    d -= 1
                    if d == 0:
                        p += 1
                        break
                p += 1
        if p < len(s) and s[p] == "(":
            d = 0
            while p < len(s):
                if s[p] == "(":
                    d += 1
                elif s[p] == ")":
                    d -= 1
                    if d == 0:
                        p += 1
                        break
                p += 1
        pos = p
    return s[:pos], s[pos:].strip(), lead


def decl_info(code_line):
    """Return (keyword, modifiers:set, name) for a code-only declaration line, or
    None if it is not a declaration line."""
    attrs, rest, _ = strip_attrs(code_line)
    if not rest:
        return None
    toks = re.findall(r"[A-Za-z_][A-Za-z0-9_]*(?:\((?:set|safe|unsafe|nonsending)\))?|\S", rest)
    mods = set()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "class" and i + 1 < len(toks) and toks[i + 1] in (
            "func", "var", "let", "subscript", "override", "final", "public", "open", "static"):
            mods.add("class")
            i += 1
            continue
        if t in MODIFIERS or re.match(r"^(public|private|fileprivate|internal|open|package)\(set\)$", t) \
                or t in ("unowned(safe)", "unowned(unsafe)", "nonisolated(unsafe)", "nonisolated(nonsending)"):
            mods.add(t)
            i += 1
            continue
        break
    if i >= len(toks):
        return None
    kw = toks[i]
    if kw not in DECL_KW:
        return None
    name = toks[i + 1] if i + 1 < len(toks) else ""
    if "@usableFromInline" in attrs:
        mods.add("@usableFromInline")
    return kw, mods, name, attrs


class Unit:
    def __init__(self):
        self.children = []
        self.pruned = False
        self.lines = None   # replacement lines (list[str]) if rewritten
        self.parent = None

    def is_container(self):
        return self.kw in CONTAINER_KW

    def __repr__(self):
        return f"Unit({self.kw} {self.name} {self.start}-{self.end})"


def resolve_ifs(text, choose=None):
    """Resolve #if/#elseif/#else/#endif. `choose(cond)` returns True if the
    branch should be taken; default: take the first branch unless the
    condition mentions canImport()."""
    if choose is None:
        choose = lambda cond: "canImport" not in cond
    lines = text.split("\n")
    code = code_only(text).split("\n")
    out = []
    stack = []  # [taking_now, already_taken, parent_active]
    active = True
    for raw, c in zip(lines, code):
        st = c.strip()
        m = re.match(r"#(if|elseif|else|endif)\b(.*)", st)
        if m:
            kind, cond = m.group(1), m.group(2).strip()
            if kind == "if":
                take = active and choose(cond)
                stack.append([take, take, active])
                active = take
            elif kind == "elseif":
                top = stack[-1]
                take = top[2] and not top[1] and choose(cond)
                top[0] = take
                top[1] = top[1] or take
                active = take
            elif kind == "else":
                top = stack[-1]
                take = top[2] and not top[1]
                top[0] = take
                top[1] = True
                active = take
            else:
                top = stack.pop()
                active = top[2]
            out.append("")
            continue
        out.append(raw if active else "")
    return "\n".join(out)


class Iface:
    def __init__(self, text):
        self.raw_lines = text.split("\n")
        self.code_lines = code_only(text).split("\n")
        assert len(self.raw_lines) == len(self.code_lines)
        self.header = []   # leading comment lines
        self.units = []
        self._parse()

    def _net(self, i):
        c = self.code_lines[i]
        return c.count("{") - c.count("}") + c.count("(") - c.count(")")

    def _parse(self):
        n = len(self.raw_lines)
        i = 0
        while i < n and self.raw_lines[i].startswith("//"):
            self.header.append(self.raw_lines[i])
            i += 1
        self.units = self._parse_block(i, n, None)

    def _parse_block(self, lo, hi, parent):
        units = []
        i = lo
        pending = None
        while i < hi:
            code = self.code_lines[i]
            st = code.strip()
            if not st:
                i += 1
                continue
            info = decl_info(code)
            if info is None:
                attrs, rest, _ = strip_attrs(code)
                if not rest:
                    if pending is None:
                        pending = i
                    i += 1
                    continue
                # Unknown line (e.g. #if, stray brace). Keep as an opaque unit.
                u = Unit()
                u.start = pending if pending is not None else i
                u.hdr = i
                d = self._net(i)
                j = i
                while d > 0 and j + 1 < hi:
                    j += 1
                    d += self._net(j)
                u.end = j
                u.hdr_end = i
                u.kw = "?"
                u.mods = set()
                u.name = st[:40]
                u.attrs = ""
                u.parent = parent
                units.append(u)
                pending = None
                i = j + 1
                continue
            kw, mods, name, attrs = info
            u = Unit()
            u.kw, u.mods, u.name, u.attrs = kw, mods, name, attrs
            u.start = pending if pending is not None else i
            u.hdr = i
            u.hdr_end = i
            u.parent = parent
            d = self._net(i)
            j = i
            while d > 0 and j + 1 < hi:
                j += 1
                d += self._net(j)
            u.end = j
            if u.is_container() and j > i:
                u.children = self._parse_block(i + 1, j, u)
            units.append(u)
            pending = None
            i = j + 1
        return units

    # ------------------------------------------------------------------ rendering
    def render(self):
        """Render to text. Returns (text, owners) where owners[k] is the list of
        units (outermost..innermost) owning output line k (0-based)."""
        out = list(self.header)
        owners = [[] for _ in out]

        def emit(units, path):
            for u in units:
                if u.pruned:
                    continue
                p = path + [u]
                if u.lines is not None:
                    for ln in u.lines:
                        out.append(ln)
                        owners.append(p)
                    continue
                if u.is_container() and u.end > u.hdr:
                    for k in range(u.start, u.hdr + 1):
                        out.append(self.raw_lines[k])
                        owners.append(p)
                    emit(u.children, p)
                    out.append(self.raw_lines[u.end])
                    owners.append(p)
                else:
                    for k in range(u.start, u.end + 1):
                        out.append(self.raw_lines[k])
                        owners.append(p)

        emit(self.units, [])
        return "\n".join(out) + "\n", owners

    def walk(self, units=None):
        units = self.units if units is None else units
        for u in units:
            yield u
            if u.children:
                yield from self.walk(u.children)

    def unit_text(self, u):
        return "\n".join(self.raw_lines[u.start:u.end + 1])

    def unit_code(self, u):
        return "\n".join(self.code_lines[u.start:u.end + 1])
