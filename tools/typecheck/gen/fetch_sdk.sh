#!/usr/bin/env bash
# Fetch the iOS SDK Swift module interfaces the stub generator needs.
#
#   gen/fetch_sdk.sh [dest-dir]      -> prints the SDK directory on stdout
#
# Source: the public mirror github.com/xybp888/iOS-SDKs (pinned commit), sparse +
# partial clone, so only the ~25 *.swiftinterface files are downloaded.
# Alternatively point KB_IOS_SDK_REF at any iPhoneOS SDK directory, e.g. on a Mac:
#   KB_IOS_SDK_REF="$(xcrun --show-sdk-path --sdk iphoneos)" tools/typecheck/run.sh
# Nothing fetched here is committed to the repository (see README, "Licensing").
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:-$here/../.build/sdk-src}"
REPO="https://github.com/xybp888/iOS-SDKs"
COMMIT="ad607cb07fe4ad1c9b91cf970bd228c2a9253207"
SDK="iPhoneOS26.4.sdk"   # newest complete SDK in the mirror; CI uses 26.5 (see README)

modules=$(python3 -c "import sys; sys.path.insert(0, '$here'); import transform; print(' '.join(sorted({transform.MODULES[m].get('src', m) for m in transform.GENERATED_ORDER})))")
patterns=""
for m in $modules; do
  for base in "System/Library/Frameworks/$m.framework/Modules" "System/Cryptexes/OS/System/Library/Frameworks/$m.framework/Modules" "usr/lib/swift"; do
    patterns+="/$SDK/$base/$m.swiftmodule/arm64e-apple-ios.swiftinterface"$'\n'
  done
done
stamp="$COMMIT $(printf '%s' "$patterns" | sha1sum | cut -c1-12)"

if [ -f "$dest/.complete" ] && [ "$(cat "$dest/.complete")" = "$stamp" ] && [ -d "$dest/$SDK" ]; then
  echo "$dest/$SDK"; exit 0
fi
if [ ! -d "$dest/.git" ]; then
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$dest" init -q .
  git -C "$dest" remote add origin "$REPO"
  git -C "$dest" config core.sparseCheckout true
  printf '%s' "$patterns" > "$dest/.git/info/sparse-checkout"
  git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$COMMIT" >&2
  git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD >&2
else
  printf '%s' "$patterns" > "$dest/.git/info/sparse-checkout"
  git -C "$dest" read-tree -mu HEAD >&2
fi
echo "$stamp" > "$dest/.complete"
echo "$dest/$SDK"
