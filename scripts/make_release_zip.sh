#!/usr/bin/env bash
# Packs a release .ipa with a short German install note into one .zip: a download that works without the GitHub
# release page (Dateien-App on the iPhone unpacks it, then "Teilen › AltStore/SideStore").
# Usage: make_release_zip.sh <path/to/KlimaBilanz-X.Y.Z.ipa> <version> <build> <out.zip>
set -euo pipefail
IPA="$1"; VERSION="$2"; BUILD="$3"; OUT="$4"
test -f "$IPA" || { echo "::error::$IPA fehlt"; exit 1; }
NAME="$(basename "$IPA")"
SHA="$(sha256sum "$IPA" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$IPA" | cut -d' ' -f1)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$IPA" "$STAGE/$NAME"
cat > "$STAGE/INSTALLIEREN.txt" <<NOTE
KlimaBilanz ${VERSION} (Build ${BUILD}) – installieren

1. Diese .zip auf dem iPhone in der Dateien-App antippen: sie entpackt sich von selbst.
2. ${NAME} lange drücken › Teilen › AltStore (oder SideStore) wählen.
   Oder in AltStore/SideStore: Meine Apps › „+“ › die .ipa auswählen.
3. Mit der kostenlosen Apple-ID unterschreibt AltStore/SideStore die App für 7 Tage;
   danach in AltStore/SideStore „Aktualisieren“ bzw. „Refresh“ tippen.

Ein Update auf eine neuere KlimaBilanz behält deine Daten, solange du die App nicht löschst.

Prüfsumme der .ipa (SHA-256):
${SHA}
NOTE
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$STAGE" && zip -q -X -9 "$OUT_ABS" "$NAME" INSTALLIEREN.txt)
unzip -t -q "$OUT_ABS"
ls -l "$OUT_ABS"
