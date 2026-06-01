"""Freeze + equivalence tests for the canonical AST serializer (M0).

`p8c/serialize.py` defines the S-expression contract that the eventual
Prog8 on-target parser (`p1`) must reproduce byte-for-byte. This file
nails that contract down three ways:

  1. **Format assertions** -- exact expected strings for representative
     expressions and statements. These are the human-audited definition
     of the format; if the serializer drifts, these fail loudly.

  2. **Serializer equivalence gate** -- for the whole real corpus
     (examples + snapshots + tinyp8 + the STMT_PROGRAMS corpus), the AST
     produced by the *recursive* parser and by the *iterative* parser
     serialize to identical text. This extends the existing
     parser-equivalence evidence (AST diff, codegen diff, fuzz) to the
     serialization layer the port depends on.

  3. **On-disk goldens** -- the serialized EXPRESSIONS and STMT_PROGRAMS
     corpora are frozen into `tests/goldens_sexp/*.sexp`. Re-serializing
     must match the committed bytes. Run with `UPDATE_GOLDENS=1` to
     regenerate after an intentional format change.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from p8c.iter_parse import IterParser  # noqa: E402
from p8c.lex import lex  # noqa: E402
from p8c.parse import Parser, parse  # noqa: E402
from p8c.serialize import serialize, ser  # noqa: E402

# Reuse the very corpora the iterative-parser equivalence tests use, so
# the serializer is frozen over exactly the inputs the port will exercise.
from tests.test_iter_parse import EXPRESSIONS, STMT_PROGRAMS  # noqa: E402

EXAMPLES = ROOT / "examples"
SNAPS = ROOT / "tests" / "snapshots"
TINYP8 = ROOT / "tinyp8" / "tinyp8.p8"
GOLDENS = ROOT / "tests" / "goldens_sexp"


def _ser_expr(src: str) -> str:
    node = IterParser(lex(src, "<t>"), "<t>").parse_expr()
    return "\n".join(ser(node)) + "\n"


def _corpus_files() -> list[Path]:
    paths: list[Path] = []
    for d in (EXAMPLES, SNAPS):
        if d.exists():
            paths.extend(sorted(d.glob("*.p8")))
    if TINYP8.exists():
        paths.append(TINYP8)
    return paths


# ---------------------------------------------------------------------------
# 1. Format assertions -- the human-audited definition of the contract.
# ---------------------------------------------------------------------------

class SerializeFormat(unittest.TestCase):
    def assertExpr(self, src: str, expected: str):
        self.assertEqual(_ser_expr(src), expected + "\n",
                         msg=f"expr serialization for {src!r}")

    def test_atoms(self):
        self.assertExpr("42", "(int 42)")
        self.assertExpr("$ff", "(int 255)")
        self.assertExpr("true", "(bool true)")
        self.assertExpr("false", "(bool false)")
        self.assertExpr("foo", "(id foo)")
        self.assertExpr("a.b.c", "(id a.b.c)")
        self.assertExpr('"hi"', '(str "hi")')
        self.assertExpr("&buf", "(addr buf)")

    def test_string_escaping(self):
        # newline char literal inside a string -> \n; quote/backslash too.
        node = IterParser(lex(r'"a\nb"', "<t>"), "<t>").parse_expr()
        self.assertEqual("\n".join(ser(node)), r'(str "a\nb")')

    def test_unary_minus_distinct_from_binary(self):
        self.assertExpr("-a", "(u-\n  (id a))")
        self.assertExpr("~a", "(~\n  (id a))")
        self.assertExpr("not a", "(not\n  (id a))")

    def test_binop_precedence_tree(self):
        self.assertExpr("a + b * c", "\n".join([
            "(+",
            "  (id a)",
            "  (*",
            "    (id b)",
            "    (id c)))",
        ]))

    def test_call_zero_and_more_args(self):
        self.assertExpr("f()", "(call f)")
        self.assertExpr("f(a, b)", "\n".join([
            "(call f",
            "  (id a)",
            "  (id b))",
        ]))
        self.assertExpr("foo.bar(1)", "\n".join([
            "(call foo.bar",
            "  (int 1))",
        ]))

    def test_index_with_and_without_field(self):
        self.assertExpr("arr[i]", "\n".join([
            "(idx",
            "  (id arr)",
            "  (id i))",
        ]))
        self.assertExpr("tokens[idx].kind", "\n".join([
            "(idx",
            "  (id tokens)",
            "  (id idx)",
            "  .kind)",
        ]))

    def test_memat(self):
        self.assertExpr("@(p)", "(mem\n  (id p))")

    def _ser_prog(self, src: str) -> str:
        return serialize(parse(lex(src, "<t>"), "<t>"))

    def test_program_skeleton(self):
        got = self._ser_prog("main { }")
        self.assertEqual(got, "\n".join([
            "(program",
            "  (address $4000)",
            "  (output raw)",
            "  (target wendy2c)",
            "  (imports)",
            "  (vars)",
            "  (enums)",
            "  (structs)",
            "  (subs",
            "    (subdef main main void",
            "      (params)",
            "      (block))))",
        ]) + "\n")

    def test_if_else_and_assign(self):
        got = self._ser_prog("ubyte x\nmain { if x == 0 { x = 1 } else { x += 2 } }")
        self.assertIn("\n".join([
            "        (if",
            "          (==",
            "            (id x)",
            "            (int 0))",
            "          (block",
            "            (assign =",
            "              (id x)",
            "              (int 1)))",
            "          (block",
            "            (assign +=",
            "              (id x)",
            "              (int 2))))",
        ]), got)

    def test_when_choices_and_else(self):
        got = self._ser_prog(
            'sub f(ubyte c) { when c { $61 -> { return } '
            'else -> { return } } }')
        self.assertIn("\n".join([
            "        (when",
            "          (id c)",
            "          (choice",
            "            (vals",
            "              (int 97))",
            "            (block",
            "              (return)))",
            "          (choice",
            "            (vals)",
            "            (block",
            "              (return))))",
        ]), got)

    def test_defer_and_for(self):
        got = self._ser_prog(
            'ubyte i\nmain { for i in 0 to 3 { defer txt.print("d") } }')
        self.assertIn("\n".join([
            "        (for i",
            "          (int 0)",
            "          (int 3)",
            "          (block",
            "            (defer",
            "              (exprstmt",
            "                (call txt.print",
            '                  (str "d"))))))',
        ]), got)

    def test_enum_struct_imports_directives(self):
        got = self._ser_prog(
            "%target nmos\n%import textio\n"
            "enum E { A, B = 5 }\n"
            "struct P { ubyte x uword y }\n"
            "main { }")
        self.assertIn("  (target nmos)", got)
        self.assertIn("    (import textio)", got)
        self.assertIn("\n".join([
            "    (enum E",
            "      (members",
            "        (A -)",
            "        (B 5)))",
        ]), got)
        self.assertIn("\n".join([
            "    (struct P",
            "      (fields",
            "        (ubyte x)",
            "        (uword y)))",
        ]), got)

    def test_asmsub_and_array_var(self):
        got = self._ser_prog(
            "asmsub putc(ubyte c) = $f009\n"
            "ubyte[4] buf\n"
            "main { }")
        self.assertIn("\n".join([
            "    (var ubyte[4] buf)",
        ]), got)
        self.assertIn("\n".join([
            "    (subdef putc asmsub void",
            "      (params",
            "        (param ubyte c))",
            "      (asmtarget $f009))",
        ]), got)


# ---------------------------------------------------------------------------
# 2. Serializer equivalence gate -- recursive vs iterative parser.
# ---------------------------------------------------------------------------

class SerializeEquivalence(unittest.TestCase):
    def test_programs_serialize_identically(self):
        for src in STMT_PROGRAMS:
            with self.subTest(src=src):
                rec = parse(lex(src, "<t>"), "<t>",
                            iter_expr=False, iter_stmt=False)
                it = parse(lex(src, "<t>"), "<t>", iter_stmt=True)
                self.assertEqual(serialize(rec), serialize(it),
                                 msg=f"serialization mismatch for {src!r}")

    def test_corpus_files_serialize_identically(self):
        files = _corpus_files()
        self.assertGreater(len(files), 0, "no .p8 corpus found")
        for p8 in files:
            with self.subTest(p8=p8.name):
                src = p8.read_text()
                rec = parse(lex(src, p8.name), p8.name,
                            iter_expr=False, iter_stmt=False)
                it = parse(lex(src, p8.name), p8.name, iter_stmt=True)
                self.assertEqual(serialize(rec), serialize(it),
                                 msg=f"serialization mismatch for {p8.name}")

    def test_expressions_serialize_identically(self):
        # Recursive vs iterative expression parser, serialized.
        for src in EXPRESSIONS:
            with self.subTest(src=src):
                rec = Parser(lex(src, "<t>"), "<t>",
                             iter_expr=False, iter_stmt=False).parse_expr()
                it = IterParser(lex(src, "<t>"), "<t>").parse_expr()
                self.assertEqual("\n".join(ser(rec)), "\n".join(ser(it)),
                                 msg=f"serialization mismatch for {src!r}")


# ---------------------------------------------------------------------------
# 3. On-disk goldens -- the frozen bytes of the contract.
# ---------------------------------------------------------------------------

def _expr_corpus_text() -> str:
    parts = []
    for src in EXPRESSIONS:
        parts.append(f";;; {src!r}\n")
        parts.append(_ser_expr(src))
        parts.append("\n")
    return "".join(parts)


def _stmt_corpus_text() -> str:
    parts = []
    for src in STMT_PROGRAMS:
        parts.append(f";;; {src!r}\n")
        parts.append(serialize(parse(lex(src, "<t>"), "<t>")))
        parts.append("\n")
    return "".join(parts)


_GOLDEN_GENERATORS = {
    "expressions.sexp": _expr_corpus_text,
    "programs.sexp": _stmt_corpus_text,
}


class SerializeGoldens(unittest.TestCase):
    def test_goldens_match(self):
        update = os.environ.get("UPDATE_GOLDENS") == "1"
        GOLDENS.mkdir(exist_ok=True)
        for name, gen in _GOLDEN_GENERATORS.items():
            text = gen()
            path = GOLDENS / name
            if update:
                path.write_text(text)
                continue
            with self.subTest(golden=name):
                self.assertTrue(path.exists(),
                                f"missing golden {name}; "
                                f"run with UPDATE_GOLDENS=1 to create it")
                self.assertEqual(text, path.read_text(),
                                 msg=f"serialization drift vs golden {name}")


if __name__ == "__main__":
    unittest.main()
