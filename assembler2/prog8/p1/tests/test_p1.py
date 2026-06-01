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


def _have_vasm() -> bool:
    return shutil.which("vasm6502_oldstyle") is not None


@unittest.skipUnless(_have_vasm(), "vasm6502_oldstyle not on PATH")
@unittest.skipUnless(EMU.exists(), f"emulator not built at {EMU}")
class P1Equivalence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = Path(tempfile.mkdtemp(prefix="p1_codegen_"))
        s_path = cls.workdir / "p1.s"
        cls.p1_bin = cls.workdir / "p1.bin"
        r = subprocess.run(
            [sys.executable, "-m", "p8c", str(P1_SRC), "-o", str(s_path)],
            capture_output=True, text=True, cwd=str(PROG8))
        assert r.returncode == 0, f"p8c failed:\n{r.stdout}\n{r.stderr}"
        r = subprocess.run(
            ["vasm6502_oldstyle", "-Fbin", "-dotdir", "-ignore-mult-inc",
             "-esc", "-wfail", "-o", str(cls.p1_bin), str(s_path)],
            capture_output=True, text=True)
        assert r.returncode == 0, f"vasm failed:\n{r.stdout}\n{r.stderr}"

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


if __name__ == "__main__":
    unittest.main()
