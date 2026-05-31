"""Parser unit tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from p8c.ast import Call, Program, StrLit, Sub  # noqa: E402
from p8c.lex import lex  # noqa: E402
from p8c.parse import ParseError, parse  # noqa: E402


def p8(src: str) -> Program:
    return parse(lex(src, "<test>"), "<test>")


class ParseBasics(unittest.TestCase):
    def test_empty_program_parses(self):
        prog = p8("")
        self.assertEqual(prog.subs, [])
        self.assertEqual(prog.imports, [])

    def test_address_directive_sets_load_addr(self):
        prog = p8("%address $8000\nmain { }")
        self.assertEqual(prog.address, 0x8000)

    def test_default_address_is_4000(self):
        prog = p8("main { }")
        self.assertEqual(prog.address, 0x4000)

    def test_import_collected_in_order(self):
        prog = p8("%import txt\n%import lcd\nmain { }")
        self.assertEqual(prog.imports, ["txt", "lcd"])

    def test_main_shorthand_creates_sub(self):
        prog = p8("main { }")
        self.assertEqual(len(prog.subs), 1)
        s = prog.subs[0]
        self.assertIsInstance(s, Sub)
        self.assertEqual(s.name, "main")
        self.assertTrue(s.is_main)
        self.assertEqual(s.body.stmts, [])

    def test_dotted_call_in_main(self):
        prog = p8('main { txt.print("hi") }')
        stmt = prog.subs[0].body.stmts[0]
        self.assertEqual(stmt.expr.path, ["txt", "print"])
        self.assertEqual(len(stmt.expr.args), 1)
        self.assertIsInstance(stmt.expr.args[0], StrLit)
        self.assertEqual(stmt.expr.args[0].value, "hi")

    def test_call_with_multiple_args(self):
        prog = p8('main { foo.bar(1, $20, "x") }')
        c: Call = prog.subs[0].body.stmts[0].expr
        self.assertEqual(c.path, ["foo", "bar"])
        self.assertEqual(len(c.args), 3)

    def test_unknown_directive_errors(self):
        with self.assertRaises(ParseError):
            p8("%bogus 5\nmain { }")


if __name__ == "__main__":
    unittest.main()
