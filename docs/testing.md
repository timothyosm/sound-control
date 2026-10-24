# Build and device testing

Sound Control includes automated checks and optional tests on connected Sony headphones. Automated checks use simulated messages; they cannot establish compatibility with every physical device.

## Build and install from source

You need macOS 13 or later, Git and Apple’s Command Line Tools. Run `xcode-select --install` if the tools are missing.

From the repository folder, run:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/test-update-installation.sh
```

The build includes Apple silicon and Intel versions of the app. It uses an ad hoc signature and is not notarised by Apple.

Quit any running copy of Sound Control before installing the build:

```sh
ditto --noextattr "build/Sound Control.app" "/Applications/Sound Control.app"
open "/Applications/Sound Control.app"
```

## Automated checks

The test suite covers Bluetooth messages, simulated device support, SQLite storage and signed update records. Storage checks include migration, reopening the database, rejected writes, locked databases and damaged files.

The installation test uses temporary app copies. It checks replacement, signature damage, build mismatches, rollback, relaunch-command failure and cleanup. It does not replace the installed app or change headphone settings.

## Sony device tests

Device tests temporarily change your sound settings and try to restore them. If Bluetooth disconnects during a test, restoration may fail. Reconnect your headphones and restore your preferred settings from the menu.

### Test noise controls

Quit the running app, connect your Sony headphones and start the test:

```sh
open "build/Sound Control.app" --args --hardware-test --log /tmp/sound-control-hardware.log
```

The log records each check and whether the original settings were restored. LinkBuds S passed noise cancelling, off, ambient sound, voice focus and restoration checks. These results confirm settings reported by the device; they do not measure sound quality or noise reduction.

### Test additional controls

Quit the running app before starting this separate test:

```sh
open "build/Sound Control.app" --args --extra-hardware-test --log /tmp/sound-control-extra-test.log
```

The test changes DSEE, Speak-to-Chat, automatic pause and voice guidance, then restores each setting. It writes the current value for equaliser presets, power, connection and touch controls. It does not change custom equaliser bands.

The test saves a restoration record in SQLite before each write. If it stops before confirming restoration, reconnect the same headphones and rerun the test. A normal app launch does not apply pending test settings.

Read the [recorded LinkBuds S results](extra-controls.md#verification) for the exact scope. Nothing and CMF support has simulated tests only.

## Publish updates

Follow the [release preparation and publishing instructions](updates.md#publish-a-release). Release signing requires the maintainer’s Keychain credential. Do not include that credential in source code, logs or release assets.
