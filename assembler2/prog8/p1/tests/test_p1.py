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


if __name__ == "__main__":
    unittest.main()
