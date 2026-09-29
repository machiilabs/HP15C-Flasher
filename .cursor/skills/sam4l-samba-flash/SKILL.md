---
name: sam4l-samba-flash
description: >-
  Research and implement ATSAM4LC2C / HP 15c CE flashing over SAM-BA USB CDC.
  Use when changing SambaClient, FlashCalw, SambaFlashApplet, Flasher, POSIX
  serial, flash wizard, or diagnosing SAM-BA timeouts, USB dropouts, or verify
  failures.
---

# SAM4L / SAM-BA flash

You are the protocol owner for this app. Writes use the official SAM-BA 2.16
SRAM applet (`SambaFlashApplet`). That path is proven on hardware.

## Hard rules

- Do not write below `0x4000`. Do not issue Erase All / `EA`.
- Writes must use `SambaFlashApplet` (official `.bin`), not host FCMD.
- Do not commit or push Atmel SAM-BA `*.c` / `*.h`. The shipping artifact is
  the official `.bin`, embedded in `SambaFlashAppletImage.swift`. A local
  extract of the Windows installer (if present) is gitignored.
- Tests must keep `commandSettleSeconds: 0` (no hardware sleeps).

## What already works

- Port: `/dev/cu.usbmodem*` only. VID `03EB` PID `6124`. FTDI `cu.usbserial` is not SAM-BA.
- Monitor: `v1.1 Oct 16 2012 17:15:20`. Commands `N#` `V#` `w` `W` `R` `S` `G`.
- Identify and 114688-byte application backup over USB CDC.
- Full application write on real hardware: official applet + `tcdrain` + 20 ms
  after every `S#` + `GENERIC::Run` poll (100 ms before first `w#`, 1 s between
  retries). Do not remove those gaps.

## Do not revive

Host `W#` to FLASHCALW, fire-and-forget FCMD, and home-grown `G#` blobs all
failed on hardware (USB dies or the monitor never returns). Do not go back.

## Required method

Protocol: [protocol.md](protocol.md). Official 2.16 applet:
`applet-flash-sam4l4.bin` (2652 bytes, load/`G#` `0x20002000`, mailbox
`0x20002040`). `G#` is a vector-table **call**; host waits by polling mailbox
command until `~cmd`.

1. Drive **that binary** from `SambaFlashApplet` over `SambaClient`.
2. After every `S#`, drain and wait (`afterSendDelay` 20 ms on hardware). Mac
   `write()` returns when the host accepts bytes, not when the monitor finishes.
3. After `G#`, wait before the first `w#`. Do not spam `w#` on NACK.
4. Tests keep `commandSettleSeconds: 0` / `afterSendDelay: 0`.

## Code map

- `Sources/HP15CFlasherCore/SambaClient.swift` — monitor
- `Sources/HP15CFlasherCore/SambaFlashApplet.swift` — load, mailbox, INIT/WRITE/UNLOCK
- `Sources/HP15CFlasherCore/SambaFlashAppletImage.swift` — embedded official `.bin`
- `Sources/HP15CFlasherCore/FlashCalw.swift` — identify/read via `R#`; write via applet
- `Sources/HP15CFlasherCore/FlashLayout.swift` — `0x4000` / `0x1C000`
- `Sources/HP15CFlasherCore/Flasher.swift` — connect modem-only

## Additional resources

- Official 2.16 protocol: [protocol.md](protocol.md)
- Known hardware facts: [reference.md](reference.md)
- Applet license: [THIRD_PARTY.md](../../../THIRD_PARTY.md)
- Cable: hold ERASE, press RESET, release ERASE
