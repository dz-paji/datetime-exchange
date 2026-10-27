#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$PROJECT_DIR/时间转换.app"
RELEASE_DIR="$PROJECT_DIR/发布包"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
WORK_DIR="$(mktemp -d /private/tmp/time-converter-release.XXXXXX)"
cleanup() {
  local result=$?
  if [[ "$result" == 0 ]]; then
    rm -rf "$WORK_DIR"
  else
    printf '构建未完成，保留诊断目录：%s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT
CACHE_DIR="$WORK_DIR/module-cache"
APP_DIR="$WORK_DIR/时间转换.app"
IMAGE_DIR="$WORK_DIR/image"
ZIP_DIR="$WORK_DIR/时间转换 $VERSION"
ARCHIVE_NAME="时间转换-${VERSION}-macOS-Universal"
mkdir -p "$CACHE_DIR" "$RELEASE_DIR" "$IMAGE_DIR"

# Stage the app separately so packaging never replaces the running local app.
ditto "$SOURCE_APP" "$APP_DIR"
for architecture in arm64 x86_64; do
  xcrun swiftc -O -parse-as-library -whole-module-optimization \
    -module-cache-path "$CACHE_DIR" -target "$architecture-apple-macosx13.0" \
    -framework AppKit "$PROJECT_DIR"/Sources/*.swift \
    -o "$WORK_DIR/TimeConverter-$architecture"
done
lipo -create "$WORK_DIR/TimeConverter-arm64" "$WORK_DIR/TimeConverter-x86_64" \
  -output "$APP_DIR/Contents/MacOS/TimeConverter"

# This is explicitly an ad-hoc signed test distribution, not Developer ID / notarized.
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/TimeConverter" -verify_arch arm64
lipo "$APP_DIR/Contents/MacOS/TimeConverter" -verify_arch x86_64
plutil -lint "$APP_DIR/Contents/Info.plist"

ditto "$APP_DIR" "$IMAGE_DIR/时间转换.app"
cp "$RELEASE_DIR/安装与使用说明.txt" "$IMAGE_DIR/安装与使用说明.txt"
ln -s /Applications "$IMAGE_DIR/Applications"
mkdir -p "$ZIP_DIR"
ditto "$APP_DIR" "$ZIP_DIR/时间转换.app"
cp "$RELEASE_DIR/安装与使用说明.txt" "$ZIP_DIR/安装与使用说明.txt"
ditto -c -k --sequesterRsrc --keepParent "$ZIP_DIR" "$RELEASE_DIR/$ARCHIVE_NAME.zip"
hdiutil create -volname "时间转换 $VERSION" -srcfolder "$IMAGE_DIR" \
  -format UDZO -ov "$RELEASE_DIR/$ARCHIVE_NAME.dmg"
hdiutil verify "$RELEASE_DIR/$ARCHIVE_NAME.dmg"

python3 - "$RELEASE_DIR" "$ARCHIVE_NAME" <<'PY'
import hashlib
import pathlib
import sys
directory, basename = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = []
for suffix in ("zip", "dmg"):
    artifact = directory / f"{basename}.{suffix}"
    lines.append(f"{hashlib.sha256(artifact.read_bytes()).hexdigest()}  {artifact.name}")
(directory / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
printf '已生成通用 Mac 测试分发包（未做 Developer ID 签名/Apple 公证）：%s\n' "$RELEASE_DIR/$ARCHIVE_NAME.dmg"
