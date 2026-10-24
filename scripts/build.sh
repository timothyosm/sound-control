#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/sound-control-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Sound Control.app"
mkdir -p "$APP/Contents/MacOS" build
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -lsqlite3 -framework AppKit -framework IOBluetooth -framework ServiceManagement Sources/*.swift -o "$APP/Contents/MacOS/SoundControl"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
ditto --noextattr "$APP" "build/Sound Control.app"
xattr -cr "build/Sound Control.app"
echo "Built $PWD/build/Sound Control.app"
