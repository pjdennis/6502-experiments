"""Codegen unit tests -- substring checks on the emitted .s text.

These are NOT golden tests (those live under tests/snapshots/); they
just assert that the codegen produces the right shape for a given
input. Adding a new feature should add a test here BEFORE adding the
golden snapshot, so we catch obvious regressions on quick local runs.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from p8c.codegen import generate  # noqa: E402
from p8c.lex import lex  # noqa: E402
from p8c.parse import parse  # noqa: E402
from p8c.sema import analyze  # noqa: E402


def compile_text(src: str) -> str:
    prog = parse(lex(src, "<test>"), "<test>")
    analyze(prog)
    return generate(prog, "<test>")


class CodeGenBasics(unittest.TestCase):
    def test_emits_org_directive_for_address(self):
        s = compile_text("%address $8123\nmain { }")
        self.assertIn(".org $8123", s)

    def test_default_org_is_4000(self):
        self.assertIn(".org $4000", compile_text("main { }"))

    def test_jmp_to_main_in_prologue(self):
        self.assertIn("jmp p8s_main", compile_text("main { }"))

    def test_main_falls_through_to_halt_loop(self):
        s = compile_text("main { }")
        self.assertIn(".Lhalt_p8s_main:", s)
        self.assertIn("bra .Lhalt_p8s_main", s)

    def test_txt_print_emits_string_and_jsr(self):
        s = compile_text('%import txt\nmain { txt.print("hi") }')
        self.assertIn("lda #<p8c_str_0", s)
        self.assertIn("ldx #>p8c_str_0", s)
        self.assertIn("jsr display_string", s)
        # String pool with the data:
        self.assertIn("p8c_str_0:", s)
        self.assertIn('"hi"', s)
        self.assertIn(", 0", s)

    def test_lcd_clear_emits_jsr_only(self):
        s = compile_text('%import lcd\nmain { lcd.clear() }')
        self.assertIn("jsr clear_display", s)

    def test_string_pool_only_present_when_strings_used(self):
        self.assertNotIn("string pool", compile_text("main { }"))


if __name__ == "__main__":
    unittest.main()
