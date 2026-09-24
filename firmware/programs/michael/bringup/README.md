# Michael bring-up programs (2021-04-06 → 04-09)

These are the first programs for the **standalone** Michael board, stage 4 of the bring-up in [`hardware/michael/README.md`](../../../../hardware/michael/README.md). They were written after the Arduino stopped being needed, and before `base_config_v2.inc` existed. So they hard-code the board's addresses: VIA at `$6000`, code at `$8000`, and an 8-bit LCD with E/RW/RS on PORTA bits 7/6/5. They don't depend on the Arduino.

| Program | What it does |
|---|---|
| `leds.s` | Blinks LEDs on PORTB (Ben Eater's first program) |
| `hello-display.s`, `hello-ram.s`, `display-example.s` | LCD bring-up in 8-bit mode, from ROM and from RAM |
| `interrupt-test.s` | Keyboard interrupt handling. By 2021-04-09 it had become an on-screen console that prints successive keyboard scan codes. Includes `full_screen_console.inc` and `simple_buffer.inc`. |

Build with `firmware/vasm` or `tools/upload/compile_and_program.sh` (EEPROM).
