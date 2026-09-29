# How 15CE Flasher programs the Collector’s Edition

This note explains what happens when you flash firmware with **15CE Flasher**, without assuming you already know SAM-BA jargon.

It is about the **HP 15c Collector’s Edition (CE)** only — the calculator that talks USB over the official pogo programming cable. It does **not** apply to the older Limited Edition or other Voyagers that use a different cable protocol.

---

## Big picture

Think of three actors:

| Who | Where it runs | Job |
|-----|---------------|-----|
| **15CE Flasher** (this Mac app) | Your Mac | Opens the USB link, splits the firmware file into pages, sends commands, checks results |
| **SAM-BA monitor** (“bootloader”) | Inside the calculator’s **flash**, at the bottom | Tiny resident program that wakes in “programming mode” and accepts short commands over USB |
| **Flash applet** | Loaded temporarily into calculator **RAM**, then discarded | Official Atmel helper that knows how to erase/program this chip’s flash hardware |

The Mac app never “pushes bytes straight into flash” for a full firmware update. It loads the applet into RAM, then uses that applet as an on-device flash engine, page by page.

Windows Atmel **SAM-BA** does the same kind of thing with the same family of helper binary. This app is a native Mac host for that path.

---

## Two kinds of memory (this trips everyone up)

The chip has **flash** and **SRAM**. They are different address spaces — like two separate filing cabinets with different number ranges.

### Flash (permanent until rewritten)

Holds programs that survive power-off: the bootloader and the Voyager firmware image.

### SRAM (volatile RAM)

Holds temporary working data. When you leave programming mode or remove power, SRAM content is gone.

**Important:** Address `0x20002000` is **not** “high up in flash.” The `0x2000…` prefix means **SRAM**. Flash lives down near `0x0000…`.

---

## Graphical memory map — flash (HP 15c CE)

The CE uses an **ATSAM4LC2C** with **128 KB** of flash (`0x00000`–`0x1FFFF`).

15CE Flasher only ever writes the **application** region. It refuses to write below `0x4000`, so the bootloader stays intact.

```text
Flash address        What lives here                         Size
───────────────────  ──────────────────────────────────────  ────────
0x00000              ┌────────────────────────────────────┐
                     │  SAM-BA monitor (bootloader)       │  16 KB
                     │  Present from the factory / HP.    │  (0x4000)
                     │  Speaks USB in programming mode.   │
0x03FFF              └────────────────────────────────────┘
0x04000              ┌────────────────────────────────────┐
                     │  Application firmware              │  112 KB
                     │  The 114,688-byte (.bin) image     │  (0x1C000)
                     │  you choose in the app.            │
                     │                                    │
                     │  ← 15CE Flasher writes ONLY here │
                     │                                    │
0x1FFFF              └────────────────────────────────────┘
                     (end of 128 KB flash)
```

Same map as a vertical strip:

```text
  0x00000 ════════════════════════════════
          ║  BOOTLOADER (SAM-BA)         ║  never overwritten by this app
          ║  0x0000 – 0x3FFF             ║
  0x04000 ════════════════════════════════
          ║                              ║
          ║  APPLICATION (Voyager FW)    ║  full file written here,
          ║  0x4000 – 0x1FFFF            ║  512-byte pages at a time
          ║                              ║
  0x20000 ════════════════════════════════  (first byte past flash)
```

| Region | Start | End (inclusive) | Bytes | Notes |
|--------|-------|-----------------|-------|-------|
| Bootloader | `0x0000` | `0x3FFF` | 16,384 | SAM-BA; do not erase/overwrite |
| Application | `0x4000` | `0x1FFFF` | 114,688 | Expected `.bin` size |

---

## Graphical memory map — SRAM (during a flash session)

While programming, SRAM is a scratch pad for the USB protocol. Approximate layout used by this stack:

```text
SRAM address         What lives here
───────────────────  ──────────────────────────────────────────────
0x20000000           ┌────────────────────────────────────────────┐
                     │  SAM-BA monitor workspace                  │
                     │  (romcodesram — monitor’s own RAM use)     │
0x200007FF           └────────────────────────────────────────────┘
        …            (gap — do not park a home-grown blob at
                     0x20001000; this monitor’s Go command expects
                     a proper vector table at the load address)

0x20002000           ┌────────────────────────────────────────────┐
                     │  Flash applet binary                       │
                     │  applet-flash-sam4l4.bin (~2.6 KB)         │
                     │  Loaded from the Mac, then run.            │
0x20002040           │  Mailbox (commands / status / arguments)   │
                     │  First field: “command” word               │
                     ├────────────────────────────────────────────┤
                     │  Applet code / data continues…             │
                     │  Page buffer (512 bytes) — address told    │
                     │  to the host after INIT                    │
                     └────────────────────────────────────────────┘
```

None of this is your Voyager “user memory” in the calculator sense. It is the programming toolchain’s temporary workspace. After reset / leaving programming mode, it is gone.

---

## Programming mode (how the monitor wakes up)

1. Seat the keyed pogo plug in the CE battery bay; USB to the Mac.
2. On the cable: hold **ERASE**, press **RESET**, release **ERASE**.
3. Display stays off. The chip is running the **bootloader**, not the normal calculator UI.
4. The Mac sees a USB CDC device (SAM-BA). The app talks to it with short monitor commands (below).

When you finish: **RESET** on the cable, then turn the calculator **ON**. “Pr Error” is normal — user memory was cleared by the flash.

---

## Monitor commands (the `S#` / `G#` alphabet)

The bootloader understands a tiny text protocol over USB. Commands end with `#`.

| Command | Plain English |
|---------|----------------|
| **`N#`** | “Use binary / non-interactive mode” (less chatty; what the app uses). |
| **`V#`** | “What version are you?” Confirms you are talking to SAM-BA. |
| **`R…#`** | **Read** memory at an address (used for identify and for verify readback). |
| **`w` / `W…#`** | **Write** a small value to an address (used for mailbox fields in SRAM). |
| **`S…#`** | **Send** a block of bytes to an address (upload the applet, or fill the page buffer). |
| **`G…#`** | **Go** — run code at an address (start the applet). |

These commands alone are a poor way to program the whole FLASHCALW controller for a 112 KB image. That is why the **applet** exists.

---

## What the flash applet is

- File name: `applet-flash-sam4l4.bin` (from Atmel SAM-BA 2.16).
- Size: 2,652 bytes.
- License: SAM Software Package License — redistributed and attributed in this project (`THIRD_PARTY.md`). It is **not** HP firmware.
- Lifetime: copied into **SRAM**, used for the session, **not** stored as part of the Voyager application image.

It is a tiny on-device program that speaks FLASHCALW (this chip’s flash controller): unlock, program a page, report status. The Mac is the remote control; the applet is the mechanic with the right tools.

---

## Step-by-step: one full flash

### 1. Connect and identify

App opens the USB port, puts the monitor in binary mode, reads version / chip identity. Optional: **backup** reads today’s application flash (`0x4000`… ) into a file on the Mac.

### 2. Load the applet into SRAM

App sends `S#` aimed at `0x20002000` plus the applet bytes. The binary now sits in RAM.

### 3. Initialize the applet

App writes an **INIT** request into the **mailbox** (a small structure in SRAM at `0x20002040`), then **`G#`** to `0x20002000` to run the applet once.

The applet replies by filling mailbox fields (flash size, page size, where the 512-byte buffer lives, …) and marks the command finished (see “done” signal below).

### 4. Page the new firmware (the Mac is the pager)

The firmware `.bin` is 114,688 bytes. Flash pages on this path are **512 bytes**.

For each page, roughly:

1. App copies that page into the applet’s **SRAM buffer** (`S#`).
2. App writes a **WRITE** command into the mailbox: “program this buffer to flash offset …” (always ≥ `0x4000`).
3. App sends **`G#`** again — applet programs that page.
4. App waits until the applet signals **done**.
5. Next page.

So **paging is driven by the Flasher app**. The applet only ever handles “this one page” when asked.

### 5. How the app knows a page finished (`~cmd`)

There is usually **no** friendly “OK” string back from `G#` in this mode.

Instead, the mailbox’s first word is a **command code** (for example “WRITE” = `0x2`):

1. Host writes `cmd` into the mailbox.
2. Host runs the applet (`G#`).
3. When the applet finishes, it writes **`~cmd`** — the **bitwise NOT** of that same number — into the command word (and a status code beside it).

Example: if `cmd` was `0x00000002`, done looks like `0xFFFFFFFD`.

The app **polls that mailbox word** until it sees `~cmd`. That means “this applet operation finished,” **not** “I compared flash to the file yet.”

### 6. Verify (separate step)

After all pages are programmed, the app can **read the application flash back** and compare it to the file you selected. That is a real content check of flash, independent of the mailbox handshake.

### 7. Restart and checksum on the calculator

You reset out of programming mode and use the calculator’s own test/checksum UI to confirm what the silicon thinks it has — a second, human-visible check.

---

## Why not write flash directly from the Mac?

People have tried “just `W#` / poke the flash controller from the host.” On this CE hardware that path tends to **kill the USB session** or leave the monitor hung. The flash controller needs the careful sequence the official applet implements.

So the design is deliberate:

- **Host** = policy (never below `0x4000`), paging, USB timing, verify.
- **Applet** = proven FLASHCALW programmer in SRAM.
- **Bootloader** = USB front door that must remain in flash.

---

## Quick glossary

| Term | Meaning |
|------|---------|
| **CE** | HP 15c Collector’s Edition |
| **SAM-BA** | Atmel/Microchip “SAM Boot Assistance” — monitor + host tools for programming SAM micros |
| **Monitor / bootloader** | Resident program in flash `0x0000–0x3FFF` |
| **Applet** | Temporary RAM helper that programs flash |
| **Mailbox** | Shared SRAM struct where host and applet exchange command / status / args |
| **Page** | 512-byte chunk of flash programming |
| **`~cmd`** | Bitwise NOT of the mailbox command word = “operation complete” |
| **Application image** | The 114,688-byte `.bin` starting at flash `0x4000` |

---

## Related files in this repo

- `THIRD_PARTY.md` — applet copyright and license text  
- `Sources/HP15CFlasherCore/FlashLayout.swift` — `0x4000` / `0x1C000` constants  
- `Sources/HP15CFlasherCore/SambaFlashApplet.swift` — load, mailbox, INIT / WRITE  
- `Sources/HP15CFlasherCore/SambaFlashAppletImage.swift` — embedded official `.bin`  

Mach II Labs is not affiliated with HP, Atmel, or Microchip. This app does not include HP firmware.

## Disclaimer

15CE Flasher and related documentation are provided as is, without warranty of any kind. Although we have employed several safeguards to help keep this software safe, flashing firmware can wipe user memory, leave the calculator unusable, or permanently brick the device. You are solely responsible for backups, choosing a correct firmware file, and following the app’s instructions. If the instructions are not clear in DEMO mode, do not execute in FLASH mode. Mach II Labs is not liable for damage, data loss, or repair costs arising from use of this software.
