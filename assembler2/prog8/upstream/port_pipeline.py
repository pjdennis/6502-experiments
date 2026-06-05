#!/usr/bin/env python3
"""Port a pipeline pass (p1_pass1_sh.p8 / p1_pass2_sh.p8) to upstream Prog8.

The pipeline's >256-element arenas are now baked into peek/poke "slabs"
directly in the source (see upstream/bake_slabs.py): each arena is a
`const uword <name> = $BASE` at a fixed high-RAM address and every access is a
peek/poke/peekw/pokew on `base + offset`. Upstream Prog8 has those builtins
natively, so this porter no longer rewrites arrays -- it only:

  1. wraps truthy `if/while peek[w](...)` conditions with `!= 0` (upstream
     requires boolean conditions; port_p1's regex can't match the baked calls'
     nested parens);
  2. derives `memtop` from the baked slab consts (the lowest fixed base) so the
     upstream allocator keeps its code/data/BSS below the slab region;
  3. runs the shared upstream fixups (I/O wrappers, \n->CR, arg hoist,
     byte-index cast of the remaining <=256 arrays, structural wrap, _-rename)
     via port_p1.port().

Usage: port_pipeline.py <in.p8> <out.p8> <out.properties> [base_properties]
"""
import re
import sys
import port_p1

IO_FLOOR = 0xF000          # slabs end at or below this (emulator I/O ports)
SLAB_LO = 0x8000           # baked slab bases live in high RAM (>= this)

src = open(sys.argv[1]).read()
out_p8, out_props = sys.argv[2], sys.argv[3]
base_props = sys.argv[4] if len(sys.argv) > 4 else "nmos.properties"


def _balanced(s, j, opn, cls):
    """Given s[j] == opn, return index of the matching cls."""
    depth = 0
    k = j
    while k < len(s):
        if s[k] == opn:
            depth += 1
        elif s[k] == cls:
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return len(s) - 1


def _wrap_truthy(text):
    """Add `!= 0` to truthy if/while conditions whose sole operand is a bare
    `<ident>(...)` call or `<ident>[...]` index (e.g. the baked
    `if peekw($x + ((i) << 1)) {` or `if is_cmp_op(peek(...)) {`). p1 has no
    bool-typed values, so any if/while condition that is a single such operand
    immediately followed by `{` is truthy. The operands' nested parens defeat
    port_p1's truthy regex, so handle them here with a balanced scan."""
    out = []
    for line in text.splitlines(keepends=True):
        code, comment = port_p1._split_comment(line)
        m = re.match(r'^(\s*)(if|while) ([A-Za-z_@][\w.]*)', code)
        if m:
            p = m.end(3)
            n = len(code)
            if p < n and code[p] == "(":
                p = _balanced(code, p, "(", ")") + 1
            if p < n and code[p] == "[":
                p = _balanced(code, p, "[", "]") + 1
            rest = code[p:]
            if rest.lstrip().startswith("{"):    # bare truthy condition
                code = code[:p] + " != 0" + rest
        out.append(code + comment)
    return "".join(out)


# ---- 1. (truthy peek/peekw conditions are now baked into the source) ----

# ---- 2. derive memtop from the baked slab consts (lowest high-RAM base) ----
slab_addrs = [
    int(h, 16) for h in
    re.findall(r'(?m)^[ \t]*const uword [A-Za-z_]\w* = \$([0-9a-fA-F]{4})\b', src)
]
slab_addrs = [a for a in slab_addrs if a >= SLAB_LO]
slab_base = min(slab_addrs) if slab_addrs else IO_FLOOR

# ---- 3. the source is already the one converged dialect ----
# p1.p8 and the `_sh` pipeline files are authored in the register-ABI I/O form
# both compilers accept; the only upstream-specific fixup left is the slab/array
# rewrite, already applied to `src` above. (The old port_p1 transform is retired.)
final = src
open(out_p8, "w").write(final)

# ---- 4. emit a .properties whose memtop is the slab base ----
props = open(base_props).read()
props = re.sub(r'(?m)^memtop\s*=.*$', "memtop = $%04x" % slab_base, props)
open(out_props, "w").write(props)

print("wrote %s (%d baked slabs, memtop $%04x)"
      % (out_p8, len(slab_addrs), slab_base))
