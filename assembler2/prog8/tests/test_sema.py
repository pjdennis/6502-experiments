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


class SemaPhase2(unittest.TestCase):
    def test_var_gets_zp_address_and_mangled_name(self):
        prog = compile_to_sema("ubyte counter\nmain { }")
        sym = prog.module_vars[0].sym
        self.assertIsNotNone(sym)
        self.assertEqual(sym.mangled, "p8v_counter")
        self.assertIsNotNone(sym.address)
        self.assertGreaterEqual(sym.address, 0x40)

    def test_sub_local_mangled_with_sub_name(self):
        prog = compile_to_sema("main { ubyte tmp }")
        body = prog.subs[0].body.stmts
        sym = body[0].sym
        self.assertEqual(sym.mangled, "p8v_main_tmp")

    def test_duplicate_var_in_same_scope_errors(self):
        with self.assertRaises(SemaError):
            compile_to_sema("ubyte x\nubyte x\nmain { }")

    def test_comparison_requires_ubyte_operands(self):
        # Bool == ubyte is a type error.
        with self.assertRaises(SemaError):
            compile_to_sema("main { if true == 0 { } }")

    def test_assignment_type_mismatch_errors(self):
        # Cannot assign string to ubyte.
        with self.assertRaises(SemaError):
            compile_to_sema('%import txt\nubyte x\nmain { x = "abc" }')

    def test_repeat_count_must_be_ubyte(self):
        with self.assertRaises(SemaError):
            compile_to_sema('%import txt\nmain { repeat "boom" { } }')


if __name__ == "__main__":
    unittest.main()
