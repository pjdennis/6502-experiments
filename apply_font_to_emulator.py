#!/usr/bin/env python3
"""
apply_font_to_emulator.py -- push the per-LCD captured font into the
emulator's HD44780 A00 ROM tables so the emulator renders text exactly
the way the physical panel does.

Updates the 5x8 ROM array in:
  assembler2/emulator/chips/hd44780_a00_font.h
  assembler2/emulator/web/hd44780_a00_font.js

The 5x10 array stays untouched; capturing it needs a separate pass
in 5x10 single-line mode (TODO).

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

ROW_PATTERN = re.compile(
    r"(\s*\{\s*)"
    r"0x[0-9a-fA-F]{2}\s*,\s*0x[0-9a-fA-F]{2}\s*,\s*"
    r"0x[0-9a-fA-F]{2}\s*,\s*0x[0-9a-fA-F]{2}\s*,\s*"
    r"0x[0-9a-fA-F]{2}\s*,\s*0x[0-9a-fA-F]{2}\s*,\s*"
    r"0x[0-9a-fA-F]{2}\s*,\s*0x[0-9a-fA-F]{2}"
    r"(\s*\}\s*,\s*/\*\s*)(0x[0-9a-fA-F]{2})([^*]*\*/)"
)


def update_c_header(font_bytes: dict[int, tuple[int, ...]]) -> None:
    """Replace 5x8 byte sequences in the C header, preserve format
    and trailing comments. Only the 5x8 array gets rewritten; the
    5x10 array (codes 0xE0..0xFF, 10 bytes each) is left alone."""
    text = C_HEADER.read_text()
    # The 5x8 array ends at "};" before the 5x10 declaration. Split.
    marker = "/* 5x10 patterns"
    if marker not in text:
        raise RuntimeError("could not locate 5x10 section marker in header")
    head, tail = text.split(marker, 1)
    tail = marker + tail

    def repl(m: re.Match) -> str:
        open_brace = m.group(1)
        close_brace_and_comment_start = m.group(2)
        code_str = m.group(3)
        comment_tail = m.group(4)
        code = int(code_str, 16)
        glyph = font_bytes.get(code)
        if glyph is None:
            return m.group(0)  # untouched
        hex_bytes = ", ".join(f"0x{b:02x}" for b in glyph)
        return (open_brace + hex_bytes
                + close_brace_and_comment_start + code_str + comment_tail)

    new_head = ROW_PATTERN.sub(repl, head)
    new_text = new_head + tail

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


def update_js(font_bytes: dict[int, tuple[int, ...]]) -> None:
    """Rebuild the base64-encoded b64_5x8 string in the JS file from
    the captured glyphs. b64_5x10 stays as-is."""
    raw = bytearray(256 * 8)
    for code in range(256):
        glyph = font_bytes.get(code)
        if glyph is None:
            continue   # leaves zeros in place
        for i, b in enumerate(glyph):
            raw[code * 8 + i] = b
    b64 = base64.b64encode(bytes(raw)).decode("ascii")

    text = JS_FILE.read_text()
    text = re.sub(
        r'(const b64_5x8 = ")[^"]*(";)',
        r'\1' + b64 + r'\2',
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
    font_bytes = {int(code_s): tuple(glyph)
                  for code_s, glyph in font_dict.items()}

    update_c_header(font_bytes)
    update_js(font_bytes)
    print(f"updated {sum(1 for c in range(256) if c in font_bytes)} of 256 codes")
    print("(codes 0x00..0x1F left as zeros -- CGRAM placeholders)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
