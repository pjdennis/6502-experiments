#!/usr/bin/env python3
"""Transform p1/p1.p8 (our p8c model) into upstream-Prog8 source for the nmos
custom target. Layered fixups:
  1. structural: drop %target; wrap all bare top-level decls in a `main` block;
     turn the old `main { stmts }` entry body into `sub start()`.
  2. I/O wrappers: replace the p8c-style %asm syscall subs with upstream asmsubs
     (register ABI; symbols mangled the upstream way: main vars -> p8b_main.p8v_*)."""
import re, sys
src = open(sys.argv[1]).read()

# ---- 2. replace the I/O wrapper block (p8c %asm) with upstream asmsubs ----
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
src = re.sub(
    r'asmsub _exit\(ubyte code\) = \$F00F.*?sub _write\(ubyte b, ubyte handle\) \{.*?\n\}\n',
    IO_NEW, src, count=1, flags=re.S)

# ---- split out_text("...") literals longer than 255 into multiple calls ----
def _split_long(m):
    indent, content = m.group(1), m.group(2)
    units, i = [], 0
    while i < len(content):
        if content[i] == "\\" and i+1 < len(content):
            units.append(content[i:i+2]); i += 2
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
src = re.sub(r'(?m)^([ \t]*)out_text\("((?:[^"\\]|\\.)*)"\)\s*$', _split_long, src)

# ---- cast array indices to ubyte (monolith arenas are all <=256, indices fit;
#      upstream limits array indexing to a byte). Balanced-bracket aware (handles
#      nested indices), and skips strings + comments. ----
_TYPES = {"ubyte","uword","byte","word","bool","str","float","long"}
def _is_lit(x):
    return re.fullmatch(r"\s*([0-9]+|\$[0-9a-fA-F]+)\s*", x) is not None
def _cast_indices(s):
    out, i = [], 0
    while i < len(s):
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i:])
        if m and (i+m.end()) < len(s) and s[i+m.end()] == "[" and m.group() not in _TYPES:
            name = m.group(); j = i + m.end(); depth = 0; k = j
            while k < len(s):
                if s[k] == "[": depth += 1
                elif s[k] == "]":
                    depth -= 1
                    if depth == 0: break
                k += 1
            if k >= len(s):                 # unbalanced (shouldn't happen) -> bail
                out.append(s[i]); i += 1; continue
            inner = _cast_indices(s[j+1:k])
            idx = inner if _is_lit(inner) else "(%s as ubyte)" % inner
            out.append(name + "[" + idx + "]"); i = k + 1
        else:
            out.append(s[i]); i += 1
    return "".join(out)
def _split_comment(line):
    instr = False; i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and not (i and line[i-1] == "\\"): instr = not instr
        elif c == ";" and not instr: return line[:i], line[i:]
        i += 1
    return line, ""
def _cast_line(line):
    code, comment = _split_comment(line)
    parts = re.split(r'("(?:[^"\\]|\\.)*")', code)
    for k in range(0, len(parts), 2):
        parts[k] = _cast_indices(parts[k])
    return "".join(parts) + comment
src = "".join(_cast_line(l) for l in src.splitlines(keepends=True))

# ---- upstream requires boolean conditions: re-add `!= 0` to truthy
#      single-operand if/while conditions (p1.p8 has no bool-typed conditions) ----
src = re.sub(
    r'\b(if|while) ([A-Za-z_@][\w.]*(?:\([^()]*\))?(?:\[[^\]]*\])?) \{',
    r'\1 \2 != 0 {', src)

# ---- 1. structural wrap ----
lines = src.splitlines(keepends=True)
out, wrapped = [], False
for line in lines:
    if line.startswith("%target"):
        continue
    if line.startswith("%import") and not wrapped:
        out.append(line); out.append("\n%output raw\n%launcher none\n\nmain {\n"); wrapped = True; continue
    if line.rstrip() == "main {":
        out.append("sub start() {\n"); continue
    out.append(line)
out.append("}\n")
# ---- upstream forbids leading-underscore identifiers: rename the wrappers ----
final = "".join(out)
final = re.sub(r"\b_(exit|close|argv|open|openout|read|write)\b", r"sys_\1", final)
open(sys.argv[2], "w").write(final)
print("wrote", sys.argv[2])
