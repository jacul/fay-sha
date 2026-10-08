#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
# All build artifacts stay in the project. No package plugins are used.
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
BIN_DIR="$(swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --show-bin-path)"
APP="dist/FaySHA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FaySHA" "$APP/Contents/MacOS/FaySHA"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>FaySHA</string>
    <key>CFBundleIdentifier</key><string>local.faysha.app</string>
    <key>CFBundleName</key><string>FaySHA</string>
    <key>CFBundleDisplayName</key><string>FaySHA</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>FaySHA</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
