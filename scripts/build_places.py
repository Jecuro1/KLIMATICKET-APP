#!/usr/bin/env python3
"""KlimaBilanz – offline place database (all Austrian public-transport stops + localities).

Reproducible, stdlib-only pipeline. Input = files downloaded into DL (scripts/fetch_places_sources.sh),
output = OUT/places.bin + OUT/localities.bin (app resources) and debug/side files in DEBUG_OUT.
Sources, licences and the yearly update procedure: docs/DATA_SOURCES.md.

    sh scripts/fetch_places_sources.sh build/places-dl          # once per timetable year (≈ 1.3 GB)
    python3 -I scripts/build_places.py --dl build/places-dl --out App/Resources --debug-out build/places \
        [--mvo path/to/haltestellen.csv]

The output is deterministic for identical inputs (no timestamps or hash-order dependence in the .bin files);
places_report.json carries the input checksums and the per-Bundesland/mode counts.

Sources (all optional except ÖV-GK *or* MVO; missing optional inputs only reduce quality):
  oevgk/   ÖV-Güteklassen 2025_revised, 01_Haltestellenkategorien_20251022 (shp+dbf, EPSG:3035)
           = the complete Mobilitätsverbünde stop list (WFS 10/2025) + weekday departures
  mvo      data.mobilitaetsverbuende.at "Haltestellen (CSV)" (needs free login) – preferred when given
  osm/     osm_pt_austria.json (Overpass JSON; extract_osm_places.py or the Overpass query in it)
  oebb_gtfs/  ÖBB-PV Soll-Fahrplan GTFS 2026 (stops/routes/trips/stop_times/calendar*)
  wl/x/    Wiener Linien GTFS stops.txt
  stmk/x/  Land Steiermark "Haltestellen des Verkehrsverbundes Steiermark" (shp+dbf, WGS84)
  statat/x/ Statistik Austria Gemeinden 2026-01-01 (shp+dbf, EPSG:31287)
  --stations / --stations-meta  the app's previous station list App/Resources/stations.json (legacy ids that
           existing trips reference – never regenerated from places) + data/stations_meta.json (EVA numbers)
  scotty_fixtures/  saved HAFAS LocMatch/LocGeoPos responses (optional: extId hints)

places.bin format (little endian, version 1) – write_bin()/read_bin() are the reference:
  header 64 B: 0 magic "KBPL" | 4 u16 version=1 | 6 u16 flags=0 | 8 u32 nRecords | 12 u32 nGemeinden
               16 8×u32 offset/length of: records, strings, gemeinden, extras | 48 u32 nStopRecords | pad
  records nRecords × 28 B; first nStopRecords are stops sorted by weight desc, then localities:
     i32 lat_e6, i32 lon_e6, u32 str_off (UTF-8, NUL-terminated: id \x1f name [\x1f alias]*),
     u32 extra_off (0xFFFFFFFF = none; offset into extras), u16 modes (ÖBB HAFAS pCls bit values),
     u16 weight (stops: departures on Wed 22.10.2025, capped 65535; localities: population),
     u16 gemeinde (index into gemeinden, 0xFFFF none),
     u8 state (0 X/abroad, 1 B, 2 K, 3 NÖ, 4 OÖ, 5 S, 6 ST, 7 T, 8 V, 9 W), u8 kind (0 stop, 1 locality),
     u8 flags (bit0 no departure on the reference weekday, bit1 not in the Verbund stop list (GTFS/OGD only),
               bit2 abroad, bit3 has legacy app id, bit4 has EVA, bit5 rail replacement served),
     u8 place class (localities: 1 city 2 town 3 village 4 suburb 5 hamlet 6 neighbourhood 7 quarter
               8 isolated_dwelling, 0 unknown; stops: 0), u16 0
  strings: concatenated NUL-terminated UTF-8 (offset 0 = "")
  gemeinden: nGemeinden × (u32 GKZ Statistik Austria, u32 str_off)
  extras: at extra_off: u8 n, then n × (u8 tag, u32 value):
     1 EVA = ÖBB HAFAS extId of the rail station (ÖBB-Infrastruktur VzV)   2 HAFAS extId (only --use-scotty-hints)
     3 legacy app station id (str_off; one entry per stations.json id mapped here, own id included)
     4 main stop record index (localities)
     5 lines (str_off, comma separated, ≤ 120 chars)      6 UIC code (OSM uic_ref / HAFAS globalIdL "U"; hint)
     Aliases: official alternative names (ÖBB GTFS / Wiener Linien / previous app names / curated codes such as
     "VIE"); display names are cleaned (arrow markers "--->" removed).
     7 main stop id (str_off; localities.bin of --osm-policy separate)
  --osm-policy separate (default) writes stops to places.bin (no OSM content) and localities to
  localities.bin (same format, nStopRecords = 0, ODbL); merge writes one places.bin (ODbL as a whole).
"""
import argparse
import collections
import csv
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import re
import struct
import sys
import unicodedata
import zlib

# =============================================================================================
# geometry
# =============================================================================================
R_EARTH = 6371008.8


def hav_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * R_EARTH * math.asin(min(1.0, math.sqrt(a)))


class LAEA:
    """EPSG:3035 inverse (EPSG Guidance Note 7-2 §1.3.12)."""
    a = 6378137.0
    f = 1 / 298.257222101
    e2 = 2 * f - f * f
    e = math.sqrt(e2)
    lat0, lon0, FE, FN = math.radians(52.0), math.radians(10.0), 4321000.0, 3210000.0

    @classmethod
    def _q(cls, phi):
        s, e, e2 = math.sin(phi), cls.e, cls.e2
        return (1 - e2) * (s / (1 - e2 * s * s) - (1 / (2 * e)) * math.log((1 - e * s) / (1 + e * s)))

    @classmethod
    def inverse(cls, E, N):
        e2 = cls.e2
        qP, q0 = cls._q(math.pi / 2), cls._q(cls.lat0)
        beta0 = math.asin(q0 / qP)
        Rq = cls.a * math.sqrt(qP / 2)
        D = cls.a * (math.cos(cls.lat0) / math.sqrt(1 - e2 * math.sin(cls.lat0) ** 2)) / (Rq * math.cos(beta0))
        x, y = E - cls.FE, N - cls.FN
        rho = math.sqrt((x / D) ** 2 + (D * y) ** 2)
        if rho == 0:
            return math.degrees(cls.lat0), math.degrees(cls.lon0)
        C = 2 * math.asin(rho / (2 * Rq))
        bp = math.asin(math.cos(C) * math.sin(beta0) + (D * y * math.sin(C) * math.cos(beta0)) / rho)
        lon = cls.lon0 + math.atan2(x * math.sin(C), D * rho * math.cos(beta0) * math.cos(C)
                                    - D * D * y * math.sin(beta0) * math.sin(C))
        phi = (bp + (e2 / 3 + 31 * e2 ** 2 / 180 + 517 * e2 ** 3 / 5040) * math.sin(2 * bp)
               + (23 * e2 ** 2 / 360 + 251 * e2 ** 3 / 3780) * math.sin(4 * bp)
               + (761 * e2 ** 3 / 45360) * math.sin(6 * bp))
        return math.degrees(phi), math.degrees(lon)


class MGILambert:
    """WGS84 lat/lon -> EPSG:31287 (MGI / Austria Lambert) incl. 7-parameter datum shift."""
    # TOWGS84 of EPSG:1618 as given in the Statistik Austria .prj (position vector convention)
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
        # inverse Helmert (WGS84 -> MGI), small-angle position-vector form
        s = 1 + cls.DS * 1e-6
        rx, ry, rz = (math.radians(v / 3600) for v in (cls.RX, cls.RY, cls.RZ))
        x0, y0, z0 = x - cls.TX, y - cls.TY, z - cls.TZ
        # R^-1 ≈ R^T for small rotations; position vector: R = [[1,-rz,ry],[rz,1,-rx],[-ry,rx,1]]
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


def read_shp(path):
    """Yields (shape_type, payload) per record; points -> (x, y); polygons -> list of rings."""
    import array
    with open(path, "rb") as fh:
        b = fh.read()
    off = 100
    while off + 8 <= len(b):
        _, clen = struct.unpack(">ii", b[off:off + 8])
        rec = b[off + 8: off + 8 + clen * 2]
        off += 8 + clen * 2
        st = struct.unpack("<i", rec[:4])[0]
        if st == 0:
            yield 0, None
        elif st in (1, 11, 21):
            yield 1, struct.unpack("<dd", rec[4:20])
        elif st in (5, 15, 25):
            nparts, npts = struct.unpack("<ii", rec[36:44])
            parts = list(struct.unpack(f"<{nparts}i", rec[44:44 + 4 * nparts]))
            pts = array.array("d")
            pts.frombytes(rec[44 + 4 * nparts: 44 + 4 * nparts + 16 * npts])
            if sys.byteorder != "little":
                pts.byteswap()
            rings = []
            for i, p in enumerate(parts):
                q = parts[i + 1] if i + 1 < nparts else npts
                rings.append(pts[2 * p: 2 * q])
            yield 5, rings
        else:
            yield st, None


def read_dbf(path, enc="utf-8"):
    with open(path, "rb") as fh:
        hdr = fh.read(32)
        n, hlen, rlen = struct.unpack("<IHH", hdr[4:12])
        fields = []
        while True:
            d = fh.read(32)
            if not d or d[0] == 0x0D:
                break
            fields.append((d[:11].split(b"\0")[0].decode("ascii"), chr(d[11]), d[16]))
        fh.seek(hlen)
        for _ in range(n):
            r = fh.read(rlen)
            if not r or r[:1] == b"\x1a":
                break
            out, pos = {}, 1
            for name, _t, ln in fields:
                out[name] = r[pos:pos + ln].decode(enc, "replace").strip()
                pos += ln
            out["_deleted"] = r[:1] == b"*"
            yield out


def dp_simplify(flat, tol):
    """Douglas-Peucker on a flat [x0,y0,x1,y1,...] ring; returns flat list."""
    n = len(flat) // 2
    if n <= 8:
        return list(flat)
    keep = bytearray(n)
    keep[0] = keep[n - 1] = 1
    stack = [(0, n - 1)]
    tol2 = tol * tol
    while stack:
        i, j = stack.pop()
        x1, y1, x2, y2 = flat[2 * i], flat[2 * i + 1], flat[2 * j], flat[2 * j + 1]
        dx, dy = x2 - x1, y2 - y1
        L2 = dx * dx + dy * dy
        best, bk = -1.0, -1
        for k in range(i + 1, j):
            px, py = flat[2 * k] - x1, flat[2 * k + 1] - y1
            if L2 == 0:
                d2 = px * px + py * py
            else:
                c = (px * dy - py * dx)
                d2 = c * c / L2
            if d2 > best:
                best, bk = d2, k
        if best > tol2 and bk > 0:
            keep[bk] = 1
            stack.append((i, bk))
            stack.append((bk, j))
    out = []
    for k in range(n):
        if keep[k]:
            out.append(flat[2 * k])
            out.append(flat[2 * k + 1])
    return out


def ring_contains(flat, x, y):
    inside = False
    n = len(flat) // 2
    j = n - 1
    for i in range(n):
        xi, yi, xj, yj = flat[2 * i], flat[2 * i + 1], flat[2 * j], flat[2 * j + 1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


# =============================================================================================
# names
# =============================================================================================
def fold(s):
    s = s.replace("ß", "ss").replace("ẞ", "ss")
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


# Query/name normalisation – token based (no regex) so the Swift PlaceIndex can apply the identical rules
# cheaply to ~60k names at load time. Exported verbatim to places_rules.json. Steps:
#   1 lower-case, ß→ss, strip diacritics (NFKD)      2 literal replacements (PRE)
#   3 split on every non [a-z0-9] character           4 bigram rules (BIGRAMS) on consecutive tokens
#   5 unigram map (UNIGRAMS)                          6 suffix rules (SUFFIXES, first match)
#   7 ae→a, oe→o, ue→u inside each token              8 join with single spaces
PRE = [("str.", "strasse ")]
BIGRAMS = [("i", "t", "in tirol"), ("i", "d", "in der"), ("a", "d", "an der"), ("a", "a", "am arlberg")]
UNIGRAMS = {"hauptbahnhof": "hbf", "hbhf": "hbf", "bahnhof": "bf", "bhf": "bf", "bahnhst": "bf",
            "bahnhaltestelle": "bf", "sankt": "st", "str": "strasse", "wr": "wiener", "ibk": "innsbruck",
            "vlbg": "vorarlberg", "bgld": "burgenland", "stmk": "steiermark", "ktn": "karnten", "sbg": "salzburg",
            "b": "bei"}
SUFFIXES = [("hauptbahnhof", "hbf"), ("bahnhof", "bf"), ("bahnhst", "bf")]
VOWELS = [("ae", "a"), ("oe", "o"), ("ue", "u")]
# query tokens that may be dropped when the strict match fails (region qualifiers, HAFAS suffixes);
# OPTIONAL_AFTER: the token following one of these is optional too ("Nußdorf b.Lienz" → "lienz")
OPTIONAL_TOKENS = ["vorarlberg", "burgenland", "steiermark", "karnten", "tirol", "salzburg", "niederosterreich",
                   "oberosterreich", "no", "oo", "in", "im", "am", "an", "bei", "der", "u", "s", "bf",
                   "ort", "ortsmitte", "zentrum"]
OPTIONAL_AFTER = ["bei"]


def norm(s):
    if not s:
        return ""
    s = fold(s.lower())
    for a_, b_ in PRE:
        s = s.replace(a_, b_)
    t = re.sub(r"[^a-z0-9]+", " ", s).split()
    out = []
    i = 0
    while i < len(t):
        if i + 1 < len(t):
            hit = next((r for x, y, r in BIGRAMS if t[i] == x and t[i + 1] == y), None)
            if hit:
                out.extend(hit.split())
                i += 2
                continue
        out.append(t[i])
        i += 1
    res = []
    for w in out:
        w = UNIGRAMS.get(w, w)
        for suf, rp in SUFFIXES:
            if w.endswith(suf) and len(w) > len(suf):
                w = w[: -len(suf)] + rp
                break
        for x, y in VOWELS:
            w = w.replace(x, y)
        res.extend(w.split())
    return " ".join(res)


STOPW = {"bf", "hbf", "hst", "haltestelle", "bahnhst", "station", "bahnhof", "u", "s", "b", "a", "d", "i",
         "an", "der", "die", "dem", "den", "im", "in", "am", "ob", "bei", "und", "zum", "zur", "abzw", "gh",
         "lokalbahn", "bahn"}


def toks(s):
    allt = norm(s).split()
    t = [x for x in allt if x not in STOPW]
    return t or allt


def name_sim(a, b):
    ta, tb = set(toks(a)), set(toks(b))
    if not ta or not tb:
        return 0.0
    inter = len(ta & tb)
    for x in ta - tb:
        for y in tb - ta:
            if len(x) >= 4 and len(y) >= 4 and (x.startswith(y) or y.startswith(x)):
                inter += 0.8
                break
    return inter / max(len(ta), len(tb))


def contain_sim(a, b):
    ta, tb = set(toks(a)), set(toks(b))
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / min(len(ta), len(tb))


# =============================================================================================
# modes – same bit values as ÖBB HAFAS pCls (docs/OEBB_LIVE.md §A3.6) so offline and live agree
# =============================================================================================
M_HIGHSPEED, M_SEV, M_IC, M_NIGHT, M_REGIONAL, M_SBAHN, M_BUS, M_SHIP = 1, 2, 4, 8, 16, 32, 64, 128
M_SUBWAY, M_TRAM, M_COACH, M_ONDEMAND_CABLE, M_WESTBAHN = 256, 512, 1024, 2048, 4096
M_RAIL = M_HIGHSPEED | M_IC | M_NIGHT | M_REGIONAL | M_SBAHN | M_WESTBAHN

CAT_BITS = {"RJX": M_HIGHSPEED, "RJ": M_HIGHSPEED, "ICE": M_HIGHSPEED, "TGV": M_HIGHSPEED, "FR": M_HIGHSPEED,
            "EC": M_IC, "IC": M_IC, "D": M_IC, "EN": M_NIGHT, "NJ": M_NIGHT, "IR": M_IC, "ECE": M_IC,
            "WB": M_WESTBAHN, "REX": M_REGIONAL, "R": M_REGIONAL, "CJX": M_REGIONAL, "RE": M_REGIONAL,
            "RB": M_REGIONAL, "S": M_SBAHN, "SB": M_SBAHN, "ER": M_REGIONAL, "Os": M_REGIONAL,
            "Sp": M_REGIONAL, "Ex": M_IC, "RR": M_REGIONAL, "BUS": M_BUS, "SEV": M_SEV, "RGJ": M_REGIONAL,
            "LKB": M_REGIONAL, "STB": M_REGIONAL, "ZB": M_REGIONAL, "MEX": M_REGIONAL, "ATZ": M_IC}

STATE_CODES = ["X", "B", "K", "NÖ", "OÖ", "S", "ST", "T", "V", "W"]
STATE_BY_LAND = {41: 1, 42: 2, 43: 3, 44: 4, 45: 5, 46: 6, 47: 7, 48: 8, 49: 9}
TRAM_CITIES = ("wien", "graz", "linz", "innsbruck", "gmunden", "baden", "wiener neudorf", "guntramsdorf",
               "traiskirchen", "vosendorf", "biedermannsdorf", "leopoldsdorf", "fulpmes", "telfes", "mutters",
               "natters", "kreith", "stubaital", "rum", "hall in tirol")


CITY_TRAMS = {  # tram line names per city (stop name prefix) – everything else on these stops is bus
    "wien": {"1", "2", "5", "6", "9", "10", "11", "18", "25", "26", "27", "30", "31", "33", "37", "38", "40", "41",
             "42", "43", "44", "46", "49", "52", "60", "62", "71", "D", "O", "WLB", "BB"},
    "graz": {"1", "3", "4", "5", "6", "7", "16", "17"},
    "linz": {"1", "2", "3", "4", "50"},
    "innsbruck": {"1", "2", "3", "5", "6", "STB"},
    "gmunden": {"174", "TT", "Traunseetram"},
}
RAIL_TOKENS = {"Regionalzug": M_REGIONAL, "LEX": M_REGIONAL, "CAT": M_REGIONAL, "RX": M_REGIONAL,
               "ZB1": M_REGIONAL, "NPB": M_REGIONAL, "WHB": M_REGIONAL, "LKB": M_REGIONAL, "GKB": M_REGIONAL}
CABLE_RX = re.compile(r"bergstation|talstation|mittelstation|seilbahn|gondel|sessel|lift\b|standseilbahn|"
                      r"zahnradbahn|kabinenbahn|bahn bergst|gletscherbahn|alm\b")
SHIP_RX = re.compile(r"schiff|anlegestelle|fahre|schiffstation|landungs|steg\b|bootsanl|schifflande|hafen")


def city_of(name):
    n = norm(name)
    for c in CITY_TRAMS:
        if n == c or n.startswith(c + " "):
            return c
    return None


def modes_from_lines(lines, vkat, name):
    """Mode bits from the ÖV-GK/MVO line list + the 'highest mode' class (VKAT_Hst)."""
    bits = 0
    city = city_of(name)
    trams = CITY_TRAMS.get(city, set())
    for raw in [x.strip() for x in (lines or "").split(",") if x.strip()]:
        tok = raw.split(" ")[0]
        if tok in trams or raw in trams:
            bits |= M_TRAM
        elif tok in ("D", "O") and city == "wien":
            bits |= M_TRAM
        elif tok in CAT_BITS:
            bits |= CAT_BITS[tok]
        elif tok in RAIL_TOKENS:
            bits |= RAIL_TOKENS[tok]
        elif re.fullmatch(r"U\d", tok):
            bits |= M_SUBWAY
        elif re.fullmatch(r"S\d{1,3}[A-Z]?", tok):
            bits |= M_SBAHN
        elif tok.startswith("SV") or tok.startswith("SEV") or raw == "BUS SEV":
            bits |= M_SEV
        elif re.fullmatch(r"(R|REX|CJX)\d+", tok):
            bits |= M_REGIONAL
        elif tok in ("MÜHXI", "AST", "RUF") or tok.startswith("AST"):
            bits |= M_ONDEMAND_CABLE
        else:
            bits |= M_BUS  # numbers, 4A, N60, X30, B01, VAL 3, SB 4, ...
    v = (vkat or "")[:1]
    n = norm(name)
    railish = re.search(r"\b(bf|hbf|lokalbahn|bahnhst|s bahn)\b|bf$", n)
    if v == "1":
        if not bits & M_RAIL:
            bits |= M_REGIONAL
    elif v == "2":
        if not bits & (M_RAIL | M_SUBWAY):
            bits |= M_REGIONAL if railish else M_BUS
    elif v == "3":
        if not bits & (M_TRAM | M_BUS):
            bits |= M_TRAM if city else M_BUS  # Metrobus / O-Bus (Salzburg)
    elif v == "4":
        bits |= M_BUS
    elif vkat and vkat.startswith("andere"):
        if SHIP_RX.search(n):
            bits |= M_SHIP
        elif CABLE_RX.search(n):
            bits |= M_ONDEMAND_CABLE
        else:
            bits |= M_ONDEMAND_CABLE if not lines else 0
    return bits


def default_modes(name):
    n = norm(name)
    if SHIP_RX.search(n):
        return M_SHIP
    if CABLE_RX.search(n):
        return M_ONDEMAND_CABLE
    return M_BUS


def osm_mode_bits(t):
    bits = 0
    if t.get("bus") == "yes" or t.get("highway") == "bus_stop" or t.get("trolleybus") == "yes" \
            or t.get("amenity") == "bus_station" or t.get("coach") == "yes":
        bits |= M_BUS
    if t.get("share_taxi") == "yes":
        bits |= M_BUS
    if t.get("tram") == "yes" or t.get("railway") == "tram_stop":
        bits |= M_TRAM
    if t.get("subway") == "yes" or t.get("station") == "subway":
        bits |= M_SUBWAY
    if t.get("light_rail") == "yes" or t.get("station") == "light_rail":
        bits |= M_REGIONAL
    if t.get("train") == "yes" or (t.get("railway") in ("station", "halt") and t.get("station") not in (
            "subway", "funicular", "light_rail", "monorail") and t.get("tram") != "yes"):
        bits |= M_REGIONAL
    if t.get("ferry") == "yes" or t.get("amenity") == "ferry_terminal":
        bits |= M_SHIP
    if t.get("aerialway") == "station" or t.get("funicular") == "yes" or t.get("station") == "funicular":
        bits |= M_ONDEMAND_CABLE
    return bits


LIFE = ("disused:", "abandoned:", "razed:", "construction:", "proposed:", "was:", "removed:",
        "demolished:", "planned:")


def osm_alive(t):
    if t.get("disused") == "yes" or t.get("abandoned") == "yes" or t.get("construction") == "yes":
        return False
    if any(k.startswith(LIFE) for k in t) and not (t.get("public_transport") or t.get("highway") == "bus_stop"
                                                     or t.get("railway") in ("station", "halt", "tram_stop")):
        return False
    if t.get("railway:historic") or t.get("historic") in ("railway_station", "railway"):
        return False
    if t.get("access") in ("private", "no"):
        return False
    return True


# =============================================================================================
# grid index
# =============================================================================================
class Grid:
    def __init__(self, cell_deg=0.01):
        self.c = cell_deg
        self.g = collections.defaultdict(list)

    def key(self, lat, lon):
        return int(math.floor(lat / self.c)), int(math.floor(lon / self.c))

    def add(self, lat, lon, item):
        self.g[self.key(lat, lon)].append((lat, lon, item))

    def near(self, lat, lon, radius_m):
        dlat = radius_m / 111195.0
        dlon = dlat / max(0.2, math.cos(math.radians(lat)))
        k0 = self.key(lat - dlat, lon - dlon)
        k1 = self.key(lat + dlat, lon + dlon)
        out = []
        for i in range(k0[0], k1[0] + 1):
            for j in range(k0[1], k1[1] + 1):
                for la, lo, it in self.g.get((i, j), ()):
                    d = hav_m(lat, lon, la, lo)
                    if d <= radius_m:
                        out.append((d, it))
        out.sort(key=lambda x: x[0])
        return out


# =============================================================================================
# loaders
# =============================================================================================
def p(*parts):
    return os.path.join(*parts)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def ifopt_parent(s):
    if not s:
        return None
    s = s.strip()
    if s.startswith("P"):
        s = s[1:]
    m = re.match(r"^([a-z]{2}):(\d+):(\d+)", s)
    if not m:
        return None
    return f"{m.group(1)}:{int(m.group(2))}:{int(m.group(3))}"


def load_oevgk(base):
    pts = [pl for st, pl in read_shp(base + ".shp")]
    out = {}
    for (r, xy) in zip(read_dbf(base + ".dbf"), pts):
        if r["_deleted"] or not xy:
            continue
        num = int(float(r["St_Nummer"]))
        s = str(num)
        land, stop = int(s[:2]), int(s[2:7])
        sid = f"at:{land}:{stop}"
        lat, lon = LAEA.inverse(*xy)
        out[sid] = {"id": sid, "name": r["St_Name"].strip(), "lat": lat, "lon": lon, "land": land,
                    "dep": int(r["Anz_Abf"] or 0), "vkat": r["VKAT_Hst"], "lines": r["Linien"],
                    "hstkat": r["HstKat"], "sev": "Schienenersatz" in (r["Hinweis"] or ""),
                    "src": {"oevgk"}, "aliases": set(), "modes": 0, "extids": {}}
    return out


def load_mvo(path):
    """data.mobilitaetsverbuende.at 'Haltestellen (CSV)', stop level (hst_*). Tolerant reader:
    separator ; or , ; coordinates hst_x/hst_y in WGS84 (lon/lat) or geom WKT 'POINT(x y)'."""
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "cp1252"):
        try:
            txt = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    first = txt.split("\n", 1)[0]
    delim = ";" if first.count(";") > first.count(",") else ","
    out = {}
    for r in csv.DictReader(txt.splitlines(), delimiter=delim):
        r = {k.strip().lower(): (v or "").strip() for k, v in r.items() if k}
        gid = ifopt_parent(r.get("hst_globid") or r.get("globale id") or "")
        if not gid:
            continue
        x, y = r.get("hst_x"), r.get("hst_y")
        lat = lon = None
        try:
            x, y = float(x.replace(",", ".")), float(y.replace(",", "."))
            lon, lat = (x, y) if abs(x) < 40 else (None, None)
        except (TypeError, ValueError, AttributeError):
            pass
        if lat is None:
            m = re.search(r"POINT\s*\(\s*([\d.]+)\s+([\d.]+)", r.get("geom", ""))
            if m:
                a, b = float(m.group(1)), float(m.group(2))
                if a > 1000:  # projected – assume EPSG:3035 like the ÖV-GK export
                    lat, lon = LAEA.inverse(a, b)
                else:
                    lon, lat = a, b
        if lat is None:
            continue
        vm = r.get("umst_agg_vm", "")
        bits = 0
        # 1 Eisenbahn 2 S-Bahn 3 U-Bahn 4 Stadtbahn 5 Strassenbahn 6 Flughafen/Schnellbus 7 Regionalbus
        # 8 Stadtbus 9 Seil-/Zahnradbahn 10 Schiff 11 AST/Rufbus 12 Sonstiges 13 Autoreisezug
        mp = {0: M_REGIONAL, 1: M_SBAHN, 2: M_SUBWAY, 3: M_TRAM, 4: M_TRAM, 5: M_BUS, 6: M_BUS, 7: M_BUS,
              8: M_ONDEMAND_CABLE, 9: M_SHIP, 10: M_ONDEMAND_CABLE, 11: 0, 12: 0}
        for i, ch in enumerate(vm):
            if ch == "1":
                bits |= mp.get(i, 0)
        land = int(gid.split(":")[1])
        out[gid] = {"id": gid, "name": r.get("hst_name", ""), "lat": lat, "lon": lon, "land": land,
                    "gem_name": r.get("hst_gem_name"), "mvo_modes": bits, "lines": r.get("linien_agg", "")}
    return out


def load_oebb_gtfs(g):
    """Parent stations of the ÖBB GTFS with weekday departures and category bits."""
    def rd(name):
        return csv.DictReader(open(p(g, name), encoding="utf-8-sig"))
    stops = {s["stop_id"]: s for s in rd("stops.txt")}

    def key(sid):
        return ifopt_parent(sid) or sid
    groups = collections.defaultdict(lambda: {"parent": None, "plats": []})
    for sid, s in stops.items():
        k = key(sid)
        if s["location_type"] == "1":
            groups[k]["parent"] = s
        elif s["location_type"] in ("", "0"):
            groups[k]["plats"].append(s)
    routes = {r["route_id"]: r for r in rd("routes.txt")}
    # reference weekday: Wednesday 2026-10-21 (normal school day, no holiday)
    ref = dt.date(2026, 10, 21)
    ds = ref.strftime("%Y%m%d")
    dow = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"][ref.weekday()]
    active = set()
    for c in rd("calendar.txt"):
        if c["start_date"] <= ds <= c["end_date"] and c[dow] == "1":
            active.add(c["service_id"])
    for c in rd("calendar_dates.txt"):
        if c["date"] == ds:
            (active.add if c["exception_type"] == "1" else active.discard)(c["service_id"])
    trips = {}
    for t in rd("trips.txt"):
        r = routes.get(t["route_id"], {})
        cat = (t.get("trip_short_name") or r.get("route_short_name") or "").split(" ")[0]
        trips[t["trip_id"]] = (t["service_id"] in active, cat, r.get("route_type"))
    dep = collections.Counter()
    cats = collections.defaultdict(set)
    for st in rd("stop_times.txt"):
        tr = trips.get(st["trip_id"])
        if not tr:
            continue
        k = key(st["stop_id"])
        cats[k].add(tr[1] if tr[2] != "3" else "BUS")
        if tr[0] and st.get("pickup_type") != "1":
            dep[k] += 1
    out = {}
    for k, gr in groups.items():
        pnt = gr["parent"]
        plats = [s for s in gr["plats"] if s.get("platform_code")] or gr["plats"]
        if pnt:
            lat, lon, name = float(pnt["stop_lat"]), float(pnt["stop_lon"]), pnt["stop_name"]
        elif plats:
            lat = sum(float(s["stop_lat"]) for s in plats) / len(plats)
            lon = sum(float(s["stop_lon"]) for s in plats) / len(plats)
            name = collections.Counter(s["stop_name"] for s in plats).most_common(1)[0][0]
        else:
            continue
        if k not in cats:
            continue
        bits = 0
        for c in cats[k]:
            bits |= CAT_BITS.get(c, M_REGIONAL if c != "BUS" else M_BUS)
        out[k] = {"id": k, "name": name, "lat": lat, "lon": lon, "dep": dep.get(k, 0), "modes": bits,
                  "cats": sorted(c for c in cats[k] if c)}
    return out


def load_wl(path):
    out = {}
    if not os.path.exists(path):
        return out
    for s in csv.DictReader(open(path, encoding="utf-8-sig")):
        k = ifopt_parent(s["stop_id"])
        if not k:
            continue
        o = out.setdefault(k, {"names": collections.Counter(), "pts": []})
        o["names"][s["stop_name"]] += 1
        o["pts"].append((float(s["stop_lat"]), float(s["stop_lon"])))
    return out


def load_stmk(base):
    out = {}
    if not os.path.exists(base + ".dbf"):
        return out
    pts = [pl for st, pl in read_shp(base + ".shp")]
    for r, xy in zip(read_dbf(base + ".dbf"), pts):
        if r["_deleted"] or not xy:
            continue
        k = f"at:46:{int(float(r['HNR']))}"
        out[k] = {"name": r["HNAME_LANG"], "short": r["HNAME_KURZ"], "lon": xy[0], "lat": xy[1],
                  "mofr": int(float(r["MoFr_S"] or 0)), "sa": int(float(r["Sa_Schule"] or 0)),
                  "so": int(float(r["SoFei"] or 0)), "lines": r["LINIE"]}
    return out


def load_gemeinden(base, tol_m=12.0):
    if not os.path.exists(base + ".dbf"):
        return [], None
    recs = list(read_dbf(base + ".dbf"))
    polys = []
    for r, (st, rings) in zip(recs, read_shp(base + ".shp")):
        if st != 5 or not rings:
            continue
        simp = [dp_simplify(ring, tol_m) for ring in rings]
        xs = [v for ring in simp for v in ring[0::2]]
        ys = [v for ring in simp for v in ring[1::2]]
        polys.append({"gkz": int(r["g_id"]), "name": r["g_name"], "rings": simp,
                      "bbox": (min(xs), min(ys), max(xs), max(ys))})
    cell = 5000.0
    idx = collections.defaultdict(list)
    for i, pg in enumerate(polys):
        x0, y0, x1, y1 = pg["bbox"]
        for gx in range(int(x0 // cell), int(x1 // cell) + 1):
            for gy in range(int(y0 // cell), int(y1 // cell) + 1):
                idx[(gx, gy)].append(i)

    def locate(lat, lon):
        x, y = MGILambert.forward(lat, lon)
        for i in idx.get((int(x // cell), int(y // cell)), ()):
            pg = polys[i]
            x0, y0, x1, y1 = pg["bbox"]
            if not (x0 <= x <= x1 and y0 <= y <= y1):
                continue
            inside = False
            for ring in pg["rings"]:
                if ring_contains(ring, x, y):
                    inside = not inside
            if inside:
                return pg
        return None
    return polys, locate


def load_osm(path):
    if not os.path.exists(path):
        return [], {}
    d = json.load(open(path, encoding="utf-8"))
    els, rels = [], {}
    for e in d.get("elements", []):
        t = e.get("tags") or {}
        if e["type"] == "relation" and t.get("public_transport") == "stop_area":
            rels[e["id"]] = e
            continue
        if "lat" in e:
            lat, lon = e["lat"], e["lon"]
        elif "center" in e:
            lat, lon = e["center"]["lat"], e["center"]["lon"]
        else:
            continue
        els.append({"k": f"{e['type'][0]}{e['id']}", "lat": lat, "lon": lon, "tags": t})
    return els, rels


def load_scotty(dirpath):
    """All HAFAS locations (type S) seen in saved responses: extId, name, coords, pCls, meta."""
    out = {}
    if not os.path.isdir(dirpath):
        return out

    def walk(o):
        if isinstance(o, dict):
            if "extId" in o and "name" in o and o.get("type") == "S" and "crd" in o:
                yield o
            for v in o.values():
                yield from walk(v)
        elif isinstance(o, list):
            for v in o:
                yield from walk(v)
    for fn in sorted(os.listdir(dirpath)):
        if not fn.endswith(".json"):
            continue
        try:
            d = json.load(open(p(dirpath, fn), encoding="utf-8"))
        except ValueError:
            continue
        for L in walk(d):
            ext = str(L["extId"])
            out[ext] = {"extId": ext, "name": L["name"], "lat": L["crd"]["y"] / 1e6, "lon": L["crd"]["x"] / 1e6,
                        "pCls": L.get("pCls", 0), "meta": bool(L.get("meta")),
                        "uic": next((g["id"] for g in L.get("globalIdL", []) if g.get("type") == "U"), None)}
    return out


# =============================================================================================
# build
# =============================================================================================
def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # repository root
    ap.add_argument("--dl", default=p(root, "build", "places-dl"), help="downloads (scripts/fetch_places_sources.sh)")
    ap.add_argument("--out", default=p(root, "App", "Resources"), help="directory for places.bin / localities.bin")
    ap.add_argument("--debug-out", default=p(root, "build", "places"),
                    help="directory for places.json, localities.json, legacy_map.json, places_report.json, "
                         "ATTRIBUTION.txt, osm_only_clusters.tsv")
    ap.add_argument("--stations", default=p(root, "App", "Resources", "stations.json"))
    ap.add_argument("--stations-meta", default=p(root, "data", "stations_meta.json"))
    ap.add_argument("--mvo", default=None, help="MVO Haltestellen CSV (stop level), optional")
    ap.add_argument("--oevgk", default=None)
    ap.add_argument("--no-localities", action="store_true")
    ap.add_argument("--osm-policy", choices=("separate", "merge"), default="separate",
                    help="separate (default): places.bin holds no OSM-derived content (CC BY / MVO licence only); "
                         "OSM localities go to localities.bin (ODbL). merge: one file, OSM aliases/modes merged "
                         "into stops – then the whole places.bin is an ODbL derivative database")
    ap.add_argument("--use-scotty-hints", action="store_true",
                    help="copy HAFAS extIds/names from saved Scotty responses into the bundle (off: ÖBB HAFAS "
                         "data is not open data; fixtures are then only used for the coverage report)")
    ap.add_argument("--osm-only", choices=("none", "nonbus", "all"), default="none",
                    help="add OSM-only stop clusters (default none: they are written to osm_only_clusters.tsv "
                         "as a gap list; 'nonbus' adds rail/tram/metro/ferry ones)")
    a = ap.parse_args()
    DL = a.dl
    os.makedirs(a.out, exist_ok=True)
    DBG = a.debug_out or a.out
    os.makedirs(DBG, exist_ok=True)
    report = {"generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "inputs": {}}

    def stamp(name, path):
        if os.path.exists(path):
            h = hashlib.sha256()
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
            report["inputs"][name] = {"path": os.path.basename(path), "bytes": os.path.getsize(path),
                                      "sha256": h.hexdigest()[:16]}

    # ---------------------------------------------------------------- base: Verbund stop list
    gk_base = a.oevgk or p(DL, "oevgk/x/01_Haltestellenkategorien/Haltestellenkategorien_20251022_revised")
    places = {}
    if os.path.exists(gk_base + ".dbf"):
        stamp("oevgk_dbf", gk_base + ".dbf")
        places = load_oevgk(gk_base)
        log("ÖV-GK stops", len(places))
    if a.mvo:
        stamp("mvo_csv", a.mvo)
        mvo = load_mvo(a.mvo)
        log("MVO stops", len(mvo))
        for k, m in mvo.items():
            pl = places.get(k)
            if pl is None:
                places[k] = {"id": k, "name": m["name"], "lat": m["lat"], "lon": m["lon"], "land": m["land"],
                             "dep": 0, "vkat": "", "lines": m["lines"], "hstkat": "", "sev": False,
                             "src": {"mvo"}, "aliases": set(), "modes": m["mvo_modes"], "extids": {}}
            else:
                if m["name"] and norm(m["name"]) != norm(pl["name"]):
                    pl["aliases"].add(pl["name"])
                    pl["name"] = m["name"]
                pl["lat"], pl["lon"] = m["lat"], m["lon"]
                pl["modes"] |= m["mvo_modes"]
                pl["src"].add("mvo")
            places[k]["gem_name"] = m.get("gem_name")
    if not places:
        sys.exit("no base stop list (ÖV-GK or --mvo) found")
    for pl in places.values():
        pl["modes"] |= modes_from_lines(pl["lines"], pl["vkat"], pl["name"])
        if pl["sev"]:
            pl["modes"] |= M_SEV
    n_base = len(places)

    # ---------------------------------------------------------------- ÖBB GTFS (rail, foreign rail)
    gtfs_dir = p(DL, "oebb_gtfs")
    oebb = {}
    if os.path.exists(p(gtfs_dir, "stops.txt")):
        stamp("oebb_gtfs_stops", p(gtfs_dir, "stops.txt"))
        oebb = load_oebb_gtfs(gtfs_dir)
        log("ÖBB GTFS stations", len(oebb))
    st_gtfs = collections.Counter()
    TARIFF_POINT = re.compile(r"\bTP\b|Tarifpunkt|Staatsgrenze|\(Gr\)$")
    for k, g in oebb.items():
        if TARIFF_POINT.search(g["name"]):
            st_gtfs["tariff_point_skipped"] += 1
            continue
        pl = places.get(k)
        if pl:
            st_gtfs["joined_by_id"] += 1
            pl["modes"] = (pl["modes"] & ~M_REGIONAL) | g["modes"] if g["modes"] & M_RAIL else pl["modes"] | g["modes"]
            pl["src"].add("oebb_gtfs")
            if norm(g["name"]) != norm(pl["name"]):
                pl["aliases"].add(g["name"])
            pl["gtfs_dep"] = g["dep"]
            continue
        if k.startswith("at:"):
            st_gtfs["at_missing_in_base"] += 1
        else:
            st_gtfs["foreign"] += 1
        places[k] = {"id": k, "name": g["name"], "lat": g["lat"], "lon": g["lon"],
                     "land": int(k.split(":")[1]) if k.startswith("at:") else 0, "dep": g["dep"], "vkat": "",
                     "lines": ",".join(g["cats"]), "hstkat": "", "sev": False, "src": {"oebb_gtfs"},
                     "aliases": set(), "modes": g["modes"], "extids": {}, "foreign": not k.startswith("at:")}
    report["oebb_gtfs"] = dict(st_gtfs)

    # ---------------------------------------------------------------- Wiener Linien + Steiermark
    wl = load_wl(p(DL, "wl/x/stops.txt"))
    if wl:
        stamp("wl_stops", p(DL, "wl/x/stops.txt"))
    st_wl = collections.Counter()
    for k, w in wl.items():
        pl = places.get(k)
        nm = w["names"].most_common(1)[0][0]
        if pl:
            st_wl["joined"] += 1
            pl["src"].add("wl_gtfs")
            # WL names omit "Wien " – keep as alias ("Stephansplatz")
            if norm(nm) != norm(pl["name"]):
                pl["aliases"].add(nm)
        else:
            st_wl["missing_in_base_added"] += 1
            lat = sum(x[0] for x in w["pts"]) / len(w["pts"])
            lon = sum(x[1] for x in w["pts"]) / len(w["pts"])
            places[k] = {"id": k, "name": nm if nm.startswith("Wien") else "Wien " + nm, "lat": lat, "lon": lon,
                         "land": 49, "dep": 0, "vkat": "", "lines": "", "hstkat": "", "sev": False,
                         "src": {"wl_gtfs"}, "aliases": {nm}, "modes": 0, "extids": {}}
    report["wiener_linien"] = dict(st_wl)

    stmk = load_stmk(p(DL, "stmk/x/Haltestellen"))
    grid0 = Grid(0.01)
    for k0, pl0 in places.items():
        grid0.add(pl0["lat"], pl0["lon"], k0)
    if stmk:
        stamp("stmk_dbf", p(DL, "stmk/x/Haltestellen.dbf"))
    st_st = collections.Counter()
    for k, s in stmk.items():
        pl = places.get(k)
        if not pl:
            if s["mofr"] + s["sa"] + s["so"] == 0:
                st_st["missing_in_base_unserved_skipped"] += 1
                continue
            near = [d for d, kk in grid0.near(s["lat"], s["lon"], 150) if name_sim(s["name"], places[kk]["name"]) >= 0.6]
            if near:
                st_st["missing_in_base_renumbered_skipped"] += 1
                continue
            st_st["missing_in_base_added"] += 1
            places[k] = {"id": k, "name": s["name"], "lat": s["lat"], "lon": s["lon"], "land": 46, "dep": 0,
                         "dep_fallback": s["mofr"], "vkat": "", "lines": "", "hstkat": "", "sev": False,
                         "src": {"stmk"}, "aliases": set(), "modes": M_BUS, "extids": {}}
            continue
        st_st["joined"] += 1
        pl["src"].add("stmk")
        if pl["dep"] == 0 and s["mofr"]:
            pl["dep_fallback"] = s["mofr"]
        d = hav_m(pl["lat"], pl["lon"], s["lat"], s["lon"])
        if d > 500:
            st_st["coord_diff_gt_500m"] += 1
    report["steiermark"] = dict(st_st)

    # ---------------------------------------------------------------- OSM
    osm_path = p(DL, "osm/osm_pt_austria.json")
    els, rels = load_osm(osm_path)
    stamp("osm_json", osm_path)
    log("OSM elements", len(els), "stop_areas", len(rels))
    grid = Grid(0.01)
    for k, pl in places.items():
        grid.add(pl["lat"], pl["lon"], k)
    stops_osm = [e for e in els if e["tags"].get("place") is None]
    place_nodes = [e for e in els if e["tags"].get("place")]
    st_osm = collections.Counter()
    unmatched = []
    osm_link = collections.defaultdict(list)
    for e in stops_osm:
        t = e["tags"]
        if not osm_alive(t):
            st_osm["dead"] += 1
            continue
        nm = t.get("name") or t.get("official_name")
        k = ifopt_parent(t.get("ref:IFOPT"))
        if k and k in places:
            st_osm["by_ifopt"] += 1
            osm_link[k].append(e)
            continue
        if not nm:
            st_osm["noname"] += 1
            continue
        best = None
        for d, cand in grid.near(e["lat"], e["lon"], 400):
            pl = places[cand]
            s = max(name_sim(nm, pl["name"]), contain_sim(nm, pl["name"]) * 0.95)
            limit = 400 if osm_mode_bits(t) & (M_RAIL | M_SHIP | M_ONDEMAND_CABLE) else 250
            if d <= limit and s >= 0.6:
                sc = s - d / 2000
                if best is None or sc > best[0]:
                    best = (sc, cand)
        if best:
            st_osm["by_name_geo"] += 1
            osm_link[best[1]].append(e)
        else:
            st_osm["unmatched"] += 1
            unmatched.append(e)
    report["osm_join"] = dict(st_osm)
    for k, lst in osm_link.items():
        pl = places[k]
        pl["osm"] = len(lst)
        if a.osm_policy == "separate":
            continue  # OSM only used for matching statistics / gap list
        pl["src"].add("osm")
        ob = 0
        for e in lst:
            t = e["tags"]
            ob |= osm_mode_bits(t)
            for key in ("alt_name", "short_name", "official_name", "loc_name", "uic_name"):
                for v in (t.get(key) or "").split(";"):
                    v = v.strip()
                    if v and norm(v) != norm(pl["name"]) and len(v) <= 60:
                        pl["aliases"].add(v)
            if t.get("uic_ref") and re.fullmatch(r"\d{7}", t["uic_ref"]) and t.get("railway") in ("station", "halt"):
                # OSM uic_ref = UIC code (ÖBB HAFAS globalIdL type U), NOT the HAFAS extId/EVA
                pl["extids"].setdefault("uic", int(t["uic_ref"]))
        # OSM adds modes (never removes Verbund modes); rail only when linked by IFOPT or the stop is rail-ish
        by_id = any(ifopt_parent(e["tags"].get("ref:IFOPT")) == k for e in lst)
        railish = pl["modes"] & M_RAIL or re.search(r"\b(bf|hbf|bahnhst|lokalbahn|s bahn)\b|bf$", norm(pl["name"]))
        pl["modes"] |= ob if (by_id or railish) else ob & ~M_RAIL
        pl["osm"] = len(lst)

    # OSM-only clusters (same normalised name within 300 m)
    clusters = []
    cg = Grid(0.01)
    for e in unmatched:
        t = e["tags"]
        nm = t.get("name") or t.get("official_name")
        key = norm(nm)
        hit = None
        for d, ci in cg.near(e["lat"], e["lon"], 300):
            if clusters[ci]["key"] == key:
                hit = ci
                break
        if hit is None:
            clusters.append({"key": key, "name": nm, "els": [e]})
            cg.add(e["lat"], e["lon"], len(clusters) - 1)
        else:
            clusters[hit]["els"].append(e)
    osm_only_stats = collections.Counter()
    osm_added = 0
    for c in clusters:
        bits = 0
        for e in c["els"]:
            bits |= osm_mode_bits(e["tags"])
        c["modes"] = bits
        lat = sum(e["lat"] for e in c["els"]) / len(c["els"])
        lon = sum(e["lon"] for e in c["els"]) / len(c["els"])
        c["lat"], c["lon"] = lat, lon
        cls = ("rail" if bits & M_RAIL else "tram" if bits & M_TRAM else "subway" if bits & M_SUBWAY else
               "ship" if bits & M_SHIP else "cable" if bits & M_ONDEMAND_CABLE else "bus" if bits & M_BUS else "other")
        osm_only_stats[cls] += 1
        c["cls"] = cls
        add = a.osm_only == "all" or (a.osm_only == "nonbus" and cls in ("rail", "tram", "subway", "ship"))
        if add:
            k = f"osm:{c['els'][0]['k']}"
            places[k] = {"id": k, "name": c["name"], "lat": lat, "lon": lon, "land": 0, "dep": 0, "vkat": "",
                         "lines": "", "hstkat": "", "sev": False, "src": {"osm"}, "aliases": set(), "modes": bits,
                         "extids": {}, "osm_only": True}
            osm_added += 1
    report["osm_only_clusters"] = dict(osm_only_stats)
    report["osm_only_added"] = osm_added
    with open(p(DBG, "osm_only_clusters.tsv"), "w", encoding="utf-8") as fh:
        fh.write("class\tname\tlat\tlon\tn\tosm\ttags\n")
        for c in sorted(clusters, key=lambda c: (c["cls"], c["name"])):
            t = c["els"][0]["tags"]
            fh.write(f"{c['cls']}\t{c['name']}\t{c['lat']:.6f}\t{c['lon']:.6f}\t{len(c['els'])}\t{c['els'][0]['k']}\t"
                     + ",".join(f"{k}={v}" for k, v in t.items() if k in ("public_transport", "highway", "railway",
                                                                             "aerialway", "amenity", "network",
                                                                             "operator", "bus"))[:200] + "\n")

    # ---------------------------------------------------------------- Gemeinde / Bundesland
    polys, locate = load_gemeinden(p(DL, "statat/x/STATISTIK_AUSTRIA_GEM_20260101"))
    if polys:
        stamp("gemeinden_shp", p(DL, "statat/x/STATISTIK_AUSTRIA_GEM_20260101.shp"))
    log("Gemeinden", len(polys))
    gem_index = {}
    gem_list = []
    st_pip = collections.Counter()
    for k, pl in places.items():
        pg = locate(pl["lat"], pl["lon"]) if locate else None
        if pg:
            if pg["gkz"] not in gem_index:
                gem_index[pg["gkz"]] = len(gem_list)
                gem_list.append((pg["gkz"], pg["name"]))
            pl["gem"] = gem_index[pg["gkz"]]
            pl["state"] = pg["gkz"] // 10000
            if pl.get("land") and STATE_BY_LAND.get(pl["land"]) != pl["state"]:
                st_pip["state_differs_from_ifopt_prefix"] += 1
            st_pip["in_austria"] += 1
        else:
            pl["gem"] = None
            pl["state"] = 0
            pl["foreign"] = True
            st_pip["outside_austria"] += 1
    report["pip"] = dict(st_pip)

    # ---------------------------------------------------------------- app legacy ids + EVA
    app_st = json.load(open(a.stations, encoding="utf-8"))
    stamp("app_stations", a.stations)
    meta_path = a.stations_meta
    meta = json.load(open(meta_path, encoding="utf-8"))["stations"] if os.path.exists(meta_path) else {}
    legacy = {}
    st_leg = collections.Counter()
    grid2 = Grid(0.01)
    for k, pl in places.items():
        grid2.add(pl["lat"], pl["lon"], k)
    for s in app_st:
        sid = s["id"]
        m = meta.get(sid, {})
        target = None
        how = None
        cand = ifopt_parent(sid) if sid.startswith("at:") else None
        if sid.startswith("wl:6020"):
            cand = f"at:49:{int(sid[7:])}"
        if m.get("dhid"):
            cand = cand or ifopt_parent(m["dhid"])
        if cand and cand in places and hav_m(places[cand]["lat"], places[cand]["lon"], s["lat"], s["lon"]) < 1500:
            target, how = cand, "id"
        if target is None:
            best = None
            for d, k in grid2.near(s["lat"], s["lon"], 600):
                pl = places[k]
                sim = max([name_sim(x, pl["name"]) for x in [s["name"]] + list(s.get("aliases") or [])]
                          + [contain_sim(s["name"], pl["name"]) * 0.95])
                railish = bool(pl["modes"] & M_RAIL)
                want_rail = s["kind"] == "rail"
                sc = sim - d / 1500 + (0.25 if railish == want_rail else 0) + min(pl["dep"], 2000) / 20000
                if sim >= 0.5 and (best is None or sc > best[0]):
                    best = (sc, k, d)
            if best:
                target, how = best[1], "name+geo"
        if target is None:
            # keep as its own entry (foreign stations, hubs without a Verbund stop)
            target, how = sid, "kept"
            places[sid] = {"id": sid, "name": s["name"], "lat": s["lat"], "lon": s["lon"], "land": 0,
                           "dep": 0, "vkat": "", "lines": "", "hstkat": "", "sev": False, "src": {"app"},
                           "aliases": set(s.get("aliases") or []), "modes": M_REGIONAL if s["kind"] == "rail" else M_SUBWAY,
                           "extids": {}, "foreign": s["state"] == "X", "gem": None,
                           "state": STATE_CODES.index(s["state"]) if s["state"] in STATE_CODES else 0}
        st_leg[how] += 1
        legacy[sid] = target
        pl = places[target]
        pl.setdefault("legacy", []).append(sid)
        for al in [s["name"]] + list(s.get("aliases") or []):
            if norm(al) != norm(pl["name"]) and not re.fullmatch(r"U\d|S\d+", al):
                pl["aliases"].add(al)
        pl["modes"] |= {"rail": M_REGIONAL, "metro": M_SUBWAY, "tram_hub": M_TRAM}.get(s["kind"], 0) \
            if not pl["modes"] & (M_RAIL | M_SUBWAY | M_TRAM) else 0
        if m.get("eva") and s["kind"] == "rail":
            pl["extids"].setdefault("eva", int(m["eva"]))
        elif sid.startswith("uic:") and s["kind"] == "rail":
            pl["extids"].setdefault("uic", int(sid[4:]))
        pl["importance_legacy"] = max(pl.get("importance_legacy", 0), s.get("importance", 0))
    report["legacy_mapping"] = dict(st_leg)

    # ---------------------------------------------------------------- Scotty fixture extIds
    scotty = load_scotty(p(DL, "scotty_fixtures")) if a.use_scotty_hints else {}
    st_sc = collections.Counter()
    for ext, L in scotty.items():
        if L["meta"]:
            st_sc["meta_skipped"] += 1
            continue
        best = None
        for d, k in grid2.near(L["lat"], L["lon"], 300):
            pl = places[k]
            sim = max(name_sim(L["name"], pl["name"]), contain_sim(L["name"], pl["name"]) * 0.9)
            if sim >= 0.6:
                sc = sim - d / 600
                if best is None or sc > best[0]:
                    best = (sc, k)
        if best:
            pl = places[best[1]]
            if L["uic"]:
                pl["extids"].setdefault("eva", int(ext))
                pl["extids"].setdefault("uic", int(L["uic"]))
            elif "(" not in L["name"]:
                pl["extids"].setdefault("hafas", int(ext))
            short = re.sub(r"\s*\(.*?\)\s*$", "", L["name"])
            if norm(short) != norm(pl["name"]):
                pl["aliases"].add(short)
            st_sc["matched"] += 1
        else:
            st_sc["unmatched"] += 1
    report["scotty_fixture_extids"] = dict(st_sc)

    # ---------------------------------------------------------------- localities (OSM place nodes)
    locs = []
    if not a.no_localities:
        stop_prefix = collections.defaultdict(list)
        for k, pl in places.items():
            tk = norm(pl["name"]).split(" ")
            for n in (1, 2, 3):
                if len(tk) >= n:
                    stop_prefix[" ".join(tk[:n])].append(k)
        for e in place_nodes:
            t = e["tags"]
            nm = t.get("name")
            if not nm or t.get("place") in ("isolated_dwelling", "locality"):
                continue
            pg = locate(e["lat"], e["lon"]) if locate else None
            if not pg:
                continue
            # main stop: most-departures stop within 2.5 km whose name starts with the locality name,
            # else nearest stop within 1.5 km
            key = norm(nm)
            best = None
            for k in stop_prefix.get(key, ()):
                pl = places[k]
                d = hav_m(e["lat"], e["lon"], pl["lat"], pl["lon"])
                if d <= 2500:
                    sc = math.log1p(pl["dep"] + pl.get("gtfs_dep", 0) * 2) - d / 2500
                    if best is None or sc > best[0]:
                        best = (sc, k)
            if best is None:
                nb = grid.near(e["lat"], e["lon"], 1500)
                if nb:
                    best = (0, nb[0][1])
            if best is None:
                continue
            if pg["gkz"] not in gem_index:
                gem_index[pg["gkz"]] = len(gem_list)
                gem_list.append((pg["gkz"], pg["name"]))
            locs.append({"id": f"osm:n{e['k'][1:]}" if e["k"].startswith("n") else f"osm:{e['k']}",
                         "name": nm, "lat": e["lat"], "lon": e["lon"], "place": t.get("place"),
                         "main": best[1], "gem": gem_index[pg["gkz"]], "state": pg["gkz"] // 10000,
                         "pop": int(t["population"]) if (t.get("population") or "").isdigit() else 0})
        # drop localities whose name equals a stop name prefix AND whose main stop already starts with it
        # (they add nothing to search) – keep only places that are also useful as a "Ort"
        report["localities"] = {"osm_place_nodes": len(place_nodes), "kept": len(locs),
                                "by_type": dict(collections.Counter(l["place"] for l in locs))}

    # ---------------------------------------------------------------- weights + finalize
    st_def = collections.Counter()
    for pl in places.values():
        if not pl["modes"]:
            pl["modes"] = default_modes(pl["name"])
            st_def[pl["modes"]] += 1
    report["modes_defaulted"] = {str(k): v for k, v in st_def.items()}
    final = []
    for k, pl in places.items():
        w = pl["dep"]
        if not w:
            w = pl.get("gtfs_dep", 0) or pl.get("dep_fallback", 0)
        pl["weight"] = min(65535, int(w))
        flags = 0
        if pl["dep"] == 0 and not pl.get("gtfs_dep"):
            flags |= 1
        if "oevgk" not in pl["src"] and "mvo" not in pl["src"]:
            flags |= 2
        if pl.get("foreign") or pl.get("state", 0) == 0:
            flags |= 4
        if pl.get("legacy"):
            flags |= 8
        if pl["extids"].get("eva"):
            flags |= 16
        if pl.get("sev"):
            flags |= 32
        pl["flags"] = flags
        final.append(pl)
    # display-name hygiene: "Amstetten ---> Fa Avenarius" → "Amstetten Fa Avenarius" (98 Verbund names)
    st_names = collections.Counter()
    for pl in final:
        clean = clean_name(pl["name"])
        if clean != pl["name"]:
            st_names["arrow_markers_removed"] += 1
            pl["name"] = clean
        pl["aliases"] = {clean_name(x) for x in pl["aliases"]}
    report["names"] = dict(st_names)
    # aliases: dedupe by normalized form, drop ones equal to name, cap 4; curated aliases always kept
    for pl in final:
        seen = {norm(pl["name"])}
        al = []
        for x in sorted(pl["aliases"], key=lambda s: (len(s), s)):
            nx = norm(x)
            if nx and nx not in seen and len(x) <= 60:
                seen.add(nx)
                al.append(x)
        al = al[:4]
        for x in CURATED_ALIASES.get(pl["id"], ()):
            if x not in al and x != pl["name"]:
                al.append(x)
        pl["alias_list"] = al

    final.sort(key=lambda pl: (-(pl["weight"]), pl["name"]))
    report["counts"] = summarize(final, locs, n_base)
    if a.osm_policy == "merge":
        write_bin(p(a.out, "places.bin"), final, locs, gem_list)
    else:
        write_bin(p(a.out, "places.bin"), final, [], gem_list)
        if locs:
            write_bin(p(a.out, "localities.bin"), [], locs, gem_list, main_as_id=True)
    write_debug(DBG, final, locs, gem_list, legacy, ATTRIBUTION + "\n" + ATTRIBUTION_OSM[a.osm_policy])
    with open(p(DBG, "places_rules.json"), "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "steps": ["lowercase", "ß→ss", "strip diacritics (NFKD)", "pre", "split non-[a-z0-9]",
                                            "bigrams", "unigrams", "suffixes", "vowels", "join ' '"],
                   "pre": PRE, "bigrams": BIGRAMS, "unigrams": UNIGRAMS, "suffixes": SUFFIXES, "vowels": VOWELS,
                   "optional_tokens": OPTIONAL_TOKENS, "optional_after": OPTIONAL_AFTER,
                   "modes": {"highspeed": M_HIGHSPEED, "railReplacement": M_SEV, "intercity": M_IC, "night": M_NIGHT,
                             "regional": M_REGIONAL, "suburban": M_SBAHN, "bus": M_BUS, "ship": M_SHIP,
                             "subway": M_SUBWAY, "tram": M_TRAM, "coach": M_COACH, "onDemandCable": M_ONDEMAND_CABLE,
                             "privateRail": M_WESTBAHN},
                   "states": STATE_CODES}, fh, ensure_ascii=False, indent=1)
    # round-trip self-test of the binary format (read_bin is the reference for the Swift PlaceDataset reader)
    chk, n_chk = read_bin(p(a.out, "places.bin"))
    assert n_chk == len(final) and len(chk) == len(final) + (len(locs) if a.osm_policy == "merge" else 0)
    assert all(c["id"] == pl["id"] and c["name"] == pl["name"] and c["aliases"] == pl["alias_list"]
               for c, pl in zip(chk, final)), "places.bin round trip failed"
    if locs and a.osm_policy == "separate":
        lchk, _ = read_bin(p(a.out, "localities.bin"))
        assert [c["id"] for c in lchk] == [lc["id"] for lc in locs], "localities.bin round trip failed"
    report["size"] = {}
    for fn in ("places.bin", "localities.bin"):
        if os.path.exists(p(a.out, fn)) and (fn == "places.bin" or a.osm_policy == "separate"):
            rb = open(p(a.out, fn), "rb").read()
            report["size"][fn] = {"bytes": len(rb), "gzip -9": len(gzip.compress(rb, 9))}
    report["attribution"] = ATTRIBUTION + "\n" + ATTRIBUTION_OSM[a.osm_policy]
    with open(p(DBG, "places_report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
    log(json.dumps(report["counts"], ensure_ascii=False)[:2000])
    log(json.dumps(report["size"]))


ARROW = re.compile(r"\s*-+>\s*")


def clean_name(s):
    return re.sub(r"\s{2,}", " ", ARROW.sub(" ", s)).strip()


# Curated search aliases (codes people type, colloquial names) – keyed by stop id, appended after the cap.
CURATED_ALIASES = {
    "at:43:4708": ["VIE", "Vienna Airport", "Schwechat Flughafen"],      # Flughafen Wien Bahnhof
    "at:43:5764": ["VIE Busterminal"],                                    # Flughafen Wien Busterminal
    "at:47:1187": ["Ibk Hbf", "INN Hbf"],                                 # Innsbruck Hauptbahnhof
    "at:47:61521": ["INN", "Innsbruck Airport"],                          # Innsbruck Flughafen
    "at:49:1468": ["Wien West"],                                          # Wien Westbahnhof
    "at:49:1349": ["Wien Süd"],                                           # Wien Hauptbahnhof (former Südbahnhof)
    "at:45:50002": ["SZG Hbf"],                                           # Salzburg Hauptbahnhof
    "at:46:1746": ["GRZ"],                                                # Flughafen Graz-Feldkirchen Bahnhof
    "at:44:40914": ["LNZ", "Linz Airport"],                               # Flughafen Linz (Hörsching) Terminal
    "at:42:6433": ["KLU", "Klagenfurt Airport"],                          # Klagenfurt Flughafen
}
PLACE_CLASS = {"city": 1, "town": 2, "village": 3, "suburb": 4, "hamlet": 5, "neighbourhood": 6, "quarter": 7,
               "isolated_dwelling": 8}


def summarize(final, locs, n_base):
    by_state = collections.Counter(STATE_CODES[pl.get("state", 0)] for pl in final)
    mode_names = {"rail": M_RAIL, "sev": M_SEV, "bus": M_BUS, "ship": M_SHIP, "subway": M_SUBWAY,
                  "tram": M_TRAM, "cable/ondemand": M_ONDEMAND_CABLE, "coach": M_COACH}
    by_mode = {n: sum(1 for pl in final if pl["modes"] & b) for n, b in mode_names.items()}
    by_mode["none"] = sum(1 for pl in final if not pl["modes"])
    by_state_mode = {}
    for s in STATE_CODES:
        sub = [pl for pl in final if STATE_CODES[pl.get("state", 0)] == s]
        by_state_mode[s] = {n: sum(1 for pl in sub if pl["modes"] & b) for n, b in mode_names.items()
                            if any(pl["modes"] & b for pl in sub)}
        by_state_mode[s]["total"] = len(sub)
        by_state_mode[s]["no_dep_weekday"] = sum(1 for pl in sub if pl["flags"] & 1)
    return {"stops_total": len(final), "base_verbund_stops": n_base,
            "added_not_in_verbund_list": sum(1 for pl in final if pl["flags"] & 2),
            "foreign": sum(1 for pl in final if pl["flags"] & 4),
            "with_eva": sum(1 for pl in final if pl["extids"].get("eva")),
            "with_hafas_extid": sum(1 for pl in final if pl["extids"].get("hafas")),
            "with_aliases": sum(1 for pl in final if pl["alias_list"]),
            "no_departures_weekday": sum(1 for pl in final if pl["flags"] & 1),
            "by_state": dict(by_state), "by_mode": by_mode, "by_state_mode": by_state_mode,
            "localities": len(locs)}


def write_bin(path, final, locs, gem_list, main_as_id=False):
    strings = bytearray(b"\0")  # offset 0 = empty
    smap = {}

    def s_off(s):
        if s in smap:
            return smap[s]
        o = len(strings)
        strings.extend(s.encode("utf-8") + b"\0")
        smap[s] = o
        return o
    index = {pl["id"]: i for i, pl in enumerate(final)}
    extras = bytearray()
    recs = bytearray()

    def rec(lat, lon, so, eo, modes, weight, gem, state, kind, flags, pclass=0):
        return struct.pack("<iiIIHHHBBBBH", int(round(lat * 1e6)), int(round(lon * 1e6)), so, eo,
                           modes & 0xFFFF, weight, 0xFFFF if gem is None else gem, state, kind, flags, pclass, 0)
    for pl in final:
        so = s_off("\x1f".join([pl["id"], pl["name"]] + pl["alias_list"]))
        ex = []
        if pl["extids"].get("eva"):
            ex.append((1, pl["extids"]["eva"]))
        if pl["extids"].get("hafas") and pl["extids"]["hafas"] != pl["extids"].get("eva"):
            ex.append((2, pl["extids"]["hafas"]))
        if pl["extids"].get("uic") and pl["extids"]["uic"] != pl["extids"].get("eva"):
            ex.append((6, pl["extids"]["uic"]))
        for lid in pl.get("legacy", []):   # every previous stations.json id, the record's own id included
            ex.append((3, s_off(lid)))
        if pl.get("lines"):
            ln = pl["lines"] if len(pl["lines"]) <= 120 else pl["lines"][:120].rsplit(",", 1)[0]
            ex.append((5, s_off(ln)))
        eo = 0xFFFFFFFF
        if ex:
            eo = len(extras)
            extras.extend(struct.pack("<B", len(ex)))
            for tag, v in ex:
                extras.extend(struct.pack("<BI", tag, v))
        recs.extend(rec(pl["lat"], pl["lon"], so, eo, pl["modes"], pl["weight"], pl.get("gem"),
                        pl.get("state", 0), 0, pl["flags"]))
    for lc in locs:
        so = s_off("\x1f".join([lc["id"], lc["name"]]))
        eo = len(extras)
        if main_as_id:  # localities.bin: main stop referenced by id (tag 7, str_off)
            extras.extend(struct.pack("<BBI", 1, 7, s_off(lc["main"])))
        else:
            extras.extend(struct.pack("<BBI", 1, 4, index[lc["main"]]))
        recs.extend(rec(lc["lat"], lc["lon"], so, eo, 0, min(65535, lc["pop"]), lc["gem"], lc["state"], 1, 0,
                        PLACE_CLASS.get(lc["place"], 0)))
    gem = bytearray()
    for gkz, name in gem_list:
        gem.extend(struct.pack("<II", gkz, s_off(name)))
    n = len(final) + len(locs)
    hdr_len = 64
    off_rec = hdr_len
    off_str = off_rec + len(recs)
    off_gem = off_str + len(strings)
    off_ex = off_gem + len(gem)
    hdr = struct.pack("<4sHHII", b"KBPL", 1, 0, n, len(gem_list))
    hdr += struct.pack("<IIIIIIII", off_rec, len(recs), off_str, len(strings), off_gem, len(gem), off_ex, len(extras))
    hdr += struct.pack("<I", len(final))  # number of stop records (localities follow)
    hdr = hdr.ljust(hdr_len, b"\0")
    with open(path, "wb") as fh:
        fh.write(hdr + recs + strings + gem + extras)


def read_bin(path):
    """Reference decoder (used by the self-test; mirrors what the Swift loader must do)."""
    b = open(path, "rb").read()
    magic, ver, _fl, n, ng = struct.unpack("<4sHHII", b[:16])
    assert magic == b"KBPL" and ver == 1
    off_rec, len_rec, off_str, len_str, off_gem, len_gem, off_ex, len_ex = struct.unpack("<8I", b[16:48])
    n_stops = struct.unpack("<I", b[48:52])[0]

    def s_at(o):
        e = b.index(b"\0", off_str + o)
        return b[off_str + o:e].decode("utf-8")
    gems = [struct.unpack("<II", b[off_gem + 8 * i: off_gem + 8 * i + 8]) for i in range(ng)]
    gems = [(g, s_at(o)) for g, o in gems]
    out = []
    for i in range(n):
        lat, lon, so, eo, modes, w, gem, state, kind, flags, pclass, _r2 = struct.unpack(
            "<iiIIHHHBBBBH", b[off_rec + 28 * i: off_rec + 28 * i + 28])
        parts = s_at(so).split("\x1f")
        ex = {}
        if eo != 0xFFFFFFFF:
            k = b[off_ex + eo]
            for j in range(k):
                tag, v = struct.unpack("<BI", b[off_ex + eo + 1 + 5 * j: off_ex + eo + 6 + 5 * j])
                ex.setdefault(tag, []).append(s_at(v) if tag in (3, 5, 7) else v)
        out.append({"id": parts[0], "name": parts[1], "aliases": parts[2:], "lat": lat / 1e6, "lon": lon / 1e6,
                    "modes": modes, "weight": w, "gem": gems[gem][1] if gem != 0xFFFF else None,
                    "state": STATE_CODES[state], "kind": kind, "flags": flags, "place_class": pclass, "extras": ex})
    return out, n_stops


def write_debug(outdir, final, locs, gem_list, legacy, attribution):
    with open(p(outdir, "places.json"), "w", encoding="utf-8") as fh:
        json.dump([{"id": pl["id"], "name": pl["name"], "aliases": pl["alias_list"], "lat": round(pl["lat"], 6),
                    "lon": round(pl["lon"], 6), "state": STATE_CODES[pl.get("state", 0)],
                    "gem": gem_list[pl["gem"]][1] if pl.get("gem") is not None else None,
                    "modes": pl["modes"], "weight": pl["weight"], "flags": pl["flags"],
                    "eva": pl["extids"].get("eva"), "hafas": pl["extids"].get("hafas"), "uic": pl["extids"].get("uic"),
                    "legacy": pl.get("legacy"), "src": sorted(pl["src"]), "lines": pl.get("lines", "")[:120]}
                   for pl in final], fh, ensure_ascii=False, separators=(",", ":"))
    with open(p(outdir, "localities.json"), "w", encoding="utf-8") as fh:
        json.dump(locs, fh, ensure_ascii=False, separators=(",", ":"))
    with open(p(outdir, "legacy_map.json"), "w", encoding="utf-8") as fh:
        json.dump(legacy, fh, ensure_ascii=False, indent=0, sort_keys=True)
    with open(p(outdir, "ATTRIBUTION.txt"), "w", encoding="utf-8") as fh:
        fh.write(attribution + "\n")


ATTRIBUTION = """Haltestellen/Orte (places.bin) – Datenquellen und Lizenzen
• Haltestellenliste: Mobilitätsverbünde Österreich OG (Haltestellen-WFS, Stand 10/2025), bereitgestellt über
  ÖV-Güteklassen 2025 (ÖROK / BMIMI / AustriaTech, https://www.mobilitydata.gv.at/daten/öv-güteklassen).
  Bei Nutzung von data.mobilitaetsverbuende.at: „Datenquelle: Mobilitätsverbünde Österreich OG,
  Datenlizenz Mobilitätsverbünde Österreich v1.1 (https://data.mobilitaetsverbuende.at); verändert
  (zusammengeführt, gekürzt, Koordinaten umgerechnet).“
• Bahnhöfe: ÖBB-Personenverkehr AG, Soll-Fahrplan GTFS 2026, CC BY 4.0 (https://data.oebb.at).
• Wien: Stadt Wien – data.wien.gv.at (Wiener Linien GTFS), CC BY 4.0.
• Steiermark: Land Steiermark – data.steiermark.gv.at (Haltestellen des Verkehrsverbundes Steiermark), CC BY 4.0.
• Gemeinden/Bundesländer: Statistik Austria – data.statistik.gv.at (Gemeindegrenzen 01.01.2026), CC BY 4.0.
• EVA-Nummern der Bahnhöfe: Datenquelle ÖBB-Infrastruktur AG (Verzeichnis der Verkehrsstationen), CC BY 3.0 AT."""
ATTRIBUTION_OSM = {
    "separate": """• Orte (localities.bin): © OpenStreetMap-Mitwirkende, ODbL 1.0 (https://www.openstreetmap.org/copyright);
  localities.bin ist eine abgeleitete Datenbank unter ODbL 1.0. places.bin enthält keine OSM-Daten.""",
    "merge": """• Orte, Namensvarianten, Verkehrsmittel-Ergänzungen: © OpenStreetMap-Mitwirkende, ODbL 1.0
  (https://www.openstreetmap.org/copyright). places.bin ist als Ganzes eine abgeleitete Datenbank unter ODbL 1.0.""",
}


if __name__ == "__main__":
    main()
