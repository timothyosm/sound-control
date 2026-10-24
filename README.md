# Sound Control

A tiny native macOS menu bar app for compatible Sony, Nothing, and CMF headphones and earbuds. Originally built for LinkBuds S, now with capability-based Sony MDR V1/V2 support and experimental Nothing/CMF support.

- Noise Cancelling, Ambient Sound, and Off where supported
- Device-reported ambient levels and voice focus where supported
- Single, left/right, and charging-case battery readings
- Headphone picker, remembered selection, and automatic reconnect
- Optional Open at Login; no accounts, telemetry, or runtime dependencies

## Compatibility

| Device/protocol family | Status |
| --- | --- |
| LinkBuds S, firmware 4.3.1 | Hardware tested, including capability discovery, sound writes/read-back, batteries, and restoring original settings |
| Nothing / CMF headphones and earbuds | Experimental ANC/Transparency/Off and battery support; simulated tests only, no hardware verification |
| Legacy MDR V1 headphones (e.g. WH-1000XM3/XM4) | Implemented and tested with synthetic protocol fixtures; not hardware verified |
| MDR V2 headphones/earbuds with supported layouts (e.g. WH-1000XM5/XM6, WF-1000XM5, WH-CH720N, WF-C700N) | Capability-driven implementation; other models need hardware verification |
| Headsets with battery support but no supported sound-control layout | Battery information only; sound controls disabled |
| Sony TVs, cameras, consoles, speakers, USB-only or LE-only devices | Not supported by this headphone RFCOMM implementation |

Model examples are compatibility candidates, not guarantees. Discovery uses Sony's advertised service UUID, not a model-name allowlist, so renamed headsets can work too. The app queries supported functions and sound capabilities before enabling writes. Unrecognized protocols, capabilities, or sound settings never enable speculative controls.

Implemented sound layouts: V1 NC-only on/off (`01`), combined NC/ambient (`02`), ambient-only (`03`); V2 NC-only (`01`), combined seamless (`13`, `14`, `16`, `17`, `18`, `19`), ambient-only on/off (`21`) and seamless (`22`). V2 `19` preserves the device's existing noise-adaptation fields. Other layouts remain unsupported; wind-reduction and automatic/adaptive modes are not separate controls in the menu.

## Nothing / CMF

Devices advertising Nothing's control service appear in **Headphones** alongside
Sony devices. Nothing exposes **Noise Cancelling**, **Transparency**, and **Off**
after a valid sound-status reply, plus available battery readings. The last
reported noise-cancelling strength is preserved. Ear (open) and Ear (stick) are
battery-only; Sony ambient-level and voice-focus controls are hidden.

Nothing support is explicitly marked **hardware unverified** in the menu. It is
not a promise that every Nothing/CMF model works. See the
[protocol notes and compatibility limits](docs/nothing-protocol.md).

## Build and run

Requires macOS 13 or newer and Apple's Command Line Tools (`xcode-select --install`).

```sh
./scripts/test.sh
./scripts/build.sh
open "build/Sound Control.app"
```

Copy `build/Sound Control.app` to Applications for a permanent installation. Pair and connect your **Sony, Nothing, or CMF headphones** in macOS Bluetooth Settings first. Allow Bluetooth access if macOS asks. The app runs only in the menu bar; it has no Dock icon. Open at Login is opt-in from its menu.

The build uses the local Mac's architecture and ad-hoc signing. It is not Developer ID signed or notarized; building locally is recommended for other Macs.

## How Sony support works

The app discovers paired devices advertising Sony's V1 or V2 RFCOMM service. It prefers V2 when both services exist, validates the handshake, reads the supported-function list and sound capability ranges, then requests only advertised battery formats. Choose a headset under **Headphones**, or leave automatic selection enabled. A selected disconnected device waits for you to connect it in Bluetooth Settings.

Commands are serialized and verified with read-back. Replies and acknowledgements can arrive in either order; duplicate inbound frames are acknowledged without applying them twice. An acknowledged optional read that receives no reply is skipped until reconnect, allowing the remaining features to work. Transport failures close only this app's control channel, not the audio connection.

Choosing an ambient level activates Ambient Sound. Voice focus is available only when advertised. Ambient ranges and steps come from the headset. Inactive ambient values may be normalized by the device in NC/Off mode, so verification compares the selected mode and only its active settings. Unknown battery values appear as a dash; case readings can be stale while the case is disconnected.

If control times out, close Sony Sound Connect on your phone and other Sony control apps, then choose Reconnect. Devices must be paired and connected through macOS first; if service discovery is missing, reconnect them in Bluetooth Settings.

## Verification

`./scripts/test.sh` checks packet fragmentation, concatenated frames, all escaped bytes, corrupt checksums/lengths, malformed-stream recovery, bounded buffers, and sound-setting parsing.

An optional **Sony-only** hardware check **changes your sound settings briefly**, tests advertised modes, ambient level and voice focus, then restores the settings read at the start. Quit any running copy before invoking it:

```sh
open "build/Sound Control.app" --args --hardware-test --log /tmp/sound-control-hardware.log
```

The log reports each read-back result and restoration. If Bluetooth disconnects during the check, restoration cannot be guaranteed; restore the desired mode from the menu after reconnecting. Normal launches do not write logs.

Hardware verification on LinkBuds S firmware 4.3.1 passed: Noise Cancelling, Off, Ambient Sound at level 10, voice focus on/off, and restoration of the original mode/level/voice settings. These are device read-back checks, not an acoustic measurement. The test suite passes 297 framing/state assertions and 132 Sony compatibility assertions, plus 367 Nothing protocol/session assertions. Only LinkBuds S has been tested on hardware; the other layouts use synthetic fixtures based on published protocol definitions.

## Scope

No EQ, firmware updates, automatic location-based sound, or non-headphone product control. Login startup and sleep/wake behavior need longer-term testing. Other Sony models and all Nothing/CMF devices require community hardware testing; passing fixture tests does not establish device compatibility.

## Protocol references and licensing

Independent Swift implementation informed by [SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge) (reference commit `8c81a2775a76097f4938fbc835411bd59088014c`) and the packet definitions in [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) (reference commit `8f4808cb635f5a176df0b7b5aea959818be5129e`). Both projects' MIT notices are retained in `THIRD_PARTY_LICENSES`. This app is unofficial and is not affiliated with Sony.
