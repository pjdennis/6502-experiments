"""Parser unit tests."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from p8c.ast import (  # noqa: E402
    Assign, BinOp, Call, If, IntLit, Program, Repeat, StrLit, Sub, VarDecl, While,
)
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


class ParsePhase2(unittest.TestCase):
    def test_module_level_var_decl(self):
        prog = p8("ubyte counter\nmain { }")
        self.assertEqual(len(prog.module_vars), 1)
        vd: VarDecl = prog.module_vars[0]
        self.assertEqual(vd.name, "counter")
        self.assertEqual(vd.type_name, "ubyte")
        self.assertIsNone(vd.init)

    def test_sub_local_var_with_init(self):
        prog = p8("main { ubyte x = $20 }")
        stmt = prog.subs[0].body.stmts[0]
        self.assertIsInstance(stmt, VarDecl)
        self.assertEqual(stmt.name, "x")
        self.assertIsInstance(stmt.init, IntLit)
        self.assertEqual(stmt.init.value, 0x20)

    def test_assignment_and_aug_assign(self):
        prog = p8("ubyte x\nmain { x = $10 x += $05 }")
        body = prog.subs[0].body.stmts
        self.assertIsInstance(body[0], Assign)
        self.assertEqual(body[0].op, "=")
        self.assertIsInstance(body[1], Assign)
        self.assertEqual(body[1].op, "+=")

    def test_if_else(self):
        prog = p8("ubyte x\nmain { if x == 0 { x = 1 } else { x = 2 } }")
        n = prog.subs[0].body.stmts[0]
        self.assertIsInstance(n, If)
        self.assertIsInstance(n.cond, BinOp)
        self.assertEqual(n.cond.op, "==")
        self.assertIsNotNone(n.else_block)

    def test_while_no_else(self):
        prog = p8("ubyte x\nmain { while x < 4 { x = x + 1 } }")
        n = prog.subs[0].body.stmts[0]
        self.assertIsInstance(n, While)
        self.assertEqual(n.cond.op, "<")

    def test_repeat_with_count(self):
        prog = p8("main { repeat 3 { } }")
        n = prog.subs[0].body.stmts[0]
        self.assertIsInstance(n, Repeat)
        self.assertEqual(n.count.value, 3)

    def test_repeat_forever(self):
        prog = p8("main { repeat { } }")
        n = prog.subs[0].body.stmts[0]
        self.assertIsInstance(n, Repeat)
        self.assertIsNone(n.count)

    def test_precedence_additive_higher_than_bitand(self):
        # C-style precedence: + binds tighter than &, so `a + b & c`
        # parses as `(a + b) & c`.
        prog = p8("ubyte a\nubyte b\nubyte c\nmain { a = a + b & c }")
        rhs = prog.subs[0].body.stmts[0].rhs
        self.assertEqual(rhs.op, "&")
        self.assertEqual(rhs.lhs.op, "+")

    def test_parens_override_precedence(self):
        prog = p8("ubyte a\nubyte b\nubyte c\nmain { a = (a + b) & c }")
        rhs = prog.subs[0].body.stmts[0].rhs
        self.assertEqual(rhs.op, "&")
        self.assertEqual(rhs.lhs.op, "+")


if __name__ == "__main__":
    unittest.main()
