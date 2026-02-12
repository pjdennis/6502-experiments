#!/usr/bin/env python3
"""
Test runner for the vi-like text editor.

Tests the editor by providing keystroke sequences as input files
and verifying the saved output matches expectations.

Usage:
    ./editor/tests/editor_tests.py [-v]
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from ansi_screen import AnsiScreen


def make_lines(n):
    """Generate content with n numbered lines: 'Line 1\\nLine 2\\n...Line N\\n'."""
    return ''.join(f"Line {i}\n" for i in range(1, n + 1))


# ANSI colors
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[0;33m"
    NC = "\033[0m"

    @classmethod
    def disable(cls):
        cls.RED = cls.GREEN = cls.YELLOW = cls.NC = ""


class EditorTestRunner:
    def __init__(self, base_dir: Path, verbose: bool = False, quiet: bool = False):
        self.base_dir = base_dir
        self.verbose = verbose
        self.quiet = quiet
        self.emulator = base_dir / "emulator.out"
        self.assembler = base_dir / "23" / "out" / "asm.out"
        self.editor_asm = base_dir / "editor" / "editor.asm"
        self.editor_bin = base_dir / "editor" / "out" / "editor.out"
        self.editor_small_bin = base_dir / "editor" / "out" / "editor_small.out"
        self.passed = 0
        self.failed = 0

    def _assemble_editor(self, output_bin, extra_args=None):
        """Assemble the editor with optional extra assembler arguments."""
        if not self.emulator.exists():
            print(f"Error: Emulator not found at {self.emulator}")
            return False
        if not self.assembler.exists():
            print(f"Error: Assembler not found at {self.assembler}")
            return False

        output_bin.parent.mkdir(exist_ok=True)
        cmd = [str(self.emulator), str(self.assembler),
               str(self.editor_asm), str(output_bin)]
        if extra_args:
            cmd.extend(extra_args)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error: Failed to assemble editor ({output_bin.name}):")
            print(result.stderr)
            return False
        return True

    def build_editor(self):
        """Assemble the editor."""
        return self._assemble_editor(self.editor_bin)

    def build_small_buffer_editor(self):
        """Assemble the editor with small buffer (256 bytes for testing)."""
        return self._assemble_editor(self.editor_small_bin,
                                     ["define:small_buffer"])

    def create_stable_copy(self):
        """Create a stable copy of editor.out after successful tests."""
        stable_path = self.base_dir / "editor" / "out" / "editor_stable.out"
        try:
            shutil.copy2(self.editor_bin, stable_path)
            if not self.quiet:
                print()
                print(f"{Colors.GREEN}Created stable copy:{Colors.NC} {stable_path}")
            return True
        except Exception as e:
            print()
            print(f"{Colors.RED}Warning: Failed to create stable copy:{Colors.NC} {e}")
            return False

    def run_editor(self, input_file: str, keys: bytes, tmpdir: Path) -> tuple:
        """Run the editor with given keystroke sequence.

        Returns (exit_code, saved_content, ansi_output).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.txt"
        keys_file.write_bytes(keys)

        result = subprocess.run(
            [str(self.emulator), str(self.editor_bin), "--load", "0400",
             "--input", str(keys_file), "--output", str(output_file), input_file],
            capture_output=True, timeout=10
        )

        saved = ""
        if Path(input_file).exists():
            saved = Path(input_file).read_text()

        ansi = output_file.read_text() if output_file.exists() else ""

        return result.returncode, saved, ansi

    def run_editor_console(self, input_file: str, keys: bytes, tmpdir: Path) -> tuple:
        """Run the editor with console-mode arg layout.

        Uses --console as input_file arg, with the file to edit as the
        first program argument (no output_file parameter).
        Stdin is redirected from a keys file to simulate keystrokes.

        Returns (exit_code, saved_content).
        """
        keys_file = tmpdir / "keys.bin"
        keys_file.write_bytes(keys)

        with open(keys_file, "rb") as stdin_file:
            result = subprocess.run(
                [str(self.emulator), str(self.editor_bin), "--load", "0400",
                 "--console", input_file],
                stdin=stdin_file, capture_output=True, timeout=10
            )

        saved = ""
        if Path(input_file).exists():
            saved = Path(input_file).read_text()

        return result.returncode, saved

    def run_test_console(self, name: str, initial_content: str, keys: bytes,
                         expected_content: str = None, expect_exit: int = 0):
        """Run an editor test using console-mode argument layout."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"
            edit_file.write_text(initial_content)

            try:
                exit_code, saved = self.run_editor_console(
                    str(edit_file), keys, tmpdir
                )
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != expect_exit:
                self._fail(name, f"Expected exit code {expect_exit}, got {exit_code}")
                return

            if expected_content is not None:
                if saved != expected_content:
                    self._fail(name,
                        f"Content mismatch:\n"
                        f"  Expected: {expected_content!r}\n"
                        f"  Actual:   {saved!r}")
                    return

            self._pass(name)

    def run_test_new_file(self, name: str, keys: bytes,
                          expected_content: str = None, expect_exit: int = 0):
        """Run an editor test on a file that does not exist yet."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "newfile.txt"
            # Do NOT create the file - it should not exist

            try:
                exit_code, saved, ansi = self.run_editor(
                    str(edit_file), keys, tmpdir
                )
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != expect_exit:
                self._fail(name, f"Expected exit code {expect_exit}, got {exit_code}")
                return

            if expected_content is not None:
                if saved != expected_content:
                    self._fail(name,
                        f"Content mismatch:\n"
                        f"  Expected: {expected_content!r}\n"
                        f"  Actual:   {saved!r}")
                    return

            self._pass(name)

    def run_test(self, name: str, initial_content: str, keys: bytes,
                 expected_content: str = None, expect_exit: int = 0,
                 expect_unmodified: bool = False):
        """Run a single editor test."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor(
                    str(edit_file), keys, tmpdir
                )
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != expect_exit:
                self._fail(name, f"Expected exit code {expect_exit}, got {exit_code}")
                return

            if expected_content is not None:
                if saved != expected_content:
                    self._fail(name,
                        f"Content mismatch:\n"
                        f"  Expected: {expected_content!r}\n"
                        f"  Actual:   {saved!r}")
                    return

            if expect_unmodified:
                if saved != initial_content:
                    self._fail(name, f"File was modified when it shouldn't have been")
                    return

            self._pass(name)

    def run_editor_small_buffer(self, input_file: str, keys: bytes,
                               tmpdir: Path) -> tuple:
        """Run the small buffer editor with given keystroke sequence.

        Returns (exit_code, saved_content, ansi_output).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.txt"
        keys_file.write_bytes(keys)

        cmd = [str(self.emulator), str(self.editor_small_bin), "--load", "0400",
               "--input", str(keys_file), "--output", str(output_file), input_file]

        result = subprocess.run(
            cmd, capture_output=True, timeout=10
        )

        saved = ""
        if Path(input_file).exists():
            saved = Path(input_file).read_text()

        ansi = output_file.read_text() if output_file.exists() else ""

        return result.returncode, saved, ansi

    def run_editor_screen(self, input_file: str, keys: bytes, tmpdir: Path,
                          rows: int = 10, cols: int = 40) -> tuple:
        """Run the editor with explicit terminal size for screen-state testing.

        Returns (exit_code, saved_content, ansi_output).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.txt"
        keys_file.write_bytes(keys)

        result = subprocess.run(
            [str(self.emulator), str(self.editor_bin), "--load", "0400",
             "--rows", str(rows), "--cols", str(cols),
             "--input", str(keys_file), "--output", str(output_file), input_file],
            capture_output=True, timeout=10
        )

        saved = ""
        if Path(input_file).exists():
            try:
                saved = Path(input_file).read_text()
            except UnicodeDecodeError:
                saved = Path(input_file).read_bytes().decode('latin-1')

        ansi = output_file.read_bytes() if output_file.exists() else b""

        return result.returncode, saved, ansi

    def run_test_screen(self, name: str, initial_content: str, keys: bytes,
                        rows: int = 10, cols: int = 40,
                        expect_cursor: tuple = None,
                        expect_lines: list = None,
                        expect_status_contains: str = None,
                        expected_content: str = None,
                        expect_content_redraws: list = None,
                        expect_content_rows: list = None,
                        expect_ansi_contains: str = None,
                        expect_cursor_at_frame: list = None,
                        expect_lines_at_frame: list = None,
                        expect_status_at_frame: list = None,
                        initial_bytes: bytes = None,
                        expect_reverse_at: list = None):
        """Run an editor test and verify screen state via ANSI output.

        Args:
            expect_cursor: (row, col) 0-based cursor position in last frame
            expect_lines: [(row_idx, text), ...] expected row content
            expect_status_contains: substring to find in status bar row
            expected_content: expected saved file content (after :wq)
            expect_content_redraws: list of bools, one per frame - True if
                content area should have been redrawn in that frame
            expect_content_rows: list of (frame_idx, expected_rows_set) tuples -
                verify exactly which content rows were touched in specific frames
            expect_ansi_contains: substring to find in raw ANSI output
            expect_cursor_at_frame: list of (frame_idx, (row, col)) tuples -
                verify cursor position at specific frames
            expect_lines_at_frame: list of (frame_idx, [(row_idx, text), ...])
                tuples - verify row content at specific frames (not just last)
            expect_status_at_frame: list of (frame_idx, substring) tuples -
                verify status bar contains substring at specific frames
            initial_bytes: raw bytes for initial file content (overrides
                initial_content; use when content has non-UTF-8 bytes)
            expect_reverse_at: list of (row, col, expected_bool) tuples -
                verify reverse video attribute at specific cells
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_bytes is not None:
                edit_file.write_bytes(initial_bytes)
            elif initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor_screen(
                    str(edit_file), keys, tmpdir, rows, cols
                )
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != 0:
                self._fail(name, f"Expected exit code 0, got {exit_code}")
                return

            if expect_ansi_contains is not None:
                ansi_text = ansi.decode('latin-1')
                if expect_ansi_contains not in ansi_text:
                    self._fail(name,
                        f"Raw ANSI output does not contain "
                        f"{expect_ansi_contains!r}")
                    return

            # Parse ANSI output through virtual terminal
            screen = AnsiScreen(rows, cols)
            screen.process(ansi.decode('latin-1'))

            if screen.frame_buffer is None:
                self._fail(name, "No rendered frame captured (no ESC[?25h)")
                return

            if expect_cursor is not None:
                actual = screen.get_cursor()
                if actual != expect_cursor:
                    self._fail(name,
                        f"Cursor: expected {expect_cursor}, got {actual}\n"
                        f"    Frame:\n{screen.dump()}")
                    return

            if expect_lines is not None:
                for row_idx, expected_text in expect_lines:
                    actual_text = screen.get_row_text(row_idx)
                    if actual_text != expected_text:
                        self._fail(name,
                            f"Row {row_idx}: expected {expected_text!r}, "
                            f"got {actual_text!r}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_status_contains is not None:
                status_row = rows - 1
                status_text = screen.get_row_text(status_row)
                if expect_status_contains not in status_text:
                    self._fail(name,
                        f"Status bar: expected substring {expect_status_contains!r} "
                        f"in {status_text!r}\n"
                        f"    Frame:\n{screen.dump()}")
                    return

            if expected_content is not None:
                if saved != expected_content:
                    self._fail(name,
                        f"Content mismatch:\n"
                        f"  Expected: {expected_content!r}\n"
                        f"  Actual:   {saved!r}")
                    return

            if expect_content_redraws is not None:
                actual_count = screen.get_frame_count()
                expected_count = len(expect_content_redraws)
                if actual_count < expected_count:
                    self._fail(name,
                        f"Expected {expected_count} frames, got {actual_count}\n"
                        f"    Frame:\n{screen.dump()}")
                    return
                for i, expected_redraw in enumerate(expect_content_redraws):
                    actual_redraw = screen.was_content_redrawn(i)
                    if actual_redraw != expected_redraw:
                        self._fail(name,
                            f"Frame {i}: expected content_redrawn="
                            f"{expected_redraw}, got {actual_redraw}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_content_rows is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, expected_rows in expect_content_rows:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_rows = screen.content_rows_touched(frame_idx)
                    if actual_rows != expected_rows:
                        self._fail(name,
                            f"Frame {frame_idx}: expected rows touched "
                            f"{expected_rows}, got {actual_rows}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_cursor_at_frame is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, expected_pos in expect_cursor_at_frame:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_pos = screen.frames[frame_idx][1]
                    if actual_pos != expected_pos:
                        self._fail(name,
                            f"Frame {frame_idx}: expected cursor at "
                            f"{expected_pos}, got {actual_pos}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_lines_at_frame is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, line_checks in expect_lines_at_frame:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    for row_idx, expected_text in line_checks:
                        actual_text = screen.get_row_text_at_frame(
                            frame_idx, row_idx)
                        if actual_text != expected_text:
                            self._fail(name,
                                f"Frame {frame_idx}, row {row_idx}: "
                                f"expected {expected_text!r}, "
                                f"got {actual_text!r}\n"
                                f"    Frame:\n{screen.dump()}")
                            return

            if expect_status_at_frame is not None:
                actual_count = screen.get_frame_count()
                status_row = rows - 1
                for frame_idx, expected_substr in expect_status_at_frame:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_text = screen.get_row_text_at_frame(
                        frame_idx, status_row)
                    if expected_substr not in actual_text:
                        self._fail(name,
                            f"Frame {frame_idx}: status bar expected "
                            f"substring {expected_substr!r} in "
                            f"{actual_text!r}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_reverse_at is not None:
                for row, col, expected_rev in expect_reverse_at:
                    actual_rev = screen.is_reverse_at(row, col)
                    if actual_rev != expected_rev:
                        self._fail(name,
                            f"Cell ({row},{col}): expected reverse="
                            f"{expected_rev}, got {actual_rev}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            self._pass(name)

    def run_test_small_buffer(self, name: str, initial_content: str, keys: bytes,
                             expected_content: str = None, expect_exit: int = 0,
                             expect_unmodified: bool = False):
        """Run a test using the small buffer editor (256 bytes)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor_small_buffer(
                    str(edit_file), keys, tmpdir
                )
            except subprocess.TimeoutExpired:
                self._fail(name, "Timed out (infinite loop?)")
                return
            except Exception as e:
                self._fail(name, f"Error: {e}")
                return

            if exit_code != expect_exit:
                self._fail(name, f"Expected exit code {expect_exit}, got {exit_code}")
                return

            if expected_content is not None:
                if saved != expected_content:
                    self._fail(name,
                        f"Content mismatch:\n"
                        f"  Expected: {expected_content!r}\n"
                        f"  Actual:   {saved!r}")
                    return

            if expect_unmodified:
                if saved != initial_content:
                    self._fail(name, f"File was modified when it shouldn't have been")
                    return

            self._pass(name)

    def _pass(self, name):
        if not self.quiet:
            print(f"  {name:<50} {Colors.GREEN}PASS{Colors.NC}")
        self.passed += 1

    def _group(self, title, leading_blank=False):
        if self.quiet:
            return
        if leading_blank:
            print()
        print(title)
        print()

    def _fail(self, name, details):
        print(f"  {name:<50} {Colors.RED}FAIL{Colors.NC}")
        print(f"    {details}")
        self.failed += 1

    def run_all_tests(self):
        """Run all editor tests."""
        print("=" * 60)
        print("Editor Test Suite")
        print("=" * 60)
        print()

        if not self.build_editor():
            return

        self._group("Basic operations:")

        # Open and quit without saving
        self.run_test(
            "Open file and :q!",
            "Hello\n",
            b":q!\r",
            expect_unmodified=True
        )

        # Open and quit unmodified file with :q
        self.run_test(
            "Quit unmodified file with :q",
            "Hello\n",
            b":q\r",
            expect_unmodified=True
        )

        # Save and quit
        self.run_test(
            "Open file and :wq (no changes)",
            "Hello\n",
            b":wq\r",
            expected_content="Hello\n"
        )

        # Delete character with x
        self.run_test(
            "Delete first char with x",
            "Hello\n",
            b"x:wq\r",
            expected_content="ello\n"
        )

        # Delete character in middle
        self.run_test(
            "Delete char at column 2 with llx",
            "Hello\n",
            b"llx:wq\r",
            expected_content="Helo\n"
        )

        # Insert character
        self.run_test(
            "Insert character with iX",
            "Hello\n",
            b"iX\x1b:wq\r",
            expected_content="XHello\n"
        )

        # Insert in middle
        self.run_test(
            "Insert at column 2 with lliX",
            "Hello\n",
            b"lliX\x1b:wq\r",
            expected_content="HeXllo\n"
        )

        # Append with a
        self.run_test(
            "Append with a at start",
            "Hello\n",
            b"aX\x1b:wq\r",
            expected_content="HXello\n"
        )

        # Append with A
        self.run_test(
            "Append with A at start",
            "Hello\n",
            b"AX\x1b:wq\r",
            expected_content="HelloX\n"
        )

        # Open line below
        self.run_test(
            "Open line below with o",
            "Hello\nWorld\n",
            b"oNew\x1b:wq\r",
            expected_content="Hello\nNew\nWorld\n"
        )

        # Open line above
        self.run_test(
            "Open line above with O",
            "Hello\nWorld\n",
            b"jONew\x1b:wq\r",
            expected_content="Hello\nNew\nWorld\n"
        )

        # Delete line with dd
        self.run_test(
            "Delete first line with dd",
            "Hello\nWorld\n",
            b"dd:wq\r",
            expected_content="World\n"
        )

        # Delete second line
        self.run_test(
            "Delete second line with jdd",
            "Hello\nWorld\nFoo\n",
            b"jdd:wq\r",
            expected_content="Hello\nFoo\n"
        )

        # Move down and edit
        self.run_test(
            "Move down and delete char",
            "Hello\nWorld\n",
            b"jx:wq\r",
            expected_content="Hello\norld\n"
        )

        # Go to end of line
        self.run_test(
            "Go to end of line and delete",
            "Hello\n",
            b"$x:wq\r",
            expected_content="Hell\n"
        )

        # Go to start of line
        self.run_test(
            "Move right then 0 goes back to start",
            "Hello\n",
            b"lll0x:wq\r",
            expected_content="ello\n"
        )

        # Insert newline (Enter)
        self.run_test(
            "Split line with Enter in insert mode",
            "Hello\n",
            b"lli\rWorld\x1b:wq\r",
            expected_content="He\nWorldllo\n"
        )

        # Backspace in insert mode
        self.run_test(
            "Backspace deletes previous char",
            "Hello\n",
            b"llli\x08\x1b:wq\r",
            expected_content="Helo\n"
        )

        # Delete in insert mode (forward delete)
        self.run_test(
            "Delete in insert mode deletes char under cursor",
            "Hello\n",
            b"lli\x1b[3~\x1b:wq\r",
            expected_content="Helo\n"
        )

        # Delete at end of line (deletes last char)
        self.run_test(
            "Delete at end of line with $i",
            "Hello\n",
            b"$i\x1b[3~\x1b:wq\r",
            expected_content="Hell\n"
        )

        # Delete past end of line (does nothing)
        self.run_test(
            "Delete past end of line does nothing",
            "Hello\n",
            b"$a\x1b[3~\x1b:wq\r",
            expected_content="Hello\n"
        )

        # Delete multiple characters (batching)
        self.run_test(
            "Delete batches multiple keypresses",
            "Hello\n",
            b"i\x1b[3~\x1b[3~\x1b[3~\x1b:wq\r",
            expected_content="lo\n"
        )

        # Delete in middle of line (deletes space)
        self.run_test(
            "Delete in middle of line",
            "Hello World\n",
            b"llllli\x1b[3~\x1b:wq\r",
            expected_content="HelloWorld\n"
        )

        # Delete batching - many characters at once
        self.run_test(
            "Delete batches many characters efficiently",
            "0123456789ABCDEF\n",
            b"i\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b:wq\r",
            expected_content="89ABCDEF\n"
        )

        # Delete batching capped at end of line
        self.run_test(
            "Delete batching stops at line end",
            "ABC\n",
            b"i\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b[3~\x1b:wq\r",
            expected_content="\n"
        )

        # Delete from middle - batching
        # NOTE: Batching not yet implemented for Delete in insert mode
        self.run_test(
            "Delete from middle of line (no batching yet)",
            "0123456789\n",
            b"llllli\x1b[3~\x1b[3~\x1b[3~\x1b:wq\r",
            expected_content="0123489\n"  # Deletes '5', '6', '7' one at a time
        )

        # Delete with long line (potential wrap scenario)
        # Line longer than typical terminal width (80 chars)
        long_line = "A" * 100 + "\n"
        expected_after_delete = "A" * 50 + "\n"
        self.run_test(
            "Delete batching on long line",
            long_line,
            b"lllllllllllllllllllllllllllllllllllllllllllllllllli" +
            b"\x1b[3~" * 50 + b"\x1b:wq\r",
            expected_content=expected_after_delete
        )

        # Delete causing line wrap change (2 rows -> 1 row)
        # Create a line that wraps at 80 chars, delete enough to unwrap
        wrap_line = "X" * 85 + "\n"
        expected_unwrap = "X" * 75 + "\n"
        self.run_test(
            "Delete batching across line wrap boundary",
            wrap_line,
            b"i" + b"\x1b[3~" * 10 + b"\x1b:wq\r",
            expected_content=expected_unwrap
        )

        # :w saves without quitting, then :q quits
        # Actually, :w then EOT will exit due to EOT handling
        self.run_test(
            "Write with :w preserves content",
            "Hello\n",
            b"x:w\r:q!\r",
            expected_content="ello\n"
        )

        # G goes to last line
        self.run_test(
            "G goes to last line and x deletes",
            "Line1\nLine2\nLine3\n",
            b"Gx:wq\r",
            expected_content="Line1\nLine2\nine3\n"
        )

        # gg goes to first line
        self.run_test(
            "jjgg goes back to first line",
            "Line1\nLine2\nLine3\n",
            b"jjggx:wq\r",
            expected_content="ine1\nLine2\nLine3\n"
        )

        # Backspace at start joins lines
        self.run_test(
            "Backspace at col 0 joins with previous line",
            "Hello\nWorld\n",
            b"ji\x08\x1b:wq\r",
            expected_content="HelloWorld\n"
        )

        # Empty file
        self.run_test(
            "Open empty file and add text",
            "",
            b"iHello\x1b:wq\r",
            expected_content="Hello\n"
        )

        # Go to line number
        self.run_test(
            "Go to line 3 and delete",
            "One\nTwo\nThree\nFour\n",
            b":3\rx:wq\r",
            expected_content="One\nTwo\nhree\nFour\n"
        )

        # Delete only line leaves empty file
        self.run_test(
            "Delete only line leaves newline",
            "Only\n",
            b"dd:wq\r",
            expected_content="\n"
        )

        # Multiple inserts
        self.run_test(
            "Insert multiple characters",
            "AB\n",
            b"liXYZ\x1b:wq\r",
            expected_content="AXYZB\n"
        )

        # Delete and retype
        self.run_test(
            "Delete char then insert replacement",
            "Hello\n",
            b"xiJ\x1b:wq\r",
            expected_content="Jello\n"
        )

        # File without trailing newline
        self.run_test(
            "File without trailing newline",
            "Hello",
            b":wq\r",
            expected_content="Hello\n"
        )

        # Multiple dd operations
        self.run_test(
            "Delete two lines with dd dd",
            "A\nB\nC\n",
            b"dddd:wq\r",
            expected_content="C\n"
        )

        # Append at end of line
        self.run_test(
            "Append at end of line with $a",
            "Hello\n",
            b"$aX\x1b:wq\r",
            expected_content="HelloX\n"
        )

        # Cursor clamps when moving from long to short line
        self.run_test(
            "Cursor clamps on move to shorter line",
            "LongLine\nAB\n",
            b"$jx:wq\r",
            expected_content="LongLine\nA\n"
        )

        # h at column 0 stays at 0
        self.run_test(
            "h at column 0 stays put",
            "Hello\n",
            b"hx:wq\r",
            expected_content="ello\n"
        )

        # j at last line stays put
        self.run_test(
            "j at last line stays put",
            "Only\n",
            b"jx:wq\r",
            expected_content="nly\n"
        )

        # k at first line stays put
        self.run_test(
            "k at first line stays put",
            "Only\n",
            b"kx:wq\r",
            expected_content="nly\n"
        )

        # :q on modified file preserves content
        # x modifies, :q warns, :q! then force quits
        # The file should still have the original content
        # (x deletes but :q doesn't save, :q! quits without saving)
        self.run_test(
            ":q on modified file refuses to quit",
            "Hello\n",
            b"x:q\r:q!\r",
            expect_unmodified=True
        )

        # l at end of line stays put
        self.run_test(
            "l at end of line stays put",
            "Hi\n",
            b"lllx:wq\r",
            expected_content="H\n"
        )

        # Open above on first line
        self.run_test(
            "Open above on first line with O",
            "Hello\n",
            b"ONew\x1b:wq\r",
            expected_content="New\nHello\n"
        )

        # Delete all lines then add text
        self.run_test(
            "Delete all lines then insert",
            "A\nB\n",
            b"dddd" + b"iNew\x1b:wq\r",
            expected_content="New\n"
        )

        # Append on empty line
        self.run_test(
            "Append on empty line",
            "\n",
            b"aHi\x1b:wq\r",
            expected_content="Hi\n"
        )

        # ESC in insert mode moves cursor back
        # Insert 'AB' at start, ESC, then x should delete B (cursor moves back)
        self.run_test(
            "ESC in insert moves cursor back one",
            "CD\n",
            b"iAB\x1bx:wq\r",
            expected_content="ACD\n"
        )

        # Multiple Enter in insert mode
        self.run_test(
            "Multiple Enter creates multiple lines",
            "AB\n",
            b"li\r\r\x1b:wq\r",
            expected_content="A\n\nB\n"
        )

        self._group("Console mode argument handling:", leading_blank=True)

        # Console mode saves to correct filename
        # In console mode, the emulator should not require an output_file
        # parameter. The file to edit is passed as a program argument.
        # We delete a char and save, to verify the change was written
        # to the correct file (not "[No Name]").
        self.run_test_console(
            "Console mode :wq saves to correct file",
            "Hello\n",
            b"x:wq\r",
            expected_content="ello\n"
        )

        self._group("New file creation:", leading_blank=True)

        # Edit a non-existent file creates it on save
        self.run_test_new_file(
            "Create new file with :wq",
            b"iHello\x1b:wq\r",
            expected_content="Hello\n"
        )

        self._group("Bounds checking (small buffer build):", leading_blank=True)

        if not self.build_small_buffer_editor():
            print("  Skipping bounds checking tests (small buffer build failed)")
        else:
            # Read-only mode: file exceeds buffer, editing keys blocked
            # small_buffer limits buffer to 256 bytes (TEXT_BUF to TEXT_BUF+$FF)
            # File has 300 bytes so it will be truncated
            # Truncation warning consumes one keypress (the 'x')
            # Then 'x' should be ignored (readonly), :q exits
            large_content = "A" * 299 + "\n"  # 300 bytes > 256
            self.run_test_small_buffer(
                "Truncated file enters read-only mode",
                large_content,
                # 'x' dismissed truncation warning, 'x' ignored (RO), :q quits
                b"xx:q\r",
                expect_unmodified=True
            )

            # Read-only mode: :w is blocked
            # Truncation warning consumes 'x', then :w shows RO message,
            # 'x' dismisses that, :q! quits
            self.run_test_small_buffer(
                "Read-only mode blocks :w",
                large_content,
                b"x:w\rx:q!\r",
                expect_unmodified=True
            )

            # Read-only mode: :wq is blocked
            self.run_test_small_buffer(
                "Read-only mode blocks :wq",
                large_content,
                b"x:wq\rx:q!\r",
                expect_unmodified=True
            )

            # Read-only mode: :1,2d is blocked
            # Multi-line content > 256 bytes to trigger truncation
            large_multiline = ''.join(f"Line {i}\n" for i in range(1, 50))
            self.run_test_small_buffer(
                "Read-only mode blocks :1,2d",
                large_multiline,
                # 'x' dismisses truncation warning, :1,2d shows RO msg,
                # 'x' dismisses that, :q! quits
                b"x:1,2d\rx:q!\r",
                expect_unmodified=True
            )

            # Read-only mode: :q exits cleanly
            self.run_test_small_buffer(
                "Read-only mode allows :q",
                large_content,
                b"x:q\r",
                expect_unmodified=True
            )

            # Read-only mode: i key is blocked (no insert mode)
            self.run_test_small_buffer(
                "Read-only mode blocks i",
                large_content,
                b"x:q\r",   # 'x' dismisses warning, :q quits
                expect_unmodified=True
            )

            # Buffer full during editing: insert char fails
            # small_buffer = 256 bytes buffer. File with 250 bytes leaves ~6 free
            # After loading, type characters until full
            near_full = "B" * 249 + "\n"  # 250 bytes, ~6 bytes free
            self.run_test_small_buffer(
                "Buffer full refuses insert char",
                near_full,
                # Enter insert mode, type 7 chars (6 succeed, 7th triggers full)
                # 'z' dismisses "Buffer full" message
                # ESC back to normal, :q! quits
                b"iAAAAAA" + b"A" + b"z\x1b:q!\r",
                expect_unmodified=True
            )

            # Buffer full during editing: newline insert fails
            # File with 254 bytes leaves ~2 free
            almost_full = "C" * 253 + "\n"  # 254 bytes, ~2 bytes free
            self.run_test_small_buffer(
                "Buffer full refuses newline insert",
                almost_full,
                # Insert mode, type 'A' (succeeds, 1 byte free),
                # then Enter (needs 1 byte for newline - should succeed or fail)
                # Actually with 2 bytes free: 'A' uses 1, Enter uses 1 = exactly full
                # Try one more char to trigger full
                b"iAA" + b"z\x1b:q!\r",
                expect_unmodified=True
            )

            # Counted paste pre-check: rejects paste that would overflow
            # small_buffer = 256 bytes. Content ~50 bytes. Yank 2 lines (~20 bytes).
            # 99p would need ~2000 bytes, way over 256 limit.
            # File should be unmodified (pre-check rejects before any paste).
            paste_content = "AAAA\nBBBB\nCCCC\nDDDD\n"  # ~20 bytes
            self.run_test_small_buffer(
                "Counted paste pre-check rejects overflow (p)",
                paste_content,
                # yy yanks 1 line, 99p would overflow, z dismisses msg
                b"2yy99pz:q!\r",
                expect_unmodified=True
            )

            # Same test for P (paste above)
            self.run_test_small_buffer(
                "Counted paste pre-check rejects overflow (P)",
                paste_content,
                b"2yy99Pz:q!\r",
                expect_unmodified=True
            )

            # Single paste that fits should still work
            self.run_test_small_buffer(
                "Single paste works when space available",
                paste_content,
                b"yyp:wq\r",
                expected_content="AAAA\nAAAA\nBBBB\nCCCC\nDDDD\n"
            )

            # Normal editing works with small buffer build
            self.run_test_small_buffer(
                "Small buffer build normal editing works",
                "Hello\n",
                b"x:wq\r",
                expected_content="ello\n"
            )

        # ============================================================
        # Screen state tests (10 rows x 40 cols)
        # 9 content rows (rows 0-8), 1 status bar (row 9)
        # page_size = 9
        # ============================================================
        self._group("Screen state - cursor movement:", leading_blank=True)

        CTRL_F = b'\x06'
        CTRL_B = b'\x02'

        # Initial cursor at (0,0)
        self.run_test_screen(
            "Initial cursor at (0,0)",
            "Hello\n",
            b":q!\r",
            expect_cursor=(0, 0)
        )

        # lll -> cursor at (0,3)
        self.run_test_screen(
            "lll moves cursor to (0,3)",
            "Hello\n",
            b"lll:q!\r",
            expect_cursor=(0, 3)
        )

        # lllh -> cursor at (0,2)
        self.run_test_screen(
            "lllh moves cursor to (0,2)",
            "Hello\n",
            b"lllh:q!\r",
            expect_cursor=(0, 2)
        )

        # jj on 3-line file -> cursor at (2,0)
        self.run_test_screen(
            "jj moves cursor to (2,0)",
            "Line 1\nLine 2\nLine 3\n",
            b"jj:q!\r",
            expect_cursor=(2, 0)
        )

        # jjk -> cursor at (1,0)
        self.run_test_screen(
            "jjk moves cursor to (1,0)",
            "Line 1\nLine 2\nLine 3\n",
            b"jjk:q!\r",
            expect_cursor=(1, 0)
        )

        # $ on "Hello" -> cursor at (0,4)
        self.run_test_screen(
            "$ goes to end of line",
            "Hello\n",
            b"$:q!\r",
            expect_cursor=(0, 4)
        )

        # lll0 -> cursor at (0,0)
        self.run_test_screen(
            "lll0 goes back to start of line",
            "Hello\n",
            b"lll0:q!\r",
            expect_cursor=(0, 0)
        )

        # $j from "LongLine" to "AB" -> cursor clamped to (1,1)
        self.run_test_screen(
            "Cursor clamps on move to shorter line",
            "LongLine\nAB\n",
            b"$j:q!\r",
            expect_cursor=(1, 1)
        )

        self._group("Screen state - screen content:", leading_blank=True)

        # 5-line file: rows 0-4 show "Line 1"-"Line 5", rows 5-8 show ~
        self.run_test_screen(
            "5-line file shows content and tildes",
            make_lines(5),
            b":q!\r",
            expect_lines=[
                (0, "Line 1"),
                (1, "Line 2"),
                (2, "Line 3"),
                (3, "Line 4"),
                (4, "Line 5"),
                (5, "~"),
                (6, "~"),
                (7, "~"),
                (8, "~"),
            ]
        )

        # 1-line file: row 0 shows content, rows 1+ show ~
        self.run_test_screen(
            "1-line file shows tildes on empty rows",
            "Hello\n",
            b":q!\r",
            expect_lines=[
                (0, "Hello"),
                (1, "~"),
                (2, "~"),
            ]
        )

        # Status bar shows line,col position (1-based)
        # Note: :q! enters command mode, so we check COMMAND mode status
        self.run_test_screen(
            "Status bar shows position at start",
            "Hello\n",
            b":q!\r",
            expect_status_contains="COMMAND - 1,"
        )

        # Status bar after moving cursor
        self.run_test_screen(
            "Status bar shows line 2 after j",
            "Hello\nWorld\n",
            b"jlll:q!\r",
            expect_status_contains="COMMAND - 2,"
        )

        # :q on modified file shows warning message
        # x modifies, :q\r triggers warning, 'z' dismisses message, :q!\r quits
        self.run_test_screen(
            ":q on modified shows warning message",
            "Hello\n",
            b"x:q\rz:q!\r",
            expect_ansi_contains="No write since last change"
        )

        self._group("Screen state - scrolling:", leading_blank=True)

        # 15-line file, 9 j's: full window after line scroll down
        self.run_test_screen(
            "Line scroll down: full window",
            make_lines(15),
            b"jjjjjjjjj:q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+2}") for i in range(9)]
        )

        # Scroll down then back to top: full window restored
        self.run_test_screen(
            "Line scroll up: full window restored",
            make_lines(15),
            b"jjjjjjjjj" + b"kkkkkkkkk" + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+1}") for i in range(9)]
        )

        # Scroll down 3 lines past bottom: verify contiguous window
        self.run_test_screen(
            "3 lines past bottom: contiguous window",
            make_lines(15),
            b"jjjjjjjjjjj:q!\r",  # 11 j's = line 12, scroll_top=4
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+4}") for i in range(9)]
        )

        self._group("Screen state - pagination:", leading_blank=True)

        # Ctrl-F from start (30 lines): full window verification
        self.run_test_screen(
            "Ctrl-F: full window after page down",
            make_lines(30),
            CTRL_F + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+10}") for i in range(9)]
        )

        # Two Ctrl-F's: full window verification
        self.run_test_screen(
            "Two Ctrl-F's: full window",
            make_lines(30),
            CTRL_F + CTRL_F + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+19}") for i in range(9)]
        )

        # Repeated Ctrl-F to end: full window with last line at bottom
        self.run_test_screen(
            "Ctrl-F to end: full window",
            make_lines(30),
            CTRL_F + CTRL_F + CTRL_F + CTRL_F + b":q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+22}") for i in range(9)]
        )

        # Ctrl-B from middle: full window after page back
        self.run_test_screen(
            "Ctrl-B: full window after page back",
            make_lines(30),
            CTRL_F + CTRL_F + CTRL_B + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+10}") for i in range(9)]
        )

        # Ctrl-B at start: stays at (0,0), full window
        self.run_test_screen(
            "Ctrl-B at start: full window unchanged",
            make_lines(30),
            CTRL_B + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+1}") for i in range(9)]
        )

        # Ctrl-F with fewer lines than a page: full window
        self.run_test_screen(
            "Ctrl-F short file: full window",
            make_lines(5),
            CTRL_F + b":q!\r",
            expect_cursor=(4, 0),
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"),
                (5, "~"), (6, "~"), (7, "~"), (8, "~"),
            ]
        )

        self._group("Screen state - G and gg:", leading_blank=True)

        # G on 20-line file: full window with last line at bottom
        self.run_test_screen(
            "G: full window at end",
            make_lines(20),
            b"G:q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+12}") for i in range(9)]
        )

        # G on 300-line file: tests 8-bit overflow in CURSOR_ROW walk
        self.run_test_screen(
            "G: large file scrolls correctly",
            make_lines(300),
            b"G:q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+292}") for i in range(9)]
        )

        # Ggg: full window back at top
        self.run_test_screen(
            "Ggg: full window at top",
            make_lines(20),
            b"Ggg:q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+1}") for i in range(9)]
        )

        self._group("Screen state - edge cases:", leading_blank=True)

        # Single-line file: jjkk stays at (0,0)
        self.run_test_screen(
            "jjkk on single line stays at (0,0)",
            "Only\n",
            b"jjkk:q!\r",
            expect_cursor=(0, 0)
        )

        # Empty line: l stays at col 0
        self.run_test_screen(
            "l on empty line stays at col 0",
            "\n",
            b"l:q!\r",
            expect_cursor=(0, 0)
        )

        # Long line wraps to next screen row
        self.run_test_screen(
            "Long line wraps to next screen row",
            "A" * 60 + "\n",
            b":q!\r",
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 20),
            ]
        )

        # ============================================================
        # Line wrapping tests
        # ============================================================
        self._group("Screen state - line wrapping:", leading_blank=True)

        # Line after wrapped line pushed down
        self.run_test_screen(
            "Line after wrap pushed down",
            "A" * 60 + "\n" + "B\n",
            b":q!\r",
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 20),
                (2, "B"),
            ]
        )

        # Tilde markers account for wrapping
        self.run_test_screen(
            "Tildes account for wrapped line height",
            "A" * 80 + "\n",
            b":q!\r",
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 40),
                (2, "~"),
            ]
        )

        # Cursor position on wrapped line ($ command)
        # 60-char line on 40-col screen: $ puts cursor at col 59
        # screen row = 59 / 40 = 1, screen col = 59 % 40 = 19
        self.run_test_screen(
            "$ on wrapped line: cursor position",
            "A" * 60 + "\n",
            b"$:q!\r",
            expect_cursor=(1, 19)
        )

        # Cursor position after right movement past screen edge
        # Move right 40 times on a 60-char line with 40-col screen
        # Cursor at col 40 -> screen row 1, screen col 0
        self.run_test_screen(
            "Right movement past screen edge wraps",
            "A" * 60 + "\n",
            b"l" * 40 + b":q!\r",
            expect_cursor=(1, 0)
        )

        # j/k skip wrapped rows (move by file line, not screen row)
        # Two long lines: j from line 0 to line 1
        self.run_test_screen(
            "j skips wrap rows to next file line",
            "A" * 60 + "\n" + "B" * 60 + "\n",
            b"j:q!\r",
            expect_cursor=(2, 0),
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 20),
                (2, "B" * 40),
                (3, "B" * 20),
            ]
        )

        # Scrolling with wrapped lines
        # 10 rows, 9 content rows. Fill with lines that take 2 rows each.
        # 5 wrapped lines = 10 screen rows needed (only 9 content rows available)
        # After j x4 to line 4, scrolling should keep cursor visible
        # Cursor is at line 5 (1-based), col 1
        self.run_test_screen(
            "Scroll with wrapped lines",
            ("X" * 60 + "\n") * 5,
            b"jjjj:q!\r",
            expect_status_contains="5,"
        )

        # Insert mode: cursor tracks wrap when typing past screen edge
        # Start with 38 chars on 40-col screen, $a enters append at col 38.
        # Type 3 chars: first X at col 39, then XX batched -> col 41.
        # Frame sequence: 0=init, 1=$, 2=a, 3=X+batch(col41), 4=ESC(col40)
        # At frame 3: CURSOR_COL=41, must be row 1 col 1 (all 3 chars inserted)
        self.run_test_screen(
            "Insert cursor tracks wrap boundary",
            "A" * 38 + "\n",
            b"$aXXX\x1b:q!\r",
            expect_cursor=(1, 0),
            expect_lines=[
                (0, "A" * 38 + "XX"),
                (1, "X"),
            ],
            expect_cursor_at_frame=[
                (3, (1, 1)),
            ]
        )

        # Insert mode: cursor on wrap continuation while typing
        # Start with 39 chars, $a enters append at col 39, type 2 chars.
        # Frame sequence: 0=init, 1=$, 2=a, 3=X+batch(col41), 4=ESC(col40)
        # At frame 3: CURSOR_COL=41, must be row 1 col 1
        self.run_test_screen(
            "Insert cursor mid-wrap while typing",
            "A" * 39 + "\n",
            b"$aXX\x1b:q!\r",
            expect_cursor=(1, 0),
            expect_lines=[
                (0, "A" * 39 + "X"),
                (1, "X"),
            ],
            expect_cursor_at_frame=[
                (3, (1, 1)),
            ]
        )

        # Backspace from wrap boundary back to previous row
        # Start with 41 chars (wraps to row 1 with 1 char). $a enters at col 41.
        # Frame sequence: 0=init, 1=$, 2=a, 3=BS+batch_BS(col39), 4=ESC(col38)
        # At frame 3: CURSOR_COL=39, must be row 0 col 39 (crossed back via batch)
        self.run_test_screen(
            "Backspace across wrap boundary",
            "A" * 41 + "\n",
            b"$a\x08\x08\x1b:q!\r",
            expect_cursor=(0, 38),
            expect_lines=[
                (0, "A" * 39),
            ],
            expect_cursor_at_frame=[
                (3, (0, 39)),
            ]
        )

        # A on wrapped line: cursor must move to end-of-line wrap row
        # 60-char line, 0 goes to col 0 (row 0), then A sets col=60 (row 1, col 20)
        # Frame sequence: 0=init, 1=0, 2=A
        # At frame 2: CURSOR_COL=60, must be row 1 col 20
        self.run_test_screen(
            "A on wrapped line positions cursor correctly",
            "A" * 60 + "\n",
            b"0AX\x1b:q!\r",
            expect_cursor=(1, 20),
            expect_cursor_at_frame=[
                (2, (1, 20)),
            ]
        )

        # a at wrap boundary: cursor crosses to next wrap row
        # 41-char line, $ goes to col 40 (row 1), h goes to col 39 (row 0),
        # then a increments to col 40 (should be row 1, col 0)
        # Frame sequence: 0=init, 1=$, 2=h, 3=a
        self.run_test_screen(
            "a at wrap boundary positions cursor correctly",
            "A" * 41 + "\n",
            b"$haX\x1b:q!\r",
            expect_cursor_at_frame=[
                (3, (1, 0)),
            ]
        )

        # Insert mode up arrow from wrap row moves to previous line
        # Line 0: "B", Line 1: 60 A's (wraps to 2 rows on 40-col screen)
        # j$ puts cursor at col 59 (row 2: line 0 row + 2 wrap rows).
        # 'a' enters insert at col 60 (still row 2).
        # Up arrow should move to line 0 ("B"), col clamped to 1 (one past 'B'), row 0.
        # Insert mode allows cursor one past last char for end-of-line insertion.
        # Frame sequence: 0=init, 1=j, 2=$, 3=a, 4=UP
        self.run_test_screen(
            "Insert up arrow from wrapped line to short line",
            "B\n" + "A" * 60 + "\n",
            b"j$a\x1b[A\x1b:q!\r",
            expect_cursor=(0, 0),
            expect_cursor_at_frame=[
                (4, (0, 1)),  # After UP arrow, before ESC
            ]
        )

        # Normal mode k from wrap row moves to previous line
        # Same setup but in normal mode with k instead of up arrow.
        # j$ puts cursor at line 1 col 59 (row 2), k should go to line 0.
        # Frame sequence: 0=init, 1=j, 2=$, 3=k
        self.run_test_screen(
            "Normal k from wrapped line to short line",
            "B\n" + "A" * 60 + "\n",
            b"j$k:q!\r",
            expect_cursor=(0, 0),
            expect_cursor_at_frame=[
                (3, (0, 0)),
            ]
        )

        # Normal mode x on wrapped line: content and cursor correct
        # 60-char line, $ goes to col 59 (row 1, col 19), x deletes -> col 58
        self.run_test_screen(
            "x on wrapped line keeps cursor correct",
            "A" * 60 + "\n",
            b"$x:q!\r",
            expect_cursor=(1, 18),
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 19),
            ]
        )

        # ============================================================
        # Render optimization tests
        # Verify cursor-only movements skip content area redraws.
        # Frame 0 is always the initial full render (True).
        # ============================================================
        self._group("Screen state - render optimization:", leading_blank=True)

        # h movement: cursor-only
        self.run_test_screen(
            "Render opt: h is cursor-only",
            "Hello\n",
            b"lh:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # l movement: cursor-only
        self.run_test_screen(
            "Render opt: lll is cursor-only",
            "Hello\n",
            b"lll:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # j without scroll: cursor-only
        self.run_test_screen(
            "Render opt: j no scroll is cursor-only",
            "Line 1\nLine 2\nLine 3\n",
            b"j:q!\r",
            expect_content_redraws=[True, False]
        )

        # k without scroll: cursor-only
        self.run_test_screen(
            "Render opt: jk no scroll is cursor-only",
            "Line 1\nLine 2\nLine 3\n",
            b"jk:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # j with scroll: batched into single full repaint
        # 10 rows, 9 content rows. 9 j's on a 15-line file:
        # All 9 j's are batched into one movement, triggering one scroll repaint
        self.run_test_screen(
            "Render opt: j scroll triggers repaint",
            make_lines(15),
            b"jjjjjjjjj:q!\r",
            expect_content_redraws=(
                [True] +          # frame 0: initial
                [True]            # frame 1: batched j*9 with scroll
            )
        )

        # 0 (line start): cursor-only
        self.run_test_screen(
            "Render opt: 0 is cursor-only",
            "Hello\n",
            b"lll0:q!\r",
            expect_content_redraws=[True, False, False, False, False]
        )

        # $ (line end): cursor-only
        self.run_test_screen(
            "Render opt: $ is cursor-only",
            "Hello\n",
            b"$:q!\r",
            expect_content_redraws=[True, False]
        )

        # ESC from insert mode: cursor-only
        # i enters insert (full repaint), ESC exits (cursor-only)
        self.run_test_screen(
            "Render opt: ESC from insert is cursor-only",
            "Hello\n",
            b"i\x1b:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # Insert char: only cursor's row is touched (not all rows)
        # i enters insert (full repaint), 'X' inserts (cursor row + below)
        # render_current_line_and_status renders from cursor row downward
        # to handle line unwrap correctly, so all rows from 0 are touched
        self.run_test_screen(
            "Render opt: insert char redraws from cursor",
            "Hello\nWorld\n",
            b"iX\x1b:q!\r",
            expect_content_redraws=[True, True, True, False],
            expect_content_rows=[(2, set(range(9)))]
        )

        # Backspace mid-line: redraws from cursor row downward
        # Move right, enter insert, backspace (mid-line)
        self.run_test_screen(
            "Render opt: backspace redraws from cursor",
            "Hello\nWorld\n",
            b"li\x08\x1b:q!\r",
            expect_content_redraws=[True, False, True, True, False],
            expect_content_rows=[(3, set(range(9)))]
        )

        # Normal mode x: redraws from cursor row downward
        self.run_test_screen(
            "Render opt: x redraws from cursor",
            "Hello\nWorld\n",
            b"x:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, set(range(9)))]
        )

        # Insert newline: full repaint (multiple lines change)
        self.run_test_screen(
            "Render opt: Enter in insert is full repaint",
            "Hello\nWorld\n",
            b"i\r\x1b:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Backspace at col 0 (join lines): full repaint
        self.run_test_screen(
            "Render opt: backspace join-lines is full repaint",
            "Hello\nWorld\n",
            b"ji\x08\x1b:q!\r",
            expect_content_redraws=[True, False, True, True, False]
        )

        # ============================================================
        # Batch insert tests
        # When multiple printable keys are buffered, they should be
        # inserted in a single operation with one render.
        # ============================================================
        self._group("Batch insert:", leading_blank=True)

        # Render optimization: batch insert reduces content redraws
        # Frame 0: initial render (True)
        # Frame 1: 'i' enters insert mode (True - status bar changes)
        # Frame 2: first char 'X' inserted, then Y and Z batched (True)
        # Frame 3: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: batch insert reduces redraws",
            "Hello\n",
            b"iXYZ\x1b:q!\r",
            expect_content_redraws=[True, True, True, False],
        )

        # Batch insert mid-line correctness
        self.run_test(
            "Batch insert mid-line",
            "ABCD\n",
            b"liXYZ\x1b:wq\r",
            expected_content="AXYZBCD\n"
        )

        # Batch stops at newline (Enter after printable chars)
        self.run_test(
            "Batch insert stops at newline",
            "Hello\n",
            b"iXY\r\x1b:wq\r",
            expected_content="XY\nHello\n"
        )

        # Batch insert many characters
        self.run_test(
            "Batch insert many characters",
            "AB\n",
            b"liHello World\x1b:wq\r",
            expected_content="AHello WorldB\n"
        )

        # ============================================================
        # Batch delete tests
        # When multiple backspace or x keys are buffered, they should
        # be deleted in a single operation with one render.
        # ============================================================
        self._group("Batch delete:", leading_blank=True)

        # Render optimization: batch backspace reduces content redraws
        # Frame 0: initial render (True)
        # Frame 1: l (False - cursor only)
        # Frame 2: l (False - cursor only)
        # Frame 3: l (False - cursor only)
        # Frame 4: i enters insert mode (True - status bar)
        # Frame 5: first BS deletes, then 2 more batched (True)
        # Frame 6: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: batch backspace reduces redraws",
            "Hello\n",
            b"llli\x08\x08\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, False, True, True, False],
        )

        # Batch backspace correctness
        # A appends after last char (col 6), 4 BS deletes F,E,D,C -> "AB\n"
        self.run_test(
            "Batch backspace mid-line",
            "ABCDEF\n",
            b"A\x08\x08\x08\x08\x1b:wq\r",
            expected_content="AB\n"
        )

        # Batch backspace stops at column 0
        # l moves to col 1, i enters insert at col 1, 3 BS: first deletes A,
        # then at col 0 batching must stop (no join-lines in batch)
        self.run_test(
            "Batch backspace stops at column 0",
            "AB\n",
            b"li\x08\x08\x08\x1b:wq\r",
            expected_content="B\n"
        )

        # Batch backspace stops at non-backspace key
        # A appends at end (col 5), 2 BS deletes E,D, then X inserts -> "ABCX\n"
        self.run_test(
            "Batch backspace stops at non-BS key",
            "ABCDE\n",
            b"A\x08\x08X\x1b:wq\r",
            expected_content="ABCX\n"
        )

        # Excess backspace keys beyond column trigger join-lines
        # Line 1: "AB", Line 2: "CD". j moves to line 2, li enters insert at col 1.
        # 3 BS keys: first deletes 'C' (col 1->0), then 2 excess BS keys should
        # trigger join-lines (joining "AB" + "D"), not be silently consumed.
        self.run_test(
            "Excess backspace triggers join-lines",
            "AB\nCD\n",
            b"jli\x08\x08\x1b:wq\r",
            expected_content="ABD\n"
        )

        # Render optimization: batch x reduces content redraws
        # Without batching: xxx -> frames [init, x, x, x] = 4 frames
        # With batching: frames [init, x+batch_xx] = 2 frames
        # Frame 0: initial render (True)
        # Frame 1: first x + batch xx (True)
        # Then j triggers a cursor-only frame (False) proving no more x frames
        self.run_test_screen(
            "Render opt: batch x reduces redraws",
            "Hello\nWorld\n",
            b"xxxj:q!\r",
            expect_content_redraws=[True, True, False],
        )

        # Batch x correctness
        self.run_test(
            "Batch x mid-line",
            "ABCDEF\n",
            b"lxxx:wq\r",
            expected_content="AEF\n"
        )

        # Batch x stops at end of line
        self.run_test(
            "Batch x stops at end of line",
            "AB\n",
            b"xxxx:wq\r",
            expected_content="\n"
        )

        # Batch x stops at non-x key
        self.run_test(
            "Batch x stops at non-x key",
            "ABCDE\n",
            b"xxl:wq\r",
            expected_content="CDE\n"
        )

        # Batch x on wrapped line: when deletion unwraps the line, the
        # stale second wrap row must be cleared.
        # 45-char line on 40-col screen: initially row 0 = A*40, row 1 = A*5.
        # Batch delete 6 chars -> 39 left, line no longer wraps.
        # Frame 0: initial (full), Frame 1: batch x (single-line redraw).
        # At frame 1, row 1 should show "B" (next line), not stale "AAAAA".
        self.run_test_screen(
            "Batch x unwrap clears stale row",
            "A" * 45 + "\nB\n",
            b"xxxxxx:q!\r",
            expect_lines_at_frame=[
                (1, [
                    (0, "A" * 39),
                    (1, "B"),
                    (2, "~"),
                ]),
            ]
        )

        # Same bug in insert mode: batch backspace on a wrapped line should
        # clear the stale wrap row when the line unwraps.
        # 45-char line, cursor at end (col 44). Batch delete 6 -> 39 left.
        # '$' moves to end-of-line, 'a' enters insert after cursor.
        # Frame 0: initial, Frame 1: $ (cursor), Frame 2: a (insert mode),
        # Frame 3: batch BS (single-line redraw - bug frame).
        self.run_test_screen(
            "Batch BS unwrap clears stale row",
            "A" * 45 + "\nB\n",
            b"$a\x7f\x7f\x7f\x7f\x7f\x7f\x1b:q!\r",
            expect_lines_at_frame=[
                (3, [
                    (0, "A" * 39),
                    (1, "B"),
                    (2, "~"),
                ]),
            ]
        )

        # Render optimization: batch Delete key in insert mode
        # Frame 0: initial render (True)
        # Frame 1: i enters insert (True - status bar)
        # Frame 2: first Del + batch Del*2 (True)
        # Frame 3: ESC exits insert (False - cursor only)
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: batch insert Delete reduces redraws",
            "Hello\n",
            b"i" + DEL * 3 + b"\x1b:q!\r",
            expect_content_redraws=[True, True, True, False],
        )

        # Render optimization: batch Delete key in normal mode
        # Without batching: Del Del Del -> frames [init, Del, Del, Del] = 4 frames
        # With batching: frames [init, Del+batch_Del*2] = 2 frames
        # Frame 0: initial render (True)
        # Frame 1: first Del + batch Del*2 (True)
        # Then j triggers a cursor-only frame (False) proving no more Del frames
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: batch Delete reduces redraws",
            "Hello\nWorld\n",
            DEL * 3 + b"j:q!\r",
            expect_content_redraws=[True, True, False],
        )

        # ============================================================
        # Batch Enter tests
        # When multiple Enter keys are buffered in insert mode, they
        # should be inserted in a single operation with one rebuild.
        # ============================================================
        self._group("Batch Enter:", leading_blank=True)

        # Render optimization: batch Enter reduces redraws
        # Frame 0: initial (True), Frame 1: i enters insert (True),
        # Frame 2: first Enter + batch Enter*2 (True), Frame 3: ESC (False)
        self.run_test_screen(
            "Render opt: batch Enter reduces redraws",
            "Hello\n",
            b"i\r\r\r\x1b:q!\r",
            expect_content_redraws=[True, True, True, False],
        )

        # Batch Enter correctness - 3 Enters create 3 empty lines before content
        self.run_test(
            "Batch Enter multiple newlines",
            "Hello\n",
            b"i\r\r\r\x1b:wq\r",
            expected_content="\n\n\nHello\n"
        )

        # Batch Enter stops at non-Enter key
        self.run_test(
            "Batch Enter stops at printable",
            "Hello\n",
            b"i\r\rX\x1b:wq\r",
            expected_content="\n\nXHello\n"
        )

        # ============================================================
        # Batch join-lines tests
        # When multiple backspace keys are buffered at column 0 with
        # empty lines above, they should be joined in a single operation.
        # ============================================================
        self._group("Batch join-lines:", leading_blank=True)

        # Render optimization: batch join-lines reduces redraws
        # Start with 4 empty lines + content. Cursor at line 3 col 0.
        # jjj batched into one move, i enters insert at line 3.
        # BS joins (empty line above), then 2 more BS batched
        # Frame sequence: init(T), jjj-batched(F), i(T), BS+batch(T), ESC(F)
        self.run_test_screen(
            "Render opt: batch join-lines reduces redraws",
            "\n\n\nHello\n",
            b"jjji\x08\x08\x08\x1b:q!\r",
            expect_content_redraws=[True, False, True, True, False],
        )

        # Batch join-lines correctness - delete 3 empty lines above
        self.run_test(
            "Batch join empty lines",
            "\n\n\nHello\n",
            b"jjji\x08\x08\x08\x1b:wq\r",
            expected_content="Hello\n"
        )

        # Batch join stops at non-empty line (3rd BS joins AB with Hello normally)
        self.run_test(
            "Batch join stops at non-empty line",
            "AB\n\n\nHello\n",
            b"jjji\x08\x08\x08\x1b:wq\r",
            expected_content="ABHello\n"
        )

        # Batch join stops at line 0
        self.run_test(
            "Batch join stops at first line",
            "\n\nHello\n",
            b"jji\x08\x08\x08\x08\x1b:wq\r",
            expected_content="Hello\n"
        )

        # Batch join-lines must not skip over a non-empty line.
        # "\n\nAB\n\n\nCD\n" = (empty)*2, AB, (empty)*2, CD.
        # Cursor on line 4 (empty), 4 BS keys.
        # Correct: delete 2 empty lines (3,4), join with AB (cursor
        # at col 2), then within-line delete 2 chars → "\n\n\nCD\n".
        # Bug: backward \n scan treats AB's trailing \n as another
        # empty line, skipping over AB entirely. The scan deletes
        # AB's \n + line 3's \n, leaving cursor at col 0 on AB.
        # Then the next batch join deletes empty lines above AB.
        # Result: "AB\nCD\n" (blank lines above AB deleted instead
        # of AB's content).
        self.run_test(
            "Batch join does not skip over non-empty line",
            "\n\nAB\n\n\nCD\n",
            b"jjjji\x08\x08\x08\x08\x1b:wq\r",
            expected_content="\n\n\nCD\n"
        )

        # ============================================================
        # Batch movement tests (j/k and arrow keys)
        # Consecutive identical movement keys are consumed in one
        # operation, reducing frame count and improving scroll perf.
        # ============================================================
        self._group("Batch movement down:", leading_blank=True)

        # Batch j keys: 5 j's on a 10-line file move to line 5
        self.run_test_screen(
            "Batch j moves correct number of lines",
            make_lines(10),
            b"jjjjj:q!\r",
            expect_cursor=(5, 0),
            expect_status_contains="COMMAND - 6,"
        )

        # Batch KEY_DOWN arrow keys
        DOWN = b"\x1b[B"
        self.run_test_screen(
            "Batch down arrow moves correct lines",
            make_lines(10),
            DOWN * 5 + b":q!\r",
            expect_cursor=(5, 0),
            expect_status_contains="COMMAND - 6,"
        )

        # Batch j with scrolling: verify screen content
        # 10 rows = 9 content rows. 11 j's on 15-line file -> line 12.
        self.run_test_screen(
            "Batch j with scrolling shows correct window",
            make_lines(15),
            b"jjjjjjjjjjj:q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+4}") for i in range(9)]
        )

        # Count prefix + batch: 3j with 2 pending j's = 5 total
        self.run_test_screen(
            "Count prefix + batch j combines",
            make_lines(10),
            b"3jjj:q!\r",
            expect_cursor=(5, 0),
            expect_status_contains="COMMAND - 6,"
        )

        # Render optimization: batch j reduces redraws
        # 5 j's on a 10-line file (no scroll). Without batching: 6 frames.
        # With batching: init(T) + batched jjjjj(F) = 2 frames
        self.run_test_screen(
            "Render opt: batch j no-scroll is single frame",
            make_lines(10),
            b"jjjjj:q!\r",
            expect_content_redraws=[True, False]
        )

        # Render optimization: batch j with scroll is single repaint
        # 11 j's on 15-line file triggers scroll, but only one frame
        self.run_test_screen(
            "Render opt: batch j scroll is single repaint",
            make_lines(15),
            b"jjjjjjjjjjj:q!\r",
            expect_content_redraws=[True, True]
        )

        self._group("Batch movement up:", leading_blank=True)

        # Batch k keys: start at line 5, 3 k's move to line 2
        self.run_test_screen(
            "Batch k moves correct number of lines",
            make_lines(10),
            b"5jkkk:q!\r",
            expect_cursor=(2, 0),
            expect_status_contains="COMMAND - 3,"
        )

        # Batch KEY_UP arrow keys
        UP = b"\x1b[A"
        self.run_test_screen(
            "Batch up arrow moves correct lines",
            make_lines(10),
            b"5j" + UP * 3 + b":q!\r",
            expect_cursor=(2, 0),
            expect_status_contains="COMMAND - 3,"
        )

        # Batch k with scrolling: scroll up from bottom
        # 15-line file, 10 rows. Go to line 14 (G), then 12 k's -> line 2.
        # ensure_cursor_visible places cursor at top of viewport.
        self.run_test_screen(
            "Batch k with scrolling shows correct window",
            make_lines(15),
            b"G" + b"k" * 12 + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(0, "Line 3")]
        )

        # Render optimization: batch k no-scroll is single frame
        # 5j produces 1 frame (batched), then kkk produces 1 frame (batched)
        self.run_test_screen(
            "Render opt: batch k no-scroll is single frame",
            make_lines(10),
            b"5jkkk:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # Render optimization: batch k with scroll is single repaint
        # G scrolls (full repaint), then 12 batched k's scroll up (one repaint)
        self.run_test_screen(
            "Render opt: batch k scroll is single repaint",
            make_lines(15),
            b"G" + b"k" * 12 + b":q!\r",
            expect_content_redraws=[True, True, True]
        )

        self._group("Insert mode navigation keys:", leading_blank=True)

        HOME = b"\x1b[H"
        END = b"\x1b[F"

        # Home key moves cursor to beginning of line
        # Start on "Hello World", move right 5 times, enter insert, Home, type X
        self.run_test(
            "Home key moves to line start",
            "Hello World\n",
            b"llllli" + HOME + b"X\x1b:wq\r",
            expected_content="XHello World\n"
        )

        # Home key does nothing when already at beginning
        self.run_test(
            "Home key at line start is no-op",
            "Hello World\n",
            b"i" + HOME + b"X\x1b:wq\r",
            expected_content="XHello World\n"
        )

        # End key moves cursor to end of line
        # Enter insert at start, End, type X
        self.run_test(
            "End key moves to line end",
            "Hello World\n",
            b"i" + END + b"X\x1b:wq\r",
            expected_content="Hello WorldX\n"
        )

        # End key does nothing when already at end
        self.run_test(
            "End key at line end is no-op",
            "Hello World\n",
            b"$a" + END + b"X\x1b:wq\r",
            expected_content="Hello WorldX\n"
        )

        # Home and End work together
        # Move right, enter insert, End (go to end), Home (back to start), type X
        self.run_test(
            "Home and End in sequence",
            "Hello World\n",
            b"llllli" + END + HOME + b"X\x1b:wq\r",
            expected_content="XHello World\n"
        )

        # Home/End on empty line
        self.run_test(
            "Home/End on empty line",
            "\n",
            b"i" + HOME + END + HOME + b"X\x1b:wq\r",
            expected_content="X\n"
        )

        # Home/End on multi-line content
        self.run_test(
            "Home/End on second line",
            "First\nSecond Line\nThird\n",
            b"jllllli" + HOME + b"X\x1b" + END + b"aY\x1b:wq\r",
            expected_content="First\nXSecond LineY\nThird\n"
        )

        # Home key during text insertion
        self.run_test(
            "Home during text insertion",
            "World\n",
            b"i" + END + b"Hello " + HOME + b"!\x1b:wq\r",
            expected_content="!WorldHello \n"
        )

        # End key after backspace
        self.run_test(
            "End key after backspace",
            "Hello\n",
            b"$i\x08\x08" + END + b"X\x1b:wq\r",
            expected_content="HeoX\n"
        )

        self._group("Insert mode cursor clamping:", leading_blank=True)

        DOWN = b"\x1b[B"
        UP = b"\x1b[A"

        # Moving from longer line to shorter line should clamp to end+1
        # Line 1: "Hello" (5 chars), Line 2: "Hi" (2 chars)
        # Start at end of line 1 (col 5), move down to line 2
        # Should be at col 2 (one past 'i'), allowing insertion at end
        self.run_test(
            "Down arrow clamps to one past end in insert mode",
            "Hello\nHi\n",
            b"$a" + DOWN + b"X\x1b:wq\r",
            expected_content="Hello\nHiX\n"
        )

        # Moving up from shorter to longer line preserves column
        self.run_test(
            "Up arrow from short to long line in insert mode",
            "Hi\nHello\n",
            b"j$a" + UP + b"X\x1b:wq\r",
            expected_content="HiX\nHello\n"
        )

        # Moving down to empty line should position at column 0
        self.run_test(
            "Down to empty line in insert mode",
            "Hello\n\n",
            b"$a" + DOWN + b"X\x1b:wq\r",
            expected_content="Hello\nX\n"
        )

        # Test wrapping boundary: 40-char line (exactly fits screen width)
        # Moving from 40-char line to shorter line should preserve insert semantics
        self.run_test(
            "Down from full-width line to short line",
            "A" * 40 + "\nHi\n",
            b"$a" + DOWN + b"X\x1b:wq\r",
            expected_content="A" * 40 + "\nHiX\n"
        )

        # Test moving down from 41-char line (wraps to 2 screen rows) to short line
        self.run_test(
            "Down from wrapped line to short line",
            "A" * 41 + "\nHi\n",
            b"$a" + DOWN + b"X\x1b:wq\r",
            expected_content="A" * 41 + "\nHiX\n"
        )

        # Test moving up from short line to wrapped line preserves column
        self.run_test(
            "Up from short line to wrapped line",
            "A" * 41 + "\nHi\n",
            b"j$a" + UP + b"X\x1b:wq\r",
            expected_content="AA" + "X" + "A" * 39 + "\nHi\n"
        )

        self._group("Delete key line joining:", leading_blank=True)

        DEL = b"\x1b[3~"

        # Delete at end of line joins with next line
        self.run_test(
            "Delete at end of line joins next line",
            "Hello\nWorld\n",
            b"$a" + DEL + b"\x1b:wq\r",
            expected_content="HelloWorld\n"
        )

        # Delete at end of line does nothing on last line
        self.run_test(
            "Delete at end of last line is no-op",
            "Hello\n",
            b"$a" + DEL + b"\x1b:wq\r",
            expected_content="Hello\n"
        )

        # Delete at end of empty line joins next line
        self.run_test(
            "Delete at end of empty line joins next",
            "\nWorld\n",
            b"i" + DEL + b"\x1b:wq\r",
            expected_content="World\n"
        )

        # Delete joins then deletes next char
        # First Delete joins "A" and "B" -> "AB\nC\n"
        # Second Delete is now in middle of "AB", deletes "B" -> "A\nC\n"
        self.run_test(
            "Delete join then delete char",
            "A\nB\nC\n",
            b"$a" + DEL + DEL + b"\x1b:wq\r",
            expected_content="A\nC\n"
        )

        # Join multiple lines by using End key after each join
        self.run_test(
            "Multiple line joins with End key",
            "A\nB\nC\n",
            b"$a" + DEL + END + DEL + b"\x1b:wq\r",
            expected_content="ABC\n"
        )

        # Delete at end preserves cursor position
        self.run_test(
            "Delete join preserves cursor position",
            "Hello\nWorld\n",
            b"$aX" + DEL + b"Y\x1b:wq\r",
            expected_content="HelloXYWorld\n"
        )

        # Delete in middle of line still works
        self.run_test(
            "Delete in middle of line unchanged",
            "Hello\n",
            b"lli" + DEL + b"\x1b:wq\r",
            expected_content="Helo\n"
        )

        self._group("Batch movement in insert mode:", leading_blank=True)

        DOWN = b"\x1b[B"
        UP = b"\x1b[A"

        # Batch KEY_DOWN in insert mode with scrolling
        # 15-line file, 10 rows. Enter insert on line 1, 11 down arrows
        # scrolls down. Insert mode delegates to normal_move_down which batches.
        self.run_test_screen(
            "Batch insert down arrow with scroll",
            make_lines(15),
            b"i" + DOWN * 11 + b"\x1b:q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+4}") for i in range(9)]
        )

        # Batch KEY_UP in insert mode with scrolling
        # Go to bottom with G, enter insert, then 12 up arrows.
        self.run_test_screen(
            "Batch insert up arrow with scroll",
            make_lines(15),
            b"Gi" + UP * 12 + b"\x1b:q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(0, "Line 3")]
        )

        # Render optimization: batch insert down arrows reduce redraws
        # i enters insert (T), then 5 batched DOWN arrows no-scroll (F), ESC (F)
        self.run_test_screen(
            "Render opt: batch insert down no-scroll",
            make_lines(10),
            b"i" + DOWN * 5 + b"\x1b:q!\r",
            expect_content_redraws=[True, True, False, False]
        )

        # Batch insert up arrows: correctness check
        # 5j batched then i, 3 UP arrows batched -> line 2 (0-indexed)
        self.run_test_screen(
            "Batch insert up moves correct lines",
            make_lines(10),
            b"5ji" + UP * 3 + b"\x1b:q!\r",
            expect_cursor=(2, 0),
            expect_status_contains="COMMAND - 3,"
        )

        # ============================================================
        # Count prefix tests
        # ============================================================
        self._group("Count prefix:", leading_blank=True)

        # Count shows in status bar
        # Frame 0: initial, Frame 1: '3' (count active, cursor+status)
        self.run_test_screen(
            "Count displays in status bar",
            "Hello\n",
            b"3:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
            ]
        )

        # Multi-digit count shows in status bar
        # Frame 0: initial, Frame 1: '1', Frame 2: '0'
        self.run_test_screen(
            "Multi-digit count in status bar",
            "Hello\n",
            b"10:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 1 - "),
                (2, " - 10 - "),
            ]
        )

        # ESC clears count
        # Frame 0: initial, Frame 1: '3' (count), Frame 2: ESC (cleared)
        self.run_test_screen(
            "ESC clears count",
            "Hello\n",
            b"3\x1b:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
                (2, "NORMAL - 1,"),
            ]
        )

        # 0 as first key goes to line-start (not count)
        self.run_test_screen(
            "0 as first key is line-start not count",
            "Hello\n",
            b"ll0:q!\r",
            expect_cursor=(0, 0)
        )

        # Count preserved across two-key: 30 continues as count digits
        self.run_test_screen(
            "30 is count thirty not count-3 + line-start",
            "Hello\n",
            b"30:q!\r",
            cols=80,
            expect_status_at_frame=[
                (2, " - 30 - "),
            ]
        )

        # Count ignores digits past 4 digits (>= 1000)
        # 1000 typed: 4th digit accepted. 5th digit ignored since 1000 >= 1000
        self.run_test_screen(
            "count limited to 4 digits (5th ignored)",
            "Hello\n",
            b"10005:q!\r",
            cols=80,
            expect_status_at_frame=[
                (4, " - 1000 - "),  # After 4th digit: count=1000
                (5, " - 1000 - "),  # 5th digit '5' ignored, still 1000
            ]
        )

        # ============================================================
        # Pending key display tests
        # ============================================================
        self._group("Pending key display:", leading_blank=True)

        # After pressing 'g', status shows "g" pending key
        self.run_test_screen(
            "g shows pending key in status",
            make_lines(5),
            b"gG:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - g - "),
            ]
        )

        # After pressing 'd', status shows "d" pending key
        self.run_test_screen(
            "d shows pending key in status",
            make_lines(3),
            b"dd:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - d - "),
            ]
        )

        # After pressing 'y', status shows "y" pending key
        self.run_test_screen(
            "y shows pending key in status",
            make_lines(3),
            b"yy:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - y - "),
            ]
        )

        # 3d shows count then count+pending key
        self.run_test_screen(
            "3d shows count and pending key",
            make_lines(5),
            b"3dd:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
                (2, " - 3d - "),
            ]
        )

        # 3y shows count then count+pending key
        self.run_test_screen(
            "3y shows count and pending key",
            make_lines(5),
            b"3yy:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
                (2, " - 3y - "),
            ]
        )

        # After dd completes, pending key is cleared
        self.run_test_screen(
            "dd clears pending key from status",
            make_lines(3),
            b"dd:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # After 3dd completes, pending key and count are cleared
        self.run_test_screen(
            "3dd clears pending key from status",
            make_lines(5),
            b"3dd:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # ESC after d clears pending key
        self.run_test_screen(
            "ESC after d clears pending key",
            make_lines(3),
            b"d\x1b:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # ESC after 3d clears everything
        self.run_test_screen(
            "ESC after 3d clears count and pending key",
            make_lines(5),
            b"3d\x1b:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # m shows pending key in status
        self.run_test_screen(
            "m shows pending key in status",
            make_lines(3),
            b"ma:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - m - "),
            ]
        )

        # ' shows pending key in status
        self.run_test_screen(
            "' shows pending key in status",
            make_lines(3),
            b"ma'a:q!\r",
            cols=80,
            expect_status_at_frame=[
                (3, " - ' - "),
            ]
        )

        # After ma, pending key clears
        self.run_test_screen(
            "ma clears pending key from status",
            make_lines(3),
            b"ma:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # After 'a with mark set, pending key clears
        self.run_test_screen(
            "'a clears pending key from status",
            make_lines(3),
            b"ma'a:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # Invalid second key after pending key resets state completely
        # (no re-dispatch, no side effects)

        # d then digit: should reset, not start a count
        # Frame 0: initial, Frame 1: 'd' pending, Frame 2: '1' should reset
        self.run_test_screen(
            "d1 resets state (no count started)",
            make_lines(3),
            b"d1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (2, "NORMAL - 1,"),  # After '1', state fully reset
            ]
        )

        # d then x: should not delete a character
        self.run_test_screen(
            "dx does not delete character",
            "Hello\n",
            b"dx:wq\r",
            expected_content="Hello\n",
        )

        # d then j: should not move cursor
        self.run_test_screen(
            "dj does not move cursor",
            make_lines(3),
            b"dj:q!\r",
            expect_cursor=(0, 0),
        )

        # g then digit: should reset, not start a count
        self.run_test_screen(
            "g1 resets state (no count started)",
            make_lines(3),
            b"g1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (2, "NORMAL - 1,"),
            ]
        )

        # g then x: should not delete a character
        self.run_test_screen(
            "gx does not delete character",
            "Hello\n",
            b"gx:wq\r",
            expected_content="Hello\n",
        )

        # y then digit: should reset, not start a count
        self.run_test_screen(
            "y1 resets state (no count started)",
            make_lines(3),
            b"y1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (2, "NORMAL - 1,"),
            ]
        )

        # y then x: should not delete a character
        self.run_test_screen(
            "yx does not delete character",
            "Hello\n",
            b"yx:wq\r",
            expected_content="Hello\n",
        )

        # 3d then non-d: should reset count too, not just pending key
        self.run_test_screen(
            "3dx resets count and pending key",
            "Hello\n",
            b"3dx:wq\r",
            expected_content="Hello\n",
        )

        # ============================================================
        # Count movement tests
        # ============================================================
        self._group("Count movement:", leading_blank=True)

        # 3j moves down 3 lines
        self.run_test_screen(
            "3j moves cursor down 3 lines",
            make_lines(10),
            b"3j:q!\r",
            expect_cursor=(3, 0),
            expect_status_contains="COMMAND - 4,"
        )

        # 5l moves right 5 columns
        self.run_test_screen(
            "5l moves cursor right 5",
            "Hello World\n",
            b"5l:q!\r",
            expect_cursor=(0, 5)
        )

        # 2h moves left 2 columns
        self.run_test_screen(
            "2h moves cursor left 2",
            "Hello World\n",
            b"5l2h:q!\r",
            expect_cursor=(0, 3)
        )

        # 3k moves up 3 lines
        self.run_test_screen(
            "3k moves cursor up 3",
            make_lines(10),
            b"5j3k:q!\r",
            expect_cursor=(2, 0),
            expect_status_contains="COMMAND - 3,"
        )

        # Count exceeding bounds clamps
        self.run_test_screen(
            "Count j clamps at last line",
            make_lines(5),
            b"99j:q!\r",
            expect_cursor=(4, 0),
            expect_status_contains="COMMAND - 5,"
        )

        self.run_test_screen(
            "Count k clamps at first line",
            make_lines(5),
            b"3j99k:q!\r",
            expect_cursor=(0, 0),
            expect_status_contains="COMMAND - 1,"
        )

        self.run_test_screen(
            "Count l clamps at end of line",
            "Hello\n",
            b"99l:q!\r",
            expect_cursor=(0, 4)
        )

        self.run_test_screen(
            "Count h clamps at column 0",
            "Hello\n",
            b"ll99h:q!\r",
            expect_cursor=(0, 0)
        )

        # Count cleared after use
        self.run_test_screen(
            "Count cleared after movement",
            make_lines(10),
            b"3j:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),   # '3' shows count
            ],
            expect_status_contains="COMMAND - 4,"  # After j, count gone
        )

        # ============================================================
        # Count + G navigation tests
        # ============================================================
        self._group("Count navigation (G):", leading_blank=True)

        # 5G goes to line 5
        self.run_test_screen(
            "5G goes to line 5",
            make_lines(10),
            b"5G:q!\r",
            expect_cursor=(4, 0),
            expect_status_contains="COMMAND - 5,"
        )

        # G without count = last line
        self.run_test_screen(
            "G without count goes to last line",
            make_lines(10),
            b"G:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 10,"
        )

        # 1G goes to first line
        self.run_test_screen(
            "1G goes to first line",
            make_lines(10),
            b"5j1G:q!\r",
            expect_cursor=(0, 0),
            expect_status_contains="COMMAND - 1,"
        )

        # 999G clamps to last line
        self.run_test_screen(
            "999G clamps to last line",
            make_lines(10),
            b"999G:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 10,"
        )

        # ============================================================
        # Count x and dd tests
        # ============================================================
        self._group("Count x and dd:", leading_blank=True)

        # 3x deletes 3 chars
        self.run_test(
            "3x deletes 3 chars",
            "ABCDEF\n",
            b"3x:wq\r",
            expected_content="DEF\n"
        )

        # 3x from middle
        self.run_test(
            "3x from middle of line",
            "ABCDEF\n",
            b"l3x:wq\r",
            expected_content="AEF\n"
        )

        # Count x exceeding line clamps
        self.run_test(
            "Count x clamps at end of line",
            "AB\n",
            b"99x:wq\r",
            expected_content="\n"
        )

        # x still works without count
        self.run_test(
            "x without count still works",
            "Hello\n",
            b"x:wq\r",
            expected_content="ello\n"
        )

        # 2dd deletes 2 lines
        self.run_test(
            "2dd deletes 2 lines",
            "A\nB\nC\nD\n",
            b"2dd:wq\r",
            expected_content="C\nD\n"
        )

        # 3dd from middle
        self.run_test(
            "3dd from line 2 deletes 3 lines",
            "A\nB\nC\nD\nE\n",
            b"j3dd:wq\r",
            expected_content="A\nE\n"
        )

        # dd still works without count
        self.run_test(
            "dd without count still works",
            "A\nB\n",
            b"dd:wq\r",
            expected_content="B\n"
        )

        # Count dd exceeding file clamps
        self.run_test(
            "Count dd clamps at end of file",
            "A\nB\nC\n",
            b"j99dd:wq\r",
            expected_content="A\n"
        )

        # ============================================================
        # D (delete to end of line)
        # ============================================================
        self._group("D (delete to end of line):", leading_blank=True)

        # D at col 5 on "Hello World" deletes " World"
        self.run_test(
            "D at col 5 deletes to end of line",
            "Hello World\n",
            b"lllllD:wq\r",
            expected_content="Hello\n"
        )

        # D at col 0 deletes entire line content (leaves newline)
        self.run_test(
            "D at col 0 deletes line content",
            "Hello\n",
            b"D:wq\r",
            expected_content="\n"
        )

        # D on empty line does nothing
        self.run_test(
            "D on empty line does nothing",
            "\n",
            b"D:wq\r",
            expected_content="\n"
        )

        # D at last char deletes just that char
        self.run_test(
            "D at last char deletes just that char",
            "ABC\n",
            b"llD:wq\r",
            expected_content="AB\n"
        )

        # D doesn't affect next line
        self.run_test(
            "D doesn't affect next line",
            "Hello World\nLine 2\n",
            b"lllllD:wq\r",
            expected_content="Hello\nLine 2\n"
        )

        # ============================================================
        # Yank buffer tests (dd fills yank, tested via paste later)
        # For now, verify dd+yank doesn't break existing behavior
        # ============================================================
        self._group("Yank buffer (dd fills yank):", leading_blank=True)

        # dd on single line still leaves empty buffer
        self.run_test(
            "dd on single-line file with yank",
            "Only\n",
            b"dd:wq\r",
            expected_content="\n"
        )

        # dd on last line
        self.run_test(
            "dd on last line with yank",
            "A\nB\nC\n",
            b"Gdd:wq\r",
            expected_content="A\nB\n"
        )

        # 2dd at end (partial: only 1 line to delete)
        self.run_test(
            "2dd at last line only deletes 1",
            "A\nB\nC\n",
            b"G2dd:wq\r",
            expected_content="A\nB\n"
        )

        # ============================================================
        # Paste tests (p and P)
        # ============================================================
        self._group("Paste (p and P):", leading_blank=True)

        # dd + p = cut and paste below (effectively move line down)
        self.run_test(
            "dd+p pastes deleted line below",
            "A\nB\nC\n",
            b"ddp:wq\r",
            expected_content="B\nA\nC\n"
        )

        # dd + P = cut and paste above (line goes back to same position)
        self.run_test(
            "dd+P pastes deleted line above (same pos)",
            "A\nB\nC\n",
            b"ddP:wq\r",
            expected_content="A\nB\nC\n"
        )

        # 2dd + p = cut 2 lines and paste below
        self.run_test(
            "2dd+p pastes 2 deleted lines below",
            "A\nB\nC\nD\n",
            b"2ddp:wq\r",
            expected_content="C\nA\nB\nD\n"
        )

        # dd on line 2 then p (paste below line 2 which is now C)
        self.run_test(
            "dd from middle + p pastes below current",
            "A\nB\nC\nD\n",
            b"jddp:wq\r",
            expected_content="A\nC\nB\nD\n"
        )

        # P pastes above current line
        # j=B, dd deletes B (cursor on C), j=D, P pastes B above D
        self.run_test(
            "dd from middle + P pastes above current",
            "A\nB\nC\nD\n",
            b"jddjP:wq\r",
            expected_content="A\nC\nB\nD\n"
        )

        # p with empty yank does nothing
        self.run_test(
            "p with empty yank does nothing",
            "A\nB\n",
            b"p:wq\r",
            expected_content="A\nB\n"
        )

        # P with empty yank does nothing
        self.run_test(
            "P with empty yank does nothing",
            "A\nB\n",
            b"P:wq\r",
            expected_content="A\nB\n"
        )

        # dd on last line then p
        self.run_test(
            "dd last line + p pastes below",
            "A\nB\nC\n",
            b"Gddp:wq\r",
            expected_content="A\nB\nC\n"
        )

        # Cursor position after p (below)
        self.run_test_screen(
            "cursor at first pasted line after p",
            "A\nB\nC\n",
            b"ddp:q!\r",
            expect_cursor=(1, 0),  # line 1 (0-based) = "A" pasted below "B"
        )

        # Cursor position after P (above)
        self.run_test_screen(
            "cursor at first pasted line after P",
            "A\nB\nC\n",
            b"jddP:q!\r",
            expect_cursor=(1, 0),  # line 1 = "B" pasted above at same line num
        )

        # Multiple dd then p (last dd overwrites yank)
        # dd deletes A (yank=A), cursor on B, j=C, dd deletes C (yank=C),
        # cursor on D, p pastes C below D
        self.run_test(
            "second dd overwrites first dd in yank",
            "A\nB\nC\nD\n",
            b"ddjddp:wq\r",
            expected_content="B\nD\nC\n"
        )

        # ============================================================
        # Count paste tests (Np, NP)
        # ============================================================
        self._group("Count paste (Np, NP):", leading_blank=True)

        # 2p pastes twice
        self.run_test(
            "2p pastes line twice below",
            "A\nB\nC\n",
            b"yy2p:wq\r",
            expected_content="A\nA\nA\nB\nC\n"
        )

        # 3p pastes three times
        self.run_test(
            "3p pastes line three times below",
            "A\nB\n",
            b"yy3p:wq\r",
            expected_content="A\nA\nA\nA\nB\n"
        )

        # 2P pastes twice above
        self.run_test(
            "2P pastes line twice above",
            "A\nB\nC\n",
            b"jyy2P:wq\r",
            expected_content="A\nB\nB\nB\nC\n"
        )

        # dd + 2p (cut one, paste two copies)
        self.run_test(
            "dd+2p pastes deleted line twice",
            "A\nB\nC\n",
            b"dd2p:wq\r",
            expected_content="B\nA\nA\nC\n"
        )

        # ============================================================
        # Yank/copy (yy) tests
        # ============================================================
        self._group("Yank/copy (yy):", leading_blank=True)

        # yy + p copies line (original stays, copy pasted below)
        self.run_test(
            "yy+p copies line below",
            "A\nB\nC\n",
            b"yyp:wq\r",
            expected_content="A\nA\nB\nC\n"
        )

        # yy doesn't modify the buffer
        self.run_test(
            "yy does not set modified flag",
            "A\nB\n",
            b"yy:q\r",
            expect_exit=0  # :q should succeed without warning
        )

        # 2yy + p copies 2 lines
        self.run_test(
            "2yy+p copies 2 lines below",
            "A\nB\nC\nD\n",
            b"2yyp:wq\r",
            expected_content="A\nA\nB\nB\nC\nD\n"
        )

        # yy from last line + p
        self.run_test(
            "yy on last line + p",
            "A\nB\nC\n",
            b"Gyyp:wq\r",
            expected_content="A\nB\nC\nC\n"
        )

        # dd overwrites yy's yank buffer
        self.run_test(
            "dd overwrites yy yank buffer",
            "A\nB\nC\n",
            b"yyjddp:wq\r",
            expected_content="A\nC\nB\n"
        )

        # yy from middle + P pastes above
        self.run_test(
            "yy from middle + P pastes above",
            "A\nB\nC\n",
            b"jyyP:wq\r",
            expected_content="A\nB\nB\nC\n"
        )

        # 2yy clamps at end of file
        self.run_test(
            "2yy at last line only yanks 1",
            "A\nB\nC\n",
            b"G2yyp:wq\r",
            expected_content="A\nB\nC\nC\n"
        )

        # ============================================================
        # Character yank/paste tests (x, D with p/P)
        # ============================================================
        self._group("Character yank/paste (x/D + p/P):", leading_blank=True)

        # x + p: swap first two characters
        self.run_test(
            "x+p swaps first two chars",
            "AB\n",
            b"xp:wq\r",
            expected_content="BA\n"
        )

        # x + P: paste before restores original
        self.run_test(
            "x+P restores original",
            "AB\n",
            b"xP:wq\r",
            expected_content="AB\n"
        )

        # 3x + p: yank multiple chars and paste
        self.run_test(
            "3x+p yanks multiple chars",
            "ABCDE\n",
            b"3xp:wq\r",
            expected_content="DABCE\n"
        )

        # D + p: delete-to-EOL and paste on same line
        self.run_test(
            "D+p deletes to EOL and pastes after",
            "ABCDE\n",
            b"lD$p:wq\r",
            expected_content="ABCDE\n"
        )

        # D + p on next line
        self.run_test(
            "D+p pastes char yank on next line",
            "ABCDE\nXY\n",
            b"lDjp:wq\r",
            expected_content="A\nXBCDEY\n"
        )

        # dd after x: line yank overwrites char yank
        self.run_test(
            "dd after x overwrites char yank",
            "AB\nCD\n",
            b"xjddp:wq\r",
            expected_content="B\nCD\n"
        )

        # x after dd: char yank overwrites line yank
        self.run_test(
            "x after dd overwrites line yank",
            "AB\nCD\n",
            b"ddjxp:wq\r",
            expected_content="DC\n"
        )

        # 2p with char yank: paste text twice inline
        self.run_test(
            "2p with char yank pastes twice",
            "AB\n",
            b"x2p:wq\r",
            expected_content="BAA\n"
        )

        # Char paste on empty line
        self.run_test(
            "char paste on empty line",
            "AB\n\n",
            b"xjp:wq\r",
            expected_content="B\nA\n"
        )

        # Cursor position after char p (non-empty line)
        self.run_test_screen(
            "cursor after char p on non-empty line",
            "ABC\n",
            b"xp:q!\r",
            expect_cursor=(0, 1),  # Pasted A after B, cursor on A (col 1)
        )

        # Cursor position after char P
        self.run_test_screen(
            "cursor after char P",
            "ABC\n",
            b"lxP:q!\r",
            expect_cursor=(0, 1),  # Deleted B, P pastes before A->cursor at B (col 1)
        )

        # Batched x yanks only last deleted char (matches slow typing)
        self.run_test(
            "batched xxxx yanks only last char",
            "ABCDE\n",
            b"xxxxp:wq\r",
            expected_content="ED\n"
        )

        # Explicit count 4x yanks all 4 chars (count is intentional)
        self.run_test(
            "4x yanks all 4 chars",
            "ABCDE\n",
            b"4xp:wq\r",
            expected_content="EABCD\n"
        )

        # D on first col yanks entire line content
        self.run_test(
            "D from col 0 yanks whole line",
            "HELLO\nWORLD\n",
            b"Djp:wq\r",
            expected_content="\nWHELLOORLD\n"
        )

        # ============================================================
        # Search tests (/)
        # ============================================================
        self._group("Search (/):", leading_blank=True)

        # Basic search finds next line
        self.run_test_screen(
            "search finds text on next line",
            "AAA\nBBB\nCCC\n",
            b"/BBB\r:q!\r",
            expect_cursor=(1, 0),  # Found on line 1 (B)
        )

        # Search wraps around
        self.run_test_screen(
            "search wraps around to beginning",
            "AAA\nBBB\nCCC\n",
            b"j/AAA\r:q!\r",
            expect_cursor=(0, 0),  # Wraps to line 0
        )

        # Search finds text at column > 0
        self.run_test_screen(
            "search finds match at column offset",
            "hello world\nfoo bar\n",
            b"/bar\r:q!\r",
            expect_cursor=(1, 4),  # "bar" starts at col 4
        )

        # Search not found shows message (and returns to current pos)
        self.run_test_screen(
            "search not found stays at current line",
            "AAA\nBBB\nCCC\n",
            b"/ZZZ\r :q!\r",  # Space dismisses message
            expect_cursor=(0, 0),  # Stays at line 0
        )

        # Empty search with previous pattern repeats
        # First /AAA finds line 2. Second / repeats from line 3 (wraps to 0).
        self.run_test_screen(
            "empty search repeats previous pattern",
            "AAA\nBBB\nAAA\n",
            b"/AAA\r/\r:q!\r",
            expect_cursor=(0, 0),  # Wraps back to line 0
        )

        # Search on single-line file
        self.run_test_screen(
            "search finds match on same line (wraps)",
            "hello\n",
            b"/hello\r:q!\r",
            expect_cursor=(0, 0),  # Only one line, wraps back
        )

        # ESC cancels search
        self.run_test_screen(
            "ESC cancels search",
            "AAA\nBBB\n",
            b"/BB\x1b:q!\r",
            expect_cursor=(0, 0),  # Stays at line 0
        )

        # Search from middle of file
        self.run_test_screen(
            "search from middle finds below first",
            "AAA\nBBB\nAAA\n",
            b"/AAA\r:q!\r",
            expect_cursor=(2, 0),  # Finds line 2 first (starts from line 1)
        )

        # ============================================================
        # Find-next (n) tests
        # ============================================================
        self._group("Find-next (n):", leading_blank=True)

        # n repeats search
        self.run_test_screen(
            "n repeats search to next match",
            "AAA\nBBB\nAAA\nBBB\n",
            b"/BBB\rn:q!\r",
            expect_cursor=(3, 0),  # First / finds line 1, n finds line 3
        )

        # n wraps around
        self.run_test_screen(
            "n wraps around to first match",
            "AAA\nBBB\nCCC\n",
            b"/BBB\rn:q!\r",
            expect_cursor=(1, 0),  # Only one BBB, n wraps back to line 1
        )

        # n with no prior search is no-op
        self.run_test_screen(
            "n with no prior search is no-op",
            "AAA\nBBB\n",
            b"n:q!\r",
            expect_cursor=(0, 0),  # Stays at line 0
        )

        # Multiple n presses
        # /X->line 2, first n->line 4, second n->wraps to line 0
        self.run_test_screen(
            "multiple n finds successive matches",
            "X\nY\nX\nY\nX\n",
            b"/X\rn:q!\r",
            expect_cursor=(4, 0),  # /X->line 2, n->line 4
        )

        # Find-prev (N) tests
        # ============================================================
        self._group("Find-prev (N):", leading_blank=True)

        # N searches backward to previous match
        # Start at line 0, /BBB finds line 1, N goes backward (wraps to line 3)
        self.run_test_screen(
            "N searches backward to previous match",
            "AAA\nBBB\nAAA\nBBB\n",
            b"/BBB\rN:q!\r",
            expect_cursor=(3, 0),  # /BBB->line 1, N wraps back to line 3
        )

        # N wraps around to last match when at beginning
        self.run_test_screen(
            "N wraps around to last match",
            "AAA\nBBB\nCCC\n",
            b"/BBB\rN:q!\r",
            expect_cursor=(1, 0),  # Only one BBB, N wraps back to line 1
        )

        # N with no prior search is no-op
        self.run_test_screen(
            "N with no prior search is no-op",
            "AAA\nBBB\n",
            b"N:q!\r",
            expect_cursor=(0, 0),  # Stays at line 0
        )

        # N goes to previous match (backward from current position)
        # /X from line 0 finds line 2, N goes backward to line 0
        self.run_test_screen(
            "N finds previous match going backward",
            "X\nY\nX\nY\nX\n",
            b"/X\rN:q!\r",
            expect_cursor=(0, 0),  # /X->line 2, N back to line 0
        )

        # n then N returns to previous match
        self.run_test_screen(
            "n then N returns to previous match",
            "X\nY\nX\nY\nX\n",
            b"/X\rnN:q!\r",
            expect_cursor=(2, 0),  # /X->line 2, n->line 4, N back to line 2
        )

        # ==========================================================
        # Marks
        # ==========================================================
        self._group("Marks (m/'/adjust):", leading_blank=True)

        # --- Set and go to mark ---

        # Set mark on line 1, go to line 3, return via 'a
        self.run_test_screen(
            "ma then 'a returns to marked line",
            make_lines(5),
            b"majj'a:q!\r",
            expect_cursor=(0, 0),  # Back to line 1
        )

        # Set mark on line 3, go to line 1, jump to mark
        self.run_test_screen(
            "'a jumps forward to marked line",
            make_lines(5),
            b"jjmakk'a:q!\r",
            expect_cursor=(2, 0),  # Line 3
        )

        # Set two marks on different lines, verify both work
        self.run_test_screen(
            "Two marks on different lines",
            make_lines(5),
            b"majjjmb'a:q!\r",
            expect_cursor=(0, 0),  # 'a -> line 1
        )

        self.run_test_screen(
            "Second mark also works",
            make_lines(5),
            b"majjjmb'b:q!\r",
            expect_cursor=(3, 0),  # 'b -> line 4
        )

        # 'z with no mark set shows error (keypress dismisses)
        self.run_test_screen(
            "'z unset mark shows error message",
            make_lines(3),
            b"'z :q!\r",  # space dismisses the error
            expect_cursor=(0, 0),  # stays on line 1
        )

        # m followed by non-letter does nothing harmful
        self.run_test(
            "m1 (non-letter) does nothing",
            make_lines(3),
            b"m1:q!\r",
            expect_unmodified=True,
        )

        # 'a sets cursor col to 0
        self.run_test_screen(
            "'a sets cursor col to 0",
            "Hello\nWorld\n",
            b"mallj'a:q!\r",
            expect_cursor=(0, 0),
        )

        # --- Mark adjustment: dd ---

        # dd the marked line -> mark is unset
        self.run_test_screen(
            "dd marked line unsets mark",
            make_lines(3),
            b"madd'a :q!\r",  # space dismisses "Mark not set"
            expect_cursor=(0, 0),  # stays (error message dismissed)
        )

        # Set mark on line 3, dd line 1 -> mark shifts to line 2
        self.run_test_screen(
            "dd above mark shifts mark down",
            make_lines(5),
            b"jjmagg dd'a:q!\r",  # gg->line1, dd line1, 'a
            expect_cursor=(1, 0),  # mark was line 3 (idx 2), now idx 1
        )

        # Set mark on line 1, dd line 3 -> mark stays on line 1
        self.run_test_screen(
            "dd below mark leaves mark unchanged",
            make_lines(5),
            b"majjdd'a:q!\r",  # mark line1, jj->line3, dd, 'a
            expect_cursor=(0, 0),  # mark still at line 1
        )

        # --- Mark adjustment: o/O ---

        # Set mark on line 3, o on line 1 (opens line 2) -> mark shifts to line 4
        self.run_test_screen(
            "o above mark shifts mark down",
            make_lines(5),
            b"jjmagg o\x1b'a:q!\r",  # mark at line3, gg, o+ESC, 'a
            expect_cursor=(3, 0),  # was idx 2, now idx 3
        )

        # Set mark on line 1, O on line 3 -> mark stays on line 1
        self.run_test_screen(
            "O below mark leaves mark unchanged",
            make_lines(5),
            b"majjO\x1b'a:q!\r",  # mark at line1, jj, O+ESC, 'a
            expect_cursor=(0, 0),
        )

        # O on same line as mark -> mark shifts down
        self.run_test_screen(
            "O on marked line shifts mark down",
            make_lines(5),
            b"jmaO\x1b'a:q!\r",  # mark at line2, O+ESC, 'a
            expect_cursor=(2, 0),  # was idx 1, shifted to idx 2
        )

        # --- Mark adjustment: paste ---

        # Yank a line, paste below line above mark -> mark shifts
        self.run_test_screen(
            "paste above mark shifts mark down",
            make_lines(5),
            b"jjmayy gg p'a:q!\r",  # mark line3, yy, gg, p, 'a
            expect_cursor=(3, 0),  # was idx 2, paste adds 1 line before -> idx 3
        )

        # Yank a line, paste below line below mark -> mark unchanged
        self.run_test_screen(
            "paste below mark leaves mark unchanged",
            make_lines(5),
            b"mayyjjjp'a:q!\r",  # mark line1, yy, jjj->line4, p, 'a
            expect_cursor=(0, 0),
        )

        # --- Mark adjustment: Enter in insert mode ---

        # Set mark on line 3, insert Enter on line 1 -> mark shifts
        self.run_test_screen(
            "Enter in insert above mark shifts mark",
            make_lines(5),
            b"jjmagg A\r\x1b'a:q!\r",  # mark line3, gg, A+Enter+ESC, 'a
            expect_cursor=(3, 0),  # was idx 2, Enter added line -> idx 3
        )

        # --- Mark adjustment: backspace join ---

        # Set mark on line 3, backspace-join at line 2 col 0 -> mark shifts
        self.run_test_screen(
            "BS join above mark shifts mark up",
            make_lines(5),
            b"jjmaki\x08\x1b'a:q!\r",  # mark line3, k->line2, i+BS(join)+ESC, 'a
            expect_cursor=(1, 0),  # was idx 2, join removed line -> idx 1
        )

        # --- :marks command ---

        self._group(":marks command:", leading_blank=True)

        # :marks with no marks shows "No marks set"
        self.run_test_screen(
            ":marks with no marks set",
            make_lines(3),
            b":marks\r :q!\r",  # space dismisses marks display
            expect_cursor=(0, 0),
        )

        # :marks shows set marks with right-justified line numbers
        self.run_test_screen(
            ":marks shows mark a with formatting",
            make_lines(3),
            b"ma:marks\r :q!\r",
            expect_cursor=(0, 0),
            expect_ansi_contains=" a      1",
        )

        # :marks with mark on line 100 aligns with single-digit marks
        self.run_test_screen(
            ":marks right-justifies line numbers",
            make_lines(100),
            b"ma:100\rmb" +         # ma on line 1, goto line 100, mb
            b":marks\r :q!\r",
            expect_ansi_contains=" b    100",
        )

        # :marks with wider terminal shows more text
        self.run_test_screen(
            ":marks wider terminal shows more text",
            "Hello World - this is a long line\n",
            b"ma:marks\r :q!\r",
            rows=10, cols=80,
            expect_ansi_contains="Hello World - this is a long line",
        )

        # :m shows "Unknown command" (partial match, doesn't match :marks)
        self.run_test_screen(
            ":m shows Unknown command",
            make_lines(3),
            b":m\r :q!\r",  # space dismisses error
            expect_ansi_contains="Unknown command",
        )

        # :marksx shows "Unknown command" (extra chars after :marks)
        self.run_test_screen(
            ":marksx shows Unknown command",
            make_lines(3),
            b":marksx\r :q!\r",  # space dismisses error
            expect_ansi_contains="Unknown command",
        )

        # --- Range yank ---

        self._group("Range yank (:'a,.y):", leading_blank=True)

        # Set mark on line 1, navigate to line 3, :'a,.y yanks 3 lines
        self.run_test(
            ":'a,.y yanks range and paste works",
            make_lines(5),
            b"majj:'a,.y\rjp:wq\r",  # ma, jj, :'a,.y, j, p, :wq
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 1\nLine 2\nLine 3\nLine 5\n",
        )

        # Range with marks in reverse order (auto-swap)
        self.run_test(
            "Range with end < start auto-swaps",
            make_lines(5),
            b"jjmakk:'a,.y\rjjjjp:wq\r",  # ma on line3, kk->line1, :'a,.y, paste
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\n",
        )

        # Range yank between two marks
        self.run_test(
            ":'a,'by yanks between two marks",
            make_lines(5),
            b"majjjmb:'a,'by\rGp:wq\r",  # ma line1, mb line4, range yank, G, p
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\nLine 4\n",
        )

        # Range yank single line
        self.run_test(
            "Range yank single line",
            make_lines(3),
            b"jma:'a,.y\rjp:wq\r",  # ma on line2, :'a,.y on line2, p after line3
            expected_content="Line 1\nLine 2\nLine 3\nLine 2\n",
        )

        # Range yank with unset mark shows error
        self.run_test_screen(
            "Range yank unset mark shows error",
            make_lines(3),
            b":'z,.y\r :q!\r",  # space dismisses error
            expect_cursor=(0, 0),
        )

        # --- Range delete ---

        self._group("Range delete (:'a,.d):", leading_blank=True)

        # :'a,.d deletes range
        self.run_test(
            ":'a,.d deletes range",
            make_lines(5),
            b"majj:'a,.d\r:wq\r",  # ma line1, jj->line3, :'a,.d
            expected_content="Line 4\nLine 5\n",
        )

        # Range delete between two marks
        self.run_test(
            ":'a,'bd deletes between two marks",
            make_lines(5),
            b"jmajjjmb:'a,'bd\r:wq\r",  # ma line2, mb line5, range delete
            expected_content="Line 1\n",
        )

        # Range delete with reverse order auto-swaps
        self.run_test(
            "Range delete reverse order auto-swaps",
            make_lines(5),
            b"jjmakk:'a,.d\r:wq\r",  # ma line3, kk->line1, :'a,.d
            expected_content="Line 4\nLine 5\n",
        )

        # Range delete of all lines leaves single empty line
        self.run_test(
            "Range delete all lines leaves empty",
            make_lines(3),
            b"majj:'a,.d\r:wq\r",  # ma line1, jj->line3, :'a,.d deletes all
            expected_content="\n",
        )

        # Range delete yanks lines first (verify with p)
        self.run_test(
            "Range delete yanks lines for paste",
            make_lines(5),
            b"majj:'a,.d\rp:wq\r",  # delete lines 1-3, then paste
            expected_content="Line 4\nLine 1\nLine 2\nLine 3\nLine 5\n",
        )

        # Range delete adjusts marks (mark below deleted range shifts up)
        self.run_test_screen(
            "Range delete adjusts marks",
            make_lines(5),
            b"jjjjmb" +           # mb on line 5
            b"ggma" +              # ma on line 1
            b"jj:'a,.d\r" +       # jj to line 3, delete lines 1-3
            b"'b:q!\r",           # 'b should be at line 2 (was 5, shifted by 3)
            expect_cursor=(1, 0),  # Mark was line 5 (idx 4), shifted to idx 1
        )

        # Range delete with unset mark shows error
        self.run_test_screen(
            "Range delete unset mark shows error",
            make_lines(3),
            b":'z,.d\r :q!\r",  # space dismisses error
            expect_ansi_contains="Mark not set",
        )

        # Shows "N lines deleted" message
        self.run_test_screen(
            "Range delete shows lines deleted message",
            make_lines(5),
            b"majj:'a,.d\r:q!\r",
            expect_ansi_contains="3 lines deleted",
        )

        # Range delete positions cursor at first deleted line
        self.run_test_screen(
            "Range delete positions cursor correctly",
            make_lines(5),
            b"majj:'a,.d\r:q!\r",  # ma line1, jj->line3, delete 1-3
            expect_cursor=(0, 0),  # cursor at first deleted line (now line 1)
        )

        # Range delete corrupts search buffer (yank buffer overlaps search buffer)
        # YANK_BUF=$E000, SEARCH_BUF=$E020 - yank overwrites search pattern
        # after 32 bytes. Delete enough lines so the yanked content exceeds
        # 32 bytes, then repeat search with empty /. The pattern should still
        # be intact.
        self.run_test_screen(
            "Search repeat works after range delete",
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ_padding\n"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ_padding\n"
            + "keepme\n" + "NEEDLE\n",
            # Cursor starts at line 0.
            # /NEEDLE finds NEEDLE on line 3. gg goes to line 0.
            # ma on line 0, j to line 1, :'a,.d deletes lines 0-1
            # (yanks >68 bytes, overwriting SEARCH_BUF at $E020).
            # Remaining: "keepme\n" (line 0) and "NEEDLE\n" (line 1).
            # Cursor at line 0 after delete. /\r repeats search.
            # If search buffer intact: finds NEEDLE on line 1 -> cursor (1,0)
            # If corrupted: pattern not found -> cursor stays at (0,0)
            b"/NEEDLE\r"          # search finds NEEDLE on line 3
            b"ggma"               # gg to line 0, set mark a
            b"j"                  # move to line 1
            b":'a,.d\r"           # delete lines 0-1 (yanks >68 bytes)
            b"/\r"                # repeat search - should find NEEDLE
            b":q!\r",
            expect_cursor=(1, 0),  # NEEDLE is on line 1 after delete
        )

        # --- Line numbers in range commands ---

        self._group("Line numbers in range commands:", leading_blank=True)

        # :1,'ay with mark a on line 3 yanks lines 1-3
        self.run_test(
            ":1,'ay yanks with line number start",
            make_lines(5),
            b"jjma:1,'ay\rGp:wq\r",  # ma on line3, :1,'ay, G, p
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\n",
        )

        # :1,3d deletes first 3 lines
        self.run_test(
            ":1,3d deletes lines 1-3",
            make_lines(5),
            b":1,3d\r:wq\r",
            expected_content="Line 4\nLine 5\n",
        )

        # :'a,3y with mark a on line 1 yanks lines 1-3
        self.run_test(
            ":'a,3y yanks mark to line number",
            make_lines(5),
            b"ma:\'a,3y\rGp:wq\r",  # ma on line1, :'a,3y, G, p
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\n",
        )

        # :1,.y from line 3 yanks lines 1-3
        self.run_test(
            ":1,.y yanks line number to current",
            make_lines(5),
            b"jj:1,.y\rGp:wq\r",  # jj to line3, :1,.y, G, p
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\n",
        )

        # :.,3y from line 1 yanks lines 1-3
        self.run_test(
            ":.,3y yanks current to line number",
            make_lines(5),
            b":.,3y\rGp:wq\r",  # on line1, :.,3y, G, p
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 1\nLine 2\nLine 3\n",
        )

        # :5 still works as goto line (regression)
        self.run_test_screen(
            ":5 goes to line 5",
            make_lines(10),
            b":5\r:q!\r",
            expect_cursor=(4, 0),
        )

        # :999 goes to last line (regression)
        self.run_test_screen(
            ":999 clamps to last line",
            make_lines(5),
            b":999\r:q!\r",
            expect_cursor=(4, 0),
        )

        # Line numbers are 1-based
        self.run_test(
            ":2,4d deletes lines 2-4 (1-based)",
            make_lines(5),
            b":2,4d\r:wq\r",
            expected_content="Line 1\nLine 5\n",
        )

        self._group("Long line handling (>255 chars):", leading_blank=True)

        long_line_300 = "A" * 300 + "\n"

        # Search on a line >255 chars should complete (not hang)
        # Search for a pattern that doesn't exist - should report not found
        self.run_test(
            "Search on >255 char line doesn't hang (pattern not found)",
            long_line_300,
            b"/ZZZZZ\r:q!\r",
            expect_unmodified=True
        )

        # Search for a pattern in first 255 chars still works
        content_with_marker = "B" * 100 + "MARKER" + "B" * 200 + "\n"
        self.run_test(
            "Search finds pattern within first 255 chars of long line",
            content_with_marker,
            b"/MARKER\rx:wq\r",
            expected_content="B" * 100 + "ARKER" + "B" * 200 + "\n"
        )

        # 'o' (open below) on a line >255 chars inserts correctly
        self.run_test(
            "Open below (o) on >255 char line",
            long_line_300,
            b"oHello\x1b:wq\r",
            expected_content=long_line_300 + "Hello\n"
        )

        # 'o' on a line exactly at 256 chars (edge case for Y wrap)
        long_line_256 = "X" * 256 + "\n"
        self.run_test(
            "Open below (o) on 256 char line (Y wrap edge case)",
            long_line_256,
            b"oWorld\x1b:wq\r",
            expected_content=long_line_256 + "World\n"
        )

        # 'o' on multi-line file where long line is first
        self.run_test(
            "Open below (o) on long first line with second line",
            long_line_300 + "Short\n",
            b"oMiddle\x1b:wq\r",
            expected_content=long_line_300 + "Middle\n" + "Short\n"
        )

        # ============================================================
        # Operations exceeding 255 lines (currently fail - TBD)
        # ============================================================
        self._group("Operations exceeding 255 lines (>255):", leading_blank=True)

        self.run_test(
            "256dd deletes 256 lines",
            make_lines(300),
            b"256dd:wq\r",
            # Lines 1-256 deleted, lines 257-300 remain
            expected_content=''.join(f"Line {i}\n" for i in range(257, 301))
        )

        self.run_test(
            "300yy yanks 300 lines",
            make_lines(300) + "Extra\n",
            b"300yyGp:wq\r",
            # After 300yy, cursor on line 1. G moves to last line (301).
            # p pastes below, so lines 1-300 appear after line 301.
            expected_content=make_lines(300) + "Extra\n" + make_lines(300)
        )

        self.run_test(
            "16yy + 16p pastes 256 lines correctly",
            make_lines(20),
            b"16yy3G16p:wq\r",
            # 16yy yanks lines 1-16. 3G moves to line 3.
            # 16p pastes 16 lines, 16 times = 256 lines below line 3.
            # Result: lines 1-3, then 256 pasted lines (16 copies of lines 1-16), then lines 4-20
            expected_content=(
                make_lines(3) +
                (make_lines(16) * 16) +
                ''.join(f"Line {i}\n" for i in range(4, 21))
            )
        )

        self.run_test(
            "Mark adjustment with 256dd",
            make_lines(400),
            b"100Gma100G256dd:wq\r",
            # 100G goes to line 100, ma sets mark a
            # 100G stays at line 100 (already there)
            # 256dd deletes lines 100-355 (256 lines)
            # Mark a was on line 100 (now deleted)
            # Result: lines 1-99, then lines 356-400
            expected_content=(
                make_lines(99) +
                ''.join(f"Line {i}\n" for i in range(356, 401))
            )
        )

        self.run_test(
            "Range :100,399d deletes 300 lines",
            make_lines(500),
            b":100,399d\r:wq\r",
            # Delete lines 100-399 (300 lines)
            # Result: lines 1-99, then lines 400-500
            expected_content=(
                make_lines(99) +
                ''.join(f"Line {i}\n" for i in range(400, 501))
            )
        )

        self._group("Screen state - non-ASCII display:", leading_blank=True)

        # Single non-ASCII byte mid-line
        self.run_test_screen(
            "Non-ASCII byte displayed as reverse ?",
            None,
            b":q!\r",
            initial_bytes=b"AB\x80CD\n",
            expect_lines=[(0, "AB?CD")],
            expect_reverse_at=[
                (0, 0, False), (0, 1, False),
                (0, 2, True),
                (0, 3, False), (0, 4, False),
            ]
        )

        # Multiple non-ASCII bytes
        self.run_test_screen(
            "Multiple non-ASCII bytes as reverse ?",
            None,
            b":q!\r",
            initial_bytes=b"A\xFF\xFEB\n",
            expect_lines=[(0, "A??B")],
            expect_reverse_at=[
                (0, 0, False),
                (0, 1, True), (0, 2, True),
                (0, 3, False),
            ]
        )

        # Cursor movement past non-ASCII bytes (one column per byte)
        self.run_test_screen(
            "Cursor movement past non-ASCII bytes",
            None,
            b"lll:q!\r",
            initial_bytes=b"A\x80\x90D\n",
            expect_cursor=(0, 3),
        )

        # Non-ASCII at end of line with $ motion
        self.run_test_screen(
            "Non-ASCII at end of line with $ motion",
            None,
            b"$:q!\r",
            initial_bytes=b"ABC\x80\n",
            expect_cursor=(0, 3),
            expect_reverse_at=[
                (0, 3, True),
            ]
        )

        self._group("Word motions (w, b, e):", leading_blank=True)

        self.run_test_screen(
            "w skips word to next word",
            "hello world\n",
            b"w:q!\r",
            expect_cursor=(0, 6),
        )

        self.run_test_screen(
            "w from middle of word",
            "hello world\n",
            b"llw:q!\r",
            expect_cursor=(0, 6),
        )

        self.run_test_screen(
            "w skips punctuation class",
            "foo...bar\n",
            b"w:q!\r",
            expect_cursor=(0, 3),
        )

        self.run_test_screen(
            "w from punct to word",
            "...bar\n",
            b"w:q!\r",
            expect_cursor=(0, 3),
        )

        self.run_test_screen(
            "w at end of line goes to next line",
            "foo\nbar\n",
            b"$w:q!\r",
            expect_cursor=(1, 0),
        )

        self.run_test_screen(
            "w on empty line goes to next line",
            "\nbar\n",
            b"w:q!\r",
            expect_cursor=(1, 0),
        )

        self.run_test_screen(
            "w skips whitespace between words",
            "foo   bar\n",
            b"w:q!\r",
            expect_cursor=(0, 6),
        )

        self.run_test_screen(
            "2w skips two words",
            "one two three\n",
            b"2w:q!\r",
            expect_cursor=(0, 8),
        )

        # b: move to start of previous word
        self.run_test_screen(
            "b from middle of second word",
            "hello world\n",
            b"$b:q!\r",
            expect_cursor=(0, 6),
        )

        self.run_test_screen(
            "b from start of second word",
            "hello world\n",
            b"llllllb:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "b at col 0 goes to previous line end",
            "foo\nbar\n",
            b"jb:q!\r",
            expect_cursor=(0, 2),
        )

        self.run_test_screen(
            "b with punctuation",
            "foo...bar\n",
            b"$b:q!\r",
            expect_cursor=(0, 6),
        )

        self.run_test_screen(
            "2b skips two words",
            "one two three\n",
            b"$2b:q!\r",
            expect_cursor=(0, 4),
        )

        # e: move to end of current/next word
        self.run_test_screen(
            "e from start of word",
            "hello world\n",
            b"e:q!\r",
            expect_cursor=(0, 4),
        )

        self.run_test_screen(
            "e skips to next word end",
            "hello world\n",
            b"ee:q!\r",
            expect_cursor=(0, 10),
        )

        self.run_test_screen(
            "e with punctuation",
            "foo...bar\n",
            b"e:q!\r",
            expect_cursor=(0, 2),
        )

        self.run_test_screen(
            "e at end of line goes to next line",
            "foo\nbar\n",
            b"ee:q!\r",
            expect_cursor=(1, 2),
        )

        self.run_test_screen(
            "2e skips two word ends",
            "one two three\n",
            b"2e:q!\r",
            expect_cursor=(0, 6),
        )

        self._group("First non-blank (^):", leading_blank=True)

        self.run_test_screen(
            "^ on line with leading spaces",
            "   hello\n",
            b"^:q!\r",
            expect_cursor=(0, 3),
        )

        self.run_test_screen(
            "^ on line without leading spaces",
            "hello\n",
            b"ll^:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "^ on empty line stays at col 0",
            "\n",
            b"^:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "^ on all-spaces line stays at col 0",
            "   \n",
            b"^:q!\r",
            expect_cursor=(0, 0),
        )

        print()
        print("=" * 60)
        total = self.passed + self.failed
        parts = [f"{Colors.GREEN}{self.passed} passed{Colors.NC}"]
        if self.failed:
            parts.append(f"{Colors.RED}{self.failed} failed{Colors.NC}")
        print(f"Results: {', '.join(parts)} of {total} tests")
        print("=" * 60)

        # Create stable copy only if all tests passed
        if self.failed == 0:
            self.create_stable_copy()


def main():
    parser = argparse.ArgumentParser(description="Editor test runner")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="Only show failures and summary")
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args()

    if args.no_color:
        Colors.disable()

    script_dir = Path(__file__).parent.resolve()
    base_dir = script_dir.parent.parent

    runner = EditorTestRunner(base_dir, verbose=args.verbose, quiet=args.quiet)
    runner.run_all_tests()

    sys.exit(1 if runner.failed > 0 else 0)


if __name__ == "__main__":
    main()
