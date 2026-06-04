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
