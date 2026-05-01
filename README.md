# DC03 Pro Control for macOS

Unofficial macOS menu bar controller for the **iBasso DC03 Pro** USB DAC.

The official iBasso control app is available for Android, but macOS users do not
get a native way to change the DC03 Pro's hardware settings. This project fills
that gap with a small AppKit status bar app that talks to the DAC over its HID
control interface.

This is not affiliated with, endorsed by, or supported by iBasso.

## Features

- Runs as a lightweight macOS menu bar app.
- No Dock icon; click `DC03` in the status bar to open controls.
- Detects the iBasso DC03 Pro over USB-C.
- Controls mapped from the device protocol:
  - Digital filter
  - Gain
  - Output mode
  - Hardware volume
  - Left/right balance
  - Presets
  - Optional raw 16-byte HID report sender for developers
- Builds locally with Apple's command line tools.
- No Apple Developer Program subscription required for local use.
- Can package a local `.dmg`.

## Supported Device

| Device | USB Vendor ID | USB Product ID |
| --- | --- | --- |
| iBasso DC03 Pro | `0x262a` | `0x187e` |

macOS exposes the control endpoint as a HID interface:

- Interface: `0`
- Usage page: `0x0c`
- Usage: `0x01`
- HID output report size: 16 bytes
- HID input report size: 32 bytes

The regular audio playback path is still handled by macOS through the standard
USB audio driver. This app only sends control messages.

## Requirements

- macOS 13 Ventura or newer
- Xcode Command Line Tools
- iBasso DC03 Pro connected by USB-C

Install the command line tools if needed:

```sh
xcode-select --install
```

## Build And Run

Clone the project:

```sh
git clone https://github.com/Chandru03/ibasso-dc03-pro-macos.git
cd ibasso-dc03-pro-macos
```

Build the app:

```sh
chmod +x macos/build_app.sh macos/package_dmg.sh
./macos/build_app.sh
```

Run it:

```sh
open "build/DC03 Pro Control.app"
```

The app appears as `DC03` in the macOS status bar. When the DAC is detected, the
title changes to `DC03 *`.

## Package A DMG

```sh
./macos/package_dmg.sh
open "build/DC03 Pro Control.dmg"
```

The generated DMG contains the app and an `/Applications` shortcut.

## Gatekeeper Notes

The app is ad-hoc signed locally by the build script. That is enough for your own
Mac, but it is not notarized by Apple.

If macOS blocks the first launch:

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. Find the blocked app message.
4. Choose **Open Anyway**.

You can also right-click the app and choose **Open**.

## Usage

1. Connect the iBasso DC03 Pro.
2. Launch `DC03 Pro Control.app`.
3. Click `DC03` in the status bar.
4. Use **Refresh Device** if you connected the DAC after launching the app.
5. Choose a preset, or apply individual settings.

Recommended first run:

- Start with a low system volume.
- Apply `IEM Quiet` or a low hardware volume first.
- Then adjust gain and volume gradually.

## What The Controls Mean

### Digital Filter

The digital filter changes how the DAC reconstructs digital samples before
analog output. The difference is usually subtle. It can slightly affect treble
edge, transient feel, and pre/post-ringing behavior. It does not create true
hardware EQ or dramatically change soundstage.

Current labels:

- `0`: Fast roll-off
- `1`: Slow roll-off
- `2`: Short delay fast
- `3`: Short delay slow
- `4`: NOS

### Gain

Gain changes the output level range:

- Low: safer for sensitive IEMs
- Medium: useful general setting
- High: for harder-to-drive headphones

Use the lowest gain that reaches your preferred loudness cleanly.

### Output Mode

The app exposes the DC03 Pro output mode values found in the control protocol:

- Normal
- Power saving

### Volume And Balance

Volume is sent to the DAC hardware, not just macOS system volume. Balance
attenuates one channel relative to the other.

## Protocol Notes

The DC03 Pro accepts 16-byte HID output reports using report ID `0`.

macOS sends these with:

```text
IOHIDDeviceSetReport(..., kIOHIDReportTypeOutput, 0, report, 16)
```

The mapped controls currently send the following report families.

Digital filter:

```text
11 11 88 60 00 00 05 09 00 00 00 vv 00 00 00 00
12 11 88 62 00 00 05 09 00 00 00 vv 00 00 00 00
```

Gain:

```text
15 11 88 60 00 00 05 08 00 00 00 vv 00 00 00 00
16 11 88 62 00 00 05 08 00 00 00 vv 00 00 00 00
```

Gain value mapping:

| App value | Register value |
| --- | --- |
| `0` | `0x00` |
| `1` | `0x20` |
| `2` | `0x31` |

Output mode:

```text
17 11 88 60 00 00 05 0b 00 00 00 vv 00 00 00 00
18 11 88 62 00 00 05 0b 00 00 00 vv 00 00 00 00
```

Output value mapping:

| App value | Register value |
| --- | --- |
| `0` | `0x1c` |
| `1` | `0x1e` |

Volume and balance use the same stepped attenuation table as the official
control flow and write both PCM and DSD-related channel registers.

## Limitations

- The DC03 Pro control protocol found so far does not expose hardware PEQ.
- There is no known hardware "soundstage" switch.
- Soundstage changes are better handled by headphones/IEMs, ear tips, recordings,
  crossfeed, EQ, or spatial audio software before the DAC.
- The app currently writes settings but does not read every current setting back
  from the DAC.
- The app is not notarized. Public binary releases would require Apple
  notarization for the smoothest user experience.

## Project Structure

```text
.
|-- README.md
|-- LICENSE
|-- CONTRIBUTING.md
|-- SECURITY.md
`-- macos
    |-- DC03ProStatusBar.swift
    |-- build_app.sh
    `-- package_dmg.sh
```

Generated files go into `build/` and are intentionally ignored by git.

## Development

Build:

```sh
./macos/build_app.sh
```

Package:

```sh
./macos/package_dmg.sh
```

Remove generated output:

```sh
rm -rf build
```

The app is intentionally dependency-free: plain Swift, AppKit, IOKit HID, and
shell scripts.

## Safety

This project sends low-level HID reports to an audio device. Known controls are
mapped in the UI, but the raw report sender can send arbitrary 16-byte reports.

Use raw reports only if you understand what they do. Keep playback volume low
when testing.

## License

MIT. See [LICENSE](LICENSE).
