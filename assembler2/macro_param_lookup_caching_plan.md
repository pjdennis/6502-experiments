# Plan: Cache slot-region pointer for macro parameter lookups

## Problem

`ss_lookup_param_slot` (`17/macro_expansion.asm:110`) is called once per
identifier resolution inside a macro body, via `resolve_identifier`
(`17/expressions.asm:48`). Each call re-derives values that are
**stable for the lifetime of the active macro frame**:

- The slot region's base address.
- The macro definition's parameter-name list pointer.
- The parameter count `N`.

Concretely, the constant prefix that runs **before the param-name walk
begins** (`macro_expansion.asm:114-152`) does:

1. Read `frame_size` at frame offset 0.
2. Compute `MACRO_ENTRY16` offset (`frame_size - 2`); read 2 bytes from
   the frame into `HTTP16`.
3. Indirect through `HTTP16` to read `N`.
4. Compute `3*N` (`ASL`/`ADC`).
5. Compute `start_of_slots = (frame_size - 7) - 3*N` (two `SBC`s).
6. Advance `HTTP16` past the count byte (16-bit `ADC`).

Roughly 80 cycles of arithmetic and indirect-loads, **paid every time**
an identifier is resolved inside a macro body — even though every
input to those steps is fixed for the duration of the frame.

The maintenance side is already efficient. `MACRO_LOOKUP_FRAME16`
points at the innermost macro frame's base and is updated O(1):

- Push: `expand_macro` writes `MACRO_LOOKUP_FRAME16 := SS_P16` after
  commit (`macro_expansion.asm:454-460`).
- Pop: `pop_label_scope_from_frame` restores it from
  `prev_macro_lookup` in the popping frame's activation payload
  (`label_scope.asm:112-118`).
- `.include` from inside a macro deliberately does **not** touch
  `MACRO_LOOKUP_FRAME16` — the file frame above the macro is invisible
  to identifier resolution (`expressions.asm:57-64`).

The fix is to extend the same maintenance pattern to the slot-region
pointer (and optionally the param-names pointer): cache them in zp,
swap on push/pop via the activation payload's scope_block, drop the
recompute from `ss_lookup_param_slot`.

## Goal

Eliminate the constant prefix in `ss_lookup_param_slot` by caching its
stable inputs in zero page, maintained alongside `MACRO_LOOKUP_FRAME16`
through the existing push/pop machinery. Per-call cost shrinks to just
the param-name walk plus the slot read.

## Design

Two new zp pointers, two new scope_block fields. Both follow the
exact pattern already established for `MACRO_LOOKUP_FRAME16` /
`prev_macro_lookup`.

### New zp state

```
MACRO_LOOKUP_SLOTS16:    .word
; Absolute address of slots[0] in the innermost macro frame, i.e.
; SS_P16 + start_of_slots_offset at the moment of expand_macro's
; commit. $0000 outside any macro (SCOPE_DEPTH==0 gates use). Updated
; in lockstep with MACRO_LOOKUP_FRAME16: written on macro push, restored
; on macro pop. Read by ss_lookup_param_slot.

MACRO_LOOKUP_PARAMS16:   .word
; Absolute address of the macro definition's first parameter name --
; equal to (the active macro's MACRO_ENTRY16) + 1 (skipping the count
; byte). $0000 outside any macro. Updated in lockstep with
; MACRO_LOOKUP_FRAME16. Read by ss_lookup_param_slot.
```

Net zp delta: +4 bytes.

### Frame payload changes

The macro frame's scope_block (today 7 bytes at `frame_size - 7..-1`)
grows by 4 bytes to 11 bytes. New layout (offsets relative to the
scope_block start = `frame_size - 11`):

```
0..1: prev LABEL_SCOPE16
2:    prev CACHED_HASH
3..4: prev MACRO_LOOKUP_FRAME16
5..6: prev MACRO_LOOKUP_SLOTS16     <-- NEW
7..8: prev MACRO_LOOKUP_PARAMS16    <-- NEW
9..10: MACRO_ENTRY16                (recursion detection;
                                     not restored on pop)
```

Net per-macro-frame delta: +4 bytes payload.

### `ss_lookup_param_slot` after the change

The constant prefix collapses. The lookup becomes:

```
ss_lookup_param_slot:
  ; Save X (callers depend on X surviving identifier lookup).
  TXA
  PHA

  ; Walk param-name list at MACRO_LOOKUP_PARAMS16. Y indexes within
  ; the current name; X counts remaining params.
  ;
  ; Maintain slot offset in TEMP: starts at 0, +3 per miss. Final
  ; slot read is (MACRO_LOOKUP_SLOTS16),Y with Y=TEMP.
  LDA MACRO_LOOKUP_PARAMS16
  STA HTTP16
  LDA MACRO_LOOKUP_PARAMS16 + 1
  STA HTTP16 + 1
  LDY #0
  LDA (HTTP16),Y                ; A = N (param count from def)
  TAX                            ; X = remaining iterations
  ; Skip past the count byte to land on param1.
  CLC
  LDA HTTP16
  ADC #$01
  STA HTTP16
  LDA HTTP16 + 1
  ADC #$00
  STA HTTP16 + 1
  LDA #0
  STA TEMP                      ; TEMP = slot offset within slots region
.lps_iter:
  ; ...as today...
.lps_match:
  ; Slot at offset TEMP within the slots region.
  LDY TEMP
  LDA (MACRO_LOOKUP_SLOTS16),Y
  STA IS_FWDREF
  INY
  LDA (MACRO_LOOKUP_SLOTS16),Y
  STA HEX16
  INY
  LDA (MACRO_LOOKUP_SLOTS16),Y
  STA HEX16 + 1
  PLA
  TAX
  CLC
  RTS
```

Cycles dropped from the prefix (rough count from current code):

- `frame_size` read + `SBC #2` + 2-byte `MACRO_ENTRY16` read (~22 cycles).
- `N` read through `HTTP16` (still happens, but now from the cached
  `MACRO_LOOKUP_PARAMS16 - 1` — actually we read N via the cached
  pointer below, so no change here).
- `3*N` and `frame_size - 7 - 3*N` and `start_of_slots` setup (~20
  cycles).
- The `PHA`/`PLA` for `frame_size` (~7 cycles).

Net per-call savings on the order of ~50 cycles. The exact figure
depends on whether we also cache `N` (see "Optional: cache N too").

### `expand_macro` after the change

After commit, where today only `MACRO_LOOKUP_FRAME16` is anchored,
also anchor the two new zp pointers. Both values are already computed
in `expand_macro`:

- `MACRO_LOOKUP_SLOTS16 := MACRO_PAYLOAD_BASE16` — already computed at
  `macro_expansion.asm:326-332` for the parse loop. After commit, that
  pointer is exactly the slot region's base. Reuse it.
- `MACRO_LOOKUP_PARAMS16 := MACRO_DEF_PTR16` — at this point in
  `expand_macro` (after `:257-263` advances past the count byte),
  `MACRO_DEF_PTR16` already points at param1. No new computation.

Inside the parse loop, `MACRO_DEF_PTR16` advances past param names
(`macro_expansion.asm:344-352`), so by the time we'd want to set
`MACRO_LOOKUP_PARAMS16`, the original pointer is gone. Two options:

1. Snapshot at commit-prep time, before parsing — keep the original
   value in a local zp word until commit.
2. Reset `MACRO_DEF_PTR16` to the param1 address at commit, since the
   subsequent body-pointer install (`CP16 MACRO_DEF_PTR16,
   SS_MEM_PTR16`) already requires `MACRO_DEF_PTR16` to be at the
   body — which it is, naturally, after the parse loop.

Option 1 is cleaner: stash the param1 address in a temporary at the
top of `expand_macro` (right after the count-byte advance), then use
it both for `MACRO_LOOKUP_PARAMS16` and as the param-walk start in
the parse loop (replacing the redundant skip-past-param-name in the
parse loop with a stride based on the cached pointer — but that's a
separate refactor, not part of this plan).

Simpler still: the cached value can just be `MACRO_ENTRY16 + 1`
computed at commit, where `MACRO_ENTRY16` is already in zp (set at
`macro_expansion.asm:218`).

### Push: write the new scope_block fields

`expand_macro`'s scope_block write loop (`macro_expansion.asm:395-...`)
adds two more INY/STA pairs, one per new field. Pattern is identical
to the existing `MACRO_LOOKUP_FRAME16` write at `:412-416`.

### Pop: restore the new zp fields

`pop_label_scope_from_frame` (`label_scope.asm:98-119`) reads two more
2-byte values from the scope_block and restores them:

```
  LDY #0
  LDA (SS_P16),Y          ; frame_size
  SEC
  SBC #11                 ; offset of activation payload start (was 7)
  TAY
  ; ...existing 5 bytes (LABEL_SCOPE16, CACHED_HASH, prev_macro_lookup)...
  INY
  LDA (SS_P16),Y
  STA MACRO_LOOKUP_SLOTS16
  INY
  LDA (SS_P16),Y
  STA MACRO_LOOKUP_SLOTS16 + 1
  INY
  LDA (SS_P16),Y
  STA MACRO_LOOKUP_PARAMS16
  INY
  LDA (SS_P16),Y
  STA MACRO_LOOKUP_PARAMS16 + 1
  DEC SCOPE_DEPTH
  RTS
```

The `SBC #7` at `label_scope.asm:102` becomes `SBC #11`. The
`ss_lookup_param_slot` constant `#7` (`macro_expansion.asm:141`)
disappears because it no longer needs to skip over the scope_block at
all — it reads slots through `MACRO_LOOKUP_SLOTS16` directly.

`check_macro_recursion` (`macro_expansion.asm:38`) is **unaffected** —
it reads `MACRO_ENTRY16` from `frame_size - 2`, and the activation
payload only grew at the *start* (the new fields go in the middle of
the scope_block, with `MACRO_ENTRY16` still last). Anchor preserved.

### Init / outside-macro state

`init_scope_state` (`label_scope.asm:75-79`) zeroes
`MACRO_LOOKUP_FRAME16` to mark "no active macro." Extend to zero
`MACRO_LOOKUP_SLOTS16` and `MACRO_LOOKUP_PARAMS16` for symmetry. They
should never be read while `SCOPE_DEPTH == 0` (the fast-path gate at
`expressions.asm:55`), but zeroing them keeps debug-time inspection
sensible.

## Optional: cache `N` too

The remaining indirect read inside `ss_lookup_param_slot`'s prefix is
`LDA (HTTP16),Y` to fetch `N` from the def. Cost: ~5 cycles, plus the
`TAX`/`STA TEMP` that follow. To eliminate, cache `N` as a 1-byte
field in the scope_block (1 zp byte + 1 payload byte per macro
frame). The savings are small relative to the byte cost. **Skip**
unless profiling shows the param-walk loop dominating.

## Pointer maintenance summary

| Operation | `MACRO_LOOKUP_FRAME16` | `MACRO_LOOKUP_SLOTS16` | `MACRO_LOOKUP_PARAMS16` |
|---|---|---|---|
| `init_scope_state` | `:= 0` | `:= 0` | `:= 0` |
| Macro push (commit in `expand_macro`) | `:= SS_P16` | `:= MACRO_PAYLOAD_BASE16` | `:= MACRO_ENTRY16 + 1` |
| Macro pop (`pop_label_scope_from_frame`) | restored from scope_block | restored from scope_block | restored from scope_block |
| `.include` from macro | unchanged | unchanged | unchanged |
| File pop | unchanged | unchanged | unchanged |

Invariant: the three pointers are either all $0000 (no active macro)
or all point into the **same** macro frame — its base, its slot
region, and its def's param-names region respectively.

## Why caching in zp + swap (vs. recompute on every call)

Lookup frequency dominates push/pop frequency. Each macro
**invocation** does exactly one push and one pop. Each macro **body**
typically resolves several to many identifiers. Caching pays off
whenever lookups-per-invocation > break-even, which for ~50-cycle
savings per lookup vs. ~30-cycle overhead per push/pop is roughly 1
lookup per macro. Real macros average far more.

The alternative — a per-frame zp cache populated lazily on first
lookup, invalidated on push/pop — adds a "have I cached this yet"
branch on every call. The eager push/pop pattern matches the existing
`MACRO_LOOKUP_FRAME16` design and shares its mechanism.

## Phasing

Per the project's small-commits TDD workflow:

1. **Add `MACRO_LOOKUP_SLOTS16` and `MACRO_LOOKUP_PARAMS16` zp words.**
   Initialize in `init_scope_state`. No reads anywhere yet. Full chain
   green. Commit.
2. **Grow the scope_block by 4 bytes.** Update the `frame_size - 7`
   anchor to `frame_size - 11` in `pop_label_scope_from_frame`,
   `ss_lookup_param_slot`'s start-of-slots computation, and any other
   site that uses `7` as the scope_block size constant. Update
   `expand_macro`'s payload_size formula (`3*N + 7` → `3*N + 11`).
   Don't yet write or read the new fields — they're zero-initialized
   reservation. Self-host verifies. Commit.
3. **Write `MACRO_LOOKUP_SLOTS16` and `MACRO_LOOKUP_PARAMS16` in
   `expand_macro`'s commit path; restore them in
   `pop_label_scope_from_frame`.** Still no reader; the values are
   maintained but unused. Easy to verify with a debug print of
   `MACRO_LOOKUP_SLOTS16` at the entry to a macro body. Full chain
   green. Commit.
4. **Switch `ss_lookup_param_slot` to use the cached pointers.** Drop
   the constant-prefix arithmetic. The 5 existing macro tests
   (parameter substitution, nested macros, recursion detection, scope
   invariants, args-at-cap) must stay green. Self-host verifies.
   Commit.
5. **Add a microbenchmark test** (optional). A macro body that
   references each of N parameters K times, asserting cycles via the
   emulator's cycle counter (if available) or wall time. Pin the
   speedup so future regressions are visible. Commit.

Each commit: build via `./asmtestgen.sh`, run `python3 run_tests.py
-q`. No editor work touches this plan.

## Test coverage

Existing tests that must stay green:

- All `macro_*` tests in `15-macros_advanced.txt` — parameter
  substitution, fwdref propagation, multiple-arg invocations.
- `macro_args_at_cap` — boundary on N.
- `macro_recursion_*` — `check_macro_recursion` shouldn't be affected
  but the regression test pins it.
- The four scope-invariant tests (Phase 4.1 of the source-stack
  unification work).
- `macro_nesting_overflow` — frame size grew by 4 bytes, so the OOM
  boundary shifts slightly.

New tests to add:

- **Identical lookup result before/after.** Source-level: a macro that
  uses each of its parameters in arithmetic. Asserts the emitted
  bytes byte-for-byte against the pre-refactor baseline.
- **Lookup pointers correctly restored on nested macro pop.** A
  macro `OUTER` that invokes `INNER` mid-body, then references one of
  its own parameters after `INNER` returns. The post-`INNER`
  reference must resolve to `OUTER`'s slot, which means
  `MACRO_LOOKUP_SLOTS16` and `MACRO_LOOKUP_PARAMS16` were both
  restored from `OUTER`'s scope_block on `INNER`'s pop.
- **`.include` from macro doesn't disturb the cached pointers.** A
  macro body that `.include`s a file and the included file references
  one of the macro's parameters. The reference must resolve through
  the cached pointers (both must survive the file push/pop). This
  pins down the same invariant the existing `MACRO_LOOKUP_FRAME16`
  contract has — extended to the new pointers.
- **Outside-any-macro state is sane.** An identifier lookup at file
  top-level (`SCOPE_DEPTH == 0`) takes the global path and never
  reads `MACRO_LOOKUP_SLOTS16` / `_PARAMS16`. Pin via the
  `SCOPE_DEPTH` gate.

## Memory map impact

Net memory: +4 bytes zp, +4 bytes per active macro frame.

Zero page is not currently tight (see the reservation plan's analysis
of the same point). With both this plan and the reservation plan
applied, total zp delta is `+3 (reservation) + 4 (this) - 1 (if
Option A in the reservation plan eliminates SS_PEND_PREV_OFF) = +6
bytes`. Still comfortably below any constraint.

The +4 bytes per macro frame is amortized — most compiles have a
small handful of macro frames in flight at once. Worst case
`macro_args_at_cap`-style stacking still fits in the source stack
budget (see step 2's `frame_size` update).

## Risks and watchouts

- **Pointer-triple invariant.** The three pointers must move
  together. Centralize the maintenance in `expand_macro`'s commit
  path and `pop_label_scope_from_frame` — no other callers should
  touch them. Worth an `enable_debug` assertion at the entry of
  `ss_lookup_param_slot` that all three are non-zero (or all zero).
- **`MACRO_PAYLOAD_BASE16` lifetime.** Today it's a scratch zp word
  used only during `expand_macro`. After this change, the value it
  holds at commit time is the same as `MACRO_LOOKUP_SLOTS16` — but
  that's coincidence, not contract. Don't be tempted to alias them
  permanently; `MACRO_PAYLOAD_BASE16` resets/reuses across nested
  expansions, while `MACRO_LOOKUP_SLOTS16` follows the macro frame's
  lifetime.
- **`init_scope_state` symmetry.** Forgetting to zero
  `MACRO_LOOKUP_SLOTS16` and `MACRO_LOOKUP_PARAMS16` at init won't
  cause a bug today (the `SCOPE_DEPTH == 0` gate prevents reads), but
  it clutters debug inspection and creates a latent trap if the gate
  ever weakens.
- **Step ordering during phasing.** Step 2 (scope_block size growth)
  must precede step 3 (writing new fields), or the new fields would
  land outside the reserved space and corrupt the slot region or
  `MACRO_ENTRY16`. The phasing above is the correct order; resist
  reordering for "convenience."
- **Optional `N` cache temptation.** Resist unless profiling
  justifies it. `N` is one indirect load per call — small, and
  `MACRO_LOOKUP_PARAMS16 - 1` is a viable derivation if needed
  later (read N via a separate zp word `MACRO_LOOKUP_DEF16` =
  `MACRO_LOOKUP_PARAMS16 - 1`, which is also stable for the frame's
  lifetime and would make `check_macro_recursion`'s
  `MACRO_ENTRY16`-from-frame read avoidable too — but again, separate
  follow-up).

## Relationship to the reserve/commit plan

This plan is **independent** of the reserve/commit reservation plan
(`text-editor` branch's `macro_frame_reservation_plan.md`). Either
can land first; both can land together. Interactions:

- Reservation plan grows scope_block writes inside `expand_macro`'s
  commit-time path; this plan adds two more writes there. Both fit
  the existing pattern.
- Reservation plan's "Option A" (fixed 2-byte prev_data slot, name at
  offset 7) doesn't touch the activation payload at all — orthogonal.
- The OOM check coordinates correctly: `expand_macro`'s
  `check_source_frame_room` accounts for `payload_size = 3*N + 11`
  (post-this-plan); the reservation plan's `ss_reserve_frame` reads
  the same `SS_PAYLOAD_SIZE` set by `expand_macro`. No conflict.

Land order recommendation: reservation plan first (it removes
`MACRO_NAME_SAVE`, the bigger memory win), this plan second (it's a
performance refinement that doesn't compete for any shared resource).
