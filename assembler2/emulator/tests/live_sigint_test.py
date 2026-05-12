#!/usr/bin/env python3
"""
Test that the wendy2c --live mode restores the terminal cleanly on
SIGINT (Ctrl-C).

The bug: Without an installed SIGINT handler and an atexit registration,
the default SIGINT action kills the process before
emu_run_wendy2c_live() can call tty_alt_screen_leave() -- leaving the
caller's terminal in raw mode, on the alternate screen, with the cursor
hidden.

The fix unifies signal/atexit setup with --console / --terminal:
install_tty_cleanup_handlers() registers atexit(restore_terminal) and a
SIGINT handler that sets sigint_requested so the live loop can exit
cleanly and tty_alt_screen_leave() runs.

This test:
1. Builds the wendy2c boot ROM + a small payload via vasm (skips if
   vasm is not on PATH, matching wendy2c_goldens.sh's pattern).
2. Launches the emulator with --machine wendy2c --live on a PTY.
3. Waits until the live render has produced output.
4. Sends SIGINT and reads the remaining PTY bytes.
5. Verifies the terminal-restore sequences (alt-screen leave
   "\x1b[?1049l" and show-cursor "\x1b[?25h") appear in the output AFTER
   the live render, i.e. the cleanup actually ran.

Usage:
    python3 emulator/tests/live_sigint_test.py [-v]
"""

import argparse
import os
import pty
import select
import signal
import subprocess
import sys
import time
from pathlib import Path


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[0;33m"
    NC = "\033[0m"

    @classmethod
    def disable(cls):
        cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


def have_vasm():
    return subprocess.run(
        ["sh", "-c", "command -v vasm6502_oldstyle"],
        capture_output=True
    ).returncode == 0


def run_vasm(src, out_path, log_path):
    result = subprocess.run(
        ["vasm6502_oldstyle", "-wdc02", "-wfail", "-Fbin", "-dotdir",
         "-ignore-mult-inc", "-esc", "-o", str(out_path), str(src)],
        capture_output=True, text=True
    )
    log_path.write_text(result.stdout + result.stderr)
    return result.returncode == 0


def build_artifacts(repo_root, out_dir):
    """Returns (boot_rom_path, framed_payload_path) or None on failure."""
    boot_src = repo_root / "upload_and_run_eeprom_wendy2c.s"
    payload_src = repo_root / "hello_ram_4000_wendy2c.s"
    boot_rom = out_dir / "wendy2c_boot.bin"
    payload_bin = out_dir / "payload.bin"
    framed = out_dir / "payload.framed"

    if not run_vasm(boot_src, boot_rom, out_dir / "boot.vasm.log"):
        return None
    if not run_vasm(payload_src, payload_bin, out_dir / "payload.vasm.log"):
        return None

    framer = repo_root / "assembler2" / "emulator" / "wendy2_upload.py"
    result = subprocess.run(
        ["python3", str(framer), str(payload_bin), "-o", str(framed)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return boot_rom, framed


def read_until(master_fd, pred, timeout):
    """Read bytes from master_fd until pred(data) is true or timeout."""
    data = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([master_fd], [], [], min(remaining, 0.1))
        if ready:
            try:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                data += chunk
                if pred(data):
                    return data
            except OSError:
                break
    return data


def drain(master_fd, timeout):
    data = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([master_fd], [], [], min(remaining, 0.05))
        if ready:
            try:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                data += chunk
            except OSError:
                break
        else:
            # Brief quiet period; keep reading for a bit longer in case
            # more output is on the way (the post-render delay in
            # emu_run_wendy2c_live is 250 ms).
            pass
    return data


def run_test(base_dir, verbose=False):
    if not have_vasm():
        print(f"  {Colors.YELLOW}SKIP{Colors.NC} live SIGINT cursor restore "
              f"(vasm6502_oldstyle not on PATH)")
        return None

    emulator = base_dir / "emulator" / "emulator.out"
    if not emulator.exists():
        print(f"  {Colors.RED}FAIL{Colors.NC} live SIGINT cursor restore: "
              f"emulator not built at {emulator}")
        return False

    repo_root = base_dir.parent
    out_dir = Path("/tmp") / "wendy2c-live-sigint-test"
    out_dir.mkdir(exist_ok=True)

    artifacts = build_artifacts(repo_root, out_dir)
    if artifacts is None:
        print(f"  {Colors.RED}FAIL{Colors.NC} live SIGINT cursor restore: "
              f"vasm/framing failed (see {out_dir}/*.vasm.log)")
        return False
    boot_rom, framed = artifacts

    master_fd, slave_fd = pty.openpty()
    proc = None
    try:
        proc = subprocess.Popen(
            [str(emulator), str(boot_rom),
             "--machine", "wendy2c",
             "--serial-input", str(framed),
             "--live"],
            stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
            preexec_fn=os.setsid,
        )
        os.close(slave_fd)
        slave_fd = -1

        # Wait for the live render's "wendy2c live" header to appear.
        pre = read_until(master_fd, lambda b: b"wendy2c live" in b, timeout=5.0)
        if b"wendy2c live" not in pre:
            print(f"  {Colors.RED}FAIL{Colors.NC} live SIGINT cursor restore: "
                  f"live header did not appear before timeout")
            if verbose:
                print(f"    Got: {pre!r}")
            return False

        # Give the live renderer a beat so it has clearly started.
        time.sleep(0.2)
        pre += drain(master_fd, timeout=0.2)

        # Send SIGINT to the whole process group (since we used setsid).
        os.killpg(proc.pid, signal.SIGINT)

        # Read the rest of the output, up to a few seconds. The
        # tty_alt_screen_leave sequence should arrive shortly.
        post = b""
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            ready, _, _ = select.select([master_fd], [], [], min(remaining, 0.1))
            if ready:
                try:
                    chunk = os.read(master_fd, 4096)
                    if not chunk:
                        break
                    post += chunk
                except OSError:
                    break
            if proc.poll() is not None and not ready:
                # Process exited and pipe drained.
                break

        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)

        if verbose:
            print(f"    Pre-SIGINT bytes:  {len(pre)}")
            print(f"    Post-SIGINT bytes: {len(post)}")
            print(f"    Post-SIGINT tail:  {post[-200:]!r}")

        # The fix should emit:
        #   "\x1b[?25h"     -- show cursor
        #   "\x1b[?1049l"   -- leave alt screen
        # Both come from tty_alt_screen_leave() (the live mode also
        # explicitly emits ?25h before calling leave). If the process
        # was killed by the default SIGINT action, neither sequence is
        # in `post`.
        ok = b"\x1b[?1049l" in post and b"\x1b[?25h" in post
        if not ok:
            print(f"  {Colors.RED}FAIL{Colors.NC} live SIGINT cursor restore: "
                  f"terminal-restore sequences not emitted after SIGINT")
            if not verbose:
                print(f"    Post-SIGINT tail: {post[-200:]!r}")
            return False

        print(f"  {Colors.GREEN}PASS{Colors.NC} live SIGINT cursor restore")
        return True

    finally:
        if slave_fd >= 0:
            try: os.close(slave_fd)
            except OSError: pass
        try: os.close(master_fd)
        except OSError: pass
        if proc and proc.poll() is None:
            try:
                proc.kill()
                proc.wait(timeout=2)
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="--live SIGINT cursor-restore test")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    if not sys.stdout.isatty():
        Colors.disable()

    base_dir = Path(__file__).resolve().parent.parent.parent
    # base_dir = .../assembler2

    print("=" * 60)
    print("wendy2c --live SIGINT cursor-restore test")
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
    else:
        print(f"Results: {Colors.RED}1 failed{Colors.NC} of 1 test")
        sys.exit(1)


if __name__ == "__main__":
    main()
