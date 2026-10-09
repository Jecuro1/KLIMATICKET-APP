#!/bin/bash
# Main-thread profiles of the app's own tour (CI job "perf"), recorded with /usr/bin/sample.
#
# Usage: perf_profile.sh <simulator udid> <path to the built KlimaBilanz.app> <out dir> [tour ...]
#
# For every tour (default: launch overview trips stats ticket gipfelbuch) the app is launched in perf mode with
# +1 500 trips, `-KBPerfTour <tour> -KBPerfTourGate YES` (App/Sources/Services/Diagnostics/PerfTour.swift). Each
# phase of the tour waits for a go file, so the sampler runs exactly around it:
#   open   – switching to the screen (its first build), 8 s window
#   scroll – three passes down and up at 2 400 pt/s, 20 s window
#   launch – (tour "launch") the first 8 s after the process started
# `sample` (1 ms interval) writes a call-tree report per phase; scripts/perf_profile.py ranks the main thread's
# hotspots (<out>/<tour>.profile.json/.md). Best effort: a failing phase is logged and skipped.
#
# Why not `xctrace record`: on the CI simulator `--launch <host .app>` is ambiguous (app + widget extension) and
# attached Time Profiler recordings did not finish within 150–240 s (runs 192, 224).
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

xcrun simctl install "$UDID" "$APP" || true
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
if [ -z "$DATA" ]; then echo "::warning::App-Container nicht gefunden – keine Profile"; exit 0; fi
DIAG="$DATA/Library/Application Support/Diagnostics"

# sample <pid> <seconds> <file> – as root when possible (a Release build has no get-task-allow).
sampler() {
  sudo -n /usr/bin/sample "$1" "$2" 1 -mayDie -file "$3" >>"$LOG" 2>&1 \
    || /usr/bin/sample "$1" "$2" 1 -mayDie -file "$3" >>"$LOG" 2>&1
  sudo -n chmod a+r "$3" 2>/dev/null || true
}

# Runs the sampler for phase $2 of $1's tour around the go file.
phase() {
  local pid=$1 name=$2 seconds=$3
  local file="$OUT/$T.$name.sample.txt"
  sampler "$pid" "$seconds" "$file" &
  local sp=$!
  sleep 1
  mkdir -p "$DIAG" && touch "$DIAG/perf-go-$name"
  wait "$sp"
  [ -s "$file" ] && PHASES+=("$name=$file")
}

for T in $TOURS; do
  echo "::group::Profil $T"
  LOG="$OUT/$T.sample.log"
  : > "$LOG"
  PHASES=()
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -f "$DIAG"/perf-go-* "$DIAG/perf-tour.json" 2>/dev/null
  PID=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" -KBPerf YES -KBDemo YES -KBPerfTrips "$TRIPS" \
          -KBPerfTour "$T" -KBPerfTourGate YES 2>>"$LOG" | awk '{print $NF}')
  echo "pid $PID" >> "$LOG"
  if [ -z "$PID" ]; then echo "::warning::$T: App startet nicht"; echo "::endgroup::"; continue; fi
  if [ "$T" = "launch" ]; then
    FILE="$OUT/$T.launch.sample.txt"
    sampler "$PID" 8 "$FILE"
    [ -s "$FILE" ] && PHASES+=("launch=$FILE")
  else
    sleep 7   # launch, first frame, monitor + tour started (waiting for the go file)
    phase "$PID" open 8
    phase "$PID" scroll 20
  fi
  sleep 1
  [ -f "$DIAG/perf-tour.json" ] && cp "$DIAG/perf-tour.json" "$OUT/$T.tour.json"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  tail -4 "$LOG"
  if [ ${#PHASES[@]} -gt 0 ]; then
    python3 "$HERE/perf_profile.py" --sample "$T" "${PHASES[@]}" --json "$OUT/$T.profile.json" > "$OUT/$T.profile.md" 2>>"$LOG" || true
    head -45 "$OUT/$T.profile.md"
    gzip -f "$OUT/$T".*.sample.txt 2>/dev/null || true
  else
    echo "::warning::Kein Profil für $T (siehe $LOG)"
  fi
  echo "::endgroup::"
done
exit 0
