# LinkBudsBar

A tiny native macOS menu bar app for Sony LinkBuds S. Click the earbuds icon in the menu bar to control sound without reaching for your phone.

- Noise Cancelling, Ambient Sound, and Off
- Ambient level 1–20 and voice focus
- Earbud and charging-case battery readings
- Automatic reconnect, refresh, and optional Open at Login
- No accounts, network services, runtime dependencies, or telemetry

## Build and run

Requires macOS 13 or newer and Apple's Command Line Tools (`xcode-select --install`).

```sh
./scripts/test.sh
./scripts/build.sh
open build/LinkBudsBar.app
```

Copy `build/LinkBudsBar.app` to Applications for a permanent installation. Pair and connect **LinkBuds S** in macOS Bluetooth Settings first. Allow Bluetooth access if macOS asks. The app runs only in the menu bar; it has no Dock icon. Open at Login is opt-in from its menu.

The build uses the local Mac's architecture and ad-hoc signing. It is not Developer ID signed or notarized; building locally is recommended for other Macs.

## How it works

The app discovers the paired LinkBuds S by name, opens Sony's second-generation Bluetooth RFCOMM service, performs the initialization handshake, and reads settings. It sends one request at a time, validates incoming frame lengths/checksums, acknowledges device packets, and reads settings back after changes. Checkmarks reflect device-reported state. A periodic refresh also picks up changes made elsewhere.

Choosing an ambient level activates Ambient Sound. Voice focus is available in Ambient Sound mode. Battery percentages are the values reported by the earbuds (case values can be stale while the case is disconnected). Missing readings appear as a dash.

If disconnected, connect the earbuds in Bluetooth Settings. If control times out, close Sony Sound Connect on your phone and other Sony control apps, then choose Reconnect. Audio pairing is managed by macOS; this app only closes its own control channel.

## Verification

`./scripts/test.sh` checks packet fragmentation, concatenated frames, all escaped bytes, corrupt checksums/lengths, malformed-stream recovery, bounded buffers, and sound-setting parsing.

An optional hardware check **changes your sound settings briefly**, tests the three modes, ambient level and voice focus, then restores the settings read at the start. Quit any running copy before invoking it:

```sh
open build/LinkBudsBar.app --args --hardware-test --log /tmp/linkbuds-hardware.log
```

The log reports each read-back result and restoration. If Bluetooth disconnects during the check, restoration cannot be guaranteed; restore the desired mode from the menu after reconnecting. Normal launches do not write logs.

Hardware verification on LinkBuds S firmware 4.3.1 passed: Noise Cancelling, Off, Ambient Sound at level 10, voice focus on/off, and restoration of the original mode/level/voice settings. These are device read-back checks, not an acoustic measurement. The protocol test suite passes 297 assertions.

## Scope

Designed for LinkBuds S and Sony's V2 protocol. It does not provide EQ, firmware updates, adaptive location-based sound, or support for other headset models. Login startup and sleep/wake behavior need longer-term testing.

## Protocol references and licensing

Independent Swift implementation informed by [SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge) (reference commit `8c81a2775a76097f4938fbc835411bd59088014c`) and the packet definitions in [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient). SonyBridge's MIT notice is retained in `THIRD_PARTY_LICENSES`. This app is unofficial and is not affiliated with Sony.
