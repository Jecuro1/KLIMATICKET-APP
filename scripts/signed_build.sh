#!/usr/bin/env bash
# Signed archive + upload to App Store Connect / TestFlight using cloud-managed signing.
# Requires: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_BASE64 (App Store Connect API key, role "App Manager" or "Admin"),
#           VERSION, BUILD. The app record (bundle id com.knitelarlberg.klimabilanz) must exist in App Store Connect.
set -euo pipefail
KEY_PATH="$RUNNER_TEMP/AuthKey_${ASC_KEY_ID}.p8"
echo "$ASC_KEY_BASE64" | base64 --decode > "$KEY_PATH"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodebuild archive \
  -project KlimaBilanz.xcodeproj -scheme KlimaBilanz -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/KlimaBilanz.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" KB_NATIVE_APPLE_SIGNIN=YES \
  "${AUTH[@]}" > build/archive.log 2>&1 || { grep -E "error:" build/archive.log | sort -u | head -80; tail -40 build/archive.log; exit 1; }

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath build/KlimaBilanz.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export "${AUTH[@]}"
echo "Uploaded build $VERSION ($BUILD) to App Store Connect – TestFlight verteilt sie automatisch."
