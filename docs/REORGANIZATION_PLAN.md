# Repository reorganization plan

Status: **proposal**. Nothing described here has been done yet. Analysis date: 2026-09-24.

## 1. Current state

### 1.1 History shape

- There is **one connected history** of 2,562 commits from a single root, `d297d44` (2020-07-20, "initial").
  - Note: Claude Code web sessions clone shallowly. Run `git fetch --unshallow` before analysing, or the history appears to have re-roots at `49d4c4c` and `2d486fc` that aren't really there.
- `main` (tip `9c3b88e`, 2026-01-10) is far behind. All current work is on a chain of `claude/*` branches, and each branch contains the previous ones. The tip of the chain is `claude/pld-hardware-memory-map-3hslxb` (`dd0cf45`, 2026-09-23), which is 1,545 commits ahead of `main`.
- `michael_keyboard_wip` forked from `main` at `536f200` (2023-04-22). It has 235 commits of its own: 225 from 2023, 7 from 2024 and 3 from 2026. It has never been merged back.

### 1.2 Projects that share this repo

| Area | Where it is today | Toolchain | Activity |
|---|---|---|---|
| SBC firmware for three boards: **Wendy (v1)**, **Michael (v2)** and the **Wendy2 family (wendy2 → 2b → 2c, 65C02 + 22V10 PLD, 512 KiB banked RAM)** | ~200 flat files at the root (`*.s`, `*.inc`) | vasm6502_oldstyle | 2020 → 2026 |
| Peripheral drivers: HD44780 LCD (4-bit/8-bit), SPI/parallel graphic display, keyboard via shift registers, sound/music, bit-banged serial, multitasking | root `*.inc` | vasm | 2020 → 2023 |
| Host tools: `transfer*.py` (serial upload), 15 `compile_and_upload_*.sh`, `makerom.py`, LCD OCR tools | root | Python and sh | |
| Arduino monitor/programmer sketches for Michael | `michael/` | Arduino | 2021 |
| Fonts | `font8x8/`, `character_patterns*.inc` | C and Python | |
| **asm1**: first self-hosting assembler (fake6502-based `emulator.c`, chain asm4v → asm4b13) | `assembler/`, duplicated in `assembler2/legacy/` | C and 6502 | 2022-11 → 2025-11 (frozen) |
| **asm2**: bootstrap chain from zero (`00/asm.c` → stages 01..17; 00–16 are frozen directory snapshots, only 17 is live) | `assembler2/NN/` | C and 6502 | 2026-01 → 2026-06 |
| **Editor**: vi-like, ~7.5k lines of 6502 | `assembler2/editor/` | asm2 stage 17 | 2026-02, 2026-07 |
| **Emulator**: fake6502 core; `nmos-default` host-stub machine plus a board-accurate `wendy2c` machine (PLD equations generated from `22V10-wendy2c.pld`); web, audio, serial-link and tracing features | `assembler2/emulator/`, `persistent_emulator.py` | C and Python | 2026-02 → 2026-09 |
| **Prog8 bootstrap**: p8c (Python), tinyp8, p1 self-hosting compiler; self-hosts on banked wendy2c (`fb90b8e`) | `assembler2/prog8/` | vasm, 64tass, prog8c | 2026-05 → 2026-06 |
| **BBC BASIC**: a MOS shim for Michael (`michael_beeb.s`, `ecfa0b0`, 2024-02-11) on `michael_keyboard_wip` only; it needs the external `../BeebEater` tree | root on mkwip | vasm | 2024 |
| BBC BASIC IV ROM analysis | `bbc-basic-four-analysis/` | Python | 2026-05 |
| Misc: webserver (6502 HTTP), terminal_demo, webapp, vscode/vim syntax | `assembler2/` | | stale |

### 1.3 Coupling that constrains the layout

- The emulator's `Makefile` reads `../22V10-wendy2c.pld`, which is hardware, and turns it into C.
- The emulator's goldens and demos assemble root-level `*_wendy2c.s` firmware.
- The editor `.include`s `17/environment.asm`, `17/macros.asm` and `17/to_decimal.asm`, and it is built by `17/out/asm.out`.
- prog8 runs on the emulator (both machines) and assembles with vasm.
- The bootstrap chain (`asmtestgen.sh`) builds stages in sequence, so each stage depends on the one before it.

Because of this coupling, splitting into several repos would need submodules or vendored copies in both directions, for example hardware → emulator and firmware → emulator tests. For a single developer that costs more than it gains.

### 1.4 Branch inventory and disposition

| Branch | Relation to chain tip (`pld-hardware-memory-map`) | Disposition |
|---|---|---|
| `claude/pld-hardware-memory-map-3hslxb` | tip | **becomes the new `main`** (fast-forward) |
| `claude/hdl-code-pld-uh33sg`, `editor-branch-merge-e7x682`, `assembler-v17-tests-copt83`, `prog8-bootstrap-continue-6Pzo0`, `review-wendy2-plan-MOfnA`, `review-stack-optimization-RvSu5`, `sync-text-editor-branch-AUWPA`, `setup-editor-assembler2-5cnH6`, `wendy2-emulator`, `text-editor`, `assembler2-tracking`, `main` | fully contained | delete (their commits stay reachable from main) |
| `claude/bbc-basic-four-analysis-JBZDp` (3 commits) | content copied in `5a7dd51` and identical | **real merge** (clean, so the 3 commits become ancestors), then delete |
| `michael_keyboard_wip` (235 commits) | diverged since 2023-04-22 | **real merge** (see Phase 1b), then delete |
| `asm-unified-parsing` (16 commits) | SKIP_FLAG refactor of old stage 23, never ported; noted as superseded in `5a7dd51` | tag `archive/asm-unified-parsing`, delete the branch |
| `claude/install-hexdump-5CahY` (22 commits) | webserver/webapp already copied; the **emulator socket API (`c3d9641`, `8ee8e70`, `9b974e8`) was never ported** and clashes with current stub addresses | tag `archive/install-hexdump`, open an issue "port socket API to modular emulator", delete the branch |
| `claude/prog8-assembler-gap-analysis-pJ7nG` (1 commit) | build outputs only (`.pyc`, `.wav`, generated `.asm`) | delete, no tag |

## 2. Future state

### 2.1 Decision: one repo, reorganized, with no history rewrite

- **Keep a single repository.** The coupling in §1.3 is real. Each area gets a top-level directory with its own README, so any area can later be split out with `git filter-repo --subdirectory-filter` if that becomes worthwhile.
- **Do not rewrite history.** The history is already connected and complete. Every reorganization step is a new forward commit. Because of this:
  - every old commit keeps its hash and still builds with the paths and scripts of its own time (`git worktree add /tmp/w <tag>`);
  - `git log --follow` and `git blame -C -C` follow files across the moves, provided the moves are **pure-rename commits** (§3, rule R2);
  - hash references in commit messages, such as "see 5a7dd51", stay valid.
- Rename the repo? `6502-experiments` → `6502-workbench`. This is optional; GitHub redirects old URLs.

### 2.2 Target layout

```
README.md                  map of the repo + quick "how to build X"
CLAUDE.md                  build/test commands (from assembler2/.claude/CLAUDE.md)
docs/
  history.md               eras, milestone tags, how each thing was built at the time
  REORGANIZATION_PLAN.md   this file
hardware/
  wendy/                   v1 notes (6522 @ $6000, 5 MHz, 4-bit LCD, PORTA banking)
  michael/                 v2 notes; arduino/ (from michael/: monitor/programmer sketches)
  wendy2c/                 22V10-wendy2c.pld, memory-map docs, PLD history notes
firmware/                  everything assembled by vasm for real boards
  Makefile                 BOARD=wendy|michael|wendy2c; -I lib/... ; build-all + manifest
  boards/
    wendy/     base_config.inc  initialize_machine.inc  upload_and_run_{ram,eeprom}.s
    michael/   (same)            + beeb/ (BBC BASIC MOS shim; expects external BeebEater)
    wendy2c/   (same)            + verification, monitor, eeprom tools
  lib/
    core/      6522, delay, utilities, copy_memory, to_decimal, convert_to_hex, buffer
    lcd/       display_routines{,_4bit,_8bit}, display_update*, display_* helpers
    graphics/  graphics_display, full_screen_console*, character_patterns*, graphics_* (mkwip)
    keyboard/  key_codes, key_names, keyboard_typematic, keyboard_driver (mkwip)
    sound/     sound, musical_notes*, morse
    tasks/     prg_*.inc (multitasking demo tasks)
    serial/    upload_and_run.inc
  programs/
    common/    board-agnostic tests/demos (buffer_test, to_decimal_test, …)
    wendy/  michael/  wendy2c/    board-specific demos and tests
  fonts/       font8x8/ sources + generators
tools/                     host-side
  upload/      transfer.py (the single parameterised version from mkwip: --port --baudrate
               --noreset, USB autodetect), compile_and_upload.sh, compile_and_program.sh
  makerom.py, keynames/ (COMMANDS generator), lcd-ocr/ (lcd_ocr, lcd_inspect, calibrate)
emulator/                  from assembler2/emulator/ + persistent_emulator.py
  (Makefile references ../hardware/wendy2c/22V10-wendy2c.pld and ../firmware/…)
toolchain/
  asm1/                    from assembler/ (+ extras only found in assembler2/legacy/)
  asm2/
    stages/00..16/         frozen bootstrap snapshots (load-bearing: the chain runs them)
    src/                   live stage 17 (the working assembler)
    bootstrap.sh           was asmtestgen.sh; run_tests.py, verify.sh
    pyasm/                 Python work-alike
  editor/
  prog8/
  syntax/                  vscode-asm6502/, asm6502.vim
research/
  bbc-basic-iv/            from bbc-basic-four-analysis/
attic/                     kept but not maintained: webserver, terminal_demo, webapp,
                           old plans/notes .md, lcd.asm, one-off experiments
```

Design notes:

- **Firmware include paths.** vasm's `-I` means the `.include "display_routines.inc"` lines don't need to change when the `.inc` files move into `lib/*`. The Makefile passes `-I` for each lib subdirectory and the board directory, so a program picks up its board's `base_config.inc` from `-I boards/$(BOARD)`. This replaces the `_v1` / `_v2` / `_wendy2c` filename suffixes.
- **Stage 17 vs a `src/` rename.** If moving stage 17 to `src/` makes the chain script awkward, keep the directory named `17/`. What matters is that the frozen stages are visibly separate from the live one.
- **Board name.** Use **`wendy2c`**. The emulator (`--machine wendy2c`), the PLD file and all 2026 work use it. The mkwip rename `wendy2c → wendy2` (`5440a45`) gets resolved in favour of `wendy2c` during the merge.

## 3. Migration plan

### Ground rules

- **R1 Green → move → green.** Following red-green-refactor, a reorganization is a pure refactor. First add the checks that prove nothing changed, and watch them fail when they should. Every move must then keep them green, with byte-identical outputs.
- **R2 Pure-rename commits.** Each move is its own commit containing only `git mv` (100% similarity). Path fixes (Makefiles, `.include`, scripts) go in a *separate* following commit. Git's rename detection then always works, so `--follow` and `blame` survive.
- **R3 One area per PR.** Small PRs into `main`, each with its tests green.
- **R4 Tag before deleting.** A branch is deleted only after its tip is reachable from `main` or has an `archive/*` tag.

### Phase 0: Safety net and baseline

1. `git fetch --unshallow`. Push `archive/<branch>` tags for **every** current branch tip, and keep a `git bundle create 6502-all.bundle --all` offline.
2. Record the green baseline on the chain tip:
   - `make -C assembler2 test` (emulator, prog8, tinyp8, p1)
   - `assembler2/asmtestgen.sh` (bootstrap chain, stage 17 self-assembles identically, 104 in-assembler tests)
   - `assembler2/verify.sh` (editor and terminal tests)
3. **New test, firmware golden manifest.**
   - Write `tools/check_firmware.sh`. It assembles every buildable firmware `.s` with its board's config and compares sha256 values against `firmware-manifest.txt`.
   - Red: the manifest doesn't exist yet, or an entry was deliberately corrupted. Green: the manifest is generated from the current tree.
   - Record the files that don't build today, such as the `wendy2_*` files that include a missing `base_config_wendy2.inc`, and the stand-alone `lcd.asm`. That way "already broken" is never confused with "broken by the move".
4. Add a GitHub Actions workflow that runs all four checks.
   - The runner needs `vasm6502_oldstyle` (build it from source in CI); prog8c and 64tass are needed for the upstream tests.
   - Every later PR must pass this workflow.

### Phase 1: Consolidate branches (history-bearing merges)

- **1a.** Fast-forward `main` to `claude/pld-hardware-memory-map-3hslxb`. Before that, check the September PLD decision (`17e4a78`: cfg `$18` = ROM upper + lower bank 2).
- **1b.** Merge `michael_keyboard_wip` into `main` with a real merge, so the 235 commits (graphics console, keyboard driver, BBC BASIC shim, generic transfer.py) become ancestors. Expected conflicts and how to resolve them:
  - **wendy2 ↔ wendy2c renames.** Keep the `wendy2c` names. Carry over mkwip's content edits (LED control `71298d5`; CONTROL_BUTTON/LED is already ported in `67e1a40`).
  - **PLD cfg `$18`.** mkwip `27bbc44` makes it RAM; main `17e4a78` (newer) makes it ROM. **The owner must decide.** The default is main's version, and the emulator config-map tests enforce it.
  - **transfer.py and upload scripts.** Take mkwip's parameterised `transfer.py` and its `compile_and_upload_{board}.sh`. Delete the per-baud copies.
  - **Diverged `.inc` files** (base_config_v2, upload_and_run.inc, graphics_display, key_codes, key_names, morse, musical_notes, …). Take mkwip for Michael-specific changes. For shared files, merge by hand and let the firmware manifest show which outputs changed on purpose.
  - Binary `michael-2023-12-04.rom`, `a.out.old`, `a.out.reference`: keep the ROM (document it in `hardware/michael/`) and drop the `a.out.*` files.
  - Regenerate `firmware-manifest.txt` and review each changed hash in the PR.
- **1c.** Merge `claude/bbc-basic-four-analysis-JBZDp`. The content is identical, so the merge is clean.
- **1d.** Delete the merged branches. Tag and delete `asm-unified-parsing` and `claude/install-hexdump-5CahY`. Open an issue to port the socket API to `emulator/` at new stub and port addresses. Delete `claude/prog8-assembler-gap-analysis-pJ7nG`.

### Phase 2: Hygiene in place (no moves yet)

- `.gitignore`: `out/`, `a.out`, `__pycache__/`, `*.pyc`, `*.wav` under test outputs.
- Remove junk:
  - `stty` (stray binary) and `DISPLAY_S` (stray listing)
  - `*.old`, `display_routines_original.inc`, `upload_and_run.old.inc`
  - numbered duplicate scripts: keep each only if a later file doesn't supersede it
- Fold `assembler2/legacy/` into `assembler/`. Only `bootstrap0.sh`, `tests/asm18..21_tests.txt` and a few `test*.asm` are unique; move those, then delete the 45 byte-identical copies.
- Fix stale references:
  - `23/` paths in `terminal_demo`, `webserver` and `tests/test_webserver.py`
  - `check_ascii.sh` and `gogen.sh`
  - `assembler2/README.md` still says 23 levels
- The firmware manifest and the Phase 0 tests must stay green, except for the reviewed deletions.

### Phase 3: Restructure (each step = one pure-rename commit + one path-fix commit + green CI)

Do the most depended-upon pieces first, so later steps only need their paths fixed once:

1. `22V10-wendy2c.pld` → `hardware/wendy2c/`. Fix the emulator Makefile and `pld_to_c.py` paths.
2. `assembler2/emulator/` and `persistent_emulator.py` → `emulator/`. Fix the Makefile split (the emulator gets its own Makefile; the prog8 targets move with prog8) and the Python imports.
3. `assembler/` → `toolchain/asm1/`.
4. `assembler2/{00..17}`, the chain scripts, `run_tests.py` and `pyasm.py` → `toolchain/asm2/`.
5. `assembler2/editor/` and the `editor*.sh` scripts → `toolchain/editor/`. Fix the `.include ../asm2/…` paths.
6. `assembler2/prog8/` → `toolchain/prog8/`.
7. Root `*.inc` → `firmware/lib/*`, and board configs → `firmware/boards/*` (dropping the suffixes).
   - This is the one step where the `.inc` files need a rename *with* different basenames, e.g. `base_config_v1.inc` → `boards/wendy/base_config.inc`.
   - Do it as pure renames first, then update the `.include` lines in a separate commit. The firmware manifest proves the outputs are identical.
8. Root `*.s` → `firmware/programs/{common,wendy,michael,wendy2c}/`. Classify each file by the `base_config_*` it includes; the Phase 0 script can print this.
9. Host tools → `tools/`. `michael/` → `hardware/michael/arduino/`. `font8x8/` → `firmware/fonts/`.
10. `bbc-basic-four-analysis/` → `research/bbc-basic-iv/`. The stale demos and plan docs → `attic/`.
11. Move the per-area `.claude/CLAUDE.md` and `.vscode` settings to the root and update them.

### Phase 4: Make the history navigable

Add annotated **milestone tags**. Each tag message says how the thing was built *at that point*: the script name, the external tools needed, and the board.

| Tag | Commit | Date | Milestone |
|---|---|---|---|
| `wendy/first-light` | `d297d44` | 2020-07-20 | first Wendy (v1) programs, Ben Eater-style |
| `michael/ram-upload` | `eb3853c` | 2021-04-09 | Michael (v2) board: RAM upload working, v1/v2 config split |
| `wendy2/upload` | `6be57cd` | 2022-04-10 | first Wendy2 (65C02 + PLD) |
| `wendy2c/intro` | `ae2865b` | 2022-04-30 | wendy2c advanced memory map, first `22V10-wendy2c.pld` |
| `wendy2c/full` | `ca09ca6` | 2022-07-22 | full wendy2c code set |
| `asm1/start` | `60be16b` | 2022-11-19 | asm1 bootstrap begins |
| `fork/michael-keyboard` | `536f200` | 2023-04-22 | michael_keyboard_wip forks |
| `michael/bbc-basic` | `ecfa0b0` | 2024-02-11 | BBC BASIC on Michael via the MOS shim |
| `asm1/self-hosts` | `07b2118` | 2025-11-15 | asm1 assembles itself byte-identically |
| `asm2/start` | `005e339` | 2026-01-06 | assembler2 enters version control |
| `editor/start` | `cc718c8` | 2026-02-07 | first editor/console program |
| `asm2/stages-00-17` | `79b02ab` | 2026-02-13 | chain renumbered 00–17 |
| `emulator/split` | `3b59d2d` | 2026-02-21 | emulator gets its own directory |
| `prog8/self-hosts` | `fb90b8e` | 2026-06-07 | p1 self-hosts on banked wendy2c |
| `wendy2c/pld-cfg18-rom` | `17e4a78` | 2026-09-23 | current PLD memory-map decision |
| `reorg/before`, `reorg/after` | — | — | bracket Phase 3 |

Also write `docs/history.md`, a timeline narrative per area covering the three boards, peripherals, asm1 → asm2 → editor → prog8, and the emulator. It should link these tags and explain how to check out and build an era (`git worktree add ../era-2021 michael/ram-upload`, then the scripts of that time and `vasm6502_oldstyle` in `./`).

### Phase 5 (optional, later): split repos

If an area gets outside users, for example the emulator or the editor, extract it with `git filter-repo --subdirectory-filter emulator`, which keeps that area's full history across the moves when `--path-rename` is also used for the old paths. Before that, the wendy2c PLD becomes an input that is copied or pinned, not read through `../`.

## 4. Decisions the owner needs to make

1. Is `claude/pld-hardware-memory-map-3hslxb` ready to become `main`?
2. PLD cfg `$18`: ROM upper (main, Sept 2026) or RAM (mkwip, May 2026)?
3. Board naming: `wendy2c` (recommended) or `wendy2`?
4. `asm-unified-parsing` refactor and install-hexdump socket API: archive only, or port?
5. Keep `attic/`, or delete stale demos outright (they stay in history either way)?
6. Rename the repository?
