"""Extract all public-transport stops (+ stop_area relations + named places) from an
OSM PBF into an Overpass-API-compatible JSON file ({"elements": [...]}).

This is the ONLY step that needs a non-stdlib module (pyosmium). The same file can be
obtained without pyosmium from Overpass API with the query in OVERPASS_QUERY below
(`out tags center;` gives the same element shape: nodes lat/lon, ways/relations center).

Usage: python -I extract_osm_places.py <austria-latest.osm.pbf> <out.json>
"""
import json
import sys

import osmium

OVERPASS_QUERY = r"""
[out:json][timeout:900];
area["ISO3166-1"="AT"][admin_level=2]->.a;
(
  nwr(area.a)["public_transport"~"^(platform|stop_position|station)$"];
  nwr(area.a)["highway"="bus_stop"];
  nwr(area.a)["railway"~"^(station|halt|tram_stop|stop|platform)$"];
  nwr(area.a)["amenity"~"^(ferry_terminal|bus_station)$"];
  nwr(area.a)["aerialway"="station"];
  relation(area.a)["public_transport"="stop_area"];
  node(area.a)["place"~"^(city|town|village|hamlet|suburb|quarter|neighbourhood|locality|isolated_dwelling)$"]["name"];
);
out tags center;
"""

KEEP = {
    "name", "official_name", "alt_name", "short_name", "loc_name", "old_name", "name:de",
    "ref:IFOPT", "ref", "local_ref", "uic_ref", "uic_name", "railway:ref", "ref:at:vvt",
    "public_transport", "highway", "railway", "amenity", "aerialway", "station", "place",
    "bus", "tram", "train", "subway", "light_rail", "monorail", "ferry", "trolleybus",
    "share_taxi", "funicular", "coach", "network", "operator", "population",
    "disused", "abandoned", "construction", "usage", "passenger", "railway:historic",
    "historic", "tourism", "access", "level", "wikidata",
}
LIFE = ("disused:", "abandoned:", "razed:", "construction:", "proposed:", "was:",
        "removed:", "demolished:", "planned:")
PLACES = {"city", "town", "village", "hamlet", "suburb", "quarter", "neighbourhood",
          "locality", "isolated_dwelling"}


def wanted(t):
    if t.get("public_transport") in ("platform", "stop_position", "station"):
        return True
    if t.get("highway") == "bus_stop":
        return True
    if t.get("railway") in ("station", "halt", "tram_stop", "stop", "platform"):
        return True
    if t.get("amenity") in ("ferry_terminal", "bus_station"):
        return True
    if t.get("aerialway") == "station":
        return True
    return False


def slim(t):
    out = {k: v for k, v in t.items() if k in KEEP}
    for k in t:
        if k.startswith(LIFE):
            out[k] = t[k]
    return out


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.el = []
        self.rel_members = {}

    def node(self, n):
        if not len(n.tags):
            return
        t = {x.k: x.v for x in n.tags}
        is_place = t.get("place") in PLACES and "name" in t
        if not (wanted(t) or is_place):
            return
        if not n.location.valid():
            return
        self.el.append({"type": "node", "id": n.id, "lat": round(n.location.lat, 7),
                        "lon": round(n.location.lon, 7), "tags": slim(t)})

    def way(self, w):
        if not len(w.tags):
            return
        t = {x.k: x.v for x in w.tags}
        if not wanted(t):
            return
        pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
        if not pts:
            return
        lat = sum(p[0] for p in pts) / len(pts)
        lon = sum(p[1] for p in pts) / len(pts)
        self.el.append({"type": "way", "id": w.id, "center": {"lat": round(lat, 7), "lon": round(lon, 7)},
                        "tags": slim(t)})

    def relation(self, r):
        t = {x.k: x.v for x in r.tags}
        if t.get("type") == "public_transport" and t.get("public_transport") == "stop_area" or \
                t.get("public_transport") == "stop_area":
            self.el.append({"type": "relation", "id": r.id, "tags": slim(t),
                            "members": [{"type": {"n": "node", "w": "way", "r": "relation"}[m.type],
                                         "ref": m.ref, "role": m.role} for m in r.members]})


if __name__ == "__main__":
    h = H()
    h.apply_file(sys.argv[1], locations=True, idx="flex_mem")
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump({"version": 0.6, "generator": "extract_osm_places.py (pyosmium)",
                   "osm3s": {"copyright": "The data included in this document is from www.openstreetmap.org. "
                                          "The data is made available under ODbL."},
                   "elements": h.el}, f, ensure_ascii=False)
    print(len(h.el), "elements", file=sys.stderr)
