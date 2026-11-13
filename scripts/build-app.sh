#!/usr/bin/env bash
# Snowfall.app ni yig'adi (Apple Silicon + Intel uchun bitta universal ilova).
#
#   scripts/build-app.sh [versiya] [build-raqami]
#   scripts/build-app.sh 1.2.0 15
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Har bir arxitekturani alohida yig'ib, lipo bilan bitta faylga birlashtiramiz.
# (Bu faqat Command Line Tools o'rnatilgan Mac'da ham, to'liq Xcode'da ham ishlaydi.)
BINARIES=()
for arch in arm64 x86_64; do
  # Har arxitektura o'z papkasida yig'iladi, aks holda SwiftPM keshi chalkashib ketadi.
  opts=(-c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch")
  swift build "${opts[@]}"
  BINARIES+=("$(swift build "${opts[@]}" --show-bin-path)/Snowfall")
done

APP="dist/Snowfall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Snowfall"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc imzo: Apple Developer akkauntisiz ham ilova Apple Silicon'da ishga tushadi.
codesign --force --sign - --timestamp=none "$APP"

echo "Tayyor: $APP (versiya $VERSION, build $BUILD)"
lipo -info "$APP/Contents/MacOS/Snowfall"
