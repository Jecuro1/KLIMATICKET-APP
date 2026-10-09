#!/usr/bin/env bash
# Regenerate every SDK-derived stub interface (Stubs/<M>/<M>.swiftinterface) in
# dependency order. Needs a checkout of the iOS SDK's .swiftinterface files:
#   KB_IOS_SDK_REF=/path/to/iPhoneOS26.x.sdk gen/regen_all.sh [Module...]
# (see README "Regenerating the generated stubs" for how to get one).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
: "${KB_IOS_SDK_REF:?set KB_IOS_SDK_REF to an iPhoneOS SDK directory}"
mods=("$@")
if [ ${#mods[@]} -eq 0 ]; then
  mods=($(python3 -c "import sys; sys.path.insert(0, '$here'); import transform; print(' '.join(transform.GENERATED_ORDER))"))
fi
for m in "${mods[@]}"; do
  python3 "$here/transform.py" "$m" | grep -v '^  \[' || { echo "regeneration of $m failed" >&2; exit 1; }
done
