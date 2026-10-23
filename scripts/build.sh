#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/linkbuds-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/LinkBudsBar.app"
mkdir -p "$APP/Contents/MacOS" build
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework IOBluetooth -framework ServiceManagement Sources/*.swift -o "$APP/Contents/MacOS/LinkBudsBar"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
ditto --noextattr "$APP" build/LinkBudsBar.app
xattr -cr build/LinkBudsBar.app
echo "Built $PWD/build/LinkBudsBar.app"
