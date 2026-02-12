#!/usr/bin/env python3
"""
Test runner for terminal mode serial I/O.

Tests the emulator's --terminal mode by assembling a test program,
running it with --terminal --input/--output, and verifying output.

Usage:
    python3 tests/terminal_tests.py [-v]
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


# ANSI colors
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[0;33m"
    NC = "\033[0m"

    @classmethod
    def disable(cls):
        cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


class TerminalTestRunner:
    def __init__(self, base_dir: Path, verbose: bool = False):
        self.base_dir = base_dir
        self.verbose = verbose
        self.emulator = base_dir / "emulator.out"
        self.assembler = base_dir / "23" / "out" / "asm.out"
        self.test_asm = base_dir / "tests" / "terminal_test.asm"
        self.test_bin = base_dir / "tests" / "out" / "terminal_test.out"
        self.passed = 0
        self.failed = 0

    def build_test_program(self):
        """Assemble the terminal test program."""
        if not self.emulator.exists():
            print(f"Error: Emulator not found at {self.emulator}")
            return False
        if not self.assembler.exists():
            print(f"Error: Assembler not found at {self.assembler}")
            return False

        self.test_bin.parent.mkdir(exist_ok=True)
        result = subprocess.run(
            [str(self.emulator), str(self.assembler),
             str(self.test_asm), str(self.test_bin)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"Error: Failed to assemble terminal test program:")
            print(result.stderr)
            return False
        return True

    def run_terminal(self, input_bytes: bytes, tmpdir: Path) -> tuple:
        """Run the test program in terminal mode with file I/O.

        Returns (exit_code, output_bytes).
        """
        keys_file = tmpdir / "input.bin"
        output_file = tmpdir / "output.bin"
        keys_file.write_bytes(input_bytes)

        result = subprocess.run(
            [str(self.emulator), str(self.test_bin), "--load", "0400",
             "--terminal", "--input", str(keys_file),
             "--output", str(output_file)],
            capture_output=True, timeout=10
        )

        output = output_file.read_bytes() if output_file.exists() else b""
        return result.returncode, output

    def _pass(self, name: str):
        self.passed += 1
        if self.verbose:
            print(f"  {Colors.GREEN}PASS{Colors.NC} {name}")

    def _fail(self, name: str, reason: str):
        self.failed += 1
        print(f"  {Colors.RED}FAIL{Colors.NC} {name}: {reason}")

    def run_test(self, name: str, input_bytes: bytes,
                 expected_output: bytes = None,
                 expect_exit: int = 0):
        """Run a terminal test case."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            try:
                exit_code, output = self.run_terminal(input_bytes, tmpdir)
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != expect_exit:
                self._fail(name,
                    f"Expected exit code {expect_exit}, got {exit_code}")
                return

            if expected_output is not None:
                if output != expected_output:
                    self._fail(name,
                        f"Output mismatch:\n"
                        f"  Expected: {expected_output!r}\n"
                        f"  Actual:   {output!r}")
                    return

            self._pass(name)

    def run_all_tests(self):
        """Run all terminal mode tests."""
        print("=" * 60)
        print("Terminal Mode Test Suite")
        print("=" * 60)

        if not self.build_test_program():
            return False

        # Echo test: send "Hello" + Ctrl+D, verify echoed output
        self.run_test(
            "Echo test",
            input_bytes=b"Hello\x04",
            expected_output=b"Hello"
        )

        # Exit test: send just Ctrl+D, verify clean exit with empty output
        self.run_test(
            "Exit on Ctrl+D",
            input_bytes=b"\x04",
            expected_output=b""
        )

        # ANSI passthrough: send ESC sequence bytes, verify they pass through
        self.run_test(
            "Binary passthrough",
            input_bytes=b"\x1b[2J\x04",
            expected_output=b"\x1b[2J"
        )

        # Multi-byte echo: various characters including CR/LF
        self.run_test(
            "CR/LF echo",
            input_bytes=b"ab\r\ncd\x04",
            expected_output=b"ab\r\ncd"
        )

        # Print results
        total = self.passed + self.failed
        print()
        print("=" * 60)
        if self.failed == 0:
            print(f"Results: {Colors.GREEN}{self.passed} passed{Colors.NC} "
                  f"of {total} tests")
        else:
            print(f"Results: {Colors.GREEN}{self.passed} passed{Colors.NC}, "
                  f"{Colors.RED}{self.failed} failed{Colors.NC} "
                  f"of {total} tests")
        print("=" * 60)

        return self.failed == 0


def main():
    parser = argparse.ArgumentParser(description="Terminal mode tests")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Show passing tests")
    args = parser.parse_args()

    if not sys.stdout.isatty():
        Colors.disable()

    base_dir = Path(__file__).resolve().parent.parent
    runner = TerminalTestRunner(base_dir, verbose=args.verbose)
    success = runner.run_all_tests()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
