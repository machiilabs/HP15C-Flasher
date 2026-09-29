# Official SAM-BA 2.16 SAM4L flash protocol

Source of truth: Atmel SAM-BA 2.16 Windows installer (NSIS PE32).  
License: [THIRD_PARTY.md](../../../THIRD_PARTY.md). Do not issue host `W#` to FLASHCALW. Drive this applet.

**Never commit Atmel `*.c` / `*.h`.** A local extract of the installer (if you have one) lives under `extracted/` and is gitignored. The shipping artifact is `applet-flash-sam4l4.bin`, embedded in `SambaFlashAppletImage.swift`.

Local copies (gitignored tree + small bin at skill root):

| File | Role |
|---|---|
| `applet-flash-sam4l4.bin` | Official SRAM applet (2652 bytes). Copy next to this file. |
| `extracted/tcl_lib/at91sam4l-ek/at91sam4l-ek.tcl` | Board script HP 15c CE uses |
| `extracted/tcl_lib/common/generic.tcl` | Host mailbox / `GENERIC::Run` |
| `extracted/applets/sam4l/sam-ba_applets/flash/flash_app_main.c` | Applet commands |
| `extracted/applets/sam4l/sam-ba_applets/common/applet.h` | Command / status codes |
| `extracted/applets/sam4l/sam-ba_applets/common/applet_cstartup.c` | Vector table + return |
| `extracted/applets/sam4l/sam-ba_applets/linker_script/sram_samba.lds` | Load at `0x20002000` |
| `extracted/applets/sam4l/bootloader/sam/applications/sam4l_sam-ba/sam_ba_monitor.c` | `G#` = vector-table **call** |
| `extracted/applets/sam4l/bootloader/sam/applications/sam4l_sam-ba/sam_ba_monitor.h` | Version `"1.1"` |

SHA-256 of `applet-flash-sam4l4.bin`:  
`01672908fce38940ce817e21401b5a89e280d9f12b00a1210bf9f6f12ace0fbf`

---

## 1. Confirmed facts

### Board for HP 15c CE (ATSAM4LC2C)

There is **no** `at91sam4l8-ek` folder in SAM-BA 2.16.

- Board list (`extracted/tcl_lib/common/boards.tcl` line 125):  
  `"sam4l-ek[not factory programmed]"` → `at91sam4l-ek/at91sam4l-ek.tcl`
- That script accepts CIDR `& 0xFFFFFFE0` matching both:
  - `0xAB0A09E0` (SAM4L4 / 256 KB)
  - `0xAB0A07E0` (SAM4L2 / 128 KB) ← HP 15c CE
- Applet is compiled as `__ATSAM4LC4C__` / `sam4l4` but `flashcalw_get_flash_size()` reports the real size at INIT.
- GUI “Flash” send = `FLASH::SendFileNoLock` (write only; refuses dest page `< appStartPage`).
- Application start is page 32 = `0x4000`. Applet refuses writes below `MONITOR_SIZE` (`0x4000`).

HP Museum Windows instructions that say pick **sam4l-ek[not factory programmed]** match this installer.

### Applet binary

| Field | Value |
|---|---|
| Filename | `tcl_lib/at91sam4l-ek/applet-flash-sam4l4.bin` |
| Size | **2652** bytes (`0xA5C`) |
| Load address | **`0x20002000`** (`FLASH::appletAddr`, linker `sram` ORIGIN) |
| `G#` argument | **`0x20002000`** — vector table **base**, **not** Thumb entry |
| Initial SP (word 0) | `0x20007FF0` (unused by `G#`; monitor does not load SP) |
| Reset vector (word 1) | **`0x20002809`** = `0x20002808 \| 1` (Thumb bit) |
| Mailbox | **`0x20002040`** (32 words / 128 bytes, section `.mailbox` after 16-word vector table) |
| Buffer | Returned by INIT at mailbox `+0x0C`. Size forced to **512** (`FLASH_PAGE_SIZE`) — comment in source: “Timeout issue” |
| Stack used on `G#` | Monitor’s stack. Applet `ResetException` `push {r0-r12}` / `pop {r0-r12}` then returns |

Vector table dump of the 2.16 `.bin`:

```
[ 0] 0x20007FF0   SP
[ 1] 0x20002809   ResetException | 1
[ 2..15] 0
mailbox at +0x40 is zeros in the file
```

SRAM: applet at `0x20002000`; SAM-BA monitor uses `0x20000000`–`0x200007FF` (`romcodesram` in the linker). Do not load at `0x20001000`.

### Mailbox word layout

Base `mailbox = 0x20002040`. Little-endian 32-bit words. Union overlays args.

| Offset | Field | INIT out | WRITE in / out | UNLOCK in | ERASE_PAGE in |
|---|---|---|---|---|---|
| `+0x00` | `command` | `0x00` then `~cmd` | `0x02` then `~cmd` | `0x05` | `0x44` |
| `+0x04` | `status` | `APPLET_*` | `APPLET_*` | `APPLET_*` | `APPLET_*` |
| `+0x08` | argv0 | `memorySize` | in: `bufferAddr` / out: `bytesWritten` | `sector` | `page` |
| `+0x0C` | argv1 | `bufferAddress` | `bufferSize` | — | — |
| `+0x10` | argv2 | `bufferSize` | `memoryOffset` | — | — |
| `+0x14` | argv3 | `lockRegionSize:u16` \| `numbersLockBits:u16 << 16` | — | — | — |
| `+0x18` | | `pageSize` | | | |
| `+0x1C` | | `nbPages` | | | |
| `+0x20` | | `appStartPage` (32) | | | |

INIT **input** (written before `G#`):

| Offset | Value for USB CDC |
|---|---|
| `+0x00` | `0x00` (INIT) |
| `+0x08` | `comType` = **`0`** (`USB_COM_TYPE`) |
| `+0x0C` | `traceLevel` (0 is fine) |
| `+0x10` | `bank` = 0 |

Expected INIT on ATSAM4LC2C (128 KB): `memorySize = 0x20000`, `bufferSize = 0x200`, `pageSize = 0x200`, `nbPages = 256`, `appStartPage = 32`, `numbersLockBits = 16`. `bufferAddress` is `&end` (after BSS); **read it from INIT**, do not hard-code.

WRITE `memoryOffset` is from flash base `0x00000000`, so application page 0 is offset **`0x4000`**.

### Command and status codes

From `applet.h` / `appletCmdSam4l` (SAM4L extras in `at91sam4l-ek.tcl`):

| Name | Word | Use on 15c restore |
|---|---|---|
| `APPLET_CMD_INIT` | `0x00` | Load + INIT once |
| `APPLET_CMD_FULL_ERASE` | `0x01` | **Do not use.** Tcl GUI has it; **applet C has no case** |
| `APPLET_CMD_WRITE` | `0x02` | Page program (`flashcalw_memcpy(..., erase=true)`) |
| `APPLET_CMD_READ` | `0x03` | Optional; host `R#` of flash also works |
| `APPLET_CMD_LOCK` | `0x04` | `flashcalw_lock_region(sector, true)` — do not lock after restore |
| `APPLET_CMD_UNLOCK` | `0x05` | `flashcalw_lock_region(sector, false)` — region index 0..15 |
| `APPLET_CMD_SECURITY` | `0x07` | **Do not set** |
| `APPLET_CMD_FUSES` | `0x40` | GUI “Unlock All” / “Set Lock Bit” (GP fuses). Lock bit 0 = locked, 1 = unlocked |
| `APPLET_CMD_ERASE_PAGE` | `0x44` | Page number; refuses pages `< 32` |
| User page / unique SN | `0x41`–`0x43` | Not needed for restore |

Status (`applet.h`):

| Name | Value |
|---|---|
| `APPLET_SUCCESS` | `0x00` |
| `APPLET_DEV_UNKNOWN` | `0x01` |
| `APPLET_WRITE_FAIL` | `0x02` (locked region on WRITE also returns this, **not** `0x04`) |
| `APPLET_READ_FAIL` | `0x03` |
| `APPLET_PROTECT_FAIL` | `0x04` |
| `APPLET_UNPROTECT_FAIL` | `0x05` |
| `APPLET_ERASE_FAIL` | `0x06` |
| `APPLET_FAIL` | `0x0f` |

Completion: applet always does `pMailbox->command = ~(pMailbox->command)` then **returns**.  
INIT `0x00` → mailbox cmd `0xFFFFFFFF`. WRITE `0x02` → `0xFFFFFFFD`.

### Host sequence (exact)

Monitor commands (binary / `N#` already done). `G#` produces **no** serial payload.

1. `S20002000,<size>#` + 2652 applet bytes (`GENERIC::LoadApplet` / `TCL_Write_Data`).
2. `W20002040,00000000#` command = INIT. Then `W` comType / trace / bank at `+8/+C/+10`.
3. `G20002000#` — **not** `G20002001#`.
4. Wait for completion: **poll `w20002040,4#` until the word equals `~cmd`**. Then `w20002044,4#` for status.
5. Read INIT outputs (`memorySize`, `bufferAddress`, `bufferSize`, …).
6. Per 512-byte chunk (HP 15c: 224 pages):
   - `S<bufferAddress>,00000200#` + page bytes
   - `W` command `2`, argv0 = buffer, argv1 = 512, argv2 = flash offset (`0x4000`, `0x4200`, …)
   - `G20002000#`
   - Poll mailbox cmd == `~0x02`, status == 0, argv0 == bytes written
7. Optional unlock **before** write if status is write/protect fail:
   - Per-region: command `0x05`, argv0 = region index (app = regions **2..15** on 128 KB).
   - GUI “Unlock All” is **fuses `0x40`**, value `0xFFFF`, mask `0xFFFF` (sets 16 lock fuses to 1 = unlocked). Different from `0x05`.

`FLASH::SendFileNoLock` does **not** unlock. Official restore may rely on regions already unlocked, or a prior “Unlock All” click.

Windows `GENERIC::Run` (`generic.tcl`): `TCL_Go` then `after 10` (10 ms), then up to **10** `TCL_Read_Int` of the command word, **1 s** apart (25 retries for erase). Linux path spins without the 10 ms delay. Completion is **mailbox invert**, not a `G#` ACK.

AT09423 (same 2.x applet model): while the applet runs, the device is **not** in monitor mode. USB **NACK**s IN packets until `call_applet` returns. The next `w#` succeeds only after the applet returns to the monitor.

### What `G#` actually does on this monitor

`sam_ba_monitor.c` (`command == 'G'`):

```c
void call_applet(uint32_t address)
{
    uint32_t *ptr_reset_vector = (uint32_t *)(address + 4);
    ptrfunc.__ptr = (void *)(*ptr_reset_vector);
    ptrfunc.__fun();          /* CALL, not BX-never-return */
    __enable_interrupt();
}
```

Version string in this tree is `SAM_BA_VERSION "1.1"` plus `__DATE__` `__TIME__` — matches hardware `v1.1 Oct 16 2012 17:15:20`.

The applet `ResetException` (`applet_cstartup.c`) runs `applet_main`, then falls off the function so `BLX` returns to the monitor. It does **not** branch to a fixed monitor address. Host must not expect a `>` or any G# reply in binary mode.

A home-grown Thumb blob at `0x20001000` never ran: this monitor’s `G#` calls `[address+4]`, so a raw `.text` with no vector table is not the reset handler. Do not revive that approach.

### Cross-checks (not invented)

- **SAM-BA 2.16 installer**: primary evidence above. Applet sources ship inside the NSIS archive (`applets/sam4l/...`). Header still says `SAM_BA_APPLETS_VERSION "2.14"`.
- **SAM-BA 2.18**: same 2.x Tcl + applet model (AT09423). Treat the 2.16 `.bin` as the binary to drive unless a 2.18 dump differs by hash.
- **Public GitHub `xtremekforever/sam-ba`**: older 2.x applets; SAM4**S** EEFC `main.c`, not SAM4L FLASHCALW. Same mailbox *idea*, different flash driver.
- **bossac / BOSSA**: **no SAM4L**. Families are EEFC SAM3/SAM4S/SAM4E and SAMD. Protocol uses `S#` + `Y#` (WordCopy applet) / EEFC `FCR` — **not** this FLASHCALW mailbox. Do not copy BOSSA.
- **SAM-BA 3.x**: QML / different host API; secure-monitor applets on other chips. Not the v1.1 Oct 2012 USB CDC monitor.
- **AT03454**: SAM-BA lives in flash `[0, 0x4000)`, app at `0x4000`. Confirms why host FCMD stalls fetch.

---

## 2. Shipped host (`SambaFlashApplet`)

This is implemented. `SambaClient` keeps `N#` `V#` `w` `W` `R` `S` `G`. `go(_:)` sends `G%08X#` and returns (no prompt). `SambaFlashApplet` owns the official `.bin`, mailbox, INIT/WRITE/UNLOCK, and poll `~cmd`. `FlashCalw.writeApplication` calls the applet, not host FCMD.

- Reject `flashOffset < 0x4000`.
- Chunk to INIT `bufferSize` (512).
- Never send applet command `0x01` (full erase) or `0x07` (security).
- After every `S#`: `tcdrain` + 20 ms on hardware (`afterSendDelay`). After `G#`: 100 ms before the first `w#`; 1 s between poll retries.
- Tests: `commandSettleSeconds: 0` / `afterSendDelay: 0`.
