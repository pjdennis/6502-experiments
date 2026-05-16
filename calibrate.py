#!/usr/bin/env python3
"""
calibrate.py -- run the LCD vision calibration end-to-end.

Two stages, both saved to lcd_calibration.json:

  geometry    -- uploads lcd_calibrate.s (all 32 cells lit with an
                 all-on CGRAM block), captures, detects the dot grid
                 bounding rectangle, saves the 4 corners.

  font        -- uploads lcd_calibrate_font.s three times (FONT_PAGE
                 0, 1, 2), captures each, extracts every cell's 5x8
                 glyph, maps it to the displayed ASCII code. This is
                 what the panel actually renders -- which differs in
                 a few cells from the canonical A00 ROM table (this
                 LCD module displays '7' with the diagonal one column
                 left of standard, for example).

After font calibration, lcd_ocr.py uses the captured glyphs for
character recognition instead of the ROM table, so on-LCD content
decodes correctly.

Usage:
  ./calibrate.py             # both stages
  ./calibrate.py --geometry  # only the corners
  ./calibrate.py --font      # only the font (geometry must already be saved)
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

import cv2
import numpy as np

import lcd_ocr

REPO_ROOT = Path(__file__).resolve().parent
SNAP_SH = REPO_ROOT / "snap.sh"
CALIB_JSON = lcd_ocr.CALIB_JSON
WORKDIR = lcd_ocr.WORKDIR

GEOMETRY_SRC = REPO_ROOT / "lcd_calibrate.s"
FONT_SRC = REPO_ROOT / "lcd_calibrate_font.s"
BUILD_OUT = REPO_ROOT / "a.out"

VASM = "vasm6502_oldstyle"
VASM_FLAGS = [
    "-quiet", "-wdc02", "-wfail", "-Fbin", "-dotdir",
    "-ignore-mult-inc", "-esc",
]
TRANSFER = REPO_ROOT / "transfer.py"
TRANSFER_BAUD = "115200"

FONT_PAGE_COUNT = 7        # 7 pages of 32 chars cover 0x20..0xFF
CHARS_PER_PAGE = 32
PAGE_BASE_OFFSET = 0x20    # first char on page 0


def build_and_upload(src: Path, defines: dict[str, int] | None = None) -> None:
    cmd = [VASM, *VASM_FLAGS]
    if defines:
        for name, value in defines.items():
            cmd.append(f"-D{name}={value}")
    cmd.extend(["-o", str(BUILD_OUT), str(src)])
    subprocess.run(cmd, check=True)
    subprocess.run(["python3", str(TRANSFER), f"--baudrate={TRANSFER_BAUD}",
                    str(BUILD_OUT)], check=True)


def snap(path: Path) -> None:
    subprocess.run([str(SNAP_SH), str(path)], check=True,
                   stdout=subprocess.DEVNULL)


def load_calib() -> dict:
    if CALIB_JSON.exists():
        return json.loads(CALIB_JSON.read_text())
    return {}


def save_calib(calib: dict) -> None:
    CALIB_JSON.write_text(json.dumps(calib, indent=2) + "\n")
    print(f"saved: {CALIB_JSON}")


# ---------------------------------------------------------------------------
# Stage: geometry
# ---------------------------------------------------------------------------

def calibrate_geometry() -> dict:
    print("--- geometry: uploading lcd_calibrate.s (all-on blocks)")
    build_and_upload(GEOMETRY_SRC)
    # Boot ROM upload-protocol + run takes ~2 s; give it a beat.
    time.sleep(2.0)
    out = WORKDIR / "calib_geom.jpg"
    WORKDIR.mkdir(parents=True, exist_ok=True)
    snap(out)

    img = cv2.imread(str(out))
    if img is None:
        raise RuntimeError(f"snapshot missing: {out}")
    corners = lcd_ocr.find_lcd_quad(img, WORKDIR)
    print(f"corners: {corners.tolist()}")
    return {
        "corners": corners.tolist(),
        "warp_size": [lcd_ocr.WARP_W, lcd_ocr.WARP_H],
        "px_per_dot": [lcd_ocr.PX_PER_DOT_W, lcd_ocr.PX_PER_DOT_H],
    }


# ---------------------------------------------------------------------------
# Stage: font
# ---------------------------------------------------------------------------

def extract_cells_from(path: Path, corners: np.ndarray) -> list[list[list[int]]]:
    img = cv2.imread(str(path))
    if img is None:
        raise RuntimeError(f"snapshot missing: {path}")
    warped = lcd_ocr.warp_to_canvas(img, corners)
    return lcd_ocr.extract_cells(warped, None)


def calibrate_font(corners: np.ndarray) -> dict[int, list[int]]:
    """Cycle through 3 ASCII pages, capture each, and harvest the
    rendered glyph for every character code."""
    font: dict[int, list[int]] = {}
    for page in range(FONT_PAGE_COUNT):
        base = PAGE_BASE_OFFSET + page * CHARS_PER_PAGE
        print(f"--- font page {page}: codes 0x{base:02x}..0x{base + 31:02x}")
        build_and_upload(FONT_SRC, defines={"FONT_PAGE": page})
        time.sleep(2.0)
        out = WORKDIR / f"calib_font_p{page}.jpg"
        snap(out)
        cells = extract_cells_from(out, corners)
        for row in range(lcd_ocr.LCD_ROWS):
            for col in range(lcd_ocr.LCD_COLS):
                code = base + row * lcd_ocr.LCD_COLS + col
                font[code] = cells[row][col]
        print(f"     captured 32 glyphs")
    return font


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--geometry", action="store_true",
                    help="Run only the geometry stage.")
    ap.add_argument("--font", action="store_true",
                    help="Run only the font stage (geometry must already exist).")
    args = ap.parse_args()

    run_geometry = args.geometry or not args.font
    run_font = args.font or not args.geometry

    calib = load_calib()

    if run_geometry:
        geom = calibrate_geometry()
        calib.update(geom)
        save_calib(calib)

    if run_font:
        if "corners" not in calib:
            print("error: geometry not calibrated yet; run --geometry first",
                  file=sys.stderr)
            return 1
        corners = np.array(calib["corners"], dtype=np.float32)
        # Clear any cached font in the module so the font stage starts fresh.
        lcd_ocr._FONT_CACHE = None
        font = calibrate_font(corners)
        # Persist with string keys (json doesn't allow int keys).
        calib["font"] = {str(code): glyph for code, glyph in sorted(font.items())}
        save_calib(calib)
        print(f"--- font: saved {len(font)} glyphs")

    return 0


if __name__ == "__main__":
    sys.exit(main())
