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

for APPEARANCE in light dark; do
  xcrun simctl ui "$UDID" appearance "$APPEARANCE"
  for SCREEN in $SCREENS; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -KBScreenshot "$SCREEN" -KBDemo YES >/dev/null
    sleep "${SHOT_DELAY:-5}"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/${APPEARANCE}-${SCREEN}.png" >/dev/null 2>&1
    echo "captured $APPEARANCE-$SCREEN"
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
ls -la "$OUT"
