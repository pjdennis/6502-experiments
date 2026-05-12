# `assembler2/emulator/`

A two-machine 6502 emulator:

- **`nmos-default`** — the original direct-memory NMOS 6502 used by the
  assembler bootstrap and the editor. Memory-mapped I/O at
  `$F006`/`$F009`/`$F00C` (read/write/error byte ports) and the rest of
  the file/console/socket ports the assembler relies on.
- **`wendy2c`** — a board-level model of the wendy2c machine: 28C256
  ROM, 628128 banked RAM, 22V10 PLD clock + chip-select decoder, 6522
  VIA, HD44780 LCD, serial-USB bridge, LED + button, all wired to a
  W65C02S core. Selected with `--machine wendy2c`.

The default machine is `nmos-default`; nothing about the assembler
bootstrap chain changed when the wendy2c work landed.

## Building and testing

```bash
make                     # build emulator/emulator.out + bootstrap asm
make test                # C unit tests + wendy2c golden-LCD tests
make wendy2c-goldens     # just the wendy2c end-to-end tests
make harte               # Tom-Harte ProcessorTests (opt-in; needs data)
```

`make test` runs the greatest C suites for every chip module and the
shell-based `wendy2c_goldens.sh`. The goldens script skips with a
warning if `vasm6502_oldstyle` isn't on `PATH`, matching the Harte
runner so CI without vasm still passes.

## CLI

```
emulator <code file> [options] [<arguments>]
emulator --server
```

Common options (the full list is in `--help`):

| Option | Notes |
|---|---|
| `--machine <name>` | `nmos-default` (default) or `wendy2c` |
| `--cpu <variant>` | `nmos` or `65c02` (wendy2c forces `65c02`) |
| `--rom <path>` | wendy2c: ROM image; falls back to the positional code file |
| `--serial-input <path>` | wendy2c: bytes pre-queued into the SERIAL_USB chip |
| `--live` | wendy2c: live ANSI render of LCD, LED, button, VIA pins |
| `--cycle-cap N` | max cycles before forced exit (decimal; default 200000000; no cap under `--live` unless this is given explicitly). For wendy2c this is oscillator ticks (~2 per CPU cycle); for `nmos-default` and `--server` it is CPU cycles. |
| `--load <hex>` | load address for the positional code file |
| `--input` / `--output` / `--error-output` | ports `$F006` / `$F009` / `$F00C` |
| `--dump` / `--no-dump` | memory dump on exit |
| `--console` / `--terminal` | full-screen UI modes (mutually exclusive) |
| `--mhz` / `--cpu-mhz` / `--baud` | wall-clock pacing + serial timing |
| `--rows N` / `--cols N` | terminal-size overrides |

## wendy2c demo

`emulator/demo_wendy2c.sh` is the end-to-end smoke launch. It:

1. Assembles `upload_and_run_eeprom_wendy2c.s` into a boot ROM.
2. Assembles a payload (default `hello_ram_4000_wendy2c.s`; override
   via `DEMO_PAYLOAD=...`).
3. Frames the payload (length + bytes + BSD checksum) using
   `wendy2_upload.py`.
4. Runs the emulator with the framed bytes pre-queued so the boot ROM
   uploads them into RAM, jumps to `$4000`, and the payload writes to
   the LCD.

Cycle cap default is 3,000,000 oscillator ticks (~150 ms wallclock).
Override with `DEMO_CYCLE_CAP=<N>`. The script fails fast if any
vasm invocation errors — older vasm releases that don't recognise
flags like `-ignore-mult-inc` will abort cleanly.

Pass `--live` to launch straight into the live render instead:

```sh
bash assembler2/emulator/demo_wendy2c.sh --live
DEMO_PAYLOAD=wendy2c_led_test.s bash assembler2/emulator/demo_wendy2c.sh --live
```

`--live` runs uncapped (`DEMO_CYCLE_CAP` still overrides if you want a
fixed-length recording); `q` / `ESC` / `Ctrl-C` in the panel quits.

## `--live` mode

`--live` (wendy2c only) enters an ANSI alternate-screen and renders
every ~30 ms:

```
  LCD:
  +----------------+
  |Hi! I'm Wendy 2.|
  |0042            |
  +----------------+

  LED PB6: [*]    BTN PA5: [ ]   (SPACE)

  PORTA bits:  1 0 1 0 0 1 1 0    DDRA=$FF
                D7  D6 BTN  D4  RW GDC GDR  RS

  PORTB bits:  0 1 0 0 0 1 0 1    DDRB=$3F
                T1 LED   E  B4  B3  B2  B1  B0

  osc:8200000  cpu:4087045  pc:$402E  irq:0  
```

Keys:
- `q` / `ESC` / `Ctrl-C` — quit (terminal contents are restored)
- `SPACE` — toggle the control button (drives PORTA bit 5)

Pacing targets ~10 MHz CPU (≈ the real wendy2c board's 9.72 MHz) so
the LED blink and morse-code timings look like the hardware. The
alternate-screen save/restore plumbing is shared with `--console` and
`--terminal` via `tty_alt_screen.{c,h}`.

## File layout

```
emulator/
├── emulator.c              main + nmos-default loop + server
├── cli.{c,h}               argument parsing + usage
├── emu_run.{c,h}           emu_run_default loop
├── emu_wendy2c.{c,h}       emu_run_wendy2c + the --live renderer
├── bus.{c,h}               chip vtable + bus walk
├── cpu_core.{c,h}          fake6502-derived CPU; NMOS + 65C02 variants
├── tty_alt_screen.{c,h}    alt-screen + raw termios save/restore
├── trace.{c,h}             E6502_TRACE ring buffers
├── console.{c,h}           full-screen console UI
├── file_io.{c,h}           the nmos-default file ports
├── chips/
│   ├── osc.c               oscillator (drives bus->osc_ticks)
│   ├── clock_22v10.c       PLD model: chip-selects + CPU clock
│   ├── rom_28c256.c        32 KiB ROM
│   ├── ram_628128.c        128 KiB banked RAM
│   ├── cpu_65c02.c         CPU-on-bus wrapper for the wendy2c machine
│   ├── via_6522.c          6522 VIA: regs + T1/T2 + IRQ + CB2/SR
│   ├── lcd_hd44780.c       4-bit HD44780 + DDRAM/CGRAM render
│   ├── serial_usb.c        USB serial -> VIA CB2 + SR shift
│   └── led_buttons.c       LED PB6 tap + control-button injection
├── demo_wendy2c.sh         end-to-end demo (assemble + upload + run)
├── wendy2_upload.py        framed-payload writer (length + BSD checksum)
└── tests/
    ├── test_chip_*.c       per-chip greatest suites
    ├── test_*.c            CLI / emu_run / bus / CPU tests
    ├── harte/              optional Tom-Harte ProcessorTests harness
    └── wendy2c_goldens.sh  end-to-end golden-LCD checks
```

## Testing references

- **Klaus Dormann's** 6502 functional tests — `tests/dormann/`. Built
  by `tests/test_dormann.c` for the NMOS and 65C02 variants.
- **Tom Harte's ProcessorTests** — `tests/harte/`. Fetched on demand
  via `tests/harte/fetch.sh`. `make harte` runs them when the data is
  present; otherwise prints a warning and exits 0.
- **wendy2c goldens** — `tests/wendy2c_goldens.sh`. Builds and
  uploads real wendy2c programs through the boot-ROM upload protocol
  and checks the resulting LCD frame.

## See also

- `WENDY2_EMULATOR_PLAN.md` — phase-by-phase plan with the design
  rationale for the bus / chip-vtable layout, cycle-pacing strategy,
  and the (still-open) audio + ST7920 + snapshot phases.
- `INVESTIGATION-wendy2c.md` — pre-phase-0 notes on the 22V10 PLD
  decode, serial RX timing, RAM bank ordering, and LCD pin map.
