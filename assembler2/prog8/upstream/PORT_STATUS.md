# Bootstrapping p1.p8 with the UPSTREAM Prog8 compiler -- status

Goal: compile the self-hosting compiler (`../p1/p1.p8`) with the **upstream**
Prog8 compiler and run it on the emulator, verifying self-host from the
official toolchain.

## Done
- **Toolchain (MILESTONE A).** Upstream `prog8c` v12.1.1 + a custom `nmos`
  target (`nmos.properties` + `libraries/nmos/syslib.p8`) + `64tass` 1.60 +
  `mkimage.py` produce an emulator image that RUNS. Proven by `hello.p8`
  ("HI" via the syscall stubs). `setup.sh` fetches/builds the tools.
- **p1.p8 compiles under upstream (0 errors).** `port_p1.py` transforms the
  p8c-flavoured `p1/p1.p8` into upstream-Prog8 source, resolving every
  static-check incompatibility:
    1. structure: bare top-level decls -> wrapped in one `main` block; the old
       `main { stmts }` entry body -> `sub start()`.
    2. I/O wrappers: p8c `%asm{{ "..." }}` syscall subs -> upstream `asmsub`s
       with register ABI (`extsub $F00F = ...` for fixed-address stubs).
    3. directives: drop `%target`; add `%output raw` + `%launcher none`.
    4. string literals > 255 chars (the file header) -> split into multiple
       `out_text()` calls.
    5. **boolean conditions:** upstream REQUIRES bool conditions, so re-add
       `!= 0` to truthy `if/while X` (the inverse of our p8c readability pass;
       a real p8c-vs-upstream divergence).
    6. leading-underscore identifiers (`_argv`..) -> `sys_argv`...
    7. **uword array indices:** upstream limits array indexing to a byte; the
       monolith's arenas are all <=256, so `arr[idx]` -> `arr[idx as ubyte]`
       (balanced-bracket aware; skips strings/comments).
  Result: `prog8c -target nmos.properties /tmp/p1_up.p8` -> a 31 KB binary.
- **It runs.** The upstream-compiled p1.p8 runs on the emulator and
  TERMINATES CORRECTLY on empty input (init, file I/O, sticky-EOF, prologue +
  trailer codegen all work).

## Remaining (the runtime gap)
The upstream-compiled p1.p8 HANGS compiling a non-empty program (e.g. `main{}`),
while our p8c compiles the same input fine -- so it's a compiler-semantics gap,
not bad input. Prime suspect: **Prog8 forbids recursion** (subs use static, not
stacked, locals) and p1.p8's expression codegen is mutually recursive
(`codegen_byte_expr`/`codegen_word_expr`/`codegen_call`/`emit_builtin`/...).
prog8c warns about exactly these. Recursive calls clobber the callees' static
locals -> wrong behaviour / wild loops.

NB the monolith's small arenas mean it can only compile small inputs; true
self-host needs the PIPELINE (`p1_pass1_sh.p8`/`p1_pass2_sh.p8`) whose arenas
exceed 256 -- those need the large-array -> memory-slab + `@()`/`peekw` rewrite
(the index-cast trick only covers the <=256 monolith).

### Next steps
1. Localize the hang (the emulator has no CPU trace; add a temporary one, or a
   marker write in p1.p8's main, to confirm recursion vs a port bug).
2. De-recurse the expression codegen in build_p1.py (explicit work-stack, as
   the parser/serializer already do) so it's upstream-legal. Then the monolith
   should compile small programs correctly under upstream.
3. For full self-host: port the pipeline `_sh` files (big arrays -> slabs).

## Update: localized the runtime hang to handle-based reads
The upstream-compiled binary terminates on EMPTY input but hangs on any
content. Bisected (via `sys_exit` markers) to the lexer's first
`next_raw_token`, then isolated with a minimal echo program: a handle-based
read loop (`sys_open(argv0)` -> `sys_read` via `jsr $f018`) reads only the
FIRST byte, then `$f018` returns carry-set (spurious EOF) -- so the lexer's
sticky-EOF logic stops/loops immediately.

The puzzle: the generated `peek_src`/`next_raw_token`/`sys_read` asm is verified
correct, the open returns a valid distinct handle (src=2, dst=3, no collision),
and the `$f018` stub-call sequence is byte-identical to our p8c-compiled
monolith -- which reads multi-byte files fine (test_p1 passes). Yet the
upstream binary gets EOF after one byte. The difference is some subtle runtime
interaction (the emulator's `bit port_eof` peek = `fgetc`+`ungetc`, or a CPU
flag/register state) that diverges for the upstream binary's exact call pattern.
Pinning it needs a CPU/PC trace, which `emulator.out` does not provide -- adding
a minimal instruction-trace (or single-byte `--trace` flag) to the emulator is
the fastest way to nail it.

### Net status
Toolchain proven; p1.p8 COMPILES under upstream (0 errors, 31 KB) and RUNS
(empty input terminates). Remaining: (a) the handle-read EOF divergence above
[needs emulator trace], then (b) codegen recursion (Prog8 forbids it; de-recurse
via work-stack), then (c) pipeline `_sh` port (>256 arenas -> slabs) for true
self-host. port_p1.py reproduces the whole port.

## Update 2: cpu=6502 fix -> lexer works; now register_subs hangs
Root-caused the "hang on any content": the target had `cpu = 65C02`, so prog8
emitted `bra` for loop-backs, but the emulator's NMOS machine mis-executes `bra`
(its NMOS addr-mode table maps $80 to `imm`, not `rel`, while the opcode table
has `bra` at $80 -> stale relative offset -> every loop breaks). Our p8c avoids
`bra` for loops, which is why p8c-compiled code never tripped it. **Fixed: set
`cpu = 6502`** in nmos.properties (committed). Now:
- minimal `repeat{}` loops run correctly (verified),
- the upstream-compiled p1.p8 LEXES input without hanging (a 1-char program
  compiles and terminates).

Next hang (exit-bisected): a program containing a `main` block hangs in
`register_subs` (specifically `parse_main` / its decl loop) -- parse_decls_pass
and build_symbols complete. Likely a port-transform interaction in the parser
loop (index-cast or the `!= 0` rewrite) OR the work-stack parser hitting an
edge; bisect `parse_main` next. After that: codegen recursion (still warned),
then the pipeline `_sh` port for true self-host.

### How to reproduce / continue
  bash upstream/setup.sh                       # prog8c.jar + 64tass
  python3 upstream/port_p1.py p1/p1.p8 /tmp/p1_up.p8
  (cd upstream && java -jar /tmp/prog8c.jar -target nmos.properties -out /tmp/up /tmp/p1_up.p8)
  python3 upstream/mkimage.py /tmp/up/p1_up.bin /tmp/up/img.bin
  emulator/emulator.out /tmp/up/img.bin <in.p8> <out.s> --no-dump
Exit-bisection: inject `sys_exit(7)` after a phase in start() to see if it's
reached. Compare output to `python3 -m p8c <in.p8> -o oracle.s`.

## Update 3: MILESTONE -- upstream-compiled p1 == p8c, byte-for-byte (full corpus)
The `register_subs`/empty-body hang turned out to be three separate
upstream-vs-p8c codegen divergences, now all fixed in `port_p1.py`:

1. **`\n` -> CR ($0d).** Prog8 hardcodes `newlineToCarriageReturn = true` for
   config-file targets (verified in the jar: `ConfigFileTarget` always builds
   `Encoder(true)`; no `.properties` knob disables it -- and the `\n` escape is
   converted at parse time, so even `cp437`/`\x0a` don't help). Every `\n` in a
   string literal AND the `'\n'` char literal become $0d. Two fixes:
   - `out_text` normalizes CR->LF as it streams bytes (p1 output is pure asm,
     never a real CR); a no-op under p8c.
   - the lexer's `'\n'` char literal is rewritten to `$0a` so `c == '\n'`
     matches a real LF byte read from the input file. (Without this, ANY
     multi-line input hung the lexer -- the earlier "register_subs hang".)

2. **Static-param argument clobbering.** Upstream passes args by writing them
   left-to-right into the callee's STATIC param vars, THEN evaluating the call
   expression. So `new_node(K, OP, e, parse_expr())` stores `p8v_kind = K`, then
   evaluates `parse_expr()` -- which itself calls `new_node`, overwriting
   `p8v_kind` -- so the outer node is built with a stale kind (it came out as
   ND_INT). Verified in the generated asm (sta p8v_kind ; jsr pexpr ; jsr mk).
   This is effectively Prog8's no-recursion rule biting through an argument
   expression; p8c is immune (it evaluates all args to temps first). Fix: hoist
   the (always-last) `parse_*()` call into a scratch global `hoist_arg` on its
   own line. A single shared temp is safe (each hoist is consumed by the very
   next line; nested parse_*() finish before the outer assignment runs).

Result: `python3 upstream/port_p1.py p1/p1.p8 | prog8c -target nmos` produces a
binary whose output is **byte-identical to `python3 -m p8c`** across ALL 25
`p1/tests/test_p1.py` corpora -- 81/81 programs. Driver: `/tmp/up_corpus.py`
(imports the corpus lists from test_p1 and diffs upstream-p1 vs the p8c oracle).

### The remaining wall for TRUE self-host: array size/index limits
The MONOLITH p1.p8 cannot compile p1.p8 itself -- not a port issue: the
p8c-compiled monolith fails identically. p1.p8 has 213 string literals and
hundreds of symbols, but the monolith's arenas are tiny (str_pool[208],
strpool_sid[48], node[60], ...). That is *why* the pipeline (`p1_pass1_sh.p8` +
`p1_pass2_sh.p8`) exists: it splits the work and uses big arenas
(node[524], sym[780], cons[272], pools 5-6 KB).

But upstream Prog8 v12.1.1 imposes HARD limits we cannot meet with typed arrays:
  - split word array length: 1..256
  - regular (`@nosplit`) word array length: 1..128
  - array indexing: ALWAYS byte 0..255 (even on a 256-element split array)
So `uword[524] node_a` (and the 780/452/272-element arenas) simply cannot be
declared, and a `uword` index cannot be used. The `(idx as ubyte)` cast in
port_p1.py only works for the monolith *because* all its arenas are <=256.

=> Porting the pipeline to upstream requires a **memory-slab rewrite**: replace
each large arena with a fixed RAM base address and rewrite every `arr[idx]`
into `peek/poke` / `peekw/pokew` on `base + idx*esize` (uword index, uword
arithmetic). This is a sizeable, mechanical-but-risky transform (address
allocation for ~10 arenas totalling ~28 KB across $0200..$F000, plus applying
all the other port fixups to the two `_sh` files). It is the last piece needed
for upstream-bootstrapped self-host; the monolith result above proves the
codegen is faithful.

## Update 4: GOAL ACHIEVED -- upstream-bootstrapped self-host (byte-identical)
The full self-host now works with UPSTREAM prog8c as the bootstrap compiler:
`upstream/selfhost.sh` builds the pipeline (p1_pass1_sh.p8 + p1_pass2_sh.p8) with
prog8c for the custom nmos target, runs both passes on the emulator to compile
p1.p8, and the emitted p1.s is **byte-identical** (0-line normalized diff) to the
p8c host oracle. The p8c self-host (/tmp/verify.sh) still passes 0-diff too.

Two pieces beyond the monolith fixes:

1. **Memory-slab port (`upstream/port_pipeline.py`).** The pipeline arenas are
   word arrays of 272..780 elements indexed by uword -- impossible under upstream
   (split word arrays <=256, regular <=128, byte indices only). The porter
   auto-detects every array > 256 elements (18 in pass1, 16 in pass2), turns its
   declaration into a `const uword <name> = $BASE` raw RAM address, and rewrites
   every `<name>[idx]` into peek/peekw/poke/pokew on `base + idx*esize` (writes
   detected by the `=` after `]`, RHS bounded to one primary; reads recursive for
   nested indexing). The slabs are laid out just under the $F000 I/O floor and
   `memtop` is lowered to the slab base so the compiler keeps code/data/BSS below.
   It reuses every monolith fixup via port_p1.port(). pass1 code+data ends ~$4EA0
   (slabs $8300-$EFFF); pass2 fits likewise -- comfortably.

2. **One codegen fix in p1_pass2_sh.p8.** emit_byte_leaf_load's ubyte fast `,y`
   path parked the array's sym index in a (static) LOCAL `asi` across a call to
   the recursive codegen_byte_expr -- upstream's local-storage allocator overlaps
   that local with a variable the recursive call writes (p8c's allocator happens
   not to), so `asi` came back 0 (-> p8v_TK_EOF). Parking it in a module scratch
   `cg_arr_si` survives the re-entry. Output-identical under p8c (verify.sh still
   0-diff), correct under upstream. (The monolith p1.p8 has a simpler fast path
   with no such recursive call, so it was already fine.)

Reproduce: `bash upstream/setup.sh && bash upstream/selfhost.sh`.

## Update 5: corpus hardening of the slab port
`upstream/selfhost_corpus.py` runs the full p1 test corpus (81 programs) through
the upstream-compiled pipeline and diffs each against the p8c oracle:
**80 byte-identical, 1 known, 0 unexpected.** The one "known" is a signed-`byte`
comparison: p1_pass2_sh.p8's `emit_cmp_cond` is hand-specialized to p1.p8 (only
ubyte/uword) and omits p8c's signed compare arm, so it differs from the full
oracle -- but on that program the upstream pipeline matches the *p8c pipeline*
byte-for-byte (verified), confirming the slab port is a faithful reproduction of
the pipeline, not a divergence. (Run selfhost.sh first to build the images.)

## Update 6: syntax convergence -- one dialect, two compilers (in progress)

Goal (per project owner): stop maintaining two dialects bridged by the
`port_p1.py` / `port_pipeline.py` transform. Instead make the pipeline source
(`p1/p1_pass1_sh.p8`, `p1/p1_pass2_sh.p8`) **native upstream Prog8**, and update
the **p8c reference compiler** to accept that same upstream syntax (and keep
producing byte-identical output) -- so both compilers build the *one*
untransformed source. p1.p8 is deprecated as the flagship (the pipeline is the
definitive prog8) but stays as the self-host input/oracle. Self-host must stay
0-diff at every step (verify.sh = p8c, selfhost.sh = upstream).

Each transform fixup is resolved one of three ways: config, bake-into-source
(equivalence-preserving + p8c already accepts), or change-p8c-then-bake.

### Done (committed, both self-hosts 0-diff, corpus 80+1)
1. **Newline = cp437.** The `\n`->CR mangling is NOT inherent: verified in
   prog8c v12.1.1 that `ConfigFileTarget` hardcodes `Encoder(true)`, but the
   translation is applied per-encoding *at encode time* -- `iso`/`petscii`/...
   opt in, `cp437`/`atascii`/`c64os` do NOT. (At unescape time `\n`->10 (LF),
   `\r`->13 (CR), for all.) So `encoding = cp437` in `nmos.properties` keeps `\n`
   as LF (`$0a`) in string AND char literals, matching p8c + the emulator;
   cp437==iso==ASCII over `$00-$7f` (the only range the pipeline's asm-text
   strings use). Deleted both newline fixups from the transform.
2. **Baked equivalence-preserving fixups:** truthy `if/while X` -> `X != 0`
   (37 pass1 / 72 pass2); `new_node/cons_prepend(.., parse_*())` last-arg hoist
   to a `uword hoist_arg` scratch (10, pass1); `out_text("...")>255` pre-split.
   Removed from the transform (and its `hoist_arg` injection).
3. **`as` type-cast in p8c + baked byte-index casts.** Added a `Cast` AST node
   (parsed in `iter_parse` at lowest precedence; typed in sema; lowered in both
   byte/word codegen as low-byte narrow / high=0 widen). Baked
   `arr[i]`->`arr[(i as ubyte)]` (112 pass1 / 104 pass2). For p8c the cast flips
   the index onto the tight `lda label,y` fast path (same runtime index), so
   pass1 even shrank slightly. NOTE: a follow-up "index narrowing" pass should
   narrow vestigial `uword` index vars to `ubyte` where they only ever index a
   <=256 array (deletes most casts + cheaper byte arithmetic); the genuinely
   `uword` values are slab OFFSETS (`poke(base+off)`, not `[]`), already uncast.

### Remaining (the two hard transform steps -- each a multi-layer p8c change)

4. **I/O register-ABI block.** The I/O subs cannot share one source form as
   *regular* subs: their `%asm` bodies reference compiler-specific mangled names
   (p8c `p8v__read_arg_handle` / `__p8c_tmp0` / `p8v_src_eof`; upstream
   `p8b_main.p8v_*`). The convergence is upstream's **register-ABI `asmsub`**
   (args in A/X/Y/AY -> no static-param mangling). p8c must gain:
     - lexer/parser: raw `%asm {{ ... }}` bodies (today p8c demands a *quoted
       string* body, `%asm{{ "...\n..." }}`);
     - parser: register annotations `@A`/`@AY`/`@X`/`@Y` on params and `-> ret
       @REG`; the `extsub $ADDR = name(params)` form (today only the builtin
       table makes extsubs; source-level uses `asmsub name(..) = $ADDR`);
     - AST: `Param.reg`, `Sub.ret_reg`, asmsub body;
     - codegen: emit asmsub bodies (label + raw asm, no static-param prologue);
       register-ABI calls incl. **multi-arg** (`_write(b @A, handle @X)`);
     - sema: register params + extsub-with-address.
   The one non-register reference, the `src_eof` global in `_read`, is decoupled
   by having the read asmsub return EOF in a register (e.g. `-> uword @AY` with
   Y=EOF flag, A=byte) and setting `src_eof` from a thin prog8 wrapper -- which
   each compiler mangles correctly. Behavior-preserving, so 0-diff holds.
   Safe build order: add the p8c capability ADDITIVELY (current source keeps
   compiling identically -> verify.sh stays 0-diff) + a unit test, THEN
   restructure `src_eof` and bake the I/O block in `asmsub` form.

5. **`main`/`start` structural wrap.** p8c treats `main {}` as the entry *sub
   body*; upstream treats `main` as a *block/namespace* of decls + a `sub
   start()` entry, with `%output raw` + `%launcher none` (and no `%target`).
   p8c must parse `main` as a block of declarations (vars/consts/subs), pick
   `start` as the program entry, and accept/ignore those directives. After this,
   the structural wrap + leading-`_`->`sys_` rename leave the transform, and
   `port_p1.py`/`port_pipeline.py` can be deleted (memtop/encoding become static
   `nmos.properties` values; verify.sh + selfhost.sh compile the one source).

### Verification gates (unchanged)
verify.sh (p8c self-host) 0-diff; selfhost.sh (upstream self-host) 0-diff;
selfhost_corpus.py 80 match + 1 known + 0 unexpected -- all on the single
untransformed source.

## Update 7: Step 5 mostly done; %target removal scope mapped

Step 5 (structural convergence) is implemented and the pipeline source is fully
on the upstream `main`/`start` form:
- **p8c parses the `main { ... sub start() }` namespace form** (additive; the
  old `main { stmts }` entry-body form still works for the corpus). The prologue
  jmp + nmos reset vector target the real entry sub. 7 tests; suite 130/130.
- **p8c `--target {nmos,wendy2c}` flag + `%launcher none` directive** -- target
  routed externally like upstream's `-target`, so the source needs no `%target`.
- **pipeline source baked to `main`/`start`** (drop `%target`, wrap decls in
  `main { }`, entry `main {` -> `sub start()`, add `%output raw`/`%launcher
  none`); the structural wrap left `port_p1.py`. Committed `verify.sh` builds the
  pipeline with `--target nmos`.
- **p1.p8 + the pipeline are off `%target`**: `p1_pass1_sh.p8` defaults
  prog_target/prog_address to nmos/$0200; `p1.p8` dropped `%target`; all build/
  oracle calls that compile them pass `--target nmos` (verify.sh, selfhost.sh,
  test_p1.py). All self-hosts 0-diff; corpus 80+1; test_p1.py 26 OK.

### Remaining to FULLY remove `%target` -- *** DONE (see Update 8) ***
1. **Port the 82-program corpus** (`%target nmos` strings in `p1/tests/test_p1.py`):
   strip the directive; the `_oracle` (p8c) + `selfhost_corpus.py` oracle calls
   pass `--target nmos`; the **monolith `p1.p8`** parser must default nmos/$0200
   (it has its own `prog_target=0`/`prog_address=$4000` defaults at ~line 5358).
2. **Port the other four sources** that carry `%target` and have their own
   parsers + test suites: `p1/expr.p8`, `p1/stmt.p8`, `p1/lexer.p8`
   (test_expr/test_stmt/test_lexer) and `tinyp8/tinyp8.p8` (tinyp8 tests).
3. **Remove the `%target` directive** from every parser: p8c (`parse_directive`),
   the pipeline (`p1_pass1_sh.p8` dir handler) and the monolith/earlier sources'
   parsers -- each kept self-host/test 0-diff (the directive becomes dead once no
   input uses it; default stays nmos).

## Update 8: `%target` FULLY REMOVED (the four steps above, all 0-diff)

The `%target` directive is gone from the entire corpus AND every parser. The
target is now selected purely externally (`p8c --target nmos`, the on-target
compilers' nmos/$0200 defaults), exactly like upstream's `-target`. Done in
four committed steps, each verified byte-identical:

1. **p1 corpus** (`p1/tests/test_p1.py`): stripped `%target nmos` from all 81
   programs; the p8c oracle (`_oracle`) and the upstream corpus oracle
   (`selfhost_corpus.py`) pass `--target nmos`; the monolith `p1.p8` driver
   defaults to nmos/$0200.
2. **The four parser-port sources** (`p1/stmt.p8`, `p1/expr.p8`, `p1/lexer.p8`,
   `tinyp8/tinyp8.p8`): dropped their own `%target nmos` directive; each test
   harness that host-compiles them now passes `--target nmos`. `build_p1.py`'s
   generated driver also moved to nmos/$0200 (regenerating `p1.p8` from the
   now-directive-free `stmt.p8` reproduces the committed file).
3. **Host p8c test inputs** (`test_codegen` MainNamespaceForm + the four e2e
   shims + `test_serialize`): stripped the directive; `compile_text()` gained an
   external `target=` param; the e2e shims pass `--target nmos`.
4. **Every parser**: removed the directive's handling from `p8c/parse.py`
   (`parse_directive`), `p1/stmt.p8` (`dir_classify` + the dk==3 block, ->
   regenerated `p1.p8`), and `p1/p1_pass1_sh.p8` (`dir_strs`/`dir_codes` 4->3 +
   the dk==3 block). pass1 even freed ~125 B.

The serializer's `(target ...)` form is KEPT (it serializes the parser's
default/external target -- the `goldens_sexp/programs.sexp` goldens already
show `(target wendy2c)`); it is test-only scaffolding (the parser-equivalence
oracle), not part of the shipped self-host pipeline. The lexer still tokenizes
any `%word` generically, so `%target` still LEXES (the `tokens.dump` golden is
unchanged); only the parser stopped giving it meaning.

Verification (all green, all byte-identical): p8c self-host 0-diff, upstream
self-host 0-diff, upstream corpus 80 + 1 known-signed + 0 unexpected, test_p1
26, test_stmt/expr/lexer 27, host p8c 130, tinyp8 22.

### Then Step 4 (I/O register-ABI) -- unchanged design in Update 6
Use the owner's bootstrap when the PIPELINE itself must parse the new asm syntax:
build a temporary old-written/new-accepting compiler, test it, then use it to
compile the final new-written/new-accepting pipeline -- avoiding dual-syntax
bloat against the memory cap.

## Update 9: Step 4 (I/O register-ABI) -- pipeline CONVERGED (A + B done)

The two-step bootstrap from Update 6 is realized for the PIPELINE. The key
relaxation that made it tractable: the convergence bar is functionally-
equivalent I/O (the generated p1.s stays 0-diff), NOT byte-identical pipeline
binaries -- so the new-form asmsubs just have to do the same I/O at runtime.

**Step A -- p8c is "new-accepting" (additive; legacy forms untouched, all
self-hosts stay 0-diff during the build-out).** Committed in two pieces:
  - **4.A1 raw `%asm {{ ... }}`.** The lexer captures the interior verbatim
    as one ASMRAW token *only* when the body is not a string, so every legacy
    `%asm{{ "..." }}` block lexes byte-for-byte as before; the parser dedents
    the raw body and codegen re-indents by two spaces (a raw block emits the
    same asm as the equivalent quoted one).
  - **4.A2-A4 register-ABI asmsubs.** AST `Param.reg` + `Sub.ret_reg`; parser
    `@A/@X/@Y/@AY` param + `-> rt @REG` annotations, the `extsub $ADDR =
    name(...)` form, and the asmsub *body* form; sema gives register params no
    storage; codegen emits asmsub bodies under their label and loads call args
    into the annotated registers (X/Y first via A, the A/AY arg last), incl.
    multi-arg, JSRing the address or the body label. Proven to compile AND
    assemble (vasm) with the right register conventions (test_codegen
    RawInlineAsm + RegisterAbiAsmsub, host p8c 138).

**Step B -- the pipeline source is now the ONE converged form.**
`p1_pass1_sh.p8` / `p1_pass2_sh.p8` carry their file-I/O wrappers as
register-ABI `extsub`/`asmsub`s named `sys_*` (no leading underscore), built
untransformed by BOTH p8c (verify.sh) and upstream prog8c (selfhost.sh).
  - **src_eof decoupling:** the read syscall is `sys_read_raw` (asmsub ->
    A=byte, Y=EOF) + a thin prog8 `sys_read` wrapper doing `src_eof = msb(r)`,
    so NO asm body references the per-compiler-mangled src_eof. A plain named
    label (`sys_read_ok`) replaces 64tass's `+` anonymous label so the body
    assembles under both vasm and 64tass.
  - **port transform retired for the pipeline:** `port_pipeline.py` calls
    `port_p1.port(io_transform=False)` -- the I/O rewrite + leading-underscore
    rename no longer apply to the (already converged) pipeline source. They
    remain (gated) only for the legacy monolith `p1.p8` path.
  - Verified byte-identical: p8c self-host 0-diff, upstream self-host 0-diff,
    upstream corpus 80+1+0, host p8c 138, test_p1 26.

### Remaining for FULL I/O convergence (the on-target half)
The PIPELINE is converged, but `p1.p8` (the self-host INPUT) still has its own
I/O wrappers in the LEGACY `%asm{{ "..." }}` + regular-sub form, so the
on-target parser (stmt.p8 / pass1_sh's parser that parses p1.p8 at runtime)
still only handles the legacy form. To finish:
1. Teach the **on-target parser** (`stmt.p8` -> regenerated `p1.p8`, and
   `p1_pass1_sh.p8`) to parse register-ABI asmsubs: `@REG` param/return
   annotations, the `extsub $ADDR = name(...)` form, the asmsub body form, and
   raw `%asm {{ }}` blocks -- plus the on-target codegen to compile them (the
   Prog8 mirror of Step A, with the self-host byte-identity + 64 KB
   constraints). This is the largest remaining piece.
2. Converge `p1.p8`'s (i.e. `build_p1.py`'s) own I/O block to the `sys_*`
   register-ABI form + src_eof decoupling.
3. Once p1.p8 is converged, drop the legacy `%asm`-string + asmsub-decl paths
   from the on-target parser/codegen and from p8c (retire the quoted-string
   inline-asm form), and DELETE `port_p1.py`'s I/O transform entirely (the
   `io_transform` flag and IO_NEW).
