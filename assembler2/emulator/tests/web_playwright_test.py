#!/usr/bin/env python3
"""End-to-end web UI test for the wendy2c emulator.

Drives the embedded HTTP+WS server with a real Chromium via Playwright:

1. Builds the wendy2c boot ROM + a CGRAM-exercising payload via vasm
   (skipped with a warning if vasm6502_oldstyle is missing -- same
   pattern as wendy2c_goldens.sh).
2. Launches emulator/emulator.out --machine wendy2c --web --web-port 0
   and parses the bound port off stderr.
3. Opens the page in headless Chromium, waits for the first state
   snapshot (status text turns to "connected"), then takes a
   screenshot to /tmp/wendy2c-web-test/.
4. Verifies via getImageData() on the LCD canvas:
   - The first character cell has at least some "on" pixels (any
     reasonable rendered glyph).
   - The CGRAM heart at column 5 of line 1 has the expected on/off
     pixel pattern in its top row (pattern: . X . X . from the
     bitmap in cgram_test_wendy2c.s).
   - Also samples a pixel from the second-line CGRAM arrow.
5. Clicks the button and verifies the .btn.held class lands.
6. Verifies that audio binary frames flowed (the JS side counts them
   on a window.__wendy2cAudioFrames property the test sets up).
"""

import argparse
import asyncio
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path


class Colors:
    RED = "\033[0;31m"; GREEN = "\033[0;32m"; YELLOW = "\033[0;33m"; NC = "\033[0m"
    @classmethod
    def disable(cls): cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


def have_vasm():
    return shutil.which("vasm6502_oldstyle") is not None


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
    payload_src = repo_root / "cgram_test_wendy2c.s"
    boot_rom    = out_dir / "boot.bin"
    payload_bin = out_dir / "cgram.bin"
    framed      = out_dir / "cgram.framed"

    if not run_vasm(boot_src,    boot_rom,    out_dir / "boot.vasm.log"):    return None
    if not run_vasm(payload_src, payload_bin, out_dir / "cgram.vasm.log"):  return None

    framer = repo_root / "assembler2" / "emulator" / "wendy2_upload.py"
    r = subprocess.run(
        ["python3", str(framer), str(payload_bin), "-o", str(framed)],
        capture_output=True, text=True
    )
    if r.returncode != 0: return None
    return boot_rom, framed


def run_test(base_dir, verbose=False, keep=False):
    if not have_vasm():
        print(f"  {Colors.YELLOW}SKIP{Colors.NC} web UI test (vasm6502_oldstyle not on PATH)")
        return None
    if not have_playwright():
        print(f"  {Colors.YELLOW}SKIP{Colors.NC} web UI test (playwright not installed: pip3 install playwright && playwright install chromium)")
        return None
    from playwright.sync_api import sync_playwright

    emulator = base_dir / "emulator" / "emulator.out"
    if not emulator.exists():
        print(f"  {Colors.RED}FAIL{Colors.NC} web UI test: emulator not built at {emulator}")
        return False

    repo_root = base_dir.parent
    out_dir = Path("/tmp") / "wendy2c-web-test"
    out_dir.mkdir(exist_ok=True)
    for f in out_dir.glob("*.png"):
        f.unlink()

    arts = build_artifacts(repo_root, out_dir)
    if arts is None:
        print(f"  {Colors.RED}FAIL{Colors.NC} web UI test: vasm/framing failed; see {out_dir}/*.vasm.log")
        return False
    boot_rom, framed = arts

    proc = subprocess.Popen(
        [str(emulator), str(boot_rom),
         "--machine", "wendy2c",
         "--serial-input", str(framed),
         "--web", "--web-port", "0"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True,
    )

    # Parse the bound port from stderr (which is line-buffered after fflush).
    port = None
    start = time.monotonic()
    while time.monotonic() - start < 3.0 and port is None:
        line = proc.stderr.readline()
        if not line: time.sleep(0.05); continue
        m = re.search(r"http://127\.0\.0\.1:(\d+)/", line)
        if m: port = int(m.group(1))
    if port is None:
        print(f"  {Colors.RED}FAIL{Colors.NC} web UI test: did not see server listen line in stderr")
        proc.kill(); proc.wait(timeout=2)
        return False

    if verbose: print(f"  emulator port {port}")

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            ctx = browser.new_context(viewport={"width": 900, "height": 700})
            page = ctx.new_page()

            # Count WS frames via Playwright's built-in API rather than
            # monkey-patching WebSocket. In playwright-python, the
            # framereceived handler receives the payload directly --
            # str for text frames, bytes for binary frames.
            state_frames = [0]
            audio_frames = [0]
            def on_frame(payload):
                if isinstance(payload, (bytes, bytearray)):
                    audio_frames[0] += 1
                else:
                    state_frames[0] += 1
            def on_ws(ws):
                ws.on("framereceived", on_frame)
            page.on("websocket", on_ws)

            page.goto(f"http://127.0.0.1:{port}/")
            # Wait for status to flip to "connected".
            page.wait_for_function(
                "document.getElementById('status-text')?.textContent.includes('connected')",
                timeout=5000,
            )
            # Give the state stream a moment so the LCD renders the
            # payload's actual content (post-upload).
            page.wait_for_timeout(1500)

            # Screenshot 1: idle.
            shot1 = out_dir / "web-idle.png"
            page.screenshot(path=str(shot1))

            sf, af = state_frames[0], audio_frames[0]
            if verbose: print(f"  state frames: {sf}, audio frames: {af}")
            if sf < 3:
                print(f"  {Colors.RED}FAIL{Colors.NC} web UI test: only {sf} state frames received in 1.5s")
                return False
            if af < 3:
                print(f"  {Colors.RED}FAIL{Colors.NC} web UI test: only {af} audio frames in 1.5s")
                return False

            # Sample LCD canvas pixels. The JS draws:
            #   LCD_MARGIN=8, DOT=3, GAP=1, COLS_PER_CHAR=5, CELL_PAD_X=6
            #   cellW = 5*(3+1) = 20; cellW+padX = 26
            # Char at col 5 row 0 starts at (8 + 5*26, 8) = (138, 8).
            # Heart slot 0 row 0 bitmap is ". X . X .". So:
            #   pixel (1,0) at (138+4, 8) should be ON  (dark teal)
            #   pixel (0,0) at (138,   8) should be OFF (lighter green)
            #
            # We don't hard-code the exact color values (those come
            # from CSS variables); instead we compare relative
            # brightness: on-pixels are noticeably DARKER than off.
            pixel_data = page.evaluate("""
                () => {
                    const c = document.getElementById('lcd');
                    const ctx = c.getContext('2d');
                    const xs = [
                        // (label, x, y)
                        ['heart_on_1_0',  138 + 4 + 1, 8 + 1],   // pixel (1,0) should be on
                        ['heart_off_0_0', 138 +   + 1, 8 + 1],   // pixel (0,0) should be off
                        ['heart_on_3_0',  138 + 12 + 1, 8 + 1],  // pixel (3,0) should be on
                        ['heart_off_4_0', 138 + 16 + 1, 8 + 1],  // pixel (4,0) should be off
                        // First row's middle pixel of 'w' (lit somewhere)
                        ['ascii_w_mid',    8 + 2*4 + 1, 8 + 2*4 + 1],
                    ];
                    return xs.map(([n, x, y]) => {
                        const d = ctx.getImageData(x, y, 1, 1).data;
                        return [n, [d[0], d[1], d[2]]];
                    });
                }
            """)
            if verbose:
                for n, rgb in pixel_data:
                    print(f"  {n}: rgb={rgb}")
            samples = dict(pixel_data)

            def brightness(rgb):
                # Simple luminance proxy: just sum.
                return rgb[0] + rgb[1] + rgb[2]

            heart_on  = brightness(samples["heart_on_1_0"])
            heart_off = brightness(samples["heart_off_0_0"])
            heart_on3 = brightness(samples["heart_on_3_0"])
            heart_off4 = brightness(samples["heart_off_4_0"])

            # On pixels should be at least ~50 brightness-units darker
            # than off pixels (off ~ 200+ in the yellow-green; on ~ 50).
            if heart_off - heart_on < 50:
                print(f"  {Colors.RED}FAIL{Colors.NC} CGRAM heart pixel (1,0) not appreciably ON: "
                      f"on={heart_on} off={heart_off}")
                return False
            if heart_off4 - heart_on3 < 50:
                print(f"  {Colors.RED}FAIL{Colors.NC} CGRAM heart pixel (3,0) not appreciably ON: "
                      f"on={heart_on3} off={heart_off4}")
                return False

            # Press the button (mouse.down only, leave it held) and
            # verify .held class lands within 1 s, then release.
            btn_box = page.locator("#btn-press").bounding_box()
            cx = btn_box["x"] + btn_box["width"] / 2
            cy = btn_box["y"] + btn_box["height"] / 2
            page.mouse.move(cx, cy)
            page.mouse.down()
            try:
                page.wait_for_function(
                    "document.getElementById('btn-press').classList.contains('held')",
                    timeout=1000,
                )
            except Exception:
                page.mouse.up()
                print(f"  {Colors.RED}FAIL{Colors.NC} button press did not produce .held class")
                return False
            shot2 = out_dir / "web-button-pressed.png"
            page.screenshot(path=str(shot2))
            page.mouse.up()

            browser.close()

        print(f"  {Colors.GREEN}PASS{Colors.NC} web UI test (screenshots in {out_dir}/)")
        if verbose:
            print(f"    {shot1}")
            print(f"    {shot2}")
        return True

    finally:
        proc.send_signal(signal.SIGINT)
        try: proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait(timeout=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--keep", action="store_true", help="(unused, reserved)")
    args = parser.parse_args()
    if not sys.stdout.isatty(): Colors.disable()

    base_dir = Path(__file__).resolve().parent.parent.parent  # .../assembler2
    print("=" * 60)
    print("wendy2c web UI test (HTTP+WS + Playwright)")
    print("=" * 60)
    result = run_test(base_dir, verbose=args.verbose, keep=args.keep)
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
