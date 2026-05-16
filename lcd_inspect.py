#!/usr/bin/env python3
"""
lcd_inspect.py -- visual side-by-side diagnostic for the LCD vision
pipeline.

For the most recent capture (default /mnt/c/temp/wendy2-snap.jpg),
produces /tmp/lcd-ocr/inspect.png: each LCD cell shown as the zoomed
warped pixels on the left, the extracted ASCII art on the right.
Optionally compares against the canonical A00 ROM (--rom) so any
mismatched pixels are highlighted.

Usage:
  ./lcd_inspect.py                    # current snap
  ./lcd_inspect.py --input PATH       # specific image
  ./lcd_inspect.py --capture          # take a fresh snap first
  ./lcd_inspect.py --font             # show every captured-font glyph
                                       (per-LCD font from lcd_calibration.json)
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

import lcd_ocr

REPO_ROOT = Path(__file__).resolve().parent
WORKDIR = lcd_ocr.WORKDIR
SCALE = 8   # warp upscale factor
GUTTER = 4


def glyph_to_art_image(glyph, scale=SCALE):
    """Draw an 8x6 ascii-art-style image of the glyph (5 cols, 8 rows)
    at given scale. ON pixels are white, OFF are dark cyan."""
    img = np.zeros((lcd_ocr.DOT_ROWS * scale, lcd_ocr.DOT_COLS * scale, 3),
                   dtype=np.uint8)
    img[:, :] = (200, 100, 50)  # dim background
    for dy in range(lcd_ocr.DOT_ROWS):
        for dx in range(lcd_ocr.DOT_COLS):
            if (glyph[dy] >> (4 - dx)) & 1:
                y0, y1 = dy * scale, (dy + 1) * scale
                x0, x1 = dx * scale, (dx + 1) * scale
                img[y0:y1, x0:x1] = (255, 255, 255)
    return img


def make_cell_panel(warped, row, col, captured_glyph,
                    reference_glyph=None, scale=SCALE):
    """Composite: (cropped warp at scale x) | (extracted ascii art)
    | (reference if given). Labelled."""
    cell_w = (lcd_ocr.DOT_COLS + lcd_ocr.GAP_DOTS_W) * lcd_ocr.PX_PER_DOT_W
    cell_h = (lcd_ocr.DOT_ROWS + lcd_ocr.GAP_DOTS_H) * lcd_ocr.PX_PER_DOT_H
    x0 = col * cell_w
    y0 = row * cell_h
    # Only crop the dot area (no inter-cell gap on the right).
    dot_w = lcd_ocr.DOT_COLS * lcd_ocr.PX_PER_DOT_W
    dot_h = lcd_ocr.DOT_ROWS * lcd_ocr.PX_PER_DOT_H
    crop = warped[y0:y0 + dot_h, x0:x0 + dot_w]
    crop_big = cv2.resize(crop, (dot_w * scale, dot_h * scale),
                          interpolation=cv2.INTER_NEAREST)
    # Art panels need each dot the same pixel size as the warp's dots
    # so the heights line up for hstack.
    art_scale = lcd_ocr.PX_PER_DOT_H * scale
    art = glyph_to_art_image(captured_glyph, scale=art_scale)

    parts = [crop_big, art]
    if reference_glyph is not None:
        ref = glyph_to_art_image(reference_glyph, scale=art_scale)
        # Highlight differences with a red border on the captured art.
        if captured_glyph != list(reference_glyph):
            cv2.rectangle(art, (0, 0), (art.shape[1] - 1, art.shape[0] - 1),
                          (0, 0, 255), 2)
        parts.append(ref)

    # Add a gutter between parts.
    h = parts[0].shape[0]
    gutter = np.full((h, GUTTER, 3), 30, dtype=np.uint8)
    composite = parts[0]
    for p in parts[1:]:
        composite = np.hstack([composite, gutter, p])
    return composite


def load_rom_font() -> dict[int, tuple[int, ...]]:
    text = (REPO_ROOT / "assembler2/emulator/chips/hd44780_a00_font.h").read_text()
    pat = re.compile(
        r"\{\s*(0x[0-9a-fA-F]{2}(?:,\s*0x[0-9a-fA-F]{2}){7})\s*\}"
        r"\s*,\s*/\*\s*(0x[0-9a-fA-F]{2})\b[^*]*\*/"
    )
    return {int(m.group(2), 16): tuple(int(b, 16)
                                        for b in m.group(1).split(","))
            for m in pat.finditer(text)}


def inspect_capture(input_path: Path, compare_rom: bool, capture: bool) -> None:
    if capture:
        subprocess.run([str(REPO_ROOT / "snap.sh"), str(input_path)],
                       check=True, stdout=subprocess.DEVNULL)

    calib = json.loads(lcd_ocr.CALIB_JSON.read_text())
    corners = np.array(calib["corners"], dtype=np.float32)

    img = cv2.imread(str(input_path))
    if img is None:
        raise RuntimeError(f"no image at {input_path}")
    warped = lcd_ocr.warp_to_canvas(img, corners)
    cells = lcd_ocr.extract_cells(warped, None)

    rom = load_rom_font() if compare_rom else None

    # Decode each cell so we can pick a "reference" glyph from font.
    font = lcd_ocr.load_font()

    panels = []
    for row in range(lcd_ocr.LCD_ROWS):
        row_panels = []
        for col in range(lcd_ocr.LCD_COLS):
            cap = cells[row][col]
            reference = None
            if rom is not None:
                # Pick the printable-ASCII glyph with smallest Hamming
                # distance for visual reference.
                cap_t = tuple(cap)
                best, bestd = None, 999
                for code in range(0x20, 0x7f):
                    bits = rom.get(code)
                    if bits is None: continue
                    d = sum(bin(x ^ y).count('1') for x, y in zip(cap_t, bits))
                    if d < bestd: bestd, best = d, code
                if best is not None:
                    reference = rom[best]
            panel = make_cell_panel(warped, row, col, cap, reference)
            row_panels.append(panel)
        panels.append(row_panels)

    # Compose: each row is a horizontal strip of cell panels separated by
    # gutters; rows are stacked vertically.
    grid_rows = []
    for row in panels:
        h = row[0].shape[0]
        gutter = np.full((h, GUTTER * 2, 3), 30, dtype=np.uint8)
        composite = row[0]
        for p in row[1:]:
            composite = np.hstack([composite, gutter, p])
        grid_rows.append(composite)
    w = max(r.shape[1] for r in grid_rows)
    grid_rows_padded = []
    vgutter = np.full((GUTTER * 4, w, 3), 30, dtype=np.uint8)
    for r in grid_rows:
        if r.shape[1] < w:
            pad = np.full((r.shape[0], w - r.shape[1], 3), 30, dtype=np.uint8)
            r = np.hstack([r, pad])
        grid_rows_padded.append(r)
    montage = grid_rows_padded[0]
    for r in grid_rows_padded[1:]:
        montage = np.vstack([montage, vgutter, r])
    out = WORKDIR / "inspect.png"
    cv2.imwrite(str(out), montage)
    print(f"wrote: {out}  (size {montage.shape[1]}x{montage.shape[0]})")
    print("each cell: [warp pixels | extracted | nearest ROM] -- red border = differs from nearest ROM")


def inspect_font():
    """Show every captured-font glyph as: ROM glyph | captured glyph,
    so you can see exactly which captures differ and how."""
    calib = json.loads(lcd_ocr.CALIB_JSON.read_text())
    font = calib.get("font")
    if not font:
        print("no captured font in lcd_calibration.json", file=sys.stderr)
        return 1
    rom = load_rom_font()

    cells_per_row = 8
    panels_per_glyph = []
    codes = sorted(int(k) for k in font.keys() if 0x20 <= int(k) <= 0x7e)
    for code in codes:
        cap = font[str(code)]
        rom_g = rom.get(code, [0]*8)
        cap_img = glyph_to_art_image(cap)
        rom_img = glyph_to_art_image(rom_g)
        if tuple(cap) != tuple(rom_g):
            cv2.rectangle(cap_img, (0, 0), (cap_img.shape[1]-1, cap_img.shape[0]-1),
                          (0, 0, 255), 2)
        h = cap_img.shape[0]
        # Label at top
        label = np.full((20, cap_img.shape[1] + GUTTER + rom_img.shape[1], 3),
                        30, dtype=np.uint8)
        cv2.putText(label, f"0x{code:02x} {chr(code)}", (4, 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        gutter = np.full((h, GUTTER, 3), 30, dtype=np.uint8)
        pair = np.hstack([cap_img, gutter, rom_img])
        panel = np.vstack([label, pair])
        panels_per_glyph.append(panel)

    # Pad to a uniform size
    max_h = max(p.shape[0] for p in panels_per_glyph)
    max_w = max(p.shape[1] for p in panels_per_glyph)
    padded = []
    for p in panels_per_glyph:
        if p.shape[0] < max_h or p.shape[1] < max_w:
            pad = np.full((max_h, max_w, 3), 30, dtype=np.uint8)
            pad[:p.shape[0], :p.shape[1]] = p
            padded.append(pad)
        else:
            padded.append(p)

    rows = []
    for start in range(0, len(padded), cells_per_row):
        chunk = padded[start:start + cells_per_row]
        gutter = np.full((max_h, GUTTER * 2, 3), 30, dtype=np.uint8)
        composite = chunk[0]
        for p in chunk[1:]:
            composite = np.hstack([composite, gutter, p])
        # Pad short last row
        if composite.shape[1] < cells_per_row * max_w + (cells_per_row - 1) * GUTTER * 2:
            target = cells_per_row * max_w + (cells_per_row - 1) * GUTTER * 2
            pad = np.full((max_h, target - composite.shape[1], 3), 30, dtype=np.uint8)
            composite = np.hstack([composite, pad])
        rows.append(composite)
    vgutter = np.full((GUTTER * 4, rows[0].shape[1], 3), 30, dtype=np.uint8)
    montage = rows[0]
    for r in rows[1:]:
        montage = np.vstack([montage, vgutter, r])

    out = WORKDIR / "font_inspect.png"
    cv2.imwrite(str(out), montage)
    print(f"wrote: {out}  (size {montage.shape[1]}x{montage.shape[0]})")
    print("layout: each panel shows [captured | ROM] for one glyph")
    print("red border = captured differs from ROM")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=lcd_ocr.DEFAULT_INPUT)
    ap.add_argument("--capture", action="store_true")
    ap.add_argument("--font", action="store_true",
                    help="Inspect the captured font (lcd_calibration.json).")
    args = ap.parse_args()

    WORKDIR.mkdir(parents=True, exist_ok=True)
    if args.font:
        inspect_font()
    else:
        inspect_capture(Path(args.input), compare_rom=True, capture=args.capture)
    return 0


if __name__ == "__main__":
    sys.exit(main())
