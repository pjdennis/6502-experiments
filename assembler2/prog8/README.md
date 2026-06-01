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

**Phase 2** (continued):

  * `uword` type with 2-byte ZP storage; literals + var load/store +
    ubyte-widens-to-uword.
  * `for var in lo to hi { ... }` -- inclusive range over a ubyte var.
  * `peek($addr)` and `poke($addr, byte_expr)` builtins.
  * `txt.print_uw(uword)` -- 4 hex chars, high byte first.
  * Module-level var initializers run at the top of `main()`.
  * `examples/peek_demo.p8` -> `00010203 1234 4C` on the LCD.

**Phase 2.5 -- uword arithmetic + subs with params/returns:**

  * Full uword arithmetic: + - & | ^ << >> with carry chains, ==
    != < <= > >= via the 16-bit unsigned-compare idiom.
  * `sub foo(ubyte x, uword y) -> ubyte { ... }` with parameter
    passing (caller stores into mangled ZP slot, then JSR) and
    `return value` (jmp to per-sub epilogue).
  * `asmsub name(...) -> rt = $ADDR` -- declare bindings to existing
    6502 routines; codegen JSRs the literal address.
  * Char literals: `'h'` lexes as an INT token.
  * `examples/uword_arith.p8`, `examples/subs.p8`.

**Phase 3 -- nmos target + self-host milestone:**

  * `%target nmos` switches the prologue: no wendy2c-specific includes,
    reset vector emitted at `$FFFC`, `main()` ends with `jsr $F00F`
    (exit syscall) on the nmos-default machine.
  * `tinyp8/tinyp8.p8` -- the hand-written `tinyp8.s` rewritten in
    Prog8, using asmsubs for the file-I/O stubs and a small inline-asm
    helper for the `read` carry-EOF signal.
  * **Self-host equivalence test**: for every `.tp8` in
    `tinyp8/tests/goldens/`, both `tinyp8.s` (hand-asm) and
    `tinyp8.p8` (compiled by p8c) produce **byte-identical** output.
    4/4 cases pass: a real working compiler, written in Prog8,
    compiled by our own host compiler, agrees bit-for-bit with the
    reference assembly version.

**Phase 3 cont -- language built out toward Prog8 parity:**

  * Fixed-size `ubyte[N]` arrays (1..256) with indexed read/write.
  * `*` ubyte multiplication via a runtime helper (shift-and-add).
  * `@(addr_expr)` byte read/write at arbitrary addresses (via the
    `__p8c_ptr0` indirect-Y pointer in ZP); literal addresses use
    direct absolute load/store.
  * `&name` address-of operator (returns a uword).
  * `const ubyte/uword NAME = LITERAL` -- compile-time constants
    folded to immediate loads at every use site.
  * Builtins: `lsb`, `msb`, `mkword`, `len`, `sizeof` (all
    statically lowered).
  * `when expr { v1, v2 -> body; else -> body }` -- linear
    cmp-and-branch dispatch, ubyte or uword.
  * `inline sub` -- body spliced at each call site; per-callsite
    return label so `return` jumps locally.
  * **Long-branch handling**: all forward conditional branches in
    if/while/for/repeat now emit as `invert-branch + JMP` so they
    work at any distance. Costs +3 bytes per branch; always-safe.

Real-program demos in examples/:
  * arrays.p8, memptr.p8, squares.p8, consts.p8, when.p8,
    inline_demo.p8, **sieve.p8** (Sieve of Eratosthenes, exercises
    arrays + multiplication + nested loops + when -- prints primes
    < 64 in hex).

Self-host equivalence (tinyp8.s == tinyp8.p8) still 4/4 -- new
features are additive, the tinyp8 corpus uses the original v0
language and remains byte-identical to the reference asm.

Still ahead for *full* Prog8 self-host:
  * `byte` / `word` signed types
  * `enum`, structs, defer
  * Strings as proper iterable buffers (currently only literal
    -> address; need string compare, length, slicing)
  * Iterative parser architecture -- Prog8 forbids recursion, so
    porting p8c (currently recursive-descent in Python) requires
    rewriting the parser around an explicit AST stack.

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
