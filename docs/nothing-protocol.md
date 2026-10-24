# Nothing / CMF support (experimental)

This is an independently authored Swift implementation of the documented Bluetooth
wire format. No Nothing X, Ear (web), or earctl source code or dependencies are
bundled. Nothing/CMF support has **not been tested on physical hardware**.

## Scope and discovery

The app discovers paired devices that advertise the Nothing control service
`aeac4a03-dff5-498f-843a-34487cf133eb`, gets its RFCOMM channel from SDP, and uses
it only after the device is connected through macOS. It does not guess channel
numbers or send commands to generic serial/Google Fast Pair services.

Protocol-family candidates include Nothing Ear (1), Ear (2), Ear (2024), Ear (a),
Ear (3), Headphone (1), and CMF Buds/Buds Pro variants. This list is not a set of
hardware compatibility claims. Models lacking this service are not discovered.

Supported functions:

- Left/right/case battery or the single battery reported by over-ear headphones.
- Noise Cancelling, Transparency, Off after a valid ANC status reply.
- Retain the last reported NC strength; use High if no NC strength has been read.
- Confirm changes with a separate read-back; no optimistic success checkmark.

There is no ANC strength selector, EQ, gesture, firmware, or personalized-ANC UI.
Sony ambient-level and voice-focus controls are hidden for Nothing devices.
Ear (open) and Ear (stick) names select battery-only mode: Ear (stick)'s
firmware-specific noise-reduction feature is not implemented. Renamed devices
are identified by their service, and ANC remains disabled without a valid reply.

## Wire facts

The frame consists of an eight-byte header, a payload, and a two-byte checksum.
Header fields: `55`, flags (`60` for requests/replies, `00` for notifications),
version `01`, 16-bit little-endian command, 16-bit little-endian payload length,
and an operation ID. CRC-16/MODBUS (polynomial `A001`, initial value `FFFF`) covers
the header and payload, and is appended little-endian. Input is bounded to a
4096-byte payload. Invalid CRCs, lengths, versions, and malformed payloads are
rejected. Only CRC-validated notification frames are consumed; polling supplies
authoritative state if a firmware variant sends other notification formats.

| Purpose | Request | Reply/event | Payload |
| --- | --- | --- | --- |
| Battery read | `C007` | `4007` / `E001` | count followed by component/value pairs |
| ANC read | `C01E` | `401E` / `E003`, `6003` | ANC record starts `01`, mode, `00` |
| ANC write | `F00F` | verified using `C01E` | `01`, mode, `00` |

ANC values: High=1, Mid=2, Low=3, Adaptive=4, Off=5, Transparency=7.
Battery component IDs: left=2, right=3, case=4, single=6. Bit 7 indicates charging;
the remaining seven bits contain percent. Values over 100 are displayed as unknown.

Requests are serialized. Read replies must match both command and operation ID;
unsolicited events cannot confirm a write. After a write the app waits 200 ms
before reading the state. Reads time out after four seconds. Missing optional
features leave available battery data usable. A verification timeout clears the
sound controls until a successful refresh. It does not automatically retry writes.

## Evidence and references

- [Bharadwaj Raju's Ear (2) protocol analysis](https://bharadwaj-raju.github.io/posts/nothing-ear-2-on-linux/)
  provides captured command and response packets. Tests compare against the
  transparency command, firmware query, and ANC read response. The article's NC
  High example has an inconsistent checksum; that test recomputes the CRC rather
  than treating the printed checksum as valid.
- [Ear (web)](https://github.com/radiance-project/ear-web) documents interoperable
  Nothing/CMF controls and the shared service UUID.
- [earctl](https://github.com/DaanHessen/earctl) provides corroborating protocol
  facts, ANC mode values, battery component IDs, and model-family information.

Tests cover stream fragmentation, coalesced packets, CRC corruption and recovery,
length limits, battery variants, malformed responses, operation-ID rollover,
stale replies, notification/read-back separation, failed verification, missing
features, and battery-only devices. They prove simulated protocol behavior, not
Bluetooth or acoustic behavior on actual Nothing hardware.
