#!/usr/bin/env python3
"""Builds App/Resources/relations.json (exact ÖBB Standard-Ticket prices between stations) from
data/oebb_relation_prices.json (official ÖBB Relationspreise tables) and App/Resources/stations.json.
Tariff points are mapped to bundled stations by coordinates (≤ 1.5 km) or by normalized name."""
import json, math, os, re, unicodedata

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

def main():
    src = json.load(open(os.path.join(ROOT, "data", "oebb_relation_prices.json"), encoding="utf-8"))
    stations = json.load(open(os.path.join(ROOT, "App", "Resources", "stations.json"), encoding="utf-8"))
    rail = [s for s in stations if s.get("kind", "rail") == "rail"]
    by_name = {}
    for s in rail:
        by_name.setdefault(norm(s["name"]), s)
    coords = src.get("station_coords_osm", {})

    def resolve(name):
        key = norm(name)
        if key in ALIASES:
            hit = by_name.get(norm(ALIASES[key]))
            if hit: return hit
        c = coords.get(name)
        if c:
            best = min(rail, key=lambda s: hav(c, (s["lat"], s["lon"])))
            if hav(c, (best["lat"], best["lon"])) <= 1.5:
                return best
        if key in by_name: return by_name[key]
        cands = [s for k, s in by_name.items() if k.startswith(key + " ") or key.startswith(k + " ")]
        return max(cands, key=lambda s: s.get("importance", 0)) if cands else None

    points, index, prices, unresolved = [], {}, {}, set()
    def idx(name):
        if name in index: return index[name]
        st = resolve(name)
        if not st:
            unresolved.add(name); index[name] = None; return None
        # several tariff names can map to one station; keep one point per station
        for i, p in enumerate(points):
            if p["stationID"] == st["id"]:
                index[name] = i; return i
        points.append({"name": name, "stationID": st["id"]})
        index[name] = len(points) - 1
        return index[name]

    for origin, dests in src["relations"].items():
        o = idx(origin)
        if o is None: continue
        for dest, v in dests.items():
            d = idx(dest)
            if d is None or d == o or not v.get("p2"): continue
            key = (min(o, d), max(o, d))
            cents = int(round(v["p2"] * 100))
            prices[key] = min(cents, prices.get(key, cents))
    out = {"validFrom": src.get("valid_from", ""), "source": src.get("source_url", ""), "points": points,
           "prices": [[a, b, c] for (a, b), c in sorted(prices.items())]}
    path = os.path.join(ROOT, "App", "Resources", "relations.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"relations: {len(prices)} pairs, {len(points)} points, unresolved {len(unresolved)}: {sorted(unresolved)[:25]}")

if __name__ == "__main__":
    main()
