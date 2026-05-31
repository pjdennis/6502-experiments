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


class CodeGenPhase2(unittest.TestCase):
    def test_var_address_bindings_emitted_in_prologue(self):
        s = compile_text("ubyte counter\nmain { }")
        self.assertIn("p8v_counter = $40", s)

    def test_assignment_loads_immediate_and_stores(self):
        s = compile_text("ubyte x\nmain { x = $7B }")
        # The immediate-load + store pair is the smoke signal.
        self.assertIn("lda #$7b", s)
        self.assertIn("sta p8v_x", s)

    def test_addition_uses_clc_adc(self):
        s = compile_text("ubyte x\nubyte y\nmain { x = x + y }")
        self.assertIn("lda p8v_x", s)
        self.assertIn("clc", s)
        self.assertIn("adc p8v_y", s)

    def test_subtraction_uses_sec_sbc(self):
        s = compile_text("ubyte x\nubyte y\nmain { x = x - y }")
        self.assertIn("sec", s)
        self.assertIn("sbc p8v_y", s)

    def test_aug_assign_or_emits_ora(self):
        s = compile_text("ubyte x\nmain { x |= $80 }")
        self.assertIn("ora #$80", s)

    def test_if_comparison_branches_with_bne_when_negated(self):
        # `if x == 0` -> bne to else/end (negated branch).
        s = compile_text("ubyte x\nmain { if x == 0 { x = 1 } }")
        self.assertIn("bne ", s)
        self.assertIn("lda #$01", s)

    def test_if_else_has_both_branches(self):
        s = compile_text("ubyte x\nmain { if x == 0 { x = 1 } else { x = 2 } }")
        self.assertIn(".Lelse_", s)
        self.assertIn(".Lendif_", s)

    def test_while_emits_top_and_end_labels(self):
        s = compile_text("ubyte x\nmain { while x < 4 { x = x + 1 } }")
        self.assertIn(".Lwhile_top_", s)
        self.assertIn(".Lwhile_end_", s)
        # `<` (unsigned) negates to `bcs` for the loop-exit branch.
        self.assertIn("bcs ", s)

    def test_repeat_pushes_counter_pulls_and_decrements(self):
        s = compile_text("main { repeat 3 { } }")
        self.assertIn("pha", s)
        self.assertIn("pla", s)
        self.assertIn("sbc #1", s)

    def test_break_inside_loop_emits_jmp(self):
        s = compile_text("ubyte x\nmain { while x < 4 { break } }")
        self.assertIn("jmp .Lwhile_end_", s)

    def test_break_outside_loop_errors(self):
        from p8c.codegen import CodeGenError
        with self.assertRaises(CodeGenError):
            compile_text("main { break }")

    def test_print_ub_loads_then_jsrs_display_hex(self):
        s = compile_text("%import txt\nubyte x\nmain { txt.print_ub(x) }")
        self.assertIn("lda p8v_x", s)
        self.assertIn("jsr display_hex", s)

    def test_uword_init_emits_lo_and_hi_stores(self):
        s = compile_text("uword w = $1234\nmain { }")
        self.assertIn("lda #$34", s)
        self.assertIn("ldy #$12", s)
        self.assertIn("sta p8v_w", s)
        self.assertIn("sty p8v_w+1", s)

    def test_for_loop_emits_init_cmp_beq_inc(self):
        s = compile_text("ubyte i\nmain { for i in 0 to 3 { } }")
        self.assertIn("sta p8v_i", s)
        self.assertIn("cmp #$03", s)
        self.assertIn("beq ", s)
        self.assertIn("inc p8v_i", s)

    def test_peek_lowers_to_absolute_load(self):
        s = compile_text("ubyte x\nmain { x = peek($f001) }")
        self.assertIn("lda $f001", s)
        self.assertIn("sta p8v_x", s)

    def test_poke_lowers_to_absolute_store(self):
        s = compile_text("main { poke($f001, $55) }")
        self.assertIn("lda #$55", s)
        self.assertIn("sta $f001", s)

    def test_print_uw_high_then_low(self):
        s = compile_text("%import txt\nuword w = $abcd\nmain { txt.print_uw(w) }")
        # Two display_hex calls.
        self.assertEqual(s.count("jsr display_hex"), 2)


if __name__ == "__main__":
    unittest.main()
