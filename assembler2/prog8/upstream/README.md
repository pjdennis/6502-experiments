# Upstream-bootstrap target for the self-hosting Prog8 compiler

Goal: compile the self-hosting compiler (`../p1/p1.p8`) with the **upstream**
Prog8 compiler (not our bootstrap `p8c`) and run it on the emulator, proving
the compiler is valid upstream Prog8 and self-hosts from the official toolchain.

- `nmos.properties` -- a custom Prog8 compilation target for this repo's
  emulator (6502/65C02, no ROM, I/O via the emulator's `$F006+` syscall stubs,
  RAW output at `$0200`).
- `libraries/nmos/syslib.p8` -- the target's syslib (adapted from upstream's
  Neo6502 custom-target example; exit routed to the `$F00F` emulator stub).
- `mkimage.py` -- wraps a prog8 RAW binary into the emulator's
  `$0200..$FFFF` image (sets the `$FFFC` reset vector to the `$0200` entry).
- `build.sh <src.p8> <out.bin>` -- compile with upstream + wrap into an image.
- `setup.sh` -- fetch `prog8c.jar` + build the `64tass` assembler it needs.
- `hello.p8` -- smoke test (writes "HI\n" via the syscall stubs).

Status: MILESTONE A done -- a trivial program compiled by upstream prog8c
v12.1.1 runs on the emulator and produces correct output.
