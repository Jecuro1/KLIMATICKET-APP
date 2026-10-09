#!/usr/bin/env python3
"""KlimaBilanz – executable reference of the place-suggestion engine (docs/PLACES_SUGGEST_SPEC.md).

Pure stdlib. Mirrors the Swift implementation in Packages/KlimaCore/Sources/KlimaCore/Places/ 1:1 (normalisation,
offline index, scoring, live LocMatch parsing, merge/dedupe) and generates the golden files the Swift tests check:

    python3 -I scripts/places_reference.py golden App/Resources/places.bin App/Resources/localities.bin \
        Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places
    python3 -I scripts/places_reference.py query App/Resources/places.bin App/Resources/localities.bin "wien w" [--ctx tripLog]

Rebuild the goldens whenever places.bin/localities.bin or the ranking change, and review the diff
(positions 4–5 inside one town are importance-driven and may legitimately move with a new dataset).
"""
from __future__ import annotations

import bisect
import json
import math
import os
import re
import sys
import time
import unicodedata
from dataclasses import dataclass, field

# ------------------------------------------------------------------------------------------------
# 1. Normalisation
# ------------------------------------------------------------------------------------------------

FOLD_TABLE = {}
for _src, _dst in [("äàáâãåāăą", "a"), ("æ", "ae"), ("çćčĉċ", "c"), ("ďđ", "d"), ("èéêëēėęěĕ", "e"), ("ğĝģ", "g"),
                   ("ìíîïīįı", "i"), ("ĺľłļ", "l"), ("ñńňņ", "n"), ("öòóôõøōőŏ", "o"), ("œ", "oe"), ("ŕřŗ", "r"),
                   ("śšşŝș", "s"), ("ß", "ss"), ("ťţț", "t"), ("üùúûūůűųŭ", "u"), ("ýÿ", "y"), ("źżž", "z"),
                   ("’‘`´", "'")]:
    for _c in _src:
        FOLD_TABLE[_c] = _dst


def fold(s: str) -> str:
    """SUGGEST_SPEC §3.1: lower-case → explicit Latin table → (NFKD minus combining marks for anything else)
    → ae/oe/ue → a/o/u. Identical in Swift (PlaceSearchBench/Normalizer.swift); golden: fold_golden.json."""
    out = []
    for ch in s.lower():
        if ch < "\x80":
            out.append(ch)
        elif ch in FOLD_TABLE:
            out.append(FOLD_TABLE[ch])
        else:
            d = unicodedata.normalize("NFKD", ch)
            out.append("".join(c for c in d if not unicodedata.combining(c)))
    return "".join(out).replace("ae", "a").replace("oe", "o").replace("ue", "u")


# Synonym groups: canonical form first. Every member is indexed as a form of a name token;
# a query token that equals a member matches every member exactly.
SYN_GROUPS = [
    ["hbf", "hauptbahnhof", "hbhf"],
    ["bf", "bahnhof", "bhf", "bhnf"],
    ["bahnhst", "bahnhaltestelle", "bhst"],
    ["hst", "haltestelle"],
    ["st", "sankt"],
    ["str", "strasse"],
    ["wiener", "wr"],
    ["abzw", "abzweigung"],
    ["flughafen", "airport"],
    ["karnten", "ktn"],
    ["niederosterreich", "no"],
    ["oberosterreich", "oo"],
    ["steiermark", "stmk"],
    ["burgenland", "bgld"],
    ["vorarlberg", "vbg", "vlbg"],
]
# City abbreviations (municipality-level aliases: valid for every stop of that municipality).
CITY_ALIASES = {"innsbruck": ["ibk"], "salzburg": ["sbg", "szbg"], "klagenfurt": ["klgft"],
                "wiener": ["wr"], "linz": [], "graz": []}
# IATA codes are record aliases (dataset aliases.json), see CURATED_RECORD_ALIASES.
CANON = {}
SYN_MEMBERS = {}
for g in SYN_GROUPS:
    for m in g:
        CANON[m] = g[0]
        SYN_MEMBERS[m] = g
ALIAS_FORMS = {}
for city, al in CITY_ALIASES.items():
    for a in al:
        ALIAS_FORMS.setdefault(city, []).append(a)
        CANON.setdefault(a, city)
        if a not in SYN_MEMBERS:
            SYN_MEMBERS[a] = [city, a]

STOPWORDS = {"an", "am", "der", "die", "das", "dem", "den", "bei", "beim", "in", "im", "ob", "a", "d", "i", "b",
             "und", "zum", "zur", "vom", "von", "auf"}
GENERIC = {"hbf", "bf", "bahnhst", "hst", "u", "s", "abzw", "bahn"}
SPLIT_SUFFIXES = ["hauptbahnhof", "bahnhof", "bahnhst", "strasse", "gasse", "platz", "weg", "brucke", "allee",
                  "kai", "gurtel", "ufer", "zeile", "steig", "siedlung", "kirche", "zentrum", "markt"]
RIVERS = {"donau", "mur", "ybbs", "rhein", "enns", "inn", "thaya", "traun", "drau", "krems", "murz", "lafnitz",
          "raab", "salzach", "triesting", "traisen", "gail", "leitha", "erlauf", "pielach", "kamp", "ager"}
# Region qualifiers / HAFAS suffixes a query may carry although the offline name lacks them ("Lauterach in Vlbg …",
# "… NÖ Abzw Ort"): unmatched they cost like a stopword. Never the first query token.
OPTIONAL_QUERY = {"niederosterreich", "oberosterreich", "vorarlberg", "burgenland", "steiermark", "karnten", "tirol",
                  "ort", "ortsmitte"}
STREET_TOKENS = {"str", "strasse", "gasse", "weg", "platz", "allee", "ring", "kai", "gurtel", "ufer", "zeile",
                 "steig", "promenade", "lande", "damm"}


def canon(t: str) -> str:
    return CANON.get(t, t)


@dataclass
class Tok:
    raw: str
    pos: int
    qualifier: bool = False
    forms: dict = field(default_factory=dict)  # form -> factor (1.0 official, 0.95 joined, 0.9 alias, 0.8 split)
    optional: bool = False                     # query side only (OPTIONAL_QUERY)

    @property
    def c(self):
        return canon(self.raw)

    @property
    def stop(self):
        return self.raw in STOPWORDS

    @property
    def generic(self):
        return self.c in GENERIC

    @property
    def numeric(self):
        return self.raw[:1].isdigit()

    @property
    def essential(self):
        return not (self.stop or self.generic or self.qualifier or self.numeric)


def lex(folded: str):
    """Raw lexemes of a folded string: [raw, qualifier, chunk, dotted]. Chunks are runs joined by '-' or '/';
    any other non-alphanumeric character ends a chunk; '(' '[' … ')' ']' mark qualifiers; '.' marks the token dotted."""
    toks, depth, buf, chunk = [], 0, "", 0

    def flush():
        nonlocal buf
        if buf:
            toks.append([buf, depth > 0, chunk, False])
            buf = ""

    for ch in folded:
        if ch.isalnum():
            buf += ch
        elif ch in "-/":
            flush()
        else:
            flush()
            if ch == "." and toks and not toks[-1][3] and toks[-1][2] == chunk:
                toks[-1][3] = True
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth = max(0, depth - 1)
            chunk += 1
    flush()
    return toks


# Token-level abbreviation rules (SUGGEST_SPEC §3.2), applied in this order. (lexemes, needs-dot-on, replacement)
ABBREV2 = [(("i", "t"), "in tirol"), (("i", "pg"), "im pongau"), (("i", "m"), "im muhlkreis"), (("a", "d"), "an der")]
ABBREV1 = {"wr": "wiener", "b": "bei", "i": "in"}


def abbreviate(lx):
    out, i = [], 0
    while i < len(lx):
        t = lx[i]
        nxt = lx[i + 1] if i + 1 < len(lx) else None
        done = False
        if t[3] and nxt is not None:
            for (a, b), rep in ABBREV2:
                if t[0] == a and nxt[0] == b and (b != "d" or nxt[3]):
                    for k, w in enumerate(rep.split()):
                        out.append([w, t[1], t[2] + k * 0.5, False])
                    i += 2
                    done = True
                    break
        if done:
            continue
        if t[3] and t[0] in ABBREV1 and (t[0] == "wr" or nxt is not None):
            out.append([ABBREV1[t[0]], t[1], t[2], False])
        else:
            out.append(t)
        i += 1
    return out


def tokenize(name: str, is_name=True):
    """Returns (tokens, trailing_boundary). Name tokens carry index forms."""
    lx = abbreviate(lex(fold(name)))
    toks = []
    chunks = {}
    for t in lx:
        chunks.setdefault(t[2], []).append(t)
    for key in sorted(chunks):
        ch_toks = chunks[key]
        parts = [t[0] for t in ch_toks]
        for k, (t, q, _, _) in enumerate(ch_toks):
            tok = Tok(t, len(toks), q or (k >= 1 and t in RIVERS))   # 'Linz/Donau' → donau is a qualifier
            if is_name:
                tok.forms[t] = 1.0
                for m in SYN_MEMBERS.get(t, []):
                    tok.forms.setdefault(m, 1.0 if CANON.get(m) == CANON.get(t) else 0.9)
                for a2 in ALIAS_FORMS.get(t, []):
                    tok.forms.setdefault(a2, 0.9)
                if len(parts) > 1 and k < len(parts) - 1:
                    tok.forms.setdefault("".join(parts[k:]), 0.95)
                for suf in SPLIT_SUFFIXES:
                    if t.endswith(suf) and len(t) - len(suf) >= 3:
                        tok.forms.setdefault(t[: len(t) - len(suf)], 0.8)
                        for m in SYN_MEMBERS.get(suf, [suf]):
                            tok.forms.setdefault(m, 0.8)
                        break
            toks.append(tok)
    trailing = bool(re.search(r"[\s.,]$", name))
    return toks, trailing


MUNICIPALITIES: set = set()   # folded municipality names (dataset A: municipality list)


def name_variants(name: str):
    """Official name plus the 'X (Ort)' → 'Ort X' variant (only when the bracket holds a known municipality)."""
    v = [name]
    m = re.match(r"^(.*?)\s*\(([^()]+)\)\s*$", name)
    if m and fold(m.group(2).strip()) in MUNICIPALITIES:
        v.append(f"{m.group(2)} {m.group(1)}")
    return v


# ------------------------------------------------------------------------------------------------
# 2. Records, importance
# ------------------------------------------------------------------------------------------------
RAIL = 1 | 4 | 8 | 16 | 32 | 4096
LONG_DISTANCE = 1 | 4 | 8


def importance_from_wt(wt):
    return math.log1p(max(0, min(wt, 32767))) / math.log1p(32767)


def importance_default(products):
    if products & LONG_DISTANCE:
        return 0.80
    if products & (16 | 32 | 4096):
        return 0.72
    if products & 256:
        return 0.75
    if products & 512:
        return 0.70
    if products & (64 | 2):
        return 0.55
    return 0.45


@dataclass
class Rec:
    id: str
    name: str
    lat: float
    lon: float
    kind: str = "stop"            # stop | station | town | address | poi
    products: int = 0
    importance: float = 0.5
    country: str = "at"
    state: str = ""
    municipality: str = ""
    aliases: list = field(default_factory=list)
    extId: str | None = None
    lid: str | None = None
    isMeta: bool = False
    source: str = "offline"       # offline | live | both
    liveRank: int | None = None
    poiCategory: str | None = None
    title: str | None = None
    subtitle: str | None = None
    wt: int | None = None
    place: str | None = None      # locality class (city/town/village/suburb/hamlet/neighbourhood/quarter)
    variants: list = field(default_factory=list)  # [(tokens, factor, is_secondary_part)]


def dist_m(a_lat, a_lon, b_lat, b_lon):
    la1, lo1, la2, lo2 = map(math.radians, (a_lat, a_lon, b_lat, b_lon))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def prepare(rec: Rec):
    rec.variants = []
    names = []
    for n in name_variants(rec.name):
        names.append((n, 1.0))
    first_tok = (tokenize(rec.name, is_name=False)[0] or [Tok("", 0)])[0].raw
    for a in rec.aliases:
        a_toks = [t.raw for t in tokenize(a, is_name=False)[0]]
        # local alias ('Jakominiplatz', 'St. Johann' for 'Graz St.Johann'): lacks the place prefix → weaker
        local = rec.kind in ("stop", "station") and first_tok and first_tok not in a_toks and canon(first_tok) not in map(canon, a_toks)
        for n in name_variants(a):
            names.append((n, 0.85 if local else 0.97))
    if rec.kind == "address":
        # "6020 Innsbruck, Maria-Theresien-Straße 1" → primary "Maria-Theresien-Straße 1 Innsbruck 6020"
        m = re.match(r"^(\d{4})\s+([^,]+),\s*(.+)$", rec.name)
        if m:
            names = [(f"{m.group(3)} {m.group(2)} {m.group(1)}", 1.0)]
    for n, f in names:
        toks, _ = tokenize(n)
        rec.variants.append((toks, f, None))
    if rec.kind == "poi":
        parts = [p.strip() for p in rec.name.split(",")]
        head = re.sub(r"\s*\(\d+\)\s*$", "", parts[0])
        tail = " ".join(parts[1:])
        ht, _ = tokenize(head)
        tt, _ = tokenize(tail)
        for t in tt:
            t.qualifier = True
        rec.variants = [(ht + [Tok(x.raw, len(ht) + i, True, x.forms) for i, x in enumerate(tt)], 1.0, len(ht))]
    return rec


# ------------------------------------------------------------------------------------------------
# 3. Offline index
# ------------------------------------------------------------------------------------------------
N_MAX = 1500   # max candidates scored per keystroke (importance order); exact-name and personal hits always added


class OfflineIndex:
    def __init__(self, records):
        # record id = rank by importance (desc) → every posting list is importance-ordered
        records = sorted(records, key=lambda r: (-r.importance, r.name, r.id))
        self.recs = [prepare(r) for r in records]
        post = {}
        self.exact = {}
        for ri, r in enumerate(self.recs):
            for toks, _, _ in r.variants:
                for t in toks:
                    for f in t.forms:
                        post.setdefault(f, set()).add(ri)
            for n in [r.name] + r.aliases:
                self.exact.setdefault(" ".join(t.c for t in tokenize(n, is_name=False)[0]), []).append(ri)
        self.forms = sorted(post)
        self.post = [sorted(post[f]) for f in self.forms]
        self.cum = [0]
        for pl in self.post:
            self.cum.append(self.cum[-1] + len(pl))
        self.tri = {}
        for fi, f in enumerate(self.forms):
            if len(f) >= 3 and f.isalpha():
                for g in trigrams(f):
                    self.tri.setdefault(g, []).append(fi)
        self.grid = {}
        for ri, r in enumerate(self.recs):
            if r.kind in ("stop", "station"):
                self.grid.setdefault(cell(r.lat, r.lon), []).append(ri)
        self.by_id = {r.id: ri for ri, r in enumerate(self.recs)}

    def prefix_range(self, p):
        lo = bisect.bisect_left(self.forms, p)
        hi = bisect.bisect_left(self.forms, p + "\uffff")
        return lo, hi

    def token_ranges(self, qt):
        """Form-index ranges matching a query token (prefix of raw or of an exact synonym key) + fuzzy forms."""
        keys = {qt}
        if qt in SYN_MEMBERS:
            keys |= set(SYN_MEMBERS[qt])
        ranges = [self.prefix_range(k) for k in keys]
        ranges = [(lo, hi) for lo, hi in ranges if hi > lo]
        fuzzy = {}
        if not ranges and len(qt) >= 4 and qt.isalpha():
            for fi, d in self.fuzzy_forms(qt):
                ranges.append((fi, fi + 1))
                fuzzy[self.forms[fi]] = d
        est = sum(self.cum[hi] - self.cum[lo] for lo, hi in ranges)
        return ranges, est, fuzzy

    def iterate(self, ranges, limit):
        """Lazy k-way merge of the posting lists in `ranges` → distinct record ids, ascending (= importance desc)."""
        import heapq
        heap = []
        for lo, hi in ranges:
            for fi in range(lo, hi):
                pl = self.post[fi]
                heap.append((pl[0], fi, 0))
        heapq.heapify(heap)
        out, last = [], -1
        while heap and len(out) < limit:
            ri, fi, k = heapq.heappop(heap)
            if ri != last:
                out.append(ri); last = ri
            if k + 1 < len(self.post[fi]):
                heapq.heappush(heap, (self.post[fi][k + 1], fi, k + 1))
        return out

    def fuzzy_forms(self, q):
        limit = 1 if len(q) <= 6 else 2
        counts = {}
        for g in trigrams(q):
            for fi in self.tri.get(g, ()):
                counts[fi] = counts.get(fi, 0) + 1
        need = max(1, len(trigrams(q)) - 3 * limit)
        res = []
        for fi, c in counts.items():
            if c < need:
                continue
            d = prefix_edit_distance(q, self.forms[fi], limit)
            if d is not None:
                res.append((fi, d))
        return res

    def nearest(self, lat, lon, k=5, max_m=2000, products=0):
        """Exact k nearest stops ≤ max_m: grid rings grow until no unvisited cell can hold a closer stop."""
        cy, cx = cell(lat, lon)
        found = []
        cell_m = 0.009 * 111195.0
        lon_cell_m = 0.0135 * 111195.0 * math.cos(math.radians(min(abs(lat), 80)))
        min_cell = max(1.0, min(cell_m, lon_cell_m))
        max_ring = min(60, math.ceil(max_m / min_cell) + 1)
        ring = 0
        while ring <= max_ring:
            for dy in range(-ring, ring + 1):
                for dx in range(-ring, ring + 1):
                    if max(abs(dy), abs(dx)) != ring:
                        continue
                    for ri in self.grid.get((cy + dy, cx + dx), ()):
                        r = self.recs[ri]
                        if products and not (r.products & products):
                            continue
                        d = dist_m(lat, lon, r.lat, r.lon)
                        if d <= max_m:
                            found.append((d, ri))
            if len(found) >= k:
                found.sort()
                if found[k - 1][0] <= ring * min_cell:
                    break
            if ring * min_cell > max_m:
                break
            ring += 1
        found.sort()
        return [(self.recs[ri], d) for d, ri in found[:k]]


def cell(lat, lon):
    return (int(math.floor(lat / 0.009)), int(math.floor(lon / 0.0135)))  # ≈ 1 km × 1 km in Austria


def trigrams(s):
    s = f"  {s} "
    return {s[i:i + 3] for i in range(len(s) - 2)}


def dl_distance(a, b, limit):
    """Optimal string alignment distance (Damerau), bounded."""
    if abs(len(a) - len(b)) > limit:
        return None
    prev2, prev = None, list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        rmin = cur[0]
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                v = min(v, prev2[j - 2] + 1)
            cur[j] = v
            rmin = min(rmin, v)
        if rmin > limit:
            return None
        prev2, prev = prev, cur
    return prev[len(b)] if prev[len(b)] <= limit else None


def prefix_edit_distance(q, t, limit):
    best = None
    for L in range(max(1, len(q) - limit), min(len(t), len(q) + limit) + 1):
        d = dl_distance(q, t[:L], limit)
        if d is not None and (best is None or d < best):
            best = d
    return best


# ------------------------------------------------------------------------------------------------
# 4. Scoring
# ------------------------------------------------------------------------------------------------
W = dict(text=100, importance=40, first=0.15, order=0.05, cov_exact=0.20, cov_partial=0.10, exact=0.50,
         skip_stop=0.05, skip_num=0.05, skip_relaxed=0.40, relaxed_anchor=0.25, foreign=-20, town_nonexact=-3,
         poi_stop_intent=-40, addr_stop_intent=-40, addr_street_intent=10, addr_number_intent=40, poi_number_intent=0,
         live_rank=5, fav=35, recent=25, near=8, near_short=16, near_km=30, near_generic=60, near_generic_km=20, tripLog_town=-1000, town_minor=-12)


@dataclass
class Query:
    text: str
    toks: list
    last_partial: bool
    has_number: bool
    street_intent: bool
    generic_only: bool = False


def parse_query(text):
    text = text[:64]                                   # limits [DECISION] §3.7: 64 characters / 8 tokens
    toks, trailing = tokenize(text, is_name=False)
    if len(toks) > 8:
        toks, trailing = toks[:8], True
    has_num = any(t.raw[:1].isdigit() for t in toks)
    street = any(t.raw in STREET_TOKENS or any(t.raw.endswith(s) for s in ("strasse", "gasse", "str"))
                 for t in toks)
    hard = [t for t in toks if not t.stop]
    generic_only = bool(hard) and all(canon(t.raw) in GENERIC | {"bahnhof", "hauptbahnhof", "haltestelle"} for t in hard)
    for k, t in enumerate(toks):
        t.optional = k > 0 and t.c in OPTIONAL_QUERY
    return Query(text, toks, not trailing, has_num, street, generic_only)


WEAK_SYN = {("bf", "hbf"): 0.9, ("bf", "bahnhst"): 0.85, ("hst", "bahnhst"): 0.85, ("hst", "bf"): 0.8}


def token_match(q: Tok, is_last_partial, nt: Tok, fuzzy):
    """Best m for query token q against name token nt."""
    best = WEAK_SYN.get((canon(q.raw), nt.c), 0.0)
    qkeys = {q.raw: 1.0}
    if q.raw in SYN_MEMBERS:
        for m in SYN_MEMBERS[q.raw]:
            qkeys.setdefault(m, 1.0)
    for f, fac in nt.forms.items():
        for qk in qkeys:
            if f == qk:
                best = max(best, 1.0 * fac)
            elif f.startswith(qk) and (fac > 0.8 or len(qk) >= 3):
                ratio = len(qk) / len(f)
                base = (0.70 + 0.30 * ratio) if is_last_partial else (0.60 + 0.30 * ratio)
                best = max(best, base * fac)
        if f in fuzzy:
            best = max(best, (0.50 - 0.10 * (fuzzy[f] - 1)) * fac)
    return best


def text_score(query: Query, rec: Rec, fuzzy_maps, relaxed=False):
    best = None
    n = len(query.toks)
    for toks, vfac, secondary_from in rec.variants:
        cand = []
        for i, q in enumerate(query.toks):
            last_p = query.last_partial and i == n - 1
            for j, nt in enumerate(toks):
                m = token_match(q, last_p, nt, fuzzy_maps[i])
                if m > 0:
                    if secondary_from is not None and j >= secondary_from:
                        m *= 0.6
                    elif nt.qualifier:
                        m *= 0.8
                    cand.append((max(2, len(q.raw)) * m, i, j, m))
        cand.sort(reverse=True)
        used_i, used_j, assign = set(), set(), {}
        for _, i, j, m in cand:
            if i in used_i or j in used_j:
                continue
            used_i.add(i); used_j.add(j); assign[i] = (j, m)
        skip = 0.0
        unmatched_hard = 0
        for i, q in enumerate(query.toks):
            if i in assign:
                continue
            if q.stop or q.optional:
                skip += W["skip_stop"]
            elif q.numeric and rec.kind not in ("address",):
                skip += W["skip_num"]
            else:
                unmatched_hard += 1
                skip += W["skip_relaxed"]
        if unmatched_hard > (1 if relaxed else 0):
            continue
        if not assign:
            continue
        wsum = sum(max(2, len(q.raw)) for i, q in enumerate(query.toks) if i in assign or not (q.stop or q.optional))
        quality = sum(max(2, len(query.toks[i].raw)) * m for i, (j, m) in assign.items()) / max(1, wsum)
        first = W["first"] if (0 in assign and assign[0][0] == 0 and assign[0][1] >= 0.7) else 0.0
        js = [assign[i][0] for i in sorted(assign)]
        order = W["order"] if (len(js) >= 2 and all(a < b for a, b in zip(js, js[1:]))) else 0.0
        ess = [t for t in toks if t.essential and (secondary_from is None or t.pos < secondary_from)]
        quals = [t for t in toks if t.qualifier and not t.generic and not t.stop and (secondary_from is None or t.pos < secondary_from)]
        matched_j = {j for j, _ in assign.values()}
        # coverage: essential tokens count 1, bracket/river qualifiers 0.5 ("Wien Hbf (Autoreisezug)" < "Wien Hbf")
        denom = len(ess) + 0.5 * len(quals)
        cov = ((sum(1 for t in ess if t.pos in matched_j) + 0.5 * sum(1 for t in quals if t.pos in matched_j)) / denom) if denom else 1.0
        last_i = n - 1
        last_exact = (last_i in assign and assign[last_i][1] >= 0.95) or not query.last_partial
        compl = (W["cov_exact"] if last_exact else W["cov_partial"]) * cov
        all_exact = all(m >= 0.95 for _, m in assign.values()) and unmatched_hard == 0
        # exact: every query token matched exactly AND every non-stopword, non-qualifier name token
        # (generic ones like Hbf/Bahnhof included) is matched → "wien" is exact for "Wien", not for "Wien Hbf"
        full = [t for t in toks if not t.stop and not t.qualifier and (secondary_from is None or t.pos < secondary_from)]
        all_name = all(t.pos in matched_j for t in full)
        exact = W["exact"] if (all_exact and all_name and last_exact) else 0.0
        if exact and (rec.kind in ("poi", "address") or vfac < 0.9):
            exact *= 0.5
        if exact and rec.kind == "town":
            exact *= PLACE_EXACT.get(rec.place, 1.0)
        anchor = W["relaxed_anchor"] if (relaxed and unmatched_hard and any(j == 0 for j, _ in assign.values())) else 0.0
        if query.generic_only:          # "bahnhof"/"hbf": every station matches; rank by distance + importance
            first = order = compl = exact = 0.0
        s = (quality + first + order + compl + exact + anchor - skip) * vfac
        if best is None or s > best[0]:
            best = (s, dict(quality=round(quality, 3), first=first, order=order, cov=round(cov, 2), exact=exact,
                            skip=skip))
    return best


PLACE_EXACT = {"city": 1.0, "town": 0.8, "village": 0.3, "suburb": 0.3, "hamlet": 0.0, "neighbourhood": 0.0,
               "quarter": 0.0, "isolated_dwelling": 0.0}


@dataclass
class Ctx:
    mode: str = "planner"          # planner | tripLog
    near: tuple | None = None
    favourites: dict = field(default_factory=dict)   # id -> True
    recents: dict = field(default_factory=dict)      # id -> (ageDays, count)
    limit: int = 8


def final_score(query: Query, rec: Rec, ts: float, ctx: Ctx):
    s = W["text"] * ts + W["importance"] * rec.importance
    if (rec.country and rec.country != "at") or rec.state == "X":
        s += W["foreign"]
    if rec.kind == "town":
        if ctx.mode == "tripLog":
            s += W["tripLog_town"]
        if rec.place in ("hamlet", "neighbourhood", "quarter", "isolated_dwelling"):
            s += W["town_minor"]
    if rec.kind == "poi":
        s += W["poi_number_intent"] if query.has_number else W["poi_stop_intent"]
    if rec.kind == "address":
        s += W["addr_number_intent"] if query.has_number else (W["addr_street_intent"] if query.street_intent else W["addr_stop_intent"])
    if rec.liveRank is not None:
        s += W["live_rank"] * (1 - (rec.liveRank - 1) / 10)
    if ctx.near:
        d = dist_m(ctx.near[0], ctx.near[1], rec.lat, rec.lon) / 1000
        if query.generic_only:      # "bahnhof", "hbf", "haltestelle": the user means the nearest one
            s += W["near_generic"] * max(0.0, 1 - d / W["near_generic_km"])
        else:
            w = W["near_short"] if len(query.text.strip()) <= 3 else W["near"]
            s += w * max(0.0, 1 - d / W["near_km"])
    if rec.id in ctx.favourites:
        s += W["fav"]
    if rec.id in ctx.recents:
        age, count = ctx.recents[rec.id]
        s += W["recent"] * 0.5 ** (age / 14) + 3 * min(count, 5)
    return s


def town_adjust(query, rec, detail):
    return W["town_nonexact"] if (rec.kind == "town" and not detail["exact"]) else 0.0


PARTIAL_TAILS = ["strasse", "gasse", "platz", "bahnhof"]
SPLIT_TAILS = sorted({m for suf in SPLIT_SUFFIXES for m in SYN_MEMBERS.get(suf, [suf])} | {"str"}, key=len, reverse=True)


def split_compounds(idx, q):
    """§3.6 query compound split: a token without any dictionary prefix match that ends in a street/station
    suffix is split ('mariahilferstrasse' → 'mariahilfer' + 'strasse'; last token may end in a partial suffix:
    'mariahilferstr')."""
    out, changed = [], False
    n = len(q.toks)
    for i, t in enumerate(q.toks):
        raw = t.raw
        lo, hi = idx.prefix_range(raw)
        if hi > lo or len(raw) < 6 or not raw.isalpha():
            out.append(t); continue
        if idx.fuzzy_forms(raw):
            out.append(t); continue                    # a typo of a real word ('insbruck') is not a compound
        last = q.last_partial and i == n - 1
        done = False
        for p in range(len(raw) - 2, 3, -1):           # head ≥ 4 characters
            head, tail = raw[:p], raw[p:]
            ok_tail = tail in SPLIT_TAILS or (last and len(tail) >= 2 and any(x.startswith(tail) for x in PARTIAL_TAILS))
            if ok_tail:
                hlo, hhi = idx.prefix_range(head)
                if hhi > hlo:
                    out += [Tok(head, 0, t.qualifier), Tok(tail, 0, t.qualifier)]
                    changed = done = True
                    break
        if not done:
            out.append(t)
    if changed:
        for k, t in enumerate(out):
            t.pos = k
            t.optional = k > 0 and t.c in OPTIONAL_QUERY
        q.toks = out
    return q


def search_offline(idx: OfflineIndex, text: str, ctx: Ctx, limit=None, stats=None):
    limit = limit or ctx.limit
    q = parse_query(text)
    if not q.toks:
        return []
    q = split_compounds(idx, q)
    info = [idx.token_ranges(t.raw) for t in q.toks]
    fuzzy_maps = [fz for _, _, fz in info]
    hard = [i for i, t in enumerate(q.toks) if not (t.stop or t.numeric or t.optional)] or list(range(len(q.toks)))
    gen = min(hard, key=lambda i: info[i][1])                       # most selective token generates candidates
    cands = idx.iterate(info[gen][0], N_MAX)
    extra = set(idx.exact.get(" ".join(t.c for t in q.toks), []))   # exact full-name hits always scored
    extra |= {idx.by_id[i] for i in list(ctx.favourites) + list(ctx.recents) if i in idx.by_id}
    pool = list(dict.fromkeys(cands + sorted(extra)))
    results = score_set(idx, q, pool, fuzzy_maps, ctx, relaxed=False)
    relaxed = False
    if len(results) < 3 and len(hard) >= 2:
        relaxed = True                                              # one non-stopword token may stay unmatched
        two = sorted(hard, key=lambda i: info[i][1])[:2]
        union = idx.iterate([r for i in two for r in info[i][0]], N_MAX)
        results = score_set(idx, q, list(dict.fromkeys(union + pool)), fuzzy_maps, ctx, relaxed=True)
    if stats is not None:
        stats.update(generator=q.toks[gen].raw, est=info[gen][1], scored=len(pool), relaxed=relaxed)
    results.sort(key=lambda x: (-x[0], -x[1].importance, len(x[1].name), x[1].name, x[1].id))
    return results[:limit]


def score_set(idx, q, cands, fuzzy_maps, ctx, relaxed):
    out = []
    for ri in cands:
        r = idx.recs[ri]
        if ctx.mode == "tripLog" and r.kind == "town":
            continue
        ts = text_score(q, r, fuzzy_maps, relaxed)
        if ts is None:
            continue
        s = final_score(q, r, ts[0], ctx) + town_adjust(q, r, ts[1])
        out.append((s, r, ts[1]))
    return out


# ------------------------------------------------------------------------------------------------
# 5. Live (LocMatch) parsing, plausibility filter, merge/dedupe
# ------------------------------------------------------------------------------------------------

def live_items(resp, query_text):
    s = (resp.get("svcResL") or [{}])[0]
    if s.get("err") != "OK":
        return []
    res = s["res"]
    ico = res.get("common", {}).get("icoL", [])
    out = []
    for rank, l in enumerate(res.get("match", {}).get("locL", []), start=1):
        typ = l.get("type")
        crd = l.get("crd") or {}
        lat, lon = crd.get("y", 0) / 1e6, crd.get("x", 0) / 1e6
        kind = {"S": "stop", "A": "address", "P": "poi"}.get(typ, "stop")
        ext = l.get("extId")
        r = Rec(id=f"live:{typ}:{ext or l.get('lid')}", name=l.get("name", ""), lat=lat, lon=lon, kind=kind,
                products=l.get("pCls", 0), country=(l.get("countryCodeL") or ["at" if typ != "S" else ""])[0] or "",
                extId=ext, lid=l.get("lid"), isMeta=bool(l.get("meta")), source="live", liveRank=rank, wt=l.get("wt"))
        if typ == "S":
            r.importance = importance_from_wt(l.get("wt", 0)) if "wt" in l else importance_default(r.products)
            if r.isMeta and ext and ext.startswith("11"):
                r.kind = "town"
            r.state = state_from_extid(ext)
            if not r.country:
                r.country = "at" if r.state else ""
        else:
            r.importance = 0.6
            i = ico[l["icoX"]] if isinstance(l.get("icoX"), int) and l["icoX"] < len(ico) else {}
            r.poiCategory = i.get("res")
        out.append(prepare(r))
    # P1 collapse: POIs 'Name (1)', 'Name (2)' within 150 m are one place
    pois, rest = [], []
    for r in out:
        if r.kind == "poi":
            base = re.sub(r"\s*\(\d+\)\s*$", "", r.name)
            if any(re.sub(r"\s*\(\d+\)\s*$", "", p.name) == base and dist_m(p.lat, p.lon, r.lat, r.lon) <= 150 for p in pois):
                continue
            r.name = base
            prepare(r)
            pois.append(r)
        rest.append(r)
    out = rest
    # C1 collapse: HAFAS publishes town-district metas and station metas with identical crd/pCls/wt
    keep = []
    for r in out:
        dup = None
        for k in keep:
            if (r.kind in ("stop", "town") and k.kind in ("stop", "town") and r.isMeta and k.isMeta
                    and r.products == k.products and r.wt == k.wt and dist_m(r.lat, r.lon, k.lat, k.lon) <= 60):
                dup = k
                break
        if dup is None:
            keep.append(r)
        else:
            station, other = (r, dup) if (r.extId or "").startswith(("12", "13")) else (dup, r)
            station.aliases.append(other.name)
            station.liveRank = min(r.liveRank, dup.liveRank)
            station.kind = "station"
            prepare(station)
            if station is r:
                keep[keep.index(dup)] = r
    return keep


def state_from_extid(ext):
    """[OBSERVED] Austrian state digit: 6-digit Verbund stop codes → 1st digit; 7-digit metas 11/12/13/14 → 3rd digit."""
    if not ext:
        return ""
    m = {"1": "B", "2": "K", "3": "NÖ", "4": "OÖ", "5": "S", "6": "ST", "7": "T", "8": "V", "9": "W"}
    if len(ext) == 6:
        return m.get(ext[0], "")
    if len(ext) == 7 and ext[:2] in ("11", "12", "13", "14"):
        return m.get(ext[2], "")
    return ""


def essential_set(name):
    v = name_variants(name)
    toks, _ = tokenize(v[-1])
    moved = len(v) > 1   # 'X (Ort)' → 'Ort X': the bracket token became a real token
    return {t.c for t in toks if (t.essential or (moved and t.qualifier)) and not t.generic}


def name_sim(a, b):
    """Jaccard over essential canonical tokens; a single extra municipality token counts as equal
    ('Riedenburg' ≈ 'Bregenz Riedenburg Bahnhst', 'Floridsdorf (Wien)' ≈ 'Wien Floridsdorf')."""
    A, B = essential_set(a), essential_set(b)
    if not A or not B:
        return 0.0
    if A != B and (A < B or B < A):
        extra = (B - A) if A < B else (A - B)
        if len(extra) == 1 and next(iter(extra)) in MUNICIPALITIES:
            return 1.0
    return len(A & B) / len(A | B)


def rec_sim(o: Rec, l: Rec):
    return max(name_sim(x, y) for x in [o.name] + o.aliases for y in [l.name] + l.aliases)


def same_place(o: Rec, l: Rec):
    """Dedupe rule D1–D4 (SUGGEST_SPEC §6.2)."""
    if o.extId and l.extId and o.extId == l.extId:
        return True                                                    # D1 same HAFAS extId
    if o.kind in ("address", "poi") or l.kind in ("address", "poi"):
        return False
    if (o.kind == "town") != (l.kind == "town"):
        return False                                                   # towns never merge with stops
    sim = rec_sim(o, l)
    d = dist_m(o.lat, o.lon, l.lat, l.lon)
    if o.kind == "town":
        return sim == 1.0 and d <= 5000                                # D4 towns
    if sim == 1.0 and (d <= 300 or (d <= 600 and (o.isMeta or l.isMeta or (o.products & RAIL and l.products & RAIL)))):
        return True                                                    # D2 same name
    if sim >= 0.75 and d <= 150:
        return True                                                    # D3 similar name, very close
    return d <= 80 and last_token_match(o, l)                          # D3' same stop-specific last token


def last_essential(name):
    toks, _ = tokenize(name)
    ess = [t.c for t in toks if t.essential]
    return ess[-1] if ess else None


def last_token_match(o, l):
    """'Lech am Arlberg Dorfhus' (VAO) ≈ 'Lech Dorfhus' (HAFAS); 'Hall-Thaur Bahnhof' ≈ 'Hall in Tirol-Thaur Bahnhst'."""
    for x in [o.name] + o.aliases:
        for y in [l.name] + l.aliases:
            a, b = last_essential(x), last_essential(y)
            if a and b and (a == b or (min(len(a), len(b)) >= 4 and (a.startswith(b) or b.startswith(a)))):
                return True
    return False


@dataclass
class Row:
    rec: Rec
    base: float | None = None        # offline score
    live_bonus: float = 0.0          # best live-rank bonus of a matching live item
    live_score: float | None = None  # best score of a matching live item scored on its own
    detail: dict = field(default_factory=dict)
    merged_names: list = field(default_factory=list)

    @property
    def score(self):
        a = (self.base + self.live_bonus) if self.base is not None else None
        return max(x for x in (a, self.live_score) if x is not None)


def dedupe_offline(offline):
    """Offline rows that are the same physical place (e.g. app rail + metro record 'Wien Westbahnhof') → one row.
    Rows hold COPIES of the index records: merging live data must never mutate the shared index."""
    import copy
    rows = []
    for s, r, det in offline:
        r = copy.copy(r)
        r.aliases = list(r.aliases)
        hit = next((row for row in rows if same_place(row.rec, r)), None)
        if hit:
            def rep_key(x):
                return (round(x.importance, 3), "(" not in x.name and "[" not in x.name, -len(x.name))
            if rep_key(r) > rep_key(hit.rec):
                r.products |= hit.rec.products
                hit.merged_names.append(hit.rec.name)
                hit.rec = r
            else:
                hit.rec.products |= r.products
                hit.merged_names.append(r.name)
            hit.base = max(hit.base, s)
        else:
            rows.append(Row(r, base=s, detail=det))
    return rows


def live_bonus(rank):
    return W["live_rank"] * (1 - (rank - 1) / 10)


def merge(offline, live, query_text, ctx: Ctx):
    q = parse_query(query_text)
    rows = dedupe_offline(offline)
    caps = {}
    for l in live:
        if ctx.mode == "tripLog" and l.kind == "town":
            continue
        fz = [{} for _ in q.toks]
        ts = text_score(q, l, fz, relaxed=True)
        if ts is None:
            # plausibility filter (OEBB_LIVE §A3.3): keep typo matches (prefix-edit distance ≤ 2) only
            if not plausible_fuzzy(q, l):
                continue
            ts = (0.30, {"quality": 0.3, "first": 0, "order": 0, "cov": 0, "exact": 0, "skip": 0})
        s = final_score(q, l, ts[0], ctx) + town_adjust(q, l, ts[1])
        if l.kind in ("address", "poi"):
            # Scotty's own A/P order is kept (popularity we cannot see): scores are made non-increasing
            if l.kind in caps:
                s = min(s, caps[l.kind] - 0.5)
            caps[l.kind] = s
            rows.append(Row(l, live_score=s, detail=ts[1]))
            continue
        hit = next((row for row in rows if same_place(row.rec, l)), None)
        if hit:
            o = hit.rec
            if o.source == "offline":
                o.source = "both"
            o.extId = o.extId or l.extId
            o.lid = o.lid or l.lid
            o.liveRank = min(o.liveRank or 99, l.liveRank)
            o.products |= l.products
            if l.wt is not None and hit.base is not None:
                o.importance = max(o.importance, importance_from_wt(l.wt))
            hit.live_bonus = max(hit.live_bonus, live_bonus(l.liveRank))
            hit.live_score = max(hit.live_score or -1e9, s)
            hit.merged_names.append(l.name)
        else:
            rows.append(Row(l, live_score=s, detail=ts[1]))
    rows.sort(key=lambda x: (-x.score, -x.rec.importance, len(x.rec.name), x.rec.name, x.rec.id))
    # diversity caps (§5.6): at most 2 addresses (5 with a house number) and 3 POIs (5 when a POI ranks first)
    cap = {"address": 5 if q.has_number else 2, "poi": 5 if rows and rows[0].rec.kind == "poi" else 3, "town": 2}
    seen, top, overflow, town_names = {}, [], [], set()
    for row in rows:
        k = row.rec.kind
        if k == "town":
            key = " ".join(t.c for t in tokenize(row.rec.name, is_name=False)[0])
            if key in town_names:            # several hamlets called 'Seefeld': only the best one up top
                overflow.append(row)
                continue
            town_names.add(key)
        if k in cap:
            seen[k] = seen.get(k, 0) + 1
            if seen[k] > cap[k]:
                overflow.append(row)
                continue
        top.append(row)
    rows = top + overflow
    return [(row.score, row.rec, row.detail) for row in rows[: ctx.limit]]


def plausible_fuzzy(q, l):
    names = [t.raw for toks, _, _ in l.variants for t in toks]
    for qt in q.toks:
        if len(qt.raw) >= 3 and qt.raw.isalpha():
            for n in names:
                if n.startswith(qt.raw) or prefix_edit_distance(qt.raw, n, 2) is not None:
                    return True
    return False


# ------------------------------------------------------------------------------------------------
# 6. Dataset (places.bin / localities.bin, scripts/build_places.py read_bin)
# ------------------------------------------------------------------------------------------------
def mode_class(m):
    if m & (1 | 4 | 8):
        return 1.0
    if m & 4096:
        return 0.9
    if m & (16 | 32):
        return 0.6
    if m & 256:
        return 0.55
    if m & 512:
        return 0.45
    if m & (128 | 2048):
        return 0.3
    if m & (64 | 2):
        return 0.25
    return 0.0


def importance_from_departures(dep, modes):
    """[FIT to HAFAS wt, 40 stops, MAE 0.024] I = 0.30 + 0.35·D + 0.35·M, D = min(1, ln(1+dep)/ln(3001))."""
    D = min(1.0, math.log1p(max(0, dep)) / math.log1p(3000))
    return min(1.0, 0.30 + 0.35 * D + 0.35 * mode_class(modes))


STATE_NUM = {0: "X", 1: "B", 2: "K", 3: "NÖ", 4: "OÖ", 5: "S", 6: "ST", 7: "T", 8: "V", 9: "W"}


PLACE_CLASSES = [None, "city", "town", "village", "suburb", "hamlet", "neighbourhood", "quarter", "isolated_dwelling"]


def read_bins(places_bin, localities_bin):
    import importlib.util
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("build_places", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                                               "build_places.py"))
    bp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bp)
    P, _ = bp.read_bin(places_bin)
    L = bp.read_bin(localities_bin)[0] if localities_bin else []
    return [r for r in P if r["kind"] == 0], [l for l in P + L if l["kind"] == 1]


def load_bins(places_bin, localities_bin):
    """Offline index exactly as the Swift PlaceDataset/PlaceIndex build it."""
    P, L = read_bins(places_bin, localities_bin)
    MUNICIPALITIES.clear()
    MUNICIPALITIES.update(fold(r["gem"]) for r in P if r.get("gem"))
    MUNICIPALITIES.update(fold(l["name"]) for l in L if PLACE_CLASSES[l["place_class"]] in ("city", "town", "village", "suburb"))
    from collections import Counter
    first = Counter()
    for r in P:
        t = tokenize(r["name"], is_name=False)[0]
        if t:
            first[t[0].raw] += 1
    MUNICIPALITIES.update(t for t, c in first.items() if c >= 3)
    recs, by_id = [], {}
    for r in P:
        modes = r["modes"]
        ex = r["extras"]
        eva = (ex.get(1) or [None])[0]
        hafas = (ex.get(2) or [None])[0]
        rail = bool(modes & RAIL) or bool(eva)
        ext = hafas or eva
        rec = Rec(id=r["id"], name=r["name"], lat=r["lat"], lon=r["lon"], kind="station" if rail else "stop",
                  products=modes, importance=importance_from_departures(r["weight"], modes),
                  country="at" if r["state"] != "X" else "", state=r["state"],
                  municipality=r.get("gem") or "", aliases=list(r["aliases"]), extId=str(ext) if ext else None)
        rec.legacy = list(ex.get(3) or [])
        recs.append(rec)
        by_id.setdefault(rec.id, rec)
    DELTA = {"city": 0.01, "town": 0.01, "village": -0.02, "suburb": -0.02}
    for l in L:
        main = by_id.get((l["extras"].get(7) or [None])[0])
        place = PLACE_CLASSES[l["place_class"]]
        imp = (main.importance if main else 0.5) + DELTA.get(place, -0.10)
        recs.append(Rec(id=l["id"], name=l["name"], lat=l["lat"], lon=l["lon"], kind="town", place=place,
                        products=main.products if main else 0, importance=max(0.0, min(1.0, imp)),
                        state=l["state"], country="at", municipality=l.get("gem") or "", aliases=[]))
    return OfflineIndex(recs)


# ------------------------------------------------------------------------------------------------
# 6b. Empty query, address/POI → stop resolution
# ------------------------------------------------------------------------------------------------
TOP_STATION_IDS = ["at:49:1349", "at:49:1468", "at:45:50002", "at:47:1187", "at:46:3040", "at:44:41164", "at:43:4848",
                   "at:42:3642", "at:42:3654", "at:48:452"]


def walk_seconds(d_m):
    """[LIVE fit, 37 LocGeoPos points, max error 0.5 s] HAFAS walking time = 120 s + 1.2 s per metre."""
    return 120 + 1.2 * d_m


def resolve_to_stop(idx, lat, lon, live_geopos=None, max_m=1500):
    """Best stops for valuing an address/POI/location (Swift PlaceIndex.resolveStops): offline stops ≤ max_m ranked by
    walk_seconds(d) − 300·importance, plus LocGeoPos rows not already present offline (dedupe D1–D3′)."""
    cands = []
    offline = idx.nearest(lat, lon, k=8, max_m=max_m)
    for rec, d in offline:
        cands.append((walk_seconds(d) - 300 * rec.importance, d, rec.name, "offline"))
    for l in live_geopos or []:
        if l["dist"] > max_m or l.get("type", "S") != "S":
            continue
        lr = live_items({"svcResL": [{"err": "OK", "res": {"match": {"locL": [l]}}}]}, "")[0]
        if any(same_place(o, lr) for o, _ in offline):
            continue
        imp = importance_from_wt(l["wt"]) if "wt" in l else 0.5
        cands.append((walk_seconds(l["dist"]) - 300 * imp, l["dist"], l["name"], "live"))
    cands.sort(key=lambda c: (c[0], c[1]))
    return cands[:3]


EXTRA_QUERIES = ["mariahilferstrasse", "mariahilferstr", "mariahilferst", "innsbruckhbf", "bahnhofstrasse", "westbahnhofstr",
                 "west bahnhof", "hall thaur", "hallthaur", "6020", "innsbruck hbf", "ibk hbf", "wien mitte", "praterstern",
                 "wien praterstern", "u6 floridsdorf", "landeck zams", "zams", "ehrwald", "lienz", "obergurgl", "sölden", "ischgl",
                 "mayrhofen", "zillertal", "bad ischl", "hallstatt", "st wolfgang", "graz jakomini", "jakominiplatz",
                 "linz taubenmarkt", "klagenfurt", "villach", "kufstein", "wels", "steyr", "krems", "tulln", "baden", "mödling",
                 "eisenstadt", "bregenz", "dornbirn", "feldkirch", "bludenz"]

CONTEXT_CASES = [
    # (label, input, ctx kwargs)
    ("bahnhof near Innsbruck", "bahnhof", dict(near=(47.2654, 11.3928))),
    ("bahnhof no location", "bahnhof", dict()),
    ("hbf near Graz", "hbf", dict(near=(47.0707, 15.4395))),
    ("wien with favourite Meidling", "wien", dict(favourites={"at:49:1015": True})),
    ("inns with recent Westbahnhof", "inns", dict(recents={"at:47:1189": (2, 3)})),
    ("vie (IATA alias)", "vie", dict()),
    ("wr neustadt", "wr neustadt", dict()),
    ("bruck mur", "bruck mur", dict()),
]


# ------------------------------------------------------------------------------------------------
# 7. Test cases
# ------------------------------------------------------------------------------------------------
CASES = [
    # (input, fixture scenario, mode)
    ("inns", "lm_all_inns", "planner"),
    ("innsbruck h", "lm_all_innsbruck_h", "planner"),
    ("wien w", "lm_all_wien_w", "planner"),
    ("st anton", "lm_all_st_anton", "planner"),
    ("hall in", "lm_all_hall_in", "planner"),
    ("Hall i.T.", "lm_all_hall_i_t", "planner"),
    ("ibk", "lm_all_ibk", "planner"),
    ("flughafen", "lm_all_flughafen", "planner"),
    ("Stephansplatz", "lm_all_stephansplatz", "planner"),
    ("Maria-Theresien-Straße 1 Innsbruck", "lm_all_maria_theresien_strasse_1_innsbruck", "planner"),
    ("Hofburg", "lm_all_hofburg", "planner"),
    ("Lech Postamt", "lm_all_lech_postamt", "planner"),
    ("wien", "lm_all_wien", "planner"),
    ("Wien Hbf", "lm_all_wien_hbf", "planner"),
    ("Salzburg", "lm_all_salzburg", "planner"),
    ("graz hbf", "lm_all_graz_hbf", "planner"),
    ("linz", "lm_all_linz", "planner"),
    ("Karlsplatz", "lm_all_karlsplatz", "planner"),
    ("Zell am See", "lm_all_zell_am_see", "planner"),
    ("St. Johann", "lm_all_st_johann", "planner"),
    ("Mariahilfer Straße", "lm_all_mariahilfer_strasse", "planner"),
    ("Schönbrunn", "lm_all_schonbrunn", "planner"),
    ("Nordkette", "lm_all_nordkette", "planner"),
    ("Gmunden", "lm_all_gmunden", "planner"),
    ("Bregenz Bf", "lm_all_bregenz_bf", "planner"),
    ("Seefeld", "lm_all_seefeld", "planner"),
    ("Westbahnhof", "lm_all_westbahnhof", "planner"),
    ("schwaz", "lm_all_schwaz", "planner"),
    ("St. Pölten", "lm_all_st_poelten_dot_umlaut", "planner"),
    ("st polten", "lm_all_st_polten_plain", "planner"),
    ("St Poelten Hbf", "lm_all_st_poelten_hbf_oe", "planner"),
    ("Sankt Pölten Hauptbahnhof", "lm_all_sankt_poelten_hauptbahnhof", "planner"),
    ("kitzbuehel", "lm_all_kitzbuehel_ue", "planner"),
    ("Kitzbuhel", "lm_all_kitzbuhel_plain", "planner"),
    ("insbruck", "lm_all_insbruck", "planner"),
    ("innsbruk", "lm_all_innsbruk", "planner"),
    ("Woergl", "lm_all_woergl_oe", "planner"),
    ("inns", "lm_all_inns", "tripLog"),
    ("innsbruck", None, "tripLog"),
    ("wien", "lm_all_wien", "tripLog"),
]



TYPING_QUERIES = ["Wien Hbf", "Ibk", "St. Anton", "St.Anton a.A.", "Hall i.T.", "Wr. Neustadt", "Lauterach in Vlbg Hasenfeldgasse",
                  "Steinbrunn im Bgld Bethausweg", "Nußdorf b.Lienz Volksschule", "Kleinmariazell NÖ Abzw Ort",
                  "Schwechat Flughafen", "Zwettl/Rodl", "Mayrhofen Bahnhof", "Obertauern", "Hintertux Gletscher",
                  "Wolfgangsee", "Achensee Schiff", "Feuerkogel", "Bad Gastein", "Gmünd NÖ"]
FOLD_INPUTS = ["Innsbruck Hbf", "Innsbruck Hauptbahnhof", "St.Pölten Hbf", "St. Pölten", "Sankt Pölten Hauptbahnhof",
               "St Poelten", "Wörgl", "Woergl", "Kitzbühel", "Kitzbuehel", "Hall i.T.", "Hall in Tirol", "Bruck a.d.Mur",
               "Bruck/Mur", "Linz/Donau Hbf", "Wr.Neustadt Hbf", "Wiener Neustadt", "Hof b.Salzburg", "St. Johann i.Pg.",
               "Maria-Theresien-Straße 1", "Mariahilferstraße", "Floridsdorf (Wien)", "Wien Hbf (U)",
               "Innsbruck [DDr.]-Alois-Lugger-Platz", "Ettendorf in Ktn Nord", "Waidhofen/Ybbs Schöffelstraße", "Weiß",
               "Straße", "Groß-Enzersdorf", "Überackern", "Œuvre", "Æble", "Łódź", "Kraków Główny", "Bratislava hl.st.",
               "Szombathely", "Český Krumlov", "Sopron", "Mürzzuschlag", "Göß", "Aéroport", "Hüttau", "Steuerberg",
               "Queen's", "Amstetten ---> Fa Avenarius", "Nr.9", "U3", "S-Bahn", "Höchst/Rhein Postamt",
               "Altmünster/Traunsee", "Treffpunkt Museum", "Flughafen Wien (VIE)", "hall in ", "st. ", "ibk",
               "Lauterach in Vlbg", "Kleinmariazell NÖ Abzw Ort", "ÄÖÜ äöü ß ẞ", "İstanbul", "Lienz (Tirol) Bahnhof"]
LIVE_FIXTURES_EXTRA = ["lm_param_field_Z_innsbruck", "lm_schema_unknown_input_key", "gp_nearby_maria_theresien_strasse_1_innsbruck",
                       "gp_nearby_hofburg_wien", "gp_nearby_lech_dorf", "lm_all_xqzvvhjkq"]
NEAREST_POINTS = [("Maria-Theresien-Straße 1, Innsbruck", 47.266873, 11.393890),
                  ("Hofburg, Wien", 48.206281, 16.365905),
                  ("Lech Dorf", 47.210699, 10.142574),
                  ("Wien Stephansplatz", 48.208350, 16.372510),
                  ("Bergdorf (Obergurgl)", 46.869000, 11.027000)]


def fmt(r: Rec):
    tag = {"stop": "S", "station": "S", "town": "Ort", "address": "A", "poi": "P"}[r.kind]
    return f"{tag}:{r.name}"


def trim_response(resp):
    """Only the fields the engine reads (decoder ignores everything else)."""
    keep = ("lid", "type", "name", "extId", "pCls", "wt", "meta", "icoX", "countryCodeL", "dist", "dur", "state")
    out = {"err": resp.get("err")} if resp.get("err") else {}
    svcs = []
    for s in resp.get("svcResL") or []:
        res = s.get("res") or {}
        def tl(lst):
            return [dict({k: l[k] for k in keep if k in l}, crd={"x": l["crd"]["x"], "y": l["crd"]["y"]})
                    for l in lst if "crd" in l]
        r2 = {}
        ico = (res.get("common") or {}).get("icoL")
        if ico is not None:
            r2["common"] = {"icoL": [{k: i[k] for k in ("res", "txtA") if k in i} for i in ico]}
        if "match" in res:
            r2["match"] = {"locL": tl(res["match"].get("locL") or [])}
        if "locL" in res:
            r2["locL"] = tl(res["locL"])
        svcs.append({"meth": s.get("meth"), "err": s.get("err"), "res": r2})
    out["svcResL"] = svcs
    return out


def golden(places_bin, localities_bin, fx_dir, out_dir, oebb_fx=None):
    import hashlib
    t0 = time.perf_counter()
    idx = load_bins(places_bin, localities_bin)
    print(f"index (python): {time.perf_counter() - t0:.1f} s, {len(idx.recs)} records, {len(idx.forms)} forms")
    live_dir = os.path.join(out_dir, "live")
    os.makedirs(live_dir, exist_ok=True)

    def load_fx(name):
        p = os.path.join(fx_dir, name + ".response.json")
        if name == "lm_all_xqzvvhjkq" and oebb_fx:      # split from the OEBB_LIVE batch (common lists are per svcRes)
            b = json.load(open(os.path.join(oebb_fx, "locmatch_batch_mixed.response.json")))
            resp = {"svcResL": [b["svcResL"][10]]}
        else:
            resp = json.load(open(p))
        t = trim_response(resp)
        with open(os.path.join(live_dir, name + ".json"), "w", encoding="utf-8") as fh:
            json.dump(t, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        return t

    cases = []
    for text, scen, mode in CASES:
        off = search_offline(idx, text, Ctx(mode=mode), limit=12)
        live = live_items(load_fx(scen), text) if scen else []
        merged = merge([list(x) for x in off], live, text, Ctx(mode=mode))
        cases.append(dict(input=text, mode=mode, fixture=scen, offline_top5=[fmt(r) for _, r, _ in off[:5]],
                          merged_top5=[fmt(r) for _, r, _ in merged[:5]],
                          live_rows=len(live), live_top5=[fmt(r) for r in live[:5]]))
    for label, text, kw in CONTEXT_CASES:
        ctx = Ctx(**kw)
        off = search_offline(idx, text, ctx, limit=12)
        rows = merge([list(x) for x in off], [], text, ctx)
        c = dict(input=text, mode="planner", context=label, merged_top5=[fmt(r) for _, r, _ in rows[:5]])
        if kw.get("near"):
            c["near"] = list(kw["near"])
        if kw.get("favourites"):
            c["favourites"] = sorted(kw["favourites"])
        if kw.get("recents"):
            c["recents"] = {k: {"ageDays": v[0], "uses": v[1]} for k, v in kw["recents"].items()}
        cases.append(c)
    for text in EXTRA_QUERIES + TYPING_QUERIES:
        off = search_offline(idx, text, Ctx(), limit=12)
        cases.append(dict(input=text, mode="planner", context="extra", offline_top5=[fmt(r) for _, r, _ in off[:5]]))
    for name in LIVE_FIXTURES_EXTRA:
        load_fx(name)
    # typing: every prefix (public search(limit: 20) = raw 28 + merge without live), both modes
    prefixes = []
    seen = set()
    for text, _, mode in CASES:
        for k in range(1, len(text) + 1):
            key = (text[:k], mode)
            if key in seen:
                continue
            seen.add(key)
            off = search_offline(idx, text[:k], Ctx(mode=mode), limit=28)
            rows = merge([list(x) for x in off], [], text[:k], Ctx(mode=mode, limit=20))
            prefixes.append(dict(input=text[:k], mode=mode, top5=[fmt(r) for _, r, _ in rows[:5]]))
    nearest = []
    for label, lat, lon in NEAREST_POINTS:
        nb = idx.nearest(lat, lon, k=5, max_m=1500)
        nearest.append(dict(label=label, lat=lat, lon=lon, names=[r.name for r, _ in nb], meters=[round(d, 1) for _, d in nb]))
    resolve = []
    for label, scen, lat, lon in [("address Maria-Theresien-Straße 1", "gp_nearby_maria_theresien_strasse_1_innsbruck", 47.266873, 11.393890),
                                  ("POI Hofburg Wien", "gp_nearby_hofburg_wien", 48.206281, 16.365905),
                                  ("Lech Dorf", "gp_nearby_lech_dorf", 47.210699, 10.142574)]:
        gp = load_fx(scen)["svcResL"][0]["res"]["locL"]
        resolve.append(dict(label=label, fixture=scen, lat=lat, lon=lon,
                            offline=[c[2] for c in resolve_to_stop(idx, lat, lon)],
                            with_live=[c[2] for c in resolve_to_stop(idx, lat, lon, gp)]))
    fold_cases = []
    for s in FOLD_INPUTS:
        toks, trailing = tokenize(s)
        fold_cases.append(dict(input=s, fold=fold(s), trailing=trailing, key=" ".join(t.c for t in tokenize(s, False)[0]),
                               tokens=[dict(raw=t.raw, qualifier=t.qualifier, stop=t.stop, generic=t.generic, numeric=t.numeric,
                                            essential=t.essential, forms=sorted([f, v] for f, v in t.forms.items()))
                                       for t in toks]))
    sha = {os.path.basename(p): hashlib.sha256(open(p, "rb").read()).hexdigest()[:16] for p in (places_bin, localities_bin)}
    gold = {"schema": "klimabilanz.places.golden/2",
            "engine": "scripts/places_reference.py == Packages/KlimaCore/Sources/KlimaCore/Places (weights v1)",
            "dataset_sha256_16": sha, "records": len(idx.recs),
            "how_to_read": "offline_top5 = search_offline(limit 12); merged_top5 = merge(offline, live fixture) top 5; "
                           "prefixes = public search(limit 20). 'S:' stop/station, 'Ort:' locality, 'A:' address, 'P:' POI.",
            "cases": cases, "prefixes": prefixes, "nearest": nearest, "resolve": resolve}
    with open(os.path.join(out_dir, "golden_places.json"), "w", encoding="utf-8") as fh:
        json.dump(gold, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(out_dir, "fold_golden.json"), "w", encoding="utf-8") as fh:
        json.dump(fold_cases, fh, ensure_ascii=False, indent=1)
    print(f"golden: {len(cases)} cases, {len(prefixes)} prefixes, {len(nearest)} nearest, {len(resolve)} resolve, "
          f"{len(fold_cases)} fold cases → {out_dir}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "golden":
        fx = os.environ.get("SCOTTY_FIXTURES")
        if not fx:
            sys.exit("set SCOTTY_FIXTURES to the LocMatch fixture directory (scenario.response.json files)")
        golden(sys.argv[2], sys.argv[3], fx, sys.argv[4], os.environ.get("OEBB_FIXTURES"))
    elif cmd == "query":
        idx = load_bins(sys.argv[2], sys.argv[3])
        mode = sys.argv[sys.argv.index("--ctx") + 1] if "--ctx" in sys.argv else "planner"
        near = tuple(map(float, sys.argv[sys.argv.index("--near") + 1].split(","))) if "--near" in sys.argv else None
        for s, r, det in search_offline(idx, sys.argv[4], Ctx(mode=mode, near=near), limit=10):
            print(f"{s:7.1f} {fmt(r):55s} imp={r.importance:.3f} {det}")
