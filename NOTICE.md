# Third-Party Notices & Attribution

`turbowarp-android` is distributed under **GPL-3.0** (see [`LICENSE`](LICENSE)).

## Original work in this repository

The following are © 2026 CrispStrobe, licensed GPL-3.0:

- the Capacitor-based Android (and iOS) wrapper and configuration,
- the JavaScript → native Scratch-Link bridge,
- the native Bluetooth (RFCOMM/SPP + BLE) plugin code,
- the LEGO extension integration, and
- the build scripts.

## Components it builds on (not vendored in this repository)

| Component | Author(s) | License | How it is used |
|---|---|---|---|
| scratch-gui (TurboWarp fork) | Scratch Foundation + TurboWarp | BSD-3-Clause (base) + GPL-3.0 (TurboWarp modifications) | Cloned separately as `../scratch-gui` and compiled into the app's web assets |
| Capacitor | Ionic | MIT | Native runtime / build framework (npm dependency) |

This repository contains the native shell and bridges; the editor itself is the
external TurboWarp/scratch-gui fork. Because the editor bundled into the shipped
app includes GPL-3.0 code, the **distributed app is GPL-3.0**. Capacitor (MIT) is
GPL-compatible.

LEGO® is a trademark of the LEGO Group, which does not sponsor or endorse this software.
