#!/usr/bin/env bash
# Construye build/Notchwatch.app a partir del binario de SwiftPM.
#   scripts/bundle.sh                 → binario de la arquitectura actual
#   UNIVERSAL=1 scripts/bundle.sh     → binario universal (arm64 + x86_64)
#   VERSION=0.2.0 scripts/bundle.sh   → fuerza la versión (si no, sale del último tag)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Notchwatch"
BUNDLE_ID="com.joandev.notchwatch"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")"
fi
VERSION="${VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "▸ Compilando $APP_NAME $VERSION ($BUILD_NUMBER)"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

if [[ ! -f "$BIN" ]]; then
  echo "✗ No encuentro el binario en $BIN" >&2
  exit 1
fi

echo "▸ Montando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # El self-test solo ejecuta la arquitectura del runner: comprobamos que van las dos.
  lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/$APP_NAME"
  echo "  binario universal: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>es</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 Joan Dev &amp; Tech</string>
</dict>
</plist>
PLIST

echo "▸ Generando icono"
ICON_PNG="$BUILD_DIR/icon-1024.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
if swift scripts/make-icon.swift "$ICON_PNG" >/dev/null 2>&1 && [[ -f "$ICON_PNG" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
    echo "  icono listo"
  else
    echo "  ⚠︎ iconutil falló: la app irá sin icono"
  fi
else
  echo "  ⚠︎ No se pudo dibujar el icono: la app irá sin icono"
fi

echo "▸ Firmando (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "✓ $APP ($VERSION)"
