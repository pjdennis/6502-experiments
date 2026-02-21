#!/usr/bin/env python3
"""
Test runner for emulator non-core logic.

Tests memory-mapped I/O ports, file handling, argument passing,
and other emulator features outside of core 6502 instruction emulation.

Usage:
    python3 tests/emulator_tests.py [-v] [-f FILTER]
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from persistent_emulator import PersistentEmulator


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[0;33m"
    NC = "\033[0m"

    @classmethod
    def disable(cls):
        cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


class EmulatorTestRunner:
    def __init__(self, base_dir: Path, verbose=False, filter_pattern=None):
        self.base_dir = base_dir
        self.verbose = verbose
        self.filter_pattern = filter_pattern
        self.emulator = base_dir / "emulator.out"
        self.assembler = base_dir / "17" / "out" / "asm.out"
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.emu = None
        self._tmpdir_obj = tempfile.TemporaryDirectory(prefix='emu_tests_')
        self.tmpdir = Path(self._tmpdir_obj.name)

    def _pass(self, name: str):
        self.passed += 1
        if self.verbose:
            print(f"  {Colors.GREEN}PASS{Colors.NC} {name}")

    def _fail(self, name: str, reason: str):
        self.failed += 1
        print(f"  {Colors.RED}FAIL{Colors.NC} {name}: {reason}")

    def _skip(self, name: str, reason: str):
        self.skipped += 1
        if self.verbose:
            print(f"  {Colors.YELLOW}SKIP{Colors.NC} {name}: {reason}")

    def _should_run(self, name: str) -> bool:
        if self.filter_pattern is None:
            return True
        return self.filter_pattern.lower() in name.lower()

    def _assert_eq(self, name: str, actual, expected) -> bool:
        if actual != expected:
            self._fail(name, f"expected {expected!r}, got {actual!r}")
            return False
        self._pass(name)
        return True

    def make_binary(self, instructions, org=0x0400):
        """Build a minimal 6502 binary from raw bytes.

        Appends reset vector (last 2 bytes = org address).
        Returns path to temp binary file.
        """
        code = bytes(instructions)
        code += bytes([org & 0xFF, (org >> 8) & 0xFF])
        path = self.tmpdir / f"test_{self.passed + self.failed}.bin"
        path.write_bytes(code)
        return path

    def _assemble(self, src, dst):
        """Assemble a test program."""
        dst.parent.mkdir(exist_ok=True)
        result = subprocess.run(
            [str(self.emulator), str(self.assembler),
             "--no-dump", str(src), str(dst)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"Error: Failed to assemble {src.name}:")
            print(result.stderr)
            return False
        return True

    def _get_server(self):
        """Get or create PersistentEmulator instance."""
        if self.emu is None:
            self.emu = PersistentEmulator(self.emulator)
        return self.emu

    def run_server(self, binary, load_addr=0x0400, args=None,
                   mode='standard', rows=0, cols=0, keys=None):
        """Run binary via PersistentEmulator with inline output+stderr capture.

        Returns (exit_code, output_bytes, stderr_bytes).
        """
        emu = self._get_server()
        return emu.run(binary, args=args, load_addr=load_addr, mode=mode,
                       rows=rows, cols=cols, keys=keys,
                       inline_output=True, inline_stderr=True)

    def run_subprocess(self, binary_or_args, extra_args=None, timeout=10):
        """Run emulator as subprocess. Returns subprocess.CompletedProcess."""
        if isinstance(binary_or_args, list):
            cmd = [str(self.emulator)] + binary_or_args
        else:
            cmd = [str(self.emulator), str(binary_or_args),
                   "--no-dump", "--load", "0400"]
            if extra_args:
                cmd.extend(extra_args)
        return subprocess.run(cmd, capture_output=True, timeout=timeout)

    # ---- Exit code tests ----

    def test_exit_code_explicit(self):
        """Writing to port $F003 sets exit code."""
        name = "Exit code via port"
        if not self._should_run(name):
            return
        # LDA #$2A / STA $F003
        binary = self.make_binary([0xA9, 0x2A, 0x8D, 0x03, 0xF0])
        exit_code, _, _ = self.run_server(binary)
        self._assert_eq(name, exit_code, 0x2A)

    def test_exit_code_zero(self):
        """Exit code 0 means clean exit."""
        name = "Exit code zero"
        if not self._should_run(name):
            return
        # LDA #$00 / STA $F003
        binary = self.make_binary([0xA9, 0x00, 0x8D, 0x03, 0xF0])
        exit_code, _, _ = self.run_server(binary)
        self._assert_eq(name, exit_code, 0)

    def test_exit_code_ff(self):
        """Exit code 255 (max byte value)."""
        name = "Exit code 255"
        if not self._should_run(name):
            return
        # LDA #$FF / STA $F003
        binary = self.make_binary([0xA9, 0xFF, 0x8D, 0x03, 0xF0])
        exit_code, _, _ = self.run_server(binary)
        self._assert_eq(name, exit_code, 255)

    def test_cycle_timeout(self):
        """Infinite loop triggers cycle timeout."""
        name = "Cycle timeout"
        if not self._should_run(name):
            return
        # JMP $0400 (infinite loop)
        binary = self.make_binary([0x4C, 0x00, 0x04])
        exit_code, _, _ = self.run_server(binary)
        self._assert_eq(name, exit_code, 1)

    # ---- Test execution ----

    def run_all_tests(self):
        print("=" * 60)
        print("Emulator Test Suite")
        print("=" * 60)

        if not self.emulator.exists():
            print(f"Error: Emulator not found at {self.emulator}")
            return False

        print("\n--- Exit code ---")
        self.test_exit_code_explicit()
        self.test_exit_code_zero()
        self.test_exit_code_ff()
        self.test_cycle_timeout()

        # Print results
        total = self.passed + self.failed
        print()
        print("=" * 60)
        parts = []
        if self.passed:
            parts.append(f"{Colors.GREEN}{self.passed} passed{Colors.NC}")
        if self.failed:
            parts.append(f"{Colors.RED}{self.failed} failed{Colors.NC}")
        if self.skipped:
            parts.append(f"{Colors.YELLOW}{self.skipped} skipped{Colors.NC}")
        print(f"Results: {', '.join(parts)} of {total} tests")
        print("=" * 60)

        if self.emu:
            self.emu.close()

        return self.failed == 0

    def cleanup(self):
        if self.emu:
            self.emu.close()
        self._tmpdir_obj.cleanup()


def main():
    parser = argparse.ArgumentParser(description="Emulator tests")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Show passing tests")
    parser.add_argument("-f", "--filter", type=str, default=None,
                        help="Only run tests matching pattern")
    args = parser.parse_args()

    if not sys.stdout.isatty():
        Colors.disable()

    base_dir = Path(__file__).resolve().parent.parent
    runner = EmulatorTestRunner(base_dir, verbose=args.verbose,
                                filter_pattern=args.filter)
    try:
        success = runner.run_all_tests()
    finally:
        runner.cleanup()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
