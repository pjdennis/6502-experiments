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
