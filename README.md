<picture>
  <img src="docs/images/sound-control-header.jpg" alt="" width="1086">
</picture>

# Sound Control

Control your headphones from the macOS menu bar. Sound Control lets you change noise settings, check batteries and adjust other supported features without opening a phone app.

You need a Mac with Apple silicon or an Intel processor, macOS 13 or later, and compatible Bluetooth headphones. Only Sony LinkBuds S has been tested on a physical device. Support for other Sony models, Nothing and CMF devices needs further testing.

## Headphone compatibility

Sound Control checks the features your headphones report before showing their controls. Available settings depend on the model and firmware, which is the software inside your headphones.

The current testing status is:

- **Sony LinkBuds S** has passed device tests for noise controls, battery readings and extra settings with firmware 4.3.1.
- **Other Sony headphones** have simulated tests for their communication formats but have not been tested on physical devices.
- **Nothing and CMF devices** have experimental support, with simulated tests only.

Sony candidates include WH-1000XM3, WH-1000XM4, WH-1000XM5, WH-1000XM6, WF-1000XM5, WH-CH720N and WF-C700N. Ear (open) and Ear (stick) do not expose noise controls in this app.

A listed model is not a guarantee of compatibility. Devices that report battery levels but lack supported sound controls may show batteries only. TVs, cameras, consoles, speakers and devices that connect only through USB or Bluetooth Low Energy are not supported.

## Install Sound Control

Install the app from the public GitHub release:

1. Open the [Sound Control download and release notes](https://github.com/timothyosm/sound-control/releases/latest).
2. Download **SoundControl.zip** from **Assets**.
3. Quit any running copy of Sound Control.
4. Open the downloaded ZIP file to extract the app.
5. Move **Sound Control.app** to your **Applications** folder and open it.
6. Pair and connect your headphones in macOS Bluetooth settings.
7. Allow Bluetooth access when macOS asks.

The app appears in the menu bar and has no Dock icon. Choose **Open at login** if you want it to start when you log in.

Apple has not notarised the app, and it is not signed with an Apple Developer ID. macOS may ask you to approve the first launch in **System Settings > Privacy & Security**. Signed update records verify later downloads; they do not replace Apple notarisation.

## Change headphone settings

Open Sound Control from the menu bar. Choose **Headphones** to select a device, or let the app choose connected headphones automatically.

Choose **Noise cancelling**, **Ambient sound**, **Transparency** or **Off**, where available. Open **More settings** for additional controls. The app reads settings back from your headphones to confirm changes.

### Sony settings

Supported Sony devices can offer:

- equaliser presets, Clear Bass and 5 frequency bands
- Speak-to-Chat and automatic pause when you remove the headphones
- automatic power off and voice guidance
- multipoint, which connects the headphones to 2 devices
- touch control assignments, sound enhancement and a connection preference.

These setting types were discovered on LinkBuds S. The [extra control implementation and test results](docs/extra-controls.md) distinguish changed settings from checks that wrote the existing value. Sony devices using the older communication format retain their noise and battery controls but do not gain these extra settings.

Choosing an ambient level turns on ambient sound. **Focus on voices** is available when the headphones report support for it.

### Nothing and CMF settings

Supported devices can offer:

- noise cancelling strength and personalised noise cancelling
- equaliser presets and a switch for the existing advanced equaliser profile
- automatic pause and low-lag mode
- dual connection and bass enhancement.

Choosing a noise cancelling strength turns on noise cancelling. The advanced equaliser switch does not edit the profile’s frequency bands. Read the [Nothing and CMF support notes](docs/nothing-protocol.md) for model and firmware limitations.

## Keep the app up to date

Sound Control checks for updates daily while it is running. Choose **Updates > Check for updates** to check immediately. When an update is available, choose **Update and restart** to install it and keep your saved settings.

Turn off **Updates > Check automatically** to stop scheduled checks. Versions before 0.6.0 need one manual installation to gain the updater.

The app verifies downloads before installation. It keeps the previous copy available to restore if replacement or the relaunch command fails. Read the [update checks, installation and recovery guide](docs/updates.md) for details.

## Fix connection problems

If your headphones do not appear, reconnect them in macOS Bluetooth settings. If a connection times out, close other headphone control apps and choose **Reconnect** in Sound Control.

Choose **Refresh** to read the settings again. Missing battery readings appear as **Unknown**. The charging case reading may be out of date while the case is disconnected.

You can [report a Sound Control problem](https://github.com/timothyosm/sound-control/issues). Include your headphone model, firmware version, macOS version and the steps that caused the problem. Reports are public, so remove personal information from any logs you attach.

## Privacy and saved settings

Sound Control does not require an account or collect analytics. Update checks contact GitHub, which receives normal connection information, including your device’s internet protocol address.

The app stores your preferences in SQLite, a local database included with macOS. Saved records include your headphone selection, update preference, last successful update check and test recovery data. The database is at:

```text
~/Library/Application Support/Sound Control/settings.sqlite3
```

Battery readings and live headphone settings stay in memory and are read again from the device. macOS manages Bluetooth pairing, permissions and login startup. Diagnostic logs are created only when you supply the optional `--log` argument.

## Build and test the app

You need Git and Apple’s Command Line Tools to build from source. Run `xcode-select --install` if the tools are not installed.

Clone the repository, then run the tests and build:

```sh
git clone https://github.com/timothyosm/sound-control.git
cd sound-control
./scripts/test.sh
./scripts/build.sh
./scripts/test-update-installation.sh
```

The app is created at `build/Sound Control.app`. The [build and device testing guide](docs/testing.md) explains installation, optional hardware tests and their limits. Device tests temporarily change headphone settings.

The app does not update headphone firmware or provide location-based controls. Login startup and sleep and wake behaviour need longer-term testing.

## Licence and credits

Sound Control is available under the [MIT licence](LICENSE). It is an independent project and is not affiliated with Sony, Nothing or CMF.

The Sony implementation draws on [SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge) and [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient). Their notices are retained in [third-party licences](THIRD_PARTY_LICENSES). The protocol guides identify the sources used for additional controls.

The header is an illustration generated with artificial intelligence, not an app screenshot. Its [image source and generation prompt](docs/images/README.md) are recorded with the artwork.

Project wording uses the [Australian Government Style Manual](https://www.stylemanual.gov.au/). The [project style sheet](docs/style.md) records the writing conventions.
