#!/usr/bin/env python3
"""
Tests for test_runner directory scanning mode.

When the test runner is invoked with no arguments (argc == 0),
it should use opendir(".") to discover .txt test files in the
current directory and run them all.

Usage:
    python3 17/tests/test_runner/test_runner_dir.py
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


# Paths relative to project root
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent
EMULATOR = PROJECT_ROOT / "emulator.out"
TEST_RUNNER = PROJECT_ROOT / "17" / "out" / "test_runner.out"


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    NC = "\033[0m"


def run_test_runner(cwd, args=None, timeout=30):
    """Run the test runner in the given directory.

    Args:
        cwd: Working directory for the test runner
        args: Optional list of arguments (test filenames)
        timeout: Timeout in seconds

    Returns:
        (stderr_output, exit_code) - test runner output goes to stderr
    """
    cmd = [str(EMULATOR), str(TEST_RUNNER), "--no-dump"]
    if args:
        cmd.extend(args)
    result = subprocess.run(
        cmd,
        capture_output=True,
        timeout=timeout,
        cwd=cwd,
    )
    # Test runner output goes to stderr (via write_d / show_message)
    output = result.stderr.decode("utf-8", errors="replace")
    return output, result.returncode


# A minimal passing test file
SIMPLE_PASS_TEST = """\
---
NAME: simple_nop
INPUT:
 1: * = $0200
 2:   NOP
EXPECT_HEX: ea
---
"""

# A test file with two tests
TWO_TESTS = """\
---
NAME: test_nop
INPUT:
 1: * = $0200
 2:   NOP
EXPECT_HEX: ea
---
NAME: test_lda_imm
INPUT:
 1: * = $0200
 2:   LDA #$42
EXPECT_HEX: a9 42
---
"""


def test_single_txt_file_in_directory():
    """When argc==0 and directory has one .txt file, it should run it."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "tests.txt").write_text(SIMPLE_PASS_TEST)
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "Running tests from tests.txt" in output, f"Missing header in: {output}"
        assert "simple_nop" in output, f"Missing test name in: {output}"
        assert "1 passed" in output, f"Missing pass count in: {output}"


def test_multiple_txt_files():
    """Multiple .txt files should all be processed in alphabetical order."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "02-second.txt").write_text(SIMPLE_PASS_TEST.replace(
            "simple_nop", "second_test"))
        Path(tmpdir, "01-first.txt").write_text(SIMPLE_PASS_TEST.replace(
            "simple_nop", "first_test"))
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        # Check alphabetical order
        first_pos = output.index("01-first.txt")
        second_pos = output.index("02-second.txt")
        assert first_pos < second_pos, \
            f"Files not in alphabetical order:\n{output}"
        assert "2 passed" in output, f"Expected 2 passed in: {output}"


def test_non_txt_files_ignored():
    """Non-.txt files should be ignored."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "test.txt").write_text(SIMPLE_PASS_TEST)
        Path(tmpdir, "readme.md").write_text("# Not a test")
        Path(tmpdir, "code.asm").write_text("NOP")
        Path(tmpdir, "data.bin").write_bytes(b"\x00\x01")
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "readme.md" not in output, f"Non-txt file processed: {output}"
        assert "code.asm" not in output, f"Non-txt file processed: {output}"
        assert "data.bin" not in output, f"Non-txt file processed: {output}"
        assert "1 passed" in output, f"Expected 1 passed in: {output}"


def test_directories_ignored():
    """Subdirectories should be ignored even if named .txt."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "test.txt").write_text(SIMPLE_PASS_TEST)
        Path(tmpdir, "subdir.txt").mkdir()
        Path(tmpdir, "another_dir").mkdir()
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "subdir.txt" not in output, f"Directory was processed: {output}"
        assert "1 passed" in output, f"Expected 1 passed in: {output}"


def test_single_file_mode_still_works():
    """When a filename is passed as argument, use it directly (regression)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "mytest.txt").write_text(SIMPLE_PASS_TEST)
        output, rc = run_test_runner(tmpdir, args=["mytest.txt"])
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "Running tests from mytest.txt" in output, \
            f"Missing header in: {output}"
        assert "1 passed" in output, f"Expected 1 passed in: {output}"


def test_empty_directory():
    """Empty directory (no .txt files) should produce summary with all zeros."""
    with tempfile.TemporaryDirectory() as tmpdir:
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "0 passed" in output, f"Expected 0 passed in: {output}"


def test_cumulative_counts_across_files():
    """Pass/fail/skip counts should accumulate across multiple files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "01-file.txt").write_text(TWO_TESTS)
        Path(tmpdir, "02-file.txt").write_text(SIMPLE_PASS_TEST)
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "3 passed" in output, f"Expected 3 passed in: {output}"


def test_long_input_lines():
    """INPUT lines longer than 255 chars should be streamed correctly."""
    # Build a macro with many parameters - the .macro line exceeds 255 chars
    params = ", ".join(f"a{i:02d}" for i in range(50))
    args = ", ".join(f"${i:02X}" for i in range(50))
    long_test = f"""\
---
NAME: long_input_line
INPUT:
 1: * = $0200
 2:   .macro BIG {params}
 3:   LDA #a00
 4:   .endmacro
 5:   BIG {args}
EXPECT_HEX: a9 00
---
"""
    # Verify the test file actually has lines >255 chars
    max_line = max(len(line) for line in long_test.splitlines())
    assert max_line > 255, f"Test setup error: max line is only {max_line} chars"

    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "test.txt").write_text(long_test)
        output, rc = run_test_runner(tmpdir)
        assert rc == 0, f"Expected exit code 0, got {rc}\nOutput: {output}"
        assert "1 passed" in output, f"Expected 1 passed in: {output}"
        assert "LIMIT" not in output, f"Unexpected LIMIT in: {output}"


# A test with intentional byte mismatch (expect a9 42, input produces a9 43)
BYTE_MISMATCH_TEST = """\
---
NAME: byte_mismatch
INPUT:
 1: * = $0200
 2:   LDA #$43
EXPECT_HEX: a9 42
---
"""

# A test with length mismatch (expect 3 bytes, input produces 2)
LENGTH_MISMATCH_TEST = """\
---
NAME: length_mismatch
INPUT:
 1: * = $0200
 2:   LDA #$42
EXPECT_HEX: a9 42 ea
---
"""


def test_byte_mismatch_shows_hex_dumps():
    """On byte mismatch, failure output should include exp: and got: hex dumps."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "test.txt").write_text(BYTE_MISMATCH_TEST)
        output, rc = run_test_runner(tmpdir)
        assert rc == 1, f"Expected exit code 1, got {rc}\nOutput: {output}"
        assert "FAIL" in output, f"Missing FAIL in: {output}"
        assert "exp: a9 42" in output, f"Missing exp hex dump in: {output}"
        assert "got: a9 43" in output, f"Missing got hex dump in: {output}"


def test_length_mismatch_shows_hex_dumps():
    """On length mismatch, failure output should include exp: and got: hex dumps."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "test.txt").write_text(LENGTH_MISMATCH_TEST)
        output, rc = run_test_runner(tmpdir)
        assert rc == 1, f"Expected exit code 1, got {rc}\nOutput: {output}"
        assert "FAIL" in output, f"Missing FAIL in: {output}"
        assert "exp: a9 42 ea" in output, f"Missing exp hex dump in: {output}"
        assert "got: a9 42" in output, f"Missing got hex dump in: {output}"


def main():
    if not EMULATOR.exists():
        print(f"Error: Emulator not found at {EMULATOR}")
        sys.exit(1)
    if not TEST_RUNNER.exists():
        print(f"Error: Test runner not found at {TEST_RUNNER}")
        sys.exit(1)

    tests = [
        ("single_txt_file_in_directory", test_single_txt_file_in_directory),
        ("multiple_txt_files", test_multiple_txt_files),
        ("non_txt_files_ignored", test_non_txt_files_ignored),
        ("directories_ignored", test_directories_ignored),
        ("single_file_mode_still_works", test_single_file_mode_still_works),
        ("empty_directory", test_empty_directory),
        ("cumulative_counts_across_files", test_cumulative_counts_across_files),
        ("long_input_lines", test_long_input_lines),
        ("byte_mismatch_shows_hex_dumps", test_byte_mismatch_shows_hex_dumps),
        ("length_mismatch_shows_hex_dumps", test_length_mismatch_shows_hex_dumps),
    ]

    passed = 0
    failed = 0
    for name, test_fn in tests:
        try:
            test_fn()
            print(f"  {Colors.GREEN}PASS{Colors.NC} {name}")
            passed += 1
        except Exception as e:
            print(f"  {Colors.RED}FAIL{Colors.NC} {name}: {e}")
            failed += 1

    print(f"\n{passed} passed, {failed} failed")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
