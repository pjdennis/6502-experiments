"""On-target expression parser equivalence test (Phase 6, M2a).

Builds `p1/expr.p8` (the Prog8 expression-parser port) with the host p8c
+ vasm, runs it on the emulator over single-expression inputs, and
asserts the AST S-expression it writes is byte-identical to the Python
oracle (p8c/serialize.py::ser applied to IterParser.parse_expr).

M2a covers atoms (int/str/bool/ident incl. dotted), prefix unary
(- ~ not), binary operators with the full precedence ladder, and
parentheses. Calls, indexing, @() and &name are M2b; the EXPRESSIONS
corpus entries that use them are filtered out here and re-enabled when
expr.p8 grows.

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
EXPR_SRC = P1 / "expr.p8"

sys.path.insert(0, str(PROG8))
sys.path.insert(0, str(PROG8 / "tests"))

from p8c.lex import lex  # noqa: E402
from p8c.iter_parse import IterParser  # noqa: E402
from p8c.serialize import ser  # noqa: E402
from test_iter_parse import EXPRESSIONS  # noqa: E402

_CALL = re.compile(r"[A-Za-z_]\w*\s*\(")


def _m2a_subset() -> list[str]:
    """EXPRESSIONS entries within the M2a grammar (no call/index/@/&)."""
    out = []
    for e in EXPRESSIONS:
        if "[" in e or "@" in e or "&" in e:
            continue
        if _CALL.search(e):
            continue
        out.append(e)
    return out


def _have_vasm() -> bool:
    return shutil.which("vasm6502_oldstyle") is not None


@unittest.skipUnless(_have_vasm(), "vasm6502_oldstyle not on PATH")
@unittest.skipUnless(EMU.exists(), f"emulator not built at {EMU}")
class ExprEquivalence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = Path(tempfile.mkdtemp(prefix="p1_expr_"))
        s_path = cls.workdir / "expr.s"
        cls.expr_bin = cls.workdir / "expr.bin"
        r = subprocess.run(
            [sys.executable, "-m", "p8c", str(EXPR_SRC), "-o", str(s_path)],
            capture_output=True, text=True, cwd=str(PROG8))
        assert r.returncode == 0, f"p8c failed:\n{r.stdout}\n{r.stderr}"
        r = subprocess.run(
            ["vasm6502_oldstyle", "-Fbin", "-dotdir", "-ignore-mult-inc",
             "-esc", "-wfail", "-o", str(cls.expr_bin), str(s_path)],
            capture_output=True, text=True)
        assert r.returncode == 0, f"vasm failed:\n{r.stdout}\n{r.stderr}"

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def _oracle(self, src: str) -> str:
        node = IterParser(lex(src, "<t>"), "<t>").parse_expr()
        return "\n".join(ser(node)) + "\n"

    def _ontarget(self, src: str) -> str:
        inp = self.workdir / "in.p8"
        out = self.workdir / "out.sexp"
        inp.write_text(src)
        r = subprocess.run(
            [str(EMU), str(self.expr_bin), str(inp), str(out), "--no-dump"],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0,
                         msg=f"emulator expr failed on {src!r}:\n"
                             f"{r.stdout}\n{r.stderr}")
        return out.read_text()

    def test_m2a_expressions(self):
        subset = _m2a_subset()
        self.assertGreater(len(subset), 20, "M2a subset unexpectedly small")
        for src in subset:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"AST serialization differs for {src!r}")


if __name__ == "__main__":
    unittest.main()
