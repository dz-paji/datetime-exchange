#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$PROJECT_DIR/时间转换.app"
CACHE_DIR="$BUILD_DIR/module-cache"
TARGET_ARCH="$(uname -m)"
mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

xcrun swiftc -O -module-cache-path "$CACHE_DIR" \
  "$PROJECT_DIR/Sources/TimeConversion.swift" "$PROJECT_DIR/Tests/main.swift" \
  -o "$BUILD_DIR/conversion-tests"
"$BUILD_DIR/conversion-tests"

xcrun swiftc -O -module-cache-path "$CACHE_DIR" \
  "$PROJECT_DIR/Sources/TimeConversion.swift" "$PROJECT_DIR/Sources/SQLGeneration.swift" "$PROJECT_DIR/SQLTests/main.swift" \
  -o "$BUILD_DIR/sql-tests"
"$BUILD_DIR/sql-tests"

xcrun swiftc -O -module-cache-path "$CACHE_DIR" \
  "$PROJECT_DIR/Sources/TimeConversion.swift" "$PROJECT_DIR/Sources/SQLGeneration.swift" "$PROJECT_DIR/Sources/SQLFieldStore.swift" "$PROJECT_DIR/SQLStoreTests/main.swift" \
  -o "$BUILD_DIR/sql-store-tests"
"$BUILD_DIR/sql-store-tests"

xcrun swiftc -O -parse-as-library -whole-module-optimization -module-cache-path "$CACHE_DIR" \
  -target "$TARGET_ARCH-apple-macosx13.0" -framework AppKit \
  "$PROJECT_DIR"/Sources/*.swift \
  -o "$APP_DIR/Contents/MacOS/TimeConverter"

if [[ ! -f "$APP_DIR/Contents/Resources/AppIcon.icns" || "$PROJECT_DIR/Tools/MakeIcon.swift" -nt "$APP_DIR/Contents/Resources/AppIcon.icns" ]]; then
  xcrun swiftc -O -module-cache-path "$CACHE_DIR" -framework AppKit \
    "$PROJECT_DIR/Tools/MakeIcon.swift" -o "$BUILD_DIR/make-icon"
  "$BUILD_DIR/make-icon" "$BUILD_DIR/AppIcon.iconset"
  iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>时间转换</string>
  <key>CFBundleDisplayName</key><string>时间转换</string>
  <key>CFBundleExecutable</key><string>TimeConverter</string>
  <key>CFBundleIdentifier</key><string>local.timeconverter.mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf '已生成：%s\n' "$APP_DIR"
