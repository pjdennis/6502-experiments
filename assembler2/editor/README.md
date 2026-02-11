# Editor (6502 vi-like)

Minimal vi-like text editor that runs under the project’s 6502 emulator in
console/ANSI mode.

## Architecture (files + roles)
- `editor.asm`: entry point, argument parsing, file load/save bootstrap,
  main loop, mode dispatch.
- `buffer.asm`: core text storage (contiguous bytes) + line table; all edits
  go through insert/delete routines and then rebuild the line table.
- `render.asm`: full-screen ANSI renderer (status line, cursor positioning).
- `input.asm`: console key reader + escape sequence parsing (arrow keys, etc.).
- `normal.asm`: normal-mode navigation + edit commands (h/j/k/l, x, dd, etc.).
- `insert.asm`: insert-mode edits (printables, Enter, Backspace, ESC).
- `command.asm`: command-line mode (`:w`, `:q`, `:wq`, `:q!`, `:NNN`).
- `terminal.asm`: ANSI helpers + small console output helpers.
- `23/environment.asm`: emulator I/O port definitions (shared with assembler).

## Control flow
1. `editor_main` (in `editor.asm`) parses argv, opens file if present, and
   loads buffer via `buf_load_file`.
2. If the file is truncated, `READONLY` is set and a warning is shown.
3. `render_init` + initial `render_screen`.
4. Main loop:
   - If `MODE == MODE_COMMAND`, run `command_handle` (does its own input).
   - Otherwise `read_key` and dispatch to `normal_handle_key` or
     `insert_handle_key`.
   - `FILE_LINE16` is recomputed from `VIEW_TOP16 + CURSOR_ROW` and
     `render_screen` redraws the full view.
   - `CMD_QUIT` exits.
   - EOT (`$04`) exits early for scripted/test mode.

## Data model & invariants
- **Text buffer**: `TEXT_BUF = $2000`, contiguous bytes, newline-delimited.
  Always ends with a newline; empty buffer is one newline.
- **Line table**: `LINE_TBL = $C000`, 16-bit pointers to each line start.
  `LINE_COUNT16` is recomputed in `buf_rebuild_lines` after every edit.
- **Buffer limits**: `TEXT_LIMIT` is conditionally defined at compile-time:
  - Normal build: `$C000` (40KB buffer: $2000-$BFFF)
  - Small buffer build (`define:small_buffer`): `$2100` (256 bytes: $2000-$20FF, used for testing)
- **Editor state**: `CURSOR_ROW/CURSOR_COL`, `VIEW_TOP16`, `FILE_LINE16`,
  `MODE`, `MODIFIED`, `READONLY` live in zero page.
- **Read-only mode**: set if file load truncates; edit keys are ignored and
  `:w` / `:wq` are blocked.

## Rendering + input
- Uses ANSI escape sequences via `terminal.asm` helpers (cursor move,
  clear line, reverse video status bar).
- `input.asm` normalizes backspace and parses ESC sequences to high-bit
  key codes (`KEY_UP`, `KEY_DOWN`, ...).

## Command mode
- `CMD_BUF` at `$0300` stores the command line; `CMD_QUIT` signals exit.
- Status messages (`show_status_message`) wait for a keypress to dismiss.

## Notes on remaining sections
- Paths in commands shown below are given relative to the parent of the editor folder

## Testing
- `editor/tests/editor_tests.py` assembles the editor (using `23/out/asm.out`
  via the emulator) and runs it under `./emulator.out`, feeding keystroke
  byte streams and verifying saved file contents.
- Bounds checking tests build `editor_small.out` assembled with
  `define:small_buffer` to create a 256-byte buffer, forcing
  truncation/read-only scenarios.

### Quick commands
- Run tests: `editor/tests/editor_tests.py`
- Run editor (console): `./editor.sh <file>`

## Tips for LLMs making changes
- Any edit that changes buffer contents must call `buf_rebuild_lines` and
  update `MODIFIED`.
- Keep the “always newline-terminated buffer” invariant intact.
- When moving between lines, clamp `CURSOR_COL` to the current line length.
- Normal-mode edit keys should be gated by `READONLY`.

## Build/run
- Assemble (release): `./emulator.out 23/out/asm.out editor/editor.asm editor/out/editor.out`
- Assemble (small buffer): `./emulator.out 23/out/asm.out editor/editor.asm editor/out/editor_small.out define:small_buffer`
- Run (console): `./emulator.out editor/out/editor.out --load 0400 --console <file>`
- Shortcut: `./editor.sh <file>`
