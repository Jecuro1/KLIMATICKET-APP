#!/bin/bash
# Time Profiler recordings of the app's own tour (CI job "perf", after the XCUITests).
#
# Usage: perf_profile.sh <simulator udid> <path to KlimaBilanz.app> <out dir> [tour ...]
#
# For every tour (default: launch overview trips stats ticket gipfelbuch) the app is launched under
# `xctrace record --template "Time Profiler"` in perf mode with +1 500 trips and `-KBPerfTour <tour>`
# (App/Sources/Services/Diagnostics/PerfTour.swift: opens the screen, scrolls it, exits). The time-profile table and
# the signpost tables are exported and reduced to main-thread hotspots per tour phase by scripts/perf_profile.py
# (<out>/<tour>.profile.json + profiles.md). Best effort: a failing recording is logged and skipped.
set -u
UDID=$1
APP=$2
OUT=$3
shift 3
TOURS=${*:-launch overview trips stats ticket gipfelbuch}
BUNDLE_ID=com.knitelarlberg.klimabilanz
TRIPS=${PERF_PROFILE_TRIPS:-1500}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"

xcrun xctrace version || { echo "::notice::xctrace fehlt – keine Profile"; exit 0; }
sudo -n DevToolsSecurity -enable >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" || true

record() {
  # $1 trace path, rest: extra xctrace arguments
  local trace=$1; shift
  rm -rf "$trace"
  # macOS has no `timeout`: perl's alarm ends a recording that hangs.
  perl -e 'alarm shift; exec @ARGV' 150 xcrun xctrace record --template 'Time Profiler' --device "$UDID" --time-limit 60s --output "$trace" "$@"
}

for T in $TOURS; do
  echo "::group::Profil $T"
  PREFIX="$OUT/$T"
  TRACE="$PREFIX.trace"
  LOG="$PREFIX.record.log"
  ARGS=(-KBPerf YES -KBDemo YES -KBPerfTrips "$TRIPS" -KBPerfTour "$T")
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

  # 1) xctrace launches the app (whole launch included) with the signpost instrument, 2) without it, 3) attach.
  record "$TRACE" --instrument os_signpost --launch -- "$APP" "${ARGS[@]}" > "$LOG" 2>&1
  if [ ! -d "$TRACE" ]; then
    record "$TRACE" --launch -- "$APP" "${ARGS[@]}" >> "$LOG" 2>&1
  fi
  if [ ! -d "$TRACE" ]; then
    PID=$(xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "${ARGS[@]}" 2>>"$LOG" | awk '{print $NF}')
    if [ -n "$PID" ]; then record "$TRACE" --attach "$PID" >> "$LOG" 2>&1; fi
  fi
  tail -5 "$LOG"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

  DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [ -n "$DATA" ] && [ -f "$DATA/Library/Application Support/Diagnostics/perf-tour.json" ]; then
    cp "$DATA/Library/Application Support/Diagnostics/perf-tour.json" "$PREFIX.tour.json"
  fi

  if [ -d "$TRACE" ]; then
    xcrun xctrace export --input "$TRACE" --toc > "$PREFIX.toc.xml" 2>>"$LOG" || true
    xcrun xctrace export --input "$TRACE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
      > "$PREFIX.time-profile.xml" 2>>"$LOG" || true
    # Signpost tables (os_signpost / Points of Interest): whatever schemas this Xcode names them.
    for SCHEMA in $(grep -o 'schema="[^"]*"' "$PREFIX.toc.xml" 2>/dev/null | sed 's/schema="//; s/"$//' | sort -u | grep -i -E 'signpost|poi|interest'); do
      xcrun xctrace export --input "$TRACE" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$SCHEMA\"]" \
        > "$PREFIX.signpost-$SCHEMA.xml" 2>>"$LOG" || true
    done
    ls -la "$PREFIX".* | sed 's/^/  /'
    python3 "$HERE/perf_profile.py" "$PREFIX" --json "$PREFIX.profile.json" > "$PREFIX.profile.md" 2>>"$LOG" || true
    head -40 "$PREFIX.profile.md"
    # The raw exports are large; the reduced JSON is what the summary needs.
    gzip -f "$PREFIX.time-profile.xml" 2>/dev/null || true
    rm -rf "$TRACE"
  else
    echo "::warning::Keine Time-Profiler-Aufnahme für $T (siehe $LOG)"
  fi
  echo "::endgroup::"
done
exit 0
