#!/usr/bin/env python3
"""Builds App/Resources/tariffs.json (the app's remotely-updatable tariff catalog) from the curated
research data in data/. Bump CATALOG_VERSION whenever prices change so installed apps pick up the update.

`updatedAt` is the day the data was last checked against the official sources: the newer of `generatedAt` in
data/klimaticket_products.json and an optional `updatedAt` in data/fare_model.json. The app shows its tariff notice around the
December timetable change until this day lies on or after 1 December (docs/TARIFF_FRESHNESS.md), so it is only moved
forward when the prices were really compared.

`relationsPack` (where to download the current relation-price table) comes from data/relations_pack_info.json, written by
scripts/build_relations_pack.py; without that file the block is left out."""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_VERSION = 5
STATE = {"Wien": "W", "Niederösterreich": "NÖ", "Oberösterreich": "OÖ", "Salzburg": "S", "Tirol": "T",
         "Vorarlberg": "V", "Kärnten": "K", "Steiermark": "ST", "Burgenland": "B"}
LOCAL_SUBVARIANTS = {"innsbruck", "kufstein", "schwaz", "lienz", "st-anton", "regionen", "stadt_ermaessigt", "pluseins"}

def stable_id(raw):
    return re.sub(r"-(\d{6}|\d{4}|current)$", "", raw)

def main():
    src = json.load(open(os.path.join(ROOT, "data", "klimaticket_products.json"), encoding="utf-8"))
    rows = src["products"]
    current = [p for p in rows if p.get("status") == "current"]
    history = {}
    for p in rows:
        if p.get("status") != "current":
            if p.get("validFrom"): history.setdefault(stable_id(p["id"]), []).append({"validFrom": p["validFrom"], "priceEUR": p["priceEUR"]})

    products = []
    for p in current:
        pid = stable_id(p["id"])
        states = [STATE[r] for r in (p.get("regions") or []) if r in STATE]
        item = {
            "id": pid,
            "family": p["family"],
            "states": states,
            "name": p["name"].replace("Classic", "Klassik") if p["family"] == "oe" else p["name"],
            "variant": p["variant"],
            "priceEUR": p["priceEUR"],
            "validFrom": p["validFrom"],
            "eligibility": p.get("eligibility", ""),
            "coverage": p.get("coverage", ""),
            "sourceUrl": p.get("sourceUrl"),
        }
        hist = sorted({(h["validFrom"], h["priceEUR"]) for h in history.get(pid, []) if h["validFrom"] and h["validFrom"] < p["validFrom"]})
        if hist:
            item["priceHistory"] = [{"validFrom": v, "priceEUR": pr} for v, pr in hist]
        if p.get("subVariant") in LOCAL_SUBVARIANTS:
            item["isLocal"] = True
        products.append(item)

    fares = json.load(open(os.path.join(ROOT, "data", "fare_model.json"), encoding="utf-8"))
    updated_at = max(src.get("generatedAt", "")[:10], fares.get("updatedAt", "")[:10]) or "2026-10-09"
    catalog = {
        "version": CATALOG_VERSION,
        "updatedAt": updated_at,
        "currency": "EUR",
        "products": products,
        "fareModel": fares["fareModel"],
        "cityFares": fares["cityFares"],
        "kilometergeldEUR": fares["kilometergeldEUR"],
        "carFullCostPerKmEUR": fares["carFullCostPerKmEUR"],
        "emissions": fares["emissions"],
        "notes": fares.get("notes", []),
        "fareIndex": fares.get("fareIndex", []),
    }
    pack_info = os.path.join(ROOT, "data", "relations_pack_info.json")
    if os.path.exists(pack_info):
        info = json.load(open(pack_info, encoding="utf-8"))
        catalog["relationsPack"] = {k: info[k] for k in ("url", "sha256", "version", "validFrom", "bytes")}
    out = os.path.join(ROOT, "App", "Resources", "tariffs.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {out}: {len(products)} products, catalog v{CATALOG_VERSION}")

if __name__ == "__main__":
    main()
