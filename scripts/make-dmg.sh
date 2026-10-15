#!/usr/bin/env bash
# Empaqueta build/Notchwatch.app en un DMG con acceso directo a Aplicaciones y su .sha256.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Notchwatch.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Falta $APP: ejecuta antes scripts/bundle.sh" >&2
  exit 1
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
VERSION="${VERSION#v}"
DMG_NAME="Notchwatch-$VERSION.dmg"
DMG="build/$DMG_NAME"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
# hdiutil a veces falla con "Resource busy" en los runners: reintentamos.
for attempt in 1 2 3; do
  if hdiutil create -volname "Notchwatch $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"; then
    break
  fi
  if [[ "$attempt" == "3" ]]; then
    echo "✗ hdiutil falló 3 veces" >&2
    exit 1
  fi
  echo "  hdiutil falló, reintento en 5 s…"
  sleep 5
done

(cd build && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "✓ $DMG"
cat "build/$DMG_NAME.sha256"
