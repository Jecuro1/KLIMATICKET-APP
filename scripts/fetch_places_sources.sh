#!/bin/sh
# Downloads every input of the places data build (≈ 1.4 GB incl. the OSM PBF). Polite: one file at a time.
# Usage: sh scripts/fetch_places_sources.sh [build/places-dl]     – then: sh scripts/build_places_all.sh --extract
# Sources, licences and the yearly update procedure: docs/DATA_SOURCES.md, format: docs/ENRICH_SPEC.md §1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DL=${1:-$HERE/../build/places-dl}
UA="KlimaBilanz-data-build/2 (places + lines + tags; one request at a time)"
mkdir -p "$DL"/oevgk "$DL"/osm "$DL"/oebb_gtfs "$DL"/wl "$DL"/stmk "$DL"/stmk_lines "$DL"/statat "$DL"/mvo
# 1 ÖV-Güteklassen 2025_revised (ÖROK/BMIMI/AustriaTech) – the MVO stop list (WFS 10/2025), weekday departures and the
#   line refs per stop on both reference days (22.10.2025 Werktag, 29.10.2025 Herbstferien → "schooldays?")
#   Licence: none stated on mobilitydata.gv.at – see docs/DATA_SOURCES.md §3 (release blocker, use 1b for releases)
curl -fL -A "$UA" -o "$DL/oevgk/gk2025.zip" "https://files.austriatech.at/d/33971b2d51a348a5958d/files/?p=/OeV_Gueteklassen_2025_nap_revised.zip&dl=1"
unzip -o -q "$DL/oevgk/gk2025.zip" '01_Haltestellenkategorien/*20251022*' '01_Haltestellenkategorien/*20251029*' -d "$DL/oevgk/x"
# 1b (preferred, needs a free account + licence acceptance, not scriptable): data.mobilitaetsverbuende.at
#    data set 46 "Haltestellen (CSV)" → build_places.py --mvo <file>; GTFS of the Verbünde (52 VOR, 53 Steiermark,
#    54 Salzburg, 55 Kärnten, 56 OÖVV, 57 VVT, 58 VVV, 69 Linz AG) → save as $DL/mvo/<label>.zip; build_places_all.sh
#    passes each one to build_lines.py --gtfs (Datenlizenz Mobilitätsverbünde Österreich v1.1, rebuild every December)
# 2 OpenStreetMap Austria extract (Geofabrik, ODbL) → osm_pt_austria.json here; the route/tag extracts are step 1 of
#   scripts/build_places_all.sh (all three need pyosmium: scripts/requirements-enrich.txt)
curl -fL -A "$UA" -o "$DL/osm/austria-latest.osm.pbf" "https://download.geofabrik.de/europe/austria-latest.osm.pbf"
python3 -I "$HERE/extract_osm_places.py" "$DL/osm/austria-latest.osm.pbf" "$DL/osm/osm_pt_austria.json"
# 3 ÖBB-PV Soll-Fahrplan GTFS 2026 (CC BY 4.0) – the download needs the terms checkbox on data.oebb.at:
#    https://data.oebb.at/de/datensaetze~soll-fahrplan-gtfs~  → unzip stops/routes/trips/stop_times/calendar*/agency
#    into $DL/oebb_gtfs
# 4 Wiener Linien GTFS incl. stop_times (CC BY 4.0, Stadt Wien – data.wien.gv.at)
curl -fL -A "$UA" -o "$DL/wl/gtfs.zip" "http://www.wienerlinien.at/ogd_realtime/doku/ogd/gtfs/gtfs.zip"
unzip -o -q "$DL/wl/gtfs.zip" stops.txt routes.txt -d "$DL/wl/x"
# 5 Land Steiermark (CC BY 4.0): Haltestellen des Verkehrsverbundes Steiermark + Linienverkehr (DIVA line code →
#   public number, type, Kategorie Schüler/Saisonal)
curl -fL -A "$UA" -o "$DL/stmk/Haltestellen.zip" "https://service.stmk.gv.at/ogd/OGD_Data_ABT17/geoinformation/Haltestellen.zip"
unzip -o -q "$DL/stmk/Haltestellen.zip" -d "$DL/stmk/x"
curl -fL -A "$UA" -o "$DL/stmk_lines/VSTG_Linienverkehr.zip" "https://service.stmk.gv.at/ogd/OGD_Data_ABT17/geoinformation/VSTG_Linienverkehr.zip"
unzip -o -q "$DL/stmk_lines/VSTG_Linienverkehr.zip" -d "$DL/stmk_lines/x"
# 6 Statistik Austria – Gemeinden 01.01.2026 (CC BY 4.0)
curl -fL -A "$UA" -o "$DL/statat/gem_20260101.zip" "https://www.statistik.at/gs-open/GEODATA/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=GEODATA:STATISTIK_AUSTRIA_GEM_20260101&outputFormat=SHAPE-ZIP&format_options=CHARSET:UTF-8"
unzip -o -q "$DL/statat/gem_20260101.zip" -d "$DL/statat/x"
echo "done – next: DL=$DL sh scripts/build_places_all.sh --extract"
