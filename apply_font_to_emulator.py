#!/usr/bin/env python3
"""
apply_font_to_emulator.py -- push the per-LCD captured font into the
emulator's HD44780 A00 ROM tables so the emulator renders text exactly
the way the physical panel does.

Updates the 5x8 and 5x10 ROM arrays in:
  assembler2/emulator/chips/hd44780_a00_font.h
  assembler2/emulator/web/hd44780_a00_font.js

5x8 covers codes 0x20..0xFF; 5x10 covers codes 0xE0..0xFF (only valid
range in HD44780 5x10 single-line mode).

Preserves codes 0x00..0x1F (CGRAM and undefined) as their existing
zero entries, and preserves the original /* 0xNN ... */ trailing
comment on every row so 'M's tag stays "0x4d 'M'", etc.
"""

import base64
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
CALIB_JSON = REPO_ROOT / "lcd_calibration.json"
C_HEADER = REPO_ROOT / "assembler2/emulator/chips/hd44780_a00_font.h"
JS_FILE = REPO_ROOT / "assembler2/emulator/web/hd44780_a00_font.js"

def _row_pattern(n_bytes: int) -> re.Pattern:
    byte_re = r"0x[0-9a-fA-F]{2}"
    bytes_re = r"\s*,\s*".join([byte_re] * n_bytes)
    return re.compile(
        r"(\s*\{\s*)" + bytes_re +
        r"(\s*\}\s*,\s*/\*\s*)(0x[0-9a-fA-F]{2})([^*]*\*/)"
    )


ROW_PATTERN_5X8 = _row_pattern(8)
ROW_PATTERN_5X10 = _row_pattern(10)


def _rewrite_array(text: str, pattern: re.Pattern,
                   font_bytes: dict[int, tuple[int, ...]]) -> str:
    def repl(m: re.Match) -> str:
        open_brace = m.group(1)
        close_brace_and_comment_start = m.group(2)
        code_str = m.group(3)
        comment_tail = m.group(4)
        code = int(code_str, 16)
        glyph = font_bytes.get(code)
        if glyph is None:
            return m.group(0)
        hex_bytes = ", ".join(f"0x{b:02x}" for b in glyph)
        return (open_brace + hex_bytes
                + close_brace_and_comment_start + code_str + comment_tail)
    return pattern.sub(repl, text)


def update_c_header(font_bytes_5x8: dict[int, tuple[int, ...]],
                    font_bytes_5x10: dict[int, tuple[int, ...]]) -> None:
    """Replace 5x8 and 5x10 byte sequences in the C header, preserving
    format and trailing comments."""
    text = C_HEADER.read_text()
    # The 5x8 array ends at "};" before the 5x10 declaration. Split so
    # the 5x8 regex only matches inside the 5x8 array.
    marker = "/* 5x10 patterns"
    if marker not in text:
        raise RuntimeError("could not locate 5x10 section marker in header")
    head, tail = text.split(marker, 1)
    head = _rewrite_array(head, ROW_PATTERN_5X8, font_bytes_5x8)
    tail = marker + _rewrite_array(tail, ROW_PATTERN_5X10, font_bytes_5x10)
    new_text = head + tail

    # Also rewrite the file-level generator header so anyone reading
    # the file can tell it came from a captured panel.
    new_text = re.sub(
        r"/\* GENERATED FROM [^\n]*",
        "/* GENERATED FROM captured wendy2c LCD panel by apply_font_to_emulator.py -- DO NOT EDIT.",
        new_text,
        count=1,
    )

    C_HEADER.write_text(new_text)
    print(f"wrote: {C_HEADER}")


def update_js(font_bytes_5x8: dict[int, tuple[int, ...]],
              font_bytes_5x10: dict[int, tuple[int, ...]]) -> None:
    """Rebuild both base64-encoded font strings in the JS file."""
    raw_5x8 = bytearray(256 * 8)
    for code in range(256):
        glyph = font_bytes_5x8.get(code)
        if glyph is None:
            continue
        for i, b in enumerate(glyph):
            raw_5x8[code * 8 + i] = b
    b64_5x8 = base64.b64encode(bytes(raw_5x8)).decode("ascii")

    # 5x10 array is 32 entries indexed (code - 0xE0).
    raw_5x10 = bytearray(32 * 10)
    for code in range(0xE0, 0x100):
        glyph = font_bytes_5x10.get(code)
        if glyph is None:
            continue
        for i, b in enumerate(glyph):
            raw_5x10[(code - 0xE0) * 10 + i] = b
    b64_5x10 = base64.b64encode(bytes(raw_5x10)).decode("ascii")

    text = JS_FILE.read_text()
    text = re.sub(
        r'(const b64_5x8 = ")[^"]*(";)',
        r'\1' + b64_5x8 + r'\2',
        text,
        count=1,
    )
    text = re.sub(
        r'(const b64_5x10 = ")[^"]*(";)',
        r'\1' + b64_5x10 + r'\2',
        text,
        count=1,
    )
    text = re.sub(
        r"// GENERATED FROM [^\n]*",
        "// GENERATED FROM captured wendy2c LCD panel by apply_font_to_emulator.py -- DO NOT EDIT.",
        text,
        count=1,
    )
    JS_FILE.write_text(text)
    print(f"wrote: {JS_FILE}")


def main() -> int:
    if not CALIB_JSON.exists():
        print(f"no calibration at {CALIB_JSON}; run ./calibrate.py first",
              file=sys.stderr)
        return 1
    calib = json.loads(CALIB_JSON.read_text())
    font_dict = calib.get("font")
    if not font_dict:
        print("calibration JSON has no captured font", file=sys.stderr)
        return 1
    font_bytes_5x8 = {int(code_s): tuple(glyph)
                      for code_s, glyph in font_dict.items()}

    font5x10_dict = calib.get("font5x10", {})
    font_bytes_5x10 = {int(code_s): tuple(glyph)
                       for code_s, glyph in font5x10_dict.items()}

    update_c_header(font_bytes_5x8, font_bytes_5x10)
    update_js(font_bytes_5x8, font_bytes_5x10)
    print(f"updated 5x8: {sum(1 for c in range(256) if c in font_bytes_5x8)} of 256 codes")
    print(f"updated 5x10: {sum(1 for c in range(0xE0, 0x100) if c in font_bytes_5x10)} of 32 codes")
    print("(codes 0x00..0x1F left as zeros -- CGRAM placeholders)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
