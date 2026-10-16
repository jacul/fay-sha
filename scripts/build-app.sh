#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
VERSION="$(cat VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain a version such as 1.0.0." >&2
    exit 1
fi
BUILD_ARGS=(-c release --disable-sandbox --cache-path "$PWD/.build/cache")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
# All build artifacts stay in the project. No package plugins are used.
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="dist/FaySHA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
bash scripts/build-icon.sh
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/FaySHA" "$APP/Contents/MacOS/FaySHA"
# Remove debug records and local symbols before replacing the code signature.
xcrun strip -S -x "$APP/Contents/MacOS/FaySHA"
# Fail packaging if a compiler leaves local source or build paths behind.
if LC_ALL=C /usr/bin/grep -aEq '/(Users|home)/' "$APP/Contents/MacOS/FaySHA" ||
    LC_ALL=C /usr/bin/grep -aFq "$PWD/" "$APP/Contents/MacOS/FaySHA"; then
    echo "The app binary contains a local path. Refusing to package it." >&2
    exit 1
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>FaySHA</string>
    <key>CFBundleIdentifier</key><string>local.faysha.app</string>
    <key>CFBundleName</key><string>FaySHA</string>
    <key>CFBundleDisplayName</key><string>FaySHA</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>FaySHA</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
