"""Extract everything the stop-tagging step needs from an Austria OSM PBF into one JSON file.

Needs pyosmium + shapely (venv). Everything downstream (build_tags.py) is stdlib + shapely.

Collected:
  pt        public-transport nodes (stops/platforms/stations/aerialway stations) with the few tags
            we need (name, wheelchair, route_ref, network, operator, mode keys, ele)
  ptw       PT platform ways (centre only) - needed to place route members
  lifts     aerialway ways (+ railway=funicular): endpoints (first node = valley, OSM draws lifts uphill),
            name, type
  pistes    piste:type ways: subsampled coordinates, name, type, difficulty
  areas     landuse=winter_sports, natural=glacier, hospital, university/college, shop=mall,
            aeroway=aerodrome, P+R parking, B+R bicycle parking, boundary=tourism|national_park,
            protected_area class 2 (national parks), place=region polygons - simplified geometry
  pois      the same POI kinds when mapped as nodes
  routes    route relations (bus/tram/train/ferry/aerialway...) with tags + member stop coordinates
  masters   route_master relations
  sites     type=site (site=piste) relations with member way ids
  admin     boundary=administrative relation tags (admin_level 4/6/7/8) - names + ref:at:gkz
Usage: python extract_osm_tags.py <austria.osm.pbf> <out.json>
"""
import json
import sys
import time

import osmium
from shapely import wkb as swkb

LIFT_TYPES = {"cable_car", "gondola", "mixed_lift", "chair_lift", "drag_lift", "t-bar", "j-bar", "platter",
              "rope_tow", "magic_carpet"}
ROUTE_TYPES = {"bus", "trolleybus", "tram", "train", "light_rail", "subway", "ferry", "aerialway", "funicular",
               "share_taxi", "coach", "monorail", "railway"}
PT_KEEP = ("name", "official_name", "alt_name", "wheelchair", "route_ref", "network", "operator",
           "public_transport", "highway", "railway", "amenity", "aerialway", "bus", "tram", "train", "ferry",
           "ref:IFOPT", "ele", "tactile_paving", "shelter", "departures_board", "station", "aerialway:access",
           "seasonal", "opening_hours", "bench")
ROUTE_KEEP = ("name", "ref", "network", "operator", "from", "to", "via", "description", "route", "bus",
              "tourism", "seasonal", "opening_hours", "interval", "note", "official_name", "wikidata",
              "public_transport:version", "colour", "night", "school", "service")


def slim(tags, keep):
    return {k: tags[k] for k in keep if k in tags}


def poi_kind(t):
    a = t.get("amenity")
    if a == "hospital" or t.get("healthcare") == "hospital":
        return "hospital"
    if a in ("university", "college"):
        return a
    if t.get("shop") == "mall":
        return "mall"
    if t.get("aeroway") == "aerodrome":
        return "aerodrome"
    if a == "parking" and t.get("park_ride", "no") not in ("no", ""):
        return "park_ride"
    if a == "bicycle_parking" and (t.get("bike_ride") == "yes" or t.get("bicycle_parking:bike_ride") == "yes"):
        return "bike_ride"
    if a == "ferry_terminal":
        return "ferry_terminal"
    if t.get("tourism") == "alpine_hut":
        return "alpine_hut"
    return None


def area_kind(t):
    k = poi_kind(t)
    if k and k not in ("ferry_terminal",):
        return k
    if t.get("landuse") == "winter_sports":
        return "winter_sports"
    if t.get("natural") == "glacier":
        return "glacier"
    b = t.get("boundary")
    if b in ("tourism", "national_park"):
        return b
    if b == "protected_area" and t.get("protect_class") == "2":
        return "national_park"
    if t.get("place") == "region" or b == "region":
        return "region"
    return None


AREA_TAGS = ("name", "official_name", "alt_name", "short_name", "operator", "network", "iata", "icao",
             "aerodrome:type", "aerodrome", "wikidata", "website", "landuse", "natural", "boundary", "amenity",
             "shop", "park_ride", "bike_ride", "capacity", "protect_class", "place", "type", "site",
             "healthcare", "emergency", "ele", "description", "operator:wikidata", "ski", "piste:type",
             "ref", "brand", "wheelchair")


def main(src, dst):
    t0 = time.time()
    fab = osmium.geom.WKBFactory()
    out = {"pt": {}, "ptw": {}, "lifts": [], "pistes": [], "areas": [], "pois": [], "routes": [],
           "masters": [], "sites": [], "admin": []}
    pt = out["pt"]
    ptw = out["ptw"]
    piste_ways = {}
    keys = osmium.filter.KeyFilter("public_transport", "highway", "railway", "amenity", "aerialway", "aeroway",
                                   "shop", "healthcare", "piste:type", "route", "boundary", "site", "landuse",
                                   "natural", "type", "tourism", "park_ride", "bike_ride", "place")
    fp = (osmium.FileProcessor(src).with_locations("flex_mem")
          .with_areas(osmium.filter.KeyFilter("landuse", "natural", "amenity", "shop", "aeroway", "boundary",
                                              "healthcare", "place", "tourism"))
          .with_filter(keys))
    n = 0
    for o in fp:
        n += 1
        if n % 2_000_000 == 0:
            print(f"{n:,} objects {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
        t = dict(o.tags)
        if o.is_area():
            k = area_kind(t)
            if not k:
                continue
            try:
                g = swkb.loads(fab.create_multipolygon(o), hex=True)
            except Exception:
                continue
            if g.is_empty:
                continue
            tol = 0.0004 if k in ("tourism", "national_park", "region") else 0.00008
            area_deg = g.area
            gs = g.simplify(tol, preserve_topology=True)
            if k == "glacier" and area_deg < 2e-6:   # < ~0.015 km2 - irrelevant
                continue
            c = g.representative_point()
            out["areas"].append({"kind": k, "osm": ("w" if o.from_way() else "r") + str(o.orig_id()),
                                 "tags": slim(t, AREA_TAGS), "lat": round(c.y, 6), "lon": round(c.x, 6),
                                 "bbox": [round(v, 5) for v in g.bounds],
                                 "geom": json.loads(json.dumps(gs.__geo_interface__)),
                                 "area_deg": area_deg})
            continue
        if isinstance(o, osmium.osm.Node):
            loc = o.location
            if not loc.valid():
                continue
            is_pt = (t.get("public_transport") in ("platform", "stop_position", "station")
                     or t.get("highway") == "bus_stop"
                     or t.get("railway") in ("station", "halt", "tram_stop", "stop", "platform")
                     or t.get("amenity") in ("bus_station", "ferry_terminal")
                     or t.get("aerialway") == "station")
            if is_pt:
                pt[o.id] = [round(loc.lat, 7), round(loc.lon, 7), slim(t, PT_KEEP)]
            k = poi_kind(t)
            if k:
                out["pois"].append({"kind": k, "osm": "n" + str(o.id), "lat": round(loc.lat, 7),
                                    "lon": round(loc.lon, 7), "tags": slim(t, AREA_TAGS)})
        elif isinstance(o, osmium.osm.Way):
            aw = t.get("aerialway")
            if aw in LIFT_TYPES or t.get("railway") == "funicular":
                pts = [(nd.lat, nd.lon) for nd in o.nodes if nd.location.valid()]
                if len(pts) >= 2:
                    out["lifts"].append({"osm": "w" + str(o.id), "type": aw or "funicular",
                                         "name": t.get("name"), "ref": t.get("ref"),
                                         "operator": t.get("operator"), "access": t.get("aerialway:access"),
                                         "occupancy": t.get("aerialway:occupancy"),
                                         "a": [round(pts[0][0], 6), round(pts[0][1], 6)],
                                         "b": [round(pts[-1][0], 6), round(pts[-1][1], 6)],
                                         "disused": any(x.startswith(("disused", "abandoned")) for x in t)})
            pty = t.get("piste:type")
            if pty:
                pts = [(nd.lat, nd.lon) for nd in o.nodes if nd.location.valid()]
                if pts:
                    step = max(1, len(pts) // 12)
                    sample = pts[::step] + [pts[-1]]
                    rec = {"osm": "w" + str(o.id), "type": pty, "name": t.get("piste:name") or t.get("name"),
                           "diff": t.get("piste:difficulty"),
                           "c": [[round(a, 5), round(b, 5)] for a, b in sample]}
                    out["pistes"].append(rec)
                    piste_ways[o.id] = len(out["pistes"]) - 1
            if (t.get("public_transport") == "platform" or t.get("railway") == "platform"
                    or t.get("highway") == "platform"):
                pts = [(nd.lat, nd.lon) for nd in o.nodes if nd.location.valid()]
                if pts:
                    ptw[o.id] = [round(sum(p[0] for p in pts) / len(pts), 7),
                                 round(sum(p[1] for p in pts) / len(pts), 7), slim(t, PT_KEEP)]
        elif isinstance(o, osmium.osm.Relation):
            typ = t.get("type")
            if typ == "route" and t.get("route") in ROUTE_TYPES:
                mem = []
                for m in o.members:
                    role = m.role or ""
                    if m.type == "n" and m.ref in pt:
                        la, lo, _ = pt[m.ref]
                        mem.append(["n" + str(m.ref), role, la, lo])
                    elif m.type == "w" and m.ref in ptw and ("platform" in role or "stop" in role):
                        la, lo, _ = ptw[m.ref]
                        mem.append(["w" + str(m.ref), role, la, lo])
                out["routes"].append({"osm": "r" + str(o.id), "tags": slim(t, ROUTE_KEEP), "members": mem})
            elif typ == "route_master":
                out["masters"].append({"osm": "r" + str(o.id), "tags": slim(t, ROUTE_KEEP),
                                       "members": ["r" + str(m.ref) for m in o.members if m.type == "r"]})
            elif typ == "site" or t.get("site") == "piste" or (t.get("landuse") == "winter_sports"
                                                                and typ != "multipolygon"):
                ways = [m.ref for m in o.members if m.type == "w"]
                out["sites"].append({"osm": "r" + str(o.id), "tags": slim(t, AREA_TAGS),
                                     "pistes": [piste_ways[w] for w in ways if w in piste_ways],
                                     "n_way_members": len(ways)})
            elif t.get("boundary") == "administrative" and t.get("admin_level") in ("2", "4", "6", "7", "8"):
                out["admin"].append({"osm": "r" + str(o.id), "tags": {k: t[k] for k in (
                    "name", "admin_level", "ref:at:gkz", "wikidata", "official_name", "name:de") if k in t}})
    for v in pt.values():
        pass
    print(f"done {n:,} objects in {time.time() - t0:.0f}s; " + ", ".join(
        f"{k}={len(v)}" for k, v in out.items()), file=sys.stderr)
    out["pt"] = {str(k): v for k, v in pt.items()}
    out["ptw"] = {str(k): v for k, v in ptw.items()}
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
