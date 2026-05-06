# Plan: Unify Scope Stack with File Stack, then Move Macro Parameters to Activation Frames

This is the implementation plan for two related changes:

1. Merge the scope stack (`SCOPE_STACK` at `$0400`) into the file stack
   (downward stack at `$F000`), and rename the merged stack to better
   reflect its multiple roles.
2. Move macro parameter storage out of `LHASHTAB` into per-invocation
   activation records carried on the merged stack.

Both align with the design discussion captured in
`macro_local_design_notes.md` (which is **deferred** — do not pull
macro-local label work into this plan).

## Working principles

- Red/green TDD: failing test first, then implementation, then commit.
- Small commits — one increment per commit, story-of-the-work history.
- Refactor before changing behavior, refactor again after, both committed
  separately.
- After every commit: `./asmtestgen.sh` (full self-host verification) +
  `python3 run_tests.py -q` + `python3 editor/tests/editor_tests.py -q`
  (last only if editor touched, which it shouldn't be).
- The file_stack component test suite (`17/tests/file_stack/`) is the
  primary verification surface for the stack refactors. Extend it
  early and lean on it.
- Use `./commit -m"..."` not `git commit`.

## Naming

Rename `file_stack` → `source_stack` throughout. Rationale:

- It's already a stack of input sources (file or memory), not just files.
- It will gain activation-record duties (scope, parameters, eventually
  macro-locals).
- "Source" stays accurate after every planned addition.

Symbol renames:

- `file_stack.asm` → `source_stack.asm`
- `FS_*` zero-page vars → `SS_*` (e.g. `FS_P16` → `SS_P16`,
  `FS_CURR_CHAR` → `SS_CURR_CHAR`, `FS_MEM_PTR16` → `SS_MEM_PTR16`)
- `file_stack_init` → `source_stack_init`, etc.
- `FILE_STACK` (the address constant) → `SOURCE_STACK`
- `FS_FILENAME` → `SS_NAME` (it's a buffer for the source's name, not
  necessarily a filename for memory sources)
- `FS_POP_MEMORY_HOOK` → goes away in Phase 3 anyway, but is renamed in
  Phase 1 to `SS_POP_MEMORY_HOOK` for symmetry during the transition

The component test program also gets renamed (`file_stack_test.asm`,
`file_stack_tests.txt`, the test directory). Update `run_tests.py` /
test runner references.

## Abstraction goal

Today, `file_stack.asm` mixes three concerns:

1. **Stack mechanics**: bounds check, advance pointer, copy bytes in/out
   relative to `FS_P16`.
2. **Frame layout knowledge**: where the name is, where `curr_type`
   lives, which prev-data variant follows.
3. **Per-frame-type behavior**: open/close a file, manage a memory
   pointer, run the (current) `FS_POP_MEMORY_HOOK`.

The refactor target: stack mechanics generic, frame walking driven by a
size-byte at a fixed offset, per-type behavior dispatched from a small
table on `curr_type`.

Tentative unified frame layout (all sources):

```
[0]      frame_size               size in bytes of this frame
[1]      curr_type                0=file, 1=memory (extends with macro)
[2]      prev_type
[3..4]   prev_line_L / prev_line_H
[5..]    type-specific payload    (name\0 first, then the rest)
```

`frame_size` at offset 0 makes both push (set up size, fill payload)
and pop (read size, advance pointer) trivial. Frame walking from
`SS_P16` to top of stack iterates by adding `frame_size` each step.

Generic helpers:

- `ss_push_frame_of_size A` — bounds check, allocate, set offset 0.
- `ss_pop_frame` — read size, dispatch on `curr_type`, deallocate.
- `ss_walk_frames callback_addr` — call callback for each frame from
  newest to oldest with frame ptr in TABP16 and Y free.
- `ss_walk_frames_by_type type, callback_addr` — same, filtered by
  `curr_type`. (Used by `check_macro_recursion`.)

Per-type vtable (tiny — addresses in a static table indexed by type):

- `on_pop` handler: file → close; memory → restore mem ptr; macro →
  dispatch to memory-source handler for restore (since macro frames
  are an extension of memory frames).

## Phase 0 — Shore up file_stack test coverage

**Goal**: confidence that subsequent refactors don't regress
push/pop/walk behavior, and a place to anchor new behaviors.

Audit the existing 31 tests; identify gaps. Likely gaps:

- Push/pop balance assertions (does `SS_P16` return exactly to
  `SOURCE_STACK` after all sources unwind across various nestings?).
- Frame size correctness for variable-length names.
- Frame iteration in any direction (no current external API to
  inspect the stack — adding one helps later phases too).
- Out-of-memory path on push (the test program currently stubs the
  `CHECK_FOR_OUT_OF_MEMORY` macro to no-op — replace with a controlled
  failure indicator the test can observe).

Tasks (each its own commit):

- **0.1** Add a `frames` mode to the test program that prints the
  current frame chain (depth, type, name). Exercise it with simple
  cases. Failing tests first → implement mode → green.
- **0.2** Add tests that assert push/pop balance using the new mode
  combined with `info` mode (compare `SS_P16` before/after).
- **0.3** Add an OOM injection test mode: configurable
  `CHECK_FOR_OUT_OF_MEMORY` that errors via the test runner so
  exhaustion is observable. Add a test that pushes until OOM and
  verifies cleanup.
- **0.4** Add a test that exercises a memory source with a forward-
  looking "extra payload" attached to the frame, accessible via the
  `frames` mode. This is the seed for Phase 3's activation data —
  prove the test infra can see it before we use it.

Stop. Commit. Verify.

## Phase 1 — Rename file_stack → source_stack

Pure mechanical refactor. No behavior change.

Tasks:

- **1.1** Rename file `file_stack.asm` → `source_stack.asm`. Update
  `asm.asm` include line and `file_stack_test.asm` include line. Run
  full chain + tests.
- **1.2** Rename `FILE_STACK` constant → `SOURCE_STACK`. Update both
  consumers (`asm.asm`, `file_stack_test.asm`).
- **1.3** Rename `FS_*` zero-page vars → `SS_*`. Single commit, full
  sweep. Includes `FS_P16`, `FS_CURR_CHAR`, `FS_CURR_LINE16`,
  `FS_CURR_FILE`, `FS_MEM_PTR16`, `FS_SRC_TYPE`, `FS_TEMP16`.
- **1.4** Rename `FS_*` constants and routines → `SS_*` /
  `source_stack_*`. Includes `FS_FILENAME`, `FS_SRC_TYPE_FILE/MEMORY`,
  `FS_POP_MEMORY_HOOK`, `FS_ERR_NO_FILE`, `file_stack_init`,
  `file_stack_empty`, `push_file_stack`, `push_memory_source`,
  `pop_source` aliases, `file_stack_read_char`.
- **1.5** Rename test artifacts: `file_stack_test.asm`,
  `file_stack_tests.txt`, test directory, `run_tests.py` references.

Each commit: name change only, full chain green.

## Phase 2 — Refactor for abstraction (no behavior change)

Goal: split stack mechanics from frame layout from per-type behavior.
Behavior identical at every commit.

Tasks:

- **2.1** Introduce `frame_size` byte at offset 0 of every frame.
  Adjust `push_source_frame` to set it; adjust `pop_source` to read
  it; adjust internal navigation. The `name` field shifts by 1 byte.
  Run full chain + file stack tests + assembler tests.
- **2.2** Extract the generic stack mechanics (bounds check, allocate,
  deallocate by size) into `ss_alloc_frame` / `ss_free_frame`. The
  current push and pop call them.
- **2.3** Replace the inline `BNE .save_memory_state` pop dispatch
  with a tiny vtable: an array of `on_pop` handler addresses indexed
  by `curr_type`. `pop_source` reads `curr_type`, indirects through
  the table.
- **2.4** Add `ss_walk_frames` (generic) and `ss_walk_frames_by_type`
  (filtered) helpers using `frame_size`. Cover with unit tests via
  the `frames` mode added in Phase 0.
- **2.5** Remove the `FS_POP_MEMORY_HOOK` indirection in favor of the
  `on_pop` vtable. The macro pop_label_scope is still hooked, but
  through the vtable now. (Will be deleted in Phase 3.)

Each commit: full chain + file stack tests green.

## Phase 3 — Merge scope stack into source stack

Goal: remove `SCOPE_STACK`, `SCOPE_PTR16`, `SCOPE_LIMIT`, the entire
`label_scope.asm` module's stack (the routines may stay during
transition, then go).

Tasks:

- **3.1** **Test first.** Add file_stack tests that prove the merged
  layout: a memory source frame carrying scope-shaped extra payload
  (LABEL_SCOPE16, CACHED_HASH, prev_macro_frame, MACRO_ENTRY16) is
  pushed and popped correctly, with values restored. These tests fail
  until 3.2 lands.
- **3.2** Extend memory-source frames with the activation header
  fields, written by `push_memory_source`'s caller (or a new
  `push_macro_frame` that wraps it). Pop restores them. Add the
  `prev_macro_frame_L/H` chain pointer linking macro frames through
  the merged stack.
- **3.3** **Test first.** Failing test for `check_macro_recursion`
  via chain walk (the current SCOPE_STACK walk path). Then rewrite
  `check_macro_recursion` to walk the new chain and delete the
  fixed-stride SCOPE_STACK loop in `macro_expansion.asm`.
- **3.4** Migrate `expand_macro` to call the new `push_macro_frame`
  (or equivalent) instead of `push_label_scope` + `push_memory_source`
  separately. Two pushes become one.
- **3.5** Migrate `pop_label_scope` logic into the memory-source
  `on_pop` (or a new macro-frame `on_pop` if we end up with separate
  curr_type for macro vs memory — likely we will).
- **3.6** Delete `SCOPE_STACK`, `SCOPE_PTR16`, `SCOPE_DEPTH`,
  `SCOPE_LIMIT`, `SCOPE_ENTRY_SIZE`, `init_scope_stack`,
  `push_label_scope`, `pop_label_scope`. The `label_scope.asm` file
  shrinks dramatically or disappears (its remaining content — just
  the `SCOPE_DEPTH` accessor used by `read_local_label`'s "are we in
  a macro" check — moves to source_stack as `ss_in_macro_expansion`
  derived from chain head).
- **3.7** Delete the `MACRO_ENTRY16` zero-page var if it's now
  redundant with the macro frame field.
- **3.8** Reclaim the `$0400-$04FF` region. Choose a use or document
  it free.
- **3.9** Replace the `err_macro_nesting_too_deep` error with the
  out-of-memory error path (which is what the file stack already uses
  for overflow). Update tests.

Commits per task. Full chain + all tests green at each.

## Phase 4 — Macro parameter activation frames

Goal: parameters live in slots on the macro frame, not in `LHASHTAB`.

Tasks:

- **4.1** **Test first.** Add assembler tests that exercise parameter
  shadowing across nested macro calls (e.g., outer macro has `x`,
  inner has `x`, body of inner uses `x` — should resolve to inner).
  These pass under the current implementation (params shadow via
  EXPANSION_ID) and must continue to pass after migration.
- **4.2** **Test first.** Add a test that proves param hash entries
  do not leak. Today this fails (or is a no-op since we can't inspect
  the heap easily). Approach: a debug-mode assembler stat or a
  controllable heap-watermark check that asserts heap usage after a
  macro-heavy run is bounded by definition cost only. May require a
  small instrumentation hook.
- **4.3** Refactor identifier lookup to call out to a single
  `resolve_identifier` choke point that today goes straight to the
  hash. No behavior change yet. Commit.
- **4.4** Extend macro-frame layout with `arg_count` + `slots[N]`
  (3 bytes per slot: value_L, value_H, fwdref). `expand_macro`
  populates slots from `MACRO_ARG_BUF` directly into the frame
  instead of via `hash_add` / `store_hash_value`. Keep the hash path
  alive in parallel for now (write to both). Tests still green via
  hash. Commit.
- **4.5** **Test first.** Add a test that resolves a parameter via
  the frame chain when the hash entry is intentionally absent
  (instrument `expand_macro` with a flag to skip the hash write).
  Fails before lookup change.
- **4.6** Update `resolve_identifier` to walk the macro-frame chain
  innermost-first before consulting the hash. Each frame's
  `macro_def_ptr` points at the parameter name list in the macro
  definition; lookup linear-scans the names, uses the matched index
  to read the slot. **No copying of names.** Commit.
- **4.7** Flip the parallel-write switch: stop writing parameters to
  the hash. Run full chain. Macro-heavy programs still build and
  self-host. Commit.
- **4.8** Delete `LABEL_TYPE_MACRO` and the parameter-hash code path.
  Delete `MACRO_ARG_BUF` and the `$0500-$05FF` region — args go
  directly into the frame at push time, no intermediate buffer
  needed (push the frame first with args parsed in-place, or use a
  small in-frame staging area; design choice in 4.4).
- **4.9** Verify with the leak test from 4.2: macro-heavy assembly
  no longer grows the heap with per-invocation param entries.
- **4.10** Reclaim or document `$0500-$05FF`. Update memory layout
  comment in `asm.asm`.

Commits per task. Full chain + all tests green at each.

## Phase 5 — Cleanup and documentation

- **5.1** Update `CLAUDE.md` memory map section to reflect freed
  regions and the merged stack.
- **5.2** Update `BOOTSTRAP-OVERVIEW` if it references any renamed
  symbols.
- **5.3** Sweep for stale references to `EXPANSION_ID16` if all uses
  are now removed (note: macro-locals still use it; that's the
  deferred work, leave intact).
- **5.4** Re-read `macro_local_design_notes.md` and add a one-line
  note about which prerequisites are now satisfied.

## Order, dependencies, exit criteria

Phases are sequential. Within a phase, tasks should be sequential
unless explicitly independent.

Each phase ends with:

- All commits pushed (well — committed; we never push) on
  `text-editor` branch (or whatever branch we pick at start).
- `./asmtestgen.sh` green (self-hosting verified).
- `python3 run_tests.py -q` green.
- File stack test suite green.
- A one-line note in this plan's status section.

## Risks and watchouts

- **Determinism between passes** is critical for the merged stack as
  it is today. Pre-flight any change with the assertion that pass 1
  and pass 2 produce identical frame chain shapes at any given
  source position.
- **`MACRO_ARG_BUF` is currently used to capture args before
  `push_label_scope` runs**, because parsing args needs the parent's
  scope. After Phase 4, the merged push order changes: parse args in
  parent's scope, build the frame with the args already in place,
  then push the frame. Verify nested-macro arg evaluation against
  Phase 4's first test.
- **The component test program reuses `file_stack.asm`**. Every
  rename in Phase 1 must update both `asm.asm` and the test program.
  Keep them moving together commit-by-commit.
- **The `CHECK_FOR_OUT_OF_MEMORY` macro** is defined per-program. The
  test program's no-op stub hides real overflow during stack tests
  unless we add the OOM injection mode in Phase 0.

## Status (filled in as work proceeds)

- [ ] Phase 0 — test coverage shoring
- [ ] Phase 1 — rename
- [ ] Phase 2 — abstraction refactor
- [ ] Phase 3 — stack merge
- [ ] Phase 4 — parameter activation frames
- [ ] Phase 5 — cleanup
