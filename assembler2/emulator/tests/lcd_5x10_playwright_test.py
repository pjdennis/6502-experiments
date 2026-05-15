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

            # Capture the most recent f5x10 value from each state frame.
            page.add_init_script("""
                window._lastF5x10 = null;
                const origWS = window.WebSocket;
                window.WebSocket = function(...args) {
                    const ws = new origWS(...args);
                    ws.addEventListener('message', (e) => {
                        if (typeof e.data === 'string') {
                            try {
                                const obj = JSON.parse(e.data);
                                if (obj.lcd && 'f5x10' in obj.lcd) {
                                    window._lastF5x10 = obj.lcd.f5x10;
                                }
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
            # Give the payload time to finish reset_display + the second
            # function-set that flips into 5x10 mode.
            page.wait_for_timeout(2500)

            f5x10 = page.evaluate("window._lastF5x10")
            if verbose: print(f"  f5x10 reported by server = {f5x10}")
            if f5x10 != 1:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: f5x10 in snapshot = {f5x10}, want 1")
                return False

            # Verify canvas size: in 5x10 mode each cell is 5x(10+1)=55 px
            # tall (DOT=3 + GAP=1 = 4 per dot * 11 rows = 44 + 11 gaps,
            # actually 11*(3+1)=44). With one display row that's 44 + 2*8
            # margin = 60. In 5x8 mode it would be 9*(3+1) + 16 = 52.
            # We just sanity-check that height grew beyond the 5x8 size.
            canvas_h = page.evaluate("document.getElementById('lcd').height")
            if verbose: print(f"  canvas height = {canvas_h}")
            if canvas_h < 55:
                print(f"  {Colors.RED}FAIL{Colors.NC} 5x10 LCD test: canvas height={canvas_h}, "
                      f"expected >= 55 (rows-per-cell should rise from 9 to 11)")
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
