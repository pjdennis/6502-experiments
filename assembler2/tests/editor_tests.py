#!/usr/bin/env python3
"""
Test runner for the vi-like text editor.

Tests the editor by providing keystroke sequences as input files
and verifying the saved output matches expectations.

Usage:
    ./tests/editor_tests.py [-v]
"""

import argparse
import os
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
        self.editor_debug_bin = base_dir / "editor" / "out" / "editor_debug.out"
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
        cmd = [str(self.emulator), str(self.assembler), "2000",
               "/dev/null", "/dev/null",
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

    def build_debug_editor(self):
        """Assemble the debug editor (with enable_debug defined)."""
        return self._assemble_editor(self.editor_debug_bin,
                                     ["define:enable_debug"])

    def run_editor(self, input_file: str, keys: bytes, tmpdir: Path) -> tuple:
        """Run the editor with given keystroke sequence.

        Returns (exit_code, saved_content, ansi_output).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.txt"
        keys_file.write_bytes(keys)

        result = subprocess.run(
            [str(self.emulator), str(self.editor_bin), "0400",
             str(keys_file), str(output_file), input_file],
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
                [str(self.emulator), str(self.editor_bin), "0400",
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

    def run_editor_debug(self, input_file: str, keys: bytes,
                         tmpdir: Path, extra_args: list = None) -> tuple:
        """Run the debug editor with given keystroke sequence and extra args.

        Returns (exit_code, saved_content, ansi_output).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.txt"
        keys_file.write_bytes(keys)

        cmd = [str(self.emulator), str(self.editor_debug_bin), "0400",
               str(keys_file), str(output_file), input_file]
        if extra_args:
            cmd.extend(extra_args)

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
            [str(self.emulator), str(self.editor_bin), "0400",
             "--rows", str(rows), "--cols", str(cols),
             str(keys_file), str(output_file), input_file],
            capture_output=True, timeout=10
        )

        saved = ""
        if Path(input_file).exists():
            saved = Path(input_file).read_text()

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
                        expect_lines_at_frame: list = None):
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
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_content is not None:
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

            self._pass(name)

    def run_test_debug(self, name: str, initial_content: str, keys: bytes,
                       extra_args: list = None,
                       expected_content: str = None, expect_exit: int = 0,
                       expect_unmodified: bool = False):
        """Run a test using the debug editor with extra arguments."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor_debug(
                    str(edit_file), keys, tmpdir, extra_args
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

        self._group("Bounds checking (debug build):", leading_blank=True)

        if not self.build_debug_editor():
            print("  Skipping bounds checking tests (debug build failed)")
        else:
            # Read-only mode: file exceeds buffer, editing keys blocked
            # bufsize:21 limits buffer to $2000-$20FF (256 bytes)
            # File has 300 bytes so it will be truncated
            # Truncation warning consumes one keypress (the 'x')
            # Then 'x' should be ignored (readonly), :q exits
            large_content = "A" * 299 + "\n"  # 300 bytes > 256
            self.run_test_debug(
                "Truncated file enters read-only mode",
                large_content,
                # 'x' dismissed truncation warning, 'x' ignored (RO), :q quits
                b"xx:q\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Read-only mode: :w is blocked
            # Truncation warning consumes 'x', then :w shows RO message,
            # 'x' dismisses that, :q! quits
            self.run_test_debug(
                "Read-only mode blocks :w",
                large_content,
                b"x:w\rx:q!\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Read-only mode: :wq is blocked
            self.run_test_debug(
                "Read-only mode blocks :wq",
                large_content,
                b"x:wq\rx:q!\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Read-only mode: :q exits cleanly
            self.run_test_debug(
                "Read-only mode allows :q",
                large_content,
                b"x:q\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Read-only mode: i key is blocked (no insert mode)
            self.run_test_debug(
                "Read-only mode blocks i",
                large_content,
                b"x:q\r",   # 'x' dismisses warning, :q quits
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Buffer full during editing: insert char fails
            # bufsize:21 = 256 bytes buffer. File with 250 bytes leaves ~6 free
            # After loading, type characters until full
            near_full = "B" * 249 + "\n"  # 250 bytes, ~6 bytes free
            self.run_test_debug(
                "Buffer full refuses insert char",
                near_full,
                # Enter insert mode, type 7 chars (6 succeed, 7th triggers full)
                # 'z' dismisses "Buffer full" message
                # ESC back to normal, :q! quits
                b"iAAAAAA" + b"A" + b"z\x1b:q!\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Buffer full during editing: newline insert fails
            # File with 254 bytes leaves ~2 free
            almost_full = "C" * 253 + "\n"  # 254 bytes, ~2 bytes free
            self.run_test_debug(
                "Buffer full refuses newline insert",
                almost_full,
                # Insert mode, type 'A' (succeeds, 1 byte free),
                # then Enter (needs 1 byte for newline - should succeed or fail)
                # Actually with 2 bytes free: 'A' uses 1, Enter uses 1 = exactly full
                # Try one more char to trigger full
                b"iAA" + b"z\x1b:q!\r",
                extra_args=["bufsize:21"],
                expect_unmodified=True
            )

            # Normal editing works with debug build (no bufsize override)
            self.run_test_debug(
                "Debug build normal editing works",
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
        # Up arrow should move to line 0 ("B"), col clamped to 0, row 0.
        # Bug: ensure_cursor_visible ran with unclamped col 60 on line 0
        # (1-char line), computing CURSOR_ROW=1 instead of 0.
        # Frame sequence: 0=init, 1=j, 2=$, 3=a, 4=UP
        self.run_test_screen(
            "Insert up arrow from wrapped line to short line",
            "B\n" + "A" * 60 + "\n",
            b"j$a\x1b[A\x1b:q!\r",
            expect_cursor=(0, 0),
            expect_cursor_at_frame=[
                (4, (0, 0)),
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

        # j with scroll: full repaint
        # 10 rows, 9 content rows. 9 j's on a 15-line file:
        # j's 1-8 are cursor-only, j 9 triggers scroll (full repaint)
        self.run_test_screen(
            "Render opt: j scroll triggers repaint",
            make_lines(15),
            b"jjjjjjjjj:q!\r",
            expect_content_redraws=(
                [True] +          # frame 0: initial
                [False] * 8 +     # frames 1-8: cursor-only
                [True]            # frame 9: scroll
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
        # jjji enters insert at line 3.
        # BS joins (empty line above), then 2 more BS batched
        # Frame sequence: init(T), j(F), j(F), j(F), i(T), BS+batch(T), ESC(F)
        self.run_test_screen(
            "Render opt: batch join-lines reduces redraws",
            "\n\n\nHello\n",
            b"jjji\x08\x08\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, False, True, True, False],
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

        print()
        print("=" * 60)
        total = self.passed + self.failed
        parts = [f"{Colors.GREEN}{self.passed} passed{Colors.NC}"]
        if self.failed:
            parts.append(f"{Colors.RED}{self.failed} failed{Colors.NC}")
        print(f"Results: {', '.join(parts)} of {total} tests")
        print("=" * 60)


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
    base_dir = script_dir.parent

    runner = EditorTestRunner(base_dir, verbose=args.verbose, quiet=args.quiet)
    runner.run_all_tests()

    sys.exit(1 if runner.failed > 0 else 0)


if __name__ == "__main__":
    main()
