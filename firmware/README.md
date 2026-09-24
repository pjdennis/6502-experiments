# Firmware

6502 assembly for the real boards, assembled with **vasm 1.9f** (`vasm6502_oldstyle`).

```
firmware/
  vasm            vasm6502_oldstyle + every include directory below (-I)
  include-dirs    the include directories, one per line
  manifest.txt    sha256 of every program's binary (regression check)
  boards/         per-board config, machine init, RAM/EEPROM upload loaders
    wendy/        Wendy (v1):     base_config_v1.inc, initialize_machine_v1.inc, upload_and_run_{ram,eeprom}_v1.s
    michael/      Michael (v2):   ..._v2
    wendy2/       Wendy 2 rev c:  ..._wendy2c, plus the wendy2c_monitor.s boot monitor
  lib/            shared routines, included by file name
    core/         6522 registers, delays, utilities, memory copy, number conversion, buffers, macros
    lcd/          HD44780 routines (4-bit and 8-bit), display_* helpers
    graphics/     SPI/parallel graphic display, character patterns, graphics console
    console/      text consoles, command table, REPL
    keyboard/     key codes/names, typematic, keyboard driver (COMMANDS regenerates key_names.inc)
    sound/        tones, musical notes, morse
    tasks/        prg_* tasks used by the multitasking demos
    serial/       upload_and_run.inc, the bit-banged serial loader
  programs/
    wendy/  michael/  wendy2/   programs for each board (by the base_config they include)
    michael/bringup/            first standalone-board programs (2021-04), hard-coded addresses
    michael/bbc-basic/          BBC BASIC MOS shim (needs the external ../BeebEater tree)
    common/                     board-independent experiments
  fonts/          font8x8 sources and dumpers
```

## Building

Programs `.include` libraries and board configs by bare file name (`.include base_config_v2.inc`, `.include display_routines.inc`). `firmware/vasm` adds every directory in `include-dirs` to vasm's include path, so a program can be assembled from any directory:

```bash
firmware/vasm -wdc02 -wfail -Fbin -dotdir -ignore-mult-inc -esc -o a.out firmware/programs/wendy2/hello_ram_4000_wendy2c.s
```

For hardware, use the scripts in [`tools/upload/`](../tools/upload/). They assemble to `a.out` in the current directory and then send it:
- `compile_and_upload_{wendy,michael,wendy2,wendy2_noreset}.sh <program.s>` send over serial with `transfer.py`. These builds use `-esc`, for programs uploaded to RAM through the board's loader.
- `compile_and_program.sh <program.s>` burns an AT28C256 EEPROM with `minipro` (no `-esc`).

Because includes are resolved by name, **file names must be unique across the include directories**. `firmware/vasm` uses `vasm6502_oldstyle` from `PATH`, or `$VASM` if set.

### Why vasm 1.9f

Two changes in newer vasm break this code:

- **vasm 2.0 and later reject `lda #(>X)`.** The Michael graphics macros use it, so `graphics_macros.inc` and 8 programs fail to assemble.
- **vasm 2.0d and later no longer add a NUL after `.ascii` strings.** Some older programs rely on the terminator; `4bit_hello.s` assembles but prints garbage.

Porting to current vasm is future work.

## Regression check

`tools/firmware_manifest.py` assembles every `.s`/`.asm` under the repository (except `attic/`, `emulator/` and `toolchain/`) twice: once with `-esc` and once without. It compares each output's sha256 with `manifest.txt`. `FAIL` entries record programs that don't assemble today.
- 39 entries contain a `FAIL`, as of the 2026-09 reorganization. They are mostly 2020–21 Wendy programs whose includes no longer match the current libraries.
- Programs that build only with `-esc` show `noesc=FAIL`.

```bash
python3 tools/firmware_manifest.py check  --include-list firmware/include-dirs   # what CI runs
python3 tools/firmware_manifest.py update --include-list firmware/include-dirs   # after an intended change
```

When a change is meant to alter a binary, run `update` and review the manifest diff in the same commit.
