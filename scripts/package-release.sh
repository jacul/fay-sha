#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Release archives support both Apple silicon and Intel Macs.
UNIVERSAL=1 bash scripts/build-app.sh
ARCHITECTURES="$(lipo -archs dist/FaySHA.app/Contents/MacOS/FaySHA)"
for REQUIRED_ARCH in arm64 x86_64; do
    case " $ARCHITECTURES " in
        *" $REQUIRED_ARCH "*) ;;
        *) echo "Release is missing $REQUIRED_ARCH." >&2; exit 1 ;;
    esac
done
VERSION="$(cat VERSION)"
ARCHIVE="FaySHA-${VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent dist/FaySHA.app "dist/$ARCHIVE"
(
    cd dist
    shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
    shasum -a 256 -c "$ARCHIVE.sha256"
)
printf 'Packaged %s/dist/%s\n' "$PWD" "$ARCHIVE"
