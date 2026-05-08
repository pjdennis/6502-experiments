# Self-hosted test runner: 4-char-name mutual recursion hang

Investigation plan for a Heisenbug introduced by Phase 6 of the
macro-frame-reservation work. Captures the exact reproducer, all the
diagnostic data gathered, and concrete next steps. **The plan deliberately
errs on the side of writing things down rather than chasing a fix** -- the
canonical Python harness still passes all 500 tests, so this is a
secondary defect we can return to fresh.

## The defect in one sentence

When the self-hosted test runner (asm.asm built with both
`define:enable_test_runner` AND `define:enable_debug`) runs a macro
mutual-recursion test where both macro names are exactly **four characters
long** and bodies are **naked** (just the other macro's name, no other
instructions), the assembler emits "Error 3 ... line 2: No global label
for local" instead of the expected "Error 31: Recursive macro invocation"
and the emulator hangs (does not terminate within 200,000,000 cycles).

## Reproduction

From `assembler2/`:

```bash
# Build the self-hosted test runner with debug:
cd 17
../emulator/emulator.out ../16/out/asm_debug.out asm.asm \
    out/test_runner.out define:enable_test_runner define:enable_debug

# Drop the failing-test fixture:
cat > /tmp/_macAB.txt <<'EOF'
NAME: macAB
INPUT:
 1: * = $0200
 2:   .macro macA
 3:   macB
 4:   .endmacro
 5:   .macro macB
 6:   macA
 7:   .endmacro
 8:   macA
EXPECT_ERROR: 31
EXPECT_LINE: 1
EXPECT_MSG: Recursive macro invocation
EOF

# Run it:
cd tests/asm
../../../emulator/emulator.out ../../out/test_runner.out -q /tmp/_macAB.txt
# -> "did not terminate within 200000000 cycles"
```

## What works (not the bug)

| Variant                                                  | Behaviour                                                       |
| -------------------------------------------------------- | --------------------------------------------------------------- |
| Python harness (`run_tests.py -q --version 17`)          | All 500 tests pass, including `macro_recursive_indirect`        |
| Regular `asm_debug.out` (no test_runner) on same input   | Error 31 fires correctly in ~1.15M cycles                       |
| Self-hosted test runner WITHOUT `enable_debug`           | Same indirect test passes in ~2.8M cycles                       |
| Direct recursion `.macro x / NOP / x / .endmacro`        | Passes in ~63K cycles                                           |
| Mutual recursion, **1-char** names (`a`/`b`)             | Passes in ~1.1M cycles                                          |
| Mutual recursion, **3-char** names (`mxa`/`mxb`)         | Passes in ~1.5M cycles                                          |
| Mutual recursion, **5-char** names (`mxabc`/`mxabd`)     | Passes in ~5.1M cycles                                          |
| Mutual recursion, **6-char** names (`abcdef`/`abcdeg`)   | Passes in ~1.0M cycles                                          |
| Mutual recursion, 4-char names but bodies have `NOP`     | Finishes in ~1.4M cycles (with a line-number mismatch -- minor) |
| `asmtestgen.sh`                                          | Halts earlier on the pre-existing `readonly_file` opendir failure, never reaches the self-hosted test runner step |

So the failure is gated by the **conjunction** of:

1. `enable_test_runner` *and* `enable_debug` both defined,
2. the parent macro's body parses naked (no leading `NOP` etc. before the
   nested invocation),
3. macro names of length **exactly 4**.

## What hangs (the bug)

Same four-character-name mutual recursion test under
`define:enable_test_runner define:enable_debug`. Buffered stderr at the
point of timeout (extracted from
`out/test_runner.out.dump.bin` at offset `$0B00`, which is `TR_STDERR_BUF`):

```
Error 3 in file _tr_in.tmp at line 2: No global label for local
```

That is **error 3** (`err_no_global_for_local`, from `labels.asm:61`),
fired by `read_local_label` when `LABEL_SCOPE16 == 0`. The reported line is
2, which in the test fixture is `.macro macA` -- a directive line, not a
local-label line. So either:

- `LABEL_SCOPE16 == 0` is being checked at a moment when the parser
  shouldn't be in `read_local_label` at all, or
- `CURR_LINE16` has been clobbered before the error message is composed
  (the error is actually firing later but reports line 2).

Then the test never terminates. Whatever happens after the error message
gets buffered, control does not return cleanly to `fake_exit` ->
`tr_test_resume`.

## Heisenbug evidence

Adding ~16 bytes of pure-debug code at the very top of `expand_macro`:

```asm
expand_macro:
  PHA
  TXA
  PHA
  TYA
  PHA
  LDA #'E'
  JSR write_b
  PLA
  TAY
  PLA
  TAX
  PLA
  ...
```

makes the test pass in ~1.4M cycles. The added bytes are saved-and-restored
register state plus a single `JSR write_b` -- functionally a no-op for the
assembler logic. **The fact that pure padding fixes it is the strongest
signal that the bug is address-layout-sensitive, not logical**, and that
my Phase 6 expand_macro happens to land on the wrong side of some
boundary.

Also: building `test_runner.out` from the **bootstrap** assembler
(`16/out/asm_debug.out`, which has none of my Phase 1-8 changes) instead
of the post-Phase-6 `out/asm.out` reproduces the same hang. So the bug is
in **what asm.asm tells the bootstrap to emit**, not in any miscompilation
introduced by my asm.out's code generator.

## Size delta

Phase 5 baseline `expand_macro` (with `MACRO_NAME_SAVE`): ~20 bytes longer
than Phase 6's reserve/commit version (the save_token + restore_token
loops are gone; the `LDA SS_PAYLOAD_SIZE / JSR push_memory...` pair is
replaced with shorter `JSR ss_commit_pending_frame`). Code below
`expand_macro` in the binary therefore shifts UP by ~20 bytes between
Phase 5 and Phase 6. Adding the 16-byte debug print pushes things down by
16 bytes -- still net -4 vs. Phase 5, but enough to leave whatever's
sensitive in a different spot.

`cmp` between `out/test_runner.out` (Phase 6) and `out/test_runner_p5.out`
(Phase 5 stash, same flags): 4815 differing bytes; first diff at file
offset 1653 decimal.

## Hypotheses (ranked by likelihood)

### H1. JMP indirect crossing a page boundary (6502 quirk)

The 6502's `JMP ($xxFF)` is famously broken: it reads the high byte from
`$xx00` instead of `$(xx+1)00`. If any `JMP (zp_ptr)` or `JMP ($abs)` in
the test_runner build ends up with operand whose low byte is `$FF`,
addresses around it would silently target wrong code.

Known indirect JMPs in the codebase (from grep):
- `init.asm:170`: `JMP (JUMP_TARGET16)` -- zp word, depends on
  JUMP_TARGET16's allocated zp address. Always a fixed zp address, so
  the bug only fires if that address itself happens to be `$xxFF`.
- `tr_fields.asm:77`: `JMP (TR_PTR16)` -- zp word.
- `tr_vectors.asm:34`: `JMP (tr_action_ptr)` -- 16-bit absolute pointer
  in code section. If this ends up at `$xxFF` after Phase 6's shift, the
  high byte read would come from `$xx00`.
- `source_stack.asm:355`: `JMP (SS_TEMP16)` -- zp word (this is
  `ss_invoke`).

The most likely culprit is `tr_action_ptr` in `tr_vectors.asm` -- it's
data in the code section, so it moves when the code above it grows or
shrinks. **Action: dump the address of `tr_action_ptr` in both the
working Phase 5 build and the broken Phase 6 build; check for a low byte
of $FF**.

### H2. `tr_call_action` trampoline lands at a problematic address

`tr_vectors.asm:33-35`:

```
tr_call_action:
  JMP (tr_action_ptr)
tr_action_ptr: .word 0
```

When `tr_save_vectors` / `tr_patch_vectors` / `tr_restore_vectors` walk
the vector table, they JSR into `tr_call_action` once per vector entry.
If the address of either `tr_call_action` (the JMP itself) or
`tr_action_ptr` (its operand) shifts onto a problematic 6502 quirk,
vector patching could go wrong. Wrong patching could leave (say)
`fake_write_d` installed for `read` or some such -- and then directive
parsing in pass 1 reads garbage, falls into `read_local_label` because of
a stray `.` byte, and fires error 3.

This would explain why the bug presents as "error 3 at line 2" rather
than the expected "error 31" -- the assembler's *parse path* is wrong from
the very first directive.

**Action: log `tr_orig_vectors` after `tr_save_vectors` runs in both
builds and compare. If the saved values differ, vectors aren't being
captured/restored correctly.**

### H3. Frame size 19 collides with something

4-char macro frame size is exactly `8 + 4 + 7 = 19` bytes. With
~258-frame chains, source stack ends up around `$F000 - 18 - 258*19 =
$D2F2`. No obvious collision with heap (`MEMP16` near `$2000`+) or
test_runner buffers (`$0900-$10FF`).

But `19 = $13` is the byte stored at offset 0 of every macro frame. If
some path interprets that byte as something other than a frame size...
unlikely, but worth listing.

**Action: try other 4-char-frame-equivalent sizes by varying the payload
explicitly (would require a synthetic test that tweaks
`SS_PAYLOAD_SIZE`).**

### H4. `_tr_in.tmp` filename interaction

The captured input file in `tests/asm/_tr_in.tmp` is what the test
runner's virtual argv passes to the assembler. The string `"_tr_in.tmp"`
is 10 chars + null = 11 bytes; pushed as the first frame.

This frame size is `8 + 10 = 18` bytes. SS_P16 starts at `$F000`, lands
at `$EFEE` after the file frame.

Then 4-char macro frames start landing at `$EFEE - 19k` for `k = 1, 2,
...`. The first macA frame is at `$EFEE - 19 = $EFDB`. Inside this frame:
`MACRO_ENTRY16` (last 2 bytes of frame) at `$EFEE - 2 = $EFEC`.

For other-length names the stack-cursor sequence is different. Maybe one
of these specific addresses (`$EFEC`, `$EFD9`, `$EFC6`, ...) is special.

**Action: try with a longer or shorter `TR_INPUT_FILE` name (rename the
constant in test_runner.asm to e.g. `_tri.tmp` or `_test_runner_input.tmp`)
and see if the bug still reproduces with 4-char macros.**

### H5. `_tr_in.tmp`'s name-buffer overrun

`SS_NAME = TOKEN = $0600`. If `_tr_in.tmp` (11 bytes) is copied into
TOKEN, that's fine. But if the file frame's name capture grabbed
something past the null... unlikely since `push_file_source` uses
`copy_string_to_token` which handles the null correctly.

### H6. Pass 2 re-entry through fake_exit corruption

If `fake_exit`'s stack unwind discards the wrong number of bytes (say,
because of my Phase 6's stack discipline change), `tr_test_resume`
returns to a stale address and re-enters the assembler somewhere weird.

`fake_exit` does `LDX TR_SAVED_SP / TXS / JMP tr_test_resume`. My Phase
6 expand_macro pushes/pulls `PHA`, `TXA / PHA`, `PHA` (a couple of bytes)
during the reserve/commit dance. If the **path that fires error 3** has
something on the stack at `BRK` time that wasn't there in Phase 5, then
TR_SAVED_SP unwind discards too few bytes and tr_test_resume jumps with
junk on the stack. Subsequent `RTS` returns to junk -> infinite loop.

**Action: in the broken build, set a specific stack value at expand_macro
entry, BRK manually inside expand_macro, and confirm `TR_SAVED_SP` is
where we expect.**

This is the most plausible LOGICAL hypothesis. The pure-padding fix would
be coincidental in this case (different code shape changes which path
fires error 3, changing the stack discipline at BRK time).

### H7. CURR_LINE16 reset timing

`ss_commit_pending_frame` resets `SS_CURR_LINE16 := 0`. The original
`push_memory_source_reserve_payload` -> `push_source_frame` does the same
thing. Logically equivalent.

But: with reserve/commit, the reset happens later in absolute time
relative to the 6502 PC. If something between `JSR ss_reserve_frame` and
`JSR ss_commit_pending_frame` reads `SS_CURR_LINE16` (e.g., during arg
parse for a 0-arg macro it shouldn't), it sees parent's value rather
than 0. For 0-arg macros, no `parse_expression` calls, so this should be
moot. But check it.

The reported error line is 2, not 1 or 8. If CURR_LINE16 had drifted, the
expected drift values would be the macro invocation line (8 in main,
or 1 inside a macro body). Line 2 is suspicious.

**Action: log `CURR_LINE16` and `SS_SRC_TYPE` at the moment error 3
fires.**

### H8. `LABEL_SCOPE16` clobbering in error-path teardown

`err_no_global_for_local` checks `LABEL_SCOPE16 == 0`. But
`expand_macro`'s scope switch sets `LABEL_SCOPE16 := EXPANSION_ID16` AFTER
`scope_block` capture. With Phase 6 ordering, that switch runs BEFORE
`ss_commit_pending_frame`. So between `INC SCOPE_DEPTH` and
`ss_commit_pending_frame`, `LABEL_SCOPE16` is set, `SCOPE_DEPTH` is
incremented, but the new frame isn't yet committed -- meaning if
something errors here, the scope state is "in" the new macro but the
source stack still says we're in the parent.

Probably not the cause (scope_block writes are pure-data, no error
paths), but worth noting.

## Diagnostic ideas to try next

These are ordered roughly by "easiest first / most informative per minute"
heuristic.

### D1. Bisect with NOPs

Add `NOP NOP ... NOP` blocks of varying sizes at the top of
`macro_expansion.asm`'s `.code` section. Find the smallest pad that fixes
it and the largest pad that still breaks it. Specifically: 0, 1, 2, 4, 8,
16, 24, 32, 48, 64 byte pads. If "fix" range is contiguous, we know it's
a single threshold; if it's periodic (e.g., every 256 bytes), that
points at a page-boundary issue.

### D2. Disassemble `tr_call_action` and `tr_action_ptr` in both builds

Find their addresses in `out/test_runner.out` (working: with debug pad)
vs. broken (without). Use the assembler's symbol-emitting machinery, or
compute manually from the file offsets. Confirm whether either lands at
`$xxFF`.

### D3. Print markers along the assembler's path

The test_runner doesn't intercept `write_b` (stdout), only `write_d`
(stderr). So adding `LDA #'X' / JSR write_b` calls at strategic points
prints to the test runner's stdout -- visible after the run, not buffered
into the test's captured stderr.

Markers to add (inside `expand_macro`):
- Entry (`'E'`)
- After `check_macro_recursion` returns (`'R'`)
- After `ss_reserve_frame` (`'S'`)
- After `ss_commit_pending_frame` (`'C'`)

And inside `read_local_label` (where error 3 fires):
- Entry (`'L'`)

A working run with markers prints `ERSC ERSC L...` (read_local_label
should never fire for our test). A broken run shows the actual sequence
to the point of hang.

Caveat: adding any markers changes addresses, which may itself fix the
bug -- but the *sequence* observed before the bug fixes itself should
still be informative if we add markers minimally (one byte each via a
table-of-strings approach to keep the same total size).

### D4. Compare `tr_orig_vectors` after `tr_save_vectors`

Add a stage just after `tr_save_vectors` that prints all 8 captured
bytes (4 vectors × 2 bytes each) to stdout, then exits cleanly. Run
under both Phase 5 (working) and Phase 6 (broken) builds; compare. If
they differ, vector capture is corrupting somehow.

### D5. Examine the dump file at the moment of timeout

The emulator dumps `test_runner.out.dump.bin` (64KB full memory) when
it hits the cycle limit. Inspect:
- 6502 stack pointer (need emulator-specific extraction)
- Zero page: especially `SS_P16`, `SS_PEND_P16`, `MACRO_LOOKUP_FRAME16`,
  `MACRO_ENTRY16`, `LABEL_SCOPE16`, `CURR_LINE16`, `SCOPE_DEPTH`,
  `IN_MACRO_DEF`
- Source stack (`$F000` down): how many frames?
- Heap state (`$2000`+): macro definitions intact?

The dump at 200M cycles should reveal whether the assembler is in an
infinite loop in pass 1 (lots of macro frames piled up) or has bounced
into pass 2 somehow (file frame at top, no macro frames).

### D6. Try `enable_test_runner` only (no `enable_debug`) plus an
explicit `BEQ .no_source` check in source_stack_read_char

This tests whether the `enable_debug`-only `.no_source` jump is the
trigger. If we manually add the same check without `enable_debug`, does
the bug appear without the rest of the debug flags?

### D7. Vary `TR_INPUT_FILE` name length

Rename the constant in `test_runner.asm` from `"_tr_in.tmp"` (10 chars)
to e.g. `"_tri.tmp"` (8 chars) or `"_test_runner_in.tmp"` (19 chars).
Rebuild and rerun. If 4-char macros still hang regardless of input
file name, the bug is purely about the macro frame layout. If hang
moves to a different macro name length, the bug is about the *combined*
frame layout pattern.

### D8. Drop `MACRO_NAME_SAVE` permanently and see if the bug came in
with that drop or with the layout reorder

`git bisect` between Phase 1 (layout reorder) and Phase 6 (expand_macro
migration) using the test_runner-build-and-run-just-this-test command as
the bisect predicate. If the bisect lands on Phase 6, the trigger is
specifically the expand_macro replacement; if it lands earlier (Phase 1),
the layout reorder is the trigger and Phase 6 just exposes it differently.

I expect this to land on Phase 6 (Phase 5 baseline runs the test in 2.9M
cycles), but a clean bisect record is useful documentation either way.

### D9. Check whether the regression depends on `_tr_in.tmp` being a
real file vs. an in-memory buffer

The test runner currently writes test INPUT to `_tr_in.tmp` and the
assembler reads it via the real file syscalls. If we instead pushed the
INPUT as a memory source (with `push_memory_source` or equivalent), would
the bug still reproduce? This would isolate whether the bug requires an
actual file source as the bottom of the stack.

## Probable order of attack

1. **D1 (NOP bisect)** -- 10 min, narrows down to a byte threshold and
   tells us if it's a page boundary thing.
2. **D2 (disassemble test_runner addresses)** -- 30 min, confirms or
   rules out H1/H2.
3. **D5 (examine dump)** -- 30 min, tells us "pass 1 infinite loop" vs.
   "stack-discipline corruption" vs. "pass 2 reentry".
4. **D3 (markers along path)** -- 30 min, identifies the actual code
   path leading to error 3.
5. **D8 (bisect Phase 6)** -- 5 min, confirms the introduction point.

Steps 1-4 should be enough to pinpoint the cause. Then targeted fix.

## Constraints on any fix

- Must NOT regress any of the 500 Python-harness tests.
- Must keep release and debug self-host parity (`asm.out == asm_2.out`,
  `asm_debug.out == asm_debug_2.out`).
- Should not require adding artificial padding to expand_macro -- if a
  pad turns out to be the workaround, it should be replaced with a
  real fix once the root cause is found.
- Should preserve the reservation plan's behaviour invariants:
  `ss_reserve_frame` BEFORE arg parsing (so TOKEN is captured into the
  pending frame), `ss_commit_pending_frame` AFTER arg parsing (so
  prev_data captures parent's post-parse cursor).

## What's already been ruled out

- Bug is **NOT** in my asm.out's code generation: bootstrap-built
  test_runner reproduces it identically.
- Bug is **NOT** caused by Python-harness incompatibility: harness passes
  all 500 tests including `macro_recursive_indirect`.
- Bug is **NOT** caused by `enable_debug` alone: `asm_debug.out` (no
  test_runner) handles the test correctly.
- Bug is **NOT** caused by `enable_test_runner` alone: nodebug
  `test_runner.out` handles the test correctly.
- Bug is **NOT** specific to the macro names "macA"/"macB": "xyab"/"xyba"
  reproduces it. It's about the *length* (4 chars) and *naked-body*
  shape, not the letters.
- Bug is **NOT** about heap-vs-stack collision: 247-frame chain ends at
  `~$DD9D`, far from heap.
