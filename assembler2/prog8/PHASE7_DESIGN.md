# Design: porting sema + codegen to Prog8 -- the self-hosting `p1.p8` (Phase 7)

Status: **design** -- no code yet. Entry point for Phase 7, written the
same way [`PARSER_PORT_DESIGN.md`](./PARSER_PORT_DESIGN.md) opened the
parser port (Phase 6 step 5), which is now **complete** (M0..M5: the
Prog8 parser runs on the 6502 and is byte-identical to the host across
the token / expression / whole-program contracts, including the whole
1289-line `tinyp8.p8`).

This doc plans the last piece of the end-state: a Prog8 program `p1.p8`
that **compiles `.p8` source to 6502 assembly on the 6502**, byte-for-
byte identical to the host `p8c`. With that, the strict self-host check
`p0(p1.p8) == p1(p1.p8)` (the asm-chain pattern) closes.

---

## 1. Goal and success criterion

`p1.p8`, running on the emulator's nmos-default machine, reads a `.p8`
source file and writes the `.s` assembly text **byte-identical** to
`python3 -m p8c source.p8 -o source.s`, across a growing corpus
(STMT-style programs -> examples -> tinyp8.p8 -> p1.p8 itself).

The success criterion has two tiers, mirroring the asm chain:

* **Output equivalence**: for every `.p8` in the corpus, `p1`'s `.s`
  equals `p8c`'s `.s` (modulo the one `; source: <path>` comment line,
  which the existing snapshot tests already normalize).
* **Strict self-host**: `p1.p8` compiled by `p8c` (call it `p0(p1.p8)`)
  and by `p1` itself (`p1(p1.p8)`) produce the same `.s`, which assembles
  to the same binary. This is the bootstrap fixpoint.

The **contract/oracle already exists**: it is `p8c -o`. No M0-style
freeze step is needed -- the host compiler's `.s` output is the golden.

Non-goal: matching p8c's *internal* structure. Only the emitted `.s`
text must match.

---

## 2. What changes vs. the parser port

The parser port produced `p1/stmt.p8`, which parses a whole program and
emits a canonical **AST serialization** for verification. The real
compiler keeps the front half and **replaces the serializer with
sema + codegen**:

```
  p1/stmt.p8  (parser milestone):  lex -> parse -> serialize-AST
  p1.p8       (the compiler):      lex -> parse -> sema -> codegen-.s
```

The AST serializer (`serialize_program`, `emit_node`, the `out_*`
spelling helpers) was scaffolding for M3-M5 and is **dropped** from
`p1.p8`. That matters for capacity: the serializer is a large slice of
`stmt.p8`'s code, and codegen reuses the same "emit text to the output
file" primitive (`out_byte`), so the code budget roughly transfers from
"serialize AST" to "emit asm".

Reused as-is from the parser: the streaming lexer (2-token window), the
shunting-yard expression parser, the frame-stack statement driver, the
node arena, the text pools, and the two-pass top-level driver.

---

## 3. The core problem: streaming vs. a whole-program symbol table

The parser streams per top-level unit (sub bodies never coexist) so a
compiler-sized program fits in 64 KB. Codegen needs more global
information than the parser did:

* **A whole-program symbol table.** Every identifier in a sub body must
  resolve to a symbol (a module var, a const, a sub, an enum member, a
  param, a local) with its allocated ZP/main-memory address (vars),
  literal value (consts), or call target (subs). So sema must build the
  **complete** symbol table *before* codegen emits any sub.

* **Byte-exact allocation order.** To reproduce p8c's addresses, the
  on-target allocator must run in p8c's exact order: module vars first
  (ZP bump from `$40`, overflow to main memory), then **each sub's
  params + locals in sub-declaration order** (the global ZP bump never
  resets across subs -- see RESUME_NOTES). Locals are discovered by
  walking each sub body, so a body must be parsed to allocate its
  locals -- but its *nodes* can be freed afterward (only the symbol
  entries persist).

* **Main-first emission.** p8c emits `jmp p8s_main` then `main` before
  the other subs. Source order is arbitrary, so codegen can't simply
  stream subs top-to-bottom.

The symbol table is small (tinyp8.p8: ~97 distinct idents, ~35 subs,
~27 module vars) and **persists** for the whole compile, unlike the
per-sub node arena.

### Proposed multi-pass architecture

All passes stream over the (rewound-on-EOF) source, as in the parser.

1. **Pass S (symbols).** Walk top-level decls. For module vars / consts:
   allocate a symbol (ZP address via the bump allocator, or const value).
   For enums: assign member values (auto-increment). For subs: register
   the sub name + its mangled label + return type; then **parse the body
   to allocate its params + locals** (walk var-decls and the loop-var of
   `for`), appending each to the global symbol table with its ZP address,
   then free the body's nodes. Structs: field layout. This pass fixes
   every address exactly as p8c does.

2. **Emit prologue + ZP bindings** from the symbol table (the fixed
   header text + one `p8v_<name> = $XX` per ZP scalar, in allocation
   order).

3. **Pass M (main).** Re-scan; find `main`; parse its body, run sema
   (resolve idents to symbols, type the expressions), codegen the body to
   `.s`; reset the node arena.

4. **Pass B (other subs).** Re-scan; skip `main`; for each remaining sub,
   parse + sema + codegen + reset, in source order (p8c emits non-main
   subs in source order).

5. **Emit trailers**: the `__p8c_mul_u8` helper (if used), array storage,
   struct storage, ZP-overflow memvar storage, the string pool, and the
   nmos reset-vector / wendy2c epilogue -- matching p8c's tail exactly.

Passes S, M, B each re-read the source (cheap; the emulator rewinds on
EOF). The symbol table built in pass S persists through M and B.

---

## 4. Data representations (on the 6502)

Building on the parser's arena + pools:

### 4.1 Symbol table (persistent)

Struct-of-arrays, indexed by a small symbol id:

    ubyte[NSYM] sym_name        ; ident id (into the persistent text pool)
    ubyte[NSYM] sym_kind        ; var / const / sub / asmsub / enummember / param / local / array / ...
    ubyte[NSYM] sym_type        ; ubyte / byte / uword / bool / ... (type tag)
    uword[NSYM] sym_addr        ; ZP/mem address (vars) -- 0xFFFF if in main memory
    uword[NSYM] sym_value       ; const value / enum value / array size / asm target
    uword       sym_count

Lookup is `find_sym(ident_id, scope)`: scan the current sub's locals
(a contiguous id range) then module scope. Because idents are interned
in one persistent pool (it survives the whole compile), comparison is
id-equality -- no string compares.

Mangling (`p8v_`, `p8s_`, `p8v_<sub>_arg_<param>`, `.L...`) is emitted
on demand from the symbol + current-sub name, matching p8c's scheme.

### 4.2 ZP allocator

A single `uword zp_next` starting at `$40`, bumped by 1 (ubyte) or 2
(uword) per scalar, overflowing to a labeled main-memory list when it
passes `$ff` (exactly the p8c rule -- already implemented host-side; the
on-target version reproduces the same addresses).

### 4.3 Per-sub node arena + label counter

The parser's arena, reset per sub. Plus a persistent `uword label_seq`
for the `.L<name>_<n>` local labels (p8c numbers them globally, so this
counter must not reset -- match its sequence exactly).

---

## 5. Codegen: the bulk of the work

This is the large, mechanical part -- a transcription of `p8c/codegen.py`
into Prog8, emitting the same instruction text. It is already a tree
walk over the AST; like the parser, the recursion is shallow (expression
depth) and is handled with the same explicit work-stack toolkit. Key
pieces to port, smallest-first (each diffs against `p8c -o`):

* **Statements**: assignment (`=`, augmented, `@()=`, `arr[i]=`),
  `txt.print` / builtins, `if/else`, `while`, `for`, `repeat`,
  `break/continue/return`, `when`, `defer`, inline `%asm`.
* **Byte expressions** (`_emit_byte_expr_into_a`) and **word expressions**
  (`_emit_word_expr_into_ay`): literals, vars, the precedence-correct
  binop sequences (incl. the dual-scratch + mkword fixes already in the
  host), unary, indexing (incl. the 16-bit array pointer path), `@()`,
  `&name`, calls (the stack-based reentrant arg passing).
* **Branches**: the invert-branch + JMP long-branch pattern, the 16-bit
  compare idiom.
* **The literal text**: instruction mnemonics, `$XX`/`#$XX` formatting,
  labels. This is where the dropped AST-serializer's code budget goes.

A first cut targets the **subset tinyp8.p8 uses** (it is the corpus that
matters for the self-host), then widens to the examples.

---

## 6. Milestones

Each milestone is a few pushes; each diffs `p1`'s `.s` against `p8c`'s.

* **P7-M1 -- skeleton. DONE.** `main { }` (nmos): prologue + ZP bindings
  (none) + `p8s_main:` + the return/exit epilogue + reset vector.
  Establishes passes S / prologue / M / trailers end-to-end with an empty
  body. `p1/p1.p8` reuses stmt.p8's streaming front-end (lexer + expr +
  statement driver + node arena), DROPS the AST serializer, and adds a
  codegen tail: `emit_prologue` / `emit_main` / `emit_trailers`, with the
  fixed asm text spelled out via `out_byte()` runs (p8c has no
  string-literal-as-data). The driver runs pass A (directives -> target +
  address), emits the prologue, runs pass M (find `main`, codegen its
  body), and emits the trailers. Byte-identical to `p8c -o` (the
  `; source:` line normalized) over the empty-main corpus at several load
  addresses. `p1/tests/test_p1.py`, `make p1-test`.
    * Code-size read: p1.bin is ~50 KB (front-end + the per-byte prologue
      text). Fits comfortably in 64 KB now, but confirms the design's
      "table-drive the literal text" mitigation will be needed before the
      corpus grows much -- the fixed-text `out_byte` runs are the dominant
      cost, exactly as the serializer milestone predicted.
* **P7-M2 -- module vars + simple assignment.** `ubyte x` ... `x = 1`,
  `x = y`, augmented. Exercises the symbol table + ZP bindings +
  `_emit_byte_expr` leaves + store.
* **P7-M3 -- expressions.** byte + uword arithmetic / comparison / unary,
  `@()`, `&`, indexing, calls, `txt.print*`.
* **P7-M4 -- control flow.** if/else, while, for, repeat, break/continue/
  return, when, defer; long branches.
* **P7-M5 -- decls + trailers.** arrays, consts, enums, structs, asmsub,
  inline sub; array/struct/string/memvar storage; the mul helper.
* **P7-M6 -- corpus + self-host.** Byte-identical `.s` over the examples
  and tinyp8.p8; then `p0(p1.p8) == p1(p1.p8)` once `p1.p8` is whole.

---

## 7. Verification

The on-target test harness already exists (`p1/tests/`): build `p1.p8`
with host p8c + vasm, run it on the emulator over a corpus, diff its
output. For Phase 7 the golden is `p8c -o` (not `--dump-ast`), with the
`; source:` line normalized -- exactly the existing snapshot
normalization. The recursive/iterative host equivalence and the codegen
fixes already proven host-side transitively back the on-target output.

---

## 8. Risks / open questions

* **64 KB capacity is THE risk.** `stmt.p8` is ~38 KB of code; codegen is
  large. Mitigations, in order: (a) drop the AST serializer (done by
  construction -- p1.p8 doesn't include it); (b) table-drive the literal
  text (mnemonics / fixed strings) instead of per-byte `out_byte` spam,
  which the serializer milestone showed is the dominant code cost; (c) if
  still too big, split codegen per construct behind the same streaming
  the parser uses, or accept that `p1` compiles up to a bounded program
  size (tinyp8.p8) first and grows. Measure early (P7-M1 already shows
  the prologue+skeleton code cost).
* **Allocation-order fidelity.** Any divergence in ZP/label/string
  numbering vs. p8c yields a different (but possibly still correct) `.s`.
  The self-host check needs *byte* identity, so pass S must replicate
  p8c's order exactly. Pin this with the smallest programs first.
* **Subset coverage.** p1.p8 only needs to compile the subset p1.p8 is
  *written in* (plus the corpus). Track that subset as codegen grows --
  the same discipline tinyp8's v-series and the parser milestones used.
* **String / data emission.** p8c lifts strings to a pool with labels and
  emits `.byte` lists with a specific escape policy (`_escape`); reproduce
  it exactly (it is small and self-contained).

---

## 9. What to do first

P7-M1: extend a copy of the parser front-end into `p1/codegen` scaffolding
that, for `main { }`, emits the fixed nmos prologue, an empty `p8s_main`,
the return/exit epilogue, and the reset vector -- diffed against
`p8c -o`. It wires up pass S (trivial here), the prologue/trailer text,
and the per-sub emission loop, and it gives the first real read on the
code-size budget. Then P7-M2 (vars + assignment) is the first codegen of
actual statements.
