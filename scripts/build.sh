#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/sound-control-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Sound Control.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" build
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" -lsqlite3 -framework AppKit -framework IOBluetooth -framework ServiceManagement Sources/*.swift -o "$STAGING/SoundControl-$ARCH"
    swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" -framework AppKit Sources/UpdateManifest.swift Sources/UpdateInstallation.swift Tools/UpdateInstaller.swift -o "$STAGING/UpdateInstaller-$ARCH"
done
lipo -create "$STAGING/SoundControl-arm64" "$STAGING/SoundControl-x86_64" -output "$APP/Contents/MacOS/SoundControl"
lipo -create "$STAGING/UpdateInstaller-arm64" "$STAGING/UpdateInstaller-x86_64" -output "$APP/Contents/Helpers/UpdateInstaller"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Helpers/UpdateInstaller"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto --noextattr "$APP" "build/Sound Control.app"
xattr -cr "build/Sound Control.app"
echo "Built $PWD/build/Sound Control.app"
