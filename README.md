# 15CE Flasher

Native macOS app that flashes firmware on post-2015 Voyager calculators (**HP 15c Collector’s Edition**, **HP 16c Collector’s Edition**, and **HP 12c**) over the official USB pogo programming cable. Windows SAM-BA is not required.

Choose **DEMO** to walk through the wizard safely, **FLASH** for one calculator, or **BATCH** to flash many units in sequence with the same firmware.

A Mach II Labs product. Free forever. It does not include HP firmware. Mach II Labs is not affiliated with HP, Atmel, or Microchip.

## Requirements

- macOS 13 or later
- HP 15c Collector’s Edition, HP 16c Collector’s Edition, or a post-2015 HP 12c
- Official USB-C (or USB-A + adapter) pogo programming cable
- A 114,688-byte (112 KB) `.bin` you already have

**Do not use this cable or this app** on an HP 15c Limited Edition, a pre-2015 HP 12c, an HP 20b, or an HP 30b. Those pogo ports are a different protocol and voltage; the cable can destroy them.

## Disclaimer

15CE Flasher and related documentation are provided as is, without warranty of any kind. Although we have employed several safeguards to help keep this software safe, flashing firmware can wipe user memory, leave the calculator unusable, or permanently brick the device. You are solely responsible for backups, choosing a correct firmware file, and following the app’s instructions. If the instructions are not clear in DEMO mode, do not execute in FLASH mode. Mach II Labs is not liable for damage, data loss, or repair costs arising from use of this software.

## Install

Download `15CEFlasher-x.y.z-N.dmg` from [machiilabs.com](https://machiilabs.com). Verify the SHA-256 posted with the file, then drag **15CE Flasher** to Applications.

The bootloader at `0x0000–0x3FFF` is never overwritten. Writes start at `0x04000`.

## Flash

1. Open the battery door and seat the keyed pogo connector.
2. Plug the cable into this Mac.
3. Hold **ERASE**, press **RESET**, release **ERASE**. The display stays off.
4. In the app: Save Backup, Choose Firmware, Flash.
5. Press **RESET** on the cable, then **ON**. “Pr Error” is expected; user memory was cleared.
6. Turn the calculator off, hold **g** and **ENTER**, press **ON**, then press **2**. The display should show `ChE - -` plus the checksum of the file you flashed (for example `0A0Ah`).
7. Press **ON** a few times to leave the test menu.

## Privacy

The app is offline. No telemetry, no network, no automatic diagnostics. Firmware files never leave this Mac.

## How flashing works

Beginner-friendly walkthrough of the bootloader, SRAM applet, paging, and memory map: [docs/how-flashing-works.md](docs/how-flashing-works.md).

## Acknowledgments

The SRAM flash helper is `applet-flash-sam4l4.bin` from Atmel SAM-BA 2.16, © 2011–2012 Atmel Corporation, redistributed under the SAM Software Package License. See [THIRD_PARTY.md](THIRD_PARTY.md). Atmel’s name is not used to endorse this product.

## License

Mach II Labs source is [MIT](LICENSE). Forks and other apps based on this code are welcome. Keep the copyright notice and the credit that Mach II Labs is the original developer of the free 15CE Flasher. The Atmel applet stays under its own license.

## Build from source

```bash
scripts/build_and_install.sh          # Release → /Applications
scripts/package_dmg.sh                # signed, notarized DMG in dist/
```

Xcode 15+, macOS 13 SDK. Daily installs bump the integer build number. `scripts/package_dmg.sh` is the public-release path.
