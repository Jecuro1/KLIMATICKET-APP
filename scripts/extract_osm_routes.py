#!/usr/bin/env python3
"""Extract every public-transport route relation of an OSM PBF (+ route_masters, stop_area
relations and the coordinates/names of all member stops) into one JSON file.

Only step of the lines pipeline that needs a non-stdlib module (pyosmium >= 4).
The same content can be fetched from Overpass API with OVERPASS_QUERY (out body; >;  out skel qt;).

Usage: python extract_osm_routes.py <austria.osm.pbf> <out osm_routes.json>
"""
import json
import sys
import time

import osmium

ROUTE_TYPES = {"bus", "trolleybus", "tram", "train", "light_rail", "subway", "monorail", "ferry",
               "share_taxi", "funicular", "aerialway", "coach", "minibus", "railway"}
KEEP_ROUTE = {"type", "route", "route_master", "ref", "name", "from", "to", "via", "operator", "network",
              "network:short", "network:wikidata", "operator:wikidata", "colour", "public_transport:version",
              "opening_hours", "interval", "duration", "seasonal", "service", "bus", "school", "night",
              "description", "note", "fixme", "disused", "ref:VAO", "ref:vvt", "ref:at:vvt", "ref:VVT",
              "ref:VOR", "ref:SVV", "ref:OOEVV", "ref:VVK", "ref:VVV", "ref:VVNB", "ref:VVSt", "ref_trips",
              "website", "wikidata", "on_demand", "charge", "fee", "official_name", "alt_name", "name:de",
              "ski", "piste:type", "line", "gtfs:route_id", "gtfs:shape_id", "ref:IFOPT", "trolley_wire",
              "aerialway"}
OVERPASS_QUERY = r"""
[out:json][timeout:1800];
area["ISO3166-1"="AT"][admin_level=2]->.a;
( relation(area.a)["type"="route"]["route"~"^(bus|trolleybus|tram|train|light_rail|subway|monorail|ferry|share_taxi|funicular|coach|minibus)$"];
  relation(area.a)["type"="route_master"];
  relation(area.a)["public_transport"="stop_area"]; );
out body; >; out skel qt;
"""


class RelPass(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.routes, self.masters, self.areas = [], [], []
        self.need_nodes, self.need_ways = set(), set()

    def relation(self, r):
        t = r.tags
        typ = t.get("type")
        if typ == "route" and (t.get("route") in ROUTE_TYPES):
            mem = []
            for m in r.members:
                role = m.role or ""
                if m.type == "n":
                    mem.append(("n", m.ref, role))
                    self.need_nodes.add(m.ref)
                elif m.type == "w" and (role.startswith("platform") or role.startswith("stop")):
                    mem.append(("w", m.ref, role))
                    self.need_ways.add(m.ref)
                elif m.type == "w":
                    mem.append(("w", m.ref, role or "track"))   # track ways: kept as id only (geometry optional)
            self.routes.append({"id": r.id, "tags": {k.k: k.v for k in t if k.k in KEEP_ROUTE or k.k.startswith("ref")},
                                "members": mem})
        elif typ == "route_master":
            self.masters.append({"id": r.id, "tags": {k.k: k.v for k in t if k.k in KEEP_ROUTE or k.k.startswith("ref")},
                                 "members": [m.ref for m in r.members if m.type == "r"]})
        elif t.get("public_transport") == "stop_area":
            mem = [(m.type, m.ref, m.role or "") for m in r.members if m.type in ("n", "w")]
            for ty, ref, _ in mem:
                (self.need_nodes if ty == "n" else self.need_ways).add(ref)
            self.areas.append({"id": r.id, "tags": {k.k: k.v for k in t if k.k in ("name", "ref:IFOPT", "network",
                                                                                     "operator", "public_transport")},
                               "members": mem})


STOP_KEEP = ("name", "official_name", "alt_name", "short_name", "ref:IFOPT", "public_transport", "highway",
             "railway", "bus", "tram", "train", "network", "operator", "route_ref", "local_ref", "uic_ref",
             "amenity", "aerialway")


class WayPass(osmium.SimpleHandler):
    def __init__(self, need):
        super().__init__()
        self.need, self.ways = need, {}

    def way(self, w):
        if w.id in self.need:
            self.ways[w.id] = {"nodes": [n.ref for n in w.nodes],
                               "tags": {k.k: k.v for k in w.tags if k.k in STOP_KEEP}}


class NodePass(osmium.SimpleHandler):
    def __init__(self, need, need_geom):
        super().__init__()
        self.need, self.need_geom = need, need_geom
        self.nodes, self.geom = {}, {}

    def node(self, n):
        i = n.id
        if i in self.need:
            self.nodes[i] = {"lat": round(n.location.lat, 7), "lon": round(n.location.lon, 7),
                             "tags": {k.k: k.v for k in n.tags if k.k in STOP_KEEP}}
        elif i in self.need_geom:
            self.geom[i] = (round(n.location.lat, 7), round(n.location.lon, 7))


def main():
    pbf, out = sys.argv[1], sys.argv[2]
    t0 = time.time()
    rp = RelPass()
    rp.apply_file(pbf)
    print(f"relations: {len(rp.routes)} routes, {len(rp.masters)} masters, {len(rp.areas)} stop_areas "
          f"({time.time()-t0:.0f}s)", file=sys.stderr)
    wp = WayPass(rp.need_ways)
    wp.apply_file(pbf)
    geom_nodes = {n for w in wp.ways.values() for n in w["nodes"]}
    print(f"ways: {len(wp.ways)} ({time.time()-t0:.0f}s)", file=sys.stderr)
    np_ = NodePass(rp.need_nodes, geom_nodes - rp.need_nodes)
    np_.apply_file(pbf)
    print(f"nodes: {len(np_.nodes)} ({time.time()-t0:.0f}s)", file=sys.stderr)
    ways = {}
    for wid, w in wp.ways.items():
        pts = [np_.geom.get(n) or ((np_.nodes[n]["lat"], np_.nodes[n]["lon"]) if n in np_.nodes else None)
               for n in w["nodes"]]
        pts = [p for p in pts if p]
        if not pts:
            continue
        ways[wid] = {"lat": round(sum(p[0] for p in pts) / len(pts), 7),
                     "lon": round(sum(p[1] for p in pts) / len(pts), 7), "tags": w["tags"]}
    nodes = {i: v for i, v in np_.nodes.items() if v["tags"] or True}
    json.dump({"generator": "extract_osm_routes.py (pyosmium)",
               "copyright": "© OpenStreetMap contributors, ODbL 1.0",
               "routes": rp.routes, "route_masters": rp.masters, "stop_areas": rp.areas,
               "nodes": {str(k): v for k, v in nodes.items()}, "ways": {str(k): v for k, v in ways.items()}},
              open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print(f"done {time.time()-t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
