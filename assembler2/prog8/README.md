# Prog8 compiler for wendy2c

Bootstrap chain for a Prog8 compiler that eventually self-hosts on
wendy2c, mirroring the asm00..asm17 chain.

## Layout

    prog8/
        p8c/                  # Phase-1 "p0" host compiler (Python)
            __main__.py       # CLI driver: `python3 -m p8c`
            lex.py
            parse.py
            sema.py
            codegen.py
            stdlib_decls.py   # symbols the stdlib modules export
        stdlib/               # Prog8 + inline-asm stdlib modules (Phase 2+)
        examples/             # demo programs
            hello.p8
        tests/
            test_lex.py       # lexer unit tests
            test_parse.py
            test_sema.py
            test_codegen.py
            test_snapshots.py # .p8 -> .s text diffs (host oracle)
            test_e2e_lcd.py   # compile + assemble + emulate + LCD diff
            goldens/          # .p8 + matching .expected.lcd
            snapshots/        # .p8 + matching .expected.s

## Building / running

    # Build the emulator (needed by the e2e golden test):
    make -C assembler2 emulator/emulator.out

    # Run the test suite:
    make -C assembler2 prog8-test

    # Compile a .p8 by hand and inspect the .s:
    python3 -m p8c assembler2/prog8/examples/hello.p8 -o /tmp/hello.s

    # Compile + assemble + run on the emulator (prints the LCD frame):
    python3 -m p8c assembler2/prog8/examples/hello.p8 --run

## Phase status

**Phase 0** (scaffolding) and **Phase 1** (walking skeleton) -- done:

  * lex/parse/sema/codegen for `main { ... }`, `%address`, `%import`,
    `%output`, `txt.print("...")`, `lcd.clear()`.
  * Test pyramid wired up: unit, snapshot, end-to-end LCD golden.
  * `hello.p8` compiles, lands at `$4000` via the wendy2c boot ROM,
    prints to the HD44780.

**Phase 2** (start) -- done in this commit:

  * Module-level + sub-local `ubyte` variable declarations with
    optional initializers; ZP allocator starting at `$40` (variables)
    with `$20/$21` reserved as codegen scratch.
  * Assignment + augmented assignment (`+=`, `-=`, `&=`, `|=`, `^=`,
    `<<=`, `>>=`).
  * Binary expressions on `ubyte`: `+`, `-`, `&`, `|`, `^`, `<<`, `>>`
    plus comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`) and logical
    (`and`, `or`, `xor`, `not`) operators with C-like precedence.
  * Unary `~`, `-`, `not`.
  * Control flow: `if`/`else`, `while`, `repeat N`, `repeat` (forever),
    `break`, `continue`. Comparison conditions branch directly --
    no 0/1 materialization.
  * `txt.print_ub(byte)` -- prints two hex chars via the existing
    `display_hex.inc` helper.
  * Demo `examples/counter.p8` exercises all of the above:
    `total=0606 OK` on the LCD.

Phase 2 still to do (next push): `byte`/`uword`/`word` types, casts,
`const`, `enum`, arrays, `for x in 0 to N`, `when`, memory-mapped
vars, builtins (`peek`/`poke`/`lsb`/`msb`/...), more stdlib
(`lcd.cursor_at`, `lcd.putc`, `button.pressed`, `txt.print_uw`).

See the plan in conversation history for Phases 3-6, including the
on-emulator emit-equivalence test tier that activates at Phase 5 when
the compiler first runs on wendy2c.

## ABI notes (Phase 1)

  * Symbol prefixing per upstream Prog8: `p8v_` vars, `p8s_` subs,
    `p8c_` constants/strings, `p8l_` labels. Right now we only emit
    `p8s_` and `p8c_str_*`.
  * Default load address is `$4000` -- matches every existing
    serial-upload demo (`hello_ram_4000_wendy2c.s` etc).
  * Emitted .s uses asm17-compatible syntax that is also accepted by
    `vasm6502_oldstyle`. Phase 1 assembles with vasm for iteration
    speed; Phase 5 switches the bootstrap-verification path to asm17.
