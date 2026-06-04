#!/usr/bin/env python3
"""Port a pipeline pass (p1_pass1_sh.p8 / p1_pass2_sh.p8) to upstream Prog8.

The pipeline's arenas are word arrays of 272..780 elements indexed by uword.
Upstream Prog8 caps word arrays at 256 (128 @nosplit) and ALWAYS uses byte
indices, so those arenas cannot be expressed as typed arrays. This porter
"slabs" every array > 256 elements: the declaration becomes a `const uword
<name> = $BASE` (a raw RAM base address), and every `<name>[idx]` access is
rewritten to peek/poke on `base + idx*esize`. The slab region is laid out just
below the I/O floor ($F000); `memtop` in the generated .properties is lowered to
the slab base so the compiler keeps its own code/data/BSS below it.

All the other upstream fixups (I/O wrappers, \n->CR, arg hoist, byte-index cast
of the REMAINING <=256 arrays, !=0 conditions, structural wrap, _-rename) are
reused from port_p1.port(), run AFTER the slab rewrite.

Usage: port_pipeline.py <in.p8> <out.p8> <out.properties> [base_properties]
"""
import re, sys
import port_p1

IO_FLOOR = 0xF000          # slabs must end at or below this (emulator I/O ports)
SLAB_THRESHOLD = 256       # arrays larger than this get slabbed

src = open(sys.argv[1]).read()
out_p8, out_props = sys.argv[2], sys.argv[3]
base_props = sys.argv[4] if len(sys.argv) > 4 else "nmos.properties"

# ---- pre-pass: add `!= 0` to truthy if/while conditions NOW, while a slabbed
#      operand is still `name[idx]`. After the slab rewrite it becomes
#      `peekw(base + (idx)*2)`, whose nested parens the port() regex can't
#      match -- so a truthy `if sym_arr_size[si] {` would slip through. ----
src = re.sub(
    r'\b(if|while) ([A-Za-z_@][\w.]*(?:\([^()]*\))?(?:\[[^\]]*\])?) \{',
    r'\1 \2 != 0 {', src)

# ---- 1. discover slab arrays (typed array decls with > 256 elements) ----
DECL = re.compile(r'(?m)^([ \t]*)(uword|ubyte)\[(\d+)\][ \t]+([A-Za-z_]\w*)(.*)$')
slabs = {}          # name -> (esize, base)  (filled with base below)
order = []          # (name, esize, count) in declaration order
for m in DECL.finditer(src):
    etype, count, name = m.group(2), int(m.group(3)), m.group(4)
    if count > SLAB_THRESHOLD:
        esize = 2 if etype == "uword" else 1
        order.append((name, esize, count))

# ---- 2. lay the slab region out just below $F000; memtop = slab base ----
total = sum(esize * count for _, esize, count in order)
slab_base = IO_FLOOR - total
slab_base &= 0xFF00                       # page-align the base
addr = slab_base
for name, esize, count in order:
    slabs[name] = (esize, addr)
    addr += esize * count
assert addr <= IO_FLOOR, "slab region overruns the I/O floor"

NAMES = "|".join(re.escape(n) for n in slabs)


def slab_read(name, inner):
    esize, base = slabs[name]
    if esize == 1:
        return "peek($%04x + (%s))" % (base, inner)
    return "peekw($%04x + (%s)*2)" % (base, inner)


def slab_write(name, inner, rhs):
    esize, base = slabs[name]
    if esize == 1:
        return "poke($%04x + (%s), %s)" % (base, inner, rhs)
    return "pokew($%04x + (%s)*2, %s)" % (base, inner, rhs)


def _balanced(s, j):
    """Given s[j] == '[', return index of the matching ']'."""
    depth = 0; k = j
    while k < len(s):
        if s[k] == "[": depth += 1
        elif s[k] == "]":
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return -1


def _str_spans(code):
    return re.split(r'("(?:[^"\\]|\\.)*")', code)


def _parse_primary(s, p):
    """Parse one primary expression starting at s[p] (skipping leading ws and
    unary prefixes); return its end index. Slab-write RHS is always a single
    primary -- a literal, a var, an `IDENT(args)` call, or an `IDENT[idx]`
    read (possibly nested) -- never a binary expression (verified)."""
    n = len(s)
    while p < n and s[p] in " \t&~-<>":          # skip ws + unary prefixes
        p += 1
    if p >= n:
        return p
    c = s[p]
    if c == "(":                                 # parenthesised group
        return _balanced_paren(s, p) + 1
    if c == "'":                                 # char literal
        q = p + 1
        while q < n and s[q] != "'":
            q += 2 if s[q] == "\\" else 1
        return q + 1
    if c.isdigit() or c == "$":                  # numeric literal
        q = p + 1
        while q < n and (s[q].isalnum()):
            q += 1
        return q
    m = re.match(r"[A-Za-z_]\w*(?:\.\w+)*", s[p:])  # identifier (.field)*
    if not m:
        return p
    q = p + m.end()
    if q < n and s[q] == "(":                    # call
        return _balanced_paren(s, q) + 1
    if q < n and s[q] == "[":                    # array read (maybe nested)
        return _balanced(s, q) + 1
    return q


def _balanced_paren(s, j):
    depth = 0; k = j
    while k < len(s):
        if s[k] == "(": depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return len(s) - 1


def rewrite_code(s):
    """Single pass over a code span: every slab access becomes peek/poke. A
    slab WRITE (`name[idx] = <primary>`) -- which may appear anywhere on the
    line, including inside a one-line `{ ... }` block -- is detected by the
    `=` following the `]`, and its RHS is bounded to a single primary. Indices
    and RHS are rewritten recursively (nested slab reads). Non-slab arrays are
    kept as `name[idx]` (index recursed) for the later byte-index cast."""
    out, i, n = [], 0, len(s)
    while i < n:
        m = re.match(r"[A-Za-z_]\w*", s[i:])
        if m and (i + m.end()) < n and s[i + m.end()] == "[":
            name = m.group(); j = i + m.end()
            k = _balanced(s, j)
            if k < 0:
                out.append(s[i]); i += 1; continue
            idx = rewrite_code(s[j + 1:k])
            if name in slabs:
                am = re.match(r'\s*=\s*(?!=)', s[k + 1:])    # a write?
                if am:
                    after = k + 1 + am.end()
                    end = _parse_primary(s, after)
                    rhs = rewrite_code(s[after:end])
                    out.append(slab_write(name, idx, rhs)); i = end
                else:
                    out.append(slab_read(name, idx)); i = k + 1
            else:
                out.append(name + "[" + idx + "]"); i = k + 1
        else:
            out.append(s[i]); i += 1
    return "".join(out)


def slab_line(line):
    code, comment = port_p1._split_comment(line)
    parts = _str_spans(code)            # protect string literals
    for x in range(0, len(parts), 2):
        parts[x] = rewrite_code(parts[x])
    return "".join(parts) + comment


# ---- 3. apply the slab rewrite, then drop the slab decls ----
src = "".join(slab_line(l) for l in src.splitlines(keepends=True))
# replace each slab decl line with its base-address const (keep trailing comment)
def _decl_to_const(m):
    name = m.group(4)
    if name in slabs:
        return "%sconst uword %s = $%04x%s" % (m.group(1), name, slabs[name][1], m.group(5))
    return m.group(0)
src = DECL.sub(_decl_to_const, src)

# ---- 4. run the shared upstream fixups ----
final = port_p1.port(src)
open(out_p8, "w").write(final)

# ---- 5. emit a .properties whose memtop is the slab base ----
props = open(base_props).read()
props = re.sub(r'(?m)^memtop\s*=.*$', "memtop = $%04x" % slab_base, props)
open(out_props, "w").write(props)

print("wrote %s (%d slabs, %d B, base $%04x, memtop $%04x)"
      % (out_p8, len(slabs), total, slab_base, slab_base))
for name, esize, count in order:
    print("    %-14s %s[%d]  base $%04x" % (name, "uword" if esize == 2 else "ubyte",
                                            count, slabs[name][1]))
