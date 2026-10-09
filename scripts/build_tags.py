#!/usr/bin/env python3
"""KlimaBilanz stop badges/tags builder (build_tags.py, docs/ENRICH_SPEC.md §1.4.2, §1.7 step 4, WP-D1/D2).

Inputs (read-only):
  build/places/places.json        39.7k stops (scripts/build_places.py --stage base: id, name, lat/lon, state, gem,
                                  modes, lines, flags)
  build/enrich/osm_tags.json      produced by scripts/extract_osm_tags.py from the Austria PBF (ODbL)
  <dl>/statat/x/STATISTIK_AUSTRIA_GEM_20260101.{shp,dbf}   Gemeinden (EPSG:31287) for GKZ/Bezirk
  scripts/places_curated.py       curated ski areas, regions, state colours, KlimaTicket hints, operator names

Outputs (--out, default build/tags):
  tags.json            catalog (legend, states, bezirke, skiAreas, regions) + per-stop tag lists with provenance
  tags_app.json        compact dictionary-encoded copy (QA, logo-pack tooling)
  tags_report.json     counts per tag/state, spot checks (51), provenance counts, data-quality warnings
  osm_lines.json       per stop: OSM route relations serving it (ref, name, network, operator, colour)
  ski_areas.geojson    simplified ski-area geometry (for map overlays / QA), ODbL

Per-stop record: {"g": GKZ, "b": Bezirk code, "t": [[key, value, conf, extra], ...]}
  conf = 0..100. extra = small dict (evidence, distance in m, role, ...) that always carries the provenance flag
  "osm": true (derived from OpenStreetMap, or a key/type ENRICH_SPEC AT-D7 reserves for the ODbL layer → only ever
  shipped in stops_osm.bin) or false (official sources and own work only → places.bin). A (key, value) can appear
  twice: once official and once from OSM when the OSM evidence is stronger.

Usage: python3 -I scripts/build_tags.py --places build/places/places.json --osm build/enrich/osm_tags.json \
           --gem build/places-dl/statat/x/STATISTIK_AUSTRIA_GEM_20260101 --out build/tags
Requires shapely (>=2) + numpy (scripts/requirements-enrich.txt); everything else stdlib.
"""
import argparse
import collections
import datetime
import hashlib
import importlib.util
import json
import math
import os
import re
import struct
import sys
import time
import unicodedata

import numpy as np
import shapely
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                         # repository root
DEF_PLACES = os.path.join(ROOT, "build", "places", "places.json")
DEF_OSM = os.path.join(ROOT, "build", "enrich", "osm_tags.json")
DEF_GEM = os.path.join(ROOT, "build", "places-dl", "statat", "x", "STATISTIK_AUSTRIA_GEM_20260101")
DEF_OUT = os.path.join(ROOT, "build", "tags")
DEF_SPOT = os.path.join(ROOT, "data", "places_spot_checks.json")
# keys that are always OSM-derived (polygons, aerialways, POIs, wheelchair) – ENRICH_SPEC AT-D7
OSM_KEYS = {"ski", "skiAlliance", "glacierSki", "glacier", "lift", "hut", "nationalPark", "wheelchair", "landscape"}
# place types ENRICH_SPEC AT-D7 keeps out of places.bin even when the stop name says so ("P+R …")
OSM_LAYER_TYPES = {"airport", "parkAndRide", "bikeAndRide", "university", "mall"}


def load_curated():
    spec = importlib.util.spec_from_file_location("places_curated", os.path.join(HERE, "places_curated.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


C = load_curated()
T0 = time.time()


def log(*a):
    print(f"[{time.time() - T0:6.1f}s]", *a, file=sys.stderr, flush=True)


# =============================================================================================
# geometry helpers
# =============================================================================================
LAT0, LON0 = 47.6, 13.3
KX = 111320.0 * math.cos(math.radians(LAT0))
KY = 110574.0


def to_m(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def _xy_tx(coords):
    # shapely.transform callback: coords is (N,2) array of (lon, lat)
    out = np.empty_like(coords)
    out[:, 0] = (coords[:, 0] - LON0) * KX
    out[:, 1] = (coords[:, 1] - LAT0) * KY
    return out


def _xy_inv(coords):
    out = np.empty_like(coords)
    out[:, 0] = coords[:, 0] / KX + LON0
    out[:, 1] = coords[:, 1] / KY + LAT0
    return out


def geo_to_m(g):
    return shapely.transform(g, _xy_tx)


def m_to_geo(g):
    return shapely.transform(g, _xy_inv)


class MGILambert:
    """WGS84 lat/lon -> EPSG:31287 (MGI / Austria Lambert) incl. 7-parameter datum shift.
    (Same implementation as places/build_places.py.)"""
    TX, TY, TZ, RX, RY, RZ, DS = 601.705, 84.263, 485.227, 4.7354, 1.3145, 5.393, -2.3887
    a_w, f_w = 6378137.0, 1 / 298.257223563
    a_b, f_b = 6377397.155, 1 / 299.1528128
    lat0, lon0, p1, p2, FE, FN = 47.5, 13.333333333333334, 49.0, 46.0, 400000.0, 400000.0

    @staticmethod
    def _to_ecef(lat, lon, a, f, h=0.0):
        e2 = 2 * f - f * f
        la, lo = math.radians(lat), math.radians(lon)
        N = a / math.sqrt(1 - e2 * math.sin(la) ** 2)
        return ((N + h) * math.cos(la) * math.cos(lo), (N + h) * math.cos(la) * math.sin(lo),
                (N * (1 - e2) + h) * math.sin(la))

    @staticmethod
    def _from_ecef(x, y, z, a, f):
        e2 = 2 * f - f * f
        lon = math.atan2(y, x)
        p = math.hypot(x, y)
        lat = math.atan2(z, p * (1 - e2))
        for _ in range(6):
            N = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
            h = p / math.cos(lat) - N
            lat = math.atan2(z, p * (1 - e2 * N / (N + h)))
        return math.degrees(lat), math.degrees(lon)

    @classmethod
    def forward(cls, lat, lon):
        x, y, z = cls._to_ecef(lat, lon, cls.a_w, cls.f_w)
        s = 1 + cls.DS * 1e-6
        rx, ry, rz = (math.radians(v / 3600) for v in (cls.RX, cls.RY, cls.RZ))
        x0, y0, z0 = x - cls.TX, y - cls.TY, z - cls.TZ
        xm = (x0 + rz * y0 - ry * z0) / s
        ym = (-rz * x0 + y0 + rx * z0) / s
        zm = (ry * x0 - rx * y0 + z0) / s
        blat, blon = cls._from_ecef(xm, ym, zm, cls.a_b, cls.f_b)
        return cls._lcc(blat, blon)

    @classmethod
    def _lcc(cls, lat, lon):
        a, f = cls.a_b, cls.f_b
        e2 = 2 * f - f * f
        e = math.sqrt(e2)

        def m(phi):
            return math.cos(phi) / math.sqrt(1 - e2 * math.sin(phi) ** 2)

        def t(phi):
            s = math.sin(phi)
            return math.tan(math.pi / 4 - phi / 2) / ((1 - e * s) / (1 + e * s)) ** (e / 2)

        p0, p1, p2 = (math.radians(v) for v in (cls.lat0, cls.p1, cls.p2))
        n = (math.log(m(p1)) - math.log(m(p2))) / (math.log(t(p1)) - math.log(t(p2)))
        F = m(p1) / (n * t(p1) ** n)
        r0 = a * F * t(p0) ** n
        r = a * F * t(math.radians(lat)) ** n
        th = n * math.radians(lon - cls.lon0)
        return cls.FE + r * math.sin(th), cls.FN + r0 - r * math.cos(th)


def read_shp_polys(path):
    import array
    with open(path, "rb") as fh:
        b = fh.read()
    off = 100
    while off + 8 <= len(b):
        _, clen = struct.unpack(">ii", b[off:off + 8])
        rec = b[off + 8: off + 8 + clen * 2]
        off += 8 + clen * 2
        st = struct.unpack("<i", rec[:4])[0]
        if st in (5, 15, 25):
            nparts, npts = struct.unpack("<ii", rec[36:44])
            parts = list(struct.unpack(f"<{nparts}i", rec[44:44 + 4 * nparts]))
            pts = array.array("d")
            pts.frombytes(rec[44 + 4 * nparts: 44 + 4 * nparts + 16 * npts])
            rings = []
            for i, p in enumerate(parts):
                q = parts[i + 1] if i + 1 < nparts else npts
                rings.append(np.frombuffer(pts[2 * p: 2 * q].tobytes(), dtype="<f8").reshape(-1, 2))
            yield rings
        else:
            yield None


def read_dbf(path, enc="utf-8"):
    with open(path, "rb") as fh:
        hdr = fh.read(32)
        n, hlen, rlen = struct.unpack("<IHH", hdr[4:12])
        fields = []
        while True:
            d = fh.read(32)
            if not d or d[0] == 0x0D:
                break
            fields.append((d[:11].split(b"\0")[0].decode("ascii"), d[16]))
        fh.seek(hlen)
        for _ in range(n):
            r = fh.read(rlen)
            out, pos = {}, 1
            for name, ln in fields:
                out[name] = r[pos:pos + ln].decode(enc, "replace").strip()
                pos += ln
            yield out


def rings_to_geom(rings):
    """Shapefile rings (outer CW, holes CCW) -> shapely (Multi)Polygon."""
    polys, holes = [], []
    for r in rings:
        if len(r) < 4:
            continue
        ring = Polygon(r)
        # shapefile: clockwise = outer. shapely signed area: CCW positive
        x, y = r[:, 0], r[:, 1]
        signed = 0.5 * np.sum(x[:-1] * y[1:] - x[1:] * y[:-1])
        (polys if signed < 0 else holes).append(ring)
    if not polys:
        return None
    g = unary_union(polys)
    if holes:
        g = g.difference(unary_union(holes))
    return g.buffer(0)


# =============================================================================================
# names
# =============================================================================================
STOP_TOKENS = {"an", "am", "der", "die", "das", "dem", "den", "bei", "beim", "in", "im", "ob", "a", "d", "i", "b",
               "und", "zum", "zur", "vom", "von", "auf", "st", "sankt", "bahnhof", "bf", "hbf", "bhf", "ort",
               "ortsmitte", "zentrum", "vorarlberg", "tirol", "salzburg", "karnten", "steiermark", "burgenland",
               "niederosterreich", "oberosterreich", "no", "oo", "wien", "haltestelle", "hst", "platz", "strasse",
               "gasse", "weg"}


def fold(s):
    s = (s or "").replace("​", "").replace("ß", "ss").lower()
    s = unicodedata.normalize("NFKD", s)
    return "".join(ch for ch in s if not unicodedata.combining(ch))


def toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", fold(s)) if t]


def sig_toks(s):
    return {t for t in toks(s) if len(t) >= 3 and t not in STOP_TOKENS}


def name_overlap(a, b):
    A, B = sig_toks(a), sig_toks(b)
    if not A or not B:
        return 0.0
    # tolerate compound/prefix variants ("steffisalp" vs "steffisalpe")
    hit = 0
    for x in A:
        if x in B or any((len(x) >= 5 and len(y) >= 5) and (x.startswith(y) or y.startswith(x)) for y in B):
            hit += 1
    return hit / min(len(A), len(B))


def norm_key(s):
    return fold(s).strip()


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", fold(s)).strip("-")


def role_for(stop_name, role):
    if re.search(r"(?i)bergstation", stop_name or ""):
        return "top"
    if re.search(r"(?i)talstation", stop_name or ""):
        return "valley"
    return role


STATE_BY_DIGIT = {1: "B", 2: "K", 3: "NÖ", 4: "OÖ", 5: "S", 6: "ST", 7: "T", 8: "V", 9: "W"}


# =============================================================================================
# loading
# =============================================================================================
def load_gemeinden(base):
    recs = list(read_dbf(base + ".dbf"))
    geoms, info = [], []
    for r, rings in zip(recs, read_shp_polys(base + ".shp")):
        if not rings:
            continue
        g = rings_to_geom(rings)
        if g is None or g.is_empty:
            continue
        geoms.append(g)
        info.append({"gkz": int(r["g_id"]), "name": r["g_name"]})
    tree = STRtree(geoms)
    by_state_name = {}
    for i, inf in enumerate(info):
        st = STATE_BY_DIGIT[inf["gkz"] // 10000]
        by_state_name[(st, inf["name"])] = inf["gkz"]
    return geoms, info, tree, by_state_name


def locate_gkz(lat, lon, gem):
    geoms, info, tree, _ = gem
    x, y = MGILambert.forward(lat, lon)
    p = Point(x, y)
    for i in tree.query(p, predicate="intersects"):
        return info[i]["gkz"], 0.0
    i = tree.query_nearest(p, max_distance=400, return_distance=True)
    if len(i[0]):
        return info[int(i[0][0])]["gkz"], float(i[1][0])
    return None, None


# =============================================================================================
# main build
# =============================================================================================
class Tagger:
    def __init__(self, places, osm, gem):
        self.P = places
        self.osm = osm
        self.gem = gem
        self.n = len(places)
        self.tags = [dict() for _ in range(self.n)]   # key -> {value: (conf, extra)}  best evidence of any source
        self.prov = [dict() for _ in range(self.n)]   # (key, value) -> [official (conf, extra) | None, osm … | None]
        self.warn = []
        self.stats = collections.Counter()
        xy = np.array([to_m(p["lat"], p["lon"]) for p in places])
        self.xy = xy
        self.pts = shapely.points(xy)
        self.tree = STRtree(self.pts)
        self.idx = {p["id"]: i for i, p in enumerate(places)}

    # -- tag store -------------------------------------------------------------------------------
    def add(self, i, key, value, conf, extra=None, osm=None, best=True):
        """osm: provenance (None = by key: OSM_KEYS / OSM_LAYER_TYPES are OSM, everything else official).
        best=False records the provenance slot only (official-evidence variants of a derived tag)."""
        conf = int(round(max(0, min(100, conf))))
        if osm is None:
            osm = key in OSM_KEYS or (key == "type" and value in OSM_LAYER_TYPES)
        elif key in OSM_KEYS or (key == "type" and value in OSM_LAYER_TYPES):
            osm = True
        slot = self.prov[i].setdefault((key, value), [None, None])
        k = 1 if osm else 0
        if slot[k] is None or conf > slot[k][0]:
            slot[k] = (conf, extra or {})
        if not best:
            return
        d = self.tags[i].setdefault(key, {})
        old = d.get(value)
        if old is None or conf > old[0]:
            d[value] = (conf, extra or {})

    def near(self, geom_m, dist):
        return self.tree.query(geom_m, predicate="dwithin", distance=dist)

    # -- admin ----------------------------------------------------------------------------------
    def admin(self):
        _, info, _, by_state_name = self.gem
        gkz_name = {inf["gkz"]: inf["name"] for inf in info}
        self.gkz = [None] * self.n
        miss = 0
        for i, p in enumerate(self.P):
            g, d = (None, None)
            if p["state"] != "X":
                g, d = locate_gkz(p["lat"], p["lon"], self.gem)
                if g is None and p.get("gem"):
                    g = by_state_name.get((p["state"], p["gem"]))
                    d = None
            if g is None:
                if p["state"] != "X":
                    miss += 1
                continue
            self.gkz[i] = g
            st = STATE_BY_DIGIT[g // 10000]
            bz = "900" if st == "W" else f"{g // 100:03d}"
            self.add(i, "bezirk", bz, 99 if d == 0 else 90,
                     {"name": C.BEZIRKE.get(bz, "?")})
            if st == "W":
                wb = (g // 100) % 100
                self.add(i, "wienBezirk", str(wb), 99, {"name": f"{wb}., {C.WIEN_BEZIRKE.get(wb, '?')}"})
            if gkz_name.get(g) != p.get("gem") and p.get("gem"):
                self.stats["gem_name_differs_from_pip"] += 1
        for i, p in enumerate(self.P):
            st = p["state"]
            self.add(i, "state", st, 100 if st != "X" else 90, {"code2": C.STATES[st]["code2"]})
        self.stats["gkz_missing_at"] = miss
        log("admin done; gkz missing (AT):", miss)

    def resolve_gem_list(self, spec, what):
        out = set()
        _, _, _, by_state_name = self.gem
        for st, names in (spec or {}).items():
            for nm in names:
                g = by_state_name.get((st, nm))
                if g is None:
                    self.warn.append(f"{what}: unknown Gemeinde {st}/{nm}")
                else:
                    out.add(g)
        return out

    # -- OSM node -> stop mapping -------------------------------------------------------------
    def map_osm_point(self, lat, lon, name=None, ifopt=None, max_d=250.0, strict_d=40.0):
        if ifopt:
            parts = ifopt.split(":")
            if len(parts) >= 3:
                k = ":".join(parts[:3])
                if k in self.idx:
                    return self.idx[k], 0.0, "ifopt"
        x, y = to_m(lat, lon)
        p = Point(x, y)
        cand = self.tree.query(p, predicate="dwithin", distance=max_d)
        best, bs = None, -1.0
        for j in cand:
            d = math.hypot(self.xy[j][0] - x, self.xy[j][1] - y)
            sim = name_overlap(name, self.P[j]["name"]) if name else 0.0
            if d > strict_d and sim < 0.5:
                continue
            if sim < 0.5 and name and d > strict_d * 0.6:
                continue
            score = sim * 2 - d / max_d
            if score > bs:
                best, bs = (j, d, "name" if sim >= 0.5 else "geo"), score
        return best if best else (None, None, None)

    # =========================================================================================
    # ski areas
    # =========================================================================================
    def ski(self):
        osm = self.osm
        gem_geoms, gem_info, gem_tree, _ = self.gem
        ski = {s["id"]: dict(s) for s in C.SKI}
        name2ids = collections.defaultdict(list)
        for s in C.SKI:
            for nm in s.get("osm", []):
                name2ids[norm_key(nm)].append(s["id"])
        for s in ski.values():
            s["gkz"] = self.resolve_gem_list(s.get("gem"), f"ski {s['id']}")
            s["polys"] = []
            s["src"] = "curated"

        def gkz_of_geo(lat, lon):
            x, y = MGILambert.forward(lat, lon)
            r = gem_tree.query(Point(x, y), predicate="intersects")
            return gem_info[int(r[0])]["gkz"] if len(r) else None

        # stops per gkz for plausibility checks
        stops_by_gkz = collections.defaultdict(list)
        for i, g in enumerate(self.gkz):
            if g:
                stops_by_gkz[g].append(i)

        auto = {}
        ws = [a for a in osm["areas"] if a["kind"] == "winter_sports"]
        for a in ws:
            nm = (a["tags"].get("name") or "").replace("​", "").strip()
            g = geo_to_m(shape(a["geom"])).buffer(0)
            if g.is_empty:
                continue
            a["_g"] = g
            gk = gkz_of_geo(a["lat"], a["lon"])
            a["_gkz"] = gk
            ids = name2ids.get(norm_key(nm), []) if nm else []
            placed = False
            for sid in ids:
                s = ski[sid]
                if s["kind"] == "alliance":
                    s["polys"].append(a)
                    placed = True
                    continue
                ok = gk in s["gkz"]
                if not ok:
                    # plausibility: polygon within 6 km of any stop of a member Gemeinde
                    for g2 in s["gkz"]:
                        js = stops_by_gkz.get(g2, [])
                        if js and min(g.distance(self.pts[j]) for j in js[:400]) < 6000:
                            ok = True
                            break
                if ok:
                    s["polys"].append(a)
                    placed = True
                else:
                    self.warn.append(f"ski {sid}: OSM polygon '{nm}' {a['osm']} rejected (outside member Gemeinden)")
            if not placed and nm and not re.search(C.AUTO_SKI_EXCLUDE, nm):
                sid = "osm-" + slug(nm)
                if sid in auto:
                    auto[sid]["polys"].append(a)
                else:
                    auto[sid] = {"id": sid, "kind": "area", "name": nm, "osm": [nm], "polys": [a], "src": "osm",
                                 "gkz": set(), "max_km": 1.5,
                                 "glacier": bool(re.search(r"(?i)gletscher", nm))}
        ski.update(auto)

        # ---- lifts ---------------------------------------------------------------------------
        lifts = []
        for l in osm["lifts"]:
            if l["disused"]:
                continue
            a = to_m(*l["a"])
            b = to_m(*l["b"])
            lifts.append({**l, "_a": Point(a), "_b": Point(b), "_ln": LineString([a, b])})
        # OSM draws aerialways uphill; fix obviously reversed big lifts (only the far end has stops)
        rx_berg, rx_tal = re.compile(r"(?i)bergstation"), re.compile(r"(?i)talstation")
        flipped = 0
        for l in lifts:
            if l["type"] not in ("funicular", "cable_car", "gondola"):
                continue
            na = [int(j) for j in self.near(l["_a"], 250)]
            nb = [int(j) for j in self.near(l["_b"], 250)]
            berg_b = any(rx_berg.search(self.P[j]["name"]) for j in nb)
            tal_b = any(rx_tal.search(self.P[j]["name"]) for j in nb)
            berg_a = any(rx_berg.search(self.P[j]["name"]) for j in na)
            if (not na and nb and not berg_b) or (tal_b and not berg_b) or (berg_a and not tal_b):
                l["_a"], l["_b"] = l["_b"], l["_a"]
                l["a"], l["b"] = l["b"], l["a"]
                l["_ln"] = LineString([l["_a"].coords[0], l["_b"].coords[0]])
                l["flipped"] = True
                flipped += 1
        self.stats["lifts_direction_flipped"] = flipped
        self.lifts = lifts
        lift_tree = STRtree([l["_ln"] for l in lifts])
        PASSENGER = {"gondola", "cable_car", "chair_lift", "mixed_lift", "funicular"}
        for l in lifts:
            l["_gkz_a"] = gkz_of_geo(*l["a"])

        # ---- geometry per area (areas + their sectors) ----------------------------------------
        children = collections.defaultdict(list)
        for s in ski.values():
            if s["kind"] == "sector":
                children[s["parent"]].append(s["id"])
        for s in ski.values():
            geoms = [a["_g"] for a in s["polys"]]
            if s.get("lift_re") and not geoms:
                rx = re.compile(s["lift_re"])
                sel = [l for l in lifts if l["_gkz_a"] in s["gkz"] and l.get("name") and rx.search(l["name"])]
                if sel:
                    geoms = [unary_union([l["_ln"] for l in sel]).buffer(350)]
                    s["geom_src"] = f"lifts({len(sel)})"
            s["_own"] = unary_union(geoms) if geoms else None
        for s in ski.values():
            parts = [s["_own"]] if s["_own"] is not None else []
            for c in children.get(s["id"], []):
                if ski[c]["_own"] is not None:
                    parts.append(ski[c]["_own"])
            s["_geom"] = unary_union(parts) if parts else None
            if s["_geom"] is None and s["kind"] != "alliance":
                self.warn.append(f"ski {s['id']}: no geometry (no OSM polygon / lifts) - Gemeinde rule only")
        self.ski_areas = ski

        # ---- assign lifts to areas (direct overlap, then chained access lifts) -----------------
        area_ids = [sid for sid, s in ski.items() if s["kind"] in ("area", "sector") and s["_geom"] is not None]
        for l in lifts:
            l["area"] = None
        for sid in area_ids:
            s = ski[sid]
            g = s["_geom"]
            for k in lift_tree.query(g, predicate="dwithin", distance=150):
                l = lifts[k]
                ov = l["_ln"].intersection(g.buffer(150)).length / max(1.0, l["_ln"].length)
                prev = l.get("_ov", -1)
                # prefer sectors over areas only when overlap is equal; else the larger overlap wins
                if ov > prev + 1e-6:
                    l["area"], l["_ov"] = sid, ov
        for sid in area_ids:   # curated access lifts (e.g. Tiroler Zugspitzbahn -> Zugspitze glacier)
            rx = ski[sid].get("force_lift_re")
            if rx:
                for l in lifts:
                    if l.get("name") and re.search(rx, l["name"]):
                        l["area"], l["_ov"] = sid, 9.0
        for _ in range(3):   # chain: lift whose top is next to an assigned lift's valley end
            assigned = [l for l in lifts if l["area"]]
            if not assigned:
                break
            ends = [l["_a"] for l in assigned] + [l["_b"] for l in assigned]
            vt = STRtree(ends)
            changed = 0
            for l in lifts:
                if l["area"] or l["type"] not in PASSENGER:
                    continue
                r = vt.query(l["_b"], predicate="dwithin", distance=300)
                if len(r):
                    l["area"] = assigned[int(r[0]) % len(assigned)]["area"]
                    l["_chain"] = True
                    changed += 1
            if not changed:
                break
        for s in ski.values():
            s["lifts"] = [l for l in lifts if l["area"] == s["id"]]

        # auto areas need at least one real ski lift (not only a cable car / funicular)
        SKI_LIFTS = {"chair_lift", "t-bar", "j-bar", "platter", "drag_lift", "rope_tow", "mixed_lift", "gondola",
                     "magic_carpet"}
        for sid in list(auto):
            if not any(l["type"] in SKI_LIFTS for l in ski[sid]["lifts"]):
                self.warn.append(f"auto ski area {sid} dropped (no ski lift)")
                for l in ski[sid]["lifts"]:
                    l["area"] = None
                del ski[sid]
                del auto[sid]
        area_ids = [x for x in area_ids if x in ski]
        # auto areas: member Gemeinden = Gemeinden of their lifts' valley stations (+ polygon centre)
        for s in auto.values():
            gs = {l["_gkz_a"] for l in s["lifts"] if l["_gkz_a"]}
            for a in s["polys"]:
                if a.get("_gkz"):
                    gs.add(a["_gkz"])
            s["gkz"] = gs

        # ---- stop rules -------------------------------------------------------------------------
        def area_root(sid):
            s = ski[sid]
            return s["parent"] if s["kind"] == "sector" else sid

        for sid in area_ids + [x for x in ski if ski[x]["kind"] in ("area", "sector") and ski[x]["_geom"] is None]:
            s = ski[sid]
            cur = s["src"] == "curated"
            g = s["_geom"]
            maxm = float(s.get("max_km", 1.5)) * 1000
            root = area_root(sid)
            key_val = root  # sectors report their parent area; the sector id goes into extra
            sector = sid if s["kind"] == "sector" else None
            hits = {}
            if g is not None:
                for j in self.near(g, max(maxm, 600)):
                    j = int(j)
                    d = g.distance(self.pts[j])
                    member = self.gkz[j] in s["gkz"]
                    if d <= 1.0:
                        hits[j] = (95 if cur else 85, "in", d)
                    elif member and d <= (maxm if cur else 800):
                        hits[j] = ((92 if d <= 1500 else (82 if d <= 3000 else 75)) if cur else 64, "resort", d)
                    elif d <= (300 if cur else 400):
                        hits[j] = (68 if cur else 60, "near", d)
            else:
                # no geometry at all: Gemeinde membership only (lower confidence)
                for g2 in s["gkz"]:
                    for j in [k for k, gg in enumerate(self.gkz) if gg == g2]:
                        hits[j] = (70, "resort-nogeo", None)
            # lift access (valley = first node; OSM aerialways are drawn uphill)
            for l in s["lifts"]:
                if l["type"] not in PASSENGER and l["type"] not in ("t-bar", "drag_lift", "platter", "j-bar"):
                    continue
                for end, role in ((l["_a"], "valley"), (l["_b"], "top")):
                    for j in self.near(end, 250):
                        j = int(j)
                        d = end.distance(self.pts[j])
                        role_j = role_for(self.P[j]["name"], role)
                        c = (95 if role_j == "valley" else 85) if cur else (85 if role_j == "valley" else 75)
                        if l["type"] not in PASSENGER:
                            c -= 10
                        prev = hits.get(j)
                        if prev is None or prev[1] != "lift":
                            hits[j] = (max(c, prev[0] if prev else 0), "lift", d, l.get("name"), role_j)
                        elif c > prev[0] or (c == prev[0] and d < prev[2]):
                            hits[j] = (c, "lift", d, l.get("name"), role_j)
            for j, h in hits.items():
                ex = {"rule": h[1]}
                if h[2] is not None:
                    ex["d"] = int(round(h[2]))
                if sector:
                    ex["sector"] = sector
                if h[1] == "lift":
                    if h[3]:
                        ex["lift"] = h[3]
                    ex["role"] = h[4]
                if not cur:
                    ex["src"] = "osm"
                self.add(j, "ski", key_val, h[0], ex)

        # alliances, glacier flag from the areas a stop got
        for i in range(self.n):
            sk = self.tags[i].get("ski")
            if not sk:
                continue
            for sid, (conf, ex) in list(sk.items()):
                s = ski[sid]
                al = list(s.get("alliances", []))
                if ex.get("sector"):
                    al += ski[ex["sector"]].get("alliances", [])
                for aid in dict.fromkeys(al):
                    self.add(i, "skiAlliance", aid, min(conf, 90), {"via": sid})
                if (s.get("glacier") or (ex.get("sector") and ski[ex["sector"]].get("glacier"))) and \
                        ex["rule"] in ("in", "lift", "resort") and ex.get("d", 0) <= 3000:
                    self.add(i, "glacierSki", sid, min(conf, 90))
        # Ski amadé also by region polygon for areas we did not curate (auto areas inside the relation)
        log("ski areas:", sum(1 for s in ski.values() if s["kind"] == "area"), "areas;",
            sum(1 for s in auto.values()), "auto;", sum(1 for l in lifts if l["area"]), "lifts assigned")

    # =========================================================================================
    # lifts / Bergbahn stations near stops
    # =========================================================================================
    def lift_stations(self):
        PASSENGER = {"gondola", "cable_car", "chair_lift", "mixed_lift", "funicular"}
        rx_lift = re.compile(C.NAME_RULES["lift"])
        for l in self.lifts:
            if l["type"] not in PASSENGER:
                continue
            for end, role in ((l["_a"], "valley"), (l["_b"], "top")):
                for j in self.near(end, 200):
                    j = int(j)
                    d = end.distance(self.pts[j])
                    nm = l.get("name") or {"funicular": "Standseilbahn", "cable_car": "Seilbahn",
                                           "gondola": "Gondelbahn", "chair_lift": "Sesselbahn",
                                           "mixed_lift": "Kombibahn"}[l["type"]]
                    conf = 90 if d <= 100 else 75
                    if l.get("name") and name_overlap(l["name"], self.P[j]["name"]) >= 0.5:
                        conf = 97
                    elif rx_lift.search(self.P[j]["name"]):
                        conf = max(conf, 92)
                    self.add(j, "lift", nm, conf, {"type": l["type"], "role": role_for(self.P[j]["name"], role),
                                                   "d": int(round(d))})
        # aerialway=station nodes with names
        for nid, (la, lo, t) in self.osm["pt"].items():
            if t.get("aerialway") != "station" or not t.get("name"):
                continue
            if re.search(r"(?i)material", t["name"]):
                continue
            p = Point(to_m(la, lo))
            for j in self.near(p, 120):
                j = int(j)
                d = p.distance(self.pts[j])
                ex = {"type": "station", "d": int(round(d))}
                if t.get("aerialway:access"):
                    ex["access"] = t["aerialway:access"]
                self.add(j, "lift", t["name"], 88 if d <= 80 else 72, ex)
        # name-only evidence (e.g. "Zürs Seekopfbahn", "Talstation")
        for i, p in enumerate(self.P):
            if "lift" not in self.tags[i] and rx_lift.search(p["name"]) and not re.search(r"(?i)bahnhof|\bbf\b", p["name"]):
                m = re.search(r"(?i)([A-ZÄÖÜa-zäöüß\-]*(bahn|lift|seilbahn|talstation|bergstation))\b", p["name"])
                if m and not re.search(r"(?i)^(s-?bahn|u-?bahn|eisenbahn|straßenbahn|strassenbahn|lokalbahn|"
                                       r"bahn|landesbahn|autobahn|westbahn|südbahn|ostbahn|nordbahn|ennstalbahn|"
                                       r"mariazellerbahn|badner ?bahn|zillertalbahn|stubaitalbahn|pinzgauer lokalbahn|"
                                       r"murtalbahn|montafonerbahn|wiener lokalbahn|rennbahn|reitbahn|trabrennbahn|"
                                       r"kegelbahn|eislaufbahn|bobbahn|rodelbahn|radrennbahn)$", m.group(1)):
                    nm = m.group(1)
                    self.add(i, "lift", nm, 60, {"type": "name"})

    # =========================================================================================
    # place types
    # =========================================================================================
    def place_types(self):
        P = self.P
        NR = {k: re.compile(v) for k, v in C.NAME_RULES.items()}
        RAIL = 1 | 4 | 8 | 16 | 32 | 4096
        rail_idx = []
        for i, p in enumerate(P):
            m, nm = p["modes"], p["name"]
            lines = set((p.get("lines") or "").split(",")) - {""}
            if m & RAIL:
                rail_idx.append(i)
                main = bool(NR["main_station"].search(nm))
                self.add(i, "type", "trainStation", 98, {"main": True} if main else None)
                if main:
                    self.add(i, "type", "mainStation", 98)
            if m & (1 | 4):
                self.add(i, "type", "longDistance", 95)
            if m & 8 or lines & {"NJ", "EN"}:
                self.add(i, "type", "nightTrain", 92, {"lines": sorted(lines & {"NJ", "EN"})} if lines & {"NJ", "EN"} else None)
            if m & 32:
                self.add(i, "type", "sBahn", 97)
            if m & 256:
                u = sorted(l for l in lines if re.fullmatch(r"U\d", l))
                self.add(i, "type", "uBahn", 98, {"lines": u} if u else None)
            if m & 512:
                self.add(i, "type", "tram", 97)
            if m & 4096:
                self.add(i, "type", "privateRail", 90)
            if m & 2 and not (m & RAIL):
                self.add(i, "type", "railReplacement", 80)
            if m & 128:
                self.add(i, "type", "ship", 95)
            if m & 2048:
                if "lift" in self.tags[i] or NR["lift"].search(nm):
                    self.add(i, "type", "cableCar", 90, osm=not NR["lift"].search(nm))
                else:
                    self.add(i, "type", "onDemand", 55, {"why": "mode bit 2048 (cable/on-demand) without lift nearby"})
            if re.search(r"(?i)(busbahnhof|busterminal|autobusbahnhof|\bzob\b|busstation)", nm):
                self.add(i, "type", "busStation", 92)
        # bus stops named "... Bahnhof" or next to a rail stop -> rail transfer
        rpts = STRtree([self.pts[i] for i in rail_idx]) if rail_idx else None
        for i, p in enumerate(P):
            if p["modes"] & RAIL or rpts is None:
                continue
            r = rpts.query_nearest(self.pts[i], max_distance=400, return_distance=True)
            if not len(r[0]):
                continue
            j, d = rail_idx[int(r[0][0])], float(r[1][0])
            named = bool(NR["station"].search(p["name"]) or NR["main_station"].search(p["name"]))
            if (named and d <= 400) or d <= 150:
                self.add(i, "railTransfer", P[j]["id"], 92 if named else 75,
                         {"name": P[j]["name"], "d": int(round(d))})
        # OSM bus_station amenity
        for nid, (la, lo, t) in self.osm["pt"].items():
            if t.get("amenity") == "bus_station":
                pnt = Point(to_m(la, lo))
                for j in self.near(pnt, 80):
                    self.add(int(j), "type", "busStation", 85, {"osm": t.get("name")}, osm=True)

        # ---- POI based (areas + nodes) -------------------------------------------------------
        feats = collections.defaultdict(list)
        for a in self.osm["areas"]:
            if a["kind"] in ("hospital", "university", "mall", "aerodrome", "park_ride", "bike_ride", "college",
                             "alpine_hut", "glacier"):
                feats[a["kind"]].append((geo_to_m(shape(a["geom"])).buffer(0), a["tags"], a))
        for a in self.osm["pois"]:
            if a["kind"] in ("hospital", "university", "mall", "aerodrome", "park_ride", "bike_ride", "college",
                             "alpine_hut", "ferry_terminal"):
                feats[a["kind"]].append((Point(to_m(a["lat"], a["lon"])), a["tags"], a))
        self.feats = feats

        def geo_rule(kind, dist, conf_in, conf_near, key, value_fn, min_area=0.0, filt=None):
            n = 0
            for g, t, a in feats.get(kind, []):
                if filt and not filt(t, a):
                    continue
                if min_area and g.geom_type != "Point" and g.area < min_area:
                    continue
                dd = dist if g.geom_type != "Point" else dist * 0.8
                for j in self.near(g, dd):
                    j = int(j)
                    d = g.distance(self.pts[j])
                    self.add(j, key, value_fn(t), conf_in if d <= 1 else conf_near, {"d": int(round(d)), "osm": a["osm"]},
                             osm=True)
                    n += 1
            return n

        # hospitals: geo + name
        geo_rule("hospital", 100, 78, 66, "type", lambda t: "hospital", min_area=3000)
        for i, p in enumerate(P):
            if NR["hospital"].search(p["name"]):
                self.add(i, "type", "hospital", 92, {"by": "name"})
        # universities (amenity=university only; colleges in AT are mostly schools)
        geo_rule("university", 100, 76, 62, "type", lambda t: "university", min_area=8000)
        for i, p in enumerate(P):
            if NR["university"].search(p["name"]):
                self.add(i, "type", "university", 88, {"by": "name"})
        # malls (>= 3000 m2)
        geo_rule("mall", 80, 78, 62, "type", lambda t: "mall", min_area=5000)
        for i, p in enumerate(P):
            if NR["mall"].search(p["name"]):
                self.add(i, "type", "mall", 80, {"by": "name"})
        # P+R / B+R
        geo_rule("park_ride", 180, 85, 72, "type", lambda t: "parkAndRide")
        geo_rule("bike_ride", 100, 85, 75, "type", lambda t: "bikeAndRide")
        for i, p in enumerate(P):
            if NR["park_ride"].search(p["name"]):
                self.add(i, "type", "parkAndRide", 95, {"by": "name"})
            if NR["bike_ride"].search(p["name"]):
                self.add(i, "type", "bikeAndRide", 95, {"by": "name"})
        # airports (IATA, public/international)
        def is_airport(t, a):
            return bool(t.get("iata")) and (t.get("aerodrome:type") in ("public", "international", "military/public")
                                            or t.get("aerodrome") in ("international", "regional", "public"))
        for g, t, a in feats.get("aerodrome", []):
            if not is_airport(t, a):
                continue
            for j in self.near(g, 1500):
                j = int(j)
                d = g.distance(self.pts[j])
                named = bool(NR["airport"].search(P[j]["name"]))
                if d <= 300 or (named and d <= 1500):
                    self.add(j, "type", "airport", 97 if named else 75,
                             {"iata": t.get("iata"), "name": t.get("name"), "d": int(round(d))})
        # ferry / Schiff
        for g, t, a in feats.get("ferry_terminal", []):
            for j in self.near(g, 150):
                j = int(j)
                d = g.distance(self.pts[j])
                if d <= 60 or name_overlap(t.get("name"), P[j]["name"]) >= 0.5:
                    self.add(j, "type", "ship", 85 if P[j]["modes"] & 128 else 70, {"osm": t.get("name")}, osm=True)
        for i, p in enumerate(P):
            if NR["ferry"].search(p["name"]) and not p["modes"] & 128:
                self.add(i, "type", "ship", 62, {"by": "name"})
        # alpine huts
        for g, t, a in feats.get("alpine_hut", []):
            if not t.get("name"):
                continue
            for j in self.near(g, 150):
                j = int(j)
                d = g.distance(self.pts[j])
                c = 85 if name_overlap(t["name"], P[j]["name"]) >= 0.5 else 65
                self.add(j, "hut", t["name"], c, {"d": int(round(d))})
        # glaciers (natural=glacier polygons) - stop within 1.5 km
        for g, t, a in feats.get("glacier", []):
            if g.area < 50_000:
                continue
            for j in self.near(g, 2000):
                j = int(j)
                d = g.distance(self.pts[j])
                self.add(j, "glacier", t.get("name") or "Gletscher", 85 if d <= 500 else (75 if d <= 1000 else 66),
                         {"d": int(round(d))})
        for i, p in enumerate(P):
            if "glacierSki" in self.tags[i]:
                sid = next(iter(self.tags[i]["glacierSki"]))
                self.add(i, "glacier", self.ski_areas[sid]["name"], self.tags[i]["glacierSki"][sid][0], {"by": "skiArea"})
            if NR["glacier"].search(p["name"]) and "glacier" not in self.tags[i]:
                self.add(i, "glacier", "Gletscher", 75, {"by": "name"})

    # =========================================================================================
    # national parks, regions
    # =========================================================================================
    def regions(self):
        P = self.P
        np_re = re.compile(C.NP_RE)
        for a in self.osm["areas"]:
            if a["kind"] != "national_park":
                continue
            nm = a["tags"].get("name") or ""
            if not np_re.search(nm):
                continue
            g = geo_to_m(shape(a["geom"])).buffer(0)
            for j in self.near(g, 500):
                j = int(j)
                d = g.distance(self.pts[j])
                self.add(j, "nationalPark", nm, 92 if d <= 1 else 72, {"d": int(round(d))} if d > 1 else None)
        # OSM region polygons
        osm_regions = collections.defaultdict(list)
        for a in self.osm["areas"]:
            if a["kind"] in ("region", "tourism"):
                nm = a["tags"].get("name")
                if nm:
                    osm_regions[nm].append(geo_to_m(shape(a["geom"])).buffer(0))
        osm_geom = {nm: unary_union(gs) for nm, gs in osm_regions.items()}

        def pip_hits(geom):
            return [int(j) for j in self.tree.query(geom, predicate="intersects")]

        self.region_catalog = {}
        for r in C.REGIONS:
            rid = r["id"]
            g_set = self.resolve_gem_list(r.get("gem"), f"region {rid}")
            bz = set(r.get("bezirk", []))
            gem_hits = set()
            for i, g in enumerate(self.gkz):
                if not g:
                    continue
                st = STATE_BY_DIGIT[g // 10000]
                b = "900" if st == "W" else f"{g // 100:03d}"
                if g in g_set or b in bz:
                    gem_hits.add(i)
            osm_hits = set()
            if r.get("osm"):
                if r["osm"] in osm_geom:
                    osm_hits = set(pip_hits(osm_geom[r["osm"]]))
                else:
                    self.warn.append(f"region {rid}: OSM polygon '{r['osm']}' not found")
            base = float(r.get("conf", 0.85)) * 100
            for i in gem_hits | osm_hits:
                if r.get("only_with_ski") and r["only_with_ski"] not in self.tags[i].get("ski", {}):
                    continue
                ski_dep = bool(r.get("only_with_ski"))     # membership depends on an (OSM-derived) ski tag
                gsrc = "gem" if r.get("gem") else "bezirk"
                if i in gem_hits and i in osm_hits:
                    c, src = max(base, 90), "gem+osm"
                    # provenance: the Gemeinde/Bezirk rule alone is official; the OSM polygon only raises confidence
                    self.add(i, "region", rid, base, {"src": gsrc}, osm=ski_dep, best=False)
                elif i in gem_hits:
                    c, src = base, gsrc
                else:
                    c, src = min(base, 80), "osm"
                self.add(i, "region", rid, c, {"src": src}, osm=ski_dep or src != gsrc)
            self.region_catalog[rid] = {"name": r["name"], "kind": "tourism", "conf": r.get("conf"),
                                        "note": r.get("note"), "stops": len(gem_hits | osm_hits)}
        for nm in C.OSM_VIERTEL:
            if nm not in osm_geom:
                self.warn.append(f"viertel '{nm}' not in OSM extract")
                continue
            rid = "v-" + slug(nm)
            hits = [i for i in pip_hits(osm_geom[nm])
                    if self.P[i]["state"] != "W" and not (self.gkz[i] and self.gkz[i] // 100 in (401, 402, 403))]
            for i in hits:
                self.add(i, "landscape", rid, 85, None)
            self.region_catalog[rid] = {"name": nm, "kind": "landscape", "conf": 0.85, "stops": len(hits)}
        # Arlberg special: stops tagged Ski Arlberg are also in region Arlberg
        for i in range(self.n):
            sk = self.tags[i].get("ski", {})
            if "ski-arlberg" in sk and sk["ski-arlberg"][0] >= 85:
                self.add(i, "region", "arlberg", 88, {"src": "skiArea"}, osm=True)

    # =========================================================================================
    # OSM routes -> service kinds (night/ski/hiking/on-demand/seasonal/airport) + osm lines
    # =========================================================================================
    def routes(self):
        RX = {
            "nightBus": re.compile(r"(?i)(nacht|night|moonliner|nightliner|nightline|nachtschwärmer|disco ?bus)"),
            "skiBus": re.compile(r"(?i)(ski ?-?bus|schi ?-?bus|ski ?-?shuttle|schi ?-?shuttle|skizubringer|gletscherbus|"
                                 r"ski ?express|skibus|ski-linie|winterbus)"),
            "hikingBus": re.compile(r"(?i)(wanderbus|almbus|alm-bus|bergsteigerbus|wandershuttle|hikerbus|hiking|"
                                    r"tälerbus|wanderexpress|almtaxi|almshuttle|hüttentaxi|naturpark ?bus|"
                                    r"nationalpark ?bus|nockbergebus|bergbus|almsammeltaxi|sommerbus|wanderlinie)"),
            "onDemand": re.compile(r"(?i)(rufbus|anruf|\bast\b|on.?demand|istmobil|ist-mobil|postbus shuttle|go-mobil|"
                                   r"gmoabus|regiotaxi|salzkammergut-shuttle|tennengau shuttle|bedarfsverkehr|"
                                   r"rufsammeltaxi|sammeltaxi|mikro-?öv|\btaxi\b)"),
            "seasonal": re.compile(r"(?i)(\(sommer\)|\(winter\)|sommerfahrplan|winterfahrplan|saison|nur im sommer|"
                                   r"nur im winter|\bsommer\b|\bwinter\b)"),
        }
        AIR = re.compile(r"(?i)(flughafen|airport)")
        stop_routes = collections.defaultdict(dict)
        kinds_ct = collections.Counter()
        unmapped = 0
        member_cache = {}
        for r in self.osm["routes"]:
            t = r["tags"]
            route = t.get("route")
            net = t.get("network") or ""
            if re.search(r"(?i)flixbus|regiojet bus|blablacar", net + " " + (t.get("operator") or "")):
                continue
            text = " ".join(t.get(k, "") or "" for k in ("name", "ref", "network", "description", "note", "official_name"))
            ref = (t.get("ref") or "").strip()
            kinds = set()
            if route in ("bus", "trolleybus", "share_taxi", "tram", "coach"):
                if re.fullmatch(r"N\d+[A-Z]?|\d+N|NL\d*|N", ref) or RX["nightBus"].search(text) or t.get("night") == "yes":
                    kinds.add("nightBus")
                if RX["skiBus"].search(text) or ref.lower() in ("ski", "skibus"):
                    kinds.add("skiBus")
                if RX["hikingBus"].search(text):
                    kinds.add("hikingBus")
                if RX["onDemand"].search(text) or route == "share_taxi":
                    kinds.add("onDemand")
                if RX["seasonal"].search(text) or t.get("seasonal") not in (None, "no"):
                    kinds.add("seasonal")
                frm_to = " ".join([t.get("from", ""), t.get("to", ""), t.get("name", "")])
                if AIR.search(frm_to):
                    kinds.add("airportLink")
            elif route == "train":
                if re.search(r"(?i)nightjet|euronight|\bNJ\b|\bEN\b", text) or ref.startswith(("NJ", "EN")):
                    kinds.add("nightTrain")
                if AIR.search(" ".join([t.get("from", ""), t.get("to", "")])):
                    kinds.add("airportLink")
            elif route == "ferry":
                kinds.add("ferryRoute")
            elif route in ("aerialway", "funicular"):
                kinds.add("liftRoute")
            mapped = set()
            for mid, role, la, lo in r["members"]:
                if mid in member_cache:
                    j = member_cache[mid]
                else:
                    src = self.osm["pt"].get(mid[1:]) if mid[0] == "n" else self.osm["ptw"].get(mid[1:])
                    nm = src[2].get("name") if src else None
                    ifo = src[2].get("ref:IFOPT") if src else None
                    j, d, how = self.map_osm_point(la, lo, nm, ifo, max_d=250, strict_d=60 if not nm else 35)
                    member_cache[mid] = j
                if j is None:
                    unmapped += 1
                    continue
                mapped.add(j)
            for j in mapped:
                key = (ref or t.get("name") or r["osm"], net)
                sr = stop_routes[j]
                if key not in sr:
                    sr[key] = {"ref": ref or None, "name": t.get("name"), "network": net or None,
                               "operator": t.get("operator"), "route": route, "colour": t.get("colour"),
                               "osm": [r["osm"]], "kinds": sorted(kinds)}
                else:
                    sr[key]["osm"].append(r["osm"])
                    sr[key]["kinds"] = sorted(set(sr[key]["kinds"]) | kinds)
            for k in kinds:
                kinds_ct[k] += 1
        self.stats["route_members_unmapped"] = unmapped
        self.stop_routes = stop_routes
        CONF = {"nightBus": 85, "skiBus": 85, "hikingBus": 85, "onDemand": 75, "seasonal": 70, "airportLink": 80,
                "nightTrain": 88, "ferryRoute": 85, "liftRoute": 85}
        for j, sr in stop_routes.items():
            per_kind = collections.defaultdict(list)
            for v in sr.values():
                for k in v["kinds"]:
                    per_kind[k].append(v["ref"] or v["name"])
            for k, refs in per_kind.items():
                refs = [x if len(x) <= 40 else x[:38] + "…" for x in refs if x]
                if k in ("ferryRoute",):
                    self.add(j, "type", "ship", 88, {"by": "osmRoute"}, osm=True)
                    continue
                if k == "liftRoute":
                    continue
                if k == "nightTrain":
                    self.add(j, "type", "nightTrain", 88, {"by": "osmRoute"}, osm=True)
                    continue
                self.add(j, "service", k, CONF[k], {"lines": sorted({x for x in refs if x})[:8]}, osm=True)
        # night lines from the dataset itself (Wien N-lines are mostly not in the GK line lists)
        for i, p in enumerate(self.P):
            ls = [l for l in (p.get("lines") or "").split(",") if re.fullmatch(r"N\d+[A-Z]?|\d+N", l)]
            if ls:
                self.add(i, "service", "nightBus", 90, {"lines": sorted(set(ls))})
        log("routes: stops with OSM routes", len(stop_routes), "kinds", dict(kinds_ct))

    # =========================================================================================
    # accessibility (OSM wheelchair on platforms/stop positions)
    # =========================================================================================
    def wheelchair(self):
        agg = collections.defaultdict(collections.Counter)
        for nid, (la, lo, t) in self.osm["pt"].items():
            w = t.get("wheelchair")
            if w not in ("yes", "no", "limited"):
                continue
            if t.get("aerialway"):
                continue
            j, d, how = self.map_osm_point(la, lo, t.get("name"), t.get("ref:IFOPT"), max_d=150, strict_d=25)
            if j is not None:
                agg[j][w] += 1
        for j, c in agg.items():
            n = sum(c.values())
            if c["yes"] and not c["no"] and not c["limited"]:
                v = "yes"
            elif c["no"] and not c["yes"] and not c["limited"]:
                v = "no"
            else:
                v = "limited"
            self.add(j, "wheelchair", v, 80 if n >= 2 else 70, {"n": n, **{k: c[k] for k in c}})

    # =========================================================================================
    # KlimaTicket hint
    # =========================================================================================
    def klimaticket(self):
        """KlimaTicket validity hint. Decided twice: with every piece of evidence (tags.json "best" view, tags_app.json,
        spot checks) and with official evidence only (stop modes and names, official line refs, official tags) – the
        latter is the tag places.bin ships, so the official layer never depends on OSM (ENRICH_SPEC §1.1)."""
        P = self.P
        border = re.compile(C.KT_BORDER_STATIONS)
        excl = re.compile(C.KT_EXCLUDED_NAMES)
        _, info, _, by_state_name = self.gem
        gkz_name = {inf["gkz"]: inf["name"] for inf in info}
        ext = collections.defaultdict(list)
        for st, gm, tid, tname in C.KLIMATICKET_EXTENSIONS:
            g = by_state_name.get((st, gm))
            if g is None:
                self.warn.append(f"klimaticket extension: unknown Gemeinde {st}/{gm}")
            else:
                ext[g].append({"id": tid, "name": tname, "ext": True})
        RAIL_TOKENS = re.compile(r"^(RJX?|ICE?|ECE?|EC|IC|D|EN|NJ|IR|WB|REX\d*|R\d*|CJX\d*|S\d+[A-Z]?|U\d)$")

        def decide(i, types, services, has_bus_routes):
            p = P[i]
            st = p["state"]
            m = p["modes"]
            g = self.gkz[i]
            gname = gkz_name.get(g)
            hint = {"verbund": C.STATES[st]["verbund"]}
            if st == "X":
                if border.search(p["name"]):
                    oe, conf, why = "border", 75, "Gemeinschaftsbahnhof/Grenzbahnhof – KlimaTicket Ö bis hierher"
                elif re.search(r"(?i)^freilassing", p["name"]):
                    oe, conf, why = "border", 70, "Freilassing: KlimaTicket Salzburg gilt; KT Ö nur ÖBB-Grenzverkehr prüfen"
                else:
                    oe, conf, why = "no", 80, "Ausland"
                hint["reg"] = [{"id": "salzburg", "name": "KlimaTicket Salzburg"}] if re.search(r"(?i)^freilassing", p["name"]) else []
            else:
                oe, conf, why = "yes", 90, None
                only_cable = "cableCar" in types and not (m & ~2048)
                if only_cable and not re.search(r"(?i)schlossberg", p["name"]):
                    if has_bus_routes:
                        oe, conf, why = "check", 70, "Seilbahn nicht im KlimaTicket; Busse an dieser Haltestelle schon"
                    else:
                        oe, conf, why = "no", 80, "Seilbahn – nicht im KlimaTicket (Ausnahme Grazer Schlossbergbahn)"
                elif m == 128:
                    oe, conf, why = "check", 70, "Schifffahrt – meist nicht inkludiert (z. B. Salzkammergut-Seen, Wolfgangsee)"
                elif excl.search(p["name"]) and not (m & 64):
                    oe, conf, why = "check", 70, "Nostalgie-/Tourismus-/Zahnradbahn – nicht inkludiert"
                elif excl.search(p["name"]) or re.search(r"(?i)schafberg ?b(ahnho)?f|schafbergbahn", p["name"]):
                    why = "Busse gültig; Nostalgie-/Zahnradbahn bzw. Schifffahrt hier nicht inkludiert"
                    conf = 80
                elif (services & {"skiBus", "hikingBus"}) and not (m & ~(64 | 2048)) and not p.get("lines"):
                    oe, conf, why = "check", 60, "nur touristische Ski-/Wanderbuslinien – Gültigkeit beim Verbund prüfen"
                elif (services & {"skiBus", "hikingBus"}) and st in ("T", "K"):
                    why = "Ski-/Wanderbusse in Tirol/Kärnten teils ausgenommen (Positivliste VVT / Kärntner Linien)"
                    conf = 80
                if (p["flags"] & 1) and not p.get("lines") and oe == "yes":
                    conf = 70
                    why = (why + "; " if why else "") + "kein Werktagsverkehr (Saison-/Bedarfshalt?)"
                reg = [dict(x) for x in C.KLIMATICKET_REGIONAL.get(st, [])]
                if st == "OÖ" and gname in C.OOE_KERNZONEN:
                    reg.insert(0, {"id": C.OOE_KERNZONEN[gname], "name": f"KlimaTicket OÖ Regional + {gname}",
                                   "note": "Kernzone: OÖ Regional allein gilt nicht im Stadtverkehr"})
                if st == "T" and gname == "Innsbruck":
                    reg.append({"id": "tirol-innsbruck", "name": "KlimaTicket Innsbruck"})
                city = C.KLIMATICKET_CITY.get((st, gname))
                if city and not any(r["name"] == city for r in reg):
                    reg.append({"id": "city-" + slug(city), "name": city})
                reg += ext.get(g, [])
                hint["reg"] = reg
            hint["oe"] = oe
            if why:
                hint["why"] = why
            return oe, conf, hint

        diff = 0
        for i, p in enumerate(P):
            tg = self.tags[i]
            # every piece of evidence
            types = set(tg.get("type", {}))
            services = set(tg.get("service", {}))
            has_bus = any(v.get("route") in ("bus", "trolleybus") for v in self.stop_routes.get(i, {}).values())
            oe, conf, hint = decide(i, types, services, has_bus)
            self.add(i, "klimaticket", oe, conf, hint, osm=True)
            # official evidence only
            pv = self.prov[i]
            types_o = {v for (k, v), sl in pv.items() if k == "type" and sl[0] is not None}
            services_o = {v for (k, v), sl in pv.items() if k == "service" and sl[0] is not None}
            has_bus_o = any(t and not RAIL_TOKENS.match(t) for t in (p.get("lines") or "").split(","))
            oe_o, conf_o, hint_o = decide(i, types_o, services_o, has_bus_o)
            self.add(i, "klimaticket", oe_o, conf_o, hint_o, osm=False, best=False)
            if (oe_o, hint_o.get("why")) != (oe, hint.get("why")):
                diff += 1
        self.stats["klimaticket_official_differs_from_full_evidence"] = diff

    # =========================================================================================
    def export(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        ski = self.ski_areas
        P = self.P
        # --- catalog -------------------------------------------------------------------------
        ski_cat = {}
        stop_ct = collections.Counter()
        for i in range(self.n):
            for sid, (c, ex) in self.tags[i].get("ski", {}).items():
                stop_ct[sid] += 1
                if ex.get("sector"):
                    stop_ct[ex["sector"]] += 1
            for sid in self.tags[i].get("skiAlliance", {}):
                stop_ct[sid] += 1
        for sid, s in ski.items():
            if s["kind"] != "alliance" and s["_geom"] is None and not stop_ct[sid]:
                continue
            if s["src"] == "osm" and not stop_ct[sid]:
                continue
            style = dict(s.get("style") or {})
            h = int(hashlib.sha1(sid.encode()).hexdigest(), 16)
            if not style:
                c, cd = C.SKI_PALETTE[h % len(C.SKI_PALETTE)]
                style = {"color": c, "colorDark": cd,
                         "glyph": "glacier" if s.get("glacier") else ("peaks2" if len(s.get("lifts", [])) >= 8 else "peaks1"),
                         "sf": "snowflake" if s.get("glacier") else "mountain.2.fill"}
            style["color"] = ensure_contrast(style["color"], "#FFFFFF", 4.5, darken=True)
            style["colorDark"] = ensure_contrast(style["colorDark"], "#000000", 4.5, darken=False)
            if "mono" not in style:
                words = [w for w in re.split(r"[\s\-–/·&()]+", s.get("short") or s["name"]) if w and w[0].isalpha()
                         and w.lower() not in ("am", "im", "an", "der", "die", "st.", "und", "bei")]
                style["mono"] = ("".join(w[0] for w in words[:3]) if len(words) > 1 else words[0][:3]).upper() if words else "SKI"
            states = set()
            for g in s.get("gkz", set()):
                states.add(STATE_BY_DIGIT[g // 10000])
            ent = {"name": s["name"], "kind": s["kind"], "src": s["src"], "style": style,
                   "stops": stop_ct[sid]}
            if s["kind"] == "alliance":   # E5: ski-pass groups are curator knowledge until checked with the operators
                ent["verified"] = sid in C.ALLIANCES_VERIFIED
            for k in ("short", "parent", "alliances", "note", "resorts", "geom_src"):
                if s.get(k):
                    ent[k] = s[k]
            if s.get("glacier"):
                ent["glacier"] = True
            if states:
                ent["states"] = sorted(states)
            if s.get("_geom") is not None:
                b = m_to_geo(s["_geom"]).bounds
                ent["bbox"] = [round(b[1], 4), round(b[0], 4), round(b[3], 4), round(b[2], 4)]
            if s.get("polys"):
                ent["osm"] = [a["osm"] for a in s["polys"]]
            if s.get("lifts"):
                ent["lifts"] = len(s["lifts"])
            ski_cat[sid] = ent
        legend = {
            "state": {"de": "Bundesland", "sf": "flag.fill", "group": "admin", "prio": 10},
            "bezirk": {"de": "Bezirk", "sf": "map", "group": "admin", "prio": 90},
            "wienBezirk": {"de": "Wiener Gemeindebezirk", "sf": "building.2", "group": "admin", "prio": 85},
            "ski": {"de": "Skigebiet", "sf": "figure.skiing.downhill", "group": "ski", "prio": 1},
            "skiAlliance": {"de": "Skiverbund / Skipass", "sf": "ticket", "group": "ski", "prio": 30},
            "glacierSki": {"de": "Gletscherskigebiet", "sf": "snowflake", "group": "ski", "prio": 25},
            "lift": {"de": "Bergbahn / Lift-Station", "sf": "cablecar.fill", "group": "ski", "prio": 5},
            "region": {"de": "Urlaubsregion", "sf": "mountain.2", "group": "region", "prio": 20},
            "landscape": {"de": "Landschaft / Viertel", "sf": "leaf", "group": "region", "prio": 60},
            "nationalPark": {"de": "Nationalpark", "sf": "tree.fill", "group": "region", "prio": 15},
            "glacier": {"de": "Gletscher in der Nähe", "sf": "snowflake.circle", "group": "nature", "prio": 40},
            "hut": {"de": "Hütte / Alm", "sf": "house.lodge.fill", "group": "nature", "prio": 50},
            "type": {"de": "Ortstyp", "group": "type", "prio": 3, "values": {
                "trainStation": {"de": "Bahnhof", "sf": "train.side.front.car"},
                "mainStation": {"de": "Hauptbahnhof", "sf": "building.columns.fill"},
                "longDistance": {"de": "Fernverkehr", "sf": "tram.fill"},
                "nightTrain": {"de": "Nachtzug", "sf": "moon.zzz.fill"},
                "sBahn": {"de": "S-Bahn", "sf": "s.circle.fill"},
                "uBahn": {"de": "U-Bahn", "sf": "u.circle.fill"},
                "tram": {"de": "Straßenbahn", "sf": "tram"},
                "privateRail": {"de": "Privat-/Lokalbahn", "sf": "lightrail"},
                "railReplacement": {"de": "Schienenersatzverkehr", "sf": "bus.doubledecker"},
                "busStation": {"de": "Busbahnhof", "sf": "bus.fill"},
                "ship": {"de": "Schiffsanlegestelle", "sf": "ferry.fill"},
                "cableCar": {"de": "Seilbahn (ÖV)", "sf": "cablecar.fill"},
                "onDemand": {"de": "Bedarfsverkehr", "sf": "phone.arrow.up.right"},
                "airport": {"de": "Flughafen", "sf": "airplane.departure"},
                "hospital": {"de": "Krankenhaus", "sf": "cross.case.fill"},
                "university": {"de": "Universität / Hochschule", "sf": "graduationcap.fill"},
                "mall": {"de": "Einkaufszentrum", "sf": "bag.fill"},
                "parkAndRide": {"de": "Park & Ride", "sf": "parkingsign.circle.fill"},
                "bikeAndRide": {"de": "Bike & Ride", "sf": "bicycle"},
            }},
            "railTransfer": {"de": "Umstieg zur Bahn", "sf": "arrow.triangle.swap", "group": "type", "prio": 35},
            "service": {"de": "Besondere Linien", "group": "service", "prio": 12, "values": {
                "nightBus": {"de": "Nachtbus", "sf": "moon.stars.fill"},
                "skiBus": {"de": "Skibus", "sf": "figure.skiing.downhill"},
                "hikingBus": {"de": "Wanderbus / Almbus", "sf": "figure.hiking"},
                "onDemand": {"de": "Rufbus / Anrufsammeltaxi", "sf": "phone.fill"},
                "seasonal": {"de": "Saisonlinie", "sf": "calendar.badge.clock"},
                "airportLink": {"de": "Direkt zum Flughafen", "sf": "airplane"},
            }},
            "wheelchair": {"de": "Barrierefreiheit (OSM)", "sf": "figure.roll", "group": "access", "prio": 8,
                           "values": {"yes": {"de": "barrierefrei"}, "limited": {"de": "teilweise barrierefrei"},
                                      "no": {"de": "nicht barrierefrei"}}},
            "klimaticket": {"de": "KlimaTicket-Hinweis", "sf": "checkmark.seal.fill", "group": "ticket", "prio": 4,
                            "values": {"yes": {"de": "KlimaTicket Ö gültig"}, "check": {"de": "Gültigkeit prüfen"},
                                       "no": {"de": "nicht im KlimaTicket"}, "border": {"de": "bis Grenzbahnhof"}}},
        }
        stops = {}
        prov_ct = collections.Counter()
        for i, p in enumerate(P):
            tl = []
            for (key, v), (off, osm) in self.prov[i].items():
                if key in ("bezirk", "wienBezirk"):
                    continue
                if off is not None:
                    tl.append([key, v, off[0], {**off[1], "osm": False}])
                    prov_ct[f"official:{key}"] += 1
                # the OSM record only where it adds something (no official record, or stronger evidence); the
                # KlimaTicket hint ships with official evidence only (see klimaticket())
                if osm is not None and key != "klimaticket" and (off is None or osm[0] > off[0]):
                    tl.append([key, v, osm[0], {**osm[1], "osm": True}])
                    prov_ct[f"osm:{key}"] += 1
            tl.sort(key=lambda r: (legend.get(r[0], {}).get("prio", 99), -r[2], r[0], r[1], r[3]["osm"]))
            rec = {"t": tl}
            if self.gkz[i]:
                rec["g"] = self.gkz[i]
                bz = self.tags[i].get("bezirk")
                if bz:
                    rec["b"] = next(iter(bz))
                wb = self.tags[i].get("wienBezirk")
                if wb:
                    rec["wb"] = int(next(iter(wb)))
            stops[p["id"]] = rec
        states = {k: v for k, v in C.STATES.items()}
        doc = {
            "version": 1,
            "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            "sources": {
                "places": "build/places/places.json (Haltestellen-Datensatz, scripts/build_places.py --stage base)",
                "osm": "© OpenStreetMap contributors, ODbL 1.0 (austria PBF, landuse=winter_sports, aerialway, "
                       "piste, route relations, amenity/shop/aeroway, boundary/place=region, national_park)",
                "gemeinden": "Statistik Austria, Gemeinden 2026-01-01 (CC BY 4.0)",
                "klimaticket": C.KT_SOURCE,
                "curated": "scripts/places_curated.py (ski areas, tourism regions, Landesfarben, Bezirke, operators)",
            },
            "legal": {
                "logos": "Keine offiziellen Logos/Wappen verwendet. Skigebiets- und Regionsnamen nur als Text "
                         "(nominative Nutzung). Farben/Glyphen = eigene Gestaltung.",
                "states": C.STATE_LEGAL,
                "attribution": "Ski-Areale, Lifte, Linienrelationen: © OpenStreetMap-Mitwirkende (ODbL). "
                               "Im App-Impressum nennen.",
            },
            "display": {"minConf": 70, "maxBadgesRow": 5,
                        "order": "legend.prio ascending, then conf descending; ski > lift > type > klimaticket",
                        "note": "Tags below minConf are evidence only (detail view / search boosts), not badges."},
            "legend": legend,
            "glyphs": C.GLYPHS,
            "states": states,
            "bezirke": C.BEZIRKE,
            "wienBezirke": {str(k): v for k, v in C.WIEN_BEZIRKE.items()},
            "skiAreas": ski_cat,
            "regions": self.region_catalog,
            "stops": stops,
        }
        self.stats["provenance"] = dict(sorted(prov_ct.items()))
        with open(os.path.join(out_dir, "tags.json"), "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        # osm lines
        ol = {}
        for j, sr in self.stop_routes.items():
            ol[P[j]["id"]] = sorted(
                ({k: v for k, v in x.items() if v not in (None, [], "")} for x in sr.values()),
                key=lambda x: (x.get("route") != "train", x.get("ref") or "~", x.get("name") or ""))
        with open(os.path.join(out_dir, "osm_lines.json"), "w", encoding="utf-8") as f:
            json.dump({"source": "© OpenStreetMap contributors, ODbL 1.0", "stops": ol}, f, ensure_ascii=False,
                      separators=(",", ":"))
        # geojson
        feats = []
        for sid, ent in ski_cat.items():
            s = ski[sid]
            g = s.get("_geom")
            if g is None:
                continue
            gg = m_to_geo(g.simplify(40, preserve_topology=True))
            gg = shapely.set_precision(gg, 1e-5)
            feats.append({"type": "Feature", "properties": {"id": sid, "name": ent["name"], "kind": ent["kind"],
                                                            "src": ent["src"], "color": ent["style"]["color"]},
                          "geometry": json.loads(shapely.to_geojson(gg))})
        with open(os.path.join(out_dir, "ski_areas.geojson"), "w", encoding="utf-8") as f:
            json.dump({"type": "FeatureCollection", "attribution": "© OpenStreetMap contributors, ODbL 1.0",
                       "features": feats}, f, ensure_ascii=False, separators=(",", ":"))
        # ---- compact app file: dictionary-encoded, conf >= 60, defaults dropped ----------------
        keys, vals = [], []
        kidx, vidx = {}, {}

        def ki(k):
            if k not in kidx:
                kidx[k] = len(keys)
                keys.append(k)
            return kidx[k]

        def vi(v):
            if v not in vidx:
                vidx[v] = len(vals)
                vals.append(v)
            return vidx[v]
        app_stops = {}
        for i, p in enumerate(P):
            flat = []
            for key, vv in self.tags[i].items():
                if key in ("state", "bezirk", "wienBezirk"):
                    continue
                for v, (conf, ex) in vv.items():
                    if conf < 60:
                        continue
                    if key == "klimaticket" and v == "yes" and not ex.get("why"):
                        continue
                    label = v
                    if key == "lift":
                        label = v + ("|" + ex.get("role", "")) if ex.get("role") else v
                    flat += [ki(key), vi(label), conf]
            rec = [self.gkz[i] or 0] + flat
            app_stops[p["id"]] = rec
        app = {"version": 1, "generated": doc["generated"], "format":
               "stops[id] = [GKZ, k0, v0, c0, k1, v1, c1, ...] with keys[k], vals[v], conf 0..100; "
               "Bezirk = GKZ//100 (Wien: 900, Gemeindebezirk = GKZ//100 % 100). klimaticket 'yes' without note is "
               "the default and omitted; KlimaTicket product list per state in states/klimaticketRegional. "
               "lift values are 'name|role'.",
               "keys": keys, "vals": vals, "stops": app_stops,
               "states": doc["states"], "bezirke": doc["bezirke"], "skiAreas": doc["skiAreas"],
               "regions": doc["regions"], "legend": doc["legend"], "display": doc["display"],
               "klimaticketRegional": C.KLIMATICKET_REGIONAL, "legal": doc["legal"], "sources": doc["sources"]}
        with open(os.path.join(out_dir, "tags_app.json"), "w", encoding="utf-8") as f:
            json.dump(app, f, ensure_ascii=False, separators=(",", ":"))
        return doc


def _lum(hexc):
    h = hexc.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def ensure_contrast(c, against, target, darken=True):
    h = c.lstrip("#")
    rgb = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    for _ in range(40):
        cur = "#%02X%02X%02X" % tuple(rgb)
        if contrast(cur, against) >= target:
            return cur
        rgb = [int(v * 0.93) for v in rgb] if darken else [int(v + (255 - v) * 0.08) for v in rgb]
    return "#%02X%02X%02X" % tuple(rgb)


def contrast(a, b):
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return round((hi + 0.05) / (lo + 0.05), 2)


# =============================================================================================
# spot checks (40) - (stop id, [(key, value-or-regex, min_conf)], reason)
# =============================================================================================
# spot checks (51) live in data/places_spot_checks.json: [{"id", "expect": [[key, value-or-regex, min_conf, {extra}?]],
# "reason"}]; scripts/check_places_v2.py runs the same checks through the shipped v2 files (AT-D5).


def run_spot(tg, spot_file):
    res = []
    spots = json.load(open(spot_file, encoding="utf-8")) if os.path.exists(spot_file) else []
    allspots = spots
    for s in allspots:
        sid = s["id"]
        if sid not in tg.idx:
            res.append({**s, "ok": False, "fail": ["stop id not found"]})
            continue
        i = tg.idx[sid]
        fails = []
        for exp in s["expect"]:
            key, val, minc = exp[:3]
            want_ex = exp[3] if len(exp) > 3 else {}
            neg = key.startswith("!")
            k = key.lstrip("!")
            if k == "kt_reg":
                kt = tg.tags[i].get("klimaticket", {})
                regs = {r["id"] for _, (c, ex) in kt.items() for r in ex.get("reg", [])}
                ok = (val in regs) != neg
                if not ok:
                    fails.append(f"{key}={val} (got {sorted(regs)})")
                continue
            vals = tg.tags[i].get(k, {})
            if val == "*":
                found = [(v, c, ex) for v, (c, ex) in vals.items()]
            elif val.startswith("(") or any(ch in val for ch in "^$*[]|"):
                found = [(v, c, ex) for v, (c, ex) in vals.items() if re.search(val, v)]
            else:
                found = [(v, c, ex) for v, (c, ex) in vals.items() if v == val]
            found = [f for f in found if all(f[2].get(a) == b for a, b in want_ex.items())]
            ok = (not found) if neg else any(c >= minc for _, c, _ in found)
            if not ok:
                fails.append(f"{key}={val}{want_ex or ''}>={minc} (got {k}: "
                             f"{sorted((v, c) for v, (c, _) in vals.items())[:6]})")
        res.append({"id": sid, "name": tg.P[i]["name"], "ok": not fails, "fail": fails, "reason": s["reason"],
                    "tags": [[k, v, c] for k, vv in tg.tags[i].items() for v, (c, _) in vv.items()]})
    return res


def reexec_deterministic():
    """Set iteration order – and with it some tie-breaks – depends on the str hash seed. Re-run once with
    PYTHONHASHSEED=0 so that two builds from the same inputs give identical files (ENRICH_SPEC §1.2, AT-D1).
    The child keeps the isolation of `python3 -I`: clean environment, no user site, script dir not on sys.path."""
    if sys.flags.hash_randomization:
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "PYTHONHASHSEED": "0", "PYTHONUTF8": "1"}
        if os.environ.get("SOURCE_DATE_EPOCH"):
            env["SOURCE_DATE_EPOCH"] = os.environ["SOURCE_DATE_EPOCH"]
        os.execve(sys.executable, [sys.executable, "-s", "-P", os.path.abspath(sys.argv[0])] + sys.argv[1:], env)


def main():
    reexec_deterministic()
    ap = argparse.ArgumentParser()
    ap.add_argument("--places", default=DEF_PLACES)
    ap.add_argument("--osm", default=DEF_OSM)
    ap.add_argument("--gem", default=DEF_GEM)
    ap.add_argument("--out", default=DEF_OUT)
    ap.add_argument("--spot", default=DEF_SPOT)
    a = ap.parse_args()
    places = json.load(open(a.places, encoding="utf-8"))
    log("places", len(places))
    osm = json.load(open(a.osm, encoding="utf-8"))
    log("osm loaded")
    gem = load_gemeinden(a.gem)
    log("gemeinden", len(gem[1]))
    tg = Tagger(places, osm, gem)
    tg.admin()
    tg.ski()
    tg.lift_stations()
    tg.place_types()
    tg.routes()
    tg.regions()
    tg.wheelchair()
    tg.klimaticket()
    doc = tg.export(a.out)
    log("exported")
    # ---- report -------------------------------------------------------------------------------
    per_tag = collections.Counter()
    per_val = collections.defaultdict(collections.Counter)
    per_state = collections.defaultdict(collections.Counter)
    conf_hist = collections.defaultdict(collections.Counter)
    for i, p in enumerate(places):
        for k, vals in tg.tags[i].items():
            per_tag[k] += 1
            per_state[k][p["state"]] += 1
            for v, (c, _) in vals.items():
                per_val[k][v] += 1
                conf_hist[k][(c // 10) * 10] += 1
    spot = run_spot(tg, a.spot)
    rep = {
        "generated": doc["generated"],
        "stops": len(places),
        "stops_with_tag": dict(per_tag.most_common()),
        "values": {k: dict(v.most_common(60 if k in ("ski", "region", "skiAlliance", "landscape") else 40))
                   for k, v in per_val.items() if k not in ("bezirk", "wienBezirk", "railTransfer", "hut")},
        "by_state": {k: dict(v) for k, v in per_state.items()},
        "confidence_histogram": {k: dict(sorted(v.items())) for k, v in conf_hist.items()},
        "ski_catalog": {"curated_areas": sum(1 for v in doc["skiAreas"].values() if v["src"] == "curated" and v["kind"] == "area"),
                        "curated_sectors": sum(1 for v in doc["skiAreas"].values() if v["kind"] == "sector"),
                        "alliances": sum(1 for v in doc["skiAreas"].values() if v["kind"] == "alliance"),
                        "osm_auto_areas": sum(1 for v in doc["skiAreas"].values() if v["src"] == "osm"),
                        "stops_with_any_ski": per_tag.get("ski", 0)},
        "stats": dict(tg.stats),
        "contrast": {
            "states": {k: {"light": contrast(v["badge"]["bg"], v["badge"]["fg"]),
                           "dark": contrast(v["badge"]["bgDark"], v["badge"]["fgDark"])}
                       for k, v in C.STATES.items()},
            "ski_white_text_light_min": min(contrast(v["style"]["color"], "#FFFFFF")
                                            for v in doc["skiAreas"].values()),
            "ski_dark_on_black_min": min(contrast(v["style"]["colorDark"], "#000000")
                                         for v in doc["skiAreas"].values()),
        },
        "warnings": tg.warn,
        "spot_checks": {"passed": sum(1 for s in spot if s["ok"]), "total": len(spot), "results": spot},
    }
    with open(os.path.join(a.out, "tags_report.json"), "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=1)
    log(f"spot checks {rep['spot_checks']['passed']}/{rep['spot_checks']['total']}; warnings {len(tg.warn)}")
    for s in spot:
        if not s["ok"]:
            log("SPOT FAIL", s["id"], s.get("name"), s["fail"])


if __name__ == "__main__":
    main()
