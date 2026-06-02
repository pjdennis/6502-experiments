# Session Resume Notes -- Prog8 bootstrap project

This file is a session-handoff note. It captures the state of the
project after the v2..v9 tinyp8 growth sessions so a fresh
conversation can pick up productively without re-reading prior
chat history. Update it (or replace it wholesale) at the end of
each session.

For the strategic plan (goal, phase map, critical path), see
[`PLAN.md`](./PLAN.md). For per-feature language-surface details,
see [`README.md`](./README.md).

Branch: `claude/prog8-bootstrap-continue-6Pzo0` (continuing the
`claude/review-wendy2-plan-MOfnA` work). Push as you go; the remote
is the source of truth across sessions.

> **Environment note (web sessions):** `vasm6502_oldstyle` is not
> preinstalled and `sun.hasenbraten.de` is blocked by the network
> policy, so the tinyp8 e2e/self-host/v2 tests *skip* unless vasm is
> on PATH. The host p8c suite (76 tests) runs without it. To build
> vasm in a session (github.com is reachable):
>
>     git clone --depth 1 https://github.com/ArchUsr64/vasm.git /tmp/vasm
>     make -C /tmp/vasm CPU=6502 SYNTAX=oldstyle
>     cp /tmp/vasm/vasm6502_oldstyle /usr/local/bin/
>
> That's a faithful upstream vasm 1.9f / 6502 backend 0.12 / oldstyle
> 0.19a; with it on PATH all 22 tinyp8 cases run.

---

## P7-M5 status + THE CAPACITY WALL (read this first)

The on-target compiler **p1.p8 now has the whole core**: all byte+word
expressions, all control flow (if/else/while/repeat/for/when/break/continue),
**subs** (void / return values / params / locals / single- and multi-arg
calls), **builtins** (lsb/msb/peek/poke/mkword), **inline %asm**, and
**asmsub** declarations + call ABI. Each was added byte-identical to `p8c -o`
(49 p1 cases). That is essentially everything p1.p8 itself is *written with*
EXCEPT: arrays (decl + storage trailer + variable indexing + len/sizeof),
`const`, `enum`, `struct`, `defer`, and the `%target/%address/%output`
directive surface beyond the nmos prologue.

**THE BLOCKER (the $F006 ceiling) IS NOW SUBSTANTIALLY RELIEVED -- pool +
port relocation DONE.** The read-only string pool no longer sits in the low
$0200..$F006 window: p8c (nmos) and p1's emit_string_pool both emit `.org
$F0C0` before the pool, parking it in the freed high region. To make room for
it there, the emulator's high I/O ports moved from the $FE80 block up to $FFE0
(stubs.h), and the command-line argv strings moved from `stubs_end` (~$F0A3)
to a dedicated ARGV_BASE=$FE00 window (emulator.c). NEW HIGH-MEMORY MAP:
  * $F006..$F0B0  stub jmp table + routines (unchanged)
  * $F0C0..$FE00  string pool (read-only; p1.bin's own pool now $F0C0..$FC06)
  * $FE00..$FFE0  argv strings (ARGV_BASE..ARGV_TOP; programs fetch via argv stub)
  * $FFE0..$FFFB  high I/O ports (argc/argv/read/write/openout/con/term/serial/eof/opendir)
  * $FFFC..$FFFF  reset vector
The move is transparent: no program references the $FE80/$FFE0 ports directly
(they go through the $F006 jmp table -> stub routines), so only stubs.h +
emulator.c (the two arg-writing sites + the port interception, all via the
#defines) changed. VERIFIED non-breaking across the WHOLE repo: asm bootstrap
self-host chain (442+30, self-assembly OK), all wendy2c goldens, p1 49,
prog8 106, tinyp8 22.

MEASURED HEADROOM AT THIS HEAD (p8c p1/p1.p8):
  * code+arena top **$E442** -> **~3.0 KB free** below the $F006 stub floor
    (was ~150 B). This is the budget the self-host arena growth draws on.
  * pool top **$FC06** -> ~506 B free below the $FE00 argv window. Dedup keeps
    the pool small enough to fit; if it ever outgrows $F0C0..$FE00, raise
    ARGV_BASE/ports further (argv only needs ~100 B for short self-host paths).

REMAINING CAPACITY MATH FOR FULL SELF-HOST -- **REVISED (the ~2 KB estimate
was wrong; the real gap is ~15 KB).** Measured/counted at this HEAD:
  * The low window is now $0200..$F006 (~60 KB) for code+arenas ONLY (pool is
    out). p1.bin code alone is ~58 KB (corpus arenas shrunk to ~1.4 KB; top
    $ED93). To SELF-HOST, p1 must hold, IN THAT SAME LOW WINDOW, arenas sized
    for p1.p8 itself. Crucially, p1 resets only the NODE/cons arenas per-sub
    (line ~3311: "reset_nodes ... keep the persistent ident/str pools"); the
    ident pool, string pool, and symbol table are PROGRAM-WIDE and cannot be
    reset (the sym table stores interned ident IDs that index the persistent
    ident pool). Counted in p1.p8:
      - distinct identifier name bytes (ident_pool): ~4-6 KB (the raw grep is
        ~12 KB incl. in-string mnemonics; genuine interned idents ~300-500).
      - ident_off/ident_len: ~400 entries x 2 x 2 = ~1.6 KB.
      - string pool (parser side): ~2.9 KB (same text as the output pool).
      - symbol table: 254 module syms (consts+vars+arrays) + ~510 params/locals.
        If params/locals accumulate (sym_count is NOT rolled back per sub) that
        is ~760 entries x ~12 B = ~9 KB; even reset-per-sub it is ~3 KB.
      - node + cons (per-sub, biggest sub ~470 nodes): ~4.7 KB + ~2 KB.
    TOTAL self-host arenas ~= 15-20 KB. code ~58 KB + arenas ~15-20 KB
    ~= 73-78 KB vs the 60 KB low window. **~13-18 KB OVER.**
  * **This is a FUNDAMENTAL constraint, not an incremental gap.** The pool
    relocation (~3 KB) and arena right-sizing (~0.3 KB) and the exhausted o_*
    helper compaction (~0.2 KB) are drops in a ~15 KB bucket. The easy levers
    are spent. Closing ~15 KB in a SINGLE binary needs an architectural change.

  ### >>> THE ANSWER: a MULTI-PASS PIPELINE (this resolves the feasibility AND
  ### the upstream-comparability question -- no banking, ordinary Prog8). <<<
    The monolith doesn't fit because the front-end AND back-end code are
    resident TOGETHER (~55 KB) plus all arenas. The repo's OWN proof-of-concept
    is the asm00->asm17 bootstrap chain: a pipeline of separate <=64 KB binaries.
    Do the same for p1. MEASURED split point in p1.bin (vasm listing):
      - front-end (lexer + parser, from stmt.p8): $0203..~$598A  ~= 22 KB
      - back-end  (codegen, from build_p1.py):     ~$598A..$D983 ~= 33 KB
    Two passes, each fits the 60 KB window:
      * PASS 1 (parse + serialize AST to a file): ~22 KB code + per-sub node
        arena (~5 KB) + ident/str pools (~8 KB) ~= 35 KB.  **ALREADY EXISTS as
        stmt.p8** -- its parser handles EVERY construct p1.p8 uses (arrays,
        const, struct, enum, defer, when; verified by p1.tests.test_stmt), and
        it already has the `(program ...)` AST serializer that p1 replaced with
        codegen. So pass 1 is essentially done.
      * PASS 2 (read serialized AST -> codegen .s): a small S-expression reader
        (~5 KB, replaces the 22 KB Prog8 front-end) + the codegen back-end
        (~33 KB) + symbol table + pools (~22 KB) ~= 55-60 KB. Tight but fits;
        split into 2 codegen sub-passes if it doesn't.
    The fixpoint becomes: pipeline(p1.p8) == p8c(p1.p8) (same .s output). The
    pipeline self-hosts; internal binary count doesn't affect the .s compare.
    Pass-to-pass data lives in FILES (via the I/O shim p1.p8 already uses), so
    program-wide arenas need not be resident in any single pass.

    FALLBACKS if the pipeline is undesired: (A) bank-switching -- but banking
    constructs in p1.p8 source diverge from upstream -> violates comparability;
    (C) shrink p1.p8 -- changes the target; (D) bounded self-host now. The
    pipeline is strictly better than A/C/D for the stated goal.

    REMAINING WORK for the pipeline (the focused multi-session task):
      1. Define the intermediate format. Cheapest: REUSE stmt.p8's existing
         `(program ...)` serialization as pass-1 output (no new code in pass 1).
      2. Build pass 2 = an S-expr reader that repopulates node_*/ident/str/sub
         arrays from the serialized AST (streaming sub-by-sub where possible),
         then runs the EXISTING codegen back-end (build_p1.py) unchanged.
      3. Rebuild the symbol table in pass 2 from the AST (build_symbols already
         does this from parsed decls; feed it the deserialized decls).
      4. Harness: p1 = run pass-1 binary then pass-2 binary; diff .s vs p8c.
         Verify byte-identical on the existing corpus FIRST (small ASTs), then
         scale to p1.p8 itself.
    Each step is corpus-verifiable. The earlier "spill the sym table to a file"
    idea is SUBSUMED by this -- the file-based pass boundary IS the spill, but
    clean (whole AST), not ad-hoc.

    VALIDATED THIS SESSION (measurements, not estimates):
      * Built stmt.p8 directly (pass-1 candidate): code+arena top **$C52E,
        ~11 KB UNDER $F006** -- vs the monolith p1.bin's ~80-390 B. The split
        gives pass 1 huge headroom, confirming the architecture fits.
      * stmt.p8 ALREADY STREAMS (2-token lexer window; ident/str pools + node
        arena reset per top-level unit -- see its lines 175/185/1828/2459). So
        pass 1 does NOT hold the whole program resident; it is the right shape.
      * p8c --dump-ast on p1.p8 = the oracle intermediate (382 KB of
        `(program ...)` text); this is the exact format pass 1 must emit and
        pass 2 must read.
    OPEN (the concrete FIRST implementation task for next session):
      * stmt.bin does NOT yet serialize p1.p8 -- it produced 0 bytes and ran to
        the cycle cap. Cause not yet isolated: could be (a) a sub bigger than
        stmt.p8's 640-node arena (growing node/cons to 1024 did NOT fix it, and
        still fit at $DA2E ~5.5 KB under $F006 -- so likely NOT just node size),
        (b) an ident/str pool overflow on some unit, (c) the latent EOF
        infinite-loop if p1.p8 lacks a trailing newline (see the EOF note
        elsewhere in this file), or (d) buffered output hiding partial progress.
        NEXT: bisect -- run stmt.bin on progressively larger prefixes of p1.p8
        (or individual big subs) to find the first unit it hangs on; check
        whether output is per-unit-flushed or end-buffered; confirm p1.p8 ends
        in a newline. Getting stmt.bin to emit p1.p8's AST byte-identically to
        `p8c --dump-ast` is pipeline MILESTONE 1 (pass 1 proven on the real
        self-host input). Then build pass 2 (S-expr reader + existing codegen).
    MILESTONE 1 PROGRESS (this session -- pass 1 now RUNS on p1.p8):
      * ROOT CAUSE of the earlier hang: stmt.p8's reset_nodes (per-unit) resets
        ONLY nodes+cons; the ident/str POOLS persist program-wide ("their total
        fits; idents dedupe" -- true for tinyp8's 34 subs, FALSE for p1.p8's
        210). p1.p8 has ~600-1700 distinct identifiers -> the 1024-byte
        ident_pool + 320-entry ident_off/len OVERFLOW -> corruption.
      * FIX APPLIED (committed): grew stmt.p8's pools -- ident_pool 1024->6144,
        ident_off/len 320->768, str_pool 1024->3072, str_off/len 160->256.
        stmt.bin now $E9AE (1.6 KB under $F006). All front-end tests green
        (test_stmt/expr/lexer, 27). VALIDATED: stmt.bin is byte-IDENTICAL to
        `p8c --dump-ast` on tinyp8.p8 (1289 lines, 34 subs) -- pass 1 is correct
        on a real medium program.
      * STATE on p1.p8: stmt.bin now runs to completion (1.53 BILLION cycles --
        it was the 200 M cycle CAP, not a hang; use
        `emulator stmt.bin --cycle-cap 3000000000 p1.p8 out` -- flags go right
        AFTER the code file, before the positional in/out args) and writes
        475787 B, but DIFFERS from the 382069 B oracle at byte 26361:
        p1 `(id target)` vs oracle `(id name_len)`. The +93 KB + the wrong-ident
        symptom = ident_off/pool STILL too small (768 < p1.p8's true unique
        count) -> interning corruption past the overflow point.
    MILESTONE 1 REMAINING (next session, tractable arena-balancing in the SMALL
    pass): size pass-1's arenas to p1.p8's EXACT needs within 60 KB --
      - measure p1.p8's true unique interned ident count + total ident bytes and
        biggest-sub node count (instrument stmt.p8 or count precisely);
      - set ident_off/len + ident_pool to that (likely ~1000 entries / ~8 KB)
        and str pools to ~p1.p8's strings, while SHRINKING node/cons from 640 to
        the biggest-sub peak to make room (node/cons is per-unit, so it only
        needs one sub's worth). stmt.bin's budget is ~60 KB; pass-1 = front-end
        +serializer code (~30 KB) + node/cons (~6-8 KB) + pools (~12-15 KB) ~=
        50-53 KB, so it FITS with correct sizing.
      - re-run vs `p8c --dump-ast` on p1.p8 until BYTE-IDENTICAL = Milestone 1.
    THEN Milestone 2: pass 2 = S-expr reader (parse the `(program ...)` text back
    into node_*/sym arrays) + the EXISTING codegen back-end; diff .s vs p8c.
    (`/tmp/stmt.p8.bak` is a scratch copy of the pre-growth stmt.p8.)

  ### CONCRETE STAGED PLAN for option B (recommended -- stays in 64 KB AND
  ### keeps p1.p8 upstream-compatible; no emulator change). The single biggest
  ### resident arena is the symbol table (~9 KB at self-host: ~250 module syms
  ### + ~510 params/locals, all held at once). KEY INSIGHT: the params/locals
  ### are held resident only so a CALL can resolve the callee's param slot
  ### addresses. Replace that with a compact per-sub SIGNATURE table so
  ### params/locals become per-sub TRANSIENT (registered at codegen, rolled
  ### back after). This cuts the sym table ~9 KB -> ~4 KB (~5 KB reclaimed),
  ### and the same pattern then applies to ident/str pools.
  ###   Stage 1 (CORRECTNESS, corpus-verifiable, NO self-host run needed):
  ###     introduce sub_param_base[sub] + a per-sub param-type list, computed
  ###     in the existing source-order registration sweep (line ~3196). Make
  ###     codegen_call resolve callee param slots from THIS table instead of
  ###     find_sym over the global sym entries. Corpus M5_PARAM/M5_SUB calls
  ###     must stay byte-identical -> proves call resolution is correct.
  ###   Stage 2: stop registering params/locals up-front; register the CURRENT
  ###     sub's (at their precomputed base addresses, source order) at the top
  ###     of its codegen and roll sym_count back after. Module syms + consts +
  ###     arrays stay resident. Corpus (multi-sub, params, locals, calls) must
  ###     stay byte-identical -> proves transient resolution is correct.
  ###   Stage 3: shrink the now-much-smaller sym_* arrays for the corpus
  ###     (reclaim margin) AND raise them toward self-host sizes; re-attempt
  ###     the array STORE + the aptr path + remaining features in the reclaimed
  ###     room. Repeat measure-build-test each step against the $F006 guard.
  ### CATCH-22 to plan around: stages add code while corpus margin is ~390 B.
  ### Sequence so each stage's NET (reclaim from rollback - new code) is >= 0:
  ### land Stage 1+2 together (the rollback reclaim should offset the signature
  ### table + pre-pass), verified only by corpus byte-identity (the self-host
  ### arena BENEFIT is not directly runnable until the whole gap closes, but
  ### the corpus proves CORRECTNESS, which is what de-risks it).
  ### INTERACTING FEATURE (also required for self-host, found while planning):
  ### ZP OVERFLOW. p1 currently assumes every scalar/param/local gets a ZP slot
  ### ($40..$FF = ~192 B). p1.p8 has ~250 module syms + ~510 params/locals --
  ### far more than 192 ZP bytes -- so p1 MUST implement p8c's "overflow ZP into
  ### main-memory memvars" (a scalar/param/local whose address is None becomes a
  ### labeled `.byte` reservation, referenced absolute; see p8c generate()'s
  ### "scalars overflowed from ZP into main memory" section + sema's zp_next cap
  ### ZP_VAR_TOP). The per-sub signature table (Stage 1) must therefore store
  ### each param's ACTUAL address (ZP or memvar label), not base+offset. Do ZP
  ### overflow FIRST (corpus-testable: force a program past ZP_VAR_TOP), then the
  ### signature-table/transient-registration streaming. These two together are
  ### the real path to self-host; both are corpus-verifiable for correctness.
  ### ATTEMPTED ZP overflow this session: implemented build_symbols overflow
  ### marking (sentinel addr $FFFF, no zp_next bump) + emit_memvars trailer
  ### (`; ---- scalars overflowed from ZP into main memory ----`, p8v_<name>: /
  ### .byte 0[, 0], between emit_arrays and emit_string_pool) + emit_zp_bindings
  ### skip. It is CORRECT in shape but cost ~820 B -> p1.bin $F1B3, ~430 B OVER
  ### $F006. Reverted. DOUBLE catch-22: not only does the code not fit the ~390 B
  ### margin, but a TEST that forces overflow needs ~96+ scalars, which forces
  ### the sym_* arrays from [40] up to ~[100] (+~780 B) -- so even the test
  ### doesn't fit. CONCLUSION: the 60 KB window is full; NO further p1 feature
  ### or streaming-infra increment fits without first executing option A (bank
  ### switching / >64 KB) or a codegen-size reduction large enough to reopen a
  ### multi-KB margin. The interlock (every increment needs margin that only an
  ### architectural change provides) is now proven from three directions
  ### (array store, ZP overflow, streaming infra).
  * RULED-OUT incremental levers (measured, so the next session doesn't chase
    them): (i) o_* / source-idiom factoring -- only ~30 raw emits left, tens of
    bytes. (ii) a register calling convention -- p1.p8 has ~948 helper call
    sites but only ~338 are single-arg; arg-in-A saves ~2 B/site gross (~700 B)
    minus per-sub callee prologue (~134 subs) -> ~300 B NET. (iii) arena
    right-sizing -- already done (~270 B); node/cons can't drop below the
    corpus peak (~50 nodes). NONE of these approach 15 KB. The gap is the SUM
    of inherent feature-logic code (~58 KB) + inherent program-wide arenas
    (~15-20 KB); only options A-D move it. RECOMMENDED next major effort:
    decide A vs B vs D, then commit to it -- piecemeal feature/compaction work
    on the current model cannot reach the fixpoint.

## Session log (this branch, newest first)
  * ubyte-array element READ (fast `,y` path); margin now ~80 B.
  * Quantified the ~15 KB self-host capacity gap (this is the headline finding).
  * Arena right-sizing (~270 B reclaimed).
  * Array declaration + storage trailer (byte-identical).
  * const support (byte-identical; folds where p8c folds).
  * Pool + I/O-port relocation -- the major capacity unblock (~3 KB freed,
    transparent across the whole repo).
  * String-pool dedup; string-pool label ordering fix (both byte-identical).

Paths forward:
  1. A bigger codegen-compaction lever in p8c (all SAFE, p1.p8-source-free,
     verified by the corpus): e.g. detect consecutive `if v == const`
     statements over the same var and emit a shared-compare chain (eval v once)
     -- the lexer/parser are full of these; estimate ~1-2 KB. Or a more compact
     uword-array-index path (the arena accesses dominate p1.p8).
  2. Right-size the arenas: profile p1.p8's actual peak node/cons/pool usage
     (instrument p8c or count) and size each arena to that + margin, rather
     than the worst-case estimate. Could save 1-2 KB vs a generous guess.
  3. Implement the remaining self-host features in p1 -- each byte-identical to
     p8c -o via the corpus, each watching the (now relieved) ceilings.
     STILL MISSING IN p1 (codegen back-end): **arrays** (decl + storage trailer
     + ND_INDEX read/store + len/sizeof; 66 array decls + pervasive indexing in
     p1.p8 -- THE BIG ONE), **defer** (26 uses), **struct** (3), **enum** (1),
     the `%target/%address/%output` directive surface beyond the nmos prologue,
     and **multi-arg call reentrancy**. (`const` and `when` are DONE.)

**DONE -- const support in p1** (commit e79f229). `const ubyte/byte/uword
NAME = <int>` -> storage-free symbol (sym_is_const / sym_cval); folds the
literal at every site p8c folds: byte-leaf load, word-leaf load (ubyte const
widened), and comparison conditions via the SPILL path (p8c's
_cmp_leaf_operand returns None for a const, so p1's new is_cmp_leaf_rhs
excludes consts -> spill -> fold during full byte eval). emit_zp_bindings
skips consts. NOT folded (matching p8c, which emits the undefined mangled name
there): const in arithmetic operands / for-bounds -- p1.p8 avoids those. Corpus
guard: test_const_programs. Cost ~1.2 KB code (code+arena top $E442 -> $E91F,
~1.7 KB under $F006). NOTE: 133 consts will become 133 sym-table entries at
self-host -> the sym_* arrays (currently [64]) must grow to ~256+ then, ~1-2 KB
more arena. The freed ~3 KB (pool relocation) covers it but watch the ceiling.

**DONE -- array declaration + storage trailer** (this commit). p1 now
registers `ubyte[N] / uword[N] name` arrays (sym_arr_size, element type in
sym_type, mangle `p8a_<name>`), emits the `; ---- arrays ----` trailer (between
the mul helper and the string pool: `p8a_<name>:` + `.byte 0,...` of count*esize
zeros, source order), and skips arrays/consts in emit_zp_bindings. Corpus guard:
test_array_decl_programs. Cost ~1.4 KB code -> **code+arena top $EE9F, only
359 B under $F006**.

**BLOCKED -- array INDEXING (ND_INDEX read/store).** Implemented and verified
byte-identical (ubyte-array fast `,y` path: const index -> `lda arr+N`; byte-var
index -> `lda idx / tay / lda arr,y`; store mirrors p8c's eval-rhs/sta tmp0/
tay/sta arr,y) BUT it pushed p1.bin's code top to ~$F395, ~900 B OVER $F006 ->
section overlap. REVERTED to keep green. The full indexing port also needs the
`__p8c_aptr` path (uword arrays -- which p1.p8 uses pervasively -- + >256 elems
+ uword/complex indices, the latter needing work-stack tasks not re-entrant
codegen_byte_expr) and len/sizeof. THE CRITICAL PATH IS NOW HEADROOM, not more
features: with 359 B of margin, the NEXT thing must be a low-window reclamation:
  * p8c codegen-compaction lever #1 (shared-compare chain for consecutive
    `if v == const` over one var -- p1.p8's lexer/classify/node-dispatch are
    full of these; est. 1-2 KB; coordinated p8c + p1 change, corpus-verified), or
  * arena right-sizing #2 (the node/ident/str/cons arenas are corpus-tuned but
    ident_pool/str_pool 224 each may be over-provisioned; est. only ~300-400 B
    -- not enough alone), or
  * structurally rewriting p1.p8's if-chains as `when` (upstream-compatible;
    `when` codegen evals once -> more compact; big manual refactor).
The reverted indexing code (read in emit_byte_leaf_load, codegen_assign_index +
its dispatch) is in git history at the commit BEFORE this one's parent if needed
to re-apply once headroom exists.

**DONE -- string-literal pool ordering across subs.** p8c used to assign
`p8c_str_N` labels during the sema walk (source order); p1 interns them during
its single codegen pass (main emitted first). A non-main sub declaring a string
before main therefore got divergent label numbers. FIXED by moving p8c's label
assignment out of sema into codegen `_str_label()` (lazy, on first reference,
main-first emission order) -- p1 needs no new code, no $F006 cost. Regression
guards: `test_codegen.test_string_labels_are_main_first`, the new p1 corpus
case (strings in subs before main).

**DONE (but ~size-neutral now) -- string-pool dedup.** Identical string content
now interns to one pool label in BOTH compilers (p8c `_str_label` value-dedup;
p1 `intern_str_label` + `str_sid_equal` byte-compare). p1.p8's own pool: 242
literals -> 172 labels, pool 3493 -> 2873 B. BUT the intern/compare subs add
~650 B of low-window code to p1.bin, so the pool-top ceiling barely moved
($EF6A -> $EF6D). HONEST ACCOUNTING: dedup trades ~620 B of (post-relocation
SLACK) high-region pool for ~650 B of (post-relocation BINDING) low-window code,
so it is net-neutral pre-relocation and slightly NEGATIVE for the binding
low-window budget post-relocation. KEPT anyway because (a) it is the obviously
correct behavior, (b) it is insurance that the self-host pool stays within the
~3.8 KB high region after the port relocation (undeduped it would be ~3.5 KB,
deduped ~2.9 KB), and (c) the 650 B code cost is recoverable via the low-window
compaction levers below. Corpus guard: M3_STR dedup case ("x"/"y"/"z" repeated).

## Size optimization: compact codegen in p8c (Phase 7 sub-goal)

p1.bin's hard ceiling is **$F006** (emulator stubs). To free space for the
remaining milestones, the strategy is to make **p8c emit more compact 6502**
(p1.bin IS p8c's output), with NO p1.p8 source change -- so it stays
upstream-Prog8-compatible by construction, and is safe for the p1-vs-oracle
tests as long as the changed pattern isn't in p1's small corpus (scalars /
arith / single-comparison conditions) or p1's port is co-updated.

* **Opt: single-arg calls** store the arg straight into the param slot (no
  push/pop) -- the common case (out_text), freed ~2.0 KB. **Opt 1/2** (and/or/
  not short-circuit; constant array index) freed ~2.7 KB. (Opt 3 leaf
  comparison in conditions is in; Opt 3b in VALUE context was reverted -- p1's
  sources have ~no value-context comparisons.) The o_* single-instruction emit
  helpers collapse ~110 `out_text("  x")+o_nl()` sites into 3-byte jsrs.

* **Opt 1 DONE -- short-circuit `and`/`or`/`not` in if/while conditions.**
  `_emit_bool_test_branch_if_false` -> `_emit_cond_branch(cond, target,
  jump_if_true)`: and/or/not recurse and branch per operand instead of
  materializing the whole boolean to 0/1 then testing it (a 4-`and` keyword
  check went 67 -> 42 instructions). The single-comparison + generic paths are
  byte-IDENTICAL to before (p1 ports/tests those); only the compound-condition
  path changed (p1's corpus has none). Behaviorally verified (and/or/not + nested
  + while-and). Freed ~2.2 KB: p1.bin 59379 -> 57195 B, pool top $E9DE -> $E156,
  margin ~1.5 KB -> ~3.8 KB. All host (105) + tinyp8 (22) + p1 (40) tests green.
* **Opt 2 DONE -- constant array index.** `arr[const]` (fast ubyte-array path,
  read + write) now emits an absolute `lda arr+const` / `sta arr+const` instead
  of `lda #const / tay / lda arr,y` (read) or the tmp0/tay dance (write) -- no Y
  setup. p1's corpus has no arrays (oracle unchanged); host array e2e + snapshot
  tests still pass; p1 compiling 40 programs byte-identically exercises
  classify_name's many constant indexes. Freed another ~0.5 KB: p1.bin
  57195 -> 56687 B, pool top $E156 -> $DF5A, margin ~3.8 KB -> ~4.3 KB.
* **Opt 3 DONE -- leaf-operand comparison in conditions.** `_emit_cmp_cond`
  (and p1's `emit_cond_branch_if_false`) now skip the tmp0/tmp1 spill when the
  rhs is a leaf (literal / var): just `<eval lhs> ; cmp #imm | cmp p8v_x` (or
  `sec / sbc operand` for signed ordering). A 4-`and` keyword check dropped
  42 -> 18 instructions. This IS in p1's tested path (single-comparison
  conditions), so it was a coordinated p8c + p1 change, verified byte-identical
  by the M4 corpus; the `counter` snapshot golden was regenerated (the only
  exact-output test that uses an `if` comparison). Freed ~2.5 KB: p1.bin pool
  top $EE8E -> $E49B, margin ~376 B -> ~2.9 KB.
* Further levers if needed: leaf comparison in VALUE context (`a = x<y`,
  `_emit_cmp_into_a`; co-update p1's `emit_cmp_tail`), table-driving
  classify_name (p1.p8 source change).

---

## Standing constraint: p1.p8 must compile under upstream Prog8

The finished `p1.p8` must be **compilable by the upstream Java/Kotlin Prog8
compiler** (its OUTPUT need not match -- only that upstream accepts the
source). So `p1.p8` must stay in the **intersection** of our p8c and upstream
Prog8; p8c may remain a superset. Biggest gap is the platform I/O shim
(`asmsub ... = $F0xx`, `%asm{{ "quoted" }}`, `%target nmos`) -- upstream uses
`romsub`/`extsub`, raw `%asm {{ }}`, and real targets; isolate it behind a
small read/write/argv/exit interface. The string idiom (`out_text(uword)` +
`@()`) should become a `str` param + `s[i]` (call sites unchanged -> a
one-signature change). Reconcile in a dedicated **upstream-compat pass**
around P7-M6; build codegen in the common subset meanwhile. See
PHASE7_DESIGN.md section 10.

---

## High-level status (tinyp8 at v9)

* **Host p8c (Python)** -- recursive-descent compiler from `.p8`
  source to 6502 asm. Wide language coverage: `ubyte`/`byte`/`uword`,
  arrays, struct + struct arrays, `enum`, `const`, `defer`, `when`,
  `inline sub`, `for`/`while`/`repeat`/`break`/`continue`/`return`,
  `if`/`else`, full arithmetic + comparisons + signed support,
  `@(addr)`, `&var`, `peek`/`poke`/`lsb`/`msb`/`mkword`/`len`/`sizeof`,
  long-branch handling, `%target wendy2c` and `%target nmos`,
  string-literal-as-data (a bare `"..."` is the address of its pool label,
  a uword -- assignable to / passable to / initializing a uword). See
  `assembler2/prog8/p8c/` and the README for the full surface.

* **tinyp8.s (hand-written 6502)** -- a tiny on-target compiler.
  Accepts `print "..."`, `print_ub $XX`, `print_uw $XXXX`, `end`.
  Lives at `assembler2/prog8/tinyp8/tinyp8.s` (~500 bytes of asm,
  assembled by vasm).

* **tinyp8.p8 (Prog8, compiled by host p8c)** -- the same compiler
  rewritten in our language. Currently at **v9**: supports `let`,
  variable references in `print_ub`, `if X OP \$YY then print_ub Z`
  with the full comparison set, `while X OP \$YY` loops with an
  optional `print_ub Y` body before the let increment, and (v9)
  **multi-character variable names** via an on-target symbol table.

* **Self-host equivalence** -- for the v0/v1 corpus (5 inputs in
  `tinyp8/tests/goldens/`), tinyp8.s and tinyp8.p8 produce
  byte-identical output. tinyp8.p8 has grown well past v1 but its
  new features only kick in for new syntax, so the equivalence
  stays intact.

* **Test counts (as of HEAD)**:
  * 105 host p8c tests (`prog8/tests/` -- lex / parse / sema /
    codegen / snapshot / e2e LCD goldens, the iterative-parser
    equivalence + integration tests, the serializer freeze suite
    `test_serialize.py`, and `test_str_data_e2e.py` for
    string-literal-as-data).
  * 5 v0/v1 e2e (`tinyp8/tests/test_e2e.py`).
  * 5 v0/v1 self-host equivalence (`test_self_host.py`).
  * 12 v2..v9 .p8-only (`test_v2.py`, sources in `goldens_v2/`).
  * **176 total, all green** (the 22 tinyp8 + 49 p1 cases need vasm; see the
    environment note above). The p1 codegen cases live in
    `p1/tests/test_p1.py` (Phase 7: P7-M1 + P7-M2 + the M3 strings,
    byte-arithmetic, mul/shift, unary, comparison, logical, @()/&name, and
    16-bit word-arithmetic + word-shift slices; P7-M4 if/else/while +
    break/continue + repeat + for + when; P7-M5 void subs + calls + return values + params + locals; builtins; inline %asm; asmsub).

Run:

    cd assembler2 && make prog8-test tinyp8-test

---

## Repo layout you need to know

    assembler2/prog8/
        p8c/                # host compiler (Python)
            __main__.py     # `python3 -m p8c source.p8 [-o out.s] [--run]`
            lex.py
            parse.py        # recursive-descent (the big rewrite candidate)
            sema.py
            codegen.py
            stdlib_decls.py # wendy2c stdlib symbol declarations
        examples/           # demo .p8 files (hello, counter, sieve,
                            # tokenizer, structs, ...)
        tests/              # host p8c tests
            goldens/        # .p8 + .expected.lcd (wendy2c output)
            snapshots/      # .p8 + .expected.s (codegen oracle)
        tinyp8/
            tinyp8.s        # v1 hand-asm compiler
            tinyp8.p8       # v8 Prog8 compiler (grows each push)
            __main__.py     # `python3 -m tinyp8` driver
            out/tinyp8.bin  # cached vasm output for tinyp8.s
            tests/
                test_e2e.py         # v0/v1 goldens via tinyp8.s
                test_self_host.py   # v0/v1 byte equivalence
                test_v2.py          # v2..v8 goldens via tinyp8.p8
                goldens/            # v0/v1 .tp8 + .expected.stdout
                goldens_v2/         # v2..v8 .tp8 + .expected.stdout

The emulator is at `assembler2/emulator/emulator.out`. The
nmos-default machine (the one tinyp8 targets) exposes file I/O
at $F006-$F03C; see `assembler2/emulator/stubs.c` for the ABI.

---

## What the on-target compiler currently accepts (tinyp8 v9)

Variable names (`X`, `Y`, `Z` below) may now be **multi-character**
lowercase identifiers (`count`, `idx`, ...), up to 8 chars, 16 vars.

    let X = $XX            ; declare and assign a literal
    let X = Y              ; copy from another var
    let X = Y + $ZZ        ; arith with literal
    let X = Y + Z          ; arith with variable
    let X = Y - $ZZ        ; ditto with subtract
    let X = Y - Z
    print "string"
    print_ub $XX           ; literal byte as 2 hex chars + \n
    print_ub X             ; variable byte (uses an in-output 38-byte
                           ; hex helper, emitted lazily on first ref)
    print_uw $XXXX         ; literal word as 4 hex chars + \n
    if X OP $YY then print_ub Z    ; OP in { == != < <= > >= }
    while X OP $YY                 ; same OP set
        let X = X + $ZZ            ; body, fixed shape
    while X OP $YY                 ; body with optional print first
        print_ub Y
        let X = X + $ZZ
    end                    ; emit exit (lda #0; jsr $F00F)
    ; comments + blank lines OK

Restrictions worth remembering:
  * Variable names are lowercase `[a-z]+`, up to 8 chars, 16 vars
    max. Backed by a symbol table (`sym_names`/`sym_lens`/`sym_addrs`)
    read via `read_ident` + `find_var` / `declare_var`. Names exist
    only at compile time -- a var reference still emits a 2-byte
    `lda <zp>`, so emitted code size (and every hard-coded branch
    displacement) is unaffected by name length.
  * `if`'s then-clause must be exactly `print_ub <var>` (10
    bytes); the BNE displacement is hard-coded.
  * `while`'s let-body must be exactly `let X = X +/- \$ZZ` (7
    bytes); the print-body, when present, must be exactly
    `print_ub <var>` (10 bytes). (The let-body var names aren't
    validated -- they're skipped past, since the loop header already
    captured the loop var's address.)
  * The compiled output's hex-print helper (38 bytes + 3-byte
    JMP-around) is emitted lazily on first var-reference print.

---

## Recommended next pushes

Listed roughly by impact / risk, biggest payoff first.

### Option A: tinyp8 v9 -- multi-character variable names -- DONE

Landed this session. The 26-slot `var_addrs[]` table was replaced by
a symbol table:

      ubyte[128] sym_names    ; packed, 16 entries x 8 bytes
      ubyte[16]  sym_lens
      ubyte[16]  sym_addrs
      ubyte      sym_count
      ubyte[8]   name_buf     ; scratch for the current ident
      ubyte      name_len

with three helpers near the top of tinyp8.p8:

      sub read_ident()        ; skip ws, read [a-z]+ into name_buf (cap 8),
                              ; set name_len; leaves the terminator peeked
      sub find_var() -> ubyte ; linear scan; returns ZP addr or 0
      sub declare_var() -> ubyte ; find-or-allocate; bumps next_var_addr

All ~8 var-reading call sites now call `read_ident` + `find_var`
(or `declare_var` for the `let` LHS). The `while` let-body var names
are still skipped past unchanged (the loop header already captured
the loop var's address). Golden: `goldens_v2/17_multichar.tp8`
(exercises `idx` vs `index` -- different lengths -- and `idx` vs
`sum` -- same length, different bytes). v0/v1 equivalence intact;
ZP high-water is ~$90, well under the $ff cap.

### Option B: tinyp8 v9b -- expand if-then to a multi-statement block (1 push)

Removes the "then must be exactly `print_ub Z`" restriction.
Implementation requires buffering the body bytes during
compilation (since the BNE displacement needs to know body
size). Add `ubyte[32] body_buf` plus a mode flag on `write_dst`
that switches output to the buffer.

Less impactful than A but unblocks more interesting demos
(if-then with multiple prints, nested arithmetic, etc.).

### Option C: tinyp8 v10 -- read input from stdin (1 push)

`input X` reads one byte from the nmos read_b stub ($F006) into
variable X. Compiles to `jsr $F006; sta <X>`. Watch out for the
EOF carry flag -- can be ignored for v0 (read returns 0 on EOF).

Smaller in scope than A/B but unlocks "real input -> output"
demos and stress-tests the on-target compiler against actual
streaming use.

### Option D: BIG -- host p8c iterative parser rewrite (steps 1-4 DONE; only the Prog8 port remains)

The standing item for *real* Prog8-in-Prog8 self-host. Host
`p8c/parse.py` is recursive descent in Python; Prog8 forbids
recursion, so porting requires rewriting it around explicit stacks.

Progress:
  1. **DONE** -- `p8c/iter_parse.py`: iterative *expression* parser
     (shunting-yard over operand/operator stacks; binary precedence
     ladder, prefix unary, parens, calls with comma args, postfix
     `arr[idx]`/`.field`). Markers carry an operand-stack "floor" so
     reductions never reach past their sub-expression; an `index_ok`
     flag matches the recursive rule that only a bare ident may be
     indexed.
  2. **DONE** -- iterative *statement* parser: `Parser.parse_block_iter`
     in `parse.py`, a frame-stack driver. Each open block / compound
     is a frame; leaf statements reuse the existing non-recursive
     helpers; `defer` is a modifier that attaches to the next
     statement (simple or compound). `if/else`, `while`, `for`,
     `repeat`, and `when` (choice list + else) build their node on
     close. The `when` body runs in a separate 'choices' frame mode.
  3. **DONE** -- wired behind flags. `parse(..., iter_expr=True)`
     swaps just expressions; `parse(..., iter_stmt=True)` runs the
     whole parser iteratively (implies iter_expr). Equivalence proven
     by `tests/test_iter_parse.py` (expr: hand corpus + trailer cases
     + 4000-sample fuzz; stmt: full-program AST diff over a corpus)
     and `tests/test_iter_parse_integration.py` (byte-identical
     codegen over all 22 example/snapshot programs under both flags).

  4. **DONE** -- iterative parser is the DEFAULT. `parse()` now defaults
     to `iter_expr=True, iter_stmt=True`, so the CLI (`python3 -m p8c`),
     every existing test tier (parse/sema/codegen/snapshots/e2e), and
     the tinyp8 self-host build all run on the iterative parser --
     byte-identical output throughout (verified: in-process
     recursive == iterative codegen for tinyp8.p8, and the CLI output
     matches modulo the source-path header comment). The recursive
     descent is NOT deleted: it is retained as the equivalence oracle
     the tests check against (select it with `iter_expr=False,
     iter_stmt=False`). Removing it would remove that oracle -- defer
     until the Prog8 port is itself the working reference.

  IN PROGRESS (step 5):
  5. Port `iter_parse.py` + `parse_block_iter` to Prog8 itself -- the
     frame structs become `ubyte[]` parallel arrays / a tagged-union
     node array (the tinyp8.p8 idiom, scaled up). THIS is what unlocks
     Phase 7 (writing p1.p8). **Design doc:**
     [`PARSER_PORT_DESIGN.md`](./PARSER_PORT_DESIGN.md) -- covers the
     node arena, the parallel-array stacks/frames, a canonical AST
     serialization as the equivalence contract, and milestones M0..M5.
     * **M0 DONE.** `p8c/serialize.py` is the canonical AST
       S-expression serializer; `p8c --dump-ast` prints it (parser
       only -- no sema/codegen, matching what the on-target parser
       yields). Format frozen by `tests/test_serialize.py` (format
       assertions + a recursive-vs-iterative serialization equivalence
       gate over the whole corpus + on-disk goldens in
       `tests/goldens_sexp/`). Regenerate goldens after an intentional
       format change with `UPDATE_GOLDENS=1`.
     * **M1 DONE -- lexer port.** Oracle: `serialize_tokens` +
       `p8c --dump-tokens` define the canonical token-dump (one token
       per line; positions dropped, like the AST contract), frozen by
       `test_serialize.py` (`TokenDumpFormat` + the `LEXER_CORPUS`
       golden `goldens_sexp/tokens.dump`). On-target: `p1/lexer.p8`
       emits that dump on the 6502 -- argv[0] source -> argv[1] dump,
       same file-I/O shim as tinyp8. Verified byte-identical over
       examples + snapshots + `tinyp8.p8` + the lexer lexing its OWN
       source + the edge-case corpus (`p1/tests/test_lexer.py`,
       `make p1-test`, 21 tests). See `p1/README.md`.
     * **M2 DONE -- expression parser port.** `p1/expr.p8` lexes one
       expression to token arrays, parses it (shunting-yard over
       explicit operand/operator stacks into a struct-of-arrays node
       arena), and serializes it (explicit work-stack walk) --
       byte-identical to the oracle over the ENTIRE `EXPRESSIONS` corpus
       + a randomized-fuzz sample. Full grammar: atoms, prefix unary,
       binary ladder, parens, calls (nested/dotted, reversed cons-cell
       arg list), indexing (`arr[i]` / `.field`), `@()`, `&name`.
       `p1/tests/test_expr.py`, `make p1-test`. Three host-p8c issues
       handled en route (mkword Y-clobber + I/O EOF-stickiness fixed;
       ubyte-array-element->uword widening worked around) -- pitfalls
       below.
     * **M3 DONE -- statement + whole-program parser port.** `p1/stmt.p8`
       ports the top-level program parser + the frame-stack statement
       driver (parse_block_iter) + the full `(program ...)` serializer,
       no recursion, uword arenas. Byte-identical to the oracle over the
       whole `STMT_PROGRAMS` corpus (`p1/tests/test_stmt.py`,
       `make p1-test`). Three host enhancements made en route (see
       pitfalls): ZP-overflow scalars -> main memory; reentrant-safe sub
       calling convention; a serializer ordering-bug fix.
     * **M4 DONE -- whole-program parse on-target.** stmt.p8 extended to
       the full top-level surface: directives + imports list, `const`,
       `enum`, `struct` (+ struct instances/arrays `Point p` /
       `Token[4] toks`), `asmsub`, `inline sub`. Byte-identical to the
       oracle over the ENTIRE `examples/` corpus (18 files incl.
       tokenizer.p8 = enum+struct+inline). `p1/tests/test_stmt.py::test_examples`.
     * **M5 DONE -- capacity / streaming.** Streaming lexer (2-token
       window, no token array) + rewind-free statement parse + two
       passes over the rewound source (pass A: directives + module
       decls, skipping sub bodies by brace-match; pass B: stream each
       sub -- parse, serialize, reset the node arena). The whole
       1289-line `tinyp8.p8` (~2300 AST lines) parses byte-identical to
       the host (`test_stmt.py::test_tinyp8_capacity`). **Step 5 COMPLETE
       -- M0..M5 all done; the Prog8 parser runs on the 6502.**
     * **Phase 7 -- sema + codegen port (IN PROGRESS).** See
       [`PHASE7_DESIGN.md`](./PHASE7_DESIGN.md). `p1.p8` = the streaming
       front-end (reused) with the AST serializer DROPPED and replaced by
       sema + codegen, emitting `.s` byte-identical to `p8c -o` (the
       oracle -- no freeze step). Multi-pass driver: pass S builds the
       whole-program symbol table with byte-exact ZP allocation (module
       vars first, then per-sub params+locals in sub order, overflow to
       memory), then emit prologue + ZP bindings, then main (parse+sema+
       codegen+reset), then the other subs, then trailers (mul helper /
       arrays / structs / memvars / string pool / reset vector).
       * **p1.p8 is GENERATED** by `p1/build_p1.py`: it splices stmt.p8's
         front-end (everything before its `; ---- serialization ----`
         section) with a codegen back-end, rendering fixed asm text as
         `out_text("...")` calls over pooled string literals. Edit the
         generator, then `python3 p1/build_p1.py`. Sourcing the front-end
         from stmt.p8 keeps the parser in lockstep across both.
       * **P7-M1 DONE.** Skeleton. Codegen tail (`emit_prologue` /
         `emit_main` / `emit_trailers`). Driver: pass A (directives ->
         target+address) -> prologue -> pass M (find + codegen `main`) ->
         trailers. `main { }` (nmos) at several load addresses is
         byte-identical to `p8c -o` (the `; source:` line normalized on
         both sides). `p1/tests/test_p1.py`, `make p1-test`.
       * **P7-M2 DONE.** Module vars + simple assignment. Pass S
         (`build_symbols`) allocates each module scalar a ZP address with
         p8c's exact bump allocator ($40 up; ubyte/byte=1, uword=2) into a
         persistent symbol table (sym_ident/sym_type/sym_addr/sym_count +
         zp_next). `emit_zp_bindings` emits the ZP block
         (`p8v_<name> = $XX`) after the prologue. `codegen_stmt` does
         assignment: `=` of a leaf (literal/var) with ubyte->uword
         widening, and byte augmented (`+= -= &= |= ^=`) with a leaf
         operand. KEY: the ident pool persists across the pass-A -> pass-M
         reset (`reset_nodes`, NOT `reset_arena`) so symbol-table ident ids
         stay valid when main is re-lexed (intern_name dedups).
       * **String-literals-as-data (enabling work) + P7-M3 strings slice
         DONE.** p8c gained string-literal-as-data: a bare `"..."` is the
         address of its pool label (a uword), assignable to / passable to /
         initializing a uword (sema: STR coerces to UWORD; codegen:
         `_emit_word_expr_into_ay(StrLit)` -> `lda #</ldy #>` the label;
         additive -- existing snapshots unchanged; `tests/test_str_data_e2e.py`).
         p1.p8 then (a) emits ALL its fixed asm text via an `out_text(uword)`
         copy loop over pooled string literals instead of per-char `out_byte`
         runs (output-identical; out_byte call sites 962 -> 9; p1.bin 54.6 KB
         -> ~48 KB), and (b) gained codegen for string literals as values
         (`lda #</ldy #>p8c_str_N`, labels numbered in encounter order) + the
         string-pool trailer (port of `_escape`: printable runs, `$XX` for
         control/`"`/`\`, `, 0` terminator, `0` for the empty string),
         between main and the reset vector. Diffed vs `p8c -o` over an M3
         string corpus (`test_p1.py::test_m3_str_programs`).
       * **P7-M3 byte-arithmetic slice DONE.** Byte `+ - & | ^` in a byte
         assignment RHS, on an explicit work stack (`cws_*`: tasks 0 eval /
         1 binop-leaf / 2 pha / 3 sta tmp1 / 4 pla / 5 binop-tmp1) since p8c
         recurses and p1 can't. Leaf-RHS fast path (left chains a+b+c) +
         generic CPU-stack spill (non-leaf RHS -> pha/sta __p8c_tmp1/pla,
         the host's dual-scratch-safe form). Augmented assignment now shares
         `emit_byte_binop_leaf` via `aug_to_binop`.
         `test_p1.py::test_m3_expr_programs`. p1.bin ~50 KB.
       * **P7-M3 byte mul + shift slice DONE.** `*` via the `__p8c_mul_u8`
         runtime helper (emitted between main and the string pool, only when
         `mul_used` was set), and the shifts `<< >>` -- an immediate count
         unrolls to repeated `asl a`/`lsr a` (count & 7), a variable count
         emits a runtime loop with a `.Lshl_top_N` / `.Lshl_end_N` (resp.
         `.Lshr_*`) label pair. Added a global `label_seq` counter (= p8c's
         `_label_id`, alloc order top-then-end) and a `mul_used` flag, both
         reset before pass M. The two binop emitters were unified into
         `emit_byte_binop_core(op, mode, rhs)` (mode 0 = leaf rhs node,
         mode 1 = `__p8c_tmp1` spill) sharing one `emit_byte_operand`; the
         leaf/zp wrappers delegate. `aug_to_binop` now maps `<<=`/`>>=`.
         Covers leaf-RHS, the generic spill path, the dual-scratch pattern
         `(b<<3)+(b<<1)`, and augmented `<<= >>=`. `p8c -o` byte-identical
         over `test_p1.py::test_m3_mulshift_programs`. p1.bin ~52 KB code.
       * **P7-M3 byte unary slice DONE.** `~` (eor #$ff) and `-` (two's
         complement: eor #$ff / clc / adc #$01), integrated into the byte
         work stack as a post-operand "apply unary" task (cws ty 6) so the
         operand may itself be a nested expression. `not` (bool 0->1 else 0,
         label pair allocated end-first to match p8c) is also ported but not
         yet test-reachable -- its operand must be bool, and bool values only
         appear once comparisons/logical land (next slice). Note: p8c's parser
         only accepts ubyte/byte/uword as var types (NOT bool/str), so bool
         module vars are unsupported on both sides -- keep p1 in lockstep.
         `test_p1.py::test_m3_unary_programs`. p1.bin ~53 KB code.
       * **P7-M3 byte comparison slice DONE.** `== != < <= > >=` producing a
         0/1 byte value (assigned to a ubyte), port of `_emit_cmp_into_a`:
         unsigned branch sequences (incl. the extra `.Lgt_no_N` for `>`) and
         the signed paths (SBC + overflow-corrected N flag, `.Lsgn_ok_N` /
         `.Lsgt_no_N`). On the byte work stack: a comparison binop pushes
         eval-lhs / sta tmp0 (ty 8) / eval-rhs / sta tmp1 (ty 3) / cmp-tail
         (ty 7); the tail allocates `cmp_true`/`cmp_end` (+ extras) AFTER the
         operands evaluate, matching p8c's `_label_id` order. Signedness:
         p8c marks a comparison signed iff BOTH operands are exactly `byte`;
         `cmp_is_signed` resolves leaf-ident types via the symbol table
         (KNOWN GAP: a nested byte-arith operand p8c infers as `byte` is
         treated unsigned here -- needs full expr typing; the corpus uses
         leaf operands). This also makes `not` test-reachable
         (`a = not (b < c)`). `test_p1.py::test_m3_cmp_programs`.
         p1.bin ~56 KB code.
       * **P7-M3 byte logical slice DONE.** Short-circuit `and`/`or` (port of
         `_emit_logical_into_a`) and `xor` (bitwise on 0/1). For `and`/`or` the
         label pair (`.Land_false_`/`.Land_end_`, `.Lor_true_`/`.Lor_end_`) is
         allocated MID-evaluation (after the lhs, before the rhs -- matching
         p8c) and consumed by the tail after the rhs; a LIFO label-id stack
         (`lstk_*`) handles nesting. Work-stack tasks: ty 9 logic-mid, ty 10
         logic-tail, ty 11 `eor __p8c_tmp0` (xor reuses ty 2 pha / ty 8 sta
         tmp0 / ty 4 pla). Operands are bool (comparisons). Diffed vs `p8c -o`
         over `test_p1.py::test_m3_logical_programs` (and/or/xor, nested,
         not-of-logical). p1.bin ~57 KB code.
       * **P7-M3 @() memory + &name slice DONE (8-bit memory).** `@(IntLit)`
         read/write -> direct `lda`/`sta $XXXX`; `@(<word>)` read/write ->
         address into `__p8c_ptr0`, `(ptr0),y` indirect; `&name` -> `lda #< /
         ldy #>` the mangled label (a uword value). Added `codegen_word_expr`
         (the uword-eval entry: leaves + `&name` for now; it GROWS into the
         full word evaluator in the 16-bit work) which `@()` addresses and
         uword assignment RHS route through. `@()` read is a self-contained
         byte leaf so it nests as a binop operand (`a = @(p) + 1`).
         `emit_memat_read` / `codegen_assign_memat`.
         `test_p1.py::test_m3_memat_programs`. p1.bin ~59 KB code.
       * **CAPACITY FIX (build_p1.py `shrink_arenas`).** The spliced front-end
         sizes its arenas for the parser milestone (whole-program parse of
         tinyp8.p8), but p1.bin is exercised only on the SMALL codegen-test
         corpus. As codegen grew, the cumulative `.byte` reservations pushed
         the string pool's ADDRESSES past $FFFF, where the labels wrapped into
         the code and `out_text()` read garbage (symptom: `jmp $f0xx` bytes in
         the emitted `.s`). `build_p1.py` now rewrites p1.p8's array sizes down
         to M-corpus needs (nodes/cons 640->256, pools 1024->512, the dead
         serializer `ws_*` ->2, etc.), reclaiming ~9 KB (p1.bin code+data
         61->52 KB). Bump `ARENA_SIZES` if a future codegen test needs a bigger
         program. (stmt.p8 keeps its own sizes.)
       * **P7-M3 WORD arithmetic/bitwise slice DONE (16-bit).** `codegen_word_expr`
         is now a work-stack uword evaluator (separate `wws_*` stack so a byte
         expr's `@()` address can drive it without corrupting the byte stack):
         leaves + `&name`, and `+ - & | ^` (port of `_emit_word_operands` +
         `_emit_word_binop_into_ay` -- LHS held on the CPU stack across the RHS
         eval, RHS -> `__p8c_wtmp0`, carry-correct add/sub + per-byte bitwise;
         ubyte widens). Word augmented assignment (`w += e`) builds the same
         synthetic `w = w op e` binop p8c does. (Word unary `~`/`-` is a
         faithful port but p8c's sema rejects it -> unreachable/untested.)
         `test_p1.py::test_m3_wordarith_programs`. p1.bin ~52 KB code.
       * **P7-M3 WORD shift slice DONE (16-bit).** uword `<< >>` (port of
         `_emit_word_shl` / `_emit_word_shr`): a constant count in [0,16]
         unrolls the asl/rol (resp. lsr/ror) step n&15 times (with the n>=8
         "shift a whole byte" special case + p8c's swapped sty/sta in that
         arm); a variable count stashes the lhs into `__p8c_wtmp0` (wws task 4)
         and loops with a `.Lwshl_top_N`/`.Lwshl_end_N` (resp. wshr) pair. The
         variable count goes through `codegen_byte_expr` (matches p8c) -- safe
         at top level; a word shift with a non-leaf count nested in a byte
         expr's `@()` address would corrupt the byte stack (documented gap).
         Augmented `<<= >>=` via the synthetic word binop. wws tasks 4-8.
         `test_p1.py::test_m3_wordshift_programs`. p1.bin ~55 KB code.
       * **STUB-CEILING BUG (root-caused + guarded).** The emulator injects
         its file-I/O syscall stub routines (reached via the $F006 jmp table:
         argv/open/read/write/...) starting at **$F006** and growing UP, OVER
         p1.bin once loaded. So p1.bin's code+arenas+string pool must end below
         ~$F006 -- otherwise the stub injection clobbers the top of the string
         pool (and pool data clobbers the stubs), giving corrupted `out_text()`
         strings AND wild jumps (a syscall RTS lands in stub bytes overwritten
         by pool data). This -- NOT the $FFFF wrap theorized earlier -- was the
         real cause of the "garbage out_text" symptom both times. Fixed by
         shrinking p1.p8's arenas further (pool top now ~$E88B); guarded by a
         new ceiling assert in `test_p1.py::setUpClass` (parses the vasm
         listing, fails if the top reaches $F006). Diagnosed with a temporary
         emulator write/jump watchpoint (reverted). KEEP THE TOP < $F006.
       * **P7-M4 control flow slice DONE (if / if-else / while + break /
         continue).** Block emission is now a non-recursive statement work
         stack (`sws_*` tasks: emit-stmt / emit-label / emit-jmp / pop-loop;
         `push_block_stmts` pushes a block's stmts in source order) since p8c
         recurses via `_emit_block` and p1 can't. Conditions go through
         `emit_cond_branch_if_false` (port of `_emit_bool_test_branch_if_false`)
         -- a comparison emits the compare straight into a long-safe
         inverted-branch (`emit_br`, the `_br` idiom), byte unsigned/signed +
         the 16-bit word compare; a non-comparison cond materializes 0/1 and
         branches on zero. `if`/`while` allocate else/endif/while_top/while_end
         labels (shared `label_seq`); `break`/`continue` jump to the current
         loop's labels via a small loop-label stack (`lp_*`). Nesting is
         arbitrary (work stack). Byte-identical to `p8c -o` over
         `test_p1.py::test_m4_control_programs` (every byte cmp op, signed +
         uword conds, non-comparison cond, break/continue, nested). p1.bin
         ~57 KB code, top ~$E88B.
       * **P7-M4 repeat slice DONE.** `repeat` forever (count 0 -> rep_top /
         jmp / rep_end) and counted (push count on the CPU stack; the rep_dec
         tail does pla/sec/sbc #1, exits at 0; break pops the saved counter via
         rep_break). The 4 counted labels (rep_top/dec/end/break) are allocated
         sequentially so the deferred tail recovers them from rep_top alone
         (sws task 5). Literal + variable counts, break/continue.
         `test_p1.py::test_m4_repeat_programs`.
       * **P7-M4 for slice DONE.** `for v in lo to hi` (inclusive ubyte; v is a
         pre-declared var, already in the symbol table -- no local allocation
         needed). Init v=lo; for_top; body; for_cont: compare v to hi (literal /
         ident / spill), exit if equal, inc v, jmp for_top; for_end. The 3 labels
         (for_top/end/cont) are allocated so the deferred cont tail (sws task 6)
         derives top=end-1, cont=end+1. Literal/variable/computed range,
         break/continue. `test_p1.py::test_m4_for_programs`. (Arenas shrunk again -- fr_* to
         32, pools/nodes smaller -- to hold the top at ~$E9DE, ~1.5 KB under
         the $F006 stub ceiling.)
       * **NEXT (rest of M4/M5):** `for` (needs the loop var allocated -- the
         first LOCAL-variable allocation, a step toward per-sub locals),
         `when`, `defer`; then array
         indexing (`arr[i]` -- needs array symbols + storage trailers), calls
         (needs pass B: emit non-main subs + their params/locals in the symbol
         table), `txt.print*`. Watch the $F006 ceiling as code grows (shrink
         arenas / table-drive text / stream).
       * **WORD comparison: NO PORT NEEDED.** p8c's `_emit_cmp_into_a` always
         evaluates comparison operands as BYTES (it compares only the low
         bytes even for uword operands -- a p8c limitation;
         `_emit_word_cmp_into_a` is unreachable for comparison-as-value). So
         p1's existing byte cmp path already matches `p8c -o` for uword
         operands -- locked in by a uword case in `test_m3_cmp_programs`.
       * **NEXT: array indexing** (`arr[i]`, needs array
         symbols + storage trailers -- M5 territory), calls, `txt.print*`.
         (was: grow codegen_word_expr -- port of `_emit_word_expr_into_ay` /
         `_emit_word_binop_into_ay`
         proper -- the work-stack pattern generalizes, mind the mkword
         Y-clobber fix). Smallest-first, each diffed against `p8c -o`. Keep
         wrapping distinct fixed fragments in o_*/out_text helpers (one
         pooled string each).

The caveat below (fixed frame layout) is addressed in the design doc's
section 3.6 -- parallel arrays sized for the widest frame kind.

Caveat worth noting for step 5: the frame dicts here lean on Python
dynamic typing (heterogeneous per-kind fields). The Prog8 port will
need a fixed frame layout -- size it for the widest frame kind, or
split per-kind state into parallel arrays indexed by frame depth.

### Option E: more host language features (varies)

Other gaps toward full upstream Prog8 parity:
  * Pointer-to-struct `^^Token`, struct-as-param, struct arrays
    in subs.
  * Multi-file `%import "name"` with namespacing.
  * Strings as proper iterable buffers (currently only literal
    -> address; need `strlen`, `strcmp`, slicing).
  * Word-size signed type (`word`).
  * Multi-dim arrays.

Each is its own 1-2 push effort. Do these opportunistically
when a demo or tinyp8 push needs them.

---

## Pitfalls / gotchas observed this session

* **Streaming lexer shares `name_buf` with the parser.** In `p1/stmt.p8`
  (M5) the lexer runs one token ahead (the 2-token window), and
  `next_raw_token` writes the lexer's scratch `name_buf` (via
  `read_ident` / `classify_name`). The parser's `read_dotted_path` was
  also using `name_buf`: it built the name, then `advance()` (which lexes
  a lookahead token, clobbering `name_buf`), then `intern_name()` --
  interning the WRONG (clobbered) text. Fix: give the parser its own
  `path_buf`, and copy it into `name_buf` only at the moment of
  interning. Symptom was off-by-a-token idents (`(id x)` -> `(id if)`).
  Capture-the-id-before-advance is fine (ids stay valid because the
  ident pool persists); only name_buf-across-advance is unsafe.

* **Per-unit reset must NOT reset the text pools.** When streaming subs,
  the lookahead window holds tokens whose ident/str ids were interned
  during the previous sub. Resetting the pools per sub invalidates them.
  So per-sub reset clears only the node arena + cons cells; the pools
  persist across the whole pass (their union fits; idents dedupe).

* **64 KB ceiling.** stmt.p8's code is ~38 KB, so the arenas + memvars
  must fit in the remaining ~25 KB. Arenas are tuned for tinyp8.p8 +
  examples (biggest sub ~470 nodes). Bigger inputs (p1's own sources)
  need either smaller code (table-driven serializer) or finer streaming.

* **Host p8c: sub calling convention was not reentrant -- FIXED.** Args
  were stored straight into the callee's static param slots as each was
  evaluated; if a LATER arg's evaluation called the same sub (directly
  or transitively), it clobbered the already-stored earlier args. So
  `new_node(KIND, 0, parse_expr(), 0)` got the wrong KIND because
  `parse_expr` calls `new_node` internally. Fix (`p8c/codegen.py`
  `_emit_call`): evaluate every arg onto the hardware stack first, then
  pop them into the param slots immediately before the JSR. This is
  essential for the self-host (nested calls are everywhere). Changed
  codegen for all regular-sub calls but snapshots/tinyp8 stayed green
  (they don't use regular-sub multi-arg calls / the behavioral tests
  pass).

* **Host p8c: ZP variable space is a hard 192-byte global pool.** The
  ZP allocator (`$40..$ff`) is a global bump allocator, never reset
  across subs (sub locals can't overlap callees' locals -- non-
  reentrant). A big program (stmt.p8) exhausts it. Fix: scalars that
  overflow ZP now spill into main memory as labeled reservations
  (`address=None` in sema; emitted like arrays; referenced by label /
  absolute addressing). Proper per-sub ZP reuse would need call-graph
  coloring -- future work.

* **64 KB capacity.** stmt.p8 + generously-sized arenas overflowed
  $FFFF (the overflow scalars landed past the address space). The M3
  arenas were shrunk (tok 600, nodes 512, pools ~1.5 KB) to fit small
  programs. Parsing a whole big program (tinyp8.p8) in one shot won't
  fit -- M5 needs per-sub streaming.

* **On-target serializer: capture work-stack fields BEFORE pushing.**
  In stmt.p8's `(vals ...)` handler, `ws_push_simple(1)` incremented
  `ws_sp`, so a following `emit_cons_children(ws_node[ws_sp], ...)` read
  the WRONG (shifted) slot -- a stale value from a previous item. Always
  copy `ws_node[ws_sp]`/`ws_depth[ws_sp]` into locals before any
  `ws_push_*`. (Cost: a one-choice-delayed `when`-values bug.)

* **Host p8c codegen: `mkword` Y-clobber -- FIXED.** `mkword(hi, lo)`
  stashed the high byte in Y, then evaluated the low arg; if that arg
  was an array read (which uses Y for indexing) the high byte was lost.
  Fix in `p8c/codegen.py`: hold the high byte on the stack and shuffle
  through X so A=low, Y=high regardless. Guarded by a case in
  `tests/test_codegen_arith_e2e.py`.

* **Emulator rewinds input on EOF (by design, not a bug).** The read
  syscall does `fseek(f, 0, SEEK_SET)` at EOF (so two-pass tools like
  asm17 can re-read their input). EOF is therefore NOT sticky at the
  syscall level: read past EOF and you get the file from the top again.
  A single-pass reader must make EOF sticky in software (once `src_eof`
  is set, never call `_read` again) -- see `p1/lexer.p8` / `p1/expr.p8`
  peek_src/read_src. Without it, a token ending exactly at EOF (input
  with no trailing newline) loops forever. Latent in lexer.p8 too,
  masked because the test corpus files all end in newline.

* **16-bit arrays -- ADDED to p8c.** `uword[N]` arrays (2 bytes/element,
  little-endian), arrays up to 8192 elements, and uword indices are now
  supported. The original tight `lda label,y` path is kept for ubyte
  arrays that are <=256 elements with a ubyte index (so all pre-existing
  arrays / snapshot goldens are byte-identical); everything else uses a
  ZP element pointer (`__p8c_aptr` = $28) computed as `label + index*esize`
  and `(__p8c_aptr),y` loads/stores. See `_emit_array_addr_into_aptr`,
  `_array_fast_byte` in `p8c/codegen.py`; behavioral test
  `tests/test_arrays16_e2e.py`. (`len()` on a >256 array still truncates
  to a ubyte -- a known minor gap; the parser doesn't `len` the big
  arenas.)

* **ubyte ARRAY ELEMENT -> uword widening -- FIXED.** `some_uword =
  ubyte_arr[i]` (and passing `ubyte_arr[i]` to a uword param) now loads
  the byte and zero-extends, in `_emit_word_expr_into_ay`'s Index case.
  The earlier `p1/expr.p8` local-copy workaround was removed.

* **Host p8c codegen: dual-scratch binary expression bug -- FIXED.** An
  expression where BOTH operands of a binary op each need a scratch temp
  was mis-compiled -- e.g. `(v << 3) + (v << 1)` gave the wrong value
  (the left operand's fixed scratch slot was clobbered while computing
  the right). Found while porting the lexer's decimal accumulator. Fix
  (`p8c/codegen.py`): the first-evaluated operand is now held on the CPU
  stack across the second operand's evaluation, so the wtmp/tmp scratch
  is never aliased across the two sides -- nesting-safe to any depth.
  Touched `_emit_word_operands` (new helper for word `+`/`-`/`&|^`),
  `_emit_word_cmp_into_a`, and the byte generic binop path (RHS now in
  `__p8c_tmp1`, since `*` uses `tmp0`). Guarded by
  `tests/test_codegen_arith_e2e.py` (behavioral, on emulator) and by
  `p1/lexer.p8`'s decimal accumulator, which now uses the naive
  `(int_val<<3)+(int_val<<1)+(c-$30)` form. Snapshot goldens were
  unaffected (no existing snapshot hit the pattern); tinyp8 self-host
  equivalence still holds.

* **ZP allocator size**: `p8c/sema.py` has `ZP_VAR_TOP`; tinyp8.p8
  v6 hit the original 0x80 cap, was bumped to 0xff. If tinyp8.p8
  v9 (multi-char names) adds more module-level state, that may
  need attention again -- or you may need to move some state
  into main memory (`ubyte[N]` arrays live there, not ZP).

* **Branch displacements in tinyp8.p8**: every conditional branch
  in the COMPILED OUTPUT has hard-coded displacement bytes. When
  you change the body size (e.g., adding instructions to a
  fixed-shape block), every dependent displacement needs
  recomputing. Tests catch most of these by failing to halt or
  jumping into garbage.

* **The hex-print helper position-independence**: the 38-byte
  `__hex_print` helper emitted into the output uses only relative
  branches (BCC/BNE) inside; the only absolute reference is
  `jmp $F009`. So it can be placed anywhere. But its skip-around
  `JMP <after>` target IS absolute -- if you change the helper
  size, recompute that.

* **Symbol naming for stdlib calls**: host p8c mangles user-defined
  subs as `p8s_<name>` and asmsub args as `p8v_<sub>_arg_<name>`.
  Inline asm in tinyp8.p8 references these mangled names directly
  (e.g., `p8v__read_arg_handle`). When refactoring, watch for
  inline-asm strings that hard-code mangled names.

* **The `_argv` shuffle**: nmos's `argv` returns A=lo, X=hi but
  Prog8 expects uword in A:Y. tinyp8.p8 wraps it with an inline-asm
  helper that does `pha; txa; tay; pla`. Same applies for any
  other syscall that returns into X.

---

## Quick-resume cheatsheet

    # 1. Get to clean state
    cd assembler2/prog8
    git pull --rebase origin claude/review-wendy2-plan-MOfnA

    # 2. Verify everything's green
    cd ..
    make prog8-test tinyp8-test

    # 3. Look at the most recent commits to see what just landed
    git log --oneline -15

    # 4. The on-target compiler is built fresh each test run, but
    #    if you want to inspect it manually:
    cd prog8
    python3 -m p8c tinyp8/tinyp8.p8 -o /tmp/tinyp8_p8.s
    vasm6502_oldstyle -Fbin -dotdir -ignore-mult-inc -esc -wfail \
        -o /tmp/tinyp8_p8.bin /tmp/tinyp8_p8.s
    echo 'let n = $42
    print_ub n
    end' > /tmp/demo.tp8
    ../emulator/emulator.out /tmp/tinyp8_p8.bin /tmp/demo.tp8 \
        /tmp/demo.body --no-dump
    # then wrap and run via tinyp8/__main__.py's helpers, or by hand.

    # 5. To add a new v9 test:
    #    write tinyp8/tests/goldens_v2/NN_name.tp8 and
    #    tinyp8/tests/goldens_v2/NN_name.expected.stdout, then
    #    `python3 -m unittest tinyp8.tests.test_v2 -v` from prog8/.

---

## Conventions that have proven themselves

* Each tinyp8 growth push adds ONE feature, with ONE new golden
  test in `goldens_v2/`. Commit with a clear "v8 -- xxx" message.
* Never modify tinyp8.s without thinking hard about the v0/v1
  equivalence guarantee. The right move is to grow tinyp8.p8
  alone for any feature that isn't trivial to retrofit into asm.
* Run all three test suites (`test_e2e`, `test_self_host`,
  `test_v2`) plus the host p8c suite before each commit -- the
  feedback loop is cheap.
* Push after every commit. The remote is the source of truth.
* When a session is ending, refresh this file or replace it
  wholesale.
