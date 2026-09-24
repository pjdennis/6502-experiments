# Klaus Dormann 6502 / 65C02 functional tests

Vendored test sources used by the `test_dormann.out` harness to validate
the NMOS and 65C02 CPU dispatch in `../../cpu_core.c`.

## Upstream

- Project: `amb5l/6502_65C02_functional_tests` (ca65 fork of the
  original Klaus Dormann tests)
- URL: https://github.com/amb5l/6502_65C02_functional_tests
- Pinned commit: `966b1a35049f9d8be44ad092ec6d43d5ba1831b3`
  (`Merge pull request #5 from rofl0r/ca65_fix`)

## License

Klaus Dormann's tests are licensed under **GPLv3+**. See `LICENSE` for
the full text. This licensing applies only to the contents of this
directory; the rest of the repo's license is unaffected because the
test artifacts are never linked into shipped binaries.

## Build dependencies

The tests are built from source with the `cc65` toolchain
(`ca65` + `ld65`). On Ubuntu / Debian:

```
sudo apt-get install cc65
```

`ca65` and `ld65` need to be on PATH for `make`-driven builds. If the
toolchain is missing, `make` in this directory exits with a clear
message and `test_dormann.out` reports SKIP for the affected variants.

## Building

From this directory:

```
make
```

This produces three 64 KiB full-memory-image binaries in `out/`:

- `6502_functional_test.bin` -- exercises every NMOS opcode and
  addressing mode.
- `65C02_extended_opcodes_test.bin` -- exercises the W65C02S
  additions (BRA / PHX-PHY-PLX-PLY / STZ / TRB / TSB / `(zp)`
  indirect / JMP `(abs,X)` / RMB-SMB-BBR-BBS / WAI / STP / BCD N+Z).
- `6502_decimal_test.bin` -- exercises BCD ADC/SBC.

Each binary loads at $0000 with `success` at a fixed PC (`jmp *`):

| Binary                              | Success PC |
|-------------------------------------|------------|
| 6502_functional_test                | `$3469`    |
| 65C02_extended_opcodes_test         | `$24F1`    |

The harness runs each binary with PC = $0400 and watches for PC to
stay unchanged across two consecutive instructions; that PC is then
compared against the success table above.

## Files

- `6502_functional_test.ca65` -- NMOS Klaus test, ca65 syntax
- `65C02_extended_opcodes_test.ca65` -- 65C02 Klaus extended-opcodes test
- `6502_decimal_test.ca65` -- BCD test, ca65 syntax
- `example.cfg` -- ld65 linker config (places code at $0400, vectors at $FFFA)
- `LICENSE` -- GPLv3 (applies to the .ca65 sources and binaries built from them)
- `Makefile` -- builds `out/*.bin` via `ca65 + ld65`
