#!/usr/bin/env python3
"""KlimaBilanz – all public-transport lines per stop (build_lines.py, docs/ENRICH_SPEC.md §1.7, WP-D1/D2).

Reproducible, stdlib-only (Python ≥ 3.10). Merges every open line↔stop source into one catalogue of
lines and, for every stop of places.json (key = places id "at:<land>:<nr>"), the list of lines that serve it.
Run twice by scripts/build_places_all.sh: once WITHOUT --osm (official layer → places.bin) and once WITH --osm
(full build → the ODbL layer stops_osm.bin keeps only what the official build lacks).

    python3 -I scripts/build_lines.py --places build/places/places.json --out build/lines_full \
        --oevgk  build/places-dl/oevgk/x/01_Haltestellenkategorien \
        --osm    build/enrich/osm_routes.json \
        --oebb-gtfs build/places-dl/oebb_gtfs   --wl-gtfs build/places-dl/wl/gtfs.zip \
        --stmk-stops build/places-dl/stmk/x/Haltestellen --stmk-lines build/places-dl/stmk_lines/x/VSTG_Linienverkehr \
        [--gtfs path/to/mvo_vvt_gtfs.zip=vvt ...]     # data.mobilitaetsverbuende.at feeds (free account)
        [--scotty-live path/to/scotty_lines_raw.json]   # validation only (not merged)

Sources (all optional except --places; missing inputs only reduce coverage):
  oevgk    ÖV-Güteklassen 2025_revised, Haltestellenkategorien 22.10.2025 (Werktag) + 29.10.2025 (Herbstferien):
           field "Linien" = all line numbers at the stop on that day (refs only; no mode/operator/termini)
  osm      OpenStreetMap route relations (extract_osm_routes.py): ref, name, network, operator, from/to,
           opening_hours, ordered stops → line identity, termini, ski/night/summer flags, next stops
  gtfs     any GTFS (ÖBB-PV rail, Wiener Linien, the 7 Verbund feeds + Linz AG of data.mobilitaetsverbuende.at):
           authoritative stop sequences, headsigns, operators, service months (→ seasonal) and night service
  stmk     Land Steiermark OGD: stop list with DIVA line codes + "Linienverkehr" (public number, type, Schüler/Saisonal)

Line identity (ENRICH_SPEC E1/E3): a catalogue line is one connected component of the stop graph of one public line
(GTFS: agency + route_short_name, split into the components of its route_ids' stop patterns; OSM: route_master or
network/ref/operator; ÖV-GK/Stmk tokens: ref + mode, attached to the nearest line with that ref ≤ 4 km, else
clustered ≤ 12 km). Two lines "R1" in Upper Austria and in the VOR area are therefore two lines with their own
termini; the network of a token-only line is the majority Verbund of its stops (cross-border 110 Reutte – Warth
is VVT, not VVV at its two Vorarlberg stops).

Outputs (OUT/):
  lines_catalog.json   {"lines": [ {id, ref, mode, net, op, name, termini:[[from,to],…], flags:[…], src:[…],
                                    n_stops, states:[…], [successor]} … ], "net_names": {…}}
  lines_by_stop.json   {place_id: {"l": [[line_idx, [to…], [next place ids…], conf], …], "p": [rail products]}}
                        conf: 2 = confirmed by an authoritative timetable source (GTFS/ÖV-GK/Stmk),
                              1 = OSM only (usually seasonal/ski or not in the October reference days)
  lines_patterns.json  [{"l": line_idx, "to": headsign, "from": origin, "s": [place ids in order], "src": …}]
  lines_report.json    coverage per state/mode, flag counts, residual gaps, validation vs live Scotty
  LINES_ATTRIBUTION.txt

Licence layering: OSM content (ODbL, share-alike for the database) must not be mixed into one shipped database with
data whose licence forbids sub-licensing (MVO v1.1). Ship two layers – a build WITHOUT --osm ("official" layer:
GTFS/Stmk[/ÖV-GK]) and a build WITH --osm (ODbL layer, offered under ODbL) – and merge them at runtime in the app,
exactly like places.bin (no OSM) + localities.bin (ODbL).
"""
import argparse
import collections
import csv
import datetime as dt
import io
import json
import math
import os
import re
import struct
import sys
import unicodedata
import zipfile

csv.field_size_limit(1 << 26)
R_EARTH = 6371008.8


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# =============================================================================================
# geometry / names (same rules as scripts/build_places.py so ids and names agree)
# =============================================================================================
def hav_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * R_EARTH * math.asin(min(1.0, math.sqrt(a)))


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
        k0, k1 = self.key(lat - dlat, lon - dlon), self.key(lat + dlat, lon + dlon)
        out = []
        for i in range(k0[0], k1[0] + 1):
            for j in range(k0[1], k1[1] + 1):
                for la, lo, it in self.g.get((i, j), ()):
                    d = hav_m(lat, lon, la, lo)
                    if d <= radius_m:
                        out.append((d, it))
        out.sort(key=lambda x: x[0])
        return out


def fold(s):
    s = s.replace("ß", "ss").replace("ẞ", "ss")
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


UNIGRAMS = {"hauptbahnhof": "hbf", "hbhf": "hbf", "bahnhof": "bf", "bhf": "bf", "bahnhst": "bf", "sankt": "st",
            "str": "strasse", "wr": "wiener", "b": "bei"}
STOPW = {"bf", "hbf", "hst", "haltestelle", "bahnhst", "station", "bahnhof", "u", "s", "b", "a", "d", "i", "an",
         "der", "die", "dem", "den", "im", "in", "am", "ob", "bei", "und", "zum", "zur", "abzw", "gh", "lokalbahn",
         "bahn", "vorarlberg", "tirol", "vlbg", "karnten", "steiermark", "salzburg", "pinzgau", "pongau", "no", "oo"}


def norm(s):
    s = fold((s or "").lower()).replace("str.", "strasse ")
    out = []
    for w in re.sub(r"[^a-z0-9]+", " ", s).split():
        w = UNIGRAMS.get(w, w)
        for suf, rp in (("hauptbahnhof", "hbf"), ("bahnhof", "bf")):
            if w.endswith(suf) and len(w) > len(suf):
                w = w[: -len(suf)] + rp
        for x, y in (("ae", "a"), ("oe", "o"), ("ue", "u")):
            w = w.replace(x, y)
        out.append(w)
    return " ".join(out)


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
    return max(inter / max(len(ta), len(tb)), len(ta & tb) / min(len(ta), len(tb)))


def ifopt_parent(s):
    if not s:
        return None
    s = s.strip()
    if s.startswith("P"):
        s = s[1:]
    m = re.match(r"^([a-z]{2}):(\d+):(\d+)", s)
    return f"{m.group(1)}:{int(m.group(2))}:{int(m.group(3))}" if m else None


def read_dbf(path, enc="utf-8"):
    with open(path, "rb") as f:
        hdr = f.read(32)
        n, hlen, rlen = struct.unpack("<IHH", hdr[4:12])
        fields = []
        while True:
            d = f.read(32)
            if d[0] == 0x0D:
                break
            fields.append((d[:11].split(b"\0")[0].decode("ascii"), d[16]))
        f.seek(hlen)
        for _ in range(n):
            r = f.read(rlen)
            if not r or r[0:1] == b"\x1a":
                break
            out, pos = {"_deleted": r[0:1] == b"*"}, 1
            for name, ln in fields:
                out[name] = r[pos:pos + ln].decode(enc, "replace").strip()
                pos += ln
            yield out


# =============================================================================================
# line vocabulary: refs, modes, networks, flags
# =============================================================================================
MODES = ["rail", "sbahn", "subway", "tram", "bus", "trolleybus", "sev", "ondemand", "cable", "ship", "coach"]
MODE_RANK = {m: i for i, m in enumerate(MODES)}
RAIL_PRODUCTS = {"RJX", "RJ", "ICE", "EC", "IC", "D", "EN", "NJ", "IR", "ECE", "WB", "REX", "R", "CJX", "S", "RE",
                 "RB", "Regionalzug", "LEX", "TGV", "FR", "ER", "SB", "ATZ", "MEX", "RGJ", "EX", "Os", "Sp", "RR",
                 "RX", "CAT", "NPB", "WHB", "LKB", "GKB", "STB", "ZB", "ZB1", "MÜHXI", "BAHN", "TRAIN"}
GENERIC_RAIL = {"RJX", "RJ", "ICE", "EC", "IC", "EN", "NJ", "IR", "ECE", "WB", "REX", "R", "CJX", "S", "RE", "RB",
                "Regionalzug", "LEX", "TGV", "FR", "ER", "ATZ", "MEX", "RGJ", "EX", "Os", "Sp", "RR", "RX"}
CITY_TRAMS = {  # tram line refs per city (stop-name prefix); build_places.py's table + Wien 12 (since 2025)
    "wien": {"1", "2", "5", "6", "9", "10", "11", "12", "18", "25", "26", "27", "30", "31", "33", "37", "38", "40", "41",
             "42", "43", "44", "46", "49", "52", "60", "62", "71", "D", "O", "WLB", "BB"},
    "graz": {"1", "3", "4", "5", "6", "7", "16", "17"},
    "linz": {"1", "2", "3", "4", "50"},
    "innsbruck": {"1", "2", "3", "5", "6", "STB"},
    "gmunden": {"174", "TT"},
}
STATE_NET = {"W": "VOR", "NÖ": "VOR", "B": "VOR", "ST": "VVSt", "K": "VKL", "OÖ": "OÖVV", "S": "SVV", "T": "VVT",
             "V": "VVV"}
NET_NAMES = {  # text only – the app renders its own neutral badges (no Verbund logos)
    "VOR": "Verkehrsverbund Ost-Region", "VVSt": "Verbund Linie (Steiermark)", "VKL": "Kärntner Linien",
    "OÖVV": "OÖ Verkehrsverbund", "SVV": "Salzburger Verkehrsverbund", "VVT": "Verkehrsverbund Tirol",
    "VVV": "Verkehrsverbund Vorarlberg", "ÖBB": "ÖBB / Bahn", "INT": "international"}
NET_RX = [(re.compile(r"\bvor\b|ost-?region|wiener linien|wiener lokalbahnen", re.I), "VOR"),
          (re.compile(r"steiermark|steirisch|verbundlinie|verbund linie|graz linien", re.I), "VVSt"),
          (re.compile(r"k[äa]rnt", re.I), "VKL"),
          (re.compile(r"ober[öo]sterreich|o[öo]vv|linz ag", re.I), "OÖVV"),
          (re.compile(r"salzburg|\bsvv\b", re.I), "SVV"),
          (re.compile(r"tirol|\bvvt\b|ivb", re.I), "VVT"),
          (re.compile(r"vorarlberg|\bvvv\b|vmobil", re.I), "VVV"),
          (re.compile(r"\b(öbb|oebb|railjet|nightjet|westbahn|eurocity|euronight|intercity)\b", re.I), "ÖBB")]
FOREIGN_NET_RX = re.compile(r"münchner|mvv|oberbayern|allgäu|ostallgäu|bodensee|ostbayern|bratislava|mhd|"
                            r"liechtenstein|ch-gr|jihomorav|ids |idsjmk|ostwind|südtirol|sad|ding|db regio|"
                            r"flixbus|regiojet|blablacar|vb |volán|gysev|slovak|ljubljana|lpp|jmk|ids bk", re.I)

FLAG_RX = {  # applied to line-level text only (stop names removed first, see line_text())
    "ski": re.compile(r"(?<![a-zäöü])(s[ck]hi|ski)(?![a-zäöü])|s[ck]hi-?(bus|shuttle|zubringer|express|pendel|linie|taxi)|"
                      r"ski-?(bus|shuttle|zubringer|express|pendel|linie|taxi)|wintersport|gletscher-?(bus|shuttle|"
                      r"express)|snow-?(bus|shuttle)|skigebiet|schigebiet|bergbahn(en)?-?shuttle|ski ?area|"
                      r"pistenbus|loipenbus|langlaufbus|winterbus|winterlinie", re.I),
    "night": re.compile(r"(?<![a-zäöü])nacht(bus|linie|schwärmer|stern|fahrt|verkehr)?(?![a-zäöü])|nightline|"
                        r"night ?bus|nightliner|moonliner|nightrider|discobus|disco-?bus|partybus|late-?night|"
                        r"(?<![a-z])night(?![a-z])", re.I),
    "summer": re.compile(r"wanderbus|alm-?bus|sommer(bus|linie|betrieb|fahrplan)?(?![a-zäöü])|bergsteigerbus|badebus|"
                         r"nationalpark-?bus|hütten-?(bus|taxi)|bike-?shuttle|rad-?(bus|shuttle)|wanderexpress|"
                         r"erlebnisbus|tälerbus|seenbus|glocknerbus|alm-?taxi|wandertaxi|gipfelbus|wander-?shuttle", re.I),
    "school": re.compile(r"schul-?bus|schüler-?(bus|verkehr|linie|kurs|fahrt)|schulkurs|schulverkehr|schulfahrt|"
                         r"school ?bus", re.I),
    "ondemand": re.compile(r"rufbus|anrufsammel|(?<![a-z])ast(?![a-z])|istmobil|gmoa-?bus|postbus ?shuttle|"
                           r"on-?demand|mikro-?öv|dorfmobil|gemeindebus|sammeltaxi|vor flex|regioflex|"
                           r"(?<![a-z])flex(?![a-z])|bedarfsverkehr|go-?mobil|emil|tälerbus-?ruf", re.I),
}
SKI_STOP_RX = re.compile(r"talstation|bergbahn|gondel|seilbahn|sesselbahn|skilift|schilift|lift(?![a-zäöü])|"
                         r"liftstation|skischaukel|skigebiet|schigebiet|skischule|schischule|piste|gletscherbahn|"
                         r"[a-zäöü]+bahn talst|jet talstation|skizentrum|schizentrum|skistadion|loipe", re.I)
SCHOOL_TOKENS = {"V": {"SK"}}
REF_ALIAS = {"WLB": "BB", "BADNERBAHN": "BB", "LOKALBAHNWIENBADEN": "BB"}


def line_text(t):
    """Route-level text without the stop names in from/to/via (so 'Schulzentrum' is not a school-bus flag)."""
    txt = " ".join(x for x in (t.get("name"), t.get("description"), t.get("note"), t.get("service"),
                               t.get("bus"), t.get("ref")) if x)
    stops = [t.get("from"), t.get("to")] + re.split(r"\s*;\s*", t.get("via") or "")
    for st in sorted((x for x in stops if x and len(x) >= 4), key=len, reverse=True):
        txt = txt.replace(st, " ")
    return txt


MONTHS = {m: i + 1 for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct",
                                          "nov", "dec"])}
WINTER, SUMMER = {11, 12, 1, 2, 3, 4}, {5, 6, 7, 8, 9, 10}


def refnorm(r):
    r = fold((r or "").strip()).upper()
    r = re.sub(r"^(BUS|LINIE|LINE|TRAM|STRASSENBAHN|BIM|O-?BUS|CITYBUS|STADTBUS)\s+", "", r)
    r = re.sub(r"[\s\-_./]+", "", r)
    return REF_ALIAS.get(r, r)


def months_from_oh(oh):
    """Months mentioned in an OSM opening_hours string (None if no month selector)."""
    if not oh:
        return None
    s = oh.lower()
    found = set()
    for m in re.finditer(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s*(\d{1,2})?\s*(-\s*(jan|feb|mar|apr|"
                         r"may|jun|jul|aug|sep|oct|nov|dec)\w*\s*(\d{1,2})?)?", s):
        a = MONTHS[m.group(1)]
        b = MONTHS[m.group(4)] if m.group(4) else a
        i = a
        while True:
            found.add(i)
            if i == b:
                break
            i = i % 12 + 1
    if not found:
        return None
    if re.search(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*[^;]*\boff\b", s) and len(found) <= 4:
        return set(range(1, 13)) - found  # "Jul-Aug off" style
    return found


def season_flags(months):
    if not months or len(months) >= 11:
        return set()
    if months <= WINTER:
        return {"winter"}
    if months <= SUMMER:
        return {"summer"}
    return {"seasonal"}


def flags_from_text(*texts):
    t = " ".join(x for x in texts if x)
    f = {k for k, rx in FLAG_RX.items() if rx.search(t)}
    if "ski" in f:
        f.add("winter")
    return f


def mode_from_token(tok, stop_name, state):
    n = norm(stop_name)
    city = next((c for c in CITY_TRAMS if n == c or n.startswith(c + " ")), None)
    t0 = tok.split(" ")[0]
    if city and (tok in CITY_TRAMS[city] or t0 in CITY_TRAMS[city]):
        return "tram"
    if re.fullmatch(r"U\d", tok):
        return "subway"
    if re.fullmatch(r"S\d{1,3}[A-Z]?", tok):
        return "sbahn"
    if t0 in RAIL_PRODUCTS or re.fullmatch(r"(R|REX|CJX)\d+", tok):
        return "rail"
    if t0.startswith("SV") or t0.startswith("SEV"):
        return "sev"
    if t0 in ("AST", "RUF") or t0.startswith("AST"):
        return "ondemand"
    return "bus"


def compat(m1, m2):
    if m1 == m2:
        return True
    grp = {"rail": "R", "sbahn": "R", "bus": "B", "trolleybus": "B", "sev": "B", "ondemand": "B", "coach": "B",
           "tram": "T", "subway": "U", "cable": "C", "ship": "W"}
    return grp.get(m1) == grp.get(m2)


def net_code(network, operator=None, state=None):
    s = " ".join(x for x in (network, operator) if x)
    if s and FOREIGN_NET_RX.search(s) and not any(rx.search(network or "") for rx, _ in NET_RX[:7]):
        return "INT"
    for rx, code in NET_RX:
        if network and rx.search(network):
            return code
    for rx, code in NET_RX:
        if operator and rx.search(operator):
            return code
    return STATE_NET.get(state) if state else None


def natkey(ref):
    m = re.match(r"([A-Za-z]*)(\d*)(.*)", ref or "")
    return (m.group(1), int(m.group(2)) if m.group(2) else -1, m.group(3))


# =============================================================================================
# catalogue
# =============================================================================================
class Catalog:
    def __init__(self, places):
        self.places = places
        self.lines = []                 # dicts
        self.by_ref = collections.defaultdict(list)
        self.stop_lines = collections.defaultdict(dict)  # pid -> {line_idx: {"to": Counter, "nx": set, "src": set}}
        self.patterns = []
        self.edges = collections.defaultdict(set)        # line_idx -> {(pid, pid)}: stop graph (E1 components)

    def new_line(self, ref, mode, net, op=None, name=None, src=None, key=None):
        L = {"ref": ref, "rn": refnorm(ref), "mode": mode, "net": net, "op": collections.Counter(),
             "name": collections.Counter(), "termini": collections.Counter(), "flags": set(), "src": set(),
             "stops": set(), "keys": set(), "alive": True}
        if op:
            L["op"][op] += 1
        if name:
            L["name"][name] += 1
        if src:
            L["src"].add(src)
        if key:
            L["keys"].add(key)
        self.lines.append(L)
        idx = len(self.lines) - 1
        self.by_ref[L["rn"]].append(idx)
        return idx

    def serve(self, idx, pid, src, to=None, nxt=None):
        e = self.stop_lines[pid].setdefault(idx, {"to": collections.Counter(), "nx": set(), "src": set()})
        e["src"].add(src)
        if to:
            e["to"][to] += 1
        if nxt:
            e["nx"].add(nxt)
        self.lines[idx]["stops"].add(pid)
        self.lines[idx]["src"].add(src)

    def find(self, rn, mode, pid, radius_m=4000, net=None):
        """Existing line with this ref serving pid (exact) or passing within radius_m of it.
        Returns (line index, distance m, nearest stop of that line) – (None, None, None) if there is none."""
        cands = [i for i in self.by_ref.get(rn, ()) if self.lines[i]["alive"] and compat(self.lines[i]["mode"], mode)]
        if not cands:
            return None, None, None
        for i in cands:
            if pid in self.lines[i]["stops"]:
                return i, 0.0, pid
        p = self.places[pid]
        best, bd, bq = None, 1e18, None
        for i in cands:
            L = self.lines[i]
            # cross-Verbund lines exist (e.g. VVT 110 into Vorarlberg) – distance decides, not the network
            if len(L["stops"]) > 4000:
                continue
            for q in sorted(L["stops"]):
                pq = self.places[q]
                if abs(pq["lat"] - p["lat"]) > 0.08 or abs(pq["lon"] - p["lon"]) > 0.12:
                    continue
                d = hav_m(p["lat"], p["lon"], pq["lat"], pq["lon"])
                if d < bd:
                    best, bd, bq = i, d, q
        if best is not None and bd <= radius_m:
            return best, bd, bq
        return None, None, None

    def link(self, idx, a, b):
        """Edge of the line's stop graph (consecutive pattern stops, or a token stop attached to its nearest stop)."""
        if a and b and a != b:
            self.edges[idx].add((a, b) if a < b else (b, a))

    def merge(self, a, b):
        """Merge line b into a."""
        if a == b:
            return a
        A, B = self.lines[a], self.lines[b]
        for k in ("op", "name", "termini"):
            A[k].update(B[k])
        A["flags"] |= B["flags"]
        A["src"] |= B["src"]
        for k in ("gtfs_allyear", "gtfs_not_night"):
            if B.get(k):
                A[k] = True
        A["keys"] |= B["keys"]
        self.edges[a] |= self.edges.pop(b, set())
        for pid in B["stops"]:
            e = self.stop_lines[pid].pop(b, None)
            if e:
                ea = self.stop_lines[pid].setdefault(a, {"to": collections.Counter(), "nx": set(), "src": set()})
                ea["to"].update(e["to"])
                ea["nx"] |= e["nx"]
                ea["src"] |= e["src"]
        A["stops"] |= B["stops"]
        B["alive"] = False
        B["merged_into"] = a
        for pt in self.patterns:
            if pt["l"] == b:
                pt["l"] = a
        if MODE_RANK.get(B["mode"], 99) < MODE_RANK.get(A["mode"], 99) and A["mode"] in ("bus",) and B["mode"] != "bus":
            A["mode"] = B["mode"]
        if not A["net"]:
            A["net"] = B["net"]
        return a

    def resolve(self, i):
        while not self.lines[i]["alive"]:
            i = self.lines[i]["merged_into"]
        return i


def split_components(cat, iso_radius_m=4000.0):
    """E1: split every line into the connected components of its stop graph (pattern edges + token attachments).
    A stop without any edge (single-stop pattern) joins the nearest stop of the line within iso_radius_m.
    The largest component keeps the line index; the others become new lines with the same attributes and the
    termini of their own patterns."""
    places = cat.places
    n_split, n_new, examples = 0, 0, []
    for i in range(len(cat.lines)):
        L = cat.lines[i]
        if not L["alive"] or len(L["stops"]) < 2:
            continue
        stops = sorted(L["stops"])
        pos = {p: k for k, p in enumerate(stops)}
        parent = list(range(len(stops)))

        def fnd(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def uni(a, b):
            ra, rb = fnd(a), fnd(b)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
        linked = set()
        for a, b in sorted(cat.edges.get(i, ())):
            if a in pos and b in pos:
                uni(pos[a], pos[b])
                linked.add(a)
                linked.add(b)
        for p in stops:
            if p in linked:
                continue
            pp = places[p]
            best, bd = None, iso_radius_m
            for q in stops:
                if q == p:
                    continue
                pq = places[q]
                if abs(pq["lat"] - pp["lat"]) > 0.05 or abs(pq["lon"] - pp["lon"]) > 0.08:
                    continue
                d = hav_m(pp["lat"], pp["lon"], pq["lat"], pq["lon"])
                if d < bd:
                    best, bd = q, d
            if best is not None:
                uni(pos[p], pos[best])
        comps = collections.OrderedDict()
        for k, p in enumerate(stops):
            comps.setdefault(fnd(k), []).append(p)
        if len(comps) == 1:
            continue
        parts = sorted(comps.values(), key=lambda c: (-len(c), c[0]))
        n_split += 1
        if len(examples) < 40:
            examples.append(f"{L['ref']} {L['mode']} {L['net']}: " + " | ".join(
                f"{places[c[0]]['name']} (+{len(c) - 1})" for c in parts[:4]))
        pat_of = collections.defaultdict(list)
        for k, pt in enumerate(cat.patterns):
            if cat.resolve(pt["l"]) == i:
                pat_of[pt["s"][0]].append(k)
        for ci, comp in enumerate(parts):
            cs = set(comp)
            if ci == 0:
                j = i
            else:
                j = cat.new_line(L["ref"], L["mode"], L["net"], key=f"comp:{i}:{ci}")
                M = cat.lines[j]
                for k in ("op", "name"):
                    M[k].update(L[k])
                M["flags"] |= L["flags"]
                M["keys"] |= {f"{x}:{ci}" for x in L["keys"]}
                for k in ("gtfs_allyear", "gtfs_not_night", "network_raw", "successor"):
                    if k in L:
                        M[k] = L[k]
                for p in comp:
                    e = cat.stop_lines[p].pop(i, None)
                    if e is not None:
                        cat.stop_lines[p][j] = e
                M["stops"] = cs
                cat.edges[j] = {(a, b) for a, b in cat.edges.get(i, ()) if a in cs}
                n_new += 1
            M = cat.lines[j]
            M["src"] = set().union(*(cat.stop_lines[p][j]["src"] for p in comp if j in cat.stop_lines[p])) or set(L["src"])
            term = collections.Counter()
            for p in comp:
                for k in pat_of.get(p, ()):
                    pt = cat.patterns[k]
                    pt["l"] = j
                    term[(pt.get("from") or places[pt["s"][0]]["name"],
                          pt.get("to") or places[pt["s"][-1]]["name"])] += pt.get("w", 1)
            M["termini"] = term
        L["stops"] = set(parts[0])
        cat.edges[i] = {(a, b) for a, b in cat.edges.get(i, ()) if a in L["stops"]}
    return {"lines_split": n_split, "new_lines": n_new, "examples": examples}


def add_pattern(cat, idx, seq, to, src, frm=None, weight=1):
    """Serve the stops of one stop sequence; termini are counted with `weight` (GTFS: number of trips)."""
    seq2 = []
    for pid in seq:
        if pid and (not seq2 or seq2[-1] != pid):
            seq2.append(pid)
    if not seq2:
        return
    for k, pid in enumerate(seq2):
        nxt = seq2[k + 1] if k + 1 < len(seq2) else None
        is_last = k == len(seq2) - 1
        cat.serve(idx, pid, src, to=None if is_last else to, nxt=nxt)
        cat.link(idx, pid, nxt)
    if len(seq2) >= 2:
        cat.patterns.append({"l": idx, "to": to, "from": frm, "s": seq2, "src": src, "w": weight})
    if frm or to:
        cat.lines[idx]["termini"][(frm or cat.places[seq2[0]]["name"], to or cat.places[seq2[-1]]["name"])] += weight


# =============================================================================================
# loaders
# =============================================================================================
def load_places(path):
    pl = {}
    for p in json.load(open(path, encoding="utf-8")):
        pl[p["id"]] = {"name": p["name"], "lat": p["lat"], "lon": p["lon"], "state": p["state"], "modes": p["modes"],
                       "weight": p["weight"], "gem": p.get("gem"), "lines0": p.get("lines", "")}
    return pl


def load_oevgk(dirpath):
    days = {}
    for tag, fn in (("20251022", "Haltestellenkategorien_20251022_revised.dbf"),
                    ("20251029", "Haltestellenkategorien_20251029_revised.dbf")):
        path = os.path.join(dirpath, fn)
        if not os.path.exists(path):
            continue
        out = {}
        for r in read_dbf(path):
            if r["_deleted"]:
                continue
            s = str(int(float(r["St_Nummer"])))
            sid = f"at:{int(s[:2])}:{int(s[2:7])}"
            out[sid] = {"lines": [x.strip() for x in r["Linien"].split(",") if x.strip()], "dep": int(r["Anz_Abf"] or 0),
                        "vkat": r["VKAT_Hst"], "trunc": len(r["Linien"]) >= 199, "sev": "Schienenersatz" in r["Hinweis"]}
        days[tag] = out
    return days


def osm_mode(route_tag, tags):
    r = route_tag
    if r in ("bus", "minibus"):
        return "bus"
    if r == "trolleybus":
        return "trolleybus"
    if r == "share_taxi":
        return "ondemand"
    if r == "coach":
        return "coach"
    if r == "tram":
        return "tram"
    if r == "light_rail":
        return "tram"
    if r == "subway":
        return "subway"
    if r in ("train", "railway", "monorail"):
        ref = (tags.get("ref") or "").replace(" ", "")
        return "sbahn" if re.fullmatch(r"S\d{1,3}[A-Z]?", ref) else "rail"
    if r == "ferry":
        return "ship"
    if r in ("funicular", "aerialway"):
        return "cable"
    return "bus"


def osm_stop_mapper(osm, places, grid):
    """OSM element key ('n123'/'w45') -> places id (IFOPT first, then name+distance)."""
    area_of = {}
    for a in osm.get("stop_areas", []):
        for ty, ref, role in a["members"]:
            area_of[f"{ty}{ref}"] = a["tags"]
    cache = {}
    stats = collections.Counter()

    def mp(key):
        if key in cache:
            return cache[key]
        el = osm["nodes"].get(key[1:]) if key[0] == "n" else osm["ways"].get(key[1:])
        res = None
        if el:
            t = el.get("tags") or {}
            at = area_of.get(key) or {}
            for cand in (t.get("ref:IFOPT"), at.get("ref:IFOPT")):
                pid = ifopt_parent(cand)
                if pid and pid in places:
                    res = pid
                    stats["ifopt"] += 1
                    break
            if not res:
                name = t.get("name") or at.get("name") or ""
                near = grid.near(el["lat"], el["lon"], 250)
                best = None
                for d, pid in near:
                    s = name_sim(name, places[pid]["name"]) if name else 0.0
                    if (name and s >= 0.5 and d <= 250) or d <= 35 or (not name and d <= 60):
                        score = d - 120 * s
                        if best is None or score < best[0]:
                            best = (score, pid)
                if best:
                    res = best[1]
                    stats["geo_name"] += 1
                else:
                    stats["unmatched"] += 1
        else:
            stats["missing_el"] += 1
        cache[key] = res
        return res
    return mp, stats


def load_osm(cat, osm_path, places, grid, report):
    osm = json.load(open(osm_path, encoding="utf-8"))
    mp, stats = osm_stop_mapper(osm, places, grid)
    master_of = {}
    for m in osm.get("route_masters", []):
        for rid in m["members"]:
            master_of[rid] = m
    groups = collections.OrderedDict()
    skipped = collections.Counter()
    for r in osm["routes"]:
        t = r["tags"]
        if t.get("disused") == "yes" or "disused" in (t.get("name", "").lower()):
            skipped["disused"] += 1
            continue
        mode = osm_mode(t.get("route"), t)
        ref = (t.get("ref") or "").strip()
        refs = [x for x in re.split(r"\s*[;,]\s*", ref) if x] if ref else []
        if not refs:
            # unnamed ski / shuttle buses: use a short name as ref
            nm = (t.get("name") or "").strip()
            if not nm:
                skipped["no_ref"] += 1
                continue
            refs = [nm[:24]]
        if mode in ("rail", "sbahn") and all(re.fullmatch(r"\d{2,4}", x) for x in refs):
            skipped["rail_kbs_number_not_a_line"] += 1   # Kursbuchstrecke, not a public line number
            continue
        m = master_of.get(r["id"])
        for ref in refs:
            gkey = ("m", m["id"], refnorm(ref)) if m else ("r", t.get("network"), refnorm(ref), mode,
                                                         fold(t.get("operator") or "").lower())
            groups.setdefault(gkey, []).append((r, mode, ref, m))
    n_routes = 0
    for gkey, rs in groups.items():
        r0, mode, ref, m = rs[0]
        mt = (m or {}).get("tags", {})
        seqs = []
        for r, mode_r, ref_r, _ in rs:
            seq = []
            for ty, ref_el, role in r["members"]:
                if ty == "w" and not (role.startswith("platform") or role.startswith("stop")):
                    continue
                if ty == "n" and role and not (role.startswith("platform") or role.startswith("stop")):
                    continue
                pid = mp(f"{ty}{ref_el}")
                if pid:
                    seq.append(pid)
            seqs.append((r, seq))
        mapped = [s for _, s in seqs if s]
        if not mapped:
            skipped["no_mapped_stop"] += 1
            continue
        states = collections.Counter(places[p]["state"] for s in mapped for p in s)
        if states and states.most_common(1)[0][0] == "X" and sum(v for k, v in states.items() if k != "X") < 2:
            skipped["abroad"] += 1
            continue
        t0 = r0["tags"]
        network = t0.get("network") or mt.get("network")
        operator = t0.get("operator") or mt.get("operator")
        main_state = next((s for s, _ in states.most_common() if s != "X"), None)
        net = net_code(network, operator, main_state)
        if mode in ("rail", "sbahn") and net is None:
            net = "ÖBB"
        idx = cat.new_line(ref, mode, net, op=operator, name=mt.get("name") or t0.get("name"), src="osm",
                           key=f"osm:{gkey}")
        L = cat.lines[idx]
        L["network_raw"] = network
        texts = []
        months_all = set()
        has_months = False
        for r, seq in seqs:
            t = r["tags"]
            texts += [line_text(t), t.get("network")]
            mo = months_from_oh(t.get("opening_hours"))
            if mo:
                has_months = True
                months_all |= mo
            else:
                months_all |= set(range(1, 13))
            oh = (t.get("opening_hours") or "")
            if re.search(r"\bSH off\b", oh) and not re.search(r"\bSH\b(?! off)", oh):
                L["flags"].add("schooldays")
            hrs = [int(h) for h in re.findall(r"(?<!\d)(\d{2}):\d{2}", oh)]
            if hrs and all(h >= 21 or h <= 5 for h in hrs):
                L["flags"].add("night")
            if t.get("on_demand") == "yes":
                L["flags"].add("ondemand")
            if seq:
                add_pattern(cat, idx, seq, t.get("to"), "osm", frm=t.get("from"))
                n_routes += 1
        L["flags"] |= flags_from_text(*texts, mt.get("name"), mt.get("description"))
        if has_months:
            L["flags"] |= season_flags(months_all)
        if re.fullmatch(r"N\d{1,3}[A-Z]?", ref.replace(" ", "")) or ref.upper().startswith("NIGHT"):
            L["flags"].add("night")
        if t0.get("route") == "trolleybus":
            L["flags"].add("trolley")
        if mode == "coach":
            L["flags"].add("longdistance")
    report["osm"] = {"route_relations": len(osm["routes"]), "groups": len(groups), "routes_used": n_routes,
                     "skipped": dict(skipped), "member_mapping": dict(stats)}
    return osm


# ---------------------------------------------------------------------------------------------- GTFS
class GtfsSrc:
    def __init__(self, path):
        self.path = path
        self.zip = zipfile.ZipFile(path) if path.endswith(".zip") else None

    def has(self, name):
        if self.zip:
            return name in self.zip.namelist()
        return os.path.exists(os.path.join(self.path, name))

    def rows(self, name):
        if self.zip:
            f = io.TextIOWrapper(self.zip.open(name), encoding="utf-8-sig", newline="")
        else:
            f = open(os.path.join(self.path, name), encoding="utf-8-sig", newline="")
        yield from csv.DictReader(f)


def gtfs_service_months(g):
    """service_id -> set of months with service; plus feed span in days."""
    days = collections.defaultdict(set)
    dmin, dmax = None, None
    wd = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    def pd(s):
        return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))
    if g.has("calendar.txt"):
        for c in g.rows("calendar.txt"):
            a, b = pd(c["start_date"]), pd(c["end_date"])
            dmin = a if dmin is None or a < dmin else dmin
            dmax = b if dmax is None or b > dmax else dmax
            mask = [c[w] == "1" for w in wd]
            if not any(mask):
                continue
            d = a
            while d <= b:
                if mask[d.weekday()]:
                    days[c["service_id"]].add(d)
                d += dt.timedelta(days=1)
    if g.has("calendar_dates.txt"):
        for c in g.rows("calendar_dates.txt"):
            d = pd(c["date"])
            dmin = d if dmin is None or d < dmin else dmin
            dmax = d if dmax is None or d > dmax else dmax
            if c["exception_type"] == "1":
                days[c["service_id"]].add(d)
            else:
                days[c["service_id"]].discard(d)
    months = {sid: {d.month for d in ds} for sid, ds in days.items()}
    span = (dmax - dmin).days if dmin and dmax else 0
    return months, span


GTFS_RT = {"0": "tram", "1": "subway", "2": "rail", "3": "bus", "4": "ship", "5": "cable", "6": "cable", "7": "cable",
           "11": "trolleybus", "12": "rail", "100": "rail", "109": "sbahn", "200": "coach", "400": "subway",
           "700": "bus", "714": "sev", "715": "ondemand", "800": "trolleybus", "900": "tram", "1000": "ship",
           "1300": "cable", "1400": "cable", "1500": "ondemand", "1501": "ondemand"}
PUBLIC_RAIL_LINE = re.compile(r"^(S\d{1,3}[A-Z]?|R\d{1,3}|REX\d{1,3}|CJX\d{1,3}|SV\d+|U\d|RS\d{1,3}|ZB\d|L\d{1,2})$")


def components_of(items, stops_of):
    """Connected components of items that share at least one stop (union-find, deterministic order)."""
    parent = list(range(len(items)))

    def fnd(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    owner = {}
    for k, it in enumerate(items):
        for p in sorted(stops_of(it)):
            if p in owner:
                ra, rb = fnd(k), fnd(owner[p])
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
            else:
                owner[p] = k
    groups = collections.OrderedDict()
    for k, it in enumerate(items):
        groups.setdefault(fnd(k), []).append(it)
    return sorted(groups.values(), key=lambda g: -sum(len(stops_of(x)) for x in g))


def make_gtfs_line(cat, label, ag, rn, mode, rids, ci, routes, route_trips, trips, smonths, first_dep, seq, rep_w,
                   agency, span, places, unknown_stop):
    r0 = routes[rids[0]]
    short = (r0.get("route_short_name") or "").strip()
    op = agency.get(ag, None) or (next(iter(agency.values())) if len(agency) == 1 else None)
    months, hours = set(), []
    pats = collections.Counter()
    heads = {}
    names = collections.Counter()
    for rid in rids:
        names[routes[rid].get("route_long_name") or ""] += len(route_trips[rid])
        for tid in route_trips[rid]:
            months |= smonths.get(trips[tid]["service_id"], set())
            if tid in first_dep:
                hours.append(first_dep[tid])
            if tid not in seq:
                continue
            ids = tuple(p for _, p in sorted(seq[tid]) if p)
            if ids:
                pats[ids] += rep_w[tid]
                heads.setdefault(ids, (trips[tid].get("trip_headsign") or "").strip())
    if not pats:
        return 0
    lname = names.most_common(1)[0][0] or None
    key = f"gtfs:{label}:{ag}:{rn}:{mode}" + (f":{ci}" if ci else "")
    idx = cat.new_line(short, mode, None, op=op, name=lname, src=f"gtfs:{label}", key=key)
    L = cat.lines[idx]
    L["flags"] |= flags_from_text(lname if lname and not re.search(r"\d{2}\.\d{2}\.", lname) else None, short)
    if span >= 300:
        sf = season_flags(months)
        L["flags"] |= sf
        if not sf:
            L["gtfs_allyear"] = True
    if hours and sum(1 for h in hours if h >= 22 or h <= 4) >= 0.8 * len(hours):
        L["flags"].add("night")
    else:
        L["gtfs_not_night"] = True
    if mode == "sev":
        L["flags"].add("sev")
    states = collections.Counter()
    for ids, n in pats.items():
        keep = [p for p in ids if p in places]
        unknown_stop[label] += len(ids) - len(keep)
        for p in keep:
            states[places[p]["state"]] += 1
        add_pattern(cat, idx, keep, heads.get(ids) or None, f"gtfs:{label}", weight=n)
    # E3: network = Verbund of the majority of the line's stops (not of the single stop)
    main_state = next((s for s, _ in states.most_common() if s != "X"), None)
    L["net"] = "ÖBB" if label == "oebb" and mode in ("rail",) else net_code(None, op, main_state)
    return 1


def load_gtfs(cat, path, label, places, report, rail_products):
    g = GtfsSrc(path)
    agency = {a.get("agency_id", ""): a["agency_name"] for a in g.rows("agency.txt")}
    routes = {r["route_id"]: r for r in g.rows("routes.txt")}
    smonths, span = gtfs_service_months(g)
    trips = {}
    route_trips = collections.defaultdict(list)
    for t in g.rows("trips.txt"):
        trips[t["trip_id"]] = t
        route_trips[t["route_id"]].append(t["trip_id"])
    log(f"  gtfs {label}: {len(routes)} routes, {len(trips)} trips, calendar span {span} d")
    # representative trips: one per (route, shape, direction, headsign) when shapes exist, else every trip
    rep = set()
    rep_of = {}
    rep_w = collections.Counter()      # trips represented by each representative trip (termini weights)
    for tid, t in trips.items():
        if t.get("shape_id"):
            k = (t["route_id"], t["shape_id"], t.get("direction_id"), t.get("trip_headsign"))
            if k in rep_of:
                rep_w[rep_of[k]] += 1
                continue
            rep_of[k] = tid
        rep.add(tid)
        rep_w[tid] += 1
    rail_cat = {}
    for tid, t in trips.items():
        r = routes.get(t["route_id"]) or {}
        if GTFS_RT.get(r.get("route_type", "3"), "bus") in ("rail", "sbahn"):
            rail_cat[tid] = (t.get("trip_short_name") or "").split(" ")[0] or (r.get("route_short_name") or "")
    # stream stop_times; keep ordered parent ids of representative trips + first departure hour of every trip
    seq = collections.defaultdict(list)
    first_dep = {}
    nrows = 0
    intern = {}
    for st in g.rows("stop_times.txt"):
        nrows += 1
        tid = st["trip_id"]
        sid = st["stop_id"]
        pid = intern.get(sid)
        if pid is None:
            pid = intern[sid] = ifopt_parent(sid) or ""
        if tid in rep:
            seq[tid].append((int(st["stop_sequence"]), pid))
        c = rail_cat.get(tid)
        if c and pid in places:
            rail_products[pid].add(c)
        dtm = st.get("departure_time")
        if dtm:
            h = int(dtm[:dtm.index(":")])
            if h < first_dep.get(tid, 99):
                first_dep[tid] = h
    log(f"  gtfs {label}: {nrows} stop_times, {len(rep)} representative trips")
    used, unknown_stop = 0, collections.Counter()
    # group route_ids that are the same public line (WL/VOR feeds split a line into many dated route_ids)
    groups = collections.OrderedDict()
    for rid, tids in route_trips.items():
        r = routes.get(rid)
        if not r:
            continue
        short = (r.get("route_short_name") or "").strip()
        mode = GTFS_RT.get(r.get("route_type", "3"), "bus")
        if mode in ("rail", "sbahn"):
            nsp = short.replace(" ", "")
            if re.fullmatch(r"S\d{1,3}[A-Z]?", nsp):
                mode = "sbahn"
            if nsp.startswith("SV"):
                mode = "sev"
            if not PUBLIC_RAIL_LINE.match(nsp):
                continue   # internal ÖBB route names ("A11"); products were recorded per stop above
        elif not short:
            continue
        if short.upper().startswith("SEV"):
            mode = "sev"
        groups.setdefault((r.get("agency_id", ""), refnorm(short), mode), []).append(rid)
    for (ag, rn, mode), rids_all in groups.items():
        # E1: one public line number can be several lines (ÖBB R1 Linz and R1 Wiener Neustadt): split the route_ids
        # of the group into connected components of their stop patterns; each component is its own line
        rid_pats = {}
        for rid in rids_all:
            pr = collections.Counter()
            for tid in route_trips[rid]:
                if tid in seq:
                    ids = tuple(p for _, p in sorted(seq[tid]) if p)
                    if ids:
                        pr[ids] += 1
            rid_pats[rid] = pr
        comps = components_of(rids_all, lambda rid: {p for ids in rid_pats[rid] for p in ids if p in places})
        for ci, rids in enumerate(comps):
            used += make_gtfs_line(cat, label, ag, rn, mode, rids, ci, routes, route_trips, trips, smonths, first_dep,
                                   seq, rep_w, agency, span, places, unknown_stop)
    report.setdefault("gtfs", {})[label] = {"routes": len(routes), "trips": len(trips), "stop_times": nrows,
                                            "routes_used": used, "calendar_span_days": span,
                                            "stop_refs_not_in_places": unknown_stop[label]}


# ---------------------------------------------------------------------------------------------- Steiermark
STMK_TYP_MODE = [(re.compile(r"eisenbahn|bahn \(|s-bahn", re.I), "rail"), (re.compile(r"straßenbahn|tram", re.I), "tram"),
                 (re.compile(r"seilbahn", re.I), "cable"), (re.compile(r"schiff", re.I), "ship"),
                 (re.compile(r"rufbus|anruf|ast", re.I), "ondemand")]


def load_stmk(stops_base, lines_base):
    lines = {}
    if lines_base and os.path.exists(lines_base + ".dbf"):
        for r in read_dbf(lines_base + ".dbf"):
            if r["_deleted"]:
                continue
            lines[r["LINEDIVA"]] = {"ref": r["LINEEFA"], "typ": r["Typ"], "kat": r["Kategorie"], "stadt": r["Stadtverk"],
                                    "verbund": r["Verbund"]}
    out = {}
    if stops_base and os.path.exists(stops_base + ".dbf"):
        for r in read_dbf(stops_base + ".dbf"):
            if r["_deleted"]:
                continue
            pid = f"at:46:{int(float(r['HNR']))}"
            toks_ = []
            for code in [x.strip() for x in r["LINIE"].split(",") if x.strip()]:
                ln = lines.get(code)
                if ln:
                    ref = ln["ref"]
                    mode = next((m for rx, m in STMK_TYP_MODE if rx.search(ln["typ"] or "")), "bus")
                    if mode == "rail" and re.fullmatch(r"S\d+", ref or ""):
                        mode = "sbahn"
                    fl = set()
                    if "Saison" in (ln["kat"] or "") or "Schüler" in (ln["kat"] or ""):
                        fl.add("school_or_seasonal")
                    toks_.append((ref, mode, fl, ln["typ"]))
                else:
                    m = re.match(r"^\d{2}([0-9A-Z]+?)[_a-z]*$", code)
                    toks_.append((m.group(1).lstrip("0") if m else code, None, set(), None))
            out[pid] = {"tokens": toks_, "dep_week": int(float(r["MoFr_S"] or 0)), "name": r["HNAME_LANG"]}
    return out, len(lines)


# =============================================================================================
# main
# =============================================================================================
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
    ap.add_argument("--places", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--oevgk")
    ap.add_argument("--osm")
    ap.add_argument("--oebb-gtfs")
    ap.add_argument("--wl-gtfs")
    ap.add_argument("--gtfs", action="append", default=[], help="path[=label] of an extra GTFS feed (zip or dir)")
    ap.add_argument("--stmk-stops")
    ap.add_argument("--stmk-lines")
    ap.add_argument("--scotty-live")
    ap.add_argument("--attach-radius", type=float, default=4000.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    report = {"generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "inputs": {}}
    places = load_places(a.places)
    grid = Grid()
    for pid, p in places.items():
        grid.add(p["lat"], p["lon"], pid)
    cat = Catalog(places)
    rail_products = collections.defaultdict(set)
    for k in ("oevgk", "osm", "oebb_gtfs", "wl_gtfs", "stmk_stops", "stmk_lines"):
        v = getattr(a, k)
        if v:
            report["inputs"][k] = v
    report["inputs"]["gtfs"] = a.gtfs

    # 1 pattern sources: GTFS first (authoritative), then OSM ------------------------------------------
    feeds = []
    if a.oebb_gtfs:
        feeds.append((a.oebb_gtfs, "oebb"))
    if a.wl_gtfs:
        feeds.append((a.wl_gtfs, "wl"))
    for spec in a.gtfs:
        path, _, label = spec.partition("=")
        feeds.append((path, label or os.path.splitext(os.path.basename(path))[0]))
    for path, label in feeds:
        log(f"GTFS {label} …")
        load_gtfs(cat, path, label, places, report, rail_products)
    n_gtfs_lines = len(cat.lines)
    if a.osm:
        log("OSM routes …")
        load_osm(cat, a.osm, places, grid, report)

    # 1b dedupe pattern lines across sources/variants: same ref, compatible mode, sharing stops
    merged = 0
    for rn, idxs in list(cat.by_ref.items()):
        idxs = [i for i in idxs if cat.lines[i]["alive"]]
        idxs.sort(key=lambda i: (0 if any(s.startswith("gtfs") for s in cat.lines[i]["src"]) else 1, i))
        for x in range(len(idxs)):
            for y in range(x + 1, len(idxs)):
                i, j = cat.resolve(idxs[x]), cat.resolve(idxs[y])
                if i == j:
                    continue
                A, B = cat.lines[i], cat.lines[j]
                if not compat(A["mode"], B["mode"]):
                    continue
                inter = len(A["stops"] & B["stops"])
                if inter >= 2 and inter >= 0.3 * min(len(A["stops"]), len(B["stops"])):
                    cat.merge(i, j)
                    merged += 1
    report["dedupe_pattern_lines_merged"] = merged

    # 2 token sources: ÖV-GK (both reference days) + Steiermark ----------------------------------------
    tok_stats = collections.Counter()
    token_only = collections.defaultdict(list)   # (mode, rn) -> [(pid, ref, src, flags)]

    def attach(pid, ref, mode, src, flags=()):
        if pid not in places:
            tok_stats["stop_not_in_places"] += 1
            return
        rn = refnorm(ref)
        if not rn:
            return
        i, d, q = cat.find(rn, mode, pid, a.attach_radius)
        if i is None and re.fullmatch(r"[A-Z]{1,2}\d?", rn):
            # "A"/"B" in ÖV-GK/Stmk = "965A"/"965B" (Stadtbus Schladming) in OSM/HAFAS: same stop, ref suffix
            for full in sorted(k for k in cat.by_ref if k != rn and k.endswith(rn) and re.fullmatch(r"\d+", k[:-len(rn)] or "x")):
                j, dj, qj = cat.find(full, mode, pid, 2000)
                if j is not None:
                    i, d, q = j, dj, qj
                    tok_stats["suffix_alias"] += 1
                    break
        if i is not None:
            cat.serve(i, pid, src)
            cat.link(i, pid, q)
            cat.lines[i]["flags"] |= set(flags)
            tok_stats["confirmed" if d == 0 else "attached_nearby"] += 1
            return
        token_only[(mode, rn)].append((pid, ref, src, set(flags)))
        tok_stats["token_only"] += 1

    oev = load_oevgk(a.oevgk) if a.oevgk else {}
    report["oevgk_days"] = {d: len(v) for d, v in oev.items()}
    day_sets = collections.defaultdict(dict)
    for day, rows in oev.items():
        for pid, r in rows.items():
            for tok in r["lines"]:
                day_sets[pid].setdefault(tok, set()).add(day)
    for pid, toks_ in day_sets.items():
        if pid not in places:
            tok_stats["stop_not_in_places"] += 1
            continue
        for tok, days in toks_.items():
            mode = mode_from_token(tok, places[pid]["name"], places[pid]["state"])
            if tok.split(" ")[0] in GENERIC_RAIL and not (tok == "D" and places[pid]["state"] == "W"):
                rail_products[pid].add(tok)
                continue
            fl = set()
            if days == {"20251022"} and len(oev) == 2:
                fl.add("schooldays?")
            if tok in SCHOOL_TOKENS.get(places[pid]["state"], ()):
                fl.add("school")   # VVV "SK" = Schulkurs (verified live: dirTxt "Schulkurs 7")
            attach(pid, tok, mode, "oevgk", fl)
    if a.stmk_stops:
        stmk, n_stmk_lines = load_stmk(a.stmk_stops, a.stmk_lines)
        report["stmk"] = {"stops": len(stmk), "line_defs": n_stmk_lines}
        for pid, s in stmk.items():
            for ref, mode, fl, typ in s["tokens"]:
                if not ref:
                    continue
                if mode is None:
                    mode = mode_from_token(ref, places.get(pid, {}).get("name", ""), "ST")
                if mode in ("rail",) and ref.split(" ")[0] in GENERIC_RAIL:
                    rail_products[pid].add(ref)
                    continue
                attach(pid, ref, mode, "stmk", fl)
    # token-only lines: one line per (mode, ref) and geographic cluster (single linkage ≤ 12 km). E3: clusters are
    # not split at Verbund borders (110 Reutte – Warth); the network is the Verbund of the majority of the stops.
    n_tok_lines = 0
    cross_net = []
    for (mode, rn), items in token_only.items():
        pids = sorted({x[0] for x in items})
        parent = {p: p for p in pids}

        def fnd(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        g2 = Grid(0.1)
        for p in pids:
            g2.add(places[p]["lat"], places[p]["lon"], p)
        link_of = {}
        for p in pids:
            for d, q in g2.near(places[p]["lat"], places[p]["lon"], 12000):
                ra, rb = fnd(p), fnd(q)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
                    link_of.setdefault(p, q)
        clusters = collections.OrderedDict()
        for p in pids:
            clusters.setdefault(fnd(p), []).append(p)
        for root, members in clusters.items():
            mem = set(members)
            ref = next(x[1] for x in items if x[0] in mem)
            srcs = {x[2] for x in items if x[0] in mem}
            nets = collections.Counter(STATE_NET.get(places[p]["state"], "INT") for p in members)
            net = sorted(nets.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
            if len(nets) > 1:
                cross_net.append(f"{ref} {mode}: " + ", ".join(f"{k} {v}" for k, v in sorted(nets.items())))
            idx = cat.new_line(ref, mode, net, src=sorted(srcs)[0], key=f"tok:{mode}:{rn}:{root}")
            for x in items:
                if x[0] in mem:
                    cat.serve(idx, x[0], x[2])
                    cat.lines[idx]["flags"] |= x[3]
            for p in members:   # the cluster is one component of the stop graph
                cat.link(idx, p, link_of.get(p) or root)
            if mode == "sev":
                cat.lines[idx]["flags"].add("sev")
            if "school" in cat.lines[idx]["flags"] and rn == "SK":
                cat.lines[idx]["name"]["Schulkurs"] += 1
            n_tok_lines += 1
    report["token_matching"] = dict(tok_stats)
    report["token_only_lines"] = n_tok_lines
    report["token_only_cross_verbund"] = {"count": len(cross_net), "examples": cross_net[:40]}

    # 2a E1: every catalogue line is one connected component of its stop graph (termini then come from the component)
    report["component_split"] = split_components(cat)

    # 2b renumbering: an ÖV-GK-only line (10/2025) whose stops are (≥ 80 %) all served by OSM/GTFS lines that
    #    ÖV-GK does not list there is an old number (Kärnten and parts of Tirol renumbered at the Dec 2025 change)
    superseded = []
    for i, L in enumerate(cat.lines):
        if not L["alive"] or L["src"] != {"oevgk"} or not L["stops"] or not re.fullmatch(r"\d{3,4}[A-Z]?", L["rn"]):
            continue
        succ = collections.Counter()
        cov = 0
        for pid in L["stops"]:
            new_here = []
            for j, e in cat.stop_lines.get(pid, {}).items():
                j2 = cat.resolve(j)
                if j2 == i:
                    continue
                Lj = cat.lines[j2]
                if compat(Lj["mode"], L["mode"]) and ("oevgk" not in e["src"]) and \
                        (Lj["src"] & {"osm"} or any(x.startswith("gtfs") for x in Lj["src"])):
                    new_here.append(j2)
            if new_here:
                cov += 1
                succ.update(new_here)
        if cov >= 0.8 * len(L["stops"]):
            best = succ.most_common(1)[0][0]
            L["flags"].add("superseded")
            L["successor"] = best
            superseded.append(i)
    for i in superseded:
        for pid in list(cat.lines[i]["stops"]):
            cat.stop_lines[pid].pop(i, None)
    report["superseded_oevgk_numbers"] = {
        "count": len(superseded),
        "by_state": dict(collections.Counter(places[next(iter(cat.lines[i]["stops"]))]["state"] for i in superseded)),
        "examples": [f"{cat.lines[i]['ref']} → {cat.lines[cat.resolve(cat.lines[i]['successor'])]['ref']} "
                     f"({places[next(iter(cat.lines[i]['stops']))]['name']})" for i in superseded[:40]]}

    # 3 finalize ----------------------------------------------------------------------------------------
    alive = [i for i, L in enumerate(cat.lines) if L["alive"] and L["stops"]]
    new_idx = {i: k for k, i in enumerate(alive)}
    catalog = []
    for i in alive:
        L = cat.lines[i]
        flags = set(L["flags"])
        if L.get("gtfs_allyear"):
            flags -= {"winter", "summer", "seasonal", "ski_candidate"}
        if L.get("gtfs_not_night") and not re.fullmatch(r"N\d+[A-Z]?", L["rn"]):
            flags.discard("night")
        if "ski" in flags:
            flags.discard("summer")
        if L["src"] & {"oevgk"} and "winter" in flags:
            flags.discard("winter")   # runs on the October reference days → not winter-only (glacier ski buses keep "ski")
        # absent from both October reference days, OSM/GTFS-only, serving lift/ski infrastructure → probable ski bus
        if not (L["src"] & {"oevgk", "stmk"}) and "summer" not in flags and "ski" not in flags and L["mode"] == "bus" \
                and any(SKI_STOP_RX.search(places[p]["name"]) for p in L["stops"]) \
                and any(places[p]["state"] in ("T", "V", "S", "K", "ST", "OÖ", "NÖ") for p in L["stops"]):
            flags.add("ski_candidate")
        if "schooldays?" in flags and (any(s.startswith("gtfs") or s == "osm" for s in L["src"])):
            flags.discard("schooldays?")
        states = collections.Counter(places[p]["state"] for p in L["stops"])
        termini = [list(t) for t, _ in L["termini"].most_common(4)]
        catalog.append({"id": new_idx[i], "ref": L["ref"], "mode": L["mode"],
                        "net": L["net"] or STATE_NET.get(states.most_common(1)[0][0]),
                        "op": L["op"].most_common(1)[0][0] if L["op"] else None,
                        "name": L["name"].most_common(1)[0][0] if L["name"] else None,
                        "termini": termini, "flags": sorted(flags), "src": sorted(L["src"]),
                        "n_stops": len(L["stops"]), "states": [s for s, _ in states.most_common()]})
        if L.get("successor") is not None:
            catalog[-1]["successor"] = cat.resolve(L["successor"])
            # the stops the old number served (it is no longer in lines_by_stop): lets the v2 stage map an official
            # line to its superseded counterpart of the full build (LPAT flag patch, ENRICH_SPEC M4/AT-D8)
            catalog[-1]["stops_superseded"] = sorted(L["stops"])
    for c_ in catalog:
        if "successor" in c_:
            c_["successor"] = new_idx.get(c_["successor"])
    by_stop = {}
    AUTH = ("gtfs", "oevgk", "stmk")
    for pid in places:
        ent = []
        for i, e in cat.stop_lines.get(pid, {}).items():
            i = cat.resolve(i)
            if i not in new_idx:
                continue
            conf = 2 if any(s.startswith(AUTH) for s in e["src"]) else 1
            to = [t for t, _ in e["to"].most_common(3)]
            nx = sorted(e["nx"])[:6]
            ent.append([new_idx[i], to, nx, conf])
        # merge duplicates produced by merges
        dd = {}
        for li, to, nx, conf in ent:
            if li in dd:
                d0 = dd[li]
                d0[1] = list(dict.fromkeys(d0[1] + to))[:3]
                d0[2] = sorted(set(d0[2]) | set(nx))[:6]
                d0[3] = max(d0[3], conf)
            else:
                dd[li] = [li, to, nx, conf]
        ent = sorted(dd.values(), key=lambda x: (MODE_RANK.get(catalog[x[0]]["mode"], 99), natkey(catalog[x[0]]["ref"])))
        prods = sorted(rail_products.get(pid, ()), key=lambda c: (["RJX", "RJ", "ICE", "EC", "IC", "EN", "NJ", "D", "IR",
                                                                     "WB", "CJX", "REX", "R", "S"] + [c]).index(c))
        if ent or prods:
            by_stop[pid] = {"l": ent, "p": prods}
    patterns = []
    seen = set()
    for pt in cat.patterns:
        li = cat.resolve(pt["l"])
        if li not in new_idx:
            continue
        key = (new_idx[li], tuple(pt["s"]))
        if key in seen:
            continue
        seen.add(key)
        patterns.append({"l": new_idx[li], "to": pt["to"], "from": pt.get("from"), "s": pt["s"], "src": pt["src"]})

    json.dump({"lines": catalog, "net_names": NET_NAMES}, open(os.path.join(a.out, "lines_catalog.json"), "w",
                                                               encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    json.dump(by_stop, open(os.path.join(a.out, "lines_by_stop.json"), "w", encoding="utf-8"), ensure_ascii=False,
              separators=(",", ":"))
    json.dump(patterns, open(os.path.join(a.out, "lines_patterns.json"), "w", encoding="utf-8"), ensure_ascii=False,
              separators=(",", ":"))

    # 4 report ------------------------------------------------------------------------------------------
    rep_cov(report, places, by_stop, catalog, oev)
    if a.scotty_live:
        report["scotty_validation"] = validate_scotty(a.scotty_live, places, by_stop, catalog)
    report["sizes"] = {f: os.path.getsize(os.path.join(a.out, f)) for f in
                       ("lines_catalog.json", "lines_by_stop.json", "lines_patterns.json")}
    json.dump(report, open(os.path.join(a.out, "lines_report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(os.path.join(a.out, "LINES_ATTRIBUTION.txt"), "w", encoding="utf-8").write(ATTRIBUTION)
    log(json.dumps(report["coverage"]["total"], ensure_ascii=False))


def stop_mode(p):
    m = p["modes"]
    if m & (1 | 4 | 8 | 16 | 32 | 4096):
        return "rail"
    if m & 256:
        return "subway"
    if m & 512:
        return "tram"
    if m & 128:
        return "ship"
    if m & 2048:
        return "cable/ondemand"
    if m & 2:
        return "sev"
    return "bus"


def rep_cov(report, places, by_stop, catalog, oev):
    base_has = collections.Counter()
    tot = collections.Counter()
    has = collections.Counter()
    has_auth = collections.Counter()
    zero_dep = collections.Counter()
    zero_dep_has = collections.Counter()
    by_mode_tot, by_mode_has, by_mode_base = collections.Counter(), collections.Counter(), collections.Counter()
    lines_per_state = collections.defaultdict(set)
    ln_count = []
    for pid, p in places.items():
        st = p["state"]
        md = stop_mode(p)
        tot[st] += 1
        by_mode_tot[md] += 1
        b = bool(p["lines0"])
        base_has[st] += b
        by_mode_base[md] += b
        e = by_stop.get(pid)
        h = bool(e and (e["l"] or e["p"]))
        has[st] += h
        by_mode_has[md] += h
        if e and any(x[3] == 2 for x in e["l"]) or (e and e["p"]):
            has_auth[st] += 1
        if p["weight"] == 0:
            zero_dep[st] += 1
            zero_dep_has[st] += h
        if e:
            ln_count.append(len(e["l"]))
            for x in e["l"]:
                lines_per_state[st].add(x[0])
    pc = lambda a_, b_: round(100.0 * a_ / b_, 1) if b_ else None
    cov = {"by_state": {}, "by_mode": {}}
    for st in sorted(tot):
        cov["by_state"][st] = {"stops": tot[st], "pct_lines_before": pc(base_has[st], tot[st]),
                               "pct_lines_after": pc(has[st], tot[st]),
                               "pct_confirmed_timetable": pc(has_auth[st], tot[st]),
                               "zero_dep_stops": zero_dep[st], "pct_zero_dep_with_lines": pc(zero_dep_has[st], zero_dep[st]),
                               "distinct_lines": len(lines_per_state[st])}
    for md in sorted(by_mode_tot):
        cov["by_mode"][md] = {"stops": by_mode_tot[md], "pct_lines_before": pc(by_mode_base[md], by_mode_tot[md]),
                              "pct_lines_after": pc(by_mode_has[md], by_mode_tot[md])}
    T = sum(tot.values())
    cov["total"] = {"stops": T, "pct_lines_before": pc(sum(base_has.values()), T), "pct_lines_after": pc(sum(has.values()), T),
                    "pct_confirmed_timetable": pc(sum(has_auth.values()), T),
                    "zero_dep_stops": sum(zero_dep.values()), "pct_zero_dep_with_lines": pc(sum(zero_dep_has.values()), sum(zero_dep.values())),
                    "lines_in_catalog": len(catalog), "avg_lines_per_stop_with_lines": round(sum(ln_count) / max(1, len(ln_count)), 2)}
    fl = collections.Counter(f for L in catalog for f in L["flags"])
    cov["line_flags"] = dict(fl.most_common())
    cov["lines_by_src"] = dict(collections.Counter("+".join(L["src"]) for L in catalog).most_common(20))
    cov["lines_by_mode"] = dict(collections.Counter(L["mode"] for L in catalog).most_common())
    cov["lines_by_net"] = dict(collections.Counter(L["net"] for L in catalog).most_common())
    gaps = [pid for pid in places if pid not in by_stop]
    gstate = collections.Counter(places[p]["state"] for p in gaps)
    gw = collections.Counter("zero_dep" if places[p]["weight"] == 0 else "has_dep" for p in gaps)
    cov["residual_gaps"] = {"stops_without_any_line": len(gaps), "by_state": dict(gstate), "by_departures": dict(gw),
                            "examples": [places[p]["name"] for p in sorted(gaps, key=lambda p: -places[p]["weight"])[:40]]}
    report["coverage"] = cov


def validate_scotty(path, places, by_stop, catalog):
    raw = []
    for pth in path.split(","):
        if os.path.exists(pth):
            raw += json.load(open(pth, encoding="utf-8"))
    out = []
    agg = collections.Counter()
    for e in raw:
        if not e.get("days"):
            continue
        pid = e.get("id")
        live = {}
        for day, v in e["days"].items():
            for ln in v.get("lines", []):
                ref = (ln.get("line") or ln.get("nameS") or "").strip()
                cat_ = (ln.get("cat") or "").strip()
                cls = ln.get("cls") or 0
                if cls & (16 | 32) and re.fullmatch(r"\d{1,3}", ref):
                    key = ("L", refnorm(("S" if cls & 32 else cat_.upper()) + ref))
                elif cat_ in GENERIC_RAIL or cls & (1 | 4 | 8 | 16 | 4096):
                    key = ("P", cat_)
                else:
                    key = ("L", refnorm(ref))
                live.setdefault(key, set()).add(day)
        ours = set()
        if pid and pid in by_stop:
            for li, *_ in by_stop[pid]["l"]:
                ours.add(("L", refnorm(catalog[li]["ref"])))
            for pr in by_stop[pid]["p"]:
                ours.add(("P", pr))
        live_l = {k for k in live if k[0] == "L"}
        ours_l = {k for k in ours if k[0] == "L"}
        if not pid or pid not in places:
            continue
        for day in e["days"]:
            ld = {k for k in live_l if day in live[k]}
            agg[f"{day}_live"] += len(ld)
            agg[f"{day}_found"] += len(ld & ours_l)
            agg[f"{day}_found_before"] += len({k for k in ld if k[1] in {refnorm(x) for x in places[pid]["lines0"].split(",") if x}})
        miss = sorted(k[1] for k in live_l - ours_l)
        extra = sorted(k[1] for k in ours_l - live_l)
        agg["live_lines"] += len(live_l)
        agg["found"] += len(live_l & ours_l)
        agg["ours_lines"] += len(ours_l)
        out.append({"id": pid, "name": e.get("name"), "hafas": (e.get("hafas") or {}).get("name"),
                    "live": sorted(k[1] for k in live_l), "ours": sorted(k[1] for k in ours_l),
                    "missing": miss, "extra_not_live": extra,
                    "before": places[pid]["lines0"] if pid in places else None})
    agg_out = dict(agg)
    agg_out["recall_pct"] = round(100.0 * agg["found"] / max(1, agg["live_lines"]), 1)
    for k in list(agg):
        if k.endswith("_live"):
            day = k[:-5]
            agg_out[f"{day}_recall_pct"] = round(100.0 * agg[f"{day}_found"] / max(1, agg[k]), 1)
            agg_out[f"{day}_recall_before_pct"] = round(100.0 * agg[f"{day}_found_before"] / max(1, agg[k]), 1)
    return {"summary": agg_out, "stops": out}


ATTRIBUTION = """Linien je Haltestelle (lines_*.json) – Datenquellen und Lizenzen
• Linienliste je Haltestelle (Stichtage 22.10.2025 Werktag, 29.10.2025 Herbstferien): ÖV-Güteklassen 2025_revised,
  ÖROK / BMIMI / AustriaTech, https://www.mobilitydata.gv.at/daten/öv-güteklassen – Daten: Mobilitätsverbünde Österreich OG
  (Haltestellen-WFS 10/2025) und VAO-Fahrplanabfrage. Verändert (zusammengeführt).
  ACHTUNG: Lizenzmodell lt. mobilitydata.gv.at „Kein(e) Lizenz und kein Vertrag“ (nur Haftungsausschluss, ÖROK) –
  vor Auslieferung in der App schriftliche Freigabe bei AustriaTech/ÖROK einholen ODER durch die Verbund-GTFS von
  data.mobilitaetsverbuende.at (Datenlizenz MVO v1.1) ersetzen (build_lines.py --gtfs …, ohne --oevgk).
• Linienverläufe, Liniennamen, Betreiber, Netze, Saison-Hinweise: © OpenStreetMap-Mitwirkende, ODbL 1.0
  (https://www.openstreetmap.org/copyright). lines_*.json enthalten OSM-Daten und sind eine abgeleitete Datenbank
  unter ODbL 1.0 (Share-Alike: die Datenbank selbst muss unter ODbL weitergegeben werden; die App bleibt frei lizenzierbar).
• Bahn: ÖBB-Personenverkehr AG, Soll-Fahrplan GTFS 2026, CC BY 4.0 (https://data.oebb.at). Verändert.
• Wien: Stadt Wien – data.wien.gv.at, Wiener Linien Fahrplandaten GTFS, CC BY 4.0. Verändert.
• Steiermark: Land Steiermark – data.steiermark.gv.at, „Haltestellen des Verkehrsverbundes Steiermark“ und
  „Linienverkehr des Verkehrsverbundes Steiermark“, CC BY 4.0. Verändert.
• Falls eingebunden (--gtfs): Datenquelle: Mobilitätsverbünde Österreich OG, Datenlizenz Mobilitätsverbünde Österreich v1.1
  (https://data.mobilitaetsverbuende.at); verändert (Linien je Haltestelle abgeleitet). Keine Gewähr.
• Netz- und Betreibernamen werden nur als Text genannt; es werden keine Logos oder Wappen verwendet.
"""

if __name__ == "__main__":
    main()
