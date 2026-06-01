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
  * **157 total, all green** (the 22 tinyp8 + 30 p1 cases need vasm; see the
    environment note above). The p1 codegen cases live in
    `p1/tests/test_p1.py` (Phase 7: P7-M1 + P7-M2 + the M3 strings slice).

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
       * **NEXT: rest of P7-M3** -- the expression trees: port
         `_emit_byte_expr_into_a` / `_emit_word_expr_into_ay` proper (binop
         precedence ladder incl. the dual-scratch + mkword fixes already in
         the host), unary, `@()`, `&name`, indexing, calls, `txt.print*`;
         uword/shift augmented assignment. Go smallest-first, each construct
         diffed against `p8c -o`. The out_text refactor reclaimed the budget,
         but keep wrapping distinct fixed fragments in o_*/out_text helpers
         so each pooled string + call site appears once.

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
