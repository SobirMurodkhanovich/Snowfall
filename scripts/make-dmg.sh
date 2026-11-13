#!/usr/bin/env bash
# dist/Snowfall.app dan o'rnatish uchun .dmg yasaydi.
#
#   scripts/make-dmg.sh [dmg-yo'li]
#   scripts/make-dmg.sh dist/Snowfall-1.0.0.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG="${1:-dist/Snowfall.dmg}"
APP="dist/Snowfall.app"
[[ -d "$APP" ]] || { echo "Avval scripts/build-app.sh ni ishga tushiring" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications" # ilovani shu papkaga sudrab tashlash uchun

rm -f "$DMG"
# GitHub'ning macOS serverlarida hdiutil ba'zan "Resource busy" beradi, shuning uchun qayta urinamiz.
for attempt in 1 2 3 4 5; do
  if hdiutil create -volname "Snowfall" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"; then
    break
  fi
  if [[ $attempt == 5 ]]; then
    echo "hdiutil 5 marta xato berdi" >&2
    exit 1
  fi
  echo "hdiutil xato berdi, ${attempt}-urinish; qayta urinilmoqda..." >&2
  sleep $((attempt * 3))
done

echo "Tayyor: $DMG"
