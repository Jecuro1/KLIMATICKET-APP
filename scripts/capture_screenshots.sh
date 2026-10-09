#!/usr/bin/env bash
# Usage: capture_screenshots.sh <UDID> <path/to/App.app> <outdir>
# Launches the app in screenshot mode (demo data) for each screen, light + dark.
set -euo pipefail
UDID="$1"; APP="$2"; OUT="$3"
BUNDLE_ID="${BUNDLE_ID:-com.knitelarlberg.klimabilanz}"
SCREENS="${SCREENS:-onboarding dashboard trips addTrip tripDetail stats ticket achievements settings update widgets}"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork 5g --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant notifications "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" 2>/dev/null || true
# Austrian time zone for the app; warm-up launch so first-boot system banners are gone before capturing.
export SIMCTL_CHILD_TZ="Europe/Vienna"
xcrun simctl launch "$UDID" "$BUNDLE_ID" -KBScreenshot dashboard -KBDemo YES >/dev/null 2>&1 || true
sleep 25
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
TRACE="$DATA/Documents/launch-trace.txt"

# Blank-launch diagnostics: a launch whose main thread never answered LaunchTrace's ping (no "stall" line) and never
# applied the Keychain read ("auth.loaded") is stuck before its first frame – the screenshot shows the launch screen.
# Sample that process (host `sample`, simulator apps are host processes) before it is terminated.
sample_if_stuck() {
  [ -n "$DATA" ] && [ -f "$TRACE" ] || return 0
  local block pid
  block=$(awk '/  launch /{b=""} {b=b $0 "\n"} END{printf "%s", b}' "$TRACE")
  printf '%s' "$block" | grep -qE "stall|auth\.loaded" && return 0
  pid=$(printf '%s' "$block" | sed -nE 's/.*  launch .* pid ([0-9]+).*/\1/p' | head -1)
  [ -n "$pid" ] || return 0
  echo "::warning::$1: main thread unresponsive since launch (pid $pid) – sampling it"
  sample "$pid" 3 -file "$OUT/stuck-$1.sample.txt" >/dev/null 2>&1 || true
}

for APPEARANCE in light dark; do
  xcrun simctl ui "$UDID" appearance "$APPEARANCE"
  for SCREEN in $SCREENS; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -KBScreenshot "$SCREEN" -KBDemo YES >/dev/null
    sleep "${SHOT_DELAY:-5}"
    # MARK: stats – MapKit streams its tiles from the network; map screens get extra time so they don't capture the
    # empty beige grid (the map screens open their sheets/camera moves after ~1 s on top).
    case "$SCREEN" in map*) sleep "${MAP_TILE_DELAY:-6}" ;; esac
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/${APPEARANCE}-${SCREEN}.png" >/dev/null 2>&1
    echo "captured $APPEARANCE-$SCREEN"
    sample_if_stuck "${APPEARANCE}-${SCREEN}"
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
# LaunchTrace (App/Sources/Core/LaunchTrace.swift): launch timestamps + main-thread stalls of every screenshot launch.
if [ -n "$DATA" ] && [ -f "$TRACE" ]; then
  cp "$TRACE" "$OUT/launch-trace.txt" || true
fi
ls -la "$OUT"
