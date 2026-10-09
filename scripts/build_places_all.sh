#!/bin/sh
# KlimaBilanz – full places data build (docs/ENRICH_SPEC.md §1.7.1 steps 1–6, docs/DATA_SOURCES.md §4).
#
#   sh scripts/build_places_all.sh                 # steps 2–6 (OSM extracts must exist, see --extract)
#   sh scripts/build_places_all.sh --extract       # also step 1 (OSM extracts from the PBF, ≈ 10 min, pyosmium)
#   sh scripts/build_places_all.sh --twice         # AT-D1: build the v2 files a second time and compare SHA-256
#   sh scripts/build_places_all.sh --no-tests      # skip goldens + swift test
#
# Environment: DL (downloads, default build/places-dl, scripts/fetch_places_sources.sh), BUILD (default build),
# PYTHON (an interpreter with scripts/requirements-enrich.txt installed; default python3),
# SOURCE_DATE_EPOCH (fixes META build.date), SCOTTY_FIXTURES / OEBB_FIXTURES (golden regeneration, optional).
# Outputs: App/Resources/{places.bin, stops_osm.bin, localities.bin}, data/places_report.json; intermediates in BUILD.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DL=${DL:-$ROOT/build/places-dl}
B=${BUILD:-$ROOT/build}
PY=${PYTHON:-python3}
EXTRACT=0; TWICE=0; TESTS=1
for arg in "$@"; do
  case "$arg" in
    --extract) EXTRACT=1 ;;
    --twice) TWICE=1 ;;
    --no-tests) TESTS=0 ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done
cd "$ROOT"
mkdir -p "$B/enrich" "$B/places"
PBF="$DL/osm/austria-latest.osm.pbf"

# 1 OSM extracts (the only steps that need pyosmium)
if [ "$EXTRACT" = 1 ] || [ ! -f "$B/enrich/osm_routes.json" ] || [ ! -f "$B/enrich/osm_tags.json" ]; then
  [ -f "$PBF" ] || { echo "missing $PBF (scripts/fetch_places_sources.sh)" >&2; exit 1; }
  [ -f "$DL/osm/osm_pt_austria.json" ] || "$PY" -I scripts/extract_osm_places.py "$PBF" "$DL/osm/osm_pt_austria.json"
  "$PY" -I scripts/extract_osm_routes.py "$PBF" "$B/enrich/osm_routes.json"
  "$PY" -I scripts/extract_osm_tags.py "$PBF" "$B/enrich/osm_tags.json"
fi

# 2 base stop list (v1 logic) → build/places/places.json + build/places/v1/*.bin (rollback artefact)
"$PY" -I scripts/build_places.py --dl "$DL" --stage base --debug-out "$B/places"

# 3 lines twice: official layer (no OSM) and full (with OSM), same places.json
LINE_SRC="--oevgk $DL/oevgk/x/01_Haltestellenkategorien --oebb-gtfs $DL/oebb_gtfs --wl-gtfs $DL/wl/gtfs.zip \
  --stmk-stops $DL/stmk/x/Haltestellen --stmk-lines $DL/stmk_lines/x/VSTG_Linienverkehr"
for f in "$DL"/mvo/*.zip; do                     # optional MVO GTFS feeds: <label>.zip (data.mobilitaetsverbuende.at)
  [ -f "$f" ] && LINE_SRC="$LINE_SRC --gtfs $f=$(basename "$f" .zip)"
done
# shellcheck disable=SC2086
"$PY" -I scripts/build_lines.py --places "$B/places/places.json" --out "$B/lines_official" $LINE_SRC
# shellcheck disable=SC2086
"$PY" -I scripts/build_lines.py --places "$B/places/places.json" --out "$B/lines_full" $LINE_SRC \
  --osm "$B/enrich/osm_routes.json"

# 4 tags (shapely + numpy)
"$PY" -I scripts/build_tags.py --places "$B/places/places.json" --osm "$B/enrich/osm_tags.json" \
  --gem "$DL/statat/x/STATISTIK_AUSTRIA_GEM_20260101" --out "$B/tags"

# 5 v2 stage → App/Resources + data/places_report.json (self-test: scripts/check_places_v2.py)
V2="--dl $DL --lines-official $B/lines_official --lines-full $B/lines_full --tags $B/tags/tags.json"
# shellcheck disable=SC2086
"$PY" -I scripts/build_places.py --stage v2 $V2 --out App/Resources --debug-out "$B/places"
if [ "$TWICE" = 1 ]; then
  # shellcheck disable=SC2086
  "$PY" -I scripts/build_places.py --stage v2 $V2 --out "$B/v2-second" --debug-out "$B/places" \
    --report "$B/v2-second/places_report.json"
  cmp data/places_report.json "$B/v2-second/places_report.json"
  "$PY" -I scripts/check_places_v2.py check --res App/Resources --compare "$B/v2-second" > /dev/null
  echo "AT-D1: second build identical"
fi

# 6 goldens + tests
if [ "$TESTS" = 1 ]; then
  if [ -n "${SCOTTY_FIXTURES:-}" ]; then
    "$PY" -I scripts/places_reference.py golden App/Resources/places.bin App/Resources/localities.bin \
      Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places --osm App/Resources/stops_osm.bin
  else
    echo "SCOTTY_FIXTURES not set – search goldens not regenerated (docs/DATA_SOURCES.md §4)"
  fi
  if command -v swift > /dev/null 2>&1; then
    swift test --package-path Packages/KlimaCore --no-parallel
  fi
fi
ls -l App/Resources/places.bin App/Resources/stops_osm.bin App/Resources/localities.bin
