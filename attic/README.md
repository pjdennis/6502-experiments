# Attic

Things that are no longer used or no longer work, kept here for the owner to review. Nothing here is built or tested. `tools/firmware_manifest.py` skips this directory.

Each item keeps its original path. For example, `attic/assembler2/webserver/` used to be `assembler2/webserver/`. Its full history is still available with `git log --follow`. Moved in the reorganization, 2026-09-24. See `docs/REORGANIZATION_PLAN.md`.

For each item, decide whether to **delete** it (it stays in git history), **restore** it (`git mv` it back and fix it), or **keep** it here.

| Item | Last changed | Why it's here |
|---|---|---|
| `stty` | 2020 | Stray binary (687 bytes), not referenced |
| `DISPLAY_S` | 2020 | Stray assembly listing |
| `a.out.old`, `a.out.reference` | 2023 | Old build outputs from michael_keyboard_wip |
| `display_routines_original.inc`, `upload_and_run.old.inc`, `michael_keyboard-v2.s.old` | 2020–21 | Superseded copies of live files |
| `lcd.asm`, `lcd_test_2.asm` | 2022-02 | Stand-alone LCD tests with hard-coded `$6000` addresses; no longer assemble |
| `commands.txt`, `gdiff.sh`, `Connection 38400.stc` | 2020 | Early notes, a git-diff helper, and serial-terminal settings |
| `TODO` | 2022-02 | Old to-do list |
| `test/` | 2020–23 | vasm syntax experiments and `makebin*.py`; most don't assemble |
| `plan-for-wendy2-merge-sort-demo.md` | 2026-05 | Plan for `wendy2_merge_sort.s`, which has been implemented |
| `assembler2/webserver/`, `assembler2/tests/` | 2026-03/07 | 6502 HTTP demo and its test. They need the emulator socket API, which was never ported (tag `archive/install-hexdump`), and use stage `23/` paths |
| `assembler2/terminal_demo/` | 2026-02 | ANSI terminal demo; uses stage `23/` paths |
| `assembler2/webapp/` | 2026-03 | Python "hello world" server; not 6502-related |
| `assembler2/gogen.sh` | 2026-02 | Watch mode for `emulator.c`, which no longer exists |
| `assembler2/new_asmtestgen.sh` | 2026-02 | Alternate bootstrap-chain script, superseded by `asmtestgen.sh` |
| `assembler2/check_ascii.sh` | 2026-02 | Scans the old `22/` and `23/` stages |
| `assembler2/REVIEW` | 2026-02 | Review of asm22 (before the renumber) |
| `assembler2/archive/` | 2026-02 | Earlier plan documents |
| `assembler2/UNIFIED_PARSING_ANALYSIS.md` | 2026-07 | Analysis for the `asm-unified-parsing` refactor, which was never ported to stage 17 (tag `archive/asm-unified-parsing`) |
