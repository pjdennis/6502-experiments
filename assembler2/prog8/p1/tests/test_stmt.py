"""On-target statement / whole-program parser equivalence test (M3).

Builds `p1/stmt.p8` (the Prog8 statement + program parser port) with the
host p8c + vasm, runs it on the emulator over whole programs, and asserts
the full `(program ...)` AST serialization it writes is byte-identical to
the Python oracle (`p8c --dump-ast`, i.e. p8c/serialize.py::serialize).

stmt.p8 ports the top-level program parser plus the frame-stack statement
driver (parse.py::parse_block_iter) with no recursion: module var decls,
subs (sub/main with params + return type), blocks, if/else, while,
for-in-to, repeat (forever / N), when (multi-value choices + else),
defer, break/continue/return, assignments (incl. augmented, `@()=`,
`arr[i]=`), call statements, and inline `%asm{{...}}`. The arenas are
uword arrays (p8c's 16-bit arrays) so node/token counts exceed 256.

M3's golden corpus is STMT_PROGRAMS; the wider examples corpus (which
adds directives, const/enum/struct, asmsub, ...) is M4.

SKIPs cleanly if vasm6502_oldstyle or the emulator binary are missing.
"""
from __future__ import annotations

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
STMT_SRC = P1 / "stmt.p8"

sys.path.insert(0, str(PROG8))
sys.path.insert(0, str(PROG8 / "tests"))

from test_iter_parse import STMT_PROGRAMS  # noqa: E402


def _have_vasm() -> bool:
    return shutil.which("vasm6502_oldstyle") is not None


@unittest.skipUnless(_have_vasm(), "vasm6502_oldstyle not on PATH")
@unittest.skipUnless(EMU.exists(), f"emulator not built at {EMU}")
class StmtEquivalence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = Path(tempfile.mkdtemp(prefix="p1_stmt_"))
        s_path = cls.workdir / "stmt.s"
        cls.stmt_bin = cls.workdir / "stmt.bin"
        # stmt.p8 keeps its >256-element arenas as the un-slabbed master (so
        # build_p1.py can resize them for p1.p8). p8c no longer compiles arrays
        # larger than 256, so bake those arenas into peek/poke slabs on a temp
        # copy first -- the same transform the committed pipeline passes use.
        baked = cls.workdir / "stmt.p8"
        baked.write_text(STMT_SRC.read_text())
        r = subprocess.run(
            [sys.executable, str(PROG8 / "upstream" / "bake_slabs.py"),
             str(baked)], capture_output=True, text=True)
        assert r.returncode == 0, f"bake_slabs failed:\n{r.stdout}\n{r.stderr}"
        r = subprocess.run(
            [sys.executable, "-m", "p8c", "--target", "nmos",
             str(baked), "-o", str(s_path)],
            capture_output=True, text=True, cwd=str(PROG8))
        assert r.returncode == 0, f"p8c failed:\n{r.stdout}\n{r.stderr}"
        r = subprocess.run(
            ["vasm6502_oldstyle", "-Fbin", "-dotdir", "-ignore-mult-inc",
             "-esc", "-wfail", "-o", str(cls.stmt_bin), str(s_path)],
            capture_output=True, text=True)
        assert r.returncode == 0, f"vasm failed:\n{r.stdout}\n{r.stderr}"

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.workdir, ignore_errors=True)

    def _oracle(self, src: str) -> str:
        inp = self.workdir / "in.p8"
        inp.write_text(src)
        r = subprocess.run(
            [sys.executable, "-m", "p8c", str(inp), "--dump-ast"],
            capture_output=True, text=True, cwd=str(PROG8))
        self.assertEqual(r.returncode, 0,
                         msg=f"oracle failed on {src!r}:\n{r.stdout}\n{r.stderr}")
        return r.stdout

    def _ontarget(self, src: str) -> str:
        inp = self.workdir / "in.p8"
        out = self.workdir / "out.sexp"
        inp.write_text(src)
        r = subprocess.run(
            [str(EMU), str(self.stmt_bin), str(inp), str(out), "--no-dump"],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0,
                         msg=f"emulator stmt failed on {src!r}:\n"
                             f"{r.stdout}\n{r.stderr}")
        return out.read_text()

    def test_stmt_programs(self):
        for src in STMT_PROGRAMS:
            with self.subTest(src=src):
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"program AST serialization differs "
                                     f"for {src!r}")

    def test_examples(self):
        # M4: the whole examples/ corpus -- directives (imports / output /
        # target), const, enum, struct (+ struct instances/arrays),
        # asmsub, inline sub, on top of the M3 statement surface.
        examples = sorted((PROG8 / "examples").glob("*.p8"))
        self.assertGreater(len(examples), 0, "no examples found")
        for p8 in examples:
            with self.subTest(example=p8.name):
                src = p8.read_text()
                self.assertEqual(self._oracle(src), self._ontarget(src),
                                 msg=f"program AST serialization differs "
                                     f"for {p8.name}")

    def test_tinyp8_capacity(self):
        # M5: the on-target parser streams per top-level unit (two passes,
        # arenas reset between subs), so a compiler-sized input fits. The
        # whole 1289-line tinyp8.p8 (~2300 AST lines, biggest sub ~470
        # nodes) parses byte-identically to the host -- the step-5 success
        # criterion (parse the asm-chain-style self-host target).
        tinyp8 = PROG8 / "tinyp8" / "tinyp8.p8"
        self.assertTrue(tinyp8.exists())
        src = tinyp8.read_text()
        self.assertEqual(self._oracle(src), self._ontarget(src),
                         msg="program AST serialization differs for tinyp8.p8")


if __name__ == "__main__":
    unittest.main()
