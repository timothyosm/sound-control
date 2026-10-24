# Sound Control

Sound Control lets you change headphone settings from the macOS menu bar. It supports compatible Sony headphones and has experimental support for Nothing and CMF devices.

You can:

- switch between noise cancelling, ambient sound or transparency, and off
- adjust ambient sound levels and focus on voices on supported Sony devices
- check headphone and charging case batteries
- choose your headphones and reconnect automatically
- open the app when you log in.

## Compatibility

Only LinkBuds S has been tested on a physical device. Tests for other devices use simulated messages. Model examples below are candidates for testing, not guarantees of compatibility.

| Device or protocol | Support |
| --- | --- |
| LinkBuds S with firmware 4.3.1 | Tested on a device: feature discovery, sound changes, battery readings and restoration of original settings |
| Nothing and CMF headphones and earbuds | Experimental noise cancelling, transparency and battery controls; no device testing |
| Sony MDR V1, such as WH-1000XM3 and WH-1000XM4 | Tested with simulated messages; no device testing |
| Sony MDR V2, such as WH-1000XM5, WH-1000XM6, WF-1000XM5, WH-CH720N and WF-C700N | Supported message formats are implemented; these models need device testing |
| Devices that report batteries but lack supported sound controls | Battery readings only |
| TVs, cameras, consoles, speakers and devices that use only USB or Bluetooth Low Energy | Not supported |

The app checks the services and features that each device reports before enabling controls. Renaming your headphones does not prevent discovery.

Nothing and CMF controls appear after the app receives valid settings. The menu shows that these devices have not been tested. Ear (open) and Ear (stick) provide battery readings only. Read the [Nothing and CMF protocol notes](docs/nothing-protocol.md) for details.

## Install and open the app

You need macOS 13 or later and Apple’s Command Line Tools. Run `xcode-select --install` if the tools are not installed.

From the repository folder, run:

```sh
./scripts/test.sh
./scripts/build.sh
ditto --noextattr "build/Sound Control.app" "/Applications/Sound Control.app"
open "/Applications/Sound Control.app"
```

Pair and connect your headphones in macOS Bluetooth settings. Allow Bluetooth access if macOS asks. The app appears in the menu bar and has no Dock icon.

Choose **Open at login** in the app’s menu to start it when you log in. macOS manages this registration.

The build runs on the local Mac’s processor architecture and uses an ad hoc signature. It is not signed with an Apple Developer ID or notarised. Build the app on each Mac where you plan to use it.

## Saved settings

The app stores preferences in a local SQLite database:

```text
~/Library/Application Support/Sound Control/settings.sqlite3
```

The database currently stores your headphone selection. It also records completed data migrations. The app moves your existing selection from macOS preferences on its first successful launch after this update.

Migration runs in a transaction. The app removes the old preference only after the transaction succeeds. If the database cannot open, the app shows an error and stops. If a selection cannot be saved, the app keeps the previous selection and shows an error.

Live battery readings and sound settings stay in memory and are read again from your headphones. macOS manages Bluetooth pairing, permissions and login registration. The app does not copy these system settings into its database.

There are no accounts or analytics. The app uses the SQLite library included with macOS. Diagnostic files are written only when you pass the optional `--log` argument.

## Sound controls

The app checks each Sony device’s supported features before requesting settings. Choose a device under **Headphones**, or let the app choose connected headphones automatically.

Commands run one at a time. After a sound change, the app reads the setting back to check that it applied. Acknowledgement of a command alone does not confirm success.

Choosing an ambient level turns on ambient sound. **Focus on voices** is available only when the device reports support for it. The available levels come from the device.

Unknown battery readings appear as **Unknown**. The charging case reading may be out of date while the case is disconnected.

If a connection times out, close other headphone control apps and choose **Reconnect**. If the device does not appear, reconnect it through macOS Bluetooth settings.

## Tests

Run `./scripts/test.sh` to check message handling, simulated device support and SQLite storage. Storage tests cover migration, reopening the database, failed writes, locked databases and damaged files.

The optional device test works with Sony headphones only. **It briefly changes your sound settings**, checks the available controls and restores the original settings. Quit the running app before starting it:

```sh
open "build/Sound Control.app" --args --hardware-test --log /tmp/sound-control-hardware.log
```

The log records each check and the restoration result. If Bluetooth disconnects during testing, restoration may fail. Reconnect and restore your preferred mode from the menu.

The LinkBuds S test passed for noise cancelling, off, ambient sound at level 10, voice focus and restoration of the original settings. These checks confirm the settings reported by the device. They do not measure sound quality or noise reduction.

## Limits

The app does not provide an equaliser, firmware updates, location-based controls or controls for other product types. Login startup and sleep and wake behaviour need longer-term testing.

Sony sound formats include V1 noise cancelling (`01`), combined noise cancelling and ambient sound (`02`), and ambient sound (`03`). V2 formats include noise cancelling (`01`), combined controls (`13`, `14`, `16`, `17`, `18`, `19`), and ambient sound (`21`, `22`). Format `19` preserves the device’s noise adaptation fields. Other formats remain unsupported. Wind reduction and adaptive modes are not separate menu controls.

## Writing style

App wording and documentation follow the [Australian Government Style Manual](https://www.stylemanual.gov.au). The [project style sheet](docs/style.md) records the conventions for future changes.

## Protocol references and licences

This independent Swift implementation draws on [SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge) at commit `8c81a2775a76097f4938fbc835411bd59088014c` and [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) at commit `8f4808cb635f5a176df0b7b5aea959818be5129e`.

Their MIT notices remain in `THIRD_PARTY_LICENSES`. Sound Control is unofficial and is not affiliated with Sony, Nothing or CMF.
