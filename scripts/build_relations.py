#!/usr/bin/env python3
"""Builds the exact ÖBB price table bundled in the app:
  App/Resources/relations-points.json  – tariff points mapped to bundled station IDs
  App/Resources/relations.bin          – raw-DEFLATE compressed little-endian UInt16 triples (pointA, pointB, price in 10-cent units)
Sources: data/oebb_relation_prices.json (33 major origins, always) and, if present, the full parsed table
(pairs_all.json from the research step, 210k pairs, path via $PAIRS_ALL). Points are matched to stations by
coordinates (≤ 1.2 km) or name. Prices are symmetric; the cheapest variant wins."""
import json, math, os, re, struct, sys, unicodedata, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def norm(s):
    s = s.lower().replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.replace("hauptbahnhof", "hbf").replace("bahnhof", "bf").replace("sankt ", "st ").replace("st.", "st ")
    s = re.sub(r"\(gr\)|bahnhst\.?|haltestelle", " ", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(s.split())

def hav(a, b):
    r = 6371.0
    dlat = math.radians(b[0] - a[0]); dlon = math.radians(b[1] - a[1])
    x = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlon / 2) ** 2
    return 2 * r * math.atan2(math.sqrt(x), math.sqrt(1 - x))

ALIASES = {"wien": "Wien Hauptbahnhof", "graz": "Graz Hauptbahnhof", "linz": "Linz Hauptbahnhof", "salzburg": "Salzburg Hauptbahnhof",
           "innsbruck": "Innsbruck Hauptbahnhof", "st poelten": "St. Pölten Hauptbahnhof", "klagenfurt": "Klagenfurt Hauptbahnhof",
           "villach": "Villach Hauptbahnhof", "wels": "Wels Hauptbahnhof"}

class Resolver:
    def __init__(self, stations, meta):
        self.rail = [s for s in stations if s.get("kind", "rail") == "rail"]
        self.by_name = {}
        for s in self.rail:
            self.by_name.setdefault(norm(s["name"]), s)
        ids = {s["id"]: s for s in self.rail}
        for sid, m in meta.items():
            if sid in ids:
                for alias in m.get("aliases") or []:
                    self.by_name.setdefault(norm(alias), ids[sid])
        # coarse grid for nearest lookup
        self.grid = {}
        for s in self.rail:
            self.grid.setdefault((round(s["lat"], 1), round(s["lon"], 1)), []).append(s)
        self.cache = {}

    def nearest(self, ll, max_km=1.2):
        best, bd = None, max_km
        la, lo = round(ll[0], 1), round(ll[1], 1)
        for dla in (-0.1, 0, 0.1):
            for dlo in (-0.1, 0, 0.1):
                for s in self.grid.get((round(la + dla, 1), round(lo + dlo, 1)), []):
                    d = hav(ll, (s["lat"], s["lon"]))
                    if d < bd: best, bd = s, d
        return best

    def resolve(self, name, ll=None):
        key = (name, tuple(ll) if ll else None)
        if key in self.cache: return self.cache[key]
        n = norm(name)
        hit = None
        if n in ALIASES: hit = self.by_name.get(norm(ALIASES[n]))
        if not hit and ll: hit = self.nearest(ll)
        if not hit: hit = self.by_name.get(n)
        if not hit:
            q = [t.rstrip(".") for t in re.split(r"[ /\-]+", n) if len(t.rstrip(".")) >= 3]
            cands = [s for k, s in self.by_name.items() if q and all(any(w.startswith(t) for w in k.split()) for t in q) and k.split()[0].startswith(q[0])]
            hit = max(cands, key=lambda s: s.get("importance", 0)) if cands else None
        self.cache[key] = hit
        return hit

def main():
    stations = json.load(open(os.path.join(ROOT, "App", "Resources", "stations.json"), encoding="utf-8"))
    meta_path = os.path.join(ROOT, "data", "stations_meta.json")
    meta = json.load(open(meta_path, encoding="utf-8")).get("stations", {}) if os.path.exists(meta_path) else {}
    R = Resolver(stations, meta)
    major = json.load(open(os.path.join(ROOT, "data", "oebb_relation_prices.json"), encoding="utf-8"))
    coords = major.get("station_coords_osm", {})

    prices = {}
    unresolved = set()
    def add(a_name, a_ll, b_name, b_ll, eur):
        if not eur: return
        a = R.resolve(a_name, a_ll); b = R.resolve(b_name, b_ll)
        if not a: unresolved.add(a_name); return
        if not b: unresolved.add(b_name); return
        if a["id"] == b["id"]: return
        k = (a["id"], b["id"]) if a["id"] < b["id"] else (b["id"], a["id"])
        v = int(round(float(eur) * 10))
        prices[k] = min(v, prices.get(k, v))

    for origin, dests in major["relations"].items():
        for dest, v in dests.items():
            add(origin, coords.get(origin), dest, coords.get(dest), v.get("p2"))
    pairs_path = os.environ.get("PAIRS_ALL")
    if pairs_path and os.path.exists(pairs_path):
        for row in json.load(open(pairs_path, encoding="utf-8")):
            add(row["von"], row.get("from_ll"), row["nach"], row.get("to_ll"), row.get("price_online_000"))

    ids = sorted({i for k in prices for i in k})
    index = {sid: n for n, sid in enumerate(ids)}
    names = {s["id"]: s["name"] for s in stations}
    points = [{"name": names.get(sid, sid), "stationID": sid} for sid in ids]
    blob = bytearray()
    for (a, b), v in sorted(prices.items()):
        blob += struct.pack("<HHH", index[a], index[b], min(v, 65535))
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = comp.compress(bytes(blob)) + comp.flush()
    res = os.path.join(ROOT, "App", "Resources")
    with open(os.path.join(res, "relations-points.json"), "w", encoding="utf-8") as f:
        json.dump({"validFrom": major.get("valid_from", ""), "source": major.get("source_url", ""), "points": points},
                  f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(res, "relations.bin"), "wb") as f:
        f.write(packed)
    old = os.path.join(res, "relations.json")
    if os.path.exists(old): os.remove(old)
    print(f"relations: {len(prices)} pairs, {len(points)} points, {len(packed)/1024:.0f} KB compressed; unresolved names: {len(unresolved)}")

if __name__ == "__main__":
    main()
