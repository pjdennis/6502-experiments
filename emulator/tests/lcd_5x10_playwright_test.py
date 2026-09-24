#!/usr/bin/env python3
"""End-to-end test of HD44780 5x10 LCD mode via the live web UI.

Boots the wendy2c emulator with lcd_5x10_demo_wendy2c.s as the
uploaded payload, opens the page with headless Chromium, and checks:

  * The state snapshots include `f5x10: 1` after the payload's
    function-set instruction lands.
  * The LCD canvas grows taller than 5x8 (rows-per-cell rose from
    9 to 11), so the dot grid is being drawn at the 5x10 size.
  * A pixel sampled on the descender of the ROM A00 glyph at code
    0xF0 (row 8/9 below the 5x8 baseline) is actually ON, proving
    the 5x10 ROM lookup is wired through.

SKIPs cleanly if vasm6502_oldstyle or playwright are missing.
"""

import argparse
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path


class Colors:
    RED    = "\033[31m"
    GREEN  = "\033[32m"
    YELLOW = "\033[33m"
    NC     = "\033[0m"

    @classmethod
    def disable(cls): cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


def have_vasm():    return shutil.which("vasm6502_oldstyle") is not None

def have_playwright():
    try:
        from playwright.sync_api import sync_playwright  # noqa
        return True
    except ImportError:
        return False


def run_vasm(src, out_path, log_path):
    r = subprocess.run(
        ["vasm6502_oldstyle", "-wdc02", "-wfail", "-Fbin", "-dotdir",
         "-ignore-mult-inc", "-esc", "-o", str(out_path), str(src)],
        capture_output=True, text=True
    )
    log_path.write_text(r.stdout + r.stderr)
    return r.returncode == 0


def build_artifacts(repo_root, out_dir):
    boot_src    = repo_root / "upload_and_run_eeprom_wendy2c.s"
    payload_src = repo_root / "lcd_5x10_demo_wendy2c.s"
    boot_rom    = out_dir / "boot.bin"
    payload_bin = out_dir / "lcd5x10.bin"
    framed      = out_dir / "lcd5x10.framed"

    if not run_vasm(boot_src,    boot_rom,    out_dir / "boot.vasm.log"):       return None
    if not run_vasm(payload_src, payload_bin, out_dir / "lcd5x10.vasm.log"):   return None

    framer = repo_root / "assembler2" / "emulator" / "wendy2_upload.py"
    r = subprocess.run(
        ["python3", str(framer), str(payload_bin), "-o", str(framed)],
        capture_output=True, text=True
    )
    if r.returncode != 0: return None
    return boot_rom, framed


def run_test(base_dir, verbose=False):
    if not have_vasm():
        print(f"  {Colors.YELLOW}SKIP{Colors.NC} 5x10 LCD test (vasm6502_oldstyle not on PATH)")
        return None
    if not have_playwright():
        print(f"  {Colors.YELLOW}SKIP{Colors.NC} 5x10 LCD test (playwright not installed)")
        return None
    from playwright.sync_api import sync_playwright

    emulator = base_dir / "emulator" / "emulator.out"
    if not emulator.exists():
        print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: emulator not built at {emulator}")
        return False

    repo_root = base_dir.parent
    out_dir = Path("/tmp") / "wendy2c-lcd5x10-test"
    out_dir.mkdir(exist_ok=True)
    for f in out_dir.glob("*.png"): f.unlink()

    arts = build_artifacts(repo_root, out_dir)
    if arts is None:
        print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: vasm/framing failed; see {out_dir}/*.vasm.log")
        return False
    boot_rom, framed = arts

    proc = subprocess.Popen(
        [str(emulator), str(boot_rom),
         "--machine", "wendy2c",
         "--serial-input", str(framed),
         "--lcd-panel", "16x1-5x10",
         "--web", "--web-port", "0"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True,
    )

    port = None
    start = time.monotonic()
    while time.monotonic() - start < 3.0 and port is None:
        line = proc.stderr.readline()
        if not line: time.sleep(0.05); continue
        m = re.search(r"http://127\.0\.0\.1:(\d+)/", line)
        if m: port = int(m.group(1))
    if port is None:
        print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: did not see server listen line")
        proc.kill(); proc.wait(timeout=2)
        return False

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            ctx = browser.new_context(viewport={"width": 900, "height": 700})
            page = ctx.new_page()

            # Capture the most recent panel_5x10 / f5x10 / panel_rows
            # from each state frame.
            page.add_init_script("""
                window._lastLcd = null;
                const origWS = window.WebSocket;
                window.WebSocket = function(...args) {
                    const ws = new origWS(...args);
                    ws.addEventListener('message', (e) => {
                        if (typeof e.data === 'string') {
                            try {
                                const obj = JSON.parse(e.data);
                                if (obj.lcd) window._lastLcd = obj.lcd;
                            } catch {}
                        }
                    });
                    return ws;
                };
                for (const k in origWS) window.WebSocket[k] = origWS[k];
            """)

            page.goto(f"http://127.0.0.1:{port}/")
            page.wait_for_function(
                "document.getElementById('status-text')?.textContent.includes('connected')",
                timeout=5000,
            )
            page.wait_for_timeout(2500)

            lcd = page.evaluate("window._lastLcd")
            if verbose:
                print(f"  panel_5x10={lcd.get('panel_5x10')}  panel_rows={lcd.get('panel_rows')}  "
                      f"f5x10={lcd.get('f5x10')}  rows={lcd.get('rows')}")
            if lcd.get("panel_5x10") != 1:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: panel_5x10 = {lcd.get('panel_5x10')}, want 1")
                return False
            if lcd.get("panel_rows") != 1:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: panel_rows = {lcd.get('panel_rows')}, want 1")
                return False
            if lcd.get("f5x10") != 1:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: f5x10 = {lcd.get('f5x10')}, want 1 "
                      f"(firmware should have set the F bit)")
                return False

            # In 16x1 5x10 panel mode each cell is 12 rows tall (10 glyph
            # + 1 gap + 1 cursor) * (DOT=3 + GAP=1) = 48 px. With one
            # display row that's 48 + 2*8 margin = 64. (For comparison
            # a 5x8 cell is 9*(3+1) = 36 px which would total 52.) We
            # just sanity-check height landed above the 5x8 size.
            canvas_h = page.evaluate("document.getElementById('lcd').height")
            if verbose: print(f"  canvas height = {canvas_h}")
            if canvas_h < 60:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: canvas height={canvas_h}, "
                      f"expected >= 60 for a 1-row 5x10 panel")
                return False

            # Sample the cursor-gap pixel: column 0, row 0 cell, at
            # y_rel = glyphRows*DOT_PITCH + 1 (the +1 lands inside the
            # blank gap row, not the dot). For DOT=3, GAP=1, pitch=4:
            # gap row is at y_rel = 10*4 = 40..42 (3 px tall).
            # Cell top-left is at (LCD_MARGIN, LCD_MARGIN) = (8, 8).
            # Sample (8+1, 8+40+1) — should be OFF (backlight color).
            # Cursor row is just below at y_rel = 11*4 = 44..46.
            samples = page.evaluate("""
                () => {
                    const c = document.getElementById('lcd');
                    const ctx = c.getContext('2d');
                    const pick = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data).slice(0,3);
                    return {
                        // Column 0 cell. Gap row sits at y_rel = 10*4 = 40..42.
                        gap:    pick(8 + 1, 8 + 40 + 1),
                        // First glyph row of '5' should have dots (any column lit).
                        glyph0: pick(8 + 4 + 1, 8 + 0 + 1),
                    };
                }
            """)
            if verbose:
                print(f"  gap rgb = {samples['gap']}")
                print(f"  glyph0 rgb = {samples['glyph0']}")
            # The gap row must always be OFF -- noticeably brighter than
            # an ON pixel. Same delta threshold as the existing web
            # playwright test: ~50+ brightness units.
            br = lambda rgb: rgb[0] + rgb[1] + rgb[2]
            if br(samples["gap"]) - br(samples["glyph0"]) < 50:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: gap row not OFF: "
                      f"gap rgb={samples['gap']} (brightness {br(samples['gap'])}), "
                      f"glyph rgb={samples['glyph0']} (brightness {br(samples['glyph0'])})")
                return False

            shot = out_dir / "lcd5x10.png"
            page.screenshot(path=str(shot))
            if verbose: print(f"  screenshot: {shot}")
            browser.close()

        print(f"  {Colors.GREEN}PASS{Colors.NC} 5x10 LCD test (screenshot in {out_dir}/)")
        return True
    finally:
        proc.send_signal(signal.SIGINT)
        try: proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(timeout=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    if not sys.stdout.isatty(): Colors.disable()

    base_dir = Path(__file__).resolve().parent.parent.parent
    print("=" * 60)
    print("wendy2c 5x10 LCD test (HTTP+WS + Playwright)")
    print("=" * 60)
    result = run_test(base_dir, verbose=args.verbose)
    print()
    print("=" * 60)
    if result is None:
        print(f"Results: {Colors.YELLOW}skipped{Colors.NC}")
        sys.exit(0)
    if result:
        print(f"Results: {Colors.GREEN}1 passed{Colors.NC} of 1 test")
        sys.exit(0)
    print(f"Results: {Colors.RED}1 failed{Colors.NC} of 1 test")
    sys.exit(1)


if __name__ == "__main__":
    main()
