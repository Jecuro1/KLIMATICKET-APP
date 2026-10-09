#!/usr/bin/env bash
# Signed builds with cloud-managed signing – an App Store Connect API key, no certificates or profiles in the repo:
#   1. one archive (Release, automatic signing, native Sign in with Apple)
#   2. TestFlight: export + upload to App Store Connect           (skip with TESTFLIGHT=false)
#   3. Direct install (ADHOC=true – release runs): ad-hoc export ("release-testing") of app + widget for every
#      registered iPhone → $OTA_DIR/KlimaBilanz-<version>-adhoc.ipa + AppIcon-57.png + AppIcon-512.png.
#      manifest.plist and update.json's otaManifestURL follow in the "Release metadata" step (docs/DIREKT_INSTALLIEREN.md).
# Needs: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID and the key as ASC_KEY_P8 (the text of AuthKey_XXXX.p8) or
#        ASC_KEY_BASE64 (base64 of the file); VERSION, BUILD. The key's role: Admin (cloud-managed distribution certificate).
# A failure here never fails the job: the unsigned .ipa, update.json and the AltStore/SideStore source are published
# regardless. Every problem becomes an ::error:: annotation and a line in the run summary.
set -euo pipefail

TMP="${RUNNER_TEMP:-$(mktemp -d)}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
OTA_DIR="${OTA_DIR:-dist/ota}"
ARCHIVE=build/KlimaBilanz.xcarchive
ICON=App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
BUNDLE_IDS=(--bundle-id com.knitelarlberg.klimabilanz --bundle-id com.knitelarlberg.klimabilanz.widgets)

summary() { printf '%s\n' "$*" >> "$SUMMARY"; }
problem() { echo "::error title=$1::$2"; summary "| $1 | ❌ $2 |"; }
log_errors() { grep -E "error:|Error Domain|No profiles|requires a provisioning profile" "$1" | sort -u | head -60 || true; tail -25 "$1"; }

mkdir -p build
summary "### Signierter Build $VERSION ($BUILD)"
summary ""
summary "| Schritt | Ergebnis |"
summary "|---|---|"

export ASC_KEY_PATH="$TMP/AuthKey_${ASC_KEY_ID}.p8"
trap 'rm -f "$ASC_KEY_PATH"' EXIT
if ! python3 scripts/asc_api.py key --out "$ASC_KEY_PATH"; then
  problem "API-Schlüssel" "ASC_KEY_P8 bzw. ASC_KEY_BASE64 ist nicht lesbar – docs/DIREKT_INSTALLIEREN.md, Schritt 3"
  exit 0
fi
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

if ! xcodebuild archive \
  -project KlimaBilanz.xcodeproj -scheme KlimaBilanz -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" KB_NATIVE_APPLE_SIGNIN=YES \
  "${AUTH[@]}" > build/archive.log 2>&1; then
  log_errors build/archive.log
  problem "Archiv" "xcodebuild archive fehlgeschlagen – Details im Log dieses Schritts"
  exit 0
fi
summary "| Archiv | ✅ signiert (Team-ID aus APPLE_TEAM_ID) |"

# export_options <method> <destination> <file>
export_options() {
  local extra=""
  if [ "$1" = "app-store-connect" ]; then extra="<key>manageAppVersionAndBuildNumber</key><false/>"; fi
  if [ "$1" = "release-testing" ]; then extra="<key>thinning</key><string>&lt;none&gt;</string>"; fi
  cat > "$3" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$1</string>
  <key>destination</key><string>$2</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  ${extra}
</dict>
</plist>
PLIST
}

# ---------------------------------------------------------------- TestFlight
if [ "${TESTFLIGHT:-auto}" = "false" ]; then
  summary "| TestFlight | übersprungen (Variable TESTFLIGHT=false) |"
else
  export_options app-store-connect upload build/ExportOptions-TestFlight.plist
  if xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions-TestFlight.plist \
       -exportPath build/export "${AUTH[@]}" > build/export-testflight.log 2>&1; then
    echo "Uploaded build $VERSION ($BUILD) to App Store Connect – TestFlight verteilt sie automatisch."
    summary "| TestFlight | ✅ hochgeladen – nach Apples Verarbeitung in TestFlight |"
  else
    log_errors build/export-testflight.log
    problem "TestFlight" "Upload fehlgeschlagen (App in App Store Connect angelegt? Ohne TestFlight: Variable TESTFLIGHT=false)"
  fi
fi

# ---------------------------------------------------------------- Direct install (ad-hoc)
if [ "${ADHOC:-false}" != "true" ]; then
  exit 0
fi
rm -rf "$OTA_DIR"
DEVICES=$(python3 scripts/asc_api.py devices || echo "?")
if [ "$DEVICES" = "0" ]; then
  echo "::notice title=Direkt installieren::Noch kein iPhone registriert – Actions › Gerät registrieren ausführen (docs/DIREKT_INSTALLIEREN.md)."
  summary "| Direkt installieren | ⏭ noch kein iPhone registriert – Actions › Gerät registrieren ausführen |"
  exit 0
fi
# Profiles cannot be edited: ad-hoc profiles that miss a registered iPhone are deleted, the export creates them anew.
python3 scripts/asc_api.py refresh-adhoc "${BUNDLE_IDS[@]}" \
  || echo "::warning title=Direkt installieren::Ad-hoc-Profile nicht geprüft – der Export nimmt die vorhandenen"
export_options release-testing export build/ExportOptions-AdHoc.plist
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions-AdHoc.plist \
     -exportPath build/export-adhoc "${AUTH[@]}" > build/export-adhoc.log 2>&1; then
  log_errors build/export-adhoc.log
  problem "Direkt installieren" "Ad-hoc-Export fehlgeschlagen – Details im Log dieses Schritts"
  exit 0
fi
EXPORTED=$(find build/export-adhoc -maxdepth 1 -name '*.ipa' | head -1)
if [ -z "$EXPORTED" ]; then
  problem "Direkt installieren" "Der Ad-hoc-Export hat keine .ipa erzeugt"
  exit 0
fi
mkdir -p "$OTA_DIR"
cp "$EXPORTED" "$OTA_DIR/KlimaBilanz-${VERSION}-adhoc.ipa"
sips -s format png -z 57 57 "$ICON" --out "$OTA_DIR/AppIcon-57.png" > /dev/null
sips -s format png -z 512 512 "$ICON" --out "$OTA_DIR/AppIcon-512.png" > /dev/null
set +e
CHECK=$(python3 scripts/asc_api.py check-ipa "$OTA_DIR/KlimaBilanz-${VERSION}-adhoc.ipa")
STATUS=$?
set -e
echo "$CHECK"
if [ $STATUS -eq 0 ]; then
  summary "| Direkt installieren | ✅ Ad-hoc-.ipa für $DEVICES registrierte(s) iPhone(s) |"
else
  echo "::warning title=Direkt installieren::$(echo "$CHECK" | tr '\n' ' ')"
  summary "| Direkt installieren | ⚠️ $(echo "$CHECK" | tr '\n' ' ') |"
fi
ls -la "$OTA_DIR"
