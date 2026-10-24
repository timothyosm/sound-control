# Extra headphone controls

Sound Control 0.5 adds **More settings**. Controls appear after the app receives recognised device data. Each write is followed by a separate read. A successful acknowledgement alone does not confirm a change.

## Sony controls

This implementation covers the Sony MDR V2 formats used by LinkBuds S. It reads the supported functions before sending feature queries. It requests the second command table only when the initial handshake reports support.

| Control | Read | Write | Validation |
| --- | --- | --- | --- |
| Equaliser presets and bands | `56 00` | `58 00` | Presets, band count and step count from `51 00` |
| DSEE | `e6 01` | `e8 01` | Supported function and DSEE type from `e1 01` |
| Connection preference | `e6 00` | `e8 00` | Supported function and recognised setting |
| Automatic pause | `f6 01` | `f8 01` | Supported function and recognised on or off value |
| Speak-to-Chat | `f6 0c` or `f6 02` | `f8` with the same subtype | Supported function and both setting fields |
| Automatic power off | `26 05` or `26 04` | `28` with the same subtype | Choices from the power capability reply |
| Touch assignments | `f6 03` or `f6 0e` | `f8` with the same subtype | Per-control presets from the capability reply |
| Multipoint | `d6` with the advertised general setting slot | `d8` with the same slot | Boolean capability identified as multipoint |
| Voice guidance | `46` in the second command table | `48` with the same subtype | Advertised switch support; language preserved |

The app preserves the other earbud’s touch assignment when changing one side. It preserves the voice guidance language and the previous power-off timer. Choosing Clear Bass or a frequency band switches to manual equaliser mode and preserves the other bands.

Some choices, such as connection preferences and multipoint, can interrupt Bluetooth. The app reconnects and reads the device state again. It does not claim success without a matching read-back.

Unknown message layouts and touch limitations remain unavailable. The six-value equaliser editor supports the reported 21-step layout, including Clear Bass. Other band layouts do not gain speculative sliders.

## Nothing and CMF controls

These controls have simulated tests but have not been tested on physical devices. Different models and firmware may expose different subsets.

| Control | Read | Write | Payload |
| --- | --- | --- | --- |
| Noise cancelling strength | `c01e` | `f00f` | `01`, strength, `00` |
| Automatic pause | `c00e` | `f004` | `01 01`, on or off |
| Low-lag mode | `c041` | `f040` | `01` for on or `02` for off, then `00` |
| Dual connection | `c027` | `f01a` | `00` or `01` |
| Basic equaliser preset | `c01f` | `f010` | Preset, `00` |
| CMF listening preset | `c050` | `f01d` | Preset, `00` |
| Bass enhancement | `c04e` | `f051` | On or off, existing strength |
| Personalised noise cancelling | `c020` | `f011` | `00` or `01` |
| Advanced equaliser switch | `c04c` | `f04f` | On or off, `00` |

Optional probes are read-only. A missing or malformed response cannot enable a write. Read replies must match the command and operation identifier. Changes wait briefly before the verification read. Timeouts clear the affected control. Failed probes are not repeated on every automatic refresh; reconnecting probes them again.

Choosing a noise cancelling strength turns on noise cancelling. Basic presets are hidden while advanced equaliser mode is reported as active. The switch enables or disables the device’s existing advanced profile; it does not edit its bands. The app preserves the reported bass enhancement strength because the level scale differs between models.

CMF preset identifiers differ from Nothing’s basic equaliser identifiers. The app keeps these command families separate. Device-specific tuning is offered only after it has been reported as the current preset. A valid settings reply does not prove that every candidate option works on every model; rejected writes are reported after read-back.

Gesture editing, custom Nothing equaliser curves, spatial audio, ear tip tests, firmware updates and lost-earbud sounds are not included in this update.

## Verification

The recorded LinkBuds S capability and settings replies are in `Tests/Fixtures/linkbuds-s-4.3.1-extras.json`. They contain protocol data without Bluetooth addresses.

Tests cover recognised and truncated replies, unsupported choices, preserving unrelated fields, distinguishing command tables, failed verification, stale operation identifiers and timeouts. Device tests distinguish changed settings from checks that write the existing value.

On 24 October 2026, the LinkBuds S test completed with no failures. It changed and restored DSEE Extreme, automatic pause, Speak-to-Chat and voice guidance. It wrote and read back the existing equaliser preset, connection preference, automatic power-off setting, both touch assignments and multipoint setting. These checks do not establish that every available option works. Custom equaliser bands were not changed during the device test.

The optional extra control test stores its pending restoration record in SQLite. It stops if restoration cannot be confirmed. Rerun it with the same device to restore the saved setting before testing again.

## Protocol sources

Sony formats are based on [SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) at commit `8f4808cb635f5a176df0b7b5aea959818be5129e`, with live LinkBuds S replies used for regression tests. Its MIT notice is retained in `THIRD_PARTY_LICENSES`.

Nothing command values and field layouts are independently implemented from the protocol behaviour documented by [Ear (web)](https://github.com/radiance-project/ear-web) at commit `d076e1371572fbf0a14b441f9b3cafbf9a237e04` and [earctl](https://github.com/DaanHessen/earctl). No code from these projects is bundled.
