# Contributing

Thanks for helping improve DC03 Pro Control for macOS.

## Good Contributions

- Confirmed protocol mappings for the iBasso DC03 Pro.
- Safer UI for existing controls.
- Better device detection and state refresh.
- Documentation improvements.
- Build and packaging improvements that do not require paid Apple Developer
  Program membership for local users.

## Ground Rules

- Do not commit proprietary iBasso APKs, decompiled source trees, or downloaded
  app binaries.
- Keep generated build output out of git.
- Keep the app dependency-free unless a dependency clearly earns its place.
- Treat raw HID commands carefully. Include the report bytes and the observed
  device behavior when proposing a protocol change.

## Local Build Check

Before opening a pull request, run:

```sh
./macos/build_app.sh
./macos/package_dmg.sh
```

If you change device-control behavior, test with the DAC connected and with
playback volume low.
