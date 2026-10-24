# App updates

Sound Control checks the public [GitHub releases](https://github.com/timothyosm/sound-control/releases) once a day while it is running. Choose **Updates > Check for updates** to check immediately. **Check automatically** turns scheduled checks on or off.

The app offers **Update and restart** when a newer compatible version is available. **Later** leaves the app unchanged; the next daily check can offer it again. Checks never alter headphone settings. Restarting reconnects to the headphones.

## Verification and installation

The app uses an embedded Ed25519 public key to verify a signed JSON release record. The record contains the version, increasing build number, minimum macOS version, exact download URL, archive size and SHA-256 digest. Downloads use HTTPS. The updater limits metadata to 64 KiB and archives to 100 MB. It verifies the archive before extraction and checks the app’s bundle identifier, build number and code signature before installation.

A detached helper waits for the app to close. It stages the new app beside the installed copy, preserves the old copy and replaces it. If replacement or the relaunch command fails, it restores the old copy. A successful relaunch command does not prove that the new version will remain healthy. A power failure during replacement can leave a hidden `.SoundControl-backup-…app` folder beside the app; retain it for recovery.

The updater does not request administrator access. The app must be in a folder you can write to. It does not install older or equal build numbers, send headphone information, or collect analytics. GitHub receives normal download requests, including your IP address.

The preference `updates.automatic` and last successful check time `updates.lastCheck` are stored in the existing SQLite database. Download staging files are temporary. Signing credentials are stored in the maintainer’s macOS Keychain and are never included in releases or the repository.

The app currently uses ad hoc code signing. It is not Apple-notarised. A first-time download may need approval in macOS Privacy & Security settings. Future updates are authenticated with the embedded release key.

## Publish a release

Use the maintainer’s Mac, where the release signing key is available. Increase both `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`. Add release notes, commit the changes and push to `main`. Then run:

```sh
./scripts/release.sh docs/releases/0.6.0.md
```

Use the notes file for the version you are publishing. The script tests both protocols and update verification, builds the universal app, tests replacement and rollback, signs the release record, uploads a draft release and publishes it only after both assets are present. Existing release versions cannot be overwritten by this script.

The stable update address is `https://github.com/timothyosm/sound-control/releases/latest/download/update.json`. Each signed record points to its exact version’s `SoundControl.zip`. GitHub Actions builds and tests commits but cannot sign or publish updates: the private key stays on the maintainer’s Mac.

The Keychain item uses service `app.timothyosmond.SoundControl.release-signing` and account `ed25519-v1`. Keep a secure backup of the signing credential. Losing it requires a fresh manually installed release with a new public key. Never put the private key in Git, logs or release assets.

## Tests

Run `./scripts/test.sh` for signature, malformed-record, version, URL, size and hash checks, together with the existing device and storage tests. Run `./scripts/build.sh` followed by `./scripts/test-update-installation.sh` for replacement, build mismatch, rollback, relaunch-command failure and cleanup tests on temporary app copies. These tests do not replace the installed app or change headphone settings.
