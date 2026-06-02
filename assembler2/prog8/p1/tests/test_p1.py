"""On-target codegen equivalence test (Phase 7).

Builds `p1/p1.p8` (the self-hosting Prog8 compiler) with the host p8c +
vasm, runs it on the emulator over a corpus of `.p8` programs, and asserts
the `.s` assembly it writes is byte-identical to the host oracle
`python3 -m p8c source.p8 -o` -- the only normalization being the
`; source: <path>` comment line (exactly what the snapshot tests
normalize), since the on-target compiler has no host path to echo.

p1.p8 reuses stmt.p8's streaming front-end (lexer + shunting-yard
expression parser + frame-stack statement driver + node arena) and
replaces the AST serializer with a codegen back-end (port of
p8c/codegen.py). See ../PHASE7_DESIGN.md.

Milestone P7-M1: `main { }` (nmos) -> prologue + ZP scratch bindings +
empty p8s_main + the nmos exit epilogue + reset vector.

SKIPs cleanly if vasm6502_oldstyle or the emulator binary are missing.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
P1 = HERE.parent
PROG8 = P1.parent
REPO = PROG8.parents[1]
EMU = REPO / "assembler2" / "emulator" / "emulator.out"
P1_SRC = P1 / "p1.p8"

_SOURCE_LINE = re.compile(r"^; source:.*$", re.MULTILINE)


def _norm(s: str) -> str:
    """Normalize the one location-dependent line (the `; source:` comment)."""
    return _SOURCE_LINE.sub("; source: SRC", s)


# P7-M1 corpus: empty `main { }` (nmos) at a few load addresses, exercising
# the prologue (incl. the .org address), the empty-main skeleton, the nmos
# exit epilogue, and the reset-vector trailer. (The default target is
# wendy2c, whose prologue M1 codegen does not yet emit, so every program
# here is explicitly `%target nmos`.)
M1_PROGRAMS = [
    "%target nmos\n%address $0200\n\nmain {\n}\n",
    "%target nmos\n\nmain {\n}\n",                      # nmos default address -> $0200
    "%target nmos\n%address $1000\n\nmain {\n}\n",
    "%target nmos\n%address $c000\n\nmain {\n}\n",
]

# P7-M2 corpus: module scalar vars (ubyte / byte / uword, in various
# declaration orders) + simple assignment -- leaf RHS (`= literal`,
# `= var`), ubyte/uword widening on word stores, and byte augmented
# assignment (+= -= &= |= ^=) with a leaf operand. Exercises pass S
# (symbol table + ZP bump allocation), the ZP-binding block, and the
# byte/word leaf-expression + store codegen.
M2_PROGRAMS = [
    # all three scalar types, plain leaf assignment + widening
    "%target nmos\n\nubyte x\nubyte y\nuword w\n\n"
    "main {\n    x = 1\n    y = x\n    w = $1234\n    w = x\n    w = y\n}\n",
    # byte type + augmented add of a var
    "%target nmos\n\nbyte a\nbyte b\n\n"
    "main {\n    a = 5\n    b = a\n    a += b\n}\n",
    # every supported byte augmented op, literal + var operands
    "%target nmos\n\nubyte x\nubyte y\n\n"
    "main {\n    x = $10\n    y = 2\n    x += 3\n    x -= 1\n    x += y\n"
    "    x -= y\n    x &= $0f\n    x |= y\n    x ^= 2\n}\n",
    # uword-only program (2-byte ZP slots), word leaf copy
    "%target nmos\n\nuword p\nuword q\n\n"
    "main {\n    p = $beef\n    q = p\n}\n",
    # interleaved types -> non-trivial ZP addresses ($40 ub, $41 uw, $43 ub)
    "%target nmos\n\nubyte a\nuword b\nubyte c\n\n"
    "main {\n    a = 1\n    b = a\n    c = 9\n}\n",
]

# Phase-7 "strings" slice (the p8c string-literal-as-data feature dogfooded
# by p1.p8 itself): a bare string literal assigned to a uword is its pool
# address. Exercises the ND_STR word-leaf codegen (lda #</ldy #> the label,
# numbered in encounter order) and the string-pool trailer (the _escape
# byte-list policy: printable runs, $XX for control / `"` / `\`, ", 0"
# terminator, "0" for the empty string), positioned between main and the
# reset vector.
M3_STR_PROGRAMS = [
    # one string
    "%target nmos\n\nuword s\n\nmain {\n    s = \"hi\"\n}\n",
    # several, in order; escapes (newline) and the empty string
    "%target nmos\n\nuword s\nuword t\n\n"
    'main {\n    s = "hi"\n    t = "a\\nb"\n    s = ""\n}\n',
    # strings interleaved with scalar assignments (label order = encounter)
    "%target nmos\n\nubyte x\nuword msg\n\n"
    'main {\n    x = 1\n    msg = "result: "\n    x += 2\n    msg = "done\\n"\n}\n',
    # every escape the pool emitter special-cases: \\ " \t \r plus a high byte
    "%target nmos\n\nuword s\n\n"
    'main {\n    s = "tab\\there\\"q\\\\b\\r"\n}\n',
    # DUPLICATE strings dedup to one pool label: "x" appears 3x and "y" 2x,
    # interleaved with a unique "z". Labels: x=str_0, y=str_1, z=str_2 (each
    # distinct content interned once, in first-encounter order). Guards that
    # p8c's value-dedup and p1's intern_str_label agree.
    "%target nmos\n\nuword s\n\n"
    'main {\n    s = "x"\n    s = "y"\n    s = "x"\n    s = "z"\n'
    '    s = "y"\n    s = "x"\n}\n',
]

# Phase-7 byte-expression slice: arithmetic / bitwise binops (+ - & | ^) in a
# byte assignment RHS, evaluated on p1's explicit work stack (p8c recurses;
# p1 can't). Covers the leaf-RHS fast path (left-nested chains a+b+c) and the
# generic CPU-stack spill path (a non-leaf RHS, e.g. b + (c + d)), which must
# match the host's dual-scratch-safe sequence (pha / sta __p8c_tmp1 / pla).
# Augmented assignment now shares the same binop emitter.
M3_EXPR_PROGRAMS = [
    # flat leaf op leaf, every supported op, literal + var operands
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    a = b + 1\n    a = b + c\n    a = b - c\n    a = b & c\n"
    "    a = b | 3\n    a = b ^ c\n}\n",
    # left-nested chains (leaf-RHS fast path, no spill)
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = b + c + a\n    a = b + c - d\n    a = ((b | c) & d) ^ a\n}\n",
    # right-nested / parenthesized RHS (generic spill path)
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = (b + c) - (a + 1)\n    a = b + (c + (d + 1))\n"
    "    a = (b - c) + (d - 1)\n}\n",
    # augmented assignment shares the binop emitter
    "%target nmos\nubyte x\nubyte y\n\n"
    "main {\n    x = $10\n    y = 2\n    x += 3\n    x -= y\n    x &= $0f\n"
    "    x |= y\n    x ^= 2\n}\n",
]

# Phase-7 byte mul + shift slice: `*` (via the __p8c_mul_u8 runtime helper,
# emitted between main and the string pool only when used) and the shifts
# `<< >>` -- immediate counts unroll to repeated asl/lsr, variable counts emit
# a runtime loop with a .Lshl_top_N / .Lshl_end_N label pair (the global label
# counter must match p8c's _label_id sequence). Exercises the leaf-RHS path,
# the generic spill path, the dual-scratch pattern, and augmented <<= / >>=.
M3_MULSHIFT_PROGRAMS = [
    # mul: leaf-RHS (literal + var) and the generic spill path
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = b * c\n    a = b * 3\n    a = (b + c) * d\n"
    "    a = d * (b + c)\n}\n",
    # shifts: immediate (unrolled) and variable (loop, label pairs) counts
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = b << 2\n    a = b >> 1\n    a = b << c\n    a = b >> d\n"
    "    a = b << 0\n}\n",
    # the dual-scratch pattern (two shift sub-expressions in one binop) +
    # variable-count shifts in a binop (two label pairs, sequential ids)
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = (b << 3) + (b << 1)\n    a = (b << c) - (b >> d)\n}\n",
    # augmented <<= / >>= (leaf + variable count) alongside mul
    "%target nmos\nubyte x\nubyte y\n\n"
    "main {\n    x = $10\n    y = 2\n    x <<= 3\n    x >>= 1\n    x <<= y\n"
    "    x >>= y\n    y = x * x\n}\n",
]

# Phase-7 byte unary slice: ~ (eor #$ff), - (two's complement: eor #$ff / clc /
# adc #$01). Integrated into the work-stack as a post-operand "apply" task, so
# the operand may itself be a nested expression (~(b+c), -(b*c), ~b+c). (`not`
# is also ported but needs a bool operand -- not reachable until comparisons
# land, so it is not in this corpus.)
M3_UNARY_PROGRAMS = [
    # ~ and - on a leaf operand
    "%target nmos\nubyte a\nubyte b\n\n"
    "main {\n    a = ~b\n    a = -b\n}\n",
    # operand is a nested expression (the work-stack handles the recursion)
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    a = ~(b + c)\n    a = -(b * c)\n    a = ~b + c\n}\n",
    # nested unary + unary mixed with mul/shift
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    a = - -b\n    a = ~b * c\n    a = -(b << 2)\n}\n",
]

# Phase-7 byte comparison slice: == != < <= > >= producing a 0/1 byte value
# (assigned to a ubyte), with the full unsigned branch sequences (incl. the
# extra .Lgt_no_N label for `>`) and the signed paths (SBC + overflow-corrected
# N flag, with .Lsgn_ok_N / .Lsgt_no_N). Signedness comes from BOTH leaf
# operands being the BYTE type (resolved via the symbol table). Also exercises
# `not` of a comparison (now that comparisons produce the bool `not` consumes)
# and a comparison with a nested (non-leaf) operand. Each label pair is
# allocated after the operands evaluate, matching p8c's _label_id order.
M3_CMP_PROGRAMS = [
    # unsigned, every op, leaf operands (var/var and var/literal)
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    a = b == c\n    a = b != c\n    a = b < c\n    a = b <= c\n"
    "    a = b > c\n    a = b >= c\n    a = b < 5\n}\n",
    # signed (both operands byte) -- the SBC / overflow path
    "%target nmos\nubyte a\nbyte s\nbyte t\n\n"
    "main {\n    a = s == t\n    a = s != t\n    a = s < t\n    a = s <= t\n"
    "    a = s > t\n    a = s >= t\n}\n",
    # not of a comparison (bool -> not) + nested (non-leaf) operand
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    a = not (b < c)\n    a = (b + 1) < c\n    a = b > (c - 1)\n}\n",
    # uword operands: p8c's comparison codegen evaluates operands as BYTES
    # (it compares only low bytes -- a p8c limitation; _emit_word_cmp_into_a
    # is unreachable for comparison-as-value), so the existing byte cmp path
    # already matches. Locks that equivalence in.
    "%target nmos\nubyte a\nuword x\nuword y\n\n"
    "main {\n    a = x < y\n    a = x == y\n    a = x >= y\n}\n",
]

# Phase-7 byte logical slice: short-circuit `and` / `or` (port of
# _emit_logical_into_a -- the label pair allocated mid-evaluation, after the
# lhs, and consumed by the tail after the rhs; nesting via a LIFO label-id
# stack) and `xor` (bitwise on 0/1: eval lhs / pha / eval rhs / sta tmp0 / pla
# / eor __p8c_tmp0). Operands must be bool (p8c), so they are comparisons here;
# also exercises nested and/or and `not` of a logical.
M3_LOGICAL_PROGRAMS = [
    # and / or / xor, each over two comparison operands
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = (b < c) and (b > d)\n    a = (b < c) or (b > d)\n"
    "    a = (b == c) xor (c == d)\n}\n",
    # nested and/or (LIFO label-stack discipline) + mixed
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = (b < c) and (c < d) and (b != d)\n"
    "    a = (b < c) or ((c < d) and (b != d))\n}\n",
    # not of a logical
    "%target nmos\nubyte a\nubyte b\nubyte c\nubyte d\n\n"
    "main {\n    a = not ((b < c) and (c < d))\n}\n",
]

# Phase-7 @() memory + &name slice (8-bit memory ops):
#   * @(IntLit) read/write -> direct absolute lda/sta $XXXX.
#   * @(<word leaf>) read/write -> address into __p8c_ptr0, (ptr0),y indirect.
#   * &name (address-of) as a uword value: lda #< / ldy #> the mangled label.
# The address word expression routes through codegen_word_expr (leaves + &name
# for now; the full word evaluator is the 16-bit slice). @() may appear as a
# binop operand (a = @(p) + 1) since the read is a self-contained byte leaf.
M3_MEMAT_PROGRAMS = [
    # @() read: literal, uword-var, and &var addresses
    "%target nmos\nubyte a\nubyte b\nuword p\n\n"
    "main {\n    a = @($d020)\n    a = @(p)\n    a = @(&b)\n}\n",
    # @() write: literal, uword-var, &var; literal and computed RHS
    "%target nmos\nubyte a\nubyte b\nuword p\n\n"
    "main {\n    @($d020) = a\n    @(p) = a\n    @(&b) = 7\n    @(p) = a + 1\n}\n",
    # @() as a binop operand + &name assigned to a uword
    "%target nmos\nubyte a\nubyte b\nuword p\n\n"
    "main {\n    a = @(p) + 1\n    p = &b\n    p = &a\n}\n",
]

# Phase-7 WORD arithmetic/bitwise slice (16-bit): uword + - & | ^ on the word
# work stack (port of _emit_word_operands + _emit_word_binop_into_ay). The LHS
# is held on the CPU stack across the RHS eval (so a RHS reusing the wtmp
# scratch can't clobber it), RHS lands in __p8c_wtmp0, then the op combines
# both bytes with carry (+/-) or per-byte (&|^). ubyte operands widen to uword.
# (Word unary ~/- is a faithful port but p8c's sema rejects it, so untested.)
M3_WORDARITH_PROGRAMS = [
    # each binop, var/var and var/ubyte (widening)
    "%target nmos\nuword w\nuword x\nuword y\nubyte b\n\n"
    "main {\n    w = x + y\n    w = x - y\n    w = x & y\n    w = x | y\n"
    "    w = x ^ y\n    w = x + b\n}\n",
    # left-nested chains and parenthesized (nesting-safety of the CPU-stack LHS)
    "%target nmos\nuword w\nuword x\nuword y\n\n"
    "main {\n    w = x + y + w\n    w = (x + y) - (w + 1)\n"
    "    w = x + (y - w)\n}\n",
    # word augmented assignment (synthetic binop: w op= e -> w = w op e)
    "%target nmos\nuword w\nuword x\n\n"
    "main {\n    w = $1000\n    w += x\n    w -= 1\n    w &= x\n    w |= $00ff\n"
    "    w ^= x\n}\n",
]

# Phase-7 WORD shift slice (16-bit): uword << / >> (port of _emit_word_shl /
# _emit_word_shr). A constant count in [0,16] unrolls the asl/rol (resp.
# lsr/ror) step n&15 times (with the n>=8 "shift a whole byte" special case);
# a variable count stashes the lhs into __p8c_wtmp0 and loops with a
# .Lwshl_top_N / .Lwshl_end_N (resp. wshr) label pair. Includes augmented
# <<= / >>= (the synthetic word binop path).
M3_WORDSHIFT_PROGRAMS = [
    # constant counts: <8, ==8, >8, ==16 (n&15==0 -> no-op), for both directions
    "%target nmos\nuword w\nuword x\n\n"
    "main {\n    w = x << 1\n    w = x << 3\n    w = x << 8\n    w = x << 9\n"
    "    w = x << 16\n    w = x >> 1\n    w = x >> 4\n    w = x >> 8\n"
    "    w = x >> 12\n}\n",
    # variable counts (loop) + a nested lhs
    "%target nmos\nuword w\nuword x\nubyte n\n\n"
    "main {\n    w = x << n\n    w = x >> n\n    w = (x + 1) << 2\n}\n",
    # augmented word shifts (synthetic binop, const + variable)
    "%target nmos\nuword w\nubyte n\n\n"
    "main {\n    w = $0100\n    w <<= 2\n    w >>= 1\n    w <<= n\n    w >>= n\n}\n",
]

# P7-M4 control flow: if / if-else / while + break / continue. Conditions emit
# the compare straight into a (long-safe, inverted-branch) branch -- byte
# unsigned + signed and the 16-bit word compare -- or, for a non-comparison
# cond, materialize 0/1 and branch on zero. The statement driver is a work
# stack (no recursion), so blocks nest arbitrarily.
M4_CONTROL_PROGRAMS = [
    # if (no else), every byte comparison op as the condition
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    if a == b {\n        c = 1\n    }\n    if a < b {\n        c = 2\n    }\n"
    "    if a >= b {\n        c = 3\n    }\n    if a > b {\n        c = 4\n    }\n"
    "    if a <= b {\n        c = 5\n    }\n    if a != b {\n        c = 6\n    }\n}\n",
    # if / else, signed-byte and uword conditions
    "%target nmos\nubyte a\nbyte s\nbyte t\nuword x\nuword y\n\n"
    "main {\n    if s < t {\n        a = 1\n    } else {\n        a = 2\n    }\n"
    "    if x < y {\n        a = 3\n    } else {\n        a = 4\n    }\n}\n",
    # while + break + continue, and a non-comparison condition (a plain var)
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    while a < b {\n        a = a + 1\n        if a == c {\n            break\n        }\n"
    "        if a == 9 {\n            continue\n        }\n        b = b - 1\n    }\n"
    "    while c {\n        c = c - 1\n    }\n}\n",
    # nested if inside if/else inside while
    "%target nmos\nubyte a\nubyte b\nubyte c\n\n"
    "main {\n    while a > b {\n        if c != 0 {\n            if a == b {\n"
    "                a = 7\n            } else {\n                a = 8\n            }\n"
    "        }\n        a = a - 1\n    }\n}\n",
]

# P7-M4 repeat: forever (count 0 -> top/jmp/end) and counted (push count on the
# CPU stack, decrement per iteration via the rep_dec tail, exit at 0; break pops
# the saved counter first). Literal and variable counts, with break/continue.
M4_REPEAT_PROGRAMS = [
    # forever loop with a break
    "%target nmos\nubyte a\nubyte b\n\n"
    "main {\n    repeat {\n        a = a + 1\n        if a == b {\n            break\n        }\n    }\n}\n",
    # counted (literal) loop
    "%target nmos\nubyte a\n\n"
    "main {\n    repeat 10 {\n        a = a + 1\n    }\n}\n",
    # counted (variable) loop with break + continue
    "%target nmos\nubyte a\nubyte b\nubyte n\n\n"
    "main {\n    repeat n {\n        b = b - 1\n        if b == 0 {\n            break\n        }\n"
    "        if b == a {\n            continue\n        }\n        a = a + 1\n    }\n}\n",
]

# P7-M4 for: `for v in lo to hi` (inclusive ubyte range; v is a pre-declared
# var). Init v=lo; compare against hi at for_cont; inc; loop. Literal range,
# variable range, computed hi (the tmp0/tmp1 spill path), break/continue.
M4_FOR_PROGRAMS = [
    # literal range
    "%target nmos\nubyte i\nubyte s\n\n"
    "main {\n    for i in 0 to 9 {\n        s = s + i\n    }\n}\n",
    # variable range + break
    "%target nmos\nubyte i\nubyte s\nubyte lo\nubyte hi\nubyte a\n\n"
    "main {\n    for i in lo to hi {\n        s = s + 1\n        if s == a {\n            break\n        }\n    }\n}\n",
    # computed hi (spill path) + continue
    "%target nmos\nubyte i\nubyte s\nubyte hi\nubyte a\n\n"
    "main {\n    for i in 1 to (hi - 1) {\n        s = s + i\n        if i == 3 {\n            continue\n        }\n        a = a + 1\n    }\n}\n",
]

# P7-M4 when: `when expr { v -> body  v1,v2 -> body  else -> body }`. expr is
# evaluated once (byte -> tmp0, word -> wtmp0); each arm matches its value(s)
# and jumps to its body, else to the next arm; else arm runs on no match.
# Byte + word selectors, multi-value arms, with/without else, and an arm body
# with a nested if (the classify_name shape).
M4_WHEN_PROGRAMS = [
    # byte selector: single + multi-value arms + else
    "%target nmos\nubyte x\nubyte r\n\n"
    "main {\n    when x {\n        1 -> { r = 10 }\n        2, 3 -> { r = 20 }\n"
    "        else -> { r = 99 }\n    }\n}\n",
    # byte selector, no else
    "%target nmos\nubyte x\nubyte r\n\n"
    "main {\n    when x {\n        5 -> { r = 1 }\n        6 -> { r = 2 }\n    }\n}\n",
    # word selector (16-bit value compare) + multi-value + else
    "%target nmos\nuword w\nuword wr\n\n"
    "main {\n    when w {\n        $1000 -> { wr = 1 }\n        $2000, $3000 -> { wr = 2 }\n"
    "        else -> { wr = 9 }\n    }\n}\n",
    # arm bodies with nested control flow
    "%target nmos\nubyte x\nubyte a\nubyte b\nubyte r\n\n"
    "main {\n    when x {\n        1 -> { if a == b { r = 1 } else { r = 2 } }\n"
    "        2 -> { while a < b { a = a + 1 } }\n        else -> { r = 0 }\n    }\n}\n",
]

# P7-M5 subs (slice 1): regular void subs with no params/locals, called as
# statements. Exercises the sub table (register_subs), pass B emission of
# non-main subs in source order, the per-sub return label + rts, and the call
# (jsr p8s_<name>). Bodies use module vars + control flow.
M5_SUB_PROGRAMS = [
    # two subs called from main, bodies touch module vars
    "%target nmos\nubyte x\nubyte y\n\n"
    "sub foo() {\n    x = 5\n}\nsub bar() {\n    y = x + 1\n}\n"
    "main {\n    foo()\n    bar()\n}\n",
    # a sub whose body has control flow + a call from inside a loop
    "%target nmos\nubyte a\nubyte b\n\n"
    "sub bump() {\n    if a < b {\n        a = a + 1\n    }\n}\n"
    "main {\n    a = 0\n    b = 5\n    while a < b {\n        bump()\n    }\n}\n",
    # subs in source order foo, baz, qux -- emission order must match
    "%target nmos\nubyte x\n\n"
    "sub foo() {\n    x = 1\n}\nsub baz() {\n    x = x + 2\n}\nsub qux() {\n    x = x * 3\n}\n"
    "main {\n    foo()\n    baz()\n    qux()\n}\n",
    # string literals in subs declared BEFORE main: pool labels must be
    # numbered in main-first EMISSION order (main's "M"=str_0, then first's
    # "F"=str_1, second's "S"=str_2), not source order. Regression guard
    # for the p8c/p1 string-label ordering divergence.
    "%target nmos\nuword s\n\n"
    'sub first() {\n    s = "F"\n}\nsub second() {\n    s = "S"\n}\n'
    'main {\n    s = "M"\n    first()\n    second()\n}\n',
]

# P7 const slice: `const ubyte/uword NAME = <int>` declares a compile-time
# constant -- no ZP binding, no storage; every use site folds in the literal
# value (p8c does this in its Ident codegen; p1 mirrors it). Folding happens
# only where p8c folds: byte-leaf load (`x = C`), word-leaf load (`w = C`,
# ubyte const widened), and the comparison SPILL path (`if x == C` -> p8c's
# _cmp_leaf_operand returns None for a const, so it spills and folds during the
# full byte-expr eval). p8c does NOT fold a const in arithmetic operands or a
# for-bound (it emits the undefined mangled name there -- a p8c limitation), so
# this corpus avoids those, matching what p1.p8 itself can use.
CONST_PROGRAMS = [
    # byte-leaf + word-leaf folding, no ZP binding for the consts
    "%target nmos\nconst ubyte LO = 5\nconst ubyte HI = 200\n"
    "ubyte a\nuword w\n\n"
    "main {\n    a = LO\n    w = HI\n    a = HI\n}\n",
    # const in comparison conditions (if / while -> spill path folds the const)
    "%target nmos\nconst ubyte K = 7\nubyte a\n\n"
    "main {\n    a = 0\n    if a == K {\n        a = K\n    }\n"
    "    while a == K {\n        a = K\n    }\n}\n",
    # const passed as a call arg (folds via the arg's byte/word leaf eval)
    "%target nmos\nconst ubyte N = 42\nubyte a\n\n"
    "sub id(ubyte v) -> ubyte {\n    return v\n}\n"
    "main {\n    a = id(N)\n}\n",
    # a program whose ONLY module symbols are consts -> no ZP-binding block
    "%target nmos\nconst ubyte A = 1\nconst ubyte B = 2\n\n"
    "main {\n    if A == B {\n    }\n}\n",
]

# P7-M5 subs (slice 2): return values + call-as-value (still no params/locals).
# `return [v]` evaluates v (byte -> A, word -> A:Y) with p8c's pha/pla dance,
# then jmps the per-sub .Lp8s_<name>_ret label; a call in an expression leaves
# its result in A (byte) or A:Y (word, ubyte-returning calls widen with ldy #0).
M5_RET_PROGRAMS = [
    # byte + word returns, call as a value (byte and word context)
    "%target nmos\nubyte a\nuword w\n\n"
    "sub get5() -> ubyte {\n    return 5\n}\nsub dbl() -> ubyte {\n    return a + a\n}\n"
    "sub bigw() -> uword {\n    return $1234\n}\n"
    "main {\n    a = get5()\n    a = dbl() + 1\n    w = bigw()\n    w = get5()\n}\n",
    # conditional return (return inside an if, plus a fall-through return)
    "%target nmos\nubyte a\n\n"
    "sub cls() -> ubyte {\n    if a > 3 {\n        return 1\n    }\n    return 0\n}\n"
    "main {\n    a = cls()\n}\n",
    # void sub with a bare `return` (early exit)
    "%target nmos\nubyte a\nubyte b\n\n"
    "sub maybe() {\n    if a == 0 {\n        return\n    }\n    b = b + 1\n}\n"
    "main {\n    maybe()\n}\n",
]

# P7-M5 subs (slice 3): params + call-with-args. Pass S now allocates each
# sub's params (p8v_<sub>_arg_<name>) in source order, continuing the ZP bump
# after module vars; the symbol table is scope-aware (a sub's params shadow
# module vars). A call evaluates each arg onto the CPU stack, then pops them
# into the param slots in reverse before the jsr (the reentrant-safe order).
M5_PARAM_PROGRAMS = [
    # one ubyte param, used in the body + returned
    "%target nmos\nubyte g\n\n"
    "sub addone(ubyte v) -> ubyte {\n    return v + 1\n}\n"
    "main {\n    g = addone(5)\n}\n",
    # two ubyte params + a uword param
    "%target nmos\nubyte g\nuword gw\n\n"
    "sub store2(ubyte a, ubyte b) {\n    g = a + b\n}\nsub setw(uword w) {\n    gw = w\n}\n"
    "main {\n    store2(3, 4)\n    setw($abcd)\n}\n",
    # three params, arg is an expression / a module var (shadowing check)
    "%target nmos\nubyte g\n\n"
    "sub add3(ubyte a, ubyte b, ubyte c) -> ubyte {\n    return a + b + c\n}\n"
    "main {\n    g = add3(1, 2, g)\n}\n",
]

# P7-M5 subs (slice 4): local variables. Pass S walks each sub body in p8c's
# _walk_block order (depth-first, source order, recursing into if/while/for/
# repeat/when bodies) and allocates each local (p8v_<sub>_<name>) continuing
# the ZP bump after the sub's params. A local declaration with an initializer
# lowers to a store; locals (and params) shadow module vars by scope.
M5_LOCAL_PROGRAMS = [
    # top-level locals in main + a sub, init + use
    "%target nmos\nubyte g\n\n"
    "sub twice(ubyte v) -> ubyte {\n    ubyte r\n    r = v + v\n    return r\n}\n"
    "main {\n    ubyte x\n    x = 3\n    g = twice(x)\n}\n",
    # a local loop var + a local accumulator (for-loop body)
    "%target nmos\nubyte g\n\n"
    "sub compute(ubyte n) -> ubyte {\n    ubyte sum\n    sum = 0\n    ubyte i\n"
    "    for i in 0 to n {\n        sum = sum + i\n    }\n    return sum\n}\n"
    "main {\n    g = compute(5)\n}\n",
    # locals declared INSIDE nested blocks (if / while) -- allocation order
    "%target nmos\nubyte g\nuword gw\n\n"
    "sub nested() {\n    ubyte a\n    a = 1\n    if g > 0 {\n        ubyte b\n"
    "        b = a + g\n        while b > 0 {\n            uword w\n            w = gw + 1\n"
    "            gw = w\n            b = b - 1\n        }\n    }\n    g = a\n}\n"
    "main {\n    nested()\n}\n",
]

# P7-M5 builtins: lsb / msb (uword -> ubyte), peek / poke (literal address),
# mkword (msb,lsb -> uword). Lowered to inline asm, not a jsr. Includes nested
# builtins in another's argument (exercises the reentrancy-safe bi_cn stack)
# and ubyte-result widening in word context.
M5_BUILTIN_PROGRAMS = [
    # lsb / msb / peek / poke / mkword, plain
    "%target nmos\nubyte b\nuword w\n\n"
    "main {\n    w = $1234\n    b = lsb(w)\n    b = msb(w)\n    b = peek($d020)\n"
    "    poke($d021, b)\n    w = mkword($ab, $cd)\n}\n",
    # nested builtins (poke value + mkword arg contain lsb) -- reentrancy
    "%target nmos\nubyte b\nuword w\n\n"
    "main {\n    w = $beef\n    poke($c000, lsb(w) + 1)\n    w = mkword(msb(w), lsb(w))\n}\n",
    # lsb in word context (ubyte result widens with ldy #0)
    "%target nmos\nuword w\nuword v\n\n"
    "main {\n    v = $0102\n    w = lsb(v)\n    w = mkword($00, msb(v))\n}\n",
]

# P7-M5 inline %asm: a `%asm{{ "...\n..." }}` block emits each line of the
# str-pooled text with a 2-space indent. This is how p1.p8's own I/O shim
# subs (out_byte / _read / _argv ...) are written; the param references
# (p8v_<sub>_arg_<name>) resolve to p1's param ZP allocation.
M5_INLINEASM_PROGRAMS = [
    # a shim-style sub whose body is one inline-asm block + a bare two-liner
    "%target nmos\nubyte g\n\n"
    "sub putc(ubyte ch) {\n"
    '    %asm{{ "lda p8v_putc_arg_ch\\nldx #1\\njsr $f024\\nrts" }}\n}\n'
    "sub raw() {\n"
    '    %asm{{ "nop\\nnop" }}\n}\n'
    "main {\n    putc($41)\n    raw()\n    g = 0\n}\n",
]

# P7-M5 asmsub: `asmsub name(params) [-> ret] = $F0xx` declarations + their
# call ABI (0 args -> just jsr; 1 arg -> load into A (ubyte) / A:Y (uword);
# then jsr the $F0xx target). Pass S allocates the asmsub's param slots
# (matching p8c's ZP bump) but does NOT walk a body (there is none).
M5_ASMSUB_PROGRAMS = [
    # void asmsubs with a ubyte arg, and a ubyte-returning one called as a value
    "%target nmos\nubyte g\n\n"
    "asmsub _exit(ubyte code) = $f00f\nasmsub _close(ubyte handle) = $f015\n"
    "asmsub getbyte() -> ubyte = $f006\n"
    "main {\n    g = getbyte()\n    _close(3)\n    _exit(0)\n}\n",
    # a uword-arg asmsub + an asmsub interleaved with a regular inline-asm sub
    "%target nmos\nuword g\n\n"
    "asmsub setw(uword w) = $f024\n"
    "sub helper() {\n"
    '    %asm{{ "nop\\nrts" }}\n}\n'
    "main {\n    setw($1234)\n    helper()\n}\n",
]


def _have_vasm() -> bool:
    return shutil.which("vasm6502_oldstyle") is not None


@unittest.skipUnless(_have_vasm(), "vasm6502_oldstyle not on PATH")
@unittest.skipUnless(EMU.exists(), f"emulator not built at {EMU}")
class P1Equivalence(unittest.TestCase):
    # The emulator injects its file-I/O syscall stub jmp table + routines from
    # $F006 up to ~$F0B0 (over p1.bin once loaded), so p1.bin's code + arenas
    # MUST end below $F006. The read-only string pool is parked ABOVE the stub
    # routines at $F0C0 (see emit_string_pool / p8c's nmos pool .org), so it has
    # its own ceiling: the emulator's argv-string window at $FE00 (ARGV_BASE in
    # stubs.h). We enforce both from the vasm listing. See build_p1.py's
    # ARENA_SIZES note.
    STUB_FLOOR = 0xF006       # code + arenas must end below this
    POOL_CEIL  = 0xFE00       # the relocated pool must end below ARGV_BASE

    @classmethod
    def setUpClass(cls):
        cls.workdir = Path(tempfile.mkdtemp(prefix="p1_codegen_"))
        s_path = cls.workdir / "p1.s"
        lst_path = cls.workdir / "p1.lst"
        cls.p1_bin = cls.workdir / "p1.bin"
        r = subprocess.run(
            [sys.executable, "-m", "p8c", str(P1_SRC), "-o", str(s_path)],
            capture_output=True, text=True, cwd=str(PROG8))
        assert r.returncode == 0, f"p8c failed:\n{r.stdout}\n{r.stderr}"
        r = subprocess.run(
            ["vasm6502_oldstyle", "-Fbin", "-dotdir", "-ignore-mult-inc",
             "-esc", "-wfail", "-L", str(lst_path), "-o", str(cls.p1_bin),
             str(s_path)],
            capture_output=True, text=True)
        assert r.returncode == 0, f"vasm failed:\n{r.stdout}\n{r.stderr}"
        # Ceiling guard, two regions: code + arenas (p8a_/p8s_/p8v_) must end
        # below the stub floor $F006; the relocated string pool (p8c_str_) must
        # end below ARGV_BASE ($FE00). Exclude the reset-vector org at $FFFx.
        code_top = 0
        pool_top = 0
        for m in re.finditer(r"^([0-9A-Fa-f]{4})\s+(p8a_|p8c_str_|p8s_|p8v_)",
                             lst_path.read_text(), re.MULTILINE):
            a = int(m.group(1), 16)
            if a >= 0xFFF0:
                continue
            if m.group(2) == "p8c_str_":
                if a > pool_top:
                    pool_top = a
            elif a > code_top:
                code_top = a
        assert 0 < code_top < cls.STUB_FLOOR, (
            f"p1.bin code+arena top ${code_top:04X} reached the emulator stub "
            f"floor ${cls.STUB_FLOOR:04X}; shrink ARENA_SIZES in build_p1.py")
        assert pool_top < cls.POOL_CEIL, (
            f"p1.bin string-pool top ${pool_top:04X} reached the argv window "
            f"${cls.POOL_CEIL:04X}; the pool outgrew its $F0C0..$FE00 window -- "
            f"raise ARGV_BASE/ports in the emulator, or dedup the pool more")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def _oracle(self, src: str) -> str:
        inp = self.workdir / "in.p8"
        out = self.workdir / "oracle.s"
        inp.write_text(src)
        r = subprocess.run(
            [sys.executable, "-m", "p8c", str(inp), "-o", str(out)],
            capture_output=True, text=True, cwd=str(PROG8))
        self.assertEqual(r.returncode, 0,
                         msg=f"oracle failed on {src!r}:\n{r.stdout}\n{r.stderr}")
        return _norm(out.read_text())

    def _ontarget(self, src: str) -> str:
        inp = self.workdir / "in.p8"
        out = self.workdir / "out.s"
        inp.write_text(src)
        r = subprocess.run(
            [str(EMU), str(self.p1_bin), str(inp), str(out), "--no-dump"],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0,
                         msg=f"emulator p1 failed on {src!r}:\n"
                             f"{r.stdout}\n{r.stderr}")
        return _norm(out.read_text())

    def test_m1_programs(self):
        for src in M1_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m2_programs(self):
        for src in M2_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_str_programs(self):
        for src in M3_STR_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_expr_programs(self):
        for src in M3_EXPR_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_mulshift_programs(self):
        for src in M3_MULSHIFT_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_unary_programs(self):
        for src in M3_UNARY_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_cmp_programs(self):
        for src in M3_CMP_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_logical_programs(self):
        for src in M3_LOGICAL_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_memat_programs(self):
        for src in M3_MEMAT_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_wordarith_programs(self):
        for src in M3_WORDARITH_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m3_wordshift_programs(self):
        for src in M3_WORDSHIFT_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m4_control_programs(self):
        for src in M4_CONTROL_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m4_repeat_programs(self):
        for src in M4_REPEAT_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m4_for_programs(self):
        for src in M4_FOR_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m4_when_programs(self):
        for src in M4_WHEN_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_sub_programs(self):
        for src in M5_SUB_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_const_programs(self):
        for src in CONST_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_ret_programs(self):
        for src in M5_RET_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_param_programs(self):
        for src in M5_PARAM_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_local_programs(self):
        for src in M5_LOCAL_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_builtin_programs(self):
        for src in M5_BUILTIN_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_inlineasm_programs(self):
        for src in M5_INLINEASM_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")

    def test_m5_asmsub_programs(self):
        for src in M5_ASMSUB_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"codegen .s differs for {src!r}")


if __name__ == "__main__":
    unittest.main()
