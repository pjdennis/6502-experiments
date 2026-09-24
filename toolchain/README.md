# Toolchain

Languages and tools that run on the 6502, mostly inside the emulator (`emulator/`).

| Directory | What it is | Build / test |
|---|---|---|
| [`asm1/`](asm1/) | First self-hosting assembler (2022-11 → 2025-11, frozen). A 6502 assembler written in 6502 assembly, run on its own fake6502-based `emulator.c`. `asm4v` is assembled by vasm, then asm4b → … → asm4b13, and asm4b13 must reproduce itself byte for byte. | `cd asm1 && ./asmtestgen.sh` (needs vasm and `hexdump`) |
| [`asm2/`](asm2/) | Second assembler (2026), bootstrapped from nothing. `00/asm.c` is a tiny C assembler for DATA lines. Each stage `NN/` is assembled by the binary of stage `NN-1`. Stages `00`–`16` are frozen snapshots that the chain still runs; **`17/` is the live assembler**. [`asm2/BOOTSTRAP-OVERVIEW`](asm2/BOOTSTRAP-OVERVIEW) lists what each stage added. | `cd asm2 && ./verify.sh` (the whole chain, 501 in-assembler tests, 1,548 editor tests, terminal tests) |
| [`asm2/editor/`](asm2/editor/) | vi-like text editor (~7.5k lines), written in asm2's dialect and built by stage 17. | `cd asm2 && python3 editor/tests/editor_tests.py`; run it with `asm2/editor.sh` |
| [`prog8/`](prog8/) | Prog8 compiler work: host compiler `p8c` (Python), `tinyp8`, and `p1`, a self-hosting compiler that compiles its own source on the emulated Wendy 2 (`fb90b8e`). Also custom upstream prog8c targets (`upstream/`). Assembles with vasm through `firmware/vasm`. | `make -C prog8 test`; `make -C prog8 wendy2-test` (needs prog8c and 64tass) |

Editor syntax highlighting: `asm2/vscode-asm6502/`, `asm2/asm6502.vim`.
