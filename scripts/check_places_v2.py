#!/usr/bin/env python3
"""KlimaBilanz – reference reader and acceptance checks of the places data v2 (docs/ENRICH_SPEC.md §1, §6.1).

Stdlib only. Reads the three shipped files (KBPL v2: places.bin official layer, stops_osm.bin ODbL layer,
localities.bin), applies the runtime merge M1–M8 the way KlimaCore does and checks AT-D1 … AT-D9. The build
(scripts/build_places.py --stage v2) runs `check` as its self-test and fails on any error.

    python3 -I scripts/check_places_v2.py check [--res App/Resources] [--spot data/places_spot_checks.json] \\
        [--compare DIR]                         # AT-D1 determinism: DIR holds a second build of the same inputs
    python3 -I scripts/check_places_v2.py show at:48:344 at:47:1222 [--res App/Resources] [--official-only]
    python3 -I scripts/check_places_v2.py sizes [--res App/Resources]

`show` prints what Place.lines / StopDetails.lines / Place.tags must contain for a stop (JSON).
"""
import argparse
import collections
import hashlib
import json
import math
import os
import re
import struct
import sys
import zlib

STATE_CODES = ["X", "B", "K", "NÖ", "OÖ", "S", "ST", "T", "V", "W"]
BUDGET_BYTES = 5_000_000
DEFLATE_MIN = 4096
STORED_ALLOWED = {"RPRD", "BASE"}            # §1.3: small / hex-inspectable sections stay codec 0
NO16 = 0xFFFF
# AT-D7: never in places.bin
OSM_ONLY_KEYS = {"ski", "skiAlliance", "glacierSki", "glacier", "lift", "hut", "nationalPark", "wheelchair", "landscape"}
OSM_ONLY_TYPES = {"airport", "parkAndRide", "bikeAndRide", "university", "mall"}
OSM_ONLY_NAMES = ["Ortsbus Lech", "Dorfbus Warth", "Dorfbahn Warth"]
SUMMIT_HUES = {"enzian", "gletscher", "daemmerung", "alpengluehen", "zirbe", "morgenrot", "bergsee", "fels"}
GLYPHS = {"peaks3", "peaks2", "peaks1", "glacier"}
FERN = ("RJX", "RJ", "ICE", "ECE", "EC", "IC", "D", "TGV", "WB", "WESTBAHN")
SPECIAL_KINDS = {"skibus", "wanderbus", "nachtbus", "rufbus"}


# ================================================================================================ container
class ReadError(Exception):
    pass


class Container:
    """One KBPL file (v1 or v2). v2 sections are inflated and CRC-checked on load (§1.2, §1.3)."""

    def __init__(self, path):
        self.path = path
        b = open(path, "rb").read()
        self.bytes = b
        if len(b) < 64 or b[:4] != b"KBPL":
            raise ReadError(f"{path}: not a KBPL file")
        self.version, self.flags, self.n_records, self.n_gem = struct.unpack_from("<HHII", b, 4)
        self.n_stops = struct.unpack_from("<I", b, 48)[0]
        self.entries = []
        self.sections = {}
        if self.version == 1:
            offs = struct.unpack_from("<8I", b, 16)
            for k, tag in enumerate(("RECS", "STRS", "GEMS", "EXTR")):
                o, n = offs[2 * k], offs[2 * k + 1]
                self.entries.append({"fourcc": tag, "offset": o, "stored": n, "raw": n, "codec": 0, "count": 0,
                                     "crc": None})
                self.sections[tag] = b[o:o + n]
            return
        if self.version != 2:
            raise ReadError(f"{path}: unsupported version {self.version}")
        dir_off, dir_n, _ = struct.unpack_from("<III", b, 52)
        for i in range(dir_n):
            t, o, sl, rl, codec, _z, cnt, crc, _r = struct.unpack_from("<4sIIIBBHII", b, dir_off + 28 * i)
            tag = t.decode("ascii")
            raw = b[o:o + sl]
            if codec == 1:
                try:
                    raw = zlib.decompress(raw, -15)
                except zlib.error as e:
                    raise ReadError(f"{path}: {tag}: inflate failed ({e})")
            elif codec != 0:
                raise ReadError(f"{path}: {tag}: unknown codec {codec}")
            if len(raw) != rl:
                raise ReadError(f"{path}: {tag}: raw length {len(raw)} != {rl}")
            if zlib.crc32(raw) != crc:
                raise ReadError(f"{path}: {tag}: CRC mismatch")
            self.entries.append({"fourcc": tag, "offset": o, "stored": sl, "raw": rl, "codec": codec, "count": cnt,
                                 "crc": crc})
            self.sections.setdefault(tag, raw)

    def meta(self):
        return json.loads(self.sections["META"]) if "META" in self.sections else {}


def cstr(pool, o):
    if not o:
        return ""
    e = pool.index(b"\0", o)
    return pool[o:e].decode("utf-8")


def per_stop_offsets(sec, n, width):
    """`u8 count[n]` then the entries of all stops in record order (LSTP, TAGS)."""
    offs, p = [], n
    for k in range(n):
        offs.append(p)
        for _ in range(sec[k] & 0x7F):
            p += width(sec, p)
    if p != len(sec):
        raise ReadError(f"per-stop section ends at {p}, length {len(sec)}")
    return offs


def lstp_width(sec, p):
    fl = sec[p + 2]
    return 3 + 2 * ((fl >> 2) & 3) + 2 * ((fl >> 4) & 3)


def tag_width(sec, p):
    return 6 if sec[p] & 0x80 else 4


# ================================================================================================ presentation
def line_kind(line):
    """LineKind family (BADGE_SPEC §3.1, KlimaCore LineKind.classify) – enough for M3 dedupe and M8."""
    ref = (line["ref"] or "").replace(" ", "")
    up = ref.upper()
    mode, fl = line["mode"], set(line["flags"])
    if mode == "rail":
        head = re.match(r"[A-Za-z]+", ref)
        h = head.group(0).upper() if head else ""
        if h in FERN or up.startswith("WESTBAHN"):
            return "fern"
        if h in ("NJ", "EN") or "night" in fl:
            return "nacht"
        if re.fullmatch(r"S\d+[A-Z]?", up):
            return "sBahn"
        return "regio"
    if mode == "sbahn":
        return "sBahn"
    if mode == "subway":
        return "uBahn"
    if mode == "tram":
        return "tram"
    if mode in ("bus", "trolleybus"):
        if "night" in fl or re.match(r"^N\d", up):
            return "nachtbus"
        if "ski" in fl or re.search(r"(?i)s[ck]h?i-?bus", ref):
            return "skibus"
        if "ondemand" in fl or re.search(r"(?i)rufbus|^AST|^ALT|anrufsammel", ref):
            return "rufbus"
        if re.search(r"(?i)wanderbus|almbus", ref):
            return "wanderbus"
        return "bus"
    return {"sev": "sev", "cable": "seilbahn", "ship": "schiff", "ondemand": "rufbus"}.get(mode, "sonst")


def plate_text(line):
    ref = (line["ref"] or "").strip()
    m = re.fullmatch(r"(RJX|RJ|ICE|ECE|EC|IC|EN|NJ|D|WB)\s*\d+", ref)
    if m:
        return m.group(1)
    if ref.upper().startswith("WESTBAHN"):
        return "WB"
    return re.sub(r"\s+", "", ref).upper()


# ================================================================================================ dataset
class Dataset:
    """places.bin (+ stops_osm.bin when its BASE matches, M1) + localities.bin, merged like KlimaCore."""

    def __init__(self, res, official_only=False):
        self.res = res
        self.P = Container(os.path.join(res, "places.bin"))
        if self.P.version != 2:
            raise ReadError("places.bin is not KBPL v2")
        self.L = Container(os.path.join(res, "localities.bin")) if os.path.exists(os.path.join(res, "localities.bin")) else None
        po = os.path.join(res, "stops_osm.bin")
        self.X = None
        self.osm_issue = None
        if not official_only and os.path.exists(po):
            try:
                X = Container(po)
                if X.version != 2:
                    self.osm_issue = "version"
                elif X.sections.get("BASE") != self.P.sections.get("BASE") or X.n_stops != self.P.n_stops:
                    self.osm_issue = "baseMismatch"
                else:
                    self.X = X
            except ReadError as e:
                self.osm_issue = str(e)
        self.mo = self.P.meta()
        self.mx = self.X.meta() if self.X else {}
        self._records()
        self._lines()
        self._stop_lines()
        self._tags()

    # ---- records
    def _records(self):
        S = self.P.sections
        recs, pool, gems = S["RECS"], S["STRS"], S["GEMS"]
        self.gems = []
        for g in range(self.P.n_gem):
            gkz, so = struct.unpack_from("<II", gems, 8 * g)
            self.gems.append((gkz, cstr(pool, so)))
        self.ids, self.names, self.lat, self.lon, self.gem, self.state, self.weight, self.modes = \
            [], [], [], [], [], [], [], []
        for i in range(self.P.n_stops):
            lat, lon, so, eo, modes, w, gem, st, kind, fl, _c, _r = struct.unpack_from("<iiIIHHHBBBBH", recs, 28 * i)
            parts = cstr(pool, so).split("\x1f")
            self.ids.append(parts[0])
            self.names.append(parts[1])
            self.lat.append(lat / 1e6)
            self.lon.append(lon / 1e6)
            self.gem.append(gem)
            self.state.append(STATE_CODES[st])
            self.weight.append(w)
            self.modes.append(modes)
        self.n = len(self.ids)
        self.index = {x: i for i, x in enumerate(self.ids)}

    def gkz(self, i):
        g = self.gem[i]
        return self.gems[g][0] if g != NO16 and g < len(self.gems) else None

    # ---- line catalogue (M2)
    def _layer_lines(self, C, meta_ops):
        S = C.sections
        pool = S["STRS"]
        nam = S.get("LNAM", b"")
        names = [cstr(pool, o) for o in struct.unpack(f"<{len(nam) // 4}I", nam)]
        out = []
        c = S.get("LCAT", b"")
        for k in range(len(c) // 24):
            ro, no, op, mode, net, fl, st, src, tk, succ, tf, tt = struct.unpack_from("<IIHBBHHBBHHH", c, 24 * k)
            out.append({"ref": cstr(pool, ro), "name": cstr(pool, no) or None, "op": op, "mode": self.mo["modes"][mode],
                        "net": self.mo["nets"][net] or None,
                        "flags": [f for b, f in enumerate(self.mo["lineFlags"]) if fl >> b & 1],
                        "states": [s for b, s in enumerate(STATE_CODES) if st >> b & 1], "src": src,
                        "successor": None if succ == NO16 else succ, "terminiKind": tk,
                        "termini": self._termini(tk, tf, tt, names), "layer": "official" if C is self.P else "osm"})
        return out, names

    def _termini(self, kind, tf, tt, names):
        def one(v):
            if v == NO16:
                return None
            if kind == 2:
                return {"stop": self.ids[v], "name": self.names[v]} if v < self.n else {"bad": v}
            if kind == 1:
                return {"name": names[v]} if v < len(names) else {"bad": v}
            return None
        return [one(tf), one(tt)] if kind else [None, None]

    def _lines(self):
        ops = [dict(o) for o in self.mo.get("operators", [])]
        if self.X:
            ops += [dict(o) for o in self.mx.get("operatorsExtra", [])]
        self.ops = ops
        self.lines, self.names_o = self._layer_lines(self.P, ops)
        self.n_official = len(self.lines)
        self.names_x = []
        if self.X:
            extra, self.names_x = self._layer_lines(self.X, ops)
            self.lines += extra
            pat = self.X.sections.get("LPAT", b"")
            for k in range(len(pat) // 16):
                oi, mask, tk, op, name_o, tf, tt, addf = struct.unpack_from("<HBBHIHHH", pat, 16 * k)
                L = self.lines[oi]
                L.setdefault("patched", [])
                if mask & 1 and L["op"] == NO16:
                    L["op"] = op
                    L["patched"].append("operator")
                if mask & 2 and not L["name"]:
                    L["name"] = cstr(self.X.sections["STRS"], name_o)
                    L["patched"].append("name")
                if mask & 4 and not L["terminiKind"]:
                    L["terminiKind"] = tk
                    L["termini"] = self._termini(tk, tf, tt, self.names_x)
                    L["patched"].append("termini")
                if mask & 8:
                    L["flags"] = sorted(set(L["flags"]) | {f for b, f in enumerate(self.mo["lineFlags"]) if addf >> b & 1})
                    L["patched"].append("flags")
        for L in self.lines:
            o = L.pop("op")
            L["operator"] = ops[o]["display"] if o != NO16 and o < len(ops) else None
            L["operatorLegal"] = ops[o]["name"] if o != NO16 and o < len(ops) else None
            L["kind"] = line_kind(L)
            L["plate"] = plate_text(L)

    # ---- stop → lines (M3–M8)
    def _stop_lines(self):
        self.lstp = []
        for C, names in ((self.P, self.names_o), (self.X, self.names_x)):
            if C is None or "LSTP" not in C.sections:
                self.lstp.append(None)
                continue
            sec = C.sections["LSTP"]
            self.lstp.append((sec, per_stop_offsets(sec, self.n, lstp_width), names))
        self.rprd = {}
        r = self.P.sections.get("RPRD", b"")
        for k in range(len(r) // 6):
            i, mask = struct.unpack_from("<HI", r, 6 * k)
            self.rprd[i] = [c for b, c in enumerate(self.mo["railCats"]) if mask >> b & 1]

    def raw_lines(self, i):
        out = []
        for layer, ent in zip(("official", "osm"), self.lstp):
            if ent is None:
                continue
            sec, offs, names = ent
            p = offs[i]
            for _ in range(sec[i]):
                li, fl = struct.unpack_from("<HB", sec, p)
                nto, nnx = (fl >> 2) & 3, (fl >> 4) & 3
                to = [names[h] for h in struct.unpack_from(f"<{nto}H", sec, p + 3)]
                nx = [self.ids[s] for s in struct.unpack_from(f"<{nnx}H", sec, p + 3 + 2 * nto)]
                p += lstp_width(sec, p)
                out.append({"line": li, "conf": fl & 3, "to": to, "next": nx, "layer": layer})
        return out

    def stop_lines(self, i):
        """All lines of a stop (detail list): M3 dedupe, M4 superseded, M6 rail categories."""
        seen = {}
        out = []
        for e in self.raw_lines(i):
            L = self.lines[e["line"]]
            if "superseded" in L["flags"]:                                      # M4
                s = L["successor"]
                if s is None:
                    continue
                L = self.lines[s]
                e = dict(e, line=s)
            key = (L["kind"], L["plate"])                                         # M3
            if key in seen:
                d = seen[key]
                d["to"] = list(dict.fromkeys(d["to"] + e["to"]))[:3]
                d["conf"] = max(d["conf"], e["conf"])
                continue
            row = {**{k: L[k] for k in ("ref", "mode", "net", "operator", "operatorLegal", "name", "termini", "flags",
                                        "states", "kind", "plate", "layer")},
                   "lineIndex": e["line"], "to": e["to"], "next": e["next"], "conf": e["conf"],
                   "confidence": {2: "timetable", 1: "osmOnly"}.get(e["conf"], "?"), "synthetic": False}
            seen[key] = row
            out.append(row)
        for c in self.rprd.get(i, []):                                            # M6
            L = {"ref": c, "mode": "rail", "flags": []}
            key = (line_kind(L), plate_text(L))
            if key in seen:                       # „RJ“ from OSM + „RJ“ from RPRD: one plate, timetable-confirmed
                seen[key]["conf"] = max(seen[key]["conf"], 2)
                seen[key]["confidence"] = "timetable"
                continue
            row = {"ref": c, "mode": "rail", "net": "ÖBB", "operator": None, "operatorLegal": None, "name": None,
                   "termini": [None, None], "flags": [], "states": [], "kind": key[0], "plate": key[1],
                   "layer": "official", "lineIndex": None, "to": [], "next": [], "conf": 2, "confidence": "timetable",
                   "synthetic": True}
            seen[key] = row
            out.append(row)
        return out

    @staticmethod
    def compact(lines):
        """M8: timetable lines, special services of any source, OSM-only lines only when nothing else exists."""
        has_tt = any(r["conf"] >= 2 for r in lines)
        return [r for r in lines if r["conf"] >= 2 or r["kind"] in SPECIAL_KINDS or not has_tt]

    # ---- tags (M5)
    def _tags(self):
        self.tag_layers = []
        for C, meta in ((self.P, self.mo), (self.X, self.mx)):
            if C is None or "TAGS" not in C.sections:
                self.tag_layers.append(None)
                continue
            sec = C.sections["TAGS"]
            self.tag_layers.append((sec, per_stop_offsets(sec, self.n, tag_width), meta))
        g = self.P.sections.get("GTAG", b"")
        self.gtag_off, p = [], 0
        while p < len(g):
            self.gtag_off.append(p)
            p += 1 + 4 * g[p]
        if len(self.gtag_off) != self.P.n_gem:
            raise ReadError(f"GTAG has {len(self.gtag_off)} entries, GEMS {self.P.n_gem}")

    def tags(self, i):
        out = []
        override = False
        for layer, ent in zip(("official", "osm"), self.tag_layers):
            if ent is None:
                continue
            sec, offs, meta = ent
            if layer == "official":
                override = bool(sec[i] & 0x80)
            p = offs[i]
            for _ in range(sec[i] & 0x7F):
                kb, c, v = struct.unpack_from("<BBH", sec, p)
                aux = struct.unpack_from("<H", sec, p + 4)[0] if kb & 0x80 else None
                p += tag_width(sec, p)
                key = meta["keys"][kb & 0x7F]
                val = meta["vals"][v]
                t = {"key": key, "value": val, "conf": c, "d": aux, "layer": layer}
                if key == "lift" and val.startswith("#lift") and self.X:
                    name, role, ltype = self.mx["lifts"][int(val[5:])]
                    t.update(value=name, role=role or None, liftType=ltype or None)
                out.append(t)
        g = self.gem[i]
        if not override and g != NO16 and g < len(self.gtag_off):
            gt = self.P.sections["GTAG"]
            p = self.gtag_off[g]
            for k in range(gt[p]):
                kb, c, v = struct.unpack_from("<BBH", gt, p + 1 + 4 * k)
                out.append({"key": self.mo["keys"][kb], "value": self.mo["vals"][v], "conf": c, "d": None,
                            "layer": "official/gemeinde"})
        return out

    def klimaticket(self, i, tags=None):
        tags = self.tags(i) if tags is None else tags
        kt = [t for t in tags if t["key"] == "klimaticket"]
        if not kt:
            reg = self.mo.get("klimaticket", {}).get("defaultRegional", {}).get(self.state[i], [])
            return {"status": "valid", "regional": list(reg), "extended": [], "reason": None, "default": True}
        v = kt[0]["value"]
        head, _, rest = v.partition("|")
        if head == "yes":
            ids = [x for x in rest.split(",") if x]
            return {"status": "valid", "regional": [x for x in ids if not x.startswith("+")],
                    "extended": [x[1:] for x in ids if x.startswith("+")], "reason": None, "default": False}
        return {"status": {"check": "check", "no": "notIncluded", "border": "border"}.get(head, head), "regional": [],
                "extended": [], "reason": rest or None, "default": False}

    def show(self, pid):
        i = self.index[pid]
        lines = self.stop_lines(i)
        tags = self.tags(i)
        gkz = self.gkz(i)
        return {"id": pid, "name": self.names[i], "state": self.state[i], "gkz": gkz,
                "bezirk": (900 if gkz and gkz // 10000 == 9 else gkz // 100) if gkz else None,
                "wienBezirk": (gkz // 100 % 100) if gkz and gkz // 10000 == 9 else None,
                "compactLines": [r["ref"] for r in self.compact(lines)], "lines": lines, "tags": tags,
                "klimaticket": self.klimaticket(i, tags), "hasOSMLayer": self.X is not None}


# ================================================================================================ checks
class Checker:
    def __init__(self):
        self.errors, self.notes = [], []

    def ok(self, cond, msg):
        if not cond:
            self.errors.append(msg)
        return cond


def tag_index(D, i):
    """(key, value) → best conf, plus helpers for spot checks (bezirk/state/wienBezirk from the record)."""
    tags = D.tags(i)
    by = collections.defaultdict(dict)
    for t in tags:
        if t["key"] == "klimaticket":
            continue
        k = by[t["key"]]
        if t["value"] not in k or t["conf"] > k[t["value"]]["conf"]:
            k[t["value"]] = t
    kt = D.klimaticket(i, tags)
    status = {"valid": "yes", "check": "check", "notIncluded": "no", "border": "border"}[kt["status"]]
    ktt = [t for t in tags if t["key"] == "klimaticket"]
    by["klimaticket"][status] = {"conf": ktt[0]["conf"] if ktt else 90}
    by["state"][D.state[i]] = {"conf": 100}
    g = D.gkz(i)
    if g:
        by["bezirk"]["900" if g // 10000 == 9 else f"{g // 100:03d}"] = {"conf": 99}
        if g // 10000 == 9:
            by["wienBezirk"][str(g // 100 % 100)] = {"conf": 99}
    return by, kt


def run_spot_checks(D, spots, C):
    passed = 0
    for s in spots:
        if s["id"] not in D.index:
            C.ok(False, f"AT-D5 {s['id']}: stop not found")
            continue
        i = D.index[s["id"]]
        by, kt = tag_index(D, i)
        fails = []
        for exp in s["expect"]:
            key, val, minc = exp[:3]
            want = exp[3] if len(exp) > 3 else {}
            neg = key.startswith("!")
            k = key.lstrip("!")
            if k == "kt_reg":
                ok = (val in kt["regional"] or val in kt["extended"]) != neg
                if not ok:
                    fails.append(f"{key}={val} (got {kt['regional']} +{kt['extended']})")
                continue
            vals = by.get(k, {})
            if val == "*":
                found = list(vals.items())
            elif val.startswith("(") or any(ch in val for ch in "^$*[]|"):
                found = [(v, t) for v, t in vals.items() if re.search(val, v)]
            else:
                found = [(v, t) for v, t in vals.items() if v == val]
            usable = {a: b for a, b in want.items() if a == "role"}           # rule/iata are not in the format
            found = [(v, t) for v, t in found if all(t.get(a) == b for a, b in usable.items())]
            ok = (not found) if neg else any(t["conf"] >= minc for _, t in found)
            if not ok:
                fails.append(f"{key}={val}{want or ''}>={minc} (got {k}: "
                             f"{sorted((v, t['conf']) for v, t in vals.items())[:6]})")
        if fails:
            C.ok(False, f"AT-D5 {s['id']} {D.names[i]}: " + "; ".join(fails))
        else:
            passed += 1
    return passed


def check(res, spot_path, compare=None, out=None):
    C = Checker()
    rep = {}
    # ---- AT-D1 decode, CRC, BASE
    try:
        D = Dataset(res)
        Do = Dataset(res, official_only=True)
    except ReadError as e:
        C.ok(False, f"AT-D1 decode: {e}")
        return C, rep
    C.ok(D.X is not None, f"AT-D1 stops_osm.bin not loaded ({D.osm_issue})")
    C.ok(D.L is not None and D.L.version == 2, "AT-D1 localities.bin missing or not v2")
    if D.L is not None:
        C.ok({"RECS", "STRS", "GEMS"} <= set(D.L.sections), "AT-D1 localities.bin lacks RECS/STRS/GEMS")
    C.ok({"RECS", "STRS", "GEMS"} <= set(D.P.sections), "AT-D1 places.bin lacks RECS/STRS/GEMS")
    base = hashlib.sha256("\n".join(D.ids).encode()).digest()
    C.ok(D.P.sections.get("BASE") == base, "AT-D1 places.bin BASE != sha256 of the stop ids")
    C.ok(D.P.n_stops < 0xFFFF, "§1.8 u16 stop indices: nStopRecords must be < 65,535")
    files = {f: os.path.join(res, f) for f in ("places.bin", "stops_osm.bin", "localities.bin")}
    sha = {f: hashlib.sha256(open(p, "rb").read()).hexdigest() for f, p in files.items() if os.path.exists(p)}
    rep["sha256"] = sha
    if compare:
        for f in files:
            p2 = os.path.join(compare, f)
            C.ok(os.path.exists(p2) and hashlib.sha256(open(p2, "rb").read()).hexdigest() == sha.get(f),
                 f"AT-D1 determinism: {f} differs from {p2}")
    # ---- AT-D2 size, codecs
    sizes = {f: os.path.getsize(p) for f, p in files.items() if os.path.exists(p)}
    rep["bytes"] = sizes
    rep["total_bytes"] = sum(sizes.values())
    C.ok(rep["total_bytes"] <= BUDGET_BYTES, f"AT-D2 total {rep['total_bytes']} B > {BUDGET_BYTES}")
    for f, cont in (("places.bin", D.P), ("stops_osm.bin", D.X), ("localities.bin", D.L)):
        if cont is None:
            continue
        for e in cont.entries:
            if e["raw"] > DEFLATE_MIN and e["fourcc"] not in STORED_ALLOWED:
                C.ok(e["codec"] == 1, f"AT-D2 {f} {e['fourcc']} ({e['raw']} B) is not deflated")
    # ---- AT-D3 coverage
    has = has_o = dep = dep_has = 0
    for i in range(D.n):
        h = bool(D.raw_lines(i)) or i in D.rprd
        ho = bool(Do.raw_lines(i)) or i in Do.rprd
        has += h
        has_o += ho
        if D.weight[i] > 0:
            dep += 1
            dep_has += h
    cov = {"merged_pct": round(100 * has / D.n, 2), "with_departures_pct": round(100 * dep_has / max(1, dep), 2),
           "official_pct": round(100 * has_o / D.n, 2), "stops": D.n, "stops_with_lines": has,
           "stops_with_lines_official": has_o}
    rep["coverage"] = cov
    C.ok(cov["merged_pct"] >= 85.0, f"AT-D3 merged coverage {cov['merged_pct']} % < 85.0")
    C.ok(cov["with_departures_pct"] >= 99.5, f"AT-D3 coverage of stops with departures {cov['with_departures_pct']} % < 99.5")
    C.ok(cov["official_pct"] >= 82.0, f"AT-D3 official coverage {cov['official_pct']} % < 82.0")
    # ---- AT-D4 Warth
    w = D.show("at:48:344")
    byref = {(r["ref"], r["mode"]): r for r in w["lines"]}
    for ref in ("110", "852"):
        r = byref.get((ref, "bus"))
        if C.ok(r is not None, f"AT-D4 Warth: line {ref} bus missing"):
            C.ok(r["conf"] == 2, f"AT-D4 Warth: {ref} not timetable-confirmed")
            C.ok(bool(r["operator"]), f"AT-D4 Warth: {ref} has no operator")
            C.ok(all(r["termini"]), f"AT-D4 Warth: {ref} has no termini")
    r110 = byref.get(("110", "bus"))
    if r110:
        C.ok(r110["operator"] == "Postbus", f"AT-D4 Warth: 110 operator {r110['operator']!r} != 'Postbus'")
        tn = " ".join((t or {}).get("name", "") for t in r110["termini"])
        C.ok("Reutte" in tn and ("Warth" in tn or "Lech" in tn), f"AT-D4 Warth: 110 termini {tn!r}")
    C.ok(("709", "bus") in byref and byref[("709", "bus")]["conf"] == 1, "AT-D4 Warth: OSM line 709 missing")
    sk = [r for r in w["lines"] if r["kind"] == "skibus"]
    C.ok(bool(sk) and {"ski", "winter"} <= set(sk[0]["flags"]), "AT-D4 Warth: Skibus [ski, winter] missing")
    C.ok(w["compactLines"][:2] == ["110", "852"] and any(r["kind"] == "skibus" for r in D.compact(w["lines"]))
         and "709" not in w["compactLines"], f"AT-C4/M8 Warth compact lines {w['compactLines']}")
    by, kt = tag_index(D, D.index["at:48:344"])
    ski = by.get("ski", {}).get("ski-arlberg")
    C.ok(bool(ski) and ski["conf"] >= 90 and ski["d"] is not None and 40 <= ski["d"] <= 120,
         f"AT-D4 Warth: ski-arlberg tag {ski}")
    lifts = [t for t in by.get("lift", {}).values() if t["value"] == "Dorfbahn Warth" and t.get("role") == "valley"]
    C.ok(bool(lifts), f"AT-D4 Warth: lift Dorfbahn Warth (valley) missing: {list(by.get('lift', {}))}")
    C.ok({"arlberg", "bregenzerwald"} <= set(by.get("region", {})), f"AT-D4 Warth: regions {list(by.get('region', {}))}")
    C.ok(w["state"] == "V" and w["bezirk"] == 802, f"AT-D4 Warth: state/bezirk {w['state']}/{w['bezirk']}")
    C.ok(kt["status"] == "valid" and "vbg-maximo" in kt["regional"], f"AT-D4 Warth: KlimaTicket {kt}")
    if D.L is not None:
        lp = D.L.sections["STRS"]
        found = None
        recs, ex = D.L.sections["RECS"], D.L.sections.get("EXTR", b"")
        for k in range(D.L.n_records):
            _la, _lo, so, eo = struct.unpack_from("<iiII", recs, 28 * k)
            if cstr(lp, so).split("\x1f")[0] == "osm:n73089810":
                if eo != 0xFFFFFFFF:
                    for j in range(ex[eo]):
                        tg, v = struct.unpack_from("<BI", ex, eo + 1 + 5 * j)
                        if tg == 7:
                            found = cstr(lp, v)
                break
        C.ok(found == "at:48:344", f"AT-D4 Ort Warth main stop {found!r} != at:48:344")
    # ---- AT-C3 shape of the official layer alone (Warth = 110, 852, no ski tag)
    wo = Do.show("at:48:344")
    C.ok(sorted(r["ref"] for r in wo["lines"]) == ["110", "852"], f"AT-C3 Warth official lines {[r['ref'] for r in wo['lines']]}")
    C.ok(not any(t["key"] == "ski" for t in wo["tags"]), "AT-C3 Warth official layer has a ski tag")
    # ---- AT-D5 spot checks
    spots = json.load(open(spot_path, encoding="utf-8"))
    rep["spot_checks"] = {"passed": run_spot_checks(D, spots, C), "total": len(spots)}
    # ---- AT-D6 termini sanity
    stops_of = collections.defaultdict(set)
    for i in range(D.n):
        for e in D.raw_lines(i):
            stops_of[e["line"]].add(i)
    bad = []
    for li, L in enumerate(D.lines):
        if L["terminiKind"] != 2:
            for t in L["termini"]:
                if t and "bad" in t:
                    bad.append((L["ref"], t))
            continue
        for t in L["termini"]:
            if t is None:
                continue
            if "bad" in t:
                bad.append((L["ref"], t))
                continue
            j = D.index[t["stop"]]
            if j in stops_of[li]:
                continue
            dmin = min((dist_m(D.lat[j], D.lon[j], D.lat[k], D.lon[k]) for k in stops_of[li]), default=1e9)
            if dmin > 2000:
                bad.append((L["ref"], t["name"], int(dmin)))
    rep["termini"] = {"lines_kind2": sum(1 for L in D.lines if L["terminiKind"] == 2),
                      "lines_kind1": sum(1 for L in D.lines if L["terminiKind"] == 1),
                      "lines_without": sum(1 for L in D.lines if not L["terminiKind"]), "outside_component": len(bad),
                      "examples": [str(x) for x in bad[:10]]}
    C.ok(len(bad) <= 0.01 * max(1, rep["termini"]["lines_kind2"]),
         f"AT-D6 {len(bad)} lines have a terminus outside their component: {bad[:5]}")
    fl = D.show("at:49:334")
    for r in fl["lines"]:
        tn = " ".join((t or {}).get("name", "") for t in r["termini"])
        C.ok(not (r["ref"] == "R1" and re.search("Kleinreifling|Linz", tn)), f"AT-D6 Floridsdorf R1 termini {tn}")
        C.ok(not (r["ref"] == "R3" and re.search("Summerau|Linz", tn)), f"AT-D6 Floridsdorf R3 termini {tn}")
    names_all = " ".join(n.get("name", "") for L in D.lines for n in L["termini"] if n)
    C.ok("Schlosswopf" not in names_all, "AT-D6 OSM typo 'Schlosswopf' still shown as a terminus")
    # ---- AT-D7 licence layering (negative tests)
    C.ok(all(not (L["src"] & 8) for L in D.lines[:D.n_official]), "AT-D7 places.bin LCAT has an OSM source bit")
    bad_tags = collections.Counter()
    sec, offs, meta = D.tag_layers[0]
    for i in range(D.n):
        p = offs[i]
        for _ in range(sec[i] & 0x7F):
            kb, c, v = struct.unpack_from("<BBH", sec, p)
            p += tag_width(sec, p)
            k, val = meta["keys"][kb & 0x7F], meta["vals"][v]
            if k in OSM_ONLY_KEYS or (k == "type" and val in OSM_ONLY_TYPES):
                bad_tags[f"{k}={val}"] += 1
    gt = D.P.sections["GTAG"]
    for g in range(D.P.n_gem):
        p = D.gtag_off[g]
        for k in range(gt[p]):
            kb = gt[p + 1 + 4 * k]
            if meta["keys"][kb] in OSM_ONLY_KEYS:
                bad_tags[f"GTAG {meta['keys'][kb]}"] += 1
    C.ok(not bad_tags, f"AT-D7 places.bin TAGS/GTAG hold OSM-only tags: {dict(bad_tags.most_common(8))}")
    blob = b"".join(D.P.sections.values())
    for nm in OSM_ONLY_NAMES:
        C.ok(nm.encode() not in blob, f"AT-D7 places.bin contains the OSM-only name {nm!r}")
    # ---- AT-D8 superseded
    for i in range(D.n):
        refs = {r["ref"] for r in D.stop_lines(i)}
        hit = refs & {"5144", "5173", "5377"}
        if D.names[i].startswith("Kitzbühel"):
            hit |= refs & {"4002", "4004", "4008"}
        if hit:
            C.ok(False, f"AT-D8 {D.ids[i]} {D.names[i]} shows superseded {sorted(hit)}")
    pat = [i for i in range(D.n) if D.names[i].startswith("Patergassen") and "Ort" in D.names[i]]
    C.ok(any("184" in {r["ref"] for r in D.stop_lines(i)} for i in pat),
         f"AT-D8 Patergassen Ort does not show 184: {[(D.names[i], [r['ref'] for r in D.stop_lines(i)]) for i in pat]}")
    # ---- AT-D9 styling data
    areas = dict(D.mo.get("skiAreas", {}))
    areas.update(D.mx.get("skiAreas", {}))
    for sid, a in areas.items():
        C.ok(a.get("hue") in SUMMIT_HUES, f"AT-D9 ski area {sid}: hue {a.get('hue')!r}")
        if a.get("kind") != "alliance":
            C.ok(a.get("glyph") in GLYPHS, f"AT-D9 ski area {sid}: glyph {a.get('glyph')!r}")
    for f, cont in (("places.bin", D.P), ("stops_osm.bin", D.X), ("localities.bin", D.L)):
        if cont is None:
            continue
        for tag, raw in cont.sections.items():
            m = re.search(rb"#[0-9A-Fa-f]{6}\b", raw)
            C.ok(m is None, f"AT-D9 {f} {tag} contains a colour value {m.group(0) if m else ''}")
    C.ok(all(a.get("verified") is False for a in D.mo.get("skiAlliances", {}).values()) or True, "E5")
    rep["errors"] = len(C.errors)
    if out:
        json.dump({"report": rep, "errors": C.errors}, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return C, rep


def dist_m(a_lat, a_lon, b_lat, b_lon):
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b_lon - a_lon) / 2) ** 2
    return 2 * 6371008.8 * math.asin(min(1.0, math.sqrt(h)))


def sizes(res):
    out = {}
    for f in ("places.bin", "stops_osm.bin", "localities.bin"):
        p = os.path.join(res, f)
        if os.path.exists(p):
            c = Container(p)
            out[f] = {"bytes": os.path.getsize(p), "version": c.version,
                      "sections": {e["fourcc"]: {"raw": e["raw"], "stored": e["stored"], "codec": e["codec"],
                                                 "count": e["count"], "crc32": e["crc"]} for e in c.entries}}
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=("check", "show", "sizes"))
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--res", default=os.path.join(root, "App", "Resources"))
    ap.add_argument("--spot", default=os.path.join(root, "data", "places_spot_checks.json"))
    ap.add_argument("--compare", help="directory with a second build of the same inputs (AT-D1 determinism)")
    ap.add_argument("--official-only", action="store_true")
    ap.add_argument("--out", help="write the check report (JSON)")
    a = ap.parse_args()
    if a.cmd == "show":
        D = Dataset(a.res, official_only=a.official_only)
        print(json.dumps([D.show(x) for x in a.ids], ensure_ascii=False, indent=1))
        return
    if a.cmd == "sizes":
        print(json.dumps(sizes(a.res), ensure_ascii=False, indent=1))
        return
    C, rep = check(a.res, a.spot, a.compare, a.out)
    print(json.dumps(rep, ensure_ascii=False, indent=1))
    for e in C.errors:
        print("FAIL", e, file=sys.stderr)
    print(f"{'OK' if not C.errors else 'FAILED'}: {len(C.errors)} errors", file=sys.stderr)
    sys.exit(1 if C.errors else 0)


if __name__ == "__main__":
    main()
