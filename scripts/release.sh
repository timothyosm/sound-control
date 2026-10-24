#!/bin/bash
# Run on the maintainer's Mac. The signing key stays in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! -f "$1" ]]; then echo 'Usage: ./scripts/release.sh release-notes.md' >&2; exit 2; fi
NOTES="$1"
if [[ -n "$(git status --porcelain)" ]]; then echo 'Commit changes before publishing a release.' >&2; exit 1; fi
RELEASE_COMMIT=$(git rev-parse HEAD)
if [[ "$(git ls-remote origin refs/heads/main | cut -f1)" != "$RELEASE_COMMIT" ]]; then echo 'Push the release commit to main first.' >&2; exit 1; fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
TAG="v$VERSION"
if gh release view "$TAG" --repo timothyosm/sound-control >/dev/null 2>&1; then echo 'This release already exists. Use a new version.' >&2; exit 1; fi
./scripts/test.sh
./scripts/build.sh
./scripts/test-update-installation.sh
swiftc Sources/UpdateManifest.swift Tools/ReleaseSigner.swift -o build/ReleaseSigner
KEY=$(build/ReleaseSigner public-key)
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print :UpdatePublicKey' Info.plist)
if [[ "$KEY" != "$EXPECTED" ]]; then echo 'The release key does not match the app.' >&2; exit 1; fi
mkdir -p build/release
ditto -c -k --keepParent --noextattr 'build/Sound Control.app' build/release/SoundControl.zip
build/ReleaseSigner build/release/SoundControl.zip "$VERSION" "$BUILD" "$MINIMUM" build/release/update.json
gh release create "$TAG" build/release/SoundControl.zip build/release/update.json --repo timothyosm/sound-control --target "$RELEASE_COMMIT" --title "Sound Control $VERSION" --notes-file "$NOTES" --draft
gh release edit "$TAG" --repo timothyosm/sound-control --draft=false --latest
