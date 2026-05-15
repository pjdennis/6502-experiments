#!/usr/bin/env python3
"""Extract HD44780 ROM Code A00 character bitmaps from the datasheet.

Reads page 17 of the HD44780U datasheet (Table 4) rendered to PNG,
then writes a header file with the 5x8 and 5x10 character patterns.

Usage:
    extract_hd44780_font.py <page17.png> -o <out.h>

Grid layout determined empirically from the 300-DPI render:
  * Table rows start at y=617 with pitch 128 (16 data rows).
  * Columns at x = 522, 622, 722, 822, 923, 1023, ..., 2128.
  * Within a cell each dot is ~10px wide/tall on ~12.5 px pitch.
  * 5x8 chars (cols 0-13) use 8 dot positions starting near y_rel=8.
  * 5x10 chars (cols 14-15) use 10 dot positions starting near y_rel=8.
  * Col 0 (CGRAM placeholders) is skipped -- those cells contain the
    text labels "CG RAM (1).. (8)" instead of glyph data.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def detect_grid(img: np.ndarray) -> tuple[list[int], list[int]]:
    """Locate the 17 column and 17 row boundary lines of Table 4.

    Looks for long runs of dark pixels (table dividers) along each axis.
    Returns (col_edges, row_edges) where each list has 17 entries; cells
    span the half-open interval between consecutive edges.
    """
    h, w = img.shape
    row_dark = (img < 128).sum(axis=1)
    col_dark = (img < 128).sum(axis=0)

    def peaks(arr: np.ndarray, threshold: int, min_gap: int) -> list[int]:
        out: list[int] = []
        last = -min_gap
        for i, v in enumerate(arr):
            if v > threshold and i - last > min_gap:
                out.append(int(i))
                last = i
        return out

    row_edges = peaks(row_dark, threshold=1500, min_gap=20)
    # Trim to the 17 data-table boundaries (header + 16 rows + bottom).
    # The boundaries we want span roughly y=540..2670.
    row_edges = [r for r in row_edges if 540 <= r <= 2680]
    if len(row_edges) < 18:
        raise SystemExit(f"expected >=18 row dividers, got {len(row_edges)}")
    # Use the data-only block: skip the first (header top), keep 17 next.
    row_edges = row_edges[1:18]

    col_edges = peaks(col_dark[300:], threshold=1000, min_gap=40)
    col_edges = [c + 300 for c in col_edges]
    # Expect 17 vertical dividers spanning ~520..2130. Trim outside.
    col_edges = [c for c in col_edges if 500 <= c <= 2140]
    if len(col_edges) < 17:
        raise SystemExit(f"expected >=17 column dividers, got {len(col_edges)}")
    col_edges = col_edges[:17]

    return col_edges, row_edges

# Dot-column centers within a cell (x_rel).
DOT_X_CENTERS = [26, 38, 51, 63, 76]

# Dot-row centers within a cell (y_rel) for 5x8 (8 rows) and 5x10 (10).
DOT_Y_5X8 = [8, 21, 33, 46, 58, 71, 83, 96]
DOT_Y_5X10 = [8, 21, 33, 46, 58, 71, 83, 96, 108, 121]

# A dot is considered lit if the average pixel value in a sample box
# of this radius around its center is below this threshold.
SAMPLE_RADIUS = 3
LIT_THRESHOLD = 128


def is_lit(img: np.ndarray, y_abs: int, x_abs: int) -> bool:
    """Return True if the SAMPLE_RADIUS-square region around (y,x) is dark."""
    y0, y1 = y_abs - SAMPLE_RADIUS, y_abs + SAMPLE_RADIUS + 1
    x0, x1 = x_abs - SAMPLE_RADIUS, x_abs + SAMPLE_RADIUS + 1
    region = img[y0:y1, x0:x1]
    return region.mean() < LIT_THRESHOLD


def extract_glyph(img: np.ndarray, cell_x0: int, cell_y0: int,
                  rows_per_char: int) -> list[int]:
    """Return rows_per_char bytes for the cell whose top-left is (cell_x0,cell_y0).

    Each byte's low 5 bits encode the dot row (bit 4 = leftmost dot,
    bit 0 = rightmost), matching HD44780 CGRAM/CGROM byte layout.
    """
    dot_ys = DOT_Y_5X8 if rows_per_char == 8 else DOT_Y_5X10
    out = []
    for r in range(rows_per_char):
        byte = 0
        for c in range(5):
            if is_lit(img, cell_y0 + dot_ys[r], cell_x0 + DOT_X_CENTERS[c]):
                byte |= 1 << (4 - c)
        out.append(byte)
    return out


def extract_all(img: np.ndarray) -> tuple[list[list[int]], list[list[int]]]:
    """Return (font_5x8, font_5x10).

    font_5x8: 256 entries of 8 bytes each (5x8 patterns for codes 0x00..0xFF).
              Col 0 (CGRAM placeholders, codes 0x00..0x0F mod 16) is left
              blank since the table shows "CG RAM(N)" labels there. The
              same applies to char codes 0x10..0x1F (col 0001) which are
              blank in the chart.
              For codes whose column is 14 or 15, the 5x8 entry is taken
              from the first 8 rows of the 5x10 pattern (datasheet does
              not provide a separate 5x8 form for these codes; in 5x8
              mode the LCD displays them with rows 0..7).
    font_5x10: 32 entries of 10 bytes each, for codes 0xE0..0xFF.
    """
    col_edges, row_edges = detect_grid(img)
    font_5x8 = [[0] * 8 for _ in range(256)]
    font_5x10 = [[0] * 10 for _ in range(32)]
    for col in range(16):
        for row in range(16):
            code = (col << 4) | row
            if col == 0:
                # CGRAM placeholders; leave 0.
                continue
            rows = 10 if col >= 14 else 8
            x0 = col_edges[col]
            y0 = row_edges[row]
            glyph = extract_glyph(img, x0, y0, rows)
            if rows == 10:
                font_5x10[code - 0xE0] = glyph
                # For 5x8 mode display of these codes, take rows 0..7.
                font_5x8[code] = glyph[:8]
            else:
                font_5x8[code] = glyph
    return font_5x8, font_5x10


def emit_js(font_5x8, font_5x10, source: str) -> str:
    """Emit a JS module that exports the A00 font tables.

    Encoded as base64 strings to keep the file compact:
      * font_5x8: 256 chars * 8 bytes = 2048 bytes
      * font_5x10: 32 chars * 10 bytes = 320 bytes
    Bit layout matches the C header (bit 4 = leftmost dot).
    """
    import base64
    blob_5x8 = bytes(b for glyph in font_5x8 for b in glyph)
    blob_5x10 = bytes(b for glyph in font_5x10 for b in glyph)
    b64_5x8 = base64.b64encode(blob_5x8).decode()
    b64_5x10 = base64.b64encode(blob_5x10).decode()
    return (
        f"// GENERATED FROM {source} by extract_hd44780_font.py -- DO NOT EDIT.\n"
        "//\n"
        "// HD44780U Character Generator ROM, code A00 (datasheet Table 4).\n"
        "// font5x8: 256 glyphs * 8 bytes each, indexed by char code.\n"
        "// font5x10: 32 glyphs * 10 bytes each, indexed by (code - 0xE0).\n"
        "// In each byte, bit 4 is the leftmost dot.\n"
        "window.HD44780_A00 = (() => {\n"
        f"  const b64_5x8 = \"{b64_5x8}\";\n"
        f"  const b64_5x10 = \"{b64_5x10}\";\n"
        "  const decode = (s) => Uint8Array.from(atob(s), (ch) => ch.charCodeAt(0));\n"
        "  return { font5x8: decode(b64_5x8), font5x10: decode(b64_5x10) };\n"
        "})();\n"
    )


def emit_header(font_5x8, font_5x10, source: str) -> str:
    lines = [
        f"/* GENERATED FROM {source} by extract_hd44780_font.py -- DO NOT EDIT.",
        " *",
        " * HD44780U Character Generator ROM, code A00 (datasheet Table 4).",
        " * Each 5x8 glyph is 8 bytes; each 5x10 glyph is 10 bytes.",
        " * Bit 4 of each byte is the leftmost dot column.",
        " */",
        "#ifndef EMULATOR_CHIPS_HD44780_A00_FONT_H",
        "#define EMULATOR_CHIPS_HD44780_A00_FONT_H",
        "",
        "#include <stdint.h>",
        "",
        "static const uint8_t hd44780_a00_font_5x8[256][8] = {",
    ]
    for code in range(256):
        bytes_str = ", ".join(f"0x{b:02x}" for b in font_5x8[code])
        comment = ""
        if 0x20 <= code < 0x7F and code != 0x5C and code != 0x7E:
            # Standard ASCII printable; show it.
            c = chr(code)
            if c.isprintable():
                comment = f"  /* 0x{code:02x} '{c}' */"
        if not comment:
            comment = f"  /* 0x{code:02x} */"
        lines.append(f"    {{ {bytes_str} }},{comment}")
    lines.append("};")
    lines.append("")
    lines.append("/* 5x10 patterns for codes 0xE0..0xFF (indexed as code-0xE0). */")
    lines.append("static const uint8_t hd44780_a00_font_5x10[32][10] = {")
    for i in range(32):
        bytes_str = ", ".join(f"0x{b:02x}" for b in font_5x10[i])
        lines.append(f"    {{ {bytes_str} }},  /* 0x{0xE0+i:02x} */")
    lines.append("};")
    lines.append("")
    lines.append("#endif")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("page17_png", help="page 17 rendered to PNG at 300 DPI")
    p.add_argument("-o", "--output", default="-",
                   help="C header output path (default stdout). Pass '' to skip.")
    p.add_argument("--js", default=None,
                   help="optional JS module output path")
    args = p.parse_args()

    img = np.array(Image.open(args.page17_png).convert("L"))
    font_5x8, font_5x10 = extract_all(img)

    if args.output:
        text = emit_header(font_5x8, font_5x10, args.page17_png)
        if args.output == "-":
            sys.stdout.write(text)
        else:
            Path(args.output).write_text(text)

    if args.js:
        js = emit_js(font_5x8, font_5x10, args.page17_png)
        Path(args.js).write_text(js)

    return 0


if __name__ == "__main__":
    sys.exit(main())
