# wendy2 -- custom banked Prog8 target

A custom (external) upstream-Prog8 compilation target for the
6502-experiments **wendy2c** machine, with first-class helpers for its
upper-window memory banking. Design + hardware details:
[`../../WENDY2_BANKING_TARGET_PLAN.md`](../../WENDY2_BANKING_TARGET_PLAN.md).

## Files

    upstream/
      wendy2.properties          # the custom target (-target wendy2.properties)
      wendy2_run.sh              # compile + boot + upload + run + print LCD
      libraries/wendy2/
        syslib.p8               # sys/cx16/p8_sys_startup; exit = STP
        textio.p8              # HD44780 4-bit LCD: clear/line2/chrout/print/print_ub
        banking.p8            # set_upper_bank / bank_peek / bank_poke / bank_call
      demos/                   # .p8 demos (m0,m1,t1..t4)
      tests/                  # test_wendy2.py + goldens/*.expected.lcd

## Memory model (summary)

* `$0000-$7FFF` fixed RAM (program loads at `$4000`, ZP, stack).
* `$8000-$EFFF` the **switchable window**: 8 RAM banks.
* `$F000-$F7FF` VIA 6522 (always mapped; carries the bank-select port).
* `$F800-$FFFF` fixed RAM (CPU vectors live here; stable across banks).

Banks are selected by VIA PORT B bits 0-4. Logical bank 0..7 map to PORTB
configs `$01,$11,$12,$13,$14,$15,$16,$17` (cfg `$00`/`$10` = ROM). The
banking helpers use that table; `bit 5` (LCD E) is preserved on every switch.

## Banking API (`%import banking`)

    banking.set_upper_bank(n)            ; select logical bank 0..7
    banking.bank_peek(n, win) -> ubyte   ; read $8000-$EFFF in bank n (auto-restore)
    banking.bank_poke(n, win, val)       ; write   "          "
    banking.bank_call(n, win) -> ubyte   ; JSR a routine in bank n, restore, return A

`win` is an absolute address in `$8000-$EFFF`. `bank_call`'s callee must end
in `RTS`; the trampoline lives in the fixed lower 32K so the return works.

## Build / run / test

    # one demo (prints the final LCD frame):
    cd assembler2/prog8/upstream && ./wendy2_run.sh demos/t1_bank_probe.p8

    # the golden test suite:
    make -C assembler2 wendy2-test

Prereqs: `prog8c.jar` at `/tmp/prog8c.jar` (or `$PROG8C`), `64tass` and
`vasm6502_oldstyle` on PATH, and the emulator built
(`make -C assembler2 emulator/emulator.out`). The suite skips cleanly if
any are missing.

## Demos / tests

| demo | shows |
|------|-------|
| `m0_exit`        | target boots + halts (blank LCD) |
| `m1_hello`       | LCD driver: two lines of text |
| `t1_bank_probe`  | **8 distinct data banks**: `ABCDEFGH` |
| `t2_banked_data` | banked arrays across 2 banks: `sum=7F80 / a+b=255 OK` |
| `t3_banked_code` | **banked code** via far-call: `far ret=2A / banked code OK` |
| `t4_bank_counters` | 8 independent per-bank counters: `33333333` |

## Status / not yet done

The `$F800+` OS-call read/write ABI (plan S2.6, milestone M5) is not yet
implemented -- it needs an emulator enhancement (a host-I/O port block
above the VIA) and is the prerequisite for running a file-I/O toolchain on
wendy2c. The banking demos here don't need it (output is the LCD).
</content>
