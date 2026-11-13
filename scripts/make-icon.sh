#!/usr/bin/env bash
# Ilova ikonkasini (Resources/AppIcon.icns) qaytadan chizadi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Tayyor: Resources/AppIcon.icns"
