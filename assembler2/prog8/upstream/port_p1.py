#!/usr/bin/env python3
"""Transform p1/p1.p8 (our p8c model) into upstream-Prog8 source for the nmos
custom target. Layered fixups:
  1. structural: drop %target; wrap all bare top-level decls in a `main` block;
     turn the old `main { stmts }` entry body into `sub start()`.
  2. I/O wrappers: replace the p8c-style %asm syscall subs with upstream asmsubs
     (register ABI; symbols mangled the upstream way: main vars -> p8b_main.p8v_*).

The transform pipeline is exposed as port(src) so the pipeline porter
(port_pipeline.py) can reuse every fixup on top of its slab rewrite."""
import re, sys
HOIST = "hoist_arg"   # scratch global for the call-argument hoist (see below)

# ---- 2. the I/O wrapper block (p8c %asm) -> upstream asmsubs ----
IO_NEW = '''; ---- syscall asmsubs (emulator $F006+ stubs; upstream ABI) ----
extsub $F00F = _exit(ubyte code @A)
extsub $F015 = _close(ubyte handle @A)
asmsub _argv(ubyte i @A) -> uword @AY {
    %asm {{
        jsr  $f01e
        pha
        txa
        tay
        pla
        rts
    }}
}
asmsub _open(uword filename @AY) -> ubyte @A {
    %asm {{
        pha
        tya
        tax
        pla
        jsr  $f012
        rts
    }}
}
asmsub _openout(uword filename @AY) -> ubyte @A {
    %asm {{
        pha
        tya
        tax
        pla
        jsr  $f021
        rts
    }}
}
asmsub _read(ubyte handle @A) -> ubyte @A {
    %asm {{
        jsr  $f018
        bcc  +
        lda  #1
        sta  p8b_main.p8v_src_eof
        lda  #0
        rts
+       pha
        lda  #0
        sta  p8b_main.p8v_src_eof
        pla
        rts
    }}
}
asmsub _write(ubyte b @A, ubyte handle @X) {
    %asm {{
        jsr  $f024
        rts
    }}
}
'''

_TYPES = {"ubyte", "uword", "byte", "word", "bool", "str", "float", "long"}


def _is_lit(x):
    return re.fullmatch(r"\s*([0-9]+|\$[0-9a-fA-F]+)\s*", x) is not None


def _cast_indices(s):
    """Wrap every array index in `(... as ubyte)` (upstream indexing is byte).
    Balanced-bracket aware so nested indices are handled."""
    out, i = [], 0
    while i < len(s):
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i:])
        if m and (i + m.end()) < len(s) and s[i + m.end()] == "[" and m.group() in _TYPES:
            # a typed array decl (`uword[16]`, `uword[]`): emit the type and let
            # the bracket be copied literally -- its content is a SIZE, not an
            # index to cast. (Skip the WHOLE token; advancing one char would
            # re-scan the suffix, e.g. `uword[]` -> `ord[]`, as a bogus index.)
            out.append(m.group()); i += m.end(); continue
        if m and (i + m.end()) < len(s) and s[i + m.end()] == "[" and m.group() not in _TYPES:
            name = m.group(); j = i + m.end(); depth = 0; k = j
            while k < len(s):
                if s[k] == "[": depth += 1
                elif s[k] == "]":
                    depth -= 1
                    if depth == 0: break
                k += 1
            if k >= len(s):                 # unbalanced (shouldn't happen) -> bail
                out.append(s[i]); i += 1; continue
            inner = _cast_indices(s[j + 1:k])
            idx = inner if _is_lit(inner) else "(%s as ubyte)" % inner
            out.append(name + "[" + idx + "]"); i = k + 1
        else:
            out.append(s[i]); i += 1
    return "".join(out)


def _split_comment(line):
    instr = False; i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and not (i and line[i - 1] == "\\"): instr = not instr
        elif c == ";" and not instr: return line[:i], line[i:]
        i += 1
    return line, ""


def _map_code(line, fn):
    """Apply fn to the code (non-string, non-comment) spans of a line."""
    code, comment = _split_comment(line)
    parts = re.split(r'("(?:[^"\\]|\\.)*")', code)
    for k in range(0, len(parts), 2):
        parts[k] = fn(parts[k])
    return "".join(parts) + comment


def _split_long(m):
    """Split an out_text("...") literal longer than 255 chars into chunks."""
    indent, content = m.group(1), m.group(2)
    units, i = [], 0
    while i < len(content):
        if content[i] == "\\" and i + 1 < len(content):
            units.append(content[i:i + 2]); i += 2
        else:
            units.append(content[i]); i += 1
    if len(units) <= 255:
        return m.group(0)
    out, chunk = [], []
    for u in units:
        chunk.append(u)
        if len(chunk) >= 200:
            out.append(indent + 'out_text("' + "".join(chunk) + '")'); chunk = []
    if chunk:
        out.append(indent + 'out_text("' + "".join(chunk) + '")')
    return "\n".join(out)


def port(src, extra_main_decls=""):
    """Run the full upstream fixup pipeline. extra_main_decls is injected at the
    top of the wrapped main block (the pipeline porter uses it for slab bases)."""
    # ---- replace the I/O wrapper block (p8c %asm) with upstream asmsubs ----
    src = re.sub(
        r'asmsub _exit\(ubyte code\) = \$F00F.*?sub _write\(ubyte b, ubyte handle\) \{.*?\n\}\n',
        IO_NEW, src, count=1, flags=re.S)

    # ---- newline: the target uses `encoding = cp437`, whose encoder does NOT
    #      translate the `\n` escape to CR (unlike iso/petscii). So `\n` stays LF
    #      ($0a) in both string and char literals -- matching p8c and the
    #      emulator. No CR->LF normalization or `'\n'`->$0a rewrite needed. ----

    # ---- NOTE: the following fixups are now BAKED into the pipeline source and
    #      are no longer applied here:
    #        - arg-hoist, long-literal split, truthy `!= 0`;
    #        - `arr[i]` -> `arr[(i as ubyte)]` byte-index casts (p8c gained `as`);
    #        - structural wrap: `%target` dropped, decls wrapped in `main { }`,
    #          entry `main {` -> `sub start()`, `%output raw`/`%launcher none`
    #          added (p8c gained the `main`/`start` namespace form + --target).
    #      What remains is the I/O block rewrite (IO_NEW, above) and the
    #      leading-underscore rename below -- both Step 4 (I/O register-ABI). ----

    # ---- upstream forbids leading-underscore identifiers: rename the wrappers ----
    final = re.sub(r"\b_(exit|close|argv|open|openout|read|write)\b", r"sys_\1", src)
    return final


if __name__ == "__main__":
    open(sys.argv[2], "w").write(port(open(sys.argv[1]).read()))
    print("wrote", sys.argv[2])
