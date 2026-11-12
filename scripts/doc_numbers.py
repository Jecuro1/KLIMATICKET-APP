#!/usr/bin/env python3
"""The numbers the README and docs quote, read from the shipped data files (nothing is typed by hand).

Usage: doc_numbers.py [--json] [--check FILE …] [--tree]

Prints one line per figure: `<key> = <value>  (<de-AT>)  – <source>`.

  stops               places.bin (KBPL v2 header)          every Austrian stop the place search covers
  localities          localities.bin (header)              OSM places (ODbL) next to the stops
  legacy_stations     App/Resources/stations.json          the frozen list old trips refer to
  relation_pairs      data/oebb_relation_prices.json        origin → destination prices of the ÖBB Relationspreise
  relation_origins    data/oebb_relation_prices.json
  relation_valid_from data/oebb_relation_prices.json        tariff date of that table
  ticket_products     App/Resources/tariffs.json            KlimaTicket products (Ö + regional)
  achievements        KlimaCore Achievements.swift          badges in the Gipfelbuch

--check README.md docs/ARCHITECTURE.md exits 1 and names every figure among stops, localities and relation_pairs that
none of the given files quotes (formatted de-AT, e.g. 39.711) – run it after the data changed.

--tree exits 1 and names every folder of the source tree (top level, Packages, App/Sources/{Features,Services,DesignSystem},
KlimaCore sources) that docs/ARCHITECTURE.md does not mention – run it after a folder was added or renamed.
"""
import importlib.util
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKED = ("stops", "localities", "relation_pairs")


def de(value):
    """de-AT grouping: 39711 → '39.711'."""
    return f"{value:,}".replace(",", ".") if isinstance(value, int) else str(value)


def _load_json(root, *parts):
    with open(os.path.join(root, *parts), encoding="utf-8") as f:
        return json.load(f)


def _container(root):
    spec = importlib.util.spec_from_file_location("check_places_v2", os.path.join(root, "scripts", "check_places_v2.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Container


def numbers(root=ROOT):
    """{key: (value, source)} in print order."""
    out = {}
    container = _container(root)
    out["stops"] = (container(os.path.join(root, "App/Resources/places.bin")).n_stops, "App/Resources/places.bin")
    out["localities"] = (container(os.path.join(root, "App/Resources/localities.bin")).n_records, "App/Resources/localities.bin")
    out["legacy_stations"] = (len(_load_json(root, "App/Resources/stations.json")), "App/Resources/stations.json")
    relations = _load_json(root, "data/oebb_relation_prices.json")
    source = "data/oebb_relation_prices.json"
    out["relation_pairs"] = (sum(len(destinations) for destinations in relations["relations"].values()), source)
    out["relation_origins"] = (len(relations["relations"]), source)
    out["relation_valid_from"] = (relations["valid_from"], source)
    out["ticket_products"] = (len(_load_json(root, "App/Resources/tariffs.json")["products"]), "App/Resources/tariffs.json")
    with open(os.path.join(root, "Packages/KlimaCore/Sources/KlimaCore/Achievements.swift"), encoding="utf-8") as f:
        out["achievements"] = (len(re.findall(r'^\s+make\("[a-z0-9-]+"', f.read(), re.M)), "Packages/KlimaCore/Sources/KlimaCore/Achievements.swift")
    return out


def missing(figures, texts):
    """Keys of CHECKED whose de-AT form appears in none of `texts`."""
    return [key for key in CHECKED if not any(de(figures[key][0]) in text for text in texts)]


TREE_PARENTS = ("", "Packages", "App/Sources", "App/Sources/Features", "App/Sources/Services", "App/Sources/DesignSystem",
                "Packages/KlimaCore/Sources/KlimaCore")
TREE_SKIP = {"build", "node_modules", "testdata", "Tests", "Sources", "Resources", "Supporting"}


def tree_names(root=ROOT):
    """Folder names ARCHITECTURE.md has to mention (hidden folders, build output and folders named in TREE_SKIP excluded)."""
    names = []
    for parent in TREE_PARENTS:
        base = os.path.join(root, parent)
        if not os.path.isdir(base):
            continue
        for entry in sorted(os.listdir(base)):
            if entry.startswith(".") or entry in TREE_SKIP or not os.path.isdir(os.path.join(base, entry)):
                continue
            names.append(entry)
    return names


def untreed(root=ROOT, text=None):
    """Folder names missing from ARCHITECTURE.md: it has to write the folder as `Name/` (a plain word does not count)."""
    if text is None:
        with open(os.path.join(root, "docs", "ARCHITECTURE.md"), encoding="utf-8") as f:
            text = f.read()
    return [name for name in dict.fromkeys(tree_names(root)) if not re.search(r"(?<![\w])" + re.escape(name) + r"/", text)]


def main(argv=None, root=ROOT):
    args = list(sys.argv[1:] if argv is None else argv)
    if "--tree" in args:
        missing_folders = untreed(root)
        for name in missing_folders:
            print(f"{name}/ steht nicht in docs/ARCHITECTURE.md")
        print(f"--- {len(missing_folders)} Ordner fehlen")
        return 1 if missing_folders else 0
    figures = numbers(root)
    if "--check" in args:
        files = args[args.index("--check") + 1:]
        texts = []
        for name in files:
            with open(os.path.join(root, name), encoding="utf-8") as f:
                texts.append(f.read())
        stale = missing(figures, texts)
        for key in stale:
            print(f"{key}: {de(figures[key][0])} ({figures[key][1]}) steht in keiner der Dateien: {', '.join(files)}")
        print(f"--- {len(stale)} Zahl(en) fehlen")
        return 1 if stale else 0
    if "--json" in args:
        print(json.dumps({key: value for key, (value, _) in figures.items()}, indent=2, ensure_ascii=False))
        return 0
    for key, (value, source) in figures.items():
        print(f"{key} = {value}  ({de(value)})  – {source}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
