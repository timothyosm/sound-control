# Nothing and CMF support (experimental)

This is an independently authored Swift implementation of the documented Bluetooth
wire format. No Nothing X, Ear (web) or earctl source code or dependencies are
bundled. Nothing and CMF support has **not been tested on physical hardware**.

## Scope and discovery

The app discovers paired devices that advertise the Nothing control service
`aeac4a03-dff5-498f-843a-34487cf133eb`. It finds the radio frequency communication (RFCOMM) channel through the Service Discovery Protocol (SDP). It uses the channel only after the device connects through macOS. It does not guess channel
numbers or send commands to generic serial or Google Fast Pair services.

Protocol-family candidates include Nothing Ear (1), Ear (2), Ear (2024), Ear (a),
Ear (3), Headphone (1) and variants of CMF Buds and Buds Pro. This list is not a set of
hardware compatibility claims. Models lacking this service are not discovered.

The app can:

- read left, right and case batteries or a single headphone battery
- set noise cancelling, transparency or off after a valid sound reply
- retain the last reported noise cancelling strength, or use high if none has been read
- read the setting back to confirm each change.

Active noise cancelling (ANC) strength, equaliser presets and other supported settings appear under **More settings**. Sony ambient level and voice focus controls are hidden for Nothing devices. See the [extra control notes](extra-controls.md) for the command formats and limits.

Devices named Ear (open) or Ear (stick) skip noise control queries. Other settings still require a valid response. The app does not implement the noise reduction feature available in some Ear (stick) firmware. Renamed devices are identified by their service. ANC stays disabled until the app receives a valid reply.

## Message format

The frame consists of an 8-byte header, a payload and a 2-byte checksum.
Header fields: `55`, flags (`60` for requests and replies, `00` for notifications),
version `01`, 16-bit little-endian command, 16-bit little-endian payload length,
and an operation ID. The cyclic redundancy check CRC-16/MODBUS (polynomial `A001`, initial value `FFFF`) covers
the header and payload, and is appended in little-endian order. Input is bounded to a
4096-byte payload. Invalid CRCs, lengths, versions and malformed payloads are
rejected. Only CRC-validated notification frames are consumed; polling supplies
authoritative state if a firmware variant sends other notification formats.

| Purpose | Request | Reply or event | Payload |
| --- | --- | --- | --- |
| Battery read | `C007` | `4007` / `E001` | count followed by component and value pairs |
| ANC read | `C01E` | `401E` / `E003`, `6003` | ANC record starts `01`, mode, `00` |
| ANC write | `F00F` | verified using `C01E` | `01`, mode, `00` |

ANC values: high = 1, medium = 2, low = 3, adaptive = 4, off = 5, transparency = 7.
Battery component IDs: left = 2, right = 3, case = 4, single = 6. Bit 7 indicates charging;
the remaining 7 bits contain the battery percentage. Values over 100 are displayed as unknown.

Requests are serialised. Read replies must match both command and operation ID;
unsolicited events cannot confirm a write. After a write the app waits 200 ms
before reading the state. Reads time out after 4 seconds. Missing optional
features leave available battery data usable. A verification timeout clears the
sound controls until a successful refresh. It does not automatically retry writes.

## Evidence and references

The implementation draws on these sources:

- [Bharadwaj Raju's Ear (2) protocol analysis](https://bharadwaj-raju.github.io/posts/nothing-ear-2-on-linux/)
  provides captured command and response packets. Tests compare against the
  transparency command, firmware query and ANC read response. The article’s high noise cancelling example has an inconsistent checksum; that test recomputes the CRC rather
  than treating the printed checksum as valid.
- [Ear (web)](https://github.com/radiance-project/ear-web) documents interoperable
  Nothing and CMF controls and the shared service UUID.
- [earctl](https://github.com/DaanHessen/earctl) provides corroborating protocol
  facts, ANC mode values, battery component IDs and model-family information.

Tests cover stream fragmentation, coalesced packets, CRC corruption and recovery,
length limits, battery variants, malformed responses, operation-ID rollover,
stale replies, notification/read-back separation, failed verification, missing
features and battery-only devices. They prove simulated protocol behaviour, not
Bluetooth or acoustic behaviour on actual Nothing hardware.
