"""Sema unit tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from p8c.lex import lex  # noqa: E402
from p8c.parse import parse  # noqa: E402
from p8c.sema import SemaError, analyze  # noqa: E402


def compile_to_sema(src: str):
    prog = parse(lex(src, "<test>"), "<test>")
    analyze(prog)
    return prog


class SemaBasics(unittest.TestCase):
    def test_main_required(self):
        with self.assertRaises(SemaError) as ctx:
            compile_to_sema("%import txt")
        self.assertIn("main", str(ctx.exception))

    def test_unknown_import_errors(self):
        with self.assertRaises(SemaError):
            compile_to_sema("%import bogusmod\nmain { }")

    def test_unknown_call_errors(self):
        with self.assertRaises(SemaError) as ctx:
            compile_to_sema("%import txt\nmain { whatever.beep() }")
        self.assertIn("whatever.beep", str(ctx.exception))

    def test_resolves_txt_print(self):
        prog = compile_to_sema('%import txt\nmain { txt.print("x") }')
        stmt = prog.subs[0].body.stmts[0]
        sym = stmt.expr.sym
        self.assertIsNotNone(sym)
        self.assertEqual(sym.kind, "extsub")
        self.assertEqual(sym.asm_target, "display_string")

    def test_main_gets_mangled(self):
        prog = compile_to_sema("main { }")
        self.assertEqual(prog.subs[0].mangled, "p8s_main")

    def test_strings_collected_with_labels(self):
        prog = compile_to_sema('%import txt\nmain { txt.print("a") txt.print("b") }')
        self.assertEqual(len(prog.strings), 2)
        self.assertEqual({s.label for s in prog.strings}, {"p8c_str_0", "p8c_str_1"})


if __name__ == "__main__":
    unittest.main()
