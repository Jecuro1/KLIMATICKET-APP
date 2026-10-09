#!/bin/sh
# Downloads every input of scripts/build_places.py (≈ 1.3 GB incl. the OSM PBF). Polite: one file at a time.
# Usage: sh scripts/fetch_places_sources.sh [build/places-dl]     – then: python3 -I scripts/build_places.py
# Sources, licences and the yearly update procedure: docs/DATA_SOURCES.md.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DL=${1:-$HERE/../build/places-dl}
mkdir -p "$DL"/oevgk "$DL"/osm "$DL"/oebb_gtfs "$DL"/wl "$DL"/stmk "$DL"/statat
# 1 ÖV-Güteklassen 2025_revised (ÖROK/BMIMI/AustriaTech) – contains the MVO stop list (WFS 10/2025) + weekday departures
#   Licence: none stated on mobilitydata.gv.at – see docs/DATA_SOURCES.md (release blocker, use 1b for releases)
curl -fL -o "$DL/oevgk/gk2025.zip" "https://files.austriatech.at/d/33971b2d51a348a5958d/files/?p=/OeV_Gueteklassen_2025_nap_revised.zip&dl=1"
unzip -o -q "$DL/oevgk/gk2025.zip" '01_Haltestellenkategorien/*20251022*' -d "$DL/oevgk/x"
# 1b (preferred, needs a free account + licence acceptance): data.mobilitaetsverbuende.at data set 46 "Haltestellen (CSV)"
#    Datenlizenz Mobilitätsverbünde Österreich v1.1 → pass the stop-level CSV with --mvo <file>
# 2 OpenStreetMap Austria extract (Geofabrik, ODbL) → Overpass-style JSON (needs pyosmium for this one step;
#   the equivalent Overpass query is in scripts/extract_osm_places.py)
curl -fL -o "$DL/osm/austria-latest.osm.pbf" "https://download.geofabrik.de/europe/austria-latest.osm.pbf"
python3 -I "$HERE/extract_osm_places.py" "$DL/osm/austria-latest.osm.pbf" "$DL/osm/osm_pt_austria.json"
# 3 ÖBB-PV Soll-Fahrplan GTFS 2026 (CC BY 4.0) – the download needs the terms checkbox on data.oebb.at:
#    https://data.oebb.at/de/datensaetze~soll-fahrplan-gtfs~  → unzip stops/routes/trips/stop_times/calendar* into $DL/oebb_gtfs
# 4 Wiener Linien GTFS (CC BY 4.0, Stadt Wien – data.wien.gv.at)
curl -fL -o "$DL/wl/gtfs.zip" "http://www.wienerlinien.at/ogd_realtime/doku/ogd/gtfs/gtfs.zip"
unzip -o -q "$DL/wl/gtfs.zip" stops.txt routes.txt -d "$DL/wl/x"
# 5 Land Steiermark – Haltestellen des Verkehrsverbundes Steiermark (CC BY 4.0)
curl -fL -o "$DL/stmk/Haltestellen.zip" "https://service.stmk.gv.at/ogd/OGD_Data_ABT17/geoinformation/Haltestellen.zip"
unzip -o -q "$DL/stmk/Haltestellen.zip" -d "$DL/stmk/x"
# 6 Statistik Austria – Gemeinden 01.01.2026 (CC BY 4.0)
curl -fL -o "$DL/statat/gem_20260101.zip" "https://www.statistik.at/gs-open/GEODATA/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=GEODATA:STATISTIK_AUSTRIA_GEM_20260101&outputFormat=SHAPE-ZIP&format_options=CHARSET:UTF-8"
unzip -o -q "$DL/statat/gem_20260101.zip" -d "$DL/statat/x"
echo "done – next: python3 -I scripts/build_places.py --dl $DL"
