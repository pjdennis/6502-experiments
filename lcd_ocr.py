#!/usr/bin/env python3
"""
lcd_ocr.py -- Capture, rectify, and decode the wendy2 16x2 LCD from
a webcam image. Pipeline:

  1. Detect the LCD's bright active area (the cyan-blue backlight is
     much brighter than anything else in the captured frame).
  2. Fit a quadrilateral to it and perspective-warp to a canonical
     pixel grid of known size.
  3. Subdivide the warped image into 16 x 2 character cells, each of
     which is 5 x 8 dots.
  4. Sample each dot, threshold against the per-cell background, and
     write the 8-byte glyph for every cell.
  5. Look up each glyph in the HD44780 A00 font ROM to decode text.

Outputs (default under /tmp/lcd-ocr/):
  - raw.jpg, detect_mask.png, warp.png, sample_grid.png : intermediates
  - cells.txt   : 32 cells of hex bytes plus ASCII-art renders
  - text.txt    : the decoded 16x2 string

Commands:
  --capture          take a fresh snapshot via ./snap.sh first
  --input  PATH      use an existing image (default: /mnt/c/temp/wendy2-snap.jpg)
  --calibrate        write calibration.json (corners, cell geometry)
  --debug            keep the intermediates and print verbose state
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT = "/mnt/c/temp/wendy2-snap.jpg"
WORKDIR = Path("/tmp/lcd-ocr")
CALIB_JSON = REPO_ROOT / "lcd_calibration.json"
FONT_HEADER = REPO_ROOT / "assembler2/emulator/chips/hd44780_a00_font.h"

# 16 char columns x 2 char rows, each cell 5 dots wide x 8 dots tall.
LCD_COLS = 16
LCD_ROWS = 2
DOT_COLS = 5
DOT_ROWS = 8

# Canonical post-warp size. The detected bounding rectangle runs from
# the leftmost lit dot's left edge to the rightmost lit dot's right
# edge, so the warp canvas covers exactly the dot grid -- no padding.
# Layout: 16 cells * 5 dots + 15 inter-cell gaps * 1 dot wide,
#          2 rows * 8 dots +  1 inter-row gap   * 1 dot tall.
PX_PER_DOT_W = 6
PX_PER_DOT_H = 6
GAP_DOTS_W = 1   # horizontal inter-cell gap, in dot widths
GAP_DOTS_H = 1   # vertical inter-row gap, in dot heights
WARP_W = (LCD_COLS * DOT_COLS + (LCD_COLS - 1) * GAP_DOTS_W) * PX_PER_DOT_W
WARP_H = (LCD_ROWS * DOT_ROWS + (LCD_ROWS - 1) * GAP_DOTS_H) * PX_PER_DOT_H


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def order_corners(pts: np.ndarray) -> np.ndarray:
    """Return a 4x2 array of corners in TL, TR, BR, BL order."""
    pts = pts.reshape(-1, 2).astype(np.float32)
    cx, cy = pts.mean(axis=0)
    ordered = np.zeros((4, 2), dtype=np.float32)
    for x, y in pts:
        if   x <  cx and y <  cy: ordered[0] = (x, y)  # TL
        elif x >= cx and y <  cy: ordered[1] = (x, y)  # TR
        elif x >= cx and y >= cy: ordered[2] = (x, y)  # BR
        else:                      ordered[3] = (x, y)  # BL
    return ordered


def find_lcd_quad(img_bgr: np.ndarray, debug_dir: Path | None) -> np.ndarray:
    """Return the 4 image-space corners of the LCD active area, ordered
    TL/TR/BR/BL.

    Strategy: the LCD's glass area is dominated by cyan (the back-
    light's color) regardless of which dot cells are lit. Threshold
    in HSV for cyan-ish hues OR for very bright low-saturation pixels
    (the lit dots themselves), keep the largest connected component
    after a moderate close to bridge the inter-cell dark gaps, then
    fit a rotated rectangle. Using minAreaRect rather than approxPoly
    avoids spurious "corners" picked up from bezel-light artefacts."""
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)

    # Calibration capture has every cell lit, so the lit dots define
    # a tight rectangle exactly matching the dot grid -- which is what
    # the sampling later needs. Other bright spots in the frame
    # (breadboard reflections, IC tops under flash) are smaller, so a
    # large close-kernel merges the dot rectangle but leaves stray
    # bright pixels as smaller components; we keep the biggest.
    bright = ((s <= 60) & (v >= 200)).astype(np.uint8) * 255
    # Close horizontally enough to span an inter-cell gap, vertically
    # enough to span an inter-row gap.
    bright = cv2.morphologyEx(bright, cv2.MORPH_CLOSE,
                              cv2.getStructuringElement(cv2.MORPH_RECT, (15, 25)))
    bright = cv2.morphologyEx(bright, cv2.MORPH_OPEN,
                              cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5)))
    mask = bright
    if debug_dir:
        cv2.imwrite(str(debug_dir / "detect_mask.png"), mask)

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                    cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        raise RuntimeError("no LCD-coloured regions found")
    contour = max(contours, key=cv2.contourArea)

    rect = cv2.minAreaRect(contour)
    corners = cv2.boxPoints(rect)
    return order_corners(corners)


def warp_to_canvas(img_bgr: np.ndarray, corners: np.ndarray) -> np.ndarray:
    dst = np.array([
        [0,         0],
        [WARP_W-1,  0],
        [WARP_W-1,  WARP_H-1],
        [0,         WARP_H-1],
    ], dtype=np.float32)
    M = cv2.getPerspectiveTransform(corners, dst)
    return cv2.warpPerspective(img_bgr, M, (WARP_W, WARP_H))


def dot_centre(row: int, col: int, dy: int, dx: int) -> tuple[int, int]:
    """Centre pixel of dot (dy, dx) within cell (row, col) in the warped image."""
    # Translate (row, col, dy, dx) into a flat (dot_row, dot_col) index
    # in the canvas: cell-internal dots are contiguous; the inter-cell
    # gap consumes 1 extra dot slot between adjacent cells.
    dot_col = col * (DOT_COLS + GAP_DOTS_W) + dx
    dot_row = row * (DOT_ROWS + GAP_DOTS_H) + dy
    return (dot_col * PX_PER_DOT_W + PX_PER_DOT_W // 2,
            dot_row * PX_PER_DOT_H + PX_PER_DOT_H // 2)


def extract_cells(warped: np.ndarray, debug_dir: Path | None
                  ) -> list[list[list[int]]]:
    """Return cells[row][col][dy] -- each entry an int with bit-4 as the
    leftmost dot in row dy of the cell at (row, col).

    Sampling: for each dot we take the brightness mean of a 5x5 patch
    centred on the dot. Thresholding is global-Otsu over the entire
    warped image; per-cell Otsu over-fires on cells with few lit
    dots because the minority bright/dim class gets a too-permissive
    threshold."""
    gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
    if debug_dir:
        cv2.imwrite(str(debug_dir / "warp_gray.png"), gray)

    # Global Otsu over the whole rectified LCD -- the lit dots are
    # ~230+ in luma vs the cyan background ~150, so a global split is
    # reliable and stable cell-to-cell.
    _, mask = cv2.threshold(gray, 0, 255,
                            cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    if debug_dir:
        cv2.imwrite(str(debug_dir / "warp_mask.png"), mask)

    overlay = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    cells: list[list[list[int]]] = []
    # 5x5 patch within the 6x6 dot pitch (1px margin on each side
    # avoids picking up the inter-dot dark gap when the warp is a
    # fraction off-grid).
    half_w = max(1, PX_PER_DOT_W // 2 - 1)
    half_h = max(1, PX_PER_DOT_H // 2 - 1)
    for row in range(LCD_ROWS):
        row_cells = []
        for col in range(LCD_COLS):
            glyph = []
            for dy in range(DOT_ROWS):
                bits = 0
                for dx in range(DOT_COLS):
                    cx, cy = dot_centre(row, col, dy, dx)
                    patch = mask[max(0, cy-half_h):cy+half_h+1,
                                 max(0, cx-half_w):cx+half_w+1]
                    on = patch.mean() > 127
                    if on:
                        bits |= 1 << (4 - dx)
                    colour = (0, 255, 0) if on else (0, 0, 255)
                    cv2.circle(overlay, (cx, cy), 1, colour, -1)
                glyph.append(bits)
            row_cells.append(glyph)
        cells.append(row_cells)

    if debug_dir:
        cv2.imwrite(str(debug_dir / "sample_grid.png"), overlay)
    return cells


def render_cell_ascii(glyph: list[int]) -> str:
    lines = []
    for byte in glyph:
        s = ""
        for dx in range(DOT_COLS):
            s += "#" if (byte >> (4 - dx)) & 1 else "."
        lines.append(s)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Font lookup
# ---------------------------------------------------------------------------

_FONT_CACHE: dict[int, tuple[int, ...]] | None = None
def load_font() -> dict[int, tuple[int, ...]]:
    """Return {char_code: (row0..row7)} for character recognition.

    Prefers the per-LCD font captured by calibrate.py (if present),
    which is what the actual panel renders -- the wendy2 LCD module
    differs from the canonical HD44780 A00 ROM in a few cells (e.g.
    '7'). Falls back to parsing the A00 ROM header otherwise."""
    global _FONT_CACHE
    if _FONT_CACHE is not None:
        return _FONT_CACHE

    if CALIB_JSON.exists():
        calib = json.loads(CALIB_JSON.read_text())
        font_data = calib.get("font")
        if font_data:
            _FONT_CACHE = {int(k): tuple(v) for k, v in font_data.items()}
            return _FONT_CACHE

    text = FONT_HEADER.read_text()
    # Look for rows like:  { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },  /* 0xNN */
    # Match an 8-byte glyph row whose trailing comment starts with
    # /* 0xNN -- optional " 'X'" or other annotation may follow.
    pattern = re.compile(
        r"\{\s*(0x[0-9a-fA-F]{2})\s*,\s*(0x[0-9a-fA-F]{2})\s*,"
        r"\s*(0x[0-9a-fA-F]{2})\s*,\s*(0x[0-9a-fA-F]{2})\s*,"
        r"\s*(0x[0-9a-fA-F]{2})\s*,\s*(0x[0-9a-fA-F]{2})\s*,"
        r"\s*(0x[0-9a-fA-F]{2})\s*,\s*(0x[0-9a-fA-F]{2})\s*\}"
        r"\s*,\s*/\*\s*(0x[0-9a-fA-F]{2})\b[^*]*\*/"
    )
    font: dict[int, tuple[int, ...]] = {}
    for m in pattern.finditer(text):
        rows = tuple(int(m.group(i), 16) for i in range(1, 9))
        code = int(m.group(9), 16)
        font[code] = rows
    _FONT_CACHE = font
    return font


def decode_cell(glyph: list[int], font: dict[int, tuple[int, ...]]) -> str:
    target = tuple(glyph)
    # All-zero glyph is most often a space; prefer 0x20 over the
    # CGRAM placeholders 0x00-0x1F which also have empty ROM entries.
    if target == (0,) * 8:
        return " "
    # Exact match in the printable ASCII range wins over any other.
    for code in range(0x20, 0x7f):
        if font.get(code) == target:
            return chr(code)
    # Then any other exact match.
    for code, bits in font.items():
        if bits == target:
            return f"<{code:02x}>"
    # Nearest-neighbour fallback. This LCD module's glyphs differ a few
    # bits from the A00 ROM in some cells (e.g. our '7' renders with a
    # slightly different diagonal), so the threshold has to be loose
    # enough to absorb that without admitting wild guesses. Restrict
    # candidates to the printable range.
    target_arr = np.unpackbits(np.array(glyph, dtype=np.uint8))
    candidates = []
    for code in range(0x20, 0x7f):
        bits = font.get(code)
        if bits is None:
            continue
        cand = np.unpackbits(np.array(bits, dtype=np.uint8))
        dist = int(np.count_nonzero(target_arr != cand))
        candidates.append((dist, code))
    candidates.sort()
    if not candidates:
        return "?"
    best_dist, best_code = candidates[0]
    runner_dist = candidates[1][0] if len(candidates) > 1 else 999
    # Accept if the closest match is decisively better than the runner-
    # up (>=4-bit gap) or extremely close in absolute terms.
    if best_dist <= 4 or (runner_dist - best_dist >= 4 and best_dist <= 12):
        return chr(best_code)
    return "?"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture", action="store_true",
                    help="Run ./snap.sh before processing.")
    ap.add_argument("--input", default=DEFAULT_INPUT,
                    help=f"Input image path (default {DEFAULT_INPUT}).")
    ap.add_argument("--calibrate", action="store_true",
                    help="Save the detected corners to lcd_calibration.json.")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    WORKDIR.mkdir(parents=True, exist_ok=True)

    if args.capture:
        subprocess.run([str(REPO_ROOT / "snap.sh"), args.input],
                       check=True, stdout=subprocess.DEVNULL)

    img = cv2.imread(args.input)
    if img is None:
        print(f"could not read {args.input}", file=sys.stderr)
        return 1
    if args.debug:
        cv2.imwrite(str(WORKDIR / "raw.jpg"), img)

    # Calibration mode redetects from a capture where every cell is lit
    # (lcd_calibrate.s); regular mode reuses the cached corners since
    # the camera doesn't move between runs.
    if args.calibrate or not CALIB_JSON.exists():
        corners = find_lcd_quad(img, WORKDIR if args.debug else None)
    else:
        corners = np.array(json.loads(CALIB_JSON.read_text())["corners"],
                            dtype=np.float32)
    if args.debug:
        annotated = img.copy()
        for i, (x, y) in enumerate(corners):
            cv2.circle(annotated, (int(x), int(y)), 8, (0, 255, 0), 2)
            cv2.putText(annotated, "TL TR BR BL".split()[i],
                        (int(x) + 10, int(y) - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
        cv2.imwrite(str(WORKDIR / "corners.jpg"), annotated)
        print(f"corners: {corners.tolist()}", file=sys.stderr)

    warped = warp_to_canvas(img, corners)
    cv2.imwrite(str(WORKDIR / "warp.png"), warped)

    cells = extract_cells(warped, WORKDIR if args.debug else None)

    # Write cells.txt
    out_cells = WORKDIR / "cells.txt"
    with out_cells.open("w") as f:
        for row in range(LCD_ROWS):
            for col in range(LCD_COLS):
                glyph = cells[row][col]
                hex_bytes = " ".join(f"{b:02x}" for b in glyph)
                f.write(f"cell row={row} col={col:2d}  bytes: {hex_bytes}\n")
                f.write(render_cell_ascii(glyph))
                f.write("\n\n")
    print(f"cells written: {out_cells}")

    # Decode text.
    font = load_font()
    text_lines = []
    for row in range(LCD_ROWS):
        line = "".join(decode_cell(cells[row][col], font)
                       for col in range(LCD_COLS))
        text_lines.append(line)
    text = "\n".join(text_lines)
    out_text = WORKDIR / "text.txt"
    out_text.write_text(text + "\n")
    print("--- decoded text ---")
    print(text)
    print(f"text written:  {out_text}")

    if args.calibrate:
        calib = {
            "corners": corners.tolist(),
            "warp_size": [WARP_W, WARP_H],
            "px_per_dot": [PX_PER_DOT_W, PX_PER_DOT_H],
        }
        CALIB_JSON.write_text(json.dumps(calib, indent=2) + "\n")
        print(f"calibration:   {CALIB_JSON}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
