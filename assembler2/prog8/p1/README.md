# p1 -- the Prog8 parser port (Phase 6, step 5)

`p1` is the on-target rewrite of the host parser: a Prog8 program that
runs on the 6502 (the emulator's nmos-default machine) and reproduces
the host parser's output, milestone by milestone, diffed byte-for-byte
against a Python oracle. See [`../PARSER_PORT_DESIGN.md`](../PARSER_PORT_DESIGN.md)
for the full plan (data representations, the serialization contract, and
milestones M0..M5).

## Status

* **M0 (done)** -- the canonical serialization contract, frozen on the
  Python side: `../p8c/serialize.py` (`serialize` for the AST,
  `serialize_tokens` for the token stream) + `p8c --dump-ast` /
  `p8c --dump-tokens`, frozen by `../tests/test_serialize.py`.

* **M1 (done)** -- `lexer.p8`: the on-target lexer. Reads a `.p8`
  source (argv[0]) and writes the canonical token-stream dump (argv[1]),
  byte-identical to `p8c --dump-tokens`. Verified by
  `tests/test_lexer.py` over every `examples/*.p8`, the snapshot corpus,
  `tinyp8.p8` (1289 lines), `lexer.p8` lexing **its own** source, and a
  focused edge-case corpus (every numeric base, every char/string
  escape, keyword traps, multi-char-operator maximal munch).

* M2 (expressions) .. M5 (capacity) -- to come.

## Running

    # all p1 milestone tests (SKIPs without vasm6502_oldstyle + emulator):
    make -C assembler2 p1-test

    # by hand: build, run on the emulator, diff against the oracle
    python3 -m p8c p1/lexer.p8 -o /tmp/lexer.s
    vasm6502_oldstyle -Fbin -dotdir -ignore-mult-inc -esc -wfail \
        -o /tmp/lexer.bin /tmp/lexer.s
    assembler2/emulator/emulator.out /tmp/lexer.bin SOURCE.p8 /tmp/out.dump --no-dump
    diff <(python3 -m p8c SOURCE.p8 --dump-tokens) /tmp/out.dump

## Notes

* The lexer uses the same file-I/O shim as `tinyp8/` (syscalls at
  `$F006..$F03C`): argv[0] = input, argv[1] = output, read via `$F018`,
  write via `$F024`.

* Integer literals are accumulated into a `uword`, so values must fit in
  16 bits (the realistic corpus does). Decimal output uses power-of-ten
  subtraction because host p8c has no `/` or `%`.

* **Host p8c codegen caveat (worked around here):** an expression in
  which *both* operands of a binary op each need a scratch temp is
  mis-compiled -- e.g. `(v << 3) + (v << 1)` yields the wrong value (the
  first operand's temp is clobbered by the second). `lexer.p8` therefore
  never nests a shift inside an add: shifts go into their own locals on
  their own statements (see `umul10`), then plain var+var adds combine
  them. Worth fixing in p8c codegen eventually; until then, keep
  on-target arithmetic decomposed.
