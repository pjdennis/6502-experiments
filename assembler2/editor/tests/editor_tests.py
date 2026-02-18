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
        self.assembler = base_dir / "17" / "out" / "asm.out"
        self.editor_asm = base_dir / "editor" / "editor.asm"
        self.editor_bin = base_dir / "editor" / "out" / "editor.out"
        self.editor_small_bin = base_dir / "editor" / "out" / "editor_small.out"
        self.editor_terminal_bin = base_dir / "editor" / "out" / "editor_terminal.out"
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
               "--no-dump", str(self.editor_asm), str(output_bin)]
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

    def build_terminal_editor(self):
        """Assemble the editor with terminal_mode defined."""
        return self._assemble_editor(self.editor_terminal_bin,
                                     ["define:terminal_mode"])

    def create_stable_copy(self):
        """Create stable copies of editor binaries after successful tests."""
        self._copy_stable(self.editor_bin, "editor_stable.out")
        self._copy_stable(self.editor_terminal_bin, "editor_terminal_stable.out")

    def _copy_stable(self, src_path, dest_name):
        """Copy a binary to a stable copy in the output directory."""
        stable_path = self.base_dir / "editor" / "out" / dest_name
        try:
            shutil.copy2(src_path, stable_path)
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
            [str(self.emulator), str(self.editor_bin), "--no-dump",
             "--load", "0400",
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
                [str(self.emulator), str(self.editor_bin), "--no-dump",
                 "--load", "0400", "--console", input_file],
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

        cmd = [str(self.emulator), str(self.editor_small_bin), "--no-dump",
               "--load", "0400",
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
            [str(self.emulator), str(self.editor_bin), "--no-dump",
             "--load", "0400",
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

    def run_editor_terminal(self, input_file: str, keys: bytes, tmpdir: Path,
                            rows: int = 10, cols: int = 40,
                            extra_args: list = None) -> tuple:
        """Run the terminal-mode editor with serial I/O.

        Returns (exit_code, saved_content, ansi_output_bytes).
        """
        keys_file = tmpdir / "keys.bin"
        output_file = tmpdir / "output.bin"
        keys_file.write_bytes(keys)

        cmd = [str(self.emulator), str(self.editor_terminal_bin),
               "--no-dump", "--load", "0400", "--terminal",
               "--rows", str(rows), "--cols", str(cols),
               "--input", str(keys_file), "--output", str(output_file),
               input_file]
        if extra_args:
            cmd.extend(extra_args)

        result = subprocess.run(cmd, capture_output=True, timeout=10)

        saved = ""
        if Path(input_file).exists():
            try:
                saved = Path(input_file).read_text()
            except UnicodeDecodeError:
                saved = Path(input_file).read_bytes().decode('latin-1')

        ansi = output_file.read_bytes() if output_file.exists() else b""

        return result.returncode, saved, ansi

    def run_test_terminal_screen(self, name: str, initial_content: str,
                                 keys: bytes, rows: int = 10, cols: int = 40,
                                 expect_cursor: tuple = None,
                                 expect_lines: list = None,
                                 expect_status_contains: str = None,
                                 expected_content: str = None,
                                 extra_args: list = None,
                                 expect_content_redraws: list = None,
                                 expect_lines_at_frame: list = None):
        """Run a terminal-mode editor test and verify screen state."""
        with tempfile.TemporaryDirectory(prefix='') as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "t"

            if initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor_terminal(
                    str(edit_file), keys, tmpdir, rows, cols,
                    extra_args=extra_args
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

            # Parse ANSI output through virtual terminal
            screen = AnsiScreen(rows, cols)
            screen.process(ansi.decode('latin-1'))

            if screen.frame_buffer is None:
                self._fail(name, "No rendered frame captured (no ESC[?25h)")
                return

            exp_dump = self._expected_dump(rows, expect_lines, expect_cursor)

            if expect_cursor is not None:
                actual = screen.get_cursor()
                if actual != expect_cursor:
                    self._fail(name,
                        f"Cursor: expected {expect_cursor}, got {actual}\n"
                        f"    Expected:\n{exp_dump}\n"
                        f"    Frame:\n{screen.dump()}")
                    return

            if expect_lines is not None:
                for row_idx, expected_text in expect_lines:
                    actual_text = screen.get_row_text(row_idx)
                    if actual_text != expected_text:
                        self._fail(name,
                            f"Row {row_idx}: expected {expected_text!r}, "
                            f"got {actual_text!r}\n"
                            f"    Expected:\n{exp_dump}\n"
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
                # Build full redraw pattern for diagnostics
                actual_pattern = [screen.was_content_redrawn(i)
                                  for i in range(actual_count)]
                pattern_str = (
                    f"    Total frames: {actual_count}\n"
                    f"    Actual redraws:   {actual_pattern}\n"
                    f"    Expected redraws: {list(expect_content_redraws)}"
                )
                if actual_count < expected_count:
                    self._fail(name,
                        f"Expected {expected_count} frames, got {actual_count}\n"
                        f"{pattern_str}\n"
                        f"    Frame:\n{screen.dump()}")
                    return
                for i, expected_redraw in enumerate(expect_content_redraws):
                    actual_redraw = screen.was_content_redrawn(i)
                    if actual_redraw != expected_redraw:
                        self._fail(name,
                            f"Frame {i}: expected content_redrawn="
                            f"{expected_redraw}, got {actual_redraw}\n"
                            f"{pattern_str}\n"
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

    def run_test_terminal(self, name: str, initial_content: str, keys: bytes,
                          expected_content: str = None, expect_exit: int = 0,
                          extra_args: list = None):
        """Run a terminal-mode editor test verifying file content."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "test.txt"

            if initial_content is not None:
                edit_file.write_text(initial_content)
            else:
                edit_file.write_text("")

            try:
                exit_code, saved, ansi = self.run_editor_terminal(
                    str(edit_file), keys, tmpdir,
                    extra_args=extra_args
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
                        expect_reverse_at: list = None,
                        expect_min_col: list = None,
                        expect_max_col: list = None,
                        expect_scrolled_at_frame: list = None,
                        expect_scroll_rows: list = None,
                        deferred_wrap: bool = False):
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
            expect_min_col: list of (frame_idx, row, min_col) tuples -
                verify minimum column written on a row in a specific frame
            expect_max_col: list of (frame_idx, row, max_col) tuples -
                verify maximum column written on a row in a specific frame
        """
        with tempfile.TemporaryDirectory(prefix='') as tmpdir:
            tmpdir = Path(tmpdir)
            edit_file = tmpdir / "t"

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
            screen = AnsiScreen(rows, cols, deferred_wrap=deferred_wrap)
            screen.process(ansi.decode('latin-1'))

            if screen.frame_buffer is None:
                self._fail(name, "No rendered frame captured (no ESC[?25h)")
                return

            exp_dump = self._expected_dump(rows, expect_lines, expect_cursor)

            if expect_cursor is not None:
                actual = screen.get_cursor()
                if actual != expect_cursor:
                    self._fail(name,
                        f"Cursor: expected {expect_cursor}, got {actual}\n"
                        f"    Expected:\n{exp_dump}\n"
                        f"    Frame:\n{screen.dump()}")
                    return

            if expect_lines is not None:
                for row_idx, expected_text in expect_lines:
                    actual_text = screen.get_row_text(row_idx)
                    if actual_text != expected_text:
                        self._fail(name,
                            f"Row {row_idx}: expected {expected_text!r}, "
                            f"got {actual_text!r}\n"
                            f"    Expected:\n{exp_dump}\n"
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
                # Build full redraw pattern for diagnostics
                actual_pattern = [screen.was_content_redrawn(i)
                                  for i in range(actual_count)]
                pattern_str = (
                    f"    Total frames: {actual_count}\n"
                    f"    Actual redraws:   {actual_pattern}\n"
                    f"    Expected redraws: {list(expect_content_redraws)}"
                )
                if actual_count < expected_count:
                    self._fail(name,
                        f"Expected {expected_count} frames, got {actual_count}\n"
                        f"{pattern_str}\n"
                        f"    Frame:\n{screen.dump()}")
                    return
                for i, expected_redraw in enumerate(expect_content_redraws):
                    actual_redraw = screen.was_content_redrawn(i)
                    if actual_redraw != expected_redraw:
                        self._fail(name,
                            f"Frame {i}: expected content_redrawn="
                            f"{expected_redraw}, got {actual_redraw}\n"
                            f"{pattern_str}\n"
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

            if expect_min_col is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, row, expected_col in expect_min_col:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_col = screen.get_min_col(frame_idx, row)
                    if actual_col != expected_col:
                        self._fail(name,
                            f"Frame {frame_idx}, row {row}: expected "
                            f"min_col={expected_col}, got {actual_col}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_max_col is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, row, expected_col in expect_max_col:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_col = screen.get_max_col(frame_idx, row)
                    if actual_col != expected_col:
                        self._fail(name,
                            f"Frame {frame_idx}, row {row}: expected "
                            f"max_col={expected_col}, got {actual_col}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_scrolled_at_frame is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, expected_scrolled in expect_scrolled_at_frame:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_scrolled = screen.was_scrolled(frame_idx)
                    if actual_scrolled != expected_scrolled:
                        self._fail(name,
                            f"Frame {frame_idx}: expected scrolled="
                            f"{expected_scrolled}, got {actual_scrolled}\n"
                            f"    Frame:\n{screen.dump()}")
                        return

            if expect_scroll_rows is not None:
                actual_count = screen.get_frame_count()
                for frame_idx, expected_rows in expect_scroll_rows:
                    if frame_idx >= actual_count:
                        self._fail(name,
                            f"Expected frame {frame_idx} but only "
                            f"{actual_count} frames\n"
                            f"    Frame:\n{screen.dump()}")
                        return
                    actual_rows = screen.scroll_rows_touched(frame_idx)
                    if actual_rows != expected_rows:
                        self._fail(name,
                            f"Frame {frame_idx}: expected scroll rows "
                            f"{expected_rows}, got {actual_rows}\n"
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

    @staticmethod
    def _expected_dump(rows, expect_lines, expect_cursor):
        """Build expected frame string for diagnostics."""
        exp_lines = dict(expect_lines) if expect_lines else {}
        exp_r, exp_c = expect_cursor if expect_cursor else (None, None)
        parts = []
        for i in range(rows):
            text = repr(exp_lines[i]) if i in exp_lines else "..."
            if i == exp_r:
                parts.append(f"  {i:2d}: {text}  <- cursor at col {exp_c}")
            else:
                parts.append(f"  {i:2d}: {text}")
        return '\n'.join(parts)

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

        # Delete across line boundaries - 6 DELs on short lines should
        # alternate between deleting chars and joining lines.
        # Each "a" line has 1 char, so each pair of DELs does:
        #   DEL 1: delete 'a' (line becomes empty)
        #   DEL 2: join with next line (merges the \n)
        # 6 DELs = 3 pairs = remove 3 of 4 lines, leaving "a\n"
        # BUG: count_pending_key greedily consumes all pending DEL keys,
        # but the cap at line length discards the excess, losing them.
        DEL = b"\x1b[3~"
        self.run_test(
            "Delete across line boundaries not lost to batching cap",
            "a\na\na\na\n",
            b"i" + DEL * 6 + b"\x1b:wq\r",
            expected_content="a\n"
        )

        # Batch DEL across multiple lines - 7 DELs from start of "Hello\nWorld\n"
        # should delete "Hello\n" (6 chars) + "W" (1 char) leaving "orld\n"
        DEL = b"\x1b[3~"
        self.run_test(
            "Batch DEL across multiple lines",
            "Hello\nWorld\n",
            b"i" + DEL * 7 + b"\x1b:wq\r",
            expected_content="orld\n"
        )

        # Batch DEL collapses empty lines - A enters insert at end of "A"
        # (col 1), 4 DELs delete: \n, \n, \n, \n leaving "AB\n"
        DEL = b"\x1b[3~"
        self.run_test(
            "Batch DEL collapses empty lines",
            "A\n\n\n\nB\n",
            b"A" + DEL * 4 + b"\x1b:wq\r",
            expected_content="AB\n"
        )

        # Batch DEL from mid-line across boundary - cursor at col 3,
        # 5 DELs: delete "lo" (2) + \n (1) + "Wo" (2) = "Helrld\n"
        DEL = b"\x1b[3~"
        self.run_test(
            "Batch DEL from mid-line across boundary",
            "Hello\nWorld\n",
            b"llli" + DEL * 5 + b"\x1b:wq\r",
            expected_content="Helrld\n"
        )

        # Batch DEL stops at final newline - 10 DELs but only 3 chars to
        # delete ("A\nB") before final \n, so result is just "\n"
        DEL = b"\x1b[3~"
        self.run_test(
            "Batch DEL stops at final newline",
            "A\nB\n",
            b"i" + DEL * 10 + b"\x1b:wq\r",
            expected_content="\n"
        )

        # Render opt: batch DEL across lines reduces redraws
        # Frame 0: initial (True), Frame 1: i enters insert (False),
        # Frame 2: DEL*4 batched (True), Frame 3: ESC (False)
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: batch DEL across lines",
            "A\nB\nC\n",
            b"i" + DEL * 4 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
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

        self._group("Screen state - half page scroll:", leading_blank=True)

        CTRL_D = b'\x04'
        CTRL_U = b'\x15'

        # Ctrl-D from start (30 lines): half-page = 4
        self.run_test_screen(
            "Ctrl-D: basic half-page down",
            make_lines(30),
            CTRL_D + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+5}") for i in range(9)]
        )

        # Two Ctrl-D's
        self.run_test_screen(
            "Two Ctrl-D's: full window",
            make_lines(30),
            CTRL_D * 2 + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+9}") for i in range(9)]
        )

        # Ctrl-D at end of file: no movement
        self.run_test_screen(
            "Ctrl-D at end: no movement",
            make_lines(30),
            b"G" + CTRL_D + b":q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+22}") for i in range(9)]
        )

        # Ctrl-D short file (5 lines): cursor moves, view stays
        self.run_test_screen(
            "Ctrl-D short file: view stays at top",
            make_lines(5),
            CTRL_D + b":q!\r",
            expect_cursor=(4, 0),
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"),
                (5, "~"), (6, "~"), (7, "~"), (8, "~"),
            ]
        )

        # Ctrl-D column preserved
        self.run_test_screen(
            "Ctrl-D: column preserved",
            make_lines(30),
            b"$" + CTRL_D + b":q!\r",
            expect_cursor=(0, 5),
            expect_lines=[(i, f"Line {i+5}") for i in range(9)]
        )

        # Ctrl-D column clamped to shorter line
        self.run_test_screen(
            "Ctrl-D: column clamped",
            "ABCDEFGHIJ\n" + "XY\n" * 12,
            b"$" + CTRL_D + b":q!\r",
            expect_cursor=(0, 1),
            expect_lines=[(i, "XY") for i in range(9)]
        )

        # Ctrl-D near end: partial scroll, view clamped
        self.run_test_screen(
            "Ctrl-D near end: view clamped",
            make_lines(12),
            CTRL_D + b":q!\r",
            expect_cursor=(1, 0),
            expect_lines=[(i, f"Line {i+4}") for i in range(9)]
        )

        # Count prefix sets scroll amount
        self.run_test_screen(
            "Ctrl-D with count: scroll 2 lines",
            make_lines(30),
            b"2" + CTRL_D + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+3}") for i in range(9)]
        )

        # --- Ctrl-U tests ---

        # Ctrl-U from middle: half-page up
        self.run_test_screen(
            "Ctrl-U: basic half-page up",
            make_lines(30),
            CTRL_F + CTRL_U + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+6}") for i in range(9)]
        )

        # Ctrl-U at start: no movement
        self.run_test_screen(
            "Ctrl-U at start: no movement",
            make_lines(30),
            CTRL_U + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+1}") for i in range(9)]
        )

        # Ctrl-U column preserved
        self.run_test_screen(
            "Ctrl-U: column preserved",
            make_lines(30),
            CTRL_F + b"lll" + CTRL_U + b":q!\r",
            expect_cursor=(0, 3),
            expect_lines=[(i, f"Line {i+6}") for i in range(9)]
        )

        # Multiple Ctrl-U from end
        self.run_test_screen(
            "Two Ctrl-U's from end",
            make_lines(30),
            b"G" + CTRL_U * 2 + b":q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+14}") for i in range(9)]
        )

        # Count prefix sets scroll amount for Ctrl-U
        self.run_test_screen(
            "Ctrl-U with count: scroll 3 lines",
            make_lines(30),
            b"G" + b"3" + CTRL_U + b":q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+19}") for i in range(9)]
        )

        # --- Sticky scroll count ---

        # Count on Ctrl-D is remembered for next Ctrl-D without count
        # 2Ctrl-D scrolls 2; next Ctrl-D (no count) also scrolls 2
        self.run_test_screen(
            "Ctrl-D count sticky for next Ctrl-D",
            make_lines(30),
            b"2" + CTRL_D + CTRL_D + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+5}") for i in range(9)]
        )

        # Ctrl-D count carries to Ctrl-U
        # Ctrl-F to line 9; 2Ctrl-D scrolls 2 (sticky=2); Ctrl-U scrolls 2 back
        self.run_test_screen(
            "Ctrl-D count sticky carries to Ctrl-U",
            make_lines(30),
            CTRL_F + b"2" + CTRL_D + CTRL_U + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+10}") for i in range(9)]
        )

        # Ctrl-U count overrides previous sticky
        # Ctrl-F to line 9; 2Ctrl-D (sticky=2); 3Ctrl-U overrides (sticky=3)
        self.run_test_screen(
            "Ctrl-U count overrides sticky",
            make_lines(30),
            CTRL_F + b"2" + CTRL_D + b"3" + CTRL_U + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+9}") for i in range(9)]
        )

        # --- Combined tests ---

        # Roundtrip: Ctrl-D then Ctrl-U returns to start
        self.run_test_screen(
            "Ctrl-D + Ctrl-U roundtrip",
            make_lines(30),
            CTRL_D + CTRL_U + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+1}") for i in range(9)]
        )

        # Three Ctrl-D's
        self.run_test_screen(
            "Three Ctrl-D's",
            make_lines(30),
            CTRL_D * 3 + b":q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(i, f"Line {i+13}") for i in range(9)]
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

        # Bug repro: last char on first wrap row erased by ESC[K
        # Real terminals use deferred auto-wrap: after writing to the last
        # column, the cursor stays there with a pending-wrap flag. ESC[K
        # then clears from that position, erasing the last character.
        self.run_test_screen(
            "Wrap: last char on first row (deferred wrap)",
            "A" * 60 + "\n",
            b":q!\r",
            expect_lines=[
                (0, "A" * 40),
                (1, "A" * 20),
            ],
            deferred_wrap=True
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

        # l movement: cursor-only (batched into single frame)
        self.run_test_screen(
            "Render opt: lll is cursor-only",
            "Hello\n",
            b"lll:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # h at col 0: cursor-only (no movement, no repaint)
        self.run_test_screen(
            "Render opt: h at col 0 is cursor-only",
            "Hello\n",
            b"h:q!\r",
            expect_content_redraws=[True, False]
        )

        # l at end-of-line: cursor-only (no movement, no repaint)
        self.run_test_screen(
            "Render opt: l at EOL is cursor-only",
            "Hello\n",
            b"$l:q!\r",
            expect_content_redraws=[True, False, False]
        )

        LEFT = b"\x1b[D"
        RIGHT = b"\x1b[C"

        # Insert LEFT at col 0: cursor-only
        self.run_test_screen(
            "Render opt: insert LEFT at col 0 is cursor-only",
            "Hello\n",
            b"i" + LEFT + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Insert RIGHT at end-of-line: cursor-only
        # $=cursor-only, a=cursor-only (enters insert), RIGHT at EOL=cursor-only, ESC=cursor-only
        self.run_test_screen(
            "Render opt: insert RIGHT at EOL is cursor-only",
            "Hello\n",
            b"$a" + RIGHT + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False, False]
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

        # 0 (line start): cursor-only (lll batched into single frame)
        self.run_test_screen(
            "Render opt: 0 is cursor-only",
            "Hello\n",
            b"lll0:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # $ (line end): cursor-only
        self.run_test_screen(
            "Render opt: $ is cursor-only",
            "Hello\n",
            b"$:q!\r",
            expect_content_redraws=[True, False]
        )

        # i enters insert mode: cursor-only (only status bar changes)
        self.run_test_screen(
            "Render opt: i enter insert is cursor-only",
            "Hello\n",
            b"i\x1b:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # a enters insert mode: cursor-only
        self.run_test_screen(
            "Render opt: a enter insert is cursor-only",
            "Hello\n",
            b"a\x1b:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # A enters insert mode: cursor-only
        self.run_test_screen(
            "Render opt: A enter insert is cursor-only",
            "Hello\n",
            b"A\x1b:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # : then ESC (cancel command mode): cursor-only
        self.run_test_screen(
            "Render opt: command cancel is cursor-only",
            "Hello\n",
            b":\x1b:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # Insert HOME at col 0: cursor-only (already at start)
        # i enters insert (F), HOME at col 0 is no-op (F), ESC (F)
        HOME = b"\x1b[H"
        self.run_test_screen(
            "Render opt: insert HOME at col 0 is cursor-only",
            "Hello\n",
            b"i" + HOME + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Insert END at end of line: cursor-only (already at end)
        # $ (F), a enters insert at end (F), END at EOL is no-op (F), ESC (F)
        END = b"\x1b[F"
        self.run_test_screen(
            "Render opt: insert END at EOL is cursor-only",
            "Hello\n",
            b"$a" + END + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False, False]
        )

        # k at first line: cursor-only (no movement, no repaint)
        self.run_test_screen(
            "Render opt: k at first line is cursor-only",
            "Hello\n",
            b"k:q!\r",
            expect_content_redraws=[True, False]
        )

        # j at last line: cursor-only (no movement, no repaint)
        self.run_test_screen(
            "Render opt: j at last line is cursor-only",
            "Hello\n",
            b"j:q!\r",
            expect_content_redraws=[True, False]
        )

        # Insert UP at first line: cursor-only
        UP = b"\x1b[A"
        self.run_test_screen(
            "Render opt: insert UP at first line is cursor-only",
            "Hello\n",
            b"i" + UP + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Insert DOWN at last line: cursor-only
        DOWN = b"\x1b[B"
        self.run_test_screen(
            "Render opt: insert DOWN at last line is cursor-only",
            "Hello\n",
            b"i" + DOWN + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Ctrl-F at bottom of file: cursor-only (view doesn't change)
        # 5-line file, 10 rows (9 content). All lines fit on screen.
        # Ctrl-F clamps to last line but view stays the same.
        CTRL_F = b'\x06'
        CTRL_B = b'\x02'
        self.run_test_screen(
            "Render opt: Ctrl-F at bottom is cursor-only",
            make_lines(5),
            CTRL_F + b":q!\r",
            expect_content_redraws=[True, False]
        )

        # Ctrl-B at top of file: cursor-only (view doesn't change)
        self.run_test_screen(
            "Render opt: Ctrl-B at top is cursor-only",
            make_lines(5),
            CTRL_B + b":q!\r",
            expect_content_redraws=[True, False]
        )

        # Ctrl-D scroll then j: Ctrl-D repaints, j is cursor-only
        CTRL_D = b'\x04'
        CTRL_U = b'\x15'
        self.run_test_screen(
            "Render opt: Ctrl-D scroll then j",
            make_lines(30),
            CTRL_D + b"j:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # Ctrl-U scroll then j: Ctrl-F and Ctrl-U repaint, j is cursor-only
        self.run_test_screen(
            "Render opt: Ctrl-U scroll then j",
            make_lines(30),
            CTRL_F + CTRL_U + b"j:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Batched Ctrl-D: two Ctrl-D's consumed in one frame
        # Frame 0: init(T), Frame 1: both Ctrl-D's batched(T), Frame 2: j(F)
        self.run_test_screen(
            "Render opt: batched Ctrl-D*2 is single frame",
            make_lines(30),
            CTRL_D * 2 + b"j:q!\r",
            expect_cursor=(1, 0),
            expect_lines=[(i, f"Line {i+9}") for i in range(9)],
            expect_content_redraws=[True, True, False]
        )

        # Batched Ctrl-U: two Ctrl-U's consumed in one frame
        # Frame 0: init(T), Frame 1: Ctrl-F(T), Frame 2: both Ctrl-U's(T), Frame 3: j(F)
        self.run_test_screen(
            "Render opt: batched Ctrl-U*2 is single frame",
            make_lines(30),
            CTRL_F + CTRL_U * 2 + b"j:q!\r",
            expect_cursor=(1, 0),
            expect_lines=[(i, f"Line {i+2}") for i in range(9)],
            expect_content_redraws=[True, True, True, False]
        )

        # Insert Ctrl-F at bottom: cursor-only
        self.run_test_screen(
            "Render opt: insert Ctrl-F at bottom is cursor-only",
            make_lines(5),
            b"i" + CTRL_F + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Insert Ctrl-B at top: cursor-only
        self.run_test_screen(
            "Render opt: insert Ctrl-B at top is cursor-only",
            make_lines(5),
            b"i" + CTRL_B + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # G at last line (no scroll): cursor-only
        # On a 5-line file (fits in 9 content rows), G moves to last line
        # but view doesn't change. ensure_cursor_visible won't upgrade.
        self.run_test_screen(
            "Render opt: G on short file is cursor-only",
            make_lines(5),
            b"G:q!\r",
            expect_content_redraws=[True, False]
        )

        # gg at first line: cursor-only (already at top)
        # g+g batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: gg at top is cursor-only",
            "Hello\n",
            b"gg:q!\r",
            expect_content_redraws=[True, False]
        )

        # yy: cursor-only (yank doesn't change display)
        # y+y batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: yy is cursor-only",
            "Hello\n",
            b"yy:q!\r",
            expect_content_redraws=[True, False]
        )

        # Mark goto to current line: cursor-only
        # m+a batched, '+a batched (no pending-key frames)
        self.run_test_screen(
            "Render opt: mark goto same line is cursor-only",
            "Line 1\nLine 2\n",
            b"ma'a:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # w at end of file: cursor-only (no next word to move to)
        self.run_test_screen(
            "Render opt: w at end of file is cursor-only",
            "Hello\n",
            b"$w:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # b at start of file: cursor-only (no previous word)
        self.run_test_screen(
            "Render opt: b at start of file is cursor-only",
            "Hello\n",
            b"b:q!\r",
            expect_content_redraws=[True, False]
        )

        # e at end of file: cursor-only (no next word end)
        self.run_test_screen(
            "Render opt: e at end of file is cursor-only",
            "Hello\n",
            b"$e:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # Forward search, match visible, no scroll -> cursor-only
        # 3-line file, 10 rows. /BBB finds line 1, no scroll.
        # Frame 0: initial (True), Frame 1: /BBB\r complete (False after fix)
        self.run_test_screen(
            "Render opt: search no-scroll is cursor-only",
            "AAA\nBBB\nCCC\n",
            b"/BBB\r:q!\r",
            expect_cursor=(1, 0),
            expect_content_redraws=[True, False]
        )

        # Search with scroll -> full repaint (verify we don't break scrolling)
        # 15-line file, 10 rows. /Line 12 finds line 11 (0-indexed), scrolls.
        self.run_test_screen(
            "Render opt: search with scroll triggers repaint",
            make_lines(15),
            b"/Line 12\r:q!\r",
            expect_content_redraws=[True, True]
        )

        # Find-next (n) no-scroll -> cursor-only
        # /AAA on "AAA\nBBB\nAAA\n" finds line 2. n wraps to line 0 (visible).
        self.run_test_screen(
            "Render opt: n no-scroll is cursor-only",
            "AAA\nBBB\nAAA\n",
            b"/AAA\rn:q!\r",
            expect_cursor=(0, 0),
            expect_content_redraws=[True, False, False]
        )

        # Cancel search (ESC) -> cursor-only
        self.run_test_screen(
            "Render opt: search cancel is cursor-only",
            "AAA\nBBB\n",
            b"/\x1b:q!\r",
            expect_content_redraws=[True, False]
        )

        # Not found -> cursor-only after dismissal
        # Space dismisses the "not found" message (consumed inside search handler)
        self.run_test_screen(
            "Render opt: search not-found is cursor-only",
            "AAA\nBBB\nCCC\n",
            b"/ZZZ\r :q!\r",
            expect_cursor=(0, 0),
            expect_content_redraws=[True, False]
        )

        # Insert char: only cursor's row is touched (not all rows)
        # i enters insert (cursor-only), 'X' inserts char
        # Single-row optimization: only row 0 is redrawn
        self.run_test_screen(
            "Render opt: insert char redraws from cursor",
            "Hello\nWorld\n",
            b"iX\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
            expect_content_rows=[(2, {0})]
        )

        # Backspace mid-line: single-row redraw
        # Move right, enter insert, backspace (mid-line)
        self.run_test_screen(
            "Render opt: backspace redraws from cursor",
            "Hello\nWorld\n",
            b"li\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, True, False],
            expect_content_rows=[(3, {0})]
        )

        # Normal mode x: single-row redraw
        self.run_test_screen(
            "Render opt: x redraws from cursor",
            "Hello\nWorld\n",
            b"x:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0})]
        )

        # r replaces char: single-row redraw
        # Frame 0: init(T), Frame 1: r+X batched replaces(T), Frame 2: :q!(F)
        self.run_test_screen(
            "Render opt: r replaces with single-row redraw",
            "Hello\n",
            b"rX:q!\r",
            expect_content_redraws=[True, True, False],
            expect_content_rows=[(1, {0})]
        )

        # ~ toggles case: single-row redraw
        self.run_test_screen(
            "Render opt: ~ toggles with single-row redraw",
            "Hello\n",
            b"~:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0})]
        )

        # s substitutes: single-row redraw for the s frame
        # Frame 0: init(T), Frame 1: s deletes+enters insert(T), Frame 2: X inserts(T), Frame 3: ESC(F)
        self.run_test_screen(
            "Render opt: s substitutes with single-row redraw",
            "Hello\n",
            b"sX\x1b:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # Insert Delete (forward delete): single-row redraw
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: insert Delete single-row redraw",
            "Hello\n",
            b"i" + DEL + b"\x1b:q!\r",
            expect_content_rows=[(2, {0})]
        )

        # D deletes to end of line: single-row redraw
        self.run_test_screen(
            "Render opt: D redraws current row only",
            "Hello World\n",
            b"D:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # dw deletes word: single-row redraw
        # d+w batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: dw redraws current row only",
            "Hello World\n",
            b"dw:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # db deletes word backward: single-row redraw
        # Frame 0: init(T), Frame 1: $(F), Frame 2: d+b batched(T)
        self.run_test_screen(
            "Render opt: db redraws current row only",
            "Hello World\n",
            b"$db:q!\r",
            expect_content_rows=[(2, {0})]
        )

        # C changes to end of line: single-row redraw
        self.run_test_screen(
            "Render opt: C redraws current row only",
            "Hello World\n",
            b"C\x1b:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # cw changes word: single-row redraw
        # c+w batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: cw redraws current row only",
            "Hello World\n",
            b"cw\x1b:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # cb changes word backward: single-row redraw
        # Frame 0: init(T), Frame 1: $(F), Frame 2: c+b batched(T)
        self.run_test_screen(
            "Render opt: cb redraws current row only",
            "Hello World\n",
            b"$cb\x1b:q!\r",
            expect_content_rows=[(2, {0})]
        )

        # de deletes to word end: single-row redraw
        # d+e batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: de redraws current row only",
            "Hello World\n",
            b"de:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # ce changes to word end: single-row redraw
        # c+e batched into single frame (no pending-key frame)
        self.run_test_screen(
            "Render opt: ce redraws current row only",
            "Hello World\n",
            b"ce\x1b:q!\r",
            expect_content_rows=[(1, {0})]
        )

        # char paste p: single-row redraw
        self.run_test_screen(
            "Render opt: char paste p redraws current row only",
            "Hello\n",
            b"xp:q!\r",
            expect_content_rows=[(2, {0})]
        )

        # char paste P: single-row redraw
        self.run_test_screen(
            "Render opt: char paste P redraws current row only",
            "Hello\n",
            b"xP:q!\r",
            expect_content_rows=[(2, {0})]
        )

        # --- Wrapped-line optimization tests (line spans 2+ screen rows) ---
        # "A"*60 = 2 rows on a 40-col screen (40+20)

        # Insert in wrapped line, same wrap count
        # Frame 0: init(T), Frame 1: i enters insert(F), Frame 2: X inserts(T)
        self.run_test_screen(
            "Render opt: insert in wrapped line, same count",
            "A" * 60 + "\nSecond\n",
            b"iX\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
            expect_content_rows=[(2, {0, 1})]
        )

        # x in wrapped line, same wrap count
        self.run_test_screen(
            "Render opt: x in wrapped line, same count",
            "A" * 60 + "\nSecond\n",
            b"x:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0, 1})]
        )

        # r replaces char in wrapped line
        # Frame 0: init(T), Frame 1: r+X batched replaces(T)
        self.run_test_screen(
            "Render opt: r in wrapped line",
            "A" * 60 + "\nSecond\n",
            b"rX:q!\r",
            expect_content_redraws=[True, True, False],
            expect_content_rows=[(1, {0})]
        )

        # ~ toggles case in wrapped line
        self.run_test_screen(
            "Render opt: ~ in wrapped line",
            "a" * 60 + "\nSecond\n",
            b"~:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0})]
        )

        # D in wrapped line stays wrapped (at col 0, deletes most but 40+ remain? No.
        # Actually $D from col 0 deletes all to EOL -> single char line.
        # Use $ to go to end, then come back: move to col 20 (on 2nd wrap row),
        # D deletes from col 20 to end -> 20 chars left = 1 row.
        # That changes row count, so it renders from first row downward.
        # Better test: line is 80 chars (2 full rows), D from col 0 -> empty = 1 row, rows change
        # For "stays wrapped": line is 80 chars, delete 1 with x -> 79 chars = still 2 rows
        self.run_test_screen(
            "Render opt: $D wrapped line stays wrapped",
            "A" * 60 + "\nSecond\n",
            b"$D:q!\r",
            expect_content_rows=[(2, {0, 1})]
        )

        # x unwraps line (41 chars -> 40 after first x -> 1 row), renders from first row
        # Row count changes from 2 to 1 on the first x, so render_from_row is used
        self.run_test_screen(
            "Render opt: x unwraps line, renders from first row",
            "A" * 41 + "\nSecond\n",
            b"x:q!\r",
            expect_content_rows=[(1, set(range(9)))]
        )

        # Insert newline: full repaint (multiple lines change)
        self.run_test_screen(
            "Render opt: Enter in insert is full repaint",
            "Hello\nWorld\n",
            b"i\r\x1b:q!\r",
            expect_content_redraws=[True, False, True, False]
        )

        # Backspace at col 0 (join lines): full repaint
        self.run_test_screen(
            "Render opt: backspace join-lines is full repaint",
            "Hello\nWorld\n",
            b"ji\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, True, False]
        )

        # ============================================================
        # Batch insert tests
        # When multiple printable keys are buffered, they should be
        # inserted in a single operation with one render.
        # ============================================================
        self._group("Batch insert:", leading_blank=True)

        # Render optimization: batch insert reduces content redraws
        # Frame 0: initial render (True)
        # Frame 1: 'i' enters insert mode (False - cursor+status only)
        # Frame 2: first char 'X' inserted, then Y and Z batched (True)
        # Frame 3: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: batch insert reduces redraws",
            "Hello\n",
            b"iXYZ\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
        )

        # Batch insert mid-line correctness
        self.run_test(
            "Batch insert mid-line",
            "ABCD\n",
            b"liXYZ\x1b:wq\r",
            expected_content="AXYZBCD\n"
        )

        # Batch includes newline (Enter after printable chars)
        self.run_test(
            "Batch insert includes newline",
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

        # --- Enter mixing: correctness ---

        # Mixed chars and newlines batched together
        self.run_test(
            "Mixed chars and newlines",
            "Hello\n",
            b"ia\rb\rc\r\x1b:wq\r",
            expected_content="a\nb\nc\nHello\n"
        )

        # Char then only newlines
        self.run_test(
            "Char then only newlines",
            "X\n",
            b"ia\r\r\r\x1b:wq\r",
            expected_content="a\n\n\nX\n"
        )

        # Mixed batch mid-line
        self.run_test(
            "Mixed batch mid-line",
            "XY\n",
            b"lia\rb\r\x1b:wq\r",
            expected_content="Xa\nb\nY\n"
        )

        # --- Enter mixing: render optimization ---
        # i\ra\ra\ra\r on "Hello\n"
        # Frame 0: initial render (True)
        # Frame 1: 'i' enters insert mode (False - cursor+status only)
        # Frame 2: enter key triggers newline insert (True)
        # Frame 3: 'a' + remaining \ra\r batched together (True)
        # Frame 4: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: mixed enter+chars reduces redraws",
            "Hello\n",
            b"i\ra\ra\ra\r\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
        )

        # --- Enter mixing: cursor position ---

        # After ia\rb\r\x1b -> cursor at (2, 0) - trailing newline, col 0
        self.run_test_screen(
            "Mixed batch cursor: trailing newline",
            "Hello\n",
            b"ia\rb\r\x1b:q!\r",
            expect_cursor=(2, 0),
        )

        # After ia\rbc\x1b -> cursor at (1, 1) - trailing chars, ESC back 1
        self.run_test_screen(
            "Mixed batch cursor: trailing chars",
            "Hello\n",
            b"ia\rbc\x1b:q!\r",
            expect_cursor=(1, 1),
        )

        # --- Backspace cancellation: correctness ---

        # BS cancels within batch: iabBSc -> "ac"
        self.run_test(
            "BS cancels within batch",
            "Hello\n",
            b"iab\x08c\x1b:wq\r",
            expected_content="acHello\n"
        )

        # BS cancels newline: ia\rBSb -> "ab"
        self.run_test(
            "BS cancels newline in batch",
            "Hello\n",
            b"ia\r\x08" b"b\x1b:wq\r",
            expected_content="abHello\n"
        )

        # BS cancels all -> no-op (second BS pushed back, at col 0 it's no-op)
        self.run_test(
            "BS cancels all in batch is no-op",
            "Hello\n",
            b"ia\x08\x08\x1b:wq\r",
            expected_content="Hello\n"
        )

        # BS then more typing: iabcBSBSde -> "ade"
        self.run_test(
            "BS then more typing",
            "X\n",
            b"iabc\x08\x08de\x1b:wq\r",
            expected_content="adeX\n"
        )

        # BS mixed with Enter: ia\rbBSc\r -> "a\nc\n"
        self.run_test(
            "BS mixed with Enter",
            "Z\n",
            b"ia\rb\x08c\r\x1b:wq\r",
            expected_content="a\nc\nZ\n"
        )

        # --- Backspace cancellation: render optimization ---
        # iabBSc on "Hello\n"
        # Frame 0: initial render (True)
        # Frame 1: 'i' enters insert mode (False - cursor+status only)
        # Frame 2: batch abBSc -> "ac" (True - single batch)
        # Frame 3: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: BS cancellation in single batch",
            "Hello\n",
            b"iab\x08c\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
        )

        # ============================================================
        # Mixed-type batch tests (unified insert_batch handler)
        # When mixed editing keys (printable, Enter, BS, DEL) arrive
        # in rapid succession, they should be consolidated into a
        # single buffer operation.
        # ============================================================
        self._group("Mixed-type batch:", leading_blank=True)

        # DEL then typing: position cursor at start, DEL deletes first
        # char, then type "Z" -> "Z" replaces first char
        DEL = b"\x1b[3~"
        self.run_test(
            "DEL then typing in single batch",
            "Hello\n",
            b"i" + DEL + b"Z\x1b:wq\r",
            expected_content="Zello\n"
        )

        # Multiple DEL then typing: 3 DELs then "ABC"
        DEL = b"\x1b[3~"
        self.run_test(
            "Multiple DEL then typing",
            "Hello World\n",
            b"i" + DEL * 3 + b"ABC\x1b:wq\r",
            expected_content="ABClo World\n"
        )

        # Typing then DEL: type "XY" then DEL removes char after insert
        DEL = b"\x1b[3~"
        self.run_test(
            "Typing then DEL in single batch",
            "Hello\n",
            b"i" + b"XY" + DEL + b"\x1b:wq\r",
            expected_content="XYello\n"
        )

        # BS overflow into buffer delete: type "a", then BS*2
        # First BS cancels 'a', second BS deletes char before cursor
        self.run_test(
            "BS overflow deletes from buffer",
            "Hello\n",
            b"lla" + b"\x08\x08\x1b:wq\r",
            expected_content="Hlo\n"
        )

        # Mixed DEL + BS: DEL*2 then BS*1 at col 2
        # DEL removes 2 chars forward, BS removes 1 char backward
        DEL = b"\x1b[3~"
        self.run_test(
            "DEL and BS mixed in batch",
            "ABCDE\n",
            b"lli" + DEL * 2 + b"\x08\x1b:wq\r",
            expected_content="AE\n"
        )

        # DEL across newline then typing
        DEL = b"\x1b[3~"
        self.run_test(
            "DEL across newline then typing",
            "AB\nCD\n",
            b"lli" + DEL * 3 + b"XY\x1b:wq\r",
            expected_content="AXYD\n"
        )

        # BS across newline then typing (col 0 BS joins line)
        self.run_test(
            "BS across newline then typing",
            "AB\nCD\n",
            b"ji\x08XY\x1b:wq\r",
            expected_content="ABXYCD\n"
        )

        # Pure DEL batch (same as before, should still work)
        DEL = b"\x1b[3~"
        self.run_test(
            "Pure DEL batch still works",
            "ABCDE\n",
            b"i" + DEL * 3 + b"\x1b:wq\r",
            expected_content="DE\n"
        )

        # BS cancels all then DEL: type "ab", BS*2 cancels, DEL*2 forward
        DEL = b"\x1b[3~"
        self.run_test(
            "BS cancels batch then DEL forward",
            "Hello\n",
            b"iab\x08\x08" + DEL * 2 + b"\x1b:wq\r",
            expected_content="llo\n"
        )

        # DEL at end of last line (past final newline) is no-op
        DEL = b"\x1b[3~"
        self.run_test(
            "DEL at final newline is no-op",
            "A\n",
            b"A" + DEL * 5 + b"\x1b:wq\r",
            expected_content="A\n"
        )

        # Mixed render optimization: DEL+typing in single batch
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: DEL+typing in single batch",
            "Hello\n",
            b"i" + DEL * 2 + b"AB\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
        )

        # Mixed: type, Enter, DEL all in one batch
        DEL = b"\x1b[3~"
        self.run_test(
            "Type Enter DEL in one batch",
            "Hello\n",
            b"iX\r" + DEL + b"\x1b:wq\r",
            expected_content="X\nello\n"
        )

        # ============================================================
        # Batch delete tests
        # When multiple backspace or x keys are buffered, they should
        # be deleted in a single operation with one render.
        # ============================================================
        self._group("Batch delete:", leading_blank=True)

        # Render optimization: batch backspace reduces content redraws
        # Frame 0: initial render (True)
        # Frame 1: lll batched (False - cursor only)
        # Frame 2: i enters insert mode (False - cursor+status only)
        # Frame 3: first BS deletes, then 2 more batched (True)
        # Frame 4: ESC exits insert (False - cursor only)
        self.run_test_screen(
            "Render opt: batch backspace reduces redraws",
            "Hello\n",
            b"llli\x08\x08\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, True, False],
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
        # Frame 1: i enters insert (False - cursor+status only)
        # Frame 2: first Del + batch Del*2 (True)
        # Frame 3: ESC exits insert (False - cursor only)
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "Render opt: batch insert Delete reduces redraws",
            "Hello\n",
            b"i" + DEL * 3 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
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
        # Frame 0: initial (True), Frame 1: i enters insert (False),
        # Frame 2: first Enter + batch Enter*2 (True), Frame 3: ESC (False)
        self.run_test_screen(
            "Render opt: batch Enter reduces redraws",
            "Hello\n",
            b"i\r\r\r\x1b:q!\r",
            expect_content_redraws=[True, False, True, False],
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
        # Frame sequence: init(T), jjj-batched(F), i(F), BS+batch(T), ESC(F)
        self.run_test_screen(
            "Render opt: batch join-lines reduces redraws",
            "\n\n\nHello\n",
            b"jjji\x08\x08\x08\x1b:q!\r",
            expect_content_redraws=[True, False, False, True, False],
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
        # Screen content verification after insert mode operations
        # These tests verify the DISPLAYED content (not just file
        # content) is correct after various insert mode operations,
        # including batched and multi-line edits.
        # ============================================================
        self._group("Insert mode screen content:", leading_blank=True)

        # Single Enter splits line - screen shows both halves
        self.run_test_screen(
            "Enter splits line: screen shows both halves",
            "Hello World\n",
            b"llllli\rX\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Hello"), (1, "X World"),
            ],
            expect_cursor=(1, 0),
        )

        # Batched Enter (2 Enters) - screen shows all lines correctly
        self.run_test_screen(
            "Batched Enter: screen shows all new lines",
            "Hello World\n",
            b"llllli\r\r\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Hello"), (1, ""), (2, " World"),
                (3, "~"),
            ],
            expect_cursor=(2, 0),
        )

        # Batched Enter (3 Enters) - screen shows all lines correctly
        self.run_test_screen(
            "Batched 3 Enters: screen shows all new lines",
            "ABCDEF\n",
            b"llli\r\r\r\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "ABC"), (1, ""), (2, ""), (3, "DEF"),
                (4, "~"),
            ],
            expect_cursor=(3, 0),
        )

        # Batched Enter at start of line
        self.run_test_screen(
            "Batched Enter at start: blank lines above",
            "Hello\nWorld\n",
            b"ji\r\r\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Hello"), (1, ""), (2, ""), (3, "World"),
                (4, "~"),
            ],
            expect_cursor=(3, 0),
        )

        # Enter with chars (a\rb\r) - screen shows all content
        self.run_test_screen(
            "Mixed chars and Enter: screen correct",
            "XY\n",
            b"ia\rb\r\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "a"), (1, "b"), (2, "XY"),
            ],
            expect_cursor=(2, 0),
        )

        # Batched Enter causing scroll with mid-screen insertion.
        # With 6 rows (5 content + 1 status), lines 1-5 fill the screen.
        # Cursor on Line 3 (row 2, middle of screen). 'A' enters insert at
        # end, then 3 Enter keys are batched. This inserts 3 blank lines
        # after "Line 3", making: Line 1-3, (blank)×3, Line 4-5 = 8 lines.
        # Cursor lands on 3rd blank (line index 5). View scrolls to keep
        # cursor visible (VIEW_TOP moves from 0 to 1).
        # The scroll optimization shifts the old screen up and only redraws
        # newly exposed bottom rows, but the rows below the insertion point
        # changed (should be blank lines, not the old "Line 4"/"Line 5").
        # Expected screen (VIEW_TOP=1, showing lines 1-5):
        #   row 0: "Line 2", row 1: "Line 3", row 2: "", row 3: "", row 4: ""
        self.run_test_screen(
            "Batched Enter with scroll: display not corrupted",
            make_lines(5),
            b"jjA\r\r\r\x1b:q!\r",
            rows=6, cols=40,
            expect_lines=[
                (0, "Line 2"), (1, "Line 3"), (2, ""), (3, ""), (4, ""),
            ],
            expect_cursor=(4, 0),
        )

        # Batched BS at col 0 joining lines - screen shows merged content
        self.run_test_screen(
            "BS at col 0 joins: screen shows merged line",
            "Hello\nWorld\n",
            b"ji\x08\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "HelloWorld"), (1, "~"),
            ],
            expect_cursor=(0, 4),
        )

        # Batched BS at col 0: 3 BS deletes 3 bytes backward from cursor
        # Cursor at col 0 of "DD". 3 bytes back = "CC\n" → delete that.
        # Result: "AA\nBB\nDD\n"
        self.run_test_screen(
            "Batched BS joins one line: screen correct",
            "AA\nBB\nCC\nDD\n",
            b"jjji\x08\x08\x08\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "AA"), (1, "BB"), (2, "DD"), (3, "~"),
            ],
            expect_cursor=(2, 0),
        )

        # DEL at end of line joining with next - screen correct
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "DEL at EOL joins lines: screen correct",
            "Hello\nWorld\n",
            b"A" + DEL + b"\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "HelloWorld"), (1, "~"),
            ],
            expect_cursor=(0, 4),
        )

        # ============================================================
        # Screen content verification after normal mode editing
        # ============================================================
        self._group("Normal mode editing screen content:", leading_blank=True)

        # D (delete to EOL) - screen shows truncated line
        self.run_test_screen(
            "D deletes to EOL: screen correct",
            "Hello World\n",
            b"lllllD:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello")],
            expect_cursor=(0, 4),
        )

        # d$ - same as D, screen shows truncated line
        self.run_test_screen(
            "d$ deletes to EOL: screen correct",
            "Hello World\n",
            b"llllld$:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello")],
            expect_cursor=(0, 4),
        )

        # 2d$ - multi-line delete, screen updates correctly
        self.run_test_screen(
            "2d$ multi-line: screen correct",
            "Hello\nWorld\nFoo\n",
            b"ll2d$:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "He"), (1, "Foo")],
            expect_cursor=(0, 1),
        )

        # d0 - screen shows shortened line
        self.run_test_screen(
            "d0 deletes to BOL: screen correct",
            "Hello\n",
            b"llld0:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "lo")],
            expect_cursor=(0, 0),
        )

        # C (change to EOL) - enters insert after deleting to EOL
        self.run_test_screen(
            "C changes to EOL: screen correct",
            "Hello World\nLine 2\n",
            b"lllllCXYZ\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "HelloXYZ"), (1, "Line 2")],
            expect_cursor=(0, 7),
        )

        # S (substitute line) - replaces entire line
        self.run_test_screen(
            "S substitutes line: screen correct",
            "Hello\nWorld\n",
            b"SXYZ\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "XYZ"), (1, "World")],
            expect_cursor=(0, 2),
        )

        # s (substitute char) - replaces single char, enters insert
        self.run_test_screen(
            "s substitutes char: screen correct",
            "Hello\nWorld\n",
            b"sX\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Xello"), (1, "World")],
            expect_cursor=(0, 0),
        )

        # 3s (substitute 3 chars) - replaces 3 chars
        self.run_test_screen(
            "3s substitutes 3 chars: screen correct",
            "Hello\nWorld\n",
            b"3sXYZ\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "XYZlo"), (1, "World")],
            expect_cursor=(0, 2),
        )

        # o (open below) - creates new line below
        self.run_test_screen(
            "o opens below: screen correct",
            "Line 1\nLine 2\n",
            b"oNew\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 1"), (1, "New"), (2, "Line 2")],
            expect_cursor=(1, 2),
        )

        # O (open above) - creates new line above
        self.run_test_screen(
            "O opens above: screen correct",
            "Line 1\nLine 2\n",
            b"jONew\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 1"), (1, "New"), (2, "Line 2")],
            expect_cursor=(1, 2),
        )

        # J (join lines) - screen shows merged line
        self.run_test_screen(
            "J joins lines: screen correct",
            "Hello\nWorld\n",
            b"J:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello World"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # 3J joins 3 lines
        self.run_test_screen(
            "3J joins 3 lines: screen correct",
            "AA\nBB\nCC\nDD\n",
            b"3J:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "AA BB CC"), (1, "DD")],
            expect_cursor=(0, 0),
        )

        # cc (change line) - replaces line content
        self.run_test_screen(
            "cc changes line: screen correct",
            "Hello\nWorld\n",
            b"ccNew\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "New"), (1, "World")],
            expect_cursor=(0, 2),
        )

        # 2cc (change 2 lines) - deletes 2, inserts blank
        self.run_test_screen(
            "2cc changes 2 lines: screen correct",
            "Line 1\nLine 2\nLine 3\n",
            b"2ccNew\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "New"), (1, "Line 3")],
            expect_cursor=(0, 2),
        )

        # dd - deletes line
        self.run_test_screen(
            "dd deletes line: screen correct",
            "Line 1\nLine 2\nLine 3\n",
            b"dd:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 2"), (1, "Line 3"), (2, "~")],
            expect_cursor=(0, 0),
        )

        # 2dd - deletes 2 lines
        self.run_test_screen(
            "2dd deletes 2 lines: screen correct",
            "Line 1\nLine 2\nLine 3\nLine 4\n",
            b"2dd:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 3"), (1, "Line 4"), (2, "~")],
            expect_cursor=(0, 0),
        )

        # p (paste below) - screen shows pasted content
        self.run_test_screen(
            "p pastes line below: screen correct",
            "Line 1\nLine 2\nLine 3\n",
            b"ddp:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 2"), (1, "Line 1"), (2, "Line 3")],
            expect_cursor=(1, 0),
        )

        # P (paste above) - screen shows pasted content
        self.run_test_screen(
            "P pastes line above: screen correct",
            "Line 1\nLine 2\nLine 3\n",
            b"ddjP:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 2"), (1, "Line 1"), (2, "Line 3")],
            expect_cursor=(1, 0),
        )

        # 2x with screen verification
        self.run_test_screen(
            "2x deletes 2 chars: screen correct",
            "Hello\nWorld\n",
            b"2x:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "llo"), (1, "World")],
            expect_cursor=(0, 0),
        )

        # >> indent - screen shows indented line
        self.run_test_screen(
            ">> indents line: screen correct",
            "Hello\nWorld\n",
            b">>:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "  Hello"), (1, "World")],
            expect_cursor=(0, 2),
        )

        # << unindent - screen shows unindented line
        self.run_test_screen(
            "<< unindents line: screen correct",
            "  Hello\nWorld\n",
            b"<<:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello"), (1, "World")],
            expect_cursor=(0, 0),
        )

        # r (replace char) - screen shows replaced char
        self.run_test_screen(
            "r replaces char: screen correct",
            "Hello\nWorld\n",
            b"rX:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Xello"), (1, "World")],
            expect_cursor=(0, 0),
        )

        # ~ (toggle case) - screen shows toggled char
        self.run_test_screen(
            "~ toggles case: screen correct",
            "Hello\n",
            b"~~~:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "hELlo")],
            expect_cursor=(0, 3),
        )

        # dw (delete word) - screen shows result
        self.run_test_screen(
            "dw deletes word: screen correct",
            "Hello World\n",
            b"dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "World")],
            expect_cursor=(0, 0),
        )

        # cw (change word) - replaces word
        self.run_test_screen(
            "cw changes word: screen correct",
            "Hello World\n",
            b"cwBye\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Bye World")],
            expect_cursor=(0, 2),
        )

        # db (delete word backward) - screen correct
        self.run_test_screen(
            "db deletes word: screen correct",
            "Hello World\n",
            b"wdb:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "World")],
            expect_cursor=(0, 0),
        )

        # 2dw - screen shows result
        self.run_test_screen(
            "2dw deletes 2 words: screen correct",
            "one two three\n",
            b"2dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "three")],
            expect_cursor=(0, 0),
        )

        # 2db - screen shows result
        self.run_test_screen(
            "2db deletes 2 words backward: screen correct",
            "one two three\n",
            b"$2db:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "one e")],
            expect_cursor=(0, 4),
        )

        # de (delete word end) - screen correct
        self.run_test_screen(
            "de deletes to word end: screen correct",
            "Hello World\n",
            b"de:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, " World")],
            expect_cursor=(0, 0),
        )

        # 2p line paste - screen shows all pasted lines
        self.run_test_screen(
            "2p line paste: screen correct",
            "A\nB\nC\n",
            b"yy2p:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "A"), (2, "A"), (3, "B"), (4, "C")],
            expect_cursor=(1, 0),
        )

        # 2P line paste above - screen correct
        self.run_test_screen(
            "2P line paste above: screen correct",
            "A\nB\n",
            b"yy2P:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "A"), (2, "A"), (3, "B")],
            expect_cursor=(0, 0),
        )

        # Batched pp line paste - screen correct
        self.run_test_screen(
            "Batched pp line paste: screen correct",
            "A\nB\nC\n",
            b"yypp:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "A"), (2, "A"), (3, "B"), (4, "C")],
            expect_cursor=(2, 0),
        )

        # Batched PPP line paste above - screen correct
        self.run_test_screen(
            "Batched PPP line paste above: screen correct",
            "A\nB\n",
            b"yyPPP:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "A"), (2, "A"), (3, "A"), (4, "B")],
            expect_cursor=(0, 0),
        )

        # 2p char paste - screen correct
        # x on "AB" yanks 'A' leaving "B", 2p pastes "AA" after cursor → "BAA"
        self.run_test_screen(
            "2p char paste: screen correct",
            "AB\n",
            b"x2p:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "BAA")],
            expect_cursor=(0, 2),
        )

        # Batched pp char paste - screen correct
        self.run_test_screen(
            "Batched pp char paste: screen correct",
            "Hello\n",
            b"xpp:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "eHHllo")],
            expect_cursor=(0, 2),
        )

        # ============================================================
        # Cross-line screen content: paste, dw/db unwrapping
        # Operations that add/remove newlines, verified via screen state
        # ============================================================
        self._group("Cross-line screen content:", leading_blank=True)

        # --- Multi-line char paste (content with newlines) ---

        # db yanks across newline ("foo\n"), p pastes inline after cursor
        # Result: "barfoo\n\n" - cursor at first pasted char (col 3)
        self.run_test_screen(
            "Multi-line char paste p: screen correct",
            "foo\nbar\n",
            b"jdb$p:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "barfoo"), (1, ""), (2, "~"),
            ],
            expect_cursor=(0, 3),
        )

        # db yanks across newline, P pastes multi-line content above
        self.run_test_screen(
            "Multi-line char paste P: screen correct",
            "foo\nbar\n",
            b"jdb0P:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "foo"), (1, "bar"),
            ],
            expect_cursor=(0, 0),
        )

        # D yanks rest of line, paste on next line inserts chars inline
        self.run_test_screen(
            "D + p char paste on next line: screen correct",
            "ABCDE\nXY\n",
            b"lDjp:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "A"), (1, "XBCDEY"),
            ],
            expect_cursor=(1, 4),
        )

        # Multi-line char paste with 2p (two copies of "foo\n")
        # Inserts "foo\nfoo\n" after 'r': "barfoo\nfoo\n\n"
        self.run_test_screen(
            "Multi-line char 2p: screen correct",
            "foo\nbar\n",
            b"jdb$2p:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "barfoo"), (1, "foo"), (2, ""), (3, "~"),
            ],
            expect_cursor=(0, 3),
        )

        # Multi-line char paste with batched pp (same content, same cursor for multiline)
        self.run_test_screen(
            "Multi-line char batched pp: screen correct",
            "foo\nbar\n",
            b"jdb$pp:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "barfoo"), (1, "foo"), (2, ""), (3, "~"),
            ],
            expect_cursor=(0, 3),
        )

        # --- Char paste causing line wrapping ---
        # Paste content that pushes a line beyond screen width

        # Single char paste causing wrap
        # yw on 18 A's yanks "AAAAAAAAAAAAAAAAAA", 2G to B line, p inserts after col 0
        # Result: "B" + 18 A's + 17 B's = 36 chars; wraps at col 20
        self.run_test_screen(
            "Char paste causes line wrap: screen correct",
            "A" * 18 + "\n" + "B" * 18 + "\n",
            b"yw2Gp:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A" * 18),
                (1, "B" + "A" * 18 + "B"),             # first 20 chars
                (2, "B" * 16),                          # remaining 16 B's
            ],
            expect_cursor=(1, 18),
        )

        # Char 2p paste causing wrap
        # yw yanks 10 A's, 2G to B line, 2p inserts 20 A's after col 0
        # Result: "B" + 20 A's + 4 B's = 25 chars
        self.run_test_screen(
            "Char 2p causing line wrap: screen correct",
            "A" * 10 + "\n" + "B" * 5 + "\n",
            b"yw2G2p:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A" * 10),
                (1, "B" + "A" * 19),                   # first 20
                (2, "A" + "B" * 4),                     # remaining 5
            ],
            expect_cursor=(2, 0),
        )

        # Batched char pp causing wrap (same content/cursor as 2p for single-line yank)
        self.run_test_screen(
            "Char batched pp causing line wrap: screen correct",
            "A" * 10 + "\n" + "B" * 5 + "\n",
            b"yw2Gpp:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A" * 10),
                (1, "B" + "A" * 19),                   # first 20
                (2, "A" + "B" * 4),                     # remaining 5
            ],
            expect_cursor=(2, 0),
        )

        # Line paste causing wrap (pasted line is wider than screen)
        self.run_test_screen(
            "Line paste of long line causes wrap: screen correct",
            "A" * 25 + "\nshort\n",
            b"yyjp:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A" * 20),      # first line wraps: first 20
                (1, "AAAAA"),        # wrap continuation
                (2, "short"),
                (3, "A" * 20),      # pasted line wraps: first 20
                (4, "AAAAA"),        # wrap continuation
            ],
            expect_cursor=(3, 0),
        )

        # --- dw causing unwrap (deleting across newlines) ---

        # 2dw crossing line boundary - unwraps lines
        self.run_test_screen(
            "2dw crossing line: screen correct",
            "one\ntwo three\n",
            b"2dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "three"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # dw at last word on line (exclusive-linewise: deletes word, keeps newline)
        self.run_test_screen(
            "dw at last word: screen correct",
            "foo\nbar\n",
            b"dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, ""), (1, "bar")],
            expect_cursor=(0, 0),
        )

        # Batched dwdw crossing line boundary
        self.run_test_screen(
            "Batched dwdw crossing line: screen correct",
            "one two\nthree four\n",
            b"dwdw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, ""), (1, "three four")],
            expect_cursor=(0, 0),
        )

        # 2dw single-line (no unwrap)
        self.run_test_screen(
            "2dw single-line: screen correct",
            "one two three four\n",
            b"2dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "three four")],
            expect_cursor=(0, 0),
        )

        # Batched dwdw single-line
        self.run_test_screen(
            "Batched dwdw single-line: screen correct",
            "one two three four\n",
            b"dwdw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "three four")],
            expect_cursor=(0, 0),
        )

        # 3dw crossing multiple lines
        self.run_test_screen(
            "3dw crossing 2 lines: screen correct",
            "aa\nbb\ncc dd\n",
            b"3dw:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "dd"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # --- db causing unwrap (deleting across newlines backward) ---

        # db from BOL - joins with previous line
        self.run_test_screen(
            "db from BOL unwraps: screen correct",
            "foo\nbar\n",
            b"jdb:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "bar"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # 2db crossing line boundary
        self.run_test_screen(
            "2db crossing line: screen correct",
            "hello world\nfoo\n",
            b"j2db:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "foo"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # Batched dbdb crossing line boundary
        self.run_test_screen(
            "Batched dbdb crossing line: screen correct",
            "one two\nthree\n",
            b"j$dbdb:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "one e"), (1, "~")],
            expect_cursor=(0, 4),
        )

        # Batched dbdb from BOL
        self.run_test_screen(
            "Batched dbdb from BOL: screen correct",
            "foo bar\nbaz\n",
            b"jdbdb:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "baz"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # 2db single-line (no unwrap)
        self.run_test_screen(
            "2db single-line: screen correct",
            "one two three\n",
            b"$2db:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "one e")],
            expect_cursor=(0, 4),
        )

        # --- de causing unwrap (deleting to word end across newlines) ---

        # de at end of line crosses to next line
        self.run_test_screen(
            "de crossing line: screen correct",
            "foo\nbar baz\n",
            b"2lde:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "fo baz"), (1, "~")],
            expect_cursor=(0, 2),
        )

        # 2de crossing line boundary
        self.run_test_screen(
            "2de crossing line: screen correct",
            "one\ntwo three\n",
            b"2de:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, " three"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # --- cb crossing line boundary ---
        self.run_test_screen(
            "cb from BOL crosses line: screen correct",
            "foo\nbar\n",
            b"jcbbaz\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "bazbar"), (1, "~")],
            expect_cursor=(0, 2),
        )

        # --- 2cw crossing line boundary ---
        self.run_test_screen(
            "2cw crossing line: screen correct",
            "foo\nbar\n",
            b"2cwx\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "x"), (1, "~")],
            expect_cursor=(0, 0),
        )

        # --- Multi-line line-mode paste screen content ---

        # 2yy + p pastes 2 lines
        self.run_test_screen(
            "2yy + p pastes 2 lines: screen correct",
            "A\nB\nC\n",
            b"2yyp:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "A"), (1, "A"), (2, "B"), (3, "B"), (4, "C"),
            ],
            expect_cursor=(1, 0),
        )

        # 2yy + 2p pastes 2 lines twice
        self.run_test_screen(
            "2yy + 2p pastes 2 lines twice: screen correct",
            "A\nB\nC\n",
            b"2yy2p:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "A"), (1, "A"), (2, "B"), (3, "A"),
                (4, "B"), (5, "B"), (6, "C"),
            ],
            expect_cursor=(1, 0),
        )

        # dd + pp pastes deleted line twice (batched)
        self.run_test_screen(
            "dd + batched pp: screen correct",
            "A\nB\nC\n",
            b"ddpp:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "B"), (1, "A"), (2, "A"), (3, "C")],
            expect_cursor=(2, 0),
        )

        # dd + 2p pastes deleted line twice (count prefix)
        self.run_test_screen(
            "dd + 2p: screen correct",
            "A\nB\nC\n",
            b"dd2p:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "B"), (1, "A"), (2, "A"), (3, "C")],
            expect_cursor=(1, 0),
        )

        # --- ce crossing line boundary ---
        self.run_test_screen(
            "2ce crossing line: screen correct",
            "foo\nbar\n",
            b"2ceX\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "X"), (1, "~")],
            expect_cursor=(0, 0),
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

        self._group("Batch movement left/right:", leading_blank=True)

        # Batch l keys: 5 l's on "Hello World" should produce a single frame
        self.run_test_screen(
            "Render opt: batch l no-scroll is single frame",
            "Hello World\n",
            b"lllll:q!\r",
            expect_content_redraws=[True, False]
        )

        # Batch h keys: move right, then 5 h's back
        self.run_test_screen(
            "Render opt: batch h no-scroll is single frame",
            "Hello World\n",
            b"$hhhhh:q!\r",
            expect_content_redraws=[True, False, False]
        )

        # Batch l correctness: 5 l's move to col 5
        self.run_test_screen(
            "Batch l moves correct columns",
            "Hello World\n",
            b"lllll:q!\r",
            expect_cursor=(0, 5),
        )

        # Batch h correctness: $ then 3 h's from col 10 -> col 7
        self.run_test_screen(
            "Batch h moves correct columns",
            "Hello World\n",
            b"$hhh:q!\r",
            expect_cursor=(0, 7),
        )

        # Count prefix + batch l: 3l with 2 pending l's = 5 total
        self.run_test_screen(
            "Count prefix + batch l combines",
            "Hello World\n",
            b"3lll:q!\r",
            expect_cursor=(0, 5),
        )

        RIGHT = b"\x1b[C"
        LEFT = b"\x1b[D"

        # Batch insert RIGHT: 5 RIGHT arrows in insert mode
        self.run_test_screen(
            "Render opt: batch insert RIGHT is single frame",
            "Hello World\n",
            b"i" + RIGHT * 5 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Batch insert LEFT: move to end, then 5 LEFT arrows in insert mode
        self.run_test_screen(
            "Render opt: batch insert LEFT is single frame",
            "Hello World\n",
            b"$a" + LEFT * 5 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False, False]
        )

        # Batch insert RIGHT correctness
        self.run_test(
            "Batch insert RIGHT moves correct columns",
            "Hello World\n",
            b"i" + RIGHT * 5 + b"X\x1b:wq\r",
            expected_content="HelloX World\n",
        )

        # Batch insert LEFT correctness
        self.run_test(
            "Batch insert LEFT moves correct columns",
            "Hello World\n",
            b"$a" + LEFT * 5 + b"X\x1b:wq\r",
            expected_content="Hello XWorld\n",
        )

        self._group("Batch word motions (w, b, e):", leading_blank=True)

        # Batch w: 5 w's on a 7-word line -> single frame
        # Words: one(0) two(4) three(8) four(14) five(19) six(24) seven(28)
        # 5 w's from col 0 -> col 24 ("six")
        self.run_test_screen(
            "Render opt: batch w is single frame",
            "one two three four five six seven\n",
            b"wwwww:q!\r",
            expect_cursor=(0, 24),
            expect_content_redraws=[True, False]
        )

        # Batch b: $ then 5 b's -> single frame
        # $ -> col 32, 5 b's -> col 8 ("three")
        self.run_test_screen(
            "Render opt: batch b is single frame",
            "one two three four five six seven\n",
            b"$bbbbb:q!\r",
            expect_cursor=(0, 8),
            expect_content_redraws=[True, False, False]
        )

        # Batch e: 5 e's -> single frame
        # e: one(2), two(6), three(12), four(17), five(22)
        self.run_test_screen(
            "Render opt: batch e is single frame",
            "one two three four five six seven\n",
            b"eeeee:q!\r",
            expect_cursor=(0, 22),
            expect_content_redraws=[True, False]
        )

        # Count prefix + batch: 3w + 2 batched w's = 5 total
        self.run_test_screen(
            "Count prefix + batch w combines",
            "one two three four five six seven\n",
            b"3www:q!\r",
            expect_cursor=(0, 24),
            expect_content_redraws=[True, False]
        )

        # ============================================================
        # Batch combo keys (dw, yw, dd, gg, ra, etc.)
        # Two-key combos should consolidate into a single render frame
        # when both keys are available in the input buffer.
        # ============================================================
        self._group("Batch combo keys:", leading_blank=True)

        # dw: d+w batched into single frame (no pending d frame)
        # Without batching: init(T), d-pending(F), dw(T) = 3 frames
        # With batching: init(T), dw(T) = 2 frames
        self.run_test_screen(
            "Batch dw is single action frame",
            "Hello World\n",
            b"dw:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # yw: y+w batched into single frame
        # Without batching: init(T), y-pending(F), yw(F) = 3 frames
        # With batching: init(T), yw(F) = 2 frames
        self.run_test_screen(
            "Batch yw is single action frame",
            "Hello World\n",
            b"yw:q!\r",
            expect_content_redraws=[True, False]
        )

        # dd: d+d batched into single frame
        self.run_test_screen(
            "Batch dd is single action frame",
            "Hello\nWorld\n",
            b"dd:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # gg: g+g batched into single frame (cursor-only, no content redraw)
        # init(T), G(F cursor-only), g+g batched(F cursor-only), :q!(F)
        self.run_test_screen(
            "Batch gg is single action frame",
            make_lines(5),
            b"Ggg:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # ra: r+a batched into single frame
        self.run_test_screen(
            "Batch ra is single action frame",
            "Hello\n",
            b"ra:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # de: d+e batched into single frame
        self.run_test_screen(
            "Batch de is single action frame",
            "Hello World\n",
            b"de:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # ye: y+e batched into single frame
        self.run_test_screen(
            "Batch ye is single action frame",
            "Hello World\n",
            b"ye:q!\r",
            expect_content_redraws=[True, False]
        )

        # cw: c+w batched into single frame (then insert mode)
        self.run_test_screen(
            "Batch cw is single action frame",
            "Hello World\n",
            b"cw\x1b:q!\r",
            expect_content_redraws=[True, True, False, False]
        )

        # >>: >+> batched into single frame
        self.run_test_screen(
            "Batch >> is single action frame",
            "Hello\nWorld\n",
            b">>:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # <<: <+< batched into single frame
        self.run_test_screen(
            "Batch << is single action frame",
            "  Hello\n  World\n",
            b"<<:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # dwdw: both dw pairs batched via pair batching + combo batching
        # d+w consumed as first pair, d+w consumed by batch_pending_pairs
        # Result: single action frame for both deletions
        self.run_test_screen(
            "Batch dwdw is single action frame",
            "one two three four\n",
            b"dwdw:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # 3dw: count digit gets own frame, then d+w batched
        # Frame 0: init(T), Frame 1: count 3(F), Frame 2: dw(T)
        self.run_test_screen(
            "Count prefix + batch dw",
            "one two three four five\n",
            b"3dw:q!\r",
            expect_content_redraws=[True, False, True, False]
        )

        # ============================================================
        # Batch paste (p, P)
        # Repeated paste keys should consolidate into a single render
        # frame when multiple keys are available in the input buffer.
        # ============================================================
        self._group("Batch paste:", leading_blank=True)

        # Line paste pp: yank a line with dd, paste twice with pp
        # Without batching: init(T), dd(T), p(T), p(T) = 4 frames
        # With batching: init(T), dd(T), pp batched(T) = 3 frames
        self.run_test_screen(
            "Batch line pp is single action frame",
            "A\nB\nC\n",
            b"ddpp:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Line paste pp correctness: two copies pasted
        self.run_test(
            "Batch line pp pastes two copies",
            "A\nB\nC\n",
            b"ddpp:wq\r",
            expected_content="B\nA\nA\nC\n"
        )

        # Line paste PPP correctness: three copies pasted above
        self.run_test(
            "Batch line PPP pastes three copies above",
            "A\nB\n",
            b"ddPPP:wq\r",
            expected_content="A\nA\nA\nB\n"
        )

        # Line paste PP: batched into single frame
        self.run_test_screen(
            "Batch line PP is single action frame",
            "A\nB\nC\n",
            b"ddPP:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Char paste pp: yank a char with x, paste twice with pp
        # Without batching: init(T), x(T), p(T), p(T) = 4 frames
        # With batching: init(T), x(T), pp batched(T) = 3 frames
        self.run_test_screen(
            "Batch char pp is single action frame",
            "Hello\n",
            b"xpp:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Char paste pp correctness
        self.run_test(
            "Batch char pp pastes two copies",
            "Hello\n",
            b"xpp:wq\r",
            expected_content="eHHllo\n"
        )

        # Char paste PPP correctness
        self.run_test(
            "Batch char PPP pastes three copies",
            "Hello\n",
            b"xPPP:wq\r",
            expected_content="HHHello\n"
        )

        # Multi-char yank + batched PP: content must match iterative
        # yw yanks "one " (4 chars), 2G goes to blank line 2, PP pastes twice
        self.run_test(
            "Batch char PP multi-char yank content matches iterative",
            "one two three\n\n",
            b"yw2GPP:wq\r",
            expected_content="one two three\noneone  \n"
        )

        # Multi-char yank + count+extras 2PP: content must match iterative
        # yw yanks "one " (4 chars), 2G goes to blank line 2, 2PP = count 2 + 1 extra
        self.run_test(
            "Count 2PP multi-char yank content matches iterative",
            "one two three\n\n",
            b"yw2G2PP:wq\r",
            expected_content="one two three\none oneone  \n"
        )

        # Char paste PP: batched into single frame
        self.run_test_screen(
            "Batch char PP is single action frame",
            "Hello\n",
            b"xPP:q!\r",
            expect_content_redraws=[True, True, True, False]
        )

        # Count + batch: 2p then extra p should paste 3 total
        self.run_test(
            "Count 2p + extra p pastes three copies",
            "A\nB\nC\n",
            b"dd2pp:wq\r",
            expected_content="B\nA\nA\nA\nC\n"
        )

        # Cursor position tests for line paste batching
        # yy pp: cursor on row 2 (two lines pasted below, cursor on last)
        self.run_test_screen(
            "Batch line pp cursor on last pasted line",
            "A\nB\nC\n",
            b"yypp:q!\r",
            expect_cursor=(2, 0),
        )

        # yy 2p: cursor on row 1 (counted paste, cursor on first pasted line)
        self.run_test_screen(
            "Count line 2p cursor on first pasted line",
            "A\nB\nC\n",
            b"yy2p:q!\r",
            expect_cursor=(1, 0),
        )

        # yy ppp: cursor on row 3
        self.run_test_screen(
            "Batch line ppp cursor on last pasted line",
            "A\nB\nC\n",
            b"yyppp:q!\r",
            expect_cursor=(3, 0),
        )

        # yy 2pp: cursor on row 2 (count 2 + 1 extra = 3 pastes, cursor at 1 + extras)
        self.run_test_screen(
            "Count 2p + batch p cursor position",
            "A\nB\nC\n",
            b"yy2pp:q!\r",
            expect_cursor=(2, 0),
        )

        # Line paste above: yy PP -> cursor on row 0
        self.run_test_screen(
            "Batch line PP cursor stays at row 0",
            "A\nB\nC\n",
            b"yyPP:q!\r",
            expect_cursor=(0, 0),
        )

        # Line paste above: yy 2P -> cursor on row 0 (no adjustment needed)
        self.run_test_screen(
            "Count line 2P cursor stays at row 0",
            "A\nB\nC\n",
            b"yy2P:q!\r",
            expect_cursor=(0, 0),
        )

        # Char paste below: x pp -> cursor at col 2
        self.run_test_screen(
            "Batch char pp cursor position",
            "Hello\n",
            b"xpp:q!\r",
            expect_cursor=(0, 2),
        )

        # Char paste below: x 2p -> cursor at col 2 (same as pp)
        self.run_test_screen(
            "Count char 2p cursor position",
            "Hello\n",
            b"x2p:q!\r",
            expect_cursor=(0, 2),
        )

        # Char paste above: lx PP -> cursor at col 1 (adjusted back by 1)
        self.run_test_screen(
            "Batch char PP cursor adjusted",
            "Hello\n",
            b"lxPP:q!\r",
            expect_cursor=(0, 1),
        )

        # Char paste above: lx 2P -> cursor at col 2 (counted, no adjustment)
        self.run_test_screen(
            "Count char 2P cursor not adjusted",
            "Hello\n",
            b"lx2P:q!\r",
            expect_cursor=(0, 2),
        )

        self._group("Batch page down/up:", leading_blank=True)

        # Render optimization: batch Ctrl-F reduces redraws
        # Without batching: 3 Ctrl-F's -> frames [init, pgdn, pgdn, pgdn] = 4
        # With batching: frames [init, pgdn+batch] = 2 frames
        # Then j triggers a cursor-only frame (False) proving batch happened
        self.run_test_screen(
            "Render opt: batch Ctrl-F reduces redraws",
            make_lines(30),
            CTRL_F * 3 + b"j:q!\r",
            expect_content_redraws=[True, True, False],
        )

        # Render optimization: batch Ctrl-B reduces redraws
        # G scrolls to end (full repaint), then 3 batched Ctrl-B's
        # produce a single repaint, then j is cursor-only
        self.run_test_screen(
            "Render opt: batch Ctrl-B reduces redraws",
            make_lines(30),
            b"G" + CTRL_B * 3 + b"j:q!\r",
            expect_content_redraws=[True, True, True, False],
        )

        # Batch Ctrl-F correctness: 3 pages down on 30-line file
        # page_size=9, lines 0->9->18->27, VIEW_TOP clamped to 21
        self.run_test_screen(
            "Batch Ctrl-F moves correct number of pages",
            make_lines(30),
            CTRL_F * 3 + b":q!\r",
            expect_cursor=(6, 0),
            expect_lines=[(i, f"Line {i+22}") for i in range(9)]
        )

        # Batch Ctrl-B correctness: go to end then 2 pages up
        # G puts cursor on line 29, VIEW_TOP=21.
        # 2 page-ups: line 29->20->11, VIEW_TOP 21->12->3
        self.run_test_screen(
            "Batch Ctrl-B moves correct number of pages",
            make_lines(30),
            b"G" + CTRL_B * 2 + b":q!\r",
            expect_cursor=(8, 0),
            expect_lines=[(i, f"Line {i+4}") for i in range(9)]
        )

        # Batch PgDn key: same result as batch Ctrl-F
        PGDN = b"\x1b[6~"
        self.run_test_screen(
            "Render opt: batch PgDn reduces redraws",
            make_lines(30),
            PGDN * 3 + b"j:q!\r",
            expect_content_redraws=[True, True, False],
        )

        # Count prefix + batch Ctrl-F: 2Ctrl-F + 1 pending = 3 pages
        self.run_test_screen(
            "Count prefix + batch Ctrl-F combines",
            make_lines(30),
            b"2" + CTRL_F * 2 + b":q!\r",
            expect_cursor=(6, 0),
            expect_lines=[(i, f"Line {i+22}") for i in range(9)]
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
        # i enters insert (F), then 5 batched DOWN arrows no-scroll (F), ESC (F)
        self.run_test_screen(
            "Render opt: batch insert down no-scroll",
            make_lines(10),
            b"i" + DOWN * 5 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, False, False]
        )

        # Render optimization: batch insert down arrows with scroll
        # 15-line file, 10 rows. i(F), then 11 DOWN arrows batch into one
        # scroll repaint(T), ESC(F). Without batching: each DOWN is a
        # separate frame, first 8 are no-scroll(F) then 3 scroll(T).
        self.run_test_screen(
            "Render opt: batch insert down scroll is single repaint",
            make_lines(15),
            b"i" + DOWN * 11 + b"\x1b:q!\r",
            expect_content_redraws=[True, False, True, False]
        )

        # Render optimization: batch insert up arrows with scroll
        # G(T) scrolls to bottom, i(F), 12 UP arrows batch into one
        # scroll repaint(T), ESC(F). Without batching: each UP is a
        # separate frame, first ~5 are no-scroll(F) then rest scroll(T).
        self.run_test_screen(
            "Render opt: batch insert up scroll is single repaint",
            make_lines(15),
            b"Gi" + UP * 12 + b"\x1b:q!\r",
            expect_content_redraws=[True, True, False, True, False]
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

        # --- Snapshot detection baseline tests ---
        # These verify current render behavior to protect against regressions
        # when switching to snapshot-based render detection.

        # Replace char (ra) triggers content redraw on current row
        # Frame 0: init(T), Frame 1: r+a batched replaces(T)
        self.run_test_screen(
            "Render opt: ra triggers current row redraw",
            "Hello\nWorld\n",
            b"ra:q!\r",
            expect_content_redraws=[True, True, False],
            expect_content_rows=[(1, {0})]
        )

        # Toggle case (~) triggers content redraw on current row
        self.run_test_screen(
            "Render opt: ~ triggers current row redraw",
            "Hello\nWorld\n",
            b"~:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0})]
        )

        # Multi-line indent (2>>) triggers full content redraw
        # Frame 0: init(T), Frame 1: 2(F count), Frame 2: >+> batched indent(T)
        self.run_test_screen(
            "Render opt: 2>> triggers full redraw",
            "Hello\nWorld\nThird\n",
            b"2>>:q!\r",
            expect_content_redraws=[True, False, True, False]
        )

        # dd triggers full content redraw
        # Frame 0: init(T), Frame 1: d+d batched dd(T)
        self.run_test_screen(
            "Render opt: dd triggers full redraw",
            "Hello\nWorld\n",
            b"dd:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # x triggers content redraw on current row
        self.run_test_screen(
            "Render opt: x triggers current row redraw",
            "Hello\nWorld\n",
            b"x:q!\r",
            expect_content_redraws=[True, True],
            expect_content_rows=[(1, {0})]
        )

        # Movement without scroll (l) does NOT trigger content redraw
        self.run_test_screen(
            "Render opt: l no content redraw",
            "Hello\n",
            b"l:q!\r",
            expect_content_redraws=[True, False]
        )

        # ESC with no pending count does NOT trigger content redraw
        self.run_test_screen(
            "Render opt: ESC no content redraw",
            "Hello\n",
            b"\x1b:q!\r",
            expect_content_redraws=[True, False]
        )

        # o (open below) triggers full content redraw
        self.run_test_screen(
            "Render opt: o triggers full redraw",
            "Hello\nWorld\n",
            b"o\x1b:q!\r",
            expect_content_redraws=[True, True, False]
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

        # Combo key batching: the pending-key frame is skipped when the
        # second key is already available.  The pending key display is only
        # visible when typing slowly (second key not yet in buffer).

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

        # 3d: count frame still shows (count digits not batched)
        self.run_test_screen(
            "3d shows count before batched combo",
            make_lines(5),
            b"3dd:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
            ]
        )

        # 3y: count frame still shows (count digits not batched)
        self.run_test_screen(
            "3y shows count before batched combo",
            make_lines(5),
            b"3yy:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, " - 3 - "),
            ]
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

        # After ma, pending key clears (m+a batched when keys available)
        self.run_test_screen(
            "ma clears pending key from status",
            make_lines(3),
            b"ma:q!\r",
            cols=80,
            expect_status_contains="COMMAND - 1,",
        )

        # After 'a with mark set, pending key clears ('+a batched)
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
        # d+1 batched: frame 1 shows reset state (no pending, no count)
        self.run_test_screen(
            "d1 resets state (no count started)",
            make_lines(3),
            b"d1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, "NORMAL - 1,"),  # After d+1 batched, state fully reset
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
        # g+1 batched: frame 1 shows reset state
        self.run_test_screen(
            "g1 resets state (no count started)",
            make_lines(3),
            b"g1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, "NORMAL - 1,"),
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
        # y+1 batched: frame 1 shows reset state
        self.run_test_screen(
            "y1 resets state (no count started)",
            make_lines(3),
            b"y1:q!\r",
            cols=80,
            expect_status_at_frame=[
                (1, "NORMAL - 1,"),
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

        # Batched dd pairs
        self.run_test(
            "dddd batches to delete 2 lines",
            "A\nB\nC\nD\n",
            b"dddd:wq\r",
            expected_content="C\nD\n"
        )

        self.run_test(
            "dddddd batches to delete 3 lines",
            "A\nB\nC\nD\nE\nF\n",
            b"dddddd:wq\r",
            expected_content="D\nE\nF\n"
        )

        self.run_test(
            "3dddd batches count 3 plus 1 extra pair",
            "A\nB\nC\nD\nE\nF\n",
            b"3dddd:wq\r",
            expected_content="E\nF\n"
        )

        self.run_test(
            "dddw partial pair restores pending d then w completes dw",
            "first\nhello world\n",
            b"dddw:wq\r",
            expected_content="world\n"
        )

        # Batched dd yank: only last line should be in yank buffer
        self.run_test(
            "dddd+p yanks only last deleted line",
            "A\nB\nC\n",
            b"ddddp:wq\r",
            expected_content="C\nB\n"
        )

        self.run_test(
            "dddddd+p yanks only last deleted line",
            "A\nB\nC\nD\n",
            b"ddddddp:wq\r",
            expected_content="D\nC\n"
        )

        self.run_test(
            "3dddd+p yanks only last deleted line (not 4)",
            "A\nB\nC\nD\nE\n",
            b"3ddddp:wq\r",
            expected_content="E\nD\n"
        )

        # Non-batched: 3dd still yanks all 3 lines
        self.run_test(
            "3dd+p still pastes all 3 lines (no batching)",
            "A\nB\nC\nD\n",
            b"3ddp:wq\r",
            expected_content="D\nA\nB\nC\n"
        )

        # Batched dd cursor position: should end on correct line
        self.run_test_screen(
            "dddd batched cursor on correct line",
            "A\nB\nC\nD\n",
            b"dddd:q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(0, "C")],
        )

        # Batched dd at end of file: cursor clamps to last line
        self.run_test(
            "dddd batched at EOF clamps correctly",
            "A\nB\n",
            b"dddd:wq\r",
            expected_content="\n"
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

        # D then p pastes deleted text (char paste inserts inline)
        self.run_test(
            "D then p pastes deleted text",
            "Hello World\n",
            b"lllllD0p:wq\r",
            expected_content="H Worldello\n",
        )

        # d$ at col 0 deletes line content (same as D)
        self.run_test(
            "d$ at col 0 deletes line content",
            "Hello\n",
            b"d$:wq\r",
            expected_content="\n"
        )

        # d$ at col 2 deletes to end
        self.run_test(
            "d$ at col 2 deletes to end",
            "Hello\n",
            b"lld$:wq\r",
            expected_content="He\n"
        )

        # d$ on empty line does nothing
        self.run_test(
            "d$ on empty line does nothing",
            "\n",
            b"d$:wq\r",
            expected_content="\n"
        )

        # d$ at last char deletes single char
        self.run_test(
            "d$ at last char deletes just that char",
            "ABC\n",
            b"lld$:wq\r",
            expected_content="AB\n"
        )

        # 2D deletes cursor-to-EOL plus next complete line
        self.run_test(
            "2D deletes to EOL + 1 line below",
            "Hello\nWorld\nFoo\n",
            b"ll2D:wq\r",
            expected_content="He\nFoo\n"
        )

        # 2d$ synonym for 2D
        self.run_test(
            "2d$ synonym for 2D",
            "Hello\nWorld\nFoo\n",
            b"ll2d$:wq\r",
            expected_content="He\nFoo\n"
        )

        # 3d$ on 4 lines at col 0: deletes 3 full lines content + newlines
        self.run_test(
            "3d$ deletes from cursor across 3 lines",
            "ab\ncd\nef\ngh\n",
            b"3d$:wq\r",
            expected_content="\ngh\n"
        )

        # Count exceeds available lines - clamps
        self.run_test(
            "5d$ clamps to available lines",
            "Hello\nWorld\n",
            b"ll5d$:wq\r",
            expected_content="He\n"
        )

        # 2D then p: charwise paste of deleted content
        # 2D at col 2 deletes "llo\nWorld", cursor clamps to col 1 ('e')
        # p pastes "llo\nWorld" after 'e', restoring original
        self.run_test(
            "2D then p pastes charwise multi-line",
            "Hello\nWorld\nFoo\n",
            b"ll2Dp:wq\r",
            expected_content="Hello\nWorld\nFoo\n"
        )

        # C then p pastes deleted text (char paste inserts inline)
        self.run_test(
            "C then p pastes deleted text",
            "Hello World\n",
            b"lllllCX\x1b0p:wq\r",
            expected_content="H WorldelloX\n",
        )

        # dw then p pastes deleted word
        self.run_test(
            "dw then p pastes deleted word",
            "foo bar baz\n",
            b"dw$p:wq\r",
            expected_content="bar bazfoo \n",
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

        # Batched yy pairs: only last yy's count matters (implicit 1)
        self.run_test(
            "yyyy+p yanks only 1 line (last yy overwrites)",
            "A\nB\nC\n",
            b"yyyyp:wq\r",
            expected_content="A\nA\nB\nC\n"
        )

        self.run_test(
            "yyyyyy+p yanks only 1 line (last yy overwrites)",
            "A\nB\nC\nD\n",
            b"yyyyyyp:wq\r",
            expected_content="A\nA\nB\nC\nD\n"
        )

        # Non-batched: 2yy still yanks 2 lines
        self.run_test(
            "2yy+p still pastes 2 lines (no batching)",
            "A\nB\nC\n",
            b"2yyp:wq\r",
            expected_content="A\nA\nB\nB\nC\n"
        )

        # yy+p on line longer than 255 chars (tests page-crossing in newline scan)
        long_line = "A" * 300
        self.run_test(
            "yy+p with 300-char line (page crossing)",
            long_line + "\nB\nC\n",
            b"yyp:wq\r",
            expected_content=long_line + "\n" + long_line + "\nB\nC\n"
        )

        # yy+p below 255-char line (tests INY wrap past newline at Y=255)
        line_255 = "B" * 255
        self.run_test(
            "yy paste below 255-char line (INY page wrap)",
            "X\n" + line_255 + "\nC\n",
            b"yyjp:wq\r",
            expected_content="X\n" + line_255 + "\nX\nC\n"
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

        # Multi-line paste cursor position: cursor at first pasted char
        self.run_test_screen(
            "p with multi-line yank: cursor at first pasted char",
            "foo\nbar\n",
            b"jdb0p:q!\r",
            expect_cursor=(0, 1),
        )

        self.run_test_screen(
            "P with multi-line yank: cursor at first pasted char",
            "foo\nbar\n",
            b"jdb0P:q!\r",
            expect_cursor=(0, 0),
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

        # Count + batch x: 2x + batched xx = 4 chars deleted, yank last
        self.run_test(
            "2x + batched xx yanks last char",
            "ABCDE\n",
            b"2xxx$p:wq\r",
            expected_content="ED\n"
        )

        # Batched x from middle of line
        self.run_test(
            "batched xx from col 2 yanks last char",
            "ABCDE\n",
            b"llxxp:wq\r",
            expected_content="ABED\n"
        )

        # D on first col yanks entire line content
        self.run_test(
            "D from col 0 yanks whole line",
            "HELLO\nWORLD\n",
            b"Djp:wq\r",
            expected_content="\nWHELLOORLD\n"
        )

        # Multi-line char paste: db yanks content with newline, P restores it
        self.run_test(
            "db cross-line yank + P round-trips content",
            "foo\nbar\n",
            b"jdb0P:wq\r",
            expected_content="foo\nbar\n",
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

        # / finds match later on SAME line (after cursor)
        self.run_test_screen(
            "/ finds match on same line after cursor",
            "AA BB AA\n",
            b"/AA\r:q!\r",
            expect_cursor=(0, 6),  # cursor starts at col 0, finds AA at col 6
        )

        # n advances to next match on same line
        self.run_test_screen(
            "n finds next match on same line",
            "AA BB AA CC AA\n",
            b"/AA\rn:q!\r",
            expect_cursor=(0, 12),  # / finds col 6, n finds col 12
        )

        # n wraps from last match on line to next line
        self.run_test_screen(
            "n wraps from last same-line match to next line",
            "AA BB AA\nCC AA DD\n",
            b"/AA\rn:q!\r",
            expect_cursor=(1, 3),  # / finds (0,6), n finds (1,3)
        )

        # / wraps around file back to same line col 0
        self.run_test_screen(
            "/ wraps around to match at start of current line",
            "AA BB\n",
            b"ll/AA\r:q!\r",
            expect_cursor=(0, 0),  # cursor at col 2, wraps to find AA at col 0
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

        # 257p: mark adjustment must use 16-bit count
        # yy yanks 1 line, 257p inserts 257 lines below line 0.
        # Mark at line 1 should shift to 1+257=258.
        # Bug: low byte of 257 ($0101) is 1, so mark shifts by 1 only -> line 2.
        self.run_test(
            "257p mark adjustment uses 16-bit count",
            "A\nB\n",
            b"jmagg" +          # mark B (line 1), go to line 0
            b"yy257p" +         # yank A, paste 257 copies below line 0
            b"'add:wq\r",       # go to mark, delete that line, save
            expected_content="A\n" * 258  # 1 original + 257 copies, B deleted
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

        # --- Mark adjustment: batched insert mode ---
        # Verify marks are correctly adjusted by the unified insert_batch
        # handler regardless of how keystrokes are batched together.

        # Batch Enter×2 above mark -> mark shifts by 2
        # (sequential composition of inserts is additive)
        self.run_test_screen(
            "Batch Enter×2 above mark shifts mark +2",
            make_lines(5),
            b"jjjmagg A\r\r\x1b'a:q!\r",  # mark line4, gg, A+Enter+Enter+ESC, 'a
            expect_cursor=(5, 0),  # was idx 3, +2 newlines -> idx 5
        )

        # Batch BS×2 crossing 2 newlines above mark -> mark shifts by -2
        # Content has consecutive empty lines so 2 backward bytes are both \n.
        # (sequential composition of deletes at same anchor is additive)
        self.run_test_screen(
            "Batch BS×2 join above mark shifts mark -2",
            "A\n\n\nB\nC\n",
            b"jjjmaki\x08\x08\x1b'a:q!\r",  # mark "B" (idx3), k->line2, BS×2
            expect_cursor=(1, 0),  # was idx 3, -2 newlines -> idx 1
        )

        # DEL across newline above mark -> mark shifts
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "DEL across newline above mark shifts mark",
            make_lines(5),
            b"jjjjmagg A" + DEL + b"\x1b'a:q!\r",  # mark line5, gg, A(end)+DEL
            expect_cursor=(3, 0),  # was idx 4, DEL removed 1 newline -> idx 3
        )

        # Mixed: Enter then BS cancels within batch -> mark unchanged
        # BS cancels the Enter during collection, so no newlines are
        # actually inserted or deleted -> marks unaffected
        self.run_test_screen(
            "Enter+BS cancel in batch leaves mark unchanged",
            make_lines(5),
            b"jjmagg i\r\x08\x1b'a:q!\r",  # mark line3, gg, Enter+BS cancel
            expect_cursor=(2, 0),  # mark still at idx 2
        )

        # Mixed: BS join + Enter re-split -> mark survives round-trip
        # BS deletes newline (joining lines), Enter re-inserts one.
        # delete(1,1) then insert(1,1) is identity for marks.
        self.run_test_screen(
            "BS join + Enter re-split preserves mark",
            make_lines(5),
            b"jjjjmagg ji\x08\r\x1b'a:q!\r",  # mark line5, j->line2, BS+Enter
            expect_cursor=(4, 0),  # mark still at idx 4
        )

        # DEL across newline + typing in batch -> mark below shifts
        DEL = b"\x1b[3~"
        self.run_test_screen(
            "DEL+typing across newline shifts mark below",
            make_lines(5),
            b"jjjmagg A" + DEL + b"XY\x1b'a:q!\r",  # mark line4, gg, A+DEL+XY
            expect_cursor=(2, 0),  # was idx 3, -1 newline -> idx 2
        )

        # BS + typing across newline -> mark below shifts
        self.run_test_screen(
            "BS+typing across newline shifts mark below",
            make_lines(5),
            b"jjjjmagg ji\x08XY\x1b'a:q!\r",  # mark line5, j->line2, BS+XY
            expect_cursor=(3, 0),  # was idx 4, -1 newline -> idx 3
        )

        # --- Mark adjustment: char delete across newlines (db) ---

        # db across newline: mark on line below shifts up
        self.run_test_screen(
            "db across newline shifts mark below",
            "AB\nCD\nEF\nGH\n",
            b"jjjmakkdb'a:q!\r",  # mark "GH" (idx3), kk->line1 col0, db
            expect_cursor=(2, 0),  # was idx 3, 1 newline deleted -> idx 2
        )

        # 2db across 2 newlines: mark shifts by 2
        self.run_test_screen(
            "2db across 2 newlines shifts mark by 2",
            "A\nB\nC\nD\nE\n",
            b"jjjjmakk2db'a:q!\r",  # mark "E" (idx4), kk->line2, 2db crosses 2 NLs
            expect_cursor=(2, 0),  # was idx 4, 2 newlines deleted -> idx 2
        )

        # de across newline: mark on consumed line is unset (col > 0)
        self.run_test_screen(
            "de across newline unsets mark on consumed line",
            "AB\nCD\nEF\n",
            b"jmagg$de'a :q!\r",  # mark "CD" (idx1), gg, $->B, de crosses NL
            expect_cursor=(0, 0),  # mark at idx1 unset (in [1,2)), space dismisses
        )

        # db from col0: mark on cursor line shifts correctly
        # db from (1,0): deletes "AB\n", cursor at (0,0). Col=0 so first_line=0.
        # Mark at idx 1 is in [0,1) -> unset (idx 1 IS the cursor line content)
        # Wait: [0, 0+1) = [0, 1). Mark at 1: NOT in range. Shifted by 1 to 0.
        self.run_test_screen(
            "db col0 shifts mark on next line",
            "AB\nCD\nEF\n",
            b"jjmakdb'a:q!\r",  # mark "EF" (idx2), k->line1, db from col0
            expect_cursor=(1, 0),  # first_line=0 (col0), [0,1): mark at 2 shifted to 1
        )

        # 2db from col0: verify content is correct
        self.run_test(
            "2db from col0 deletes 2 words backward",
            "A\nB\nC\nD\nE\n",
            b"jjj2db:wq\r",  # line3, 2db
            expected_content="A\nD\nE\n",
        )

        # 2db from col0: mark past deletion shifts correctly
        self.run_test_screen(
            "2db from col0 shifts mark past deletion",
            "A\nB\nC\nD\nE\n",
            b"jjjjmak2db'a:q!\r",  # mark "E" (idx4), k->line3, 2db deletes B\nC\n
            expect_cursor=(2, 0),  # mark at 4 shifted by -2 to 2 ("E")
        )

        # 2db from col0: mark on consumed line is unset
        # After 2db: "A\nD\nE\n", cursor at line 1. Mark 'a' was line 2 (in [1,3)) -> unset.
        # 'a fails -> cursor stays at (1,0). If mark were valid at 2, cursor would go to (2,0).
        self.run_test_screen(
            "2db from col0 unsets mark on consumed line",
            "A\nB\nC\nD\nE\n",
            b"jjmaj2db'a:q!\r",  # mark "C" (idx2), j->line3, 2db deletes B\nC\n
            expect_cursor=(1, 0),  # mark unset, cursor stays at line 1
        )

        # --- Mark adjustment: char paste with newlines ---

        # Char paste below (p) with multiline content: mark shifts up
        # de across newline yanks "B\nCD", then p pastes it back.
        # After de: "A\nEF\n" (2 lines), mark shifted from 2 to 1.
        # After p: "AB\nCD\nEF\n" (3 lines), delta=1, mark at 1 shifts to 2.
        self.run_test_screen(
            "char paste below shifts mark on line below",
            "AB\nCD\nEF\n",
            b"jjma" +           # mark "EF" (idx 2)
            b"gg$de" +          # go to 'B', de yanks "B\nCD" (1 newline)
            b"p" +              # paste below: inserts "B\nCD" after 'A'
            b"'a:q!\r",
            expect_cursor=(2, 0),  # was 1 after de, +1 from paste newline -> 2
        )

        # Char paste above (P) with multiline content: mark shifts up
        # Same sequence but P instead of p. Col=0 so at_line=FILE_LINE16.
        self.run_test_screen(
            "char paste above shifts mark on line below",
            "AB\nCD\nEF\n",
            b"jjma" +           # mark "EF" (idx 2)
            b"gg$de" +          # go to 'B', de yanks "B\nCD" (1 newline)
            b"P" +              # paste above: inserts "B\nCD" at cursor
            b"'a:q!\r",
            expect_cursor=(2, 0),  # was 1 after de, +1 from paste newline -> 2
        )

        # --- Mark adjustment: undo/redo of multiline char delete ---

        # Undo of multiline char delete (db): mark shifts back up
        self.run_test_screen(
            "undo multiline char delete shifts mark back",
            "AB\nCD\nEF\n",
            b"jjma" +           # mark "EF" (idx 2)
            b"kdb" +            # line 1 col0, db deletes "AB\n" -> mark shifts to 1
            b"u" +              # undo: pastes "AB\n" back -> mark shifts to 2
            b"'a:q!\r",
            expect_cursor=(2, 0),  # mark restored to original idx 2
        )

        # Redo of multiline char delete: mark shifts down (via delete_at_cursor)
        self.run_test_screen(
            "redo multiline char delete shifts mark down",
            "AB\nCD\nEF\n",
            b"jjma" +           # mark "EF" (idx 2)
            b"kdb" +            # db deletes "AB\n" -> mark shifts to 1
            b"u u" +            # undo then redo: mark should be back at 1
            b"'a:q!\r",
            expect_cursor=(1, 0),  # mark shifted down by redo
        )

        # Mark below 2d$ range gets adjusted
        # Set mark on line 2 (ccc), go to line 0, 2d$ deletes "aaa\nbbb"
        # ccc was line 2, becomes line 1 after 1 newline removed
        self.run_test_screen(
            "2d$ adjusts mark below range",
            "aaa\nbbb\nccc\nddd\n",
            b"2jmakk2d$'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(1, 0),
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

        self._group("Range indent/unindent (:>, :<):", leading_blank=True)

        # Range indent
        self.run_test(
            ":1,3> indents lines 1-3",
            "aaa\nbbb\nccc\nddd\n",
            b":1,3>\r:wq\r",
            expected_content="  aaa\n  bbb\n  ccc\nddd\n",
        )

        # Range unindent
        self.run_test(
            ":1,3< unindents lines 1-3",
            "  aaa\n  bbb\n  ccc\nddd\n",
            b":1,3<\r:wq\r",
            expected_content="aaa\nbbb\nccc\nddd\n",
        )

        # Bare :> indents current line
        self.run_test(
            ":> indents current line",
            "hello\nworld\n",
            b":>\r:wq\r",
            expected_content="  hello\nworld\n",
        )

        # Bare :< unindents current line
        self.run_test(
            ":< unindents current line",
            "  hello\nworld\n",
            b":<\r:wq\r",
            expected_content="hello\nworld\n",
        )

        # Single-position :.> indents current line (cursor on line 2)
        self.run_test(
            ":.> indents current line",
            "hello\nworld\n",
            b"j:.>\r:wq\r",
            expected_content="hello\n  world\n",
        )

        # Single-position :2> indents line 2
        self.run_test(
            ":2> indents line 2",
            "aaa\nbbb\nccc\n",
            b":2>\r:wq\r",
            expected_content="aaa\n  bbb\nccc\n",
        )

        # Mark range indent
        self.run_test(
            ":'a,.> indents from mark to current",
            "aaa\nbbb\nccc\nddd\n",
            b"majj:'a,.>\r:wq\r",
            expected_content="  aaa\n  bbb\n  ccc\nddd\n",
        )

        # Mark range unindent
        self.run_test(
            ":'a,.< unindents from mark to current",
            "  aaa\n  bbb\n  ccc\nddd\n",
            b"majj:'a,.<\r:wq\r",
            expected_content="aaa\nbbb\nccc\nddd\n",
        )

        # Empty line handling
        self.run_test(
            ":> range skips empty lines",
            "aaa\n\nbbb\n",
            b":1,3>\r:wq\r",
            expected_content="  aaa\n\n  bbb\n",
        )

        # Single-position :5d works (bonus from single-position support)
        self.run_test(
            ":5d deletes line 5 (single-position command)",
            make_lines(6),
            b":5d\r:wq\r",
            expected_content="Line 1\nLine 2\nLine 3\nLine 4\nLine 6\n",
        )

        # :5 still works as goto (regression)
        self.run_test_screen(
            ":5 still works as goto after shift support",
            make_lines(10),
            b":5\r:q!\r",
            expect_cursor=(4, 0),
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

        self._group("Screen state - tab and control char display:", leading_blank=True)

        # Tab displayed as reverse >
        self.run_test_screen(
            "Tab displayed as reverse >",
            None,
            b":q!\r",
            initial_bytes=b"A\tB\n",
            expect_lines=[(0, "A>B")],
            expect_reverse_at=[
                (0, 0, False),
                (0, 1, True),
                (0, 2, False),
            ]
        )

        # Control char displayed as reverse ?
        self.run_test_screen(
            "Control char displayed as reverse ?",
            None,
            b":q!\r",
            initial_bytes=b"A\x01B\n",
            expect_lines=[(0, "A?B")],
            expect_reverse_at=[
                (0, 0, False),
                (0, 1, True),
                (0, 2, False),
            ]
        )

        # Tab inserted via insert mode
        self.run_test_screen(
            "Tab key inserts tab in insert mode",
            "AB\n",
            b"i\tC\x1b:q!\r",
            expect_lines=[(0, ">CAB")],
            expect_reverse_at=[
                (0, 0, True),
                (0, 1, False),
            ]
        )

        # Multiple tabs and control chars
        self.run_test_screen(
            "Multiple tabs and control chars",
            None,
            b":q!\r",
            initial_bytes=b"\t\x02\t\n",
            expect_lines=[(0, ">?>")],
            expect_reverse_at=[
                (0, 0, True),
                (0, 1, True),
                (0, 2, True),
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
            "b at col 0 goes to start of last word on previous line",
            "foo\nbar\n",
            b"jb:q!\r",
            expect_cursor=(0, 0),
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

        self.run_test_screen(
            "b from BOL to multi-word prev line",
            "one two\nthree\n",
            b"jb:q!\r",
            expect_cursor=(0, 4),
        )

        self.run_test_screen(
            "2b crossing line boundary",
            "hello\nworld\n",
            b"j2b:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "w then b returns to origin",
            "hello\nworld\n",
            b"wb:q!\r",
            expect_cursor=(0, 0),
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

        self._group("Toggle case (~):", leading_blank=True)

        self.run_test(
            "~ toggles lowercase to uppercase",
            "hello\n",
            b"~:wq\r",
            expected_content="Hello\n"
        )

        self.run_test(
            "~ toggles uppercase to lowercase",
            "HELLO\n",
            b"~:wq\r",
            expected_content="hELLO\n"
        )

        self.run_test(
            "~ on non-alpha advances cursor",
            "1abc\n",
            b"~~:wq\r",
            expected_content="1Abc\n"
        )

        self.run_test(
            "3~ toggles 3 chars",
            "hello\n",
            b"3~:wq\r",
            expected_content="HELlo\n"
        )

        self.run_test(
            "~ on empty line does nothing",
            "\n",
            b"~:q!\r",
            expect_unmodified=True
        )

        # Batched ~ (rapid ~~~ toggles 3 chars)
        self.run_test(
            "~~~ batched toggles 3 chars",
            "hello\n",
            b"~~~:wq\r",
            expected_content="HELlo\n"
        )

        # Batched ~ matches count prefix
        self.run_test(
            "~~~ batched matches 3~ result",
            "hello\n",
            b"3~:wq\r",
            expected_content="HELlo\n"
        )

        # Batched ~ cursor position
        self.run_test_screen(
            "~~~ batched cursor at col 3",
            "hello\n",
            b"~~~:q!\r",
            expect_cursor=(0, 3),
        )

        # Count + batch combination
        self.run_test(
            "2~ + batched ~ toggles 3 chars",
            "hello\n",
            b"2~~:wq\r",
            expected_content="HELlo\n"
        )

        # Batched ~ at end of line stops at last char
        self.run_test(
            "~~~~~ batched on 3-char line toggles all",
            "abc\n",
            b"~~~~~:wq\r",
            expected_content="ABC\n"
        )

        # Render: batched ~ is single action frame
        self.run_test_screen(
            "Batch ~~~ is single action frame",
            "hello\n",
            b"~~~:q!\r",
            expect_content_redraws=[True, True, False]
        )

        self._group("Join lines (J):", leading_blank=True)

        self.run_test(
            "J joins two lines with space",
            "foo\nbar\n",
            b"J:wq\r",
            expected_content="foo bar\n"
        )

        self.run_test(
            "3J joins 3 lines",
            "one\ntwo\nthree\nfour\n",
            b"3J:wq\r",
            expected_content="one two three\nfour\n"
        )

        self.run_test(
            "J on last line does nothing",
            "only\n",
            b"J:q!\r",
            expect_unmodified=True
        )

        # Batched J (rapid JJ joins 2 lines)
        self.run_test(
            "JJ batched joins 2 lines",
            "aaa\nbbb\nccc\nddd\n",
            b"JJ:wq\r",
            expected_content="aaa bbb ccc\nddd\n"
        )

        # Batched JJ matches 3J result (3J joins current + 2 more)
        self.run_test(
            "JJ batched matches 3J result",
            "aaa\nbbb\nccc\nddd\n",
            b"3J:wq\r",
            expected_content="aaa bbb ccc\nddd\n"
        )

        # Triple batched J
        self.run_test(
            "JJJ batched joins 3 lines",
            "aaa\nbbb\nccc\nddd\neee\n",
            b"JJJ:wq\r",
            expected_content="aaa bbb ccc ddd\neee\n"
        )

        # Count + batch combination: 2J = 1 join, + batched J = 1 more join = 2 total
        self.run_test(
            "2J + batched J joins 3 lines into one",
            "aaa\nbbb\nccc\nddd\n",
            b"2JJ:wq\r",
            expected_content="aaa bbb ccc\nddd\n"
        )

        # Batched J at end of file stops gracefully
        self.run_test(
            "JJJ batched on 3-line file joins all",
            "aaa\nbbb\nccc\n",
            b"JJJ:wq\r",
            expected_content="aaa bbb ccc\n"
        )

        # Render: batched JJ is single action frame
        self.run_test_screen(
            "Batch JJ is single action frame",
            "aaa\nbbb\nccc\n",
            b"JJ:q!\r",
            expect_content_redraws=[True, True, False]
        )

        self._group("Replace char (r):", leading_blank=True)

        self.run_test(
            "rx replaces char at cursor",
            "hello\n",
            b"rx:wq\r",
            expected_content="xello\n"
        )

        self.run_test(
            "3rx replaces 3 chars",
            "hello\n",
            b"3rx:wq\r",
            expected_content="xxxlo\n"
        )

        self.run_test(
            "r on empty line does nothing",
            "\n",
            b"rx:q!\r",
            expect_unmodified=True
        )

        self._group("Substitute char (s):", leading_blank=True)

        self.run_test(
            "s deletes char and enters insert",
            "hello\n",
            b"sX\x1b:wq\r",
            expected_content="Xello\n"
        )

        self.run_test(
            "2s deletes 2 chars and enters insert",
            "hello\n",
            b"2sXY\x1b:wq\r",
            expected_content="XYllo\n"
        )

        self.run_test(
            "s on empty line enters insert",
            "\n",
            b"sX\x1b:wq\r",
            expected_content="X\n"
        )

        self._group("Change to EOL (C):", leading_blank=True)

        self.run_test(
            "C at start deletes all and inserts",
            "hello\n",
            b"CXY\x1b:wq\r",
            expected_content="XY\n"
        )

        self.run_test(
            "C at middle deletes to EOL and inserts",
            "hello\n",
            b"llCXY\x1b:wq\r",
            expected_content="heXY\n"
        )

        self.run_test(
            "C on empty line enters insert",
            "\n",
            b"CX\x1b:wq\r",
            expected_content="X\n"
        )

        # Counted C: 2C at col 2 deletes to EOL + next line, enters insert
        self.run_test(
            "2C changes to EOL + next line",
            "Hello\nWorld\nFoo\n",
            b"ll2CNew\x1b:wq\r",
            expected_content="HeNew\nFoo\n"
        )

        # 3C from col 0 on 4 lines
        self.run_test(
            "3C changes 3 lines from cursor",
            "ab\ncd\nef\ngh\n",
            b"3CX\x1b:wq\r",
            expected_content="X\ngh\n"
        )

        # Counted C clamps to available lines
        self.run_test(
            "5C clamps to available lines",
            "Hello\nWorld\n",
            b"ll5CX\x1b:wq\r",
            expected_content="HeX\n"
        )

        self._group("Change line (cc, S):", leading_blank=True)

        self.run_test(
            "cc deletes line and enters insert",
            "hello\nworld\n",
            b"ccXY\x1b:wq\r",
            expected_content="XY\nworld\n"
        )

        self.run_test(
            "2cc changes 2 lines",
            "one\ntwo\nthree\n",
            b"2ccXY\x1b:wq\r",
            expected_content="XY\nthree\n"
        )

        self.run_test(
            "S substitutes single line",
            "hello\nworld\n",
            b"SXY\x1b:wq\r",
            expected_content="XY\nworld\n"
        )

        # 2S substitutes 2 lines (same as 2cc)
        self.run_test(
            "2S substitutes 2 lines",
            "one\ntwo\nthree\n",
            b"2SXY\x1b:wq\r",
            expected_content="XY\nthree\n"
        )

        # 3S substitutes 3 lines
        self.run_test(
            "3S substitutes 3 lines",
            "aaa\nbbb\nccc\nddd\n",
            b"3SX\x1b:wq\r",
            expected_content="X\nddd\n"
        )

        # S with count clamped to available lines
        self.run_test(
            "5S clamps to available lines",
            "hello\nworld\n",
            b"5SX\x1b:wq\r",
            expected_content="X\n"
        )

        self.run_test(
            "cc on single line",
            "hello\n",
            b"ccXY\x1b:wq\r",
            expected_content="XY\n"
        )

        # 3dd then p pastes 3 deleted lines
        self.run_test(
            "3dd then p pastes 3 deleted lines",
            "aaa\nbbb\nccc\nddd\n",
            b"3ddp:wq\r",
            expected_content="ddd\naaa\nbbb\nccc\n",
        )

        # 2cc replaces 2 lines and enters insert
        self.run_test(
            "2cc replaces 2 lines and enters insert",
            "aaa\nbbb\nccc\n",
            b"2ccX\x1b:wq\r",
            expected_content="X\nccc\n",
        )

        self._group("Indent (>>, <<):", leading_blank=True)

        self.run_test(
            ">> indents single line by 2 spaces",
            "hello\n",
            b">>:wq\r",
            expected_content="  hello\n"
        )

        self.run_test(
            ">> on single line indents correctly",
            "one\ntwo\n",
            b">>:wq\r",
            expected_content="  one\ntwo\n"
        )

        self.run_test(
            ">> on multiple lines with count",
            "one\ntwo\nthree\n",
            b"2>>:wq\r",
            expected_content="  one\n  two\nthree\n"
        )

        self.run_test(
            ">> on empty line does not indent",
            "\n",
            b">>:wq\r",
            expected_content="\n"
        )

        self.run_test(
            ">> skips empty lines in range",
            "aaa\n\nbbb\n",
            b"3>>:wq\r",
            expected_content="  aaa\n\n  bbb\n"
        )

        self.run_test(
            ">> on spaces-only line does indent",
            "   \n",
            b">>:wq\r",
            expected_content="     \n"
        )

        self.run_test(
            ">> on all empty lines is no-op",
            "\n\n\n",
            b"3>>:wq\r",
            expected_content="\n\n\n"
        )

        self.run_test_screen(
            ">> on empty line does not move cursor",
            "\nfoo\n",
            b">>:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test(
            ">> with count and mixed empty lines",
            "aaa\n\n\nbbb\n",
            b"4>>:wq\r",
            expected_content="  aaa\n\n\n  bbb\n"
        )

        self.run_test(
            ">> preserves lines after indented range",
            "aaa\nbbb\nccc\n",
            b"2>>:wq\r",
            expected_content="  aaa\n  bbb\nccc\n"
        )

        self.run_test(
            "<< unindents single line",
            "  hello\n",
            b"<<:wq\r",
            expected_content="hello\n"
        )

        self.run_test(
            "<< with partial indent (1 space)",
            " hello\n",
            b"<<:wq\r",
            expected_content="hello\n"
        )

        self.run_test(
            "<< on line with no indent",
            "hello\n",
            b"<<:wq\r",
            expected_content="hello\n"
        )

        self.run_test(
            "<< on multiple lines with count",
            "  one\n  two\nthree\n",
            b"2<<:wq\r",
            expected_content="one\ntwo\nthree\n"
        )

        self.run_test(
            ">> then << round-trips",
            "hello\n",
            b">><<:wq\r",
            expected_content="hello\n"
        )

        self.run_test(
            "<< with mixed indent levels",
            "  aaa\n bbb\nccc\n",
            b"3<<:wq\r",
            expected_content="aaa\nbbb\nccc\n"
        )

        self.run_test(
            "<< preserves lines after range",
            "  aaa\n  bbb\n  ccc\n",
            b"2<<:wq\r",
            expected_content="aaa\nbbb\n  ccc\n"
        )

        self.run_test(
            "<< with empty lines in range",
            "  aaa\n\n  bbb\n",
            b"3<<:wq\r",
            expected_content="aaa\n\nbbb\n"
        )

        self.run_test_screen(
            "<< on unindented line does not move cursor",
            "hello\n",
            b"ll<<:q!\r",
            expect_cursor=(0, 2),
        )

        self.run_test_screen(
            "<< adjusts cursor by actual spaces removed",
            " hello\n",
            b"lll<<:q!\r",
            expect_cursor=(0, 2),
        )

        # >>>> = two rapid >> combos: indents current line TWICE (4 spaces)
        # This is NOT the same as 2>> which indents 2 lines once.
        self.run_test(
            ">>>> indents current line twice (4 spaces)",
            "aaa\nbbb\nccc\n",
            b">>>>:wq\r",
            expected_content="    aaa\nbbb\nccc\n"
        )

        # 2>> indents 2 lines (count = line count, not repeat count)
        self.run_test(
            "2>> indents two lines once (different from >>>>)",
            "aaa\nbbb\nccc\n",
            b"2>>:wq\r",
            expected_content="  aaa\n  bbb\nccc\n"
        )

        # <<<< = two rapid << combos: unindents current line twice
        self.run_test(
            "<<<< unindents current line twice",
            "    aaa\n  bbb\n  ccc\n",
            b"<<<<:wq\r",
            expected_content="aaa\n  bbb\n  ccc\n"
        )

        # 2<< unindents 2 lines (count = line count, not repeat count)
        self.run_test(
            "2<< unindents two lines once (different from <<<<)",
            "  aaa\n  bbb\n  ccc\n",
            b"2<<:wq\r",
            expected_content="aaa\nbbb\n  ccc\n"
        )

        # >>>>>> = three rapid >> combos: indents current line three times (6 spaces)
        self.run_test(
            ">>>>>> indents current line three times (6 spaces)",
            "aaa\nbbb\nccc\nddd\n",
            b">>>>>>:wq\r",
            expected_content="      aaa\nbbb\nccc\nddd\n"
        )

        # >>>> cursor: col 1 + two indents (2+2 spaces) = col 5
        self.run_test_screen(
            ">>>> cursor col adjusted for double indent",
            "aaa\nbbb\nccc\n",
            b"l>>>>:q!\r",
            expect_cursor=(0, 5),
        )

        # <<<< cursor: col 3 on "  aaa", first << removes 2 → col 1, second << no-op → col 1
        self.run_test_screen(
            "<<<< cursor col adjusted for double unindent",
            "  aaa\n  bbb\n  ccc\n",
            b"lll<<<<:q!\r",
            expect_cursor=(0, 1),
        )

        # Render: >>>> batched into single action frame (3 frames: init, action, quit)
        self.run_test_screen(
            "Render: >>>> is single action frame",
            "aaa\nbbb\nccc\n",
            b">>>>:q!\r",
            expect_content_redraws=[True, True, False]
        )

        # Render: <<<< batched into single action frame (3 frames: init, action, quit)
        self.run_test_screen(
            "Render: <<<< is single action frame",
            "  aaa\n  bbb\n  ccc\n",
            b"<<<<:q!\r",
            expect_content_redraws=[True, True, False]
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

        self._group("Delete word (dw):", leading_blank=True)

        self.run_test(
            "dw deletes word and trailing space",
            "hello world\n",
            b"dw:wq\r",
            expected_content="world\n",
        )

        self.run_test(
            "dw at middle of word deletes to next word",
            "hello world\n",
            b"lldw:wq\r",
            expected_content="heworld\n",
        )

        self.run_test(
            "dw on punctuation deletes punct and space",
            "...bar baz\n",
            b"dw:wq\r",
            expected_content="bar baz\n",
        )

        self.run_test(
            "dw on last word deletes to EOL",
            "foo bar\n",
            b"4ldw:wq\r",
            expected_content="foo \n",
        )

        self.run_test(
            "dw on whitespace deletes to next word",
            "foo   bar\n",
            b"3ldw:wq\r",
            expected_content="foobar\n",
        )

        self.run_test(
            "dw on empty line does nothing",
            "\n",
            b"dw:wq\r",
            expected_content="\n",
        )

        self.run_test(
            "2dw deletes two words",
            "one two three\n",
            b"2dw:wq\r",
            expected_content="three\n",
        )

        self.run_test(
            "dw yanks deleted text (paste back)",
            "hello world\n",
            b"dw$p:wq\r",
            expected_content="worldhello \n",
        )

        # dw on whitespace only deletes whitespace (not next word)
        self.run_test(
            "dw on only whitespace deletes whitespace",
            "foo   \n",
            b"3ldw:wq\r",
            expected_content="foo\n",
        )

        # Batched dw pairs
        self.run_test(
            "dwdw batches to delete 2 words",
            "one two three four\n",
            b"dwdw:wq\r",
            expected_content="three four\n",
        )

        self.run_test(
            "dwdwdw batches to delete 3 words",
            "one two three four\n",
            b"dwdwdw:wq\r",
            expected_content="four\n",
        )

        self.run_test(
            "2dwdw batches count 2 plus 1 extra pair",
            "one two three four\n",
            b"2dwdw:wq\r",
            expected_content="four\n",
        )

        # Batched dw yank: only last word deleted is in yank buffer
        self.run_test(
            "dwdw+$p yanks only last deleted word",
            "one two three\n",
            b"dwdw$p:wq\r",
            expected_content="threetwo \n",
        )

        # Count-prefix dw yank: yanks ALL deleted text
        self.run_test(
            "2dw+$p yanks all deleted text",
            "one two three\n",
            b"2dw$p:wq\r",
            expected_content="threeone two \n",
        )

        self.run_test(
            "3dw+$p yanks all deleted text",
            "one two three four\n",
            b"3dw$p:wq\r",
            expected_content="fourone two three \n",
        )

        # Multi-line dw tests
        self.run_test(
            "dw at last word uses exclusive-linewise (preserves newline)",
            "foo\nbar\n",
            b"dw:wq\r",
            expected_content="\nbar\n",
        )

        self.run_test(
            "dw at last word with trailing spaces",
            "foo  \nbar\n",
            b"dw:wq\r",
            expected_content="\nbar\n",
        )

        self.run_test(
            "2dw crossing line boundary (lands mid-line, no adjustment)",
            "one\ntwo three\n",
            b"2dw:wq\r",
            expected_content="three\n",
        )

        self.run_test(
            "dw mid-line (single-line, no line crossing)",
            "foo bar\n",
            b"dw:wq\r",
            expected_content="bar\n",
        )

        self.run_test(
            "dwdw multi-line batch (crosses line boundary)",
            "one two\nthree four\n",
            b"dwdw:wq\r",
            expected_content="\nthree four\n",
        )

        self._group("Delete word backward (db):", leading_blank=True)

        self.run_test(
            "db deletes previous word",
            "hello world\n",
            b"wdb:wq\r",
            expected_content="world\n",
        )

        self.run_test(
            "db from middle of word deletes back to word start",
            "hello world\n",
            b"wlldb:wq\r",
            expected_content="hello rld\n",
        )

        self.run_test(
            "db at col 0 does nothing",
            "hello\n",
            b"db:wq\r",
            expected_content="hello\n",
        )

        self.run_test(
            "db with whitespace before cursor",
            "foo   bar\n",
            b"6ldb:wq\r",
            expected_content="bar\n",
        )

        self.run_test(
            "2db deletes two words backward",
            "one two three\n",
            b"$2db:wq\r",
            expected_content="one e\n",
        )

        self.run_test(
            "db yanks deleted text",
            "hello world\n",
            b"wdb$p:wq\r",
            expected_content="worldhello \n",
        )

        # Batched db pairs
        self.run_test(
            "dbdb batches to delete 2 words backward",
            "one two three\n",
            b"$dbdb:wq\r",
            expected_content="one e\n",
        )

        self.run_test(
            "dbdbdb batches to delete 3 words backward",
            "one two three four\n",
            b"$dbdbdb:wq\r",
            expected_content="one r\n",
        )

        # Batched db yank: only last word deleted is in yank buffer
        self.run_test(
            "dbdb+0p yanks only last deleted word",
            "one two three\n",
            b"$dbdb0p:wq\r",
            expected_content="otwo ne e\n",
        )

        # Count-prefix db yank: yanks ALL deleted text
        self.run_test(
            "2db+0p yanks all deleted text backward",
            "one two three\n",
            b"$2db0p:wq\r",
            expected_content="otwo threne e\n",
        )

        self.run_test(
            "3db+0p yanks all deleted text backward",
            "one two three four\n",
            b"$3db0p:wq\r",
            expected_content="otwo three foune r\n",
        )

        # Multi-line db tests
        self.run_test(
            "db from BOL deletes previous line content",
            "foo\nbar\n",
            b"jdb:wq\r",
            expected_content="bar\n",
        )

        self.run_test(
            "2db crossing line boundary",
            "hello world\nfoo\n",
            b"j2db:wq\r",
            expected_content="foo\n",
        )

        self.run_test(
            "2dbdb count+batch deletes 3 words backward",
            "one two three four\n",
            b"$2dbdb:wq\r",
            expected_content="one r\n",
        )

        self.run_test(
            "dbdb multi-line batch (crosses line boundary)",
            "one two\nthree\n",
            b"j$dbdb:wq\r",
            expected_content="one e\n",
        )

        self._group("Change word (cw):", leading_blank=True)

        self.run_test(
            "cw deletes word and enters insert mode",
            "hello world\n",
            b"cwbye\x1b:wq\r",
            expected_content="bye world\n",
        )

        self.run_test(
            "cw from mid-word deletes rest of word (ce behavior)",
            "hello world\n",
            b"llcwXX\x1b:wq\r",
            expected_content="heXX world\n",
        )

        self.run_test(
            "cw on punct deletes punct class",
            "...bar\n",
            b"cwXX\x1b:wq\r",
            expected_content="XXbar\n",
        )

        self.run_test(
            "cw on whitespace deletes ws and next word",
            "foo   bar baz\n",
            b"3lcwX\x1b:wq\r",
            expected_content="fooX baz\n",
        )

        self.run_test(
            "cw on empty line enters insert mode",
            "\n",
            b"cwhi\x1b:wq\r",
            expected_content="hi\n",
        )

        self.run_test(
            "2cw deletes two words and enters insert mode",
            "one two three\n",
            b"2cwX\x1b:wq\r",
            expected_content="X three\n",
        )

        # Count-prefix cw yank: yanks ALL deleted text
        self.run_test(
            "2cw+Esc $p yanks all deleted text",
            "one two three\n",
            b"2cw\x1b$p:wq\r",
            expected_content=" threeone two\n",
        )

        # Multi-line cw tests
        self.run_test(
            "cw at last word on line (ce semantics, no line join)",
            "foo\nbar\n",
            b"cwbaz\x1b:wq\r",
            expected_content="baz\nbar\n",
        )

        self.run_test(
            "2cw crossing line boundary",
            "foo\nbar\n",
            b"2cwx\x1b:wq\r",
            expected_content="x\n",
        )

        self._group("Change word backward (cb):", leading_blank=True)

        self.run_test(
            "cb deletes previous word and enters insert mode",
            "hello world\n",
            b"wcbX\x1b:wq\r",
            expected_content="Xworld\n",
        )

        self.run_test(
            "cb at col 0 just enters insert mode",
            "hello\n",
            b"cbhi \x1b:wq\r",
            expected_content="hi hello\n",
        )

        self.run_test(
            "cb from mid-word deletes back to word start",
            "hello world\n",
            b"wllcbX\x1b:wq\r",
            expected_content="hello Xrld\n",
        )

        self.run_test(
            "2cb deletes two words backward",
            "one two three\n",
            b"8l2cbX\x1b:wq\r",
            expected_content="Xthree\n",
        )

        # cb on all-whitespace line (cursor after spaces)
        self.run_test(
            "cb on whitespace-only content",
            "   \n",
            b"$cbX\x1b:wq\r",
            expected_content="X \n",
        )

        # Count-prefix cb yank: yanks ALL deleted text
        self.run_test(
            "2cb+Esc 0p yanks all deleted text backward",
            "one two three\n",
            b"8l2cb\x1b0p:wq\r",
            expected_content="tone two hree\n",
        )

        # db at start of line stays put
        self.run_test_screen(
            "db at start of line is no-op",
            "hello world\n",
            b"db:q!\r",
            expect_cursor=(0, 0),
        )

        # Multi-line cb tests
        self.run_test(
            "cb from BOL deletes back across line",
            "foo\nbar\n",
            b"jcbbaz\x1b:wq\r",
            expected_content="bazbar\n",
        )

        self._group("Yank word forward (yw):", leading_blank=True)

        self.run_test(
            "yw yanks word and trailing space",
            "hello world\n",
            b"yw$p:wq\r",
            expected_content="hello worldhello \n",
        )

        self.run_test(
            "yw at middle of word yanks to next word",
            "hello world\n",
            b"llyw$p:wq\r",
            expected_content="hello worldllo \n",
        )

        self.run_test(
            "yw on punctuation yanks punct group",
            "...bar baz\n",
            b"yw$p:wq\r",
            expected_content="...bar baz...\n",
        )

        self.run_test(
            "yw on last word yanks to EOL",
            "foo bar\n",
            b"4lyw$p:wq\r",
            expected_content="foo barbar\n",
        )

        self.run_test(
            "yw on whitespace yanks spaces only",
            "foo   bar\n",
            b"3lyw$p:wq\r",
            expected_content="foo   bar   \n",
        )

        self.run_test(
            "yw on empty line preserves previous yank",
            "hello\n\n",
            b"yyjyw$p:wq\r",
            expected_content="hello\n\nhello\n",
        )

        self.run_test(
            "2yw yanks two words",
            "one two three\n",
            b"2yw$p:wq\r",
            expected_content="one two threeone two \n",
        )

        self.run_test(
            "yw does not modify the file",
            "hello world\n",
            b"yw:q\r",
            expect_exit=0,
        )

        self.run_test_screen(
            "yw cursor stays at original position",
            "hello world\n",
            b"yw:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "yw from col 2 cursor stays at col 2",
            "hello world\n",
            b"llyw:q!\r",
            expect_cursor=(0, 2),
        )

        self.run_test(
            "ywyw yanks same word (second overwrites first)",
            "hello world\n",
            b"ywyw$p:wq\r",
            expected_content="hello worldhello \n",
        )

        self.run_test(
            "yw on only whitespace yanks whitespace",
            "foo   \n",
            b"3lyw$p:wq\r",
            expected_content="foo      \n",
        )

        # Multi-line yw tests
        self.run_test(
            "yw at last word uses exclusive-linewise (yanks word only)",
            "foo\nbar\n",
            b"ywjp:wq\r",
            expected_content="foo\nbfooar\n",
        )

        self._group("Yank word backward (yb):", leading_blank=True)

        self.run_test(
            "yb yanks previous word",
            "hello world\n",
            b"wyb$p:wq\r",
            expected_content="hello worldhello \n",
        )

        self.run_test(
            "yb from middle of word yanks back to word start",
            "hello world\n",
            b"wllyb$p:wq\r",
            expected_content="hello worldwo\n",
        )

        self.run_test(
            "yb at col 0 does nothing",
            "hello\n",
            b"yb:q\r",
            expect_exit=0,
        )

        self.run_test(
            "yb with whitespace before cursor",
            "foo   bar\n",
            b"6lyb$p:wq\r",
            expected_content="foo   barfoo   \n",
        )

        self.run_test(
            "2yb yanks two words backward",
            "one two three\n",
            b"$2yb$p:wq\r",
            expected_content="one two threetwo thre\n",
        )

        self.run_test(
            "yb does not modify the file",
            "hello world\n",
            b"wyb:q\r",
            expect_exit=0,
        )

        self.run_test_screen(
            "yb cursor moves to word start",
            "hello world\n",
            b"wyb:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test(
            "ybyb yanks second word back (cursor moves twice)",
            "one two three\n",
            b"$ybyb$p:wq\r",
            expected_content="one two threetwo \n",
        )

        # Multi-line yb tests
        self.run_test(
            "yb from BOL yanks across line boundary",
            "foo\nbar\n",
            b"jyb0P:wq\r",
            expected_content="foo\nfoo\nbar\n",
        )

        self._group("Delete word end (de):", leading_blank=True)

        self.run_test(
            "de deletes to end of word (inclusive)",
            "hello world\n",
            b"de:wq\r",
            expected_content=" world\n",
        )

        self.run_test(
            "de from mid-word deletes to end of word",
            "hello world\n",
            b"llde:wq\r",
            expected_content="he world\n",
        )

        self.run_test(
            "de at end of word deletes next word",
            "hello world\n",
            b"4lde:wq\r",
            expected_content="hell\n",
        )

        self.run_test(
            "de on punctuation deletes punct group",
            "...bar\n",
            b"de:wq\r",
            expected_content="bar\n",
        )

        self.run_test(
            "de on single char line",
            "x\n",
            b"de:wq\r",
            expected_content="\n",
        )

        self.run_test(
            "de on empty line does nothing",
            "\n",
            b"de:wq\r",
            expected_content="\n",
        )

        self.run_test(
            "2de deletes two word ends",
            "one two three\n",
            b"2de:wq\r",
            expected_content=" three\n",
        )

        self.run_test(
            "de yanks deleted text (paste back)",
            "hello world\n",
            b"de$p:wq\r",
            expected_content=" worldhello\n",
        )

        # Batched de pairs
        self.run_test(
            "dede batches to delete 2 word ends",
            "one two three four\n",
            b"dede:wq\r",
            expected_content=" three four\n",
        )

        self.run_test(
            "dedede batches to delete 3 word ends",
            "one two three four\n",
            b"dedede:wq\r",
            expected_content=" four\n",
        )

        self.run_test(
            "2dede batches count 2 plus 1 extra pair",
            "one two three four\n",
            b"2dede:wq\r",
            expected_content=" four\n",
        )

        # Batched de yank: only last word-end deleted is in yank buffer
        # After first de removes "one", cursor is on space; second de's
        # inclusive range is " two" (space through end of word)
        self.run_test(
            "dede+$p yanks only last deleted word",
            "one two three\n",
            b"dede$p:wq\r",
            expected_content=" three two\n",
        )

        # Count-prefix de yank: yanks ALL deleted text
        self.run_test(
            "2de+$p yanks all deleted text",
            "one two three\n",
            b"2de$p:wq\r",
            expected_content=" threeone two\n",
        )

        # Multi-line de tests
        self.run_test(
            "de at end of line crosses to next line",
            "foo\nbar baz\n",
            b"2lde:wq\r",
            expected_content="fo baz\n",
        )

        self.run_test(
            "2de crossing line boundary",
            "one\ntwo three\n",
            b"2de:wq\r",
            expected_content=" three\n",
        )

        self.run_test(
            "2dede count+batch deletes 3 word ends",
            "one two three four\n",
            b"2dede:wq\r",
            expected_content=" four\n",
        )

        self._group("Change word end (ce):", leading_blank=True)

        self.run_test(
            "ce deletes to end of word and enters insert mode",
            "hello world\n",
            b"cebye\x1b:wq\r",
            expected_content="bye world\n",
        )

        self.run_test(
            "ce from mid-word deletes rest of word",
            "hello world\n",
            b"llceXX\x1b:wq\r",
            expected_content="heXX world\n",
        )

        self.run_test(
            "ce on punctuation deletes punct class",
            "...bar\n",
            b"ceXX\x1b:wq\r",
            expected_content="XXbar\n",
        )

        self.run_test(
            "ce on empty line enters insert mode",
            "\n",
            b"cehi\x1b:wq\r",
            expected_content="hi\n",
        )

        self.run_test(
            "2ce deletes two word ends and enters insert mode",
            "one two three\n",
            b"2ceX\x1b:wq\r",
            expected_content="X three\n",
        )

        # Count-prefix ce yank: yanks ALL deleted text
        self.run_test(
            "2ce+Esc $p yanks all deleted text",
            "one two three\n",
            b"2ce\x1b$p:wq\r",
            expected_content=" threeone two\n",
        )

        # Multi-line ce tests
        self.run_test(
            "ce at last word on line",
            "foo\nbar\n",
            b"cebaz\x1b:wq\r",
            expected_content="baz\nbar\n",
        )

        self.run_test(
            "2ce crossing line boundary",
            "foo\nbar baz\n",
            b"2cex\x1b:wq\r",
            expected_content="x baz\n",
        )

        self._group("Yank word end (ye):", leading_blank=True)

        self.run_test(
            "ye yanks to end of word (inclusive, no trailing space)",
            "hello world\n",
            b"ye$p:wq\r",
            expected_content="hello worldhello\n",
        )

        self.run_test(
            "ye at middle of word yanks to word end",
            "hello world\n",
            b"llye$p:wq\r",
            expected_content="hello worldllo\n",
        )

        self.run_test(
            "ye on punctuation yanks punct group",
            "...bar baz\n",
            b"ye$p:wq\r",
            expected_content="...bar baz...\n",
        )

        self.run_test(
            "ye on last word yanks to end of word",
            "foo bar\n",
            b"4lye$p:wq\r",
            expected_content="foo barbar\n",
        )

        self.run_test(
            "ye on empty line preserves previous yank",
            "hello\n\n",
            b"yyjye$p:wq\r",
            expected_content="hello\n\nhello\n",
        )

        self.run_test(
            "2ye yanks two word ends",
            "one two three\n",
            b"2ye$p:wq\r",
            expected_content="one two threeone two\n",
        )

        self.run_test(
            "ye does not modify the file",
            "hello world\n",
            b"ye:q\r",
            expect_exit=0,
        )

        self.run_test_screen(
            "ye cursor stays at original position",
            "hello world\n",
            b"ye:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "ye from col 2 cursor stays at col 2",
            "hello world\n",
            b"llye:q!\r",
            expect_cursor=(0, 2),
        )

        self.run_test(
            "yeye yanks same word end (second overwrites first)",
            "hello world\n",
            b"yeye$p:wq\r",
            expected_content="hello worldhello\n",
        )

        # Multi-line ye tests
        # From end of "foo" (col 2), e crosses to end of "bar" on next line.
        # Inclusive range = "o\nbar". Pasting after $ inserts after last char.
        self.run_test(
            "ye at end of word yanks next word across line",
            "foo\nbar baz\n",
            b"2lye$p:wq\r",
            expected_content="fooo\nbar\nbar baz\n",
        )

        self._group("Delete/yank to BOL (d0, y0):", leading_blank=True)

        # d0 at col 3 deletes "Hel"
        self.run_test(
            "d0 at col 3 deletes to BOL",
            "Hello\n",
            b"llld0:wq\r",
            expected_content="lo\n"
        )

        # d0 at col 0 does nothing
        self.run_test(
            "d0 at col 0 does nothing",
            "Hello\n",
            b"d0:wq\r",
            expected_content="Hello\n"
        )

        # d0 on empty line does nothing
        self.run_test(
            "d0 on empty line does nothing",
            "\n",
            b"d0:wq\r",
            expected_content="\n"
        )

        # 2d0 = d0 (count ignored)
        self.run_test(
            "2d0 same as d0 (count ignored)",
            "Hello\n",
            b"lll2d0:wq\r",
            expected_content="lo\n"
        )

        # y0 at col 3 yanks "Hel", paste at col 0
        self.run_test(
            "y0p yanks to BOL and pastes",
            "Hello\n",
            b"llly0P:wq\r",
            expected_content="HelHello\n"
        )

        # y0 at col 0 does nothing (no yank)
        self.run_test(
            "y0 at col 0 does nothing",
            "Hello\n",
            b"y0:wq\r",
            expected_content="Hello\n"
        )

        self._group("Yank to EOL (y$):", leading_blank=True)

        # y$ at col 2 yanks "llo", paste after cursor char 'l' at col 2
        self.run_test(
            "y$p yanks to EOL and pastes",
            "Hello\n",
            b"lly$p:wq\r",
            expected_content="Helllolo\n"
        )

        # y$ at col 0 yanks whole line content
        self.run_test(
            "y$0p yanks whole line",
            "Hello\n",
            b"y$0P:wq\r",
            expected_content="HelloHello\n"
        )

        # y$ on empty line does nothing (no yank)
        self.run_test(
            "y$ on empty line",
            "\n",
            b"y$:wq\r",
            expected_content="\n"
        )

        # 2y$ yanks across 2 lines
        self.run_test(
            "2y$p yanks across 2 lines",
            "Hello\nWorld\nFoo\n",
            b"ll2y$$p:wq\r",
            expected_content="Hellollo\nWorld\nWorld\nFoo\n"
        )

        # y$ doesn't modify buffer
        self.run_test(
            "y$ doesn't modify buffer",
            "Hello\n",
            b"y$:wq\r",
            expected_content="Hello\n"
        )

        self._group("Backward search (?):", leading_blank=True)

        self.run_test_screen(
            "? finds match on previous line",
            "alpha\nbeta\ngamma\n",
            b"jj?alpha\r:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "? wraps around to find match below",
            "alpha\nbeta\ngamma\n",
            b"?gamma\r:q!\r",
            expect_cursor=(2, 0),
        )

        self.run_test_screen(
            "n after ? searches backward",
            "aaa\nbbb\naaa\nccc\naaa\n",
            b"jj?aaa\rn:q!\r",
            expect_cursor=(4, 0),
        )

        self.run_test_screen(
            "N after ? searches forward",
            "aaa\nbbb\naaa\nccc\naaa\n",
            b"jj?aaa\rN:q!\r",
            expect_cursor=(2, 0),
        )

        self.run_test_screen(
            "n after / searches forward",
            "aaa\nbbb\naaa\nccc\naaa\n",
            b"jj/aaa\rn:q!\r",
            expect_cursor=(0, 0),
        )

        self.run_test_screen(
            "N after / searches backward",
            "aaa\nbbb\naaa\nccc\naaa\n",
            b"jj/aaa\rN:q!\r",
            expect_cursor=(2, 0),
        )

        self.run_test_screen(
            "? with empty pattern reuses previous",
            "foo\nbar\nfoo\n",
            b"jj?foo\r?\r:q!\r",
            expect_cursor=(2, 0),
        )

        # ? finds match earlier on same line (before cursor)
        self.run_test_screen(
            "? finds match on same line before cursor",
            "AA BB AA\n",
            b"llllll?AA\r:q!\r",
            expect_cursor=(0, 0),  # cursor at col 6, finds AA at col 0
        )

        # N (after /) finds previous match on same line
        self.run_test_screen(
            "N finds previous match on same line",
            "AA BB AA CC AA\n",
            b"/AA\rnN:q!\r",
            expect_cursor=(0, 6),  # /->col6, n->col12, N reverses back to col6
        )

        # ? finds rightmost match on previous line
        self.run_test_screen(
            "? finds rightmost match on previous line",
            "AA BB AA\nCC\n",
            b"j?AA\r:q!\r",
            expect_cursor=(0, 6),  # from line 1, backward finds last AA on line 0
        )

        # ? wraps around to find match after cursor on same line
        self.run_test_screen(
            "? wraps around to match after cursor on same line",
            "BB CC AA\n",
            b"lll?AA\r:q!\r",
            expect_cursor=(0, 6),  # cursor at col 3, no AA before col 3, wraps to find AA at col 6
        )

        # Forward search skips match AT cursor position
        self.run_test_screen(
            "/ skips match at cursor position",
            "AA BB\n",
            b"/AA\r:q!\r",   # cursor at (0,0) which IS an AA match
            expect_cursor=(0, 0),  # only one AA, wraps all the way around back to it
        )

        # Single-line file, multiple matches, n cycles through
        self.run_test_screen(
            "n cycles through all matches on single line",
            "ABCABCABC\n",
            b"/ABC\rnn:q!\r",
            expect_cursor=(0, 0),  # /->col3, n->col6, n wraps to col0
        )

        # Backward search with cursor at col 0 goes to previous line
        self.run_test_screen(
            "? at col 0 goes to previous line",
            "AA\nBB\nAA\n",
            b"jj?AA\r:q!\r",
            expect_cursor=(0, 0),  # from (2,0), goes to (0,0)
        )

        # Backspace on empty pattern cancels ? search
        self.run_test_screen(
            "? backspace cancels to normal mode",
            "AAA\nBBB\n",
            b"j?\x7f:q!\r",
            expect_cursor=(1, 0),  # Stays on line 1
        )

        # / with backspace editing pattern
        self.run_test_screen(
            "/ with backspace editing pattern",
            "AAA\nBBB\nBCC\n",
            b"/BC\x7fBB\r:q!\r",
            expect_cursor=(1, 0),  # Searches for "BBB" not "BC"
        )

        # : command with multiple backspaces then retype
        self.run_test(
            ": command backspace then retype",
            "hello\n",
            b":ww\x7f\x7fq!\r",
            # Type :ww, BS twice to clear, type q! -> :q!
        )

        # ============================================================
        # Extended key handling (function keys, ctrl+arrows, etc.)
        # ============================================================
        self._group("Extended key handling:", leading_blank=True)

        # F5 (ESC[15~) in normal mode - should be consumed, no side effects
        self.run_test(
            "F5 in normal mode is no-op",
            "hello\n",
            b"\x1b[15~:wq\r",
            expected_content="hello\n"
        )

        # F12 (ESC[24~) in normal mode - should be consumed, no side effects
        self.run_test(
            "F12 in normal mode is no-op",
            "hello\n",
            b"\x1b[24~:wq\r",
            expected_content="hello\n"
        )

        # Ctrl+Right word motion in normal mode
        self.run_test_screen(
            "Ctrl+Right moves to next word in normal mode",
            "hello world\n",
            b"\x1b[1;5C:q!\r",
            expect_cursor=(0, 6),
        )

        # Ctrl+Left word motion in normal mode
        self.run_test_screen(
            "Ctrl+Left moves to prev word in normal mode",
            "hello world\n",
            b"$\x1b[1;5D:q!\r",
            expect_cursor=(0, 6),
        )

        # Ctrl+Right crosses line boundary
        self.run_test_screen(
            "Ctrl+Right crosses line boundary",
            "foo\nbar\n",
            b"$\x1b[1;5C:q!\r",
            expect_cursor=(1, 0),
        )

        # Ctrl+Left crosses line boundary (lands at start of last word)
        self.run_test_screen(
            "Ctrl+Left crosses line boundary",
            "foo\nbar\n",
            b"j\x1b[1;5D:q!\r",
            expect_cursor=(0, 0),
        )

        # Count prefix with Ctrl+Right
        self.run_test_screen(
            "Count prefix with Ctrl+Right",
            "one two three\n",
            b"2\x1b[1;5C:q!\r",
            expect_cursor=(0, 8),
        )

        # Batching: 3x Ctrl+Right
        self.run_test_screen(
            "Batching 3x Ctrl+Right",
            "one two three four five\n",
            b"\x1b[1;5C\x1b[1;5C\x1b[1;5C:q!\r",
            expect_cursor=(0, 14),
        )

        # Shift+Up (ESC[1;2A) in normal mode - should be consumed
        self.run_test(
            "Shift+Up in normal mode is no-op",
            "hello\n",
            b"\x1b[1;2A:wq\r",
            expected_content="hello\n"
        )

        # Ctrl+Up (ESC[1;5A) in normal mode - should be consumed
        self.run_test(
            "Ctrl+Up in normal mode is no-op",
            "hello\n",
            b"\x1b[1;5A:wq\r",
            expected_content="hello\n"
        )

        # Ctrl+Down (ESC[1;5B) in normal mode - should be consumed
        self.run_test(
            "Ctrl+Down in normal mode is no-op",
            "hello\n",
            b"\x1b[1;5B:wq\r",
            expected_content="hello\n"
        )

        # Insert key (ESC[2~) in normal mode - should be no-op
        self.run_test(
            "Insert key in normal mode is no-op",
            "hello\n",
            b"\x1b[2~:wq\r",
            expected_content="hello\n"
        )

        # Multiple unknown sequences in a row
        self.run_test(
            "Multiple unknown keys in a row",
            "hello\n",
            b"\x1b[15~\x1b[24~\x1b[1;2A:wq\r",
            expected_content="hello\n"
        )

        # F5 in insert mode - should stay in insert mode
        self.run_test(
            "F5 in insert mode stays in insert mode",
            "hello\n",
            b"i\x1b[15~X\x1b:wq\r",
            expected_content="Xhello\n"
        )

        # Ctrl+Right word motion in insert mode
        self.run_test(
            "Ctrl+Right in insert mode moves to next word",
            "hello world\n",
            b"i\x1b[1;5CX\x1b:wq\r",
            expected_content="hello Xworld\n"
        )

        # Ctrl+Left word motion in insert mode
        self.run_test(
            "Ctrl+Left in insert mode moves to prev word",
            "hello world\n",
            b"$a\x1b[1;5DX\x1b:wq\r",
            expected_content="hello Xworld\n"
        )

        # Ctrl+Right crosses line in insert mode
        self.run_test(
            "Ctrl+Right crosses line in insert mode",
            "foo\nbar\n",
            b"$a\x1b[1;5CX\x1b:wq\r",
            expected_content="foo\nXbar\n"
        )

        # Ctrl+Left crosses line in insert mode (lands at start of last word)
        self.run_test(
            "Ctrl+Left crosses line in insert mode",
            "foo\nbar\n",
            b"ji\x1b[1;5DX\x1b:wq\r",
            expected_content="Xfoo\nbar\n"
        )

        # Batching Ctrl+Right in insert mode
        self.run_test(
            "Batching 3x Ctrl+Right in insert mode",
            "one two three four\n",
            b"i\x1b[1;5C\x1b[1;5C\x1b[1;5CX\x1b:wq\r",
            expected_content="one two three Xfour\n"
        )

        # Ctrl+Right on empty line in insert mode
        self.run_test(
            "Ctrl+Right on empty line in insert mode",
            "\nbar\n",
            b"i\x1b[1;5CX\x1b:wq\r",
            expected_content="\nXbar\n"
        )

        # Regression: arrow keys still work
        self.run_test_screen(
            "Regression: right arrow still works",
            "hello\n",
            b"ll:q!\r",
            expect_cursor=(0, 2),
        )

        # Regression: delete key still works
        self.run_test(
            "Regression: delete key still works",
            "hello\n",
            b"\x1b[3~:wq\r",
            expected_content="ello\n"
        )

        # Regression: PgDn still works
        self.run_test_screen(
            "Regression: PgDn still works",
            make_lines(30),
            b"\x1b[6~:q!\r",
            expect_cursor=(0, 0),
            expect_lines=[(0, "Line 10")],
        )

        # SS3 sequences (ESC O <final>) - F1-F4 on some terminals
        # F1 SS3 (ESC O P) in normal mode - should be consumed
        self.run_test(
            "F1 SS3 in normal mode is no-op",
            "hello\n",
            b"\x1bOP:wq\r",
            expected_content="hello\n"
        )

        # F2 SS3 (ESC O Q) in normal mode - should be consumed
        self.run_test(
            "F2 SS3 in normal mode is no-op",
            "hello\n",
            b"\x1bOQ:wq\r",
            expected_content="hello\n"
        )

        # F1 SS3 in insert mode - should stay in insert mode
        self.run_test(
            "F1 SS3 in insert mode stays in insert mode",
            "hello\n",
            b"i\x1bOPX\x1b:wq\r",
            expected_content="Xhello\n"
        )

        # ============================================================
        # Terminal mode tests
        # ============================================================
        self._group("Terminal mode:", leading_blank=True)

        if not self.build_terminal_editor():
            print("  Skipping terminal mode tests (build failed)")
        else:
            # Basic smoke test: quit exits cleanly
            self.run_test_terminal(
                "Terminal :q! exits cleanly",
                "Hello\n",
                b":q!\r"
            )

            # Open and save unchanged
            self.run_test_terminal(
                "Terminal :wq saves unchanged file",
                "Hello\n",
                b":wq\r",
                expected_content="Hello\n"
            )

            # Delete char with x
            self.run_test_terminal(
                "Terminal x deletes first char",
                "Hello\n",
                b"x:wq\r",
                expected_content="ello\n"
            )

            # Terminal size detection: 10x40
            self.run_test_terminal_screen(
                "Terminal size 10x40",
                "Hello\n",
                b":q!\r",
                rows=10, cols=40,
                expect_lines=[(0, "Hello")],
                expect_status_contains="/t "
            )

            # Terminal size detection: verify tilde rows
            self.run_test_terminal_screen(
                "Terminal size 10x40 tilde rows",
                "Line1\nLine2\n",
                b":q!\r",
                rows=10, cols=40,
                expect_lines=[
                    (0, "Line1"),
                    (1, "Line2"),
                    (2, "~"),
                    (7, "~"),
                ]
            )

            # Terminal size detection: 24x80
            self.run_test_terminal_screen(
                "Terminal size 24x80",
                "Hello\n",
                b":q!\r",
                rows=24, cols=80,
                expect_lines=[(0, "Hello")],
                expect_status_contains="/t "
            )

            # Terminal size with baud rate
            self.run_test_terminal_screen(
                "Terminal size with baud rate",
                "Hello\n",
                b":q!\r",
                rows=10, cols=40,
                expect_lines=[(0, "Hello")],
                expect_status_contains="/t ",
                extra_args=["--cpu-mhz", "1", "--baud", "9600"]
            )

            # --------------------------------------------------------
            # Screen state tests in terminal mode
            # --------------------------------------------------------
            self._group("Terminal mode - screen state:", leading_blank=True)

            # Cursor at (0,0) on open
            self.run_test_terminal_screen(
                "Terminal cursor at (0,0) on open",
                "Hello\n",
                b":q!\r",
                expect_cursor=(0, 0)
            )

            # Cursor movement: lll -> (0,3)
            self.run_test_terminal_screen(
                "Terminal lll moves cursor to (0,3)",
                "Hello\n",
                b"lll:q!\r",
                expect_cursor=(0, 3)
            )

            # Cursor movement: lllh -> (0,2)
            self.run_test_terminal_screen(
                "Terminal lllh moves cursor to (0,2)",
                "Hello\n",
                b"lllh:q!\r",
                expect_cursor=(0, 2)
            )

            # Cursor movement: jj -> (2,0)
            self.run_test_terminal_screen(
                "Terminal jj moves cursor to (2,0)",
                "Line 1\nLine 2\nLine 3\n",
                b"jj:q!\r",
                expect_cursor=(2, 0)
            )

            # Cursor movement: jjk -> (1,0)
            self.run_test_terminal_screen(
                "Terminal jjk moves cursor to (1,0)",
                "Line 1\nLine 2\nLine 3\n",
                b"jjk:q!\r",
                expect_cursor=(1, 0)
            )

            # Arrow keys: right right right -> (0,3)
            self.run_test_terminal_screen(
                "Terminal arrow keys move cursor",
                "Hello\n",
                b"\x1b[C\x1b[C\x1b[C:q!\r",
                expect_cursor=(0, 3)
            )

            # Screen content: 5-line file
            self.run_test_terminal_screen(
                "Terminal 5-line file content and tildes",
                make_lines(5),
                b":q!\r",
                expect_lines=[
                    (0, "Line 1"),
                    (1, "Line 2"),
                    (2, "Line 3"),
                    (3, "Line 4"),
                    (4, "Line 5"),
                    (5, "~"),
                    (8, "~"),
                ]
            )

            # Status bar shows filename and position
            self.run_test_terminal_screen(
                "Terminal status bar shows filename",
                "Hello\n",
                b":q!\r",
                expect_status_contains="/t "
            )

            # Status bar shows mode (COMMAND after :)
            self.run_test_terminal_screen(
                "Terminal status bar shows COMMAND",
                "Hello\n",
                b":q!\r",
                expect_status_contains="COMMAND - 1,"
            )

            # Status bar after cursor movement
            self.run_test_terminal_screen(
                "Terminal status bar after j",
                "Hello\nWorld\n",
                b"jlll:q!\r",
                expect_status_contains="COMMAND - 2,"
            )

            # Scrolling down past screen bottom
            self.run_test_terminal_screen(
                "Terminal scroll down",
                make_lines(15),
                b"jjjjjjjjj:q!\r",
                expect_cursor=(8, 0),
                expect_lines=[(i, f"Line {i+2}") for i in range(9)]
            )

            # Scroll down then back up
            self.run_test_terminal_screen(
                "Terminal scroll up restores view",
                make_lines(15),
                b"jjjjjjjjj" + b"kkkkkkkkk" + b":q!\r",
                expect_cursor=(0, 0),
                expect_lines=[(i, f"Line {i+1}") for i in range(9)]
            )

            # Insert mode: type a character
            self.run_test_terminal_screen(
                "Terminal insert updates screen",
                "Hello\n",
                b"iX\x1b:q!\r",
                expect_lines=[(0, "XHello")],
                expect_cursor=(0, 0)
            )

            # Insert mode: ESC returns to normal
            self.run_test_terminal_screen(
                "Terminal ESC returns to normal mode",
                "Hello\n",
                b"i\x1b:q!\r",
                expect_status_contains="COMMAND"
            )

            # --------------------------------------------------------
            # Baud rate screen state tests
            # --------------------------------------------------------
            self._group("Terminal mode - baud rate screen state:", leading_blank=True)

            BAUD_ARGS = ["--cpu-mhz", "1", "--baud", "9600"]

            # Cursor movement with baud rate
            self.run_test_terminal_screen(
                "Terminal baud: cursor movement",
                "Hello\n",
                b"lll:q!\r",
                expect_cursor=(0, 3),
                extra_args=BAUD_ARGS
            )

            # Insert with baud rate
            self.run_test_terminal_screen(
                "Terminal baud: insert character",
                "Hello\n",
                b"iX\x1b:q!\r",
                expect_lines=[(0, "XHello")],
                extra_args=BAUD_ARGS
            )

            # Scrolling with baud rate
            self.run_test_terminal_screen(
                "Terminal baud: scroll down",
                make_lines(15),
                b"jjjjjjjjj:q!\r",
                expect_cursor=(8, 0),
                expect_lines=[(0, "Line 2"), (8, "Line 10")],
                extra_args=BAUD_ARGS
            )

            # --------------------------------------------------------
            # Functional tests in terminal mode
            # --------------------------------------------------------
            self._group("Terminal mode - functional:", leading_blank=True)

            # :w saves file
            self.run_test_terminal(
                "Terminal :w saves file",
                "Hello\n",
                b":w\r:q!\r",
                expected_content="Hello\n"
            )

            # :wq saves and quits
            self.run_test_terminal(
                "Terminal :wq saves and quits",
                "Hello\n",
                b":wq\r",
                expected_content="Hello\n"
            )

            # :q on unmodified file
            self.run_test_terminal(
                "Terminal :q on unmodified",
                "Hello\n",
                b":q\r",
                expected_content="Hello\n"
            )

            # :q! force quit
            self.run_test_terminal(
                "Terminal :q! force quit",
                "Hello\n",
                b"x:q!\r",
                expected_content="Hello\n"
            )

            # x delete character
            self.run_test_terminal(
                "Terminal x deletes char",
                "Hello\n",
                b"llx:wq\r",
                expected_content="Helo\n"
            )

            # dd delete line
            self.run_test_terminal(
                "Terminal dd deletes line",
                "Line 1\nLine 2\nLine 3\n",
                b"jdd:wq\r",
                expected_content="Line 1\nLine 3\n"
            )

            # i insert mode
            self.run_test_terminal(
                "Terminal i inserts text",
                "Hello\n",
                b"iWorld \x1b:wq\r",
                expected_content="World Hello\n"
            )

            # a append mode
            self.run_test_terminal(
                "Terminal a appends text",
                "Hello\n",
                b"aX\x1b:wq\r",
                expected_content="HXello\n"
            )

            # o open line below
            self.run_test_terminal(
                "Terminal o opens line below",
                "Line 1\nLine 2\n",
                b"oNew\x1b:wq\r",
                expected_content="Line 1\nNew\nLine 2\n"
            )

            # O open line above
            self.run_test_terminal(
                "Terminal O opens line above",
                "Line 1\nLine 2\n",
                b"jONew\x1b:wq\r",
                expected_content="Line 1\nNew\nLine 2\n"
            )

            # --------------------------------------------------------
            # Baud rate functional tests
            # --------------------------------------------------------
            self._group("Terminal mode - baud rate functional:", leading_blank=True)

            # Batch insert with baud rate
            self.run_test_terminal(
                "Terminal baud: insert text",
                "Hello\n",
                b"iABC\x1b:wq\r",
                expected_content="ABCHello\n",
                extra_args=BAUD_ARGS
            )

            # Batch delete with baud rate
            self.run_test_terminal(
                "Terminal baud: x delete",
                "Hello\n",
                b"xx:wq\r",
                expected_content="llo\n",
                extra_args=BAUD_ARGS
            )

            # dd with baud rate
            self.run_test_terminal(
                "Terminal baud: dd delete line",
                "Line 1\nLine 2\nLine 3\n",
                b"dd:wq\r",
                expected_content="Line 2\nLine 3\n",
                extra_args=BAUD_ARGS
            )

            # Command mode with baud rate
            self.run_test_terminal(
                "Terminal baud: :wq command",
                "Test\n",
                b":wq\r",
                expected_content="Test\n",
                extra_args=BAUD_ARGS
            )

            # Search mode with baud rate
            self.run_test_terminal_screen(
                "Terminal baud: search /Line",
                "First\nLine 2\nLine 3\n",
                b"/Line\r:q!\r",
                expect_cursor=(1, 0),
                extra_args=BAUD_ARGS
            )

            # Backward search
            self.run_test_terminal_screen(
                "Terminal baud: backward search ?alpha",
                "alpha\nbeta\ngamma\n",
                b"jj?alpha\r:q!\r",
                expect_cursor=(0, 0),
                extra_args=BAUD_ARGS
            )

            # --------------------------------------------------------
            # Baud rate batching tests
            # --------------------------------------------------------
            self._group("Terminal mode - baud rate batching:", leading_blank=True)

            BAUD2_ARGS = ["--cpu-mhz", "2", "--baud", "9600"]

            # Insert 5 chars at 2MHz/9600 baud - should batch into fewer
            # frames than 5.  With hardware FIFO buffering, chars accumulate
            # in the RX buffer during rendering and the editor reads them
            # all in one batch.  Verify only 1 content redraw for the
            # insert (frame index 1), not 5 separate redraws.
            self.run_test_terminal_screen(
                "Terminal baud: insert batching",
                "\n",
                b"ihello\x1b:q!\r",
                expect_lines=[(0, "hello")],
                expect_lines_at_frame=[
                    # Frame 1: enter insert mode, no chars yet
                    (1, [(0, "")]),
                    # Frame 2: all 5 chars batched in one redraw
                    (2, [(0, "hello")]),
                ],
                extra_args=BAUD2_ARGS
            )

        # ============================================================
        # Scroll region optimization tests
        # ============================================================
        self._group("Scroll region optimization:", leading_blank=True)

        # j past bottom: scroll up uses partial redraw, not full repaint.
        # 15-line file, 10-row screen (9 content + 1 status).
        # All 10 j's batch into one cycle. Cursor moves to line 10,
        # VIEW_TOP goes from 0 to 2 (delta=2). Frame 1 is the scroll
        # frame - with optimization, only 2 newly exposed bottom rows.
        self.run_test_screen(
            "Scroll opt: j past bottom uses scroll",
            make_lines(15),
            b"j" * 10 + b":q!\r",
            rows=10, cols=40,
            expect_lines=[(i, f"Line {i+3}") for i in range(9)],
            expect_cursor=(8, 0),
            # Frame 1 is the scroll frame - should touch only 2 rows
            # (newly exposed bottom rows), not all 9
            expect_content_rows=[(1, {7, 8})]
        )

        # k past top: scroll down uses partial redraw.
        # After scrolling down, scroll back up.
        # 10 j's batch → frame 1 (scroll down). 10 k's batch → frame 2
        # (scroll up). VIEW_TOP goes from 2 back to 0 (delta=2).
        self.run_test_screen(
            "Scroll opt: k past top uses scroll",
            make_lines(15),
            b"j" * 10 + b"k" * 10 + b":q!\r",
            rows=10, cols=40,
            expect_lines=[(i, f"Line {i+1}") for i in range(9)],
            expect_cursor=(0, 0),
            # Frame 2 is the scroll-up frame - should touch only 2 rows
            # (newly exposed top rows), not all 9
            expect_content_rows=[(2, {0, 1})]
        )

        # Batched jjjjjjjjjjjjj scrolls multiple in one frame.
        # 13 j's: cursor at line 13, VIEW_TOP goes from 0 to 5 (delta=5).
        # With optimization: scroll up 5, render 5 new bottom rows.
        self.run_test_screen(
            "Scroll opt: batched j*13 scrolls multiple",
            make_lines(20),
            b"j" * 13 + b":q!\r",
            rows=10, cols=40,
            expect_lines=[(i, f"Line {i+6}") for i in range(9)],
            expect_cursor=(8, 0),
            # Frame 1: scroll by 5 - touches only the 5 new bottom rows
            expect_content_rows=[(1, {4, 5, 6, 7, 8})]
        )

        # Large scroll falls back to full repaint (G to end of file)
        self.run_test_screen(
            "Scroll opt: large scroll falls back to full repaint",
            make_lines(20),
            b"G:q!\r",
            rows=10, cols=40,
            expect_lines=[(i, f"Line {i+12}") for i in range(9)],
            expect_cursor=(8, 0),
            # G scrolls by 11 lines (>= 9 content rows), falls back to
            # full repaint touching all 9 content rows
            expect_content_rows=[(1, {0, 1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # Scroll by 1 row: single j from bottom edge
        # Put cursor at line 8 (bottom), then 1 more j to scroll by 1.
        # Since all batch: 9 j's = cursor at line 9. VIEW_TOP goes 0→1.
        self.run_test_screen(
            "Scroll opt: scroll by 1 row",
            make_lines(15),
            b"j" * 9 + b":q!\r",
            rows=10, cols=40,
            expect_lines=[(i, f"Line {i+2}") for i in range(9)],
            expect_cursor=(8, 0),
            # Frame 1: scroll by 1 - touches only 1 new bottom row
            expect_content_rows=[(1, {8})]
        )

        # dd at cursor row 3: scroll shifts rows below cursor up,
        # only bottom row needs rendering.
        # Frames: 0=initial, 1=jjj cursor-only, 2=dd scroll frame
        self.run_test_screen(
            "Scroll opt: dd at mid-screen uses scroll",
            make_lines(15),
            b"jjjdd:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            # Frame 2 (dd): cursor row + bottom row touched
            expect_content_rows=[(2, {3, 8})]
        )

        # dd at row 0: entire content area scrolls up, bottom row rendered
        self.run_test_screen(
            "Scroll opt: dd at top uses scroll",
            make_lines(15),
            b"dd:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 2"), (1, "Line 3"), (2, "Line 4"),
                (3, "Line 5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(0, 0),
            # Frame 1 (dd): cursor row + bottom row touched
            expect_content_rows=[(1, {0, 8})]
        )

        # 3dd: 3 lines deleted, 3 bottom rows need rendering
        # Frame 0=initial, 1=count '3' display, 2=dd scroll frame
        self.run_test_screen(
            "Scroll opt: 3dd uses scroll",
            make_lines(15),
            b"3dd:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 4"), (1, "Line 5"), (2, "Line 6"),
                (3, "Line 7"), (4, "Line 8"), (5, "Line 9"),
                (6, "Line 10"), (7, "Line 11"), (8, "Line 12"),
            ],
            expect_cursor=(0, 0),
            # Frame 2 (3dd): cursor row + bottom 3 rows touched
            expect_content_rows=[(2, {0, 6, 7, 8})]
        )

        # o at mid-screen: scroll shifts rows below insertion down,
        # only new empty line needs rendering.
        # Frames: 0=initial, 1=jjj cursor, 2=o scroll frame
        self.run_test_screen(
            "Scroll opt: o at mid-screen uses scroll",
            make_lines(15),
            b"jjjo\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, ""),
                (5, "Line 5"), (6, "Line 6"), (7, "Line 7"),
                (8, "Line 8"),
            ],
            expect_cursor=(4, 0),
            # Frame 2 (o): new line row + row above (re-rendered by handler)
            expect_content_rows=[(2, {3, 4})]
        )

        # O at mid-screen: scroll shifts cursor row and below down,
        # only new empty line needs rendering.
        self.run_test_screen(
            "Scroll opt: O at mid-screen uses scroll",
            make_lines(15),
            b"jjjO\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, ""),
                (4, "Line 4"), (5, "Line 5"), (6, "Line 6"),
                (7, "Line 7"), (8, "Line 8"),
            ],
            expect_cursor=(3, 0),
            # Frame 2 (O): new line row + row above
            expect_content_rows=[(2, {2, 3})]
        )

        # p (line paste below) at mid-screen uses scroll
        # Frames: 0=initial, 1=jjj cursor, 2=yy status, 3=p scroll
        self.run_test_screen(
            "Scroll opt: p (line paste) uses scroll",
            make_lines(15),
            b"jjjyyp:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 4"),
                (5, "Line 5"), (6, "Line 6"), (7, "Line 7"),
                (8, "Line 8"),
            ],
            expect_cursor=(4, 0),
            # Frame 3 (p): pasted row + row above
            expect_content_rows=[(3, {3, 4})]
        )

        # J at mid-screen: join decreases LINE_COUNT16, scroll shifts up.
        # Frames: 0=initial, 1=jjj cursor, 2=J scroll frame
        self.run_test_screen(
            "Scroll opt: J at mid-screen uses scroll",
            make_lines(15),
            b"jjjJ:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4 Line 5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            # Frame 2 (J): cursor row (content changed) + bottom row
            expect_content_rows=[(2, {3, 8})]
        )

        # J at mid-screen: scroll region should NOT include the cursor row.
        # The cursor row content changes (gains joined text) and gets re-rendered,
        # so scrolling it first causes a visible glitch.
        # Scroll region should be rows 4-8 (0-based), not 3-8.
        # Frames: 0=initial, 1=jjj cursor, 2=J scroll frame
        self.run_test_screen(
            "Scroll opt: J at mid-screen does not scroll cursor row",
            make_lines(15),
            b"jjjJ:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4 Line 5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            # Frame 2 (J): scroll region should be rows 4-8, NOT 3-8
            expect_scroll_rows=[(2, {4, 5, 6, 7, 8})]
        )

        # J redo at mid-screen: scroll region should NOT include the cursor row.
        # Sequence: J, u (undo), space (break u-batching), u (redo).
        # Frames: 0=initial, 1=jjj cursor, 2=J, 3=u (undo), 4=space (status),
        #         5=u (redo)
        self.run_test_screen(
            "Scroll opt: J redo does not scroll cursor row",
            make_lines(15),
            b"jjjJu u:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4 Line 5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            # Frame 5 (redo J): scroll region should be rows 4-8, NOT 3-8
            expect_scroll_rows=[(5, {4, 5, 6, 7, 8})]
        )

        # J on wrapped cursor line: both wrap rows must show correct content.
        # Line 2 = "This is a longer line!" (22 chars, wraps at 20 cols = 2 rows).
        # After J, line 2 = "This is a longer line! Short 4" (30 chars, still 2 rows).
        # Frames: 0=initial, 1=jj cursor, 2=J scroll frame
        wrap_j_content = ("Short 1\nShort 2\n"
                          "This is a longer line!\n"
                          + ''.join(f"Short {i}\n" for i in range(4, 15)))
        self.run_test_screen(
            "Scroll opt: J on wrapped cursor line correct content",
            wrap_j_content,
            b"jjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "This is a longer lin"),
                (3, "e! Short 4"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
        )

        # J on wrapped cursor line: scroll region must skip ALL cursor line rows.
        # Cursor line occupies rows 2-3 (0-based). Scroll should be rows 4-8.
        self.run_test_screen(
            "Scroll opt: J on wrapped cursor line scroll region",
            wrap_j_content,
            b"jjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "This is a longer lin"),
                (3, "e! Short 4"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(2, {4, 5, 6, 7, 8})]
        )

        # J redo on wrapped cursor line: scroll region must skip wrap rows.
        # Sequence: J, u (undo), space (break u-batching), u (redo).
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u (undo), 4=space, 5=u (redo)
        self.run_test_screen(
            "Scroll opt: J redo on wrapped cursor line scroll region",
            wrap_j_content,
            b"jjJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "This is a longer lin"),
                (3, "e! Short 4"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(5, {4, 5, 6, 7, 8})]
        )

        # J undo on wrapped cursor line: after undo, screen should return
        # to the original layout. The scroll region must skip ALL cursor
        # line wrap rows, not just one — otherwise the wrap continuation
        # gets pushed down and appears duplicated below the restored line.
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u (undo)
        self.run_test_screen(
            "Scroll opt: J undo on wrapped cursor line correct content",
            wrap_j_content,
            b"jjJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "This is a longer lin"),
                (3, "e!"),
                (4, "Short 4"), (5, "Short 5"),
                (6, "Short 6"), (7, "Short 7"),
                (8, "Short 8"),
            ],
            expect_cursor=(2, 0),
        )

        # J undo where result was wrapped: J joins "A" with
        # "123456789012345678901" (21 chars) producing "A 123..." (23 chars)
        # which wraps to 2 rows. Undo restores original 3 lines, cursor line
        # "A" shrinks from 2 wrapped rows to 1 row, so lines below must
        # scroll down to fill the gap.
        # Frames: 0=initial, 1=J, 2=u (undo)
        self.run_test_screen(
            "Scroll opt: J undo unwraps result scrolls lines below",
            "A\n123456789012345678901\nB\n",
            b"Ju:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A"),
                (1, "12345678901234567890"),
                (2, "1"),
                (3, "B"),
            ],
            expect_cursor=(0, 0),
            expect_scroll_rows=[(2, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # J undo unwraps at mid-screen: cursor at row 3, J joins "A" with
        # "123456789012345678901" (21 chars) producing wrapped result (2 rows).
        # Before J: A(1) + 123...(2) = 3 rows. After J: 2 rows. Undo: back to 3.
        # Scroll region should start below cursor row 3, not at cursor.
        # Frames: 0=initial, 1=jjj cursor, 2=J, 3=u (undo)
        undo_unwrap_mid = ("Short 1\nShort 2\nShort 3\n"
                           "A\n123456789012345678901\nB\n"
                           + ''.join(f"Short {i}\n" for i in range(7, 15)))
        self.run_test_screen(
            "Scroll opt: J undo unwraps at mid-screen",
            undo_unwrap_mid,
            b"jjjJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"), (2, "Short 3"),
                (3, "A"),
                (4, "12345678901234567890"),
                (5, "1"),
                (6, "B"),
                (7, "Short 7"), (8, "Short 8"),
            ],
            expect_cursor=(3, 0),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})]
        )

        # J undo restores wrapped next line: J on "Short" joins with
        # "This is a longer line!" (22 chars, wraps to 2 rows at 20 cols).
        # Result "Short This is a longer line!" (28 chars, 2 rows).
        # Before: 1+2=3 rows, After J: 2 rows (freed 1). Undo: back to 3 rows.
        # Lines below must scroll down 1 to restore the wrapped line.
        # Frames: 0=initial, 1=j cursor, 2=J, 3=u (undo)
        undo_restore_wrap = ("Short 1\n"
                             "Short\nThis is a longer line!\nMore\n"
                             + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: J undo restores wrapped next line",
            undo_restore_wrap,
            b"jJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short"),
                (2, "This is a longer lin"),
                (3, "e!"),
                (4, "More"),
                (5, "Short 5"), (6, "Short 6"),
                (7, "Short 7"), (8, "Short 8"),
            ],
            expect_cursor=(1, 0),
            expect_scroll_rows=[(3, {2, 3, 4, 5, 6, 7, 8})]
        )

        # J undo same height no scroll: J joins two non-wrapped lines
        # "Almost full width!!" (19) + " " + "X" = 21 chars, wraps to 2 rows.
        # Before: 1+1=2 rows. After J: 2 rows (wrap). Undo: back to 2 rows.
        # No net height change, so no scroll needed.
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u (undo)
        undo_same_height = ("Short 1\nShort 2\n"
                            "Almost full width!!\nX\n"
                            + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: J undo same height no scroll",
            undo_same_height,
            b"jjJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Almost full width!!"),
                (3, "X"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(3, set())],
            # No scroll, only cursor line (row 2) + restored line (row 3) repainted
            expect_content_rows=[(3, {2, 3})]
        )

        # J forward scroll down when line grows: both lines are exactly
        # screen width (20 chars). J joins them with a space, producing a
        # 41-char line (3 rows vs original 2). Scroll DOWN to make room.
        # Scroll region: rows below old content (0-based rows 4-8).
        # Frames: 0=initial, 1=jj cursor, 2=J
        j_grow_content = ("Short 1\nShort 2\n"
                          "12345678901234567890\n12345678901234567890\n"
                          + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: J forward scroll down when line grows",
            j_grow_content,
            b"jjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "12345678901234567890"),
                (3, " 1234567890123456789"),
                (4, "0"),
                (5, "Short 5"), (6, "Short 6"),
                (7, "Short 7"), (8, "Short 8"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(2, {4, 5, 6, 7, 8})],
            # Only cursor line's 3 wrap rows repainted; rows 5-8 handled by scroll
            expect_content_rows=[(2, {2, 3, 4})]
        )

        # J undo negative displacement scroll up: undo of the above J.
        # Joined line was 3 rows, restored to two 1-row lines. Scroll UP
        # to fill freed rows. Scroll region: below old joined line end
        # (0-based rows 5-8).
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u (undo)
        self.run_test_screen(
            "Scroll opt: J undo negative displacement scroll up",
            j_grow_content,
            b"jjJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "12345678901234567890"),
                (3, "12345678901234567890"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})],
            # Only cursor line (row 2) + restored line (row 3) + bottom exposed (row 8)
            expect_content_rows=[(3, {2, 3, 8})]
        )

        # J redo scroll down when line grows: same as J forward, but via
        # undo then redo (J, u, space, u). Scroll DOWN on redo frame.
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u, 4=space (noop), 5=u (redo)
        self.run_test_screen(
            "Scroll opt: J redo scroll down when line grows",
            j_grow_content,
            b"jjJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "12345678901234567890"),
                (3, " 1234567890123456789"),
                (4, "0"),
                (5, "Short 5"), (6, "Short 6"),
                (7, "Short 7"), (8, "Short 8"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(5, {4, 5, 6, 7, 8})],
            # Only cursor line's 3 wrap rows repainted; rows 5-8 handled by scroll
            expect_content_rows=[(5, {2, 3, 4})]
        )

        # J undo where cursor line stays wrapped: cursor line
        # "This is a longer line!" (22 chars, wraps to 2 rows) joins with
        # "Short 4". Result: "This is a longer line! Short 4" (30 chars,
        # still 2 rows). Undo restores "Short 4" as separate line.
        # Before J: 2+1=3 rows. After J: 2 rows. Undo: back to 3 rows.
        # Cursor line remains wrapped (2 rows), so scroll region must
        # start below BOTH cursor wrap rows.
        # Frames: 0=initial, 1=jj cursor, 2=J, 3=u (undo)
        self.run_test_screen(
            "Scroll opt: J undo cursor stays wrapped scroll region",
            wrap_j_content,
            b"jjJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "This is a longer lin"),
                (3, "e!"),
                (4, "Short 4"), (5, "Short 5"),
                (6, "Short 6"), (7, "Short 7"),
                (8, "Short 8"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})]
        )

        # JJ undo restores wrapped line: JJ joins Short 2 + "This is a
        # longer line!" (wraps) + Short 4. Undo of last J restores Short 4,
        # leaving "Short 2 This is a longer line!" (30 chars, 2 rows).
        # Before undo: 2 rows. After undo: 2+1=3 rows. Lines below scroll down.
        # Cursor line wraps, so scroll region must skip cursor wrap rows.
        # Frames: 0=initial, 1=j cursor, 2=JJ, 3=u (undo of second J)
        self.run_test_screen(
            "Scroll opt: JJ undo restores line below wrapped result",
            wrap_j_content,
            b"jJJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line!"),
                (3, "Short 4"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(1, 0),
            expect_scroll_rows=[(3, {3, 4, 5, 6, 7, 8})]
        )

        # JJ undo unwraps cursor line: JJ joins A + B + "123456789012345678901"
        # (21 chars). Result "A B 123456789012345678901" (25 chars, wraps to 2
        # rows). Undo of last J: "A B" (3 chars, 1 row) + "123..." (21 chars,
        # 2 rows) = 3 rows vs 2 rows before undo.
        # Cursor line shrinks from 2 wrap rows to 1 non-wrapped row.
        # Frames: 0=initial, 1=JJ, 2=u (undo of second J)
        jj_undo_unwrap = ("A\nB\n123456789012345678901\nC\n"
                          + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: JJ undo unwraps cursor line",
            jj_undo_unwrap,
            b"JJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A B"),
                (1, "12345678901234567890"),
                (2, "1"),
                (3, "C"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(0, 0),
            expect_scroll_rows=[(2, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # JJ undo partially unwraps cursor line: JJ joins A +
        # "BBBBBBBBBBBBBBBBBBB" (19 chars) + "123456789012345678901" (21 chars).
        # Result: "A BBBBBBBBBBBBBBBBBBB 123456789012345678901" (43 chars,
        # wraps to 3 rows). Undo of last J: "A BBBBBBBBBBBBBBBBBBB" (21 chars,
        # 2 rows) + "123..." (21 chars, 2 rows) = 4 rows vs 3 rows before undo.
        # Cursor line goes from 3 wrap rows to 2 wrap rows. Scroll region must
        # skip both remaining cursor wrap rows.
        # Frames: 0=initial, 1=JJ, 2=u (undo of second J)
        jj_undo_partial = ("A\nBBBBBBBBBBBBBBBBBBB\n123456789012345678901\nC\n"
                           + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: JJ undo partially unwraps cursor line",
            jj_undo_partial,
            b"JJu:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "A BBBBBBBBBBBBBBBBBB"),
                (1, "B"),
                (2, "12345678901234567890"),
                (3, "1"),
                (4, "C"),
                (5, "Short 5"), (6, "Short 6"),
                (7, "Short 7"), (8, "Short 8"),
            ],
            expect_cursor=(0, 0),
            expect_scroll_rows=[(2, {2, 3, 4, 5, 6, 7, 8})]
        )

        # J joining next wrapped line: when B wraps, ALL of B's rows need
        # repainting since B's content reflows into A. The scroll region must
        # not include B's wrap rows — otherwise stale wrap content appears.
        # Setup: cursor on "Short 2" (non-wrapped), next line wraps to 2 rows.
        # After J: "Short 2 This is a longer line!" wraps to 2 rows.
        # Frames: 0=initial, 1=j cursor, 2=J
        self.run_test_screen(
            "Scroll opt: J joining next wrapped line correct content",
            wrap_j_content,
            b"jJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line!"),
                (3, "Short 4"), (4, "Short 5"),
                (5, "Short 6"), (6, "Short 7"),
                (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(1, 0),
        )

        # J that causes line to wrap: joining non-wrapped A with non-wrapped B
        # produces a wrapped result occupying the same vertical space (2 rows)
        # as A+B individually (1+1). No scroll needed — just repaint.
        # "Almost full width!!" (19 chars) + " " + "XY" = 22 chars, wraps at 20.
        # Frames: 0=initial, 1=jj cursor, 2=J
        join_becomes_wrap = ("Short 1\nShort 2\n"
                             "Almost full width!!\n"
                             "XY\n"
                             + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: J result wraps same height no scroll",
            join_becomes_wrap,
            b"jjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Almost full width!!"),
                (3, "XY"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(2, set())],
            # No scroll, only cursor line's 2 wrap rows repainted
            expect_content_rows=[(2, {2, 3})]
        )

        # JJ (2 batched joins) where first joined line B is wrapped:
        # joins Short 2 + "This is a longer line!" (wraps) + Short 4.
        # Result: "Short 2 This is a longer line! Short 4" (38 chars, 2 rows).
        # Before: 1+2+1 = 4 rows. After: 2 rows. Freed: 2.
        # Frames: 0=initial, 1=j cursor, 2=JJ
        self.run_test_screen(
            "Scroll opt: JJ first joined line wrapped",
            wrap_j_content,
            b"jJJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line! Short 4"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
            # Only cursor line's 2 wrap rows + bottom exposed rows repainted
            expect_content_rows=[(2, {1, 2, 7, 8})]
        )

        # JJ (2 batched joins) where second joined line C is wrapped:
        # joins Short 2 + "and" + "This is a longer line!" (wraps).
        # Result: "Short 2 and This is a longer line!" (34 chars, 2 rows).
        # Before: 1+1+2 = 4 rows. After: 2 rows. Freed: 2.
        # Frames: 0=initial, 1=j cursor, 2=JJ
        join_c_wrapped = ("Short 1\n"
                          "Short 2\n"
                          "and\n"
                          "This is a longer line!\n"
                          + ''.join(f"Short {i}\n" for i in range(5, 15)))
        self.run_test_screen(
            "Scroll opt: JJ second joined line wrapped",
            join_c_wrapped,
            b"jJJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 and This is"),
                (2, "a longer line!"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
            # Only cursor line's 2 wrap rows + bottom exposed rows repainted
            expect_content_rows=[(2, {1, 2, 7, 8})]
        )

        # JJ (2 batched joins) all non-wrapped, result wraps to same height:
        # 3 lines of 1 row each become 1 line wrapping to 3 rows. No scroll.
        # "First longer line!!" (19) + " " + "Second longer line!" (19)
        # + " " + "Third!" (6) = 46 chars -> 3 rows at 20 cols.
        # Frames: 0=initial, 1=jj cursor, 2=JJ
        join_3_same_height = ("Short 1\nShort 2\n"
                              "First longer line!!\n"
                              "Second longer line!\n"
                              "Third!\n"
                              + ''.join(f"Short {i}\n" for i in range(6, 15)))
        self.run_test_screen(
            "Scroll opt: JJ result wraps same height no scroll",
            join_3_same_height,
            b"jjJJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "First longer line!!"),
                (3, "Second longer line!"),
                (4, "Third!"),
                (5, "Short 6"), (6, "Short 7"),
                (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(2, set())]
        )

        # JJ (2 batched joins) result wraps, partial height reduction:
        # 3 non-wrapped lines (3 rows) become 1 line wrapping to 2 rows.
        # Freed 1 row, but file delta = 2. SCROLL_DELTA must not overcount.
        # "Almost full width!!" (19) + " " + "XY" (2) + " " + "Z" (1) = 24 chars.
        # Frames: 0=initial, 1=jj cursor, 2=JJ
        join_jj_partial = ("Short 1\nShort 2\n"
                           "Almost full width!!\n"
                           "XY\n"
                           "Z\n"
                           + ''.join(f"Short {i}\n" for i in range(6, 15)))
        self.run_test_screen(
            "Scroll opt: JJ result wraps partial height reduction",
            join_jj_partial,
            b"jjJJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Almost full width!!"),
                (3, "XY Z"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(2, 0),
        )

        # JJJ (3 batched joins) with wrapped line among those joined:
        # joins Short 2 + "This is a longer line!" (wraps) + Short 4 + Short 5.
        # Result: 46 chars, 3 rows at 20 cols.
        # Before: 1+2+1+1 = 5 rows. After: 3 rows. Freed: 2.
        # File delta = 3 but actual SCROLL_DELTA should be 2.
        # Frames: 0=initial, 1=j cursor, 2=JJJ
        self.run_test_screen(
            "Scroll opt: JJJ with wrapped line among joined",
            wrap_j_content,
            b"jJJJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line! Short 4 S"),
                (3, "hort 5"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
        )

        # J with following line off-screen: cursor near bottom, joined line wraps,
        # following line was off-screen but should become visible after join frees rows.
        join_offscreen = ("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\n"
                          "Short 7\nThis is a longer line!\nLine 9\nLine 10\n")
        self.run_test_screen(
            "Scroll opt: J with following line off screen",
            join_offscreen,
            b"jjjjjjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"),
                (2, "Line 3"), (3, "Line 4"),
                (4, "Line 5"), (5, "Line 6"),
                (6, "Short 7 This is a lo"),
                (7, "nger line!"),
                (8, "Line 9"),
            ],
            expect_cursor=(6, 0),
        )

        # J at end of file: joining the last two lines, no following line.
        # Row after combined line should show ~ (EOF tilde).
        join_eof = ("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\n"
                    "Short 8\nEnd\n")
        self.run_test_screen(
            "Scroll opt: J at EOF no following line",
            join_eof,
            b"jjjjjjjJ:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"),
                (2, "Line 3"), (3, "Line 4"),
                (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"),
                (7, "Short 8 End"),
                (8, "~"),
            ],
            expect_cursor=(7, 0),
        )

        # --- Redo counterparts for all J scroll tests ---
        # Each uses "Ju u" pattern: J, u (undo), space (break batching), u (redo).
        # Space is unmapped in normal mode, so cursor stays at col 0.

        self.run_test_screen(
            "Redo: J joining next wrapped line",
            wrap_j_content,
            b"jJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line!"),
                (3, "Short 4"), (4, "Short 5"),
                (5, "Short 6"), (6, "Short 7"),
                (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(1, 0),
        )

        self.run_test_screen(
            "Redo: J result wraps same height no scroll",
            join_becomes_wrap,
            b"jjJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Almost full width!!"),
                (3, "XY"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(5, set())],
            # No scroll, only cursor line's 2 wrap rows repainted
            expect_content_rows=[(5, {2, 3})]
        )

        self.run_test_screen(
            "Redo: JJ first joined line wrapped",
            wrap_j_content,
            b"jJJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line! Short 4"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
            # Redo re-joins 1 line (batched JJ records UNDO_JOIN_COUNT=1):
            # cursor wrap rows (1,2) + 1 bottom exposed row (8)
            expect_content_rows=[(5, {1, 2, 8})]
        )

        self.run_test_screen(
            "Redo: JJ second joined line wrapped",
            join_c_wrapped,
            b"jJJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 and This is"),
                (2, "a longer line!"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
            # Redo re-joins 1 line (batched JJ records UNDO_JOIN_COUNT=1):
            # cursor wrap rows (1,2) + 1 bottom exposed row (8)
            expect_content_rows=[(5, {1, 2, 8})]
        )

        self.run_test_screen(
            "Redo: JJ result wraps same height no scroll",
            join_3_same_height,
            b"jjJJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "First longer line!!"),
                (3, "Second longer line!"),
                (4, "Third!"),
                (5, "Short 6"), (6, "Short 7"),
                (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(2, 0),
            expect_scroll_rows=[(5, set())],
            # No scroll, only cursor line's 3 wrap rows repainted
            expect_content_rows=[(5, {2, 3, 4})]
        )

        self.run_test_screen(
            "Redo: JJ result wraps partial height reduction",
            join_jj_partial,
            b"jjJJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Almost full width!!"),
                (3, "XY Z"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(2, 0),
        )

        self.run_test_screen(
            "Redo: JJJ with wrapped line among joined",
            wrap_j_content,
            b"jJJJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"),
                (1, "Short 2 This is a lo"),
                (2, "nger line! Short 4 S"),
                (3, "hort 5"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(1, 0),
        )

        self.run_test_screen(
            "Redo: J with following line off screen",
            join_offscreen,
            b"jjjjjjJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"),
                (2, "Line 3"), (3, "Line 4"),
                (4, "Line 5"), (5, "Line 6"),
                (6, "Short 7 This is a lo"),
                (7, "nger line!"),
                (8, "Line 9"),
            ],
            expect_cursor=(6, 0),
        )

        self.run_test_screen(
            "Redo: J at EOF no following line",
            join_eof,
            b"jjjjjjjJu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"),
                (2, "Line 3"), (3, "Line 4"),
                (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"),
                (7, "Short 8 End"),
                (8, "~"),
            ],
            expect_cursor=(7, 0),
        )

        # 3J at mid-screen: joins 2 lines, scroll shifts up by 2.
        # Frames: 0=initial, 1='3' count display, 2=jjj cursor, 3=J scroll
        self.run_test_screen(
            "Scroll opt: 3J at mid-screen uses scroll",
            make_lines(15),
            b"jjj3J:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4 Line 5 Line 6"), (4, "Line 7"),
                (5, "Line 8"), (6, "Line 9"), (7, "Line 10"),
                (8, "Line 11"),
            ],
            expect_cursor=(3, 0),
            # Frame 3 (3J): cursor row + bottom 2 rows
            expect_content_rows=[(3, {3, 7, 8})]
        )

        # 3J where result wraps: 3 non-wrapped lines (3 rows) become 1 wrapped
        # line (2 rows). Freed 1 row, scroll shifts up by 1.
        # "Short 3" (7) + " " + "Short 4" (7) + " " + "Short 5" (7) = 23 chars,
        # wraps to 2 rows at 20 cols.
        # Frames: 0=initial, 1='3' count display, 2=jj cursor, 3=J scroll
        content_3j_wrap = ("Short 1\nShort 2\n"
                           "Short 3\nShort 4\nShort 5\n"
                           + ''.join(f"Short {i}\n" for i in range(6, 15)))
        self.run_test_screen(
            "Scroll opt: 3J wrapping result uses scroll",
            content_3j_wrap,
            b"jj3J:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Short 3 Short 4 Shor"),
                (3, "t 5"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(2, 0),
            # Only cursor line's 2 wrap rows + bottom row exposed by scroll
            expect_content_rows=[(3, {2, 3, 8})]
        )

        # 3J wrapping redo: same result as forward, via undo then redo.
        # Frames: 0=initial, 1='3' count, 2=jj, 3=J, 4=u, 5=space, 6=u (redo)
        self.run_test_screen(
            "Redo: 3J wrapping result uses scroll",
            content_3j_wrap,
            b"jj3Ju u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"),
                (2, "Short 3 Short 4 Shor"),
                (3, "t 5"),
                (4, "Short 6"), (5, "Short 7"),
                (6, "Short 8"), (7, "Short 9"),
                (8, "Short 10"),
            ],
            expect_cursor=(2, 0),
            # Only cursor line's 2 wrap rows + bottom row exposed by scroll
            expect_content_rows=[(6, {2, 3, 8})]
        )

        # 3cc at mid-screen: deletes 3 lines, inserts blank, scroll shifts up.
        # Net LINE_COUNT16 decrease = 2. Frames: 0=initial, 1='3' count,
        # 2=jjj cursor, 3=cc scroll frame
        self.run_test_screen(
            "Scroll opt: 3cc at mid-screen uses scroll",
            make_lines(15),
            b"jjj3cc\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, ""), (4, "Line 7"),
                (5, "Line 8"), (6, "Line 9"), (7, "Line 10"),
                (8, "Line 11"),
            ],
            expect_cursor=(3, 0),
            # Frame 3 (3cc): cursor row + bottom 2 rows
            expect_content_rows=[(3, {3, 7, 8})]
        )

        # Enter in insert mode at mid-line: splits line, LINE_COUNT16 increases.
        # Frames: 0=initial, 1=jjj cursor, 2=llll cursor,
        #         3=i mode switch, 4=Enter scroll frame
        # "llll" moves to col 4 in "Line 4", Enter splits to "Line" / " 4"
        self.run_test_screen(
            "Scroll opt: Enter in insert mode uses scroll",
            make_lines(15),
            b"jjjlllli\r\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line"), (4, " 4"),
                (5, "Line 5"), (6, "Line 6"), (7, "Line 7"),
                (8, "Line 8"),
            ],
            expect_cursor=(4, 0),
            # Frame 4 (Enter): split row above + new row
            expect_content_rows=[(4, {3, 4})]
        )

        # Enter at start of wrapped line: inserts blank above, content shifts down.
        # The wrapped continuation must not be duplicated as a ghost row.
        # Frames: 0=initial, 1=i mode switch, 2=Enter scroll frame, 3=ESC
        self.run_test_screen(
            "Scroll opt: Enter above wrapped line no ghost row",
            "The quick brown fox jumps over the lazy dog. Once upon a time\n",
            b"i\r\x1b:q!\r",
            rows=10, cols=50,
            expect_lines=[
                (0, ""),
                (1, "The quick brown fox jumps over the lazy dog. Once"),
                (2, "upon a time"),
                (3, "~"),
            ],
            expect_cursor=(1, 0),
        )

        # Enter at end of wrapped line: cursor was at wrap row 1 (end of line).
        # After Enter, blank line appears below the wrapped line.
        # The wrap continuation row must not be overwritten with wrap row 0 content.
        self.run_test_screen(
            "Scroll opt: Enter at end of wrapped line no overwrite",
            "The quick brown fox jumps over the lazy dog. Once upon a time\n",
            b"A\r\x1b:q!\r",
            rows=10, cols=50,
            expect_lines=[
                (0, "The quick brown fox jumps over the lazy dog. Once"),
                (1, "upon a time"),
                (2, ""),
                (3, "~"),
            ],
            expect_cursor=(2, 0),
        )

        # BS at col 0 below a wrapped line: joins with previous (wrapped) line.
        # The cursor ends up on a wrap continuation row. The re-render of the
        # cursor row must not overwrite with wrap row 0 content.
        self.run_test_screen(
            "Scroll opt: BS below wrapped line no overwrite",
            "The quick brown fox jumps over the lazy dog. Once upon a time\nhello\n",
            b"ji\x08\x1b:q!\r",
            rows=10, cols=50,
            expect_lines=[
                (0, "The quick brown fox jumps over the lazy dog. Once"),
                (1, "upon a timehello"),
                (2, "~"),
            ],
        )

        # BS at col 0 in insert mode: joins with previous line, LINE_COUNT16 decreases.
        # Cursor was at line 3 (Line 4), col 0. BS joins with line 2 (Line 3).
        # Frames: 0=initial, 1=jjj cursor, 2=i mode switch, 3=BS scroll frame
        self.run_test_screen(
            "Scroll opt: BS at col 0 in insert mode uses scroll",
            make_lines(15),
            b"jjji\x08\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"),
                (2, "Line 3Line 4"), (3, "Line 5"), (4, "Line 6"),
                (5, "Line 7"), (6, "Line 8"), (7, "Line 9"),
                (8, "Line 10"),
            ],
            expect_cursor=(2, 5),
            # Frame 3 (BS): cursor row (content changed) + bottom row
            expect_content_rows=[(3, {2, 8})]
        )

        # BS at col 0 joining with line that creates a wrapped result.
        # Line 0: "This is 20 char line" (20 chars = 1 row at 20 cols).
        # Line 1: "end" (3 chars = 1 row). BS at col 0 joins them.
        # Merged: "This is 20 char lineend" (23 chars = 2 rows at 20 cols).
        # Old total = 1+1 = 2, new total = 2. Displacement = 0.
        # File delta = 1. Current code scrolls by 1 (wrong), should not scroll.
        # After ESC: cursor col 20→19 (back one), wrap row 0 col 19.
        self.run_test_screen(
            "Scroll opt: BS creating wrap no displacement",
            "This is 20 char line\nend\nnext line\nanother\n",
            b"ji\x08\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "This is 20 char line"),
                (1, "end"),
                (2, "next line"),
                (3, "another"),
                (4, "~"),
            ],
            expect_cursor=(0, 19),
        )

        # BS at col 0 joining wrapped previous line.
        # Line 0: "This is a longer line!" (22 chars = 2 rows at 20 cols).
        # Line 1: "end" (3 chars = 1 row). BS at col 0 joins them.
        # Merged: "This is a longer line!end" (25 chars = 2 rows at 20 cols).
        # Old total = 2+1 = 3, new total = 2. Displacement = 1 = file delta.
        # After ESC: cursor col 22→21, wrap row 1 col 1.
        self.run_test_screen(
            "Scroll opt: BS joining with wrapped line",
            "This is a longer line!\nend\nnext line\nanother\n",
            b"ji\x08\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "This is a longer lin"),
                (1, "e!end"),
                (2, "next line"),
                (3, "another"),
                (4, "~"),
            ],
            expect_cursor=(1, 1),
        )

        # Enter in middle of wrapped line: total screen rows unchanged.
        # Line: "12345678901234567890abc" (23 chars = 2 rows at 20 cols).
        # 10 l's to col 10, i enters insert, iii types 3 chars, Enter splits.
        # "1234567890iii" (13, 1 row) + "1234567890abc" (13, 1 row) = 2 rows.
        # Old total = 2. Displacement = 0. SCROLL_DELTA=1 is wrong.
        self.run_test_screen(
            "Scroll opt: Enter on wrapped line no displacement",
            "12345678901234567890abc\nnext line\nanother\n",
            b"lllllllllliiii\r\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "1234567890iii"),
                (1, "1234567890abc"),
                (2, "next line"),
                (3, "another"),
                (4, "~"),
            ],
            expect_cursor=(1, 0),
        )

        # j past bottom with wrapped line between old/new VIEW_TOP.
        # Line 0 wraps (22 chars at 20 cols = 2 rows). When scrolling past it,
        # SCROLL_DELTA should accumulate 2 screen rows, not fall back.
        # Lines 1-19 are short (1 row each).
        wrap_content = ("This is a longer line!\n"
                        + ''.join(f"Short {i}\n" for i in range(1, 20)))
        self.run_test_screen(
            "Scroll opt: j past bottom with wrapped line uses scroll",
            wrap_content,
            b"j" * 9 + b":q!\r",
            rows=10, cols=20,
            # VIEW_TOP scrolls from 0 to 1 (past wrapping line 0 = 2 screen rows).
            # SCROLL_DELTA = 2 screen rows (line 0: 2 rows)
            expect_lines=[
                (0, "Short 1"), (1, "Short 2"), (2, "Short 3"),
                (3, "Short 4"), (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(8, 0),
            # Scroll optimization: only bottom 2 rows touched (not all 9)
            expect_content_rows=[(1, {7, 8})]
        )

        # k past top with wrapped line between old/new VIEW_TOP.
        # After scrolling down past the wrapping line, scroll back up.
        self.run_test_screen(
            "Scroll opt: k past top with wrapped line uses scroll",
            wrap_content,
            b"j" * 9 + b"k" * 9 + b":q!\r",
            rows=10, cols=20,
            # VIEW_TOP scrolls back from 1 to 0 (past wrapping line 0).
            # SCROLL_DELTA = 2 screen rows
            expect_lines=[
                (0, "This is a longer lin"), (1, "e!"),
                (2, "Short 1"), (3, "Short 2"), (4, "Short 3"),
                (5, "Short 4"), (6, "Short 5"), (7, "Short 6"),
                (8, "Short 7"),
            ],
            expect_cursor=(0, 0),
            # Scroll optimization: only top 2 rows touched (not all 9)
            expect_content_rows=[(2, {0, 1})]
        )

        # dd on a wrapped line: SCROLL_DELTA should be 2 (screen rows), not 1
        wrap_dd_content = ("Short 0\n"
                           "This is a longer line!\n"  # 22 chars at 20 cols = 2 rows
                           + ''.join(f"Short {i}\n" for i in range(2, 12)))
        self.run_test_screen(
            "Scroll opt: dd on wrapped line uses correct scroll",
            wrap_dd_content,
            b"jdd:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 0"), (1, "Short 2"), (2, "Short 3"),
                (3, "Short 4"), (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(1, 0),
            # Frame 2 (dd): cursor row 1 + bottom 2 rows (7, 8)
            expect_content_rows=[(2, {1, 7, 8})]
        )

        # p pasting a wrapped line: SCROLL_DELTA should be 2 (screen rows)
        wrap_p_content = ("This is a longer line!\n"  # wraps at 20 cols
                          + ''.join(f"Short {i}\n" for i in range(1, 12)))
        self.run_test_screen(
            "Scroll opt: p pasting wrapped line uses correct scroll",
            wrap_p_content,
            b"yyjjjp:q!\r",
            rows=10, cols=20,
            # yy yanks line 0 (wrapped). jjj to line 3 = "Short 3" at row 4.
            # p pastes below: new line 4 = "This is a longer line!" (2 screen rows).
            # SCROLL_DELTA should be 2.
            expect_lines=[
                (0, "This is a longer lin"), (1, "e!"),
                (2, "Short 1"), (3, "Short 2"), (4, "Short 3"),
                (5, "This is a longer lin"), (6, "e!"),
                (7, "Short 4"), (8, "Short 5"),
            ],
            expect_cursor=(5, 0),
            # Frame 3 (p): row above cursor (4) + 2 cursor rows (5, 6)
            expect_content_rows=[(3, {4, 5, 6})]
        )

        # pp batched paste of wrapped line: BATCH_EXTRA adjusts FILE_LINE16 past
        # first pasted lines, causing scroll walk to start at wrong position.
        # Without fix, row 4 shows stale content instead of COPY1 wrap row 0.
        self.run_test_screen(
            "Scroll opt: pp batched paste of wrapped line",
            wrap_p_content,
            b"yyjjpp:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "This is a longer lin"), (1, "e!"),
                (2, "Short 1"), (3, "Short 2"),
                (4, "This is a longer lin"), (5, "e!"),
                (6, "This is a longer lin"), (7, "e!"),
                (8, "Short 3"),
            ],
            expect_cursor=(6, 0),
        )

        # 2cc deleting lines including a wrapped line: displacement > file delta.
        # Lines: "Short 1" (1 row), "This is a longer line!" (2 rows at 20 cols).
        # 2cc: deletes both (3 screen rows), inserts blank (1 row).
        # File delta = 1, but actual displacement = 2.
        cc_wrap_content = ("Short 1\n"
                           "This is a longer line!\n"
                           + ''.join(f"Short {i}\n" for i in range(3, 12)))
        self.run_test_screen(
            "Scroll opt: 2cc on wrapped lines correct displacement",
            cc_wrap_content,
            b"2cc\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, ""),
                (1, "Short 3"), (2, "Short 4"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(0, 0),
        )

        # dd when replacement line wraps and cursor has WRAP_QUOT > 0.
        # Line 0: 25 chars (2 rows at 20 cols). Line 1: also 25 chars.
        # $ moves to col 24. dd deletes line 0. Replacement wraps.
        # clamp_cursor_col keeps col 24, WRAP_QUOT=1.
        # Bug: row 0 shows stale deleted content instead of replacement row 0.
        dd_wrap_replace = ("1234567890123456789012345\n"
                           "abcdefghijklmnopqrstuvwxy\n"
                           + ''.join(f"Short {i}\n" for i in range(3, 12)))
        self.run_test_screen(
            "Scroll opt: dd with wrapped replacement WRAP_QUOT>0",
            dd_wrap_replace,
            b"$dd:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "abcdefghijklmnopqrst"),
                (1, "uvwxy"),
                (2, "Short 3"), (3, "Short 4"),
                (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"),
                (8, "Short 9"),
            ],
            expect_cursor=(1, 4),
        )

        # Redo of 2cc on wrapped lines: same displacement issue.
        self.run_test_screen(
            "Redo: 2cc on wrapped lines correct displacement",
            cc_wrap_content,
            b"2cc\x1bu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, ""),
                (1, "Short 3"), (2, "Short 4"),
                (3, "Short 5"), (4, "Short 6"),
                (5, "Short 7"), (6, "Short 8"),
                (7, "Short 9"), (8, "Short 10"),
            ],
            expect_cursor=(0, 0),
        )

        # Redo of dd on wrapped line: missing pre-computation.
        # dd deletes wrapped line (2 rows), redo should use SCROLL_DELTA=2.
        self.run_test_screen(
            "Redo: dd on wrapped line correct displacement",
            wrap_dd_content,
            b"jddu u:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "Short 0"), (1, "Short 2"), (2, "Short 3"),
                (3, "Short 4"), (4, "Short 5"), (5, "Short 6"),
                (6, "Short 7"), (7, "Short 8"), (8, "Short 9"),
            ],
            expect_cursor=(1, 0),
        )

        # J on last visible line: joined line is off-screen, only cursor row redrawn.
        # rows=10 → 9 content rows (0-8), status on row 9.
        # jjjjjjjj = 8 j's → cursor at row 8 (Line 9). J joins off-screen Line 10.
        # Frames: 0=initial, 1=jjjjjjjj cursor, 2=J frame
        self.run_test_screen(
            "Scroll opt: J on last visible line minimal repaint",
            make_lines(15),
            b"j" * 8 + b"J:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (7, "Line 8"),
                (8, "Line 9 Line 10"),
            ],
            expect_cursor=(8, 0),
            # Frame 2 (J): only cursor row 8 redrawn, no scroll needed
            expect_content_rows=[(2, {8})],
            expect_scrolled_at_frame=[(2, False)]
        )

        # dd on last visible line: deleted line at bottom, only cursor row redrawn.
        # Cursor moves to next line (Line 10) which scrolls into view at row 8.
        # Frames: 0=initial, 1=jjjjjjjj cursor, 2=dd frame
        self.run_test_screen(
            "Scroll opt: dd on last visible line minimal repaint",
            make_lines(15),
            b"j" * 8 + b"dd:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (7, "Line 8"),
                (8, "Line 10"),
            ],
            expect_cursor=(8, 0),
            # Frame 2 (dd): only cursor row 8 redrawn
            expect_content_rows=[(2, {8})]
        )

        # J undo on last visible line: restore split line below (off-screen).
        # Frames: 0=initial, 1=jjjjjjjj cursor, 2=J frame, 3=u undo frame
        self.run_test_screen(
            "Scroll opt: J undo on last visible line minimal repaint",
            make_lines(15),
            b"j" * 8 + b"Ju:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (7, "Line 8"),
                (8, "Line 9"),
            ],
            expect_cursor=(8, 0),
            # Frame 3 (u): row above cursor (7) + cursor row (8)
            expect_content_rows=[(3, {7, 8})]
        )

        # J undo on wrapped last line: no scroll should happen.
        # Cursor line wraps (22 chars at 20 cols = 2 rows), filling rows 7-8.
        # J joins the off-screen line, u restores it. The insert scroll path
        # computes ANSI_ROW=CURSOR_ROW+2=9, ANSI_COL=SCREEN_ROWS-1=9, giving
        # a single-row scroll region [9;9r]. This scroll is unnecessary and
        # causes visible status bar artifacts on real terminals.
        # Frames: 0=initial, 1=jjjjjjj cursor, 2=J frame, 3=u undo frame
        wrap_undo_content = (''.join(f"L{i}\n" for i in range(1, 8))
                             + "This is a longer line!\n"
                             + "Next\nMore1\nMore2\n")
        self.run_test_screen(
            "Scroll opt: J undo on wrapped last line no scroll",
            wrap_undo_content,
            b"j" * 7 + b"Ju:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (7, "This is a longer lin"),
                (8, "e!"),
            ],
            expect_cursor=(7, 0),
            # Frame 3 (u): no scroll needed, just re-render
            expect_scrolled_at_frame=[(3, False)]
        )

        # J redo on last visible line: same as J, minimal repaint.
        # Frames: 0=initial, 1=jjjjjjjj cursor, 2=J, 3=u undo, 4=space noop, 5=u redo
        self.run_test_screen(
            "Scroll opt: J redo on last visible line minimal repaint",
            make_lines(15),
            b"j" * 8 + b"Ju u:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (7, "Line 8"),
                (8, "Line 9 Line 10"),
            ],
            expect_cursor=(8, 0),
            # Frame 5 (redo): only cursor row 8 redrawn
            expect_content_rows=[(5, {8})]
        )

        self._group("Scroll opt: charwise delete:", leading_blank=True)

        # Charwise deletes should NOT include cursor row in scroll region.
        # The cursor row content changes and gets repainted, but the scroll
        # should only cover rows BELOW the cursor row.

        # 2d$ at row 3 with col offset: deletes "e 4\nLine 5", merging remainder.
        # jjjll = line 3, col 2. 2d$ deletes from col 2 to EOL + next line.
        # Result: "Li" on line 3, "Line 6" on line 4.
        # Frames: 0=initial, 1=jjj cursor, 2=ll cursor, 3=count '2', 4=d$
        self.run_test_screen(
            "Scroll opt: 2d$ does not scroll cursor row",
            make_lines(15),
            b"jjjll2d$:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Li"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 1),
            # Scroll region: rows 4-8 (below cursor), NOT including row 3
            expect_scroll_rows=[(4, {4, 5, 6, 7, 8})]
        )

        # 2D at row 3: same as 2d$ from col 0, deletes current+next line content.
        # Result: empty line 3, "Line 6" on line 4.
        # Frames: 0=initial, 1=jjj cursor, 2=count '2', 3=D
        self.run_test_screen(
            "Scroll opt: 2D does not scroll cursor row",
            make_lines(15),
            b"jjj2D:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, ""), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})]
        )

        # Single d$ does NOT trigger scroll (no line count change, auto-detect handles it).
        # Frames: 0=initial, 1=d$ frame
        self.run_test_screen(
            "Scroll opt: single d$ no scroll just current line",
            make_lines(10),
            b"lld$:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Li")],
            expect_cursor=(0, 1),
            expect_scrolled_at_frame=[(1, False)]
        )

        # Cross-line de: cursor at "4" in "Line 4", de deletes to end of next word.
        # Result: line 3 = "Line  5"
        # Frames: 0=initial, 1=jjj, 2=lllll, 3=de
        self.run_test_screen(
            "Scroll opt: cross-line de does not scroll cursor row",
            make_lines(15),
            b"jjjlllllde:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line  5"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 5),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})]
        )

        # 2C (change to EOL multi-line): deletes 2 lines' content, enters insert.
        # ESC exits insert mode without typing.
        # Frames: 0=initial, 1=jjj, 2=count '2', 3=C (delete+insert), 4=ESC
        self.run_test_screen(
            "Scroll opt: 2C does not scroll cursor row",
            make_lines(15),
            b"jjj2C\x1b:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, ""), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 0),
            expect_scroll_rows=[(3, {4, 5, 6, 7, 8})]
        )

        # Undo of 2d$: restores deleted content, line count increases.
        # Undo uses line-insert scroll which pushes content down below cursor.
        # Cursor row content changes but should NOT be in scroll region (it'll be repainted).
        # Frames: 0=initial, 1=jjj, 2=ll, 3=count '2', 4=d$ (delete scroll), 5=u (insert scroll)
        self.run_test_screen(
            "Scroll opt: 2d$ undo does not scroll cursor row",
            make_lines(15),
            b"jjjll2d$u:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"), (7, "Line 8"), (8, "Line 9"),
            ],
            expect_cursor=(3, 2),
            expect_scroll_rows=[(5, {4, 5, 6, 7, 8})]
        )

        # Undo of 2D: same as 2d$ undo, cursor row should not be scrolled.
        # Frames: 0=initial, 1=jjj, 2=count '2', 3=D (delete scroll), 4=u (insert scroll)
        self.run_test_screen(
            "Scroll opt: 2D undo does not scroll cursor row",
            make_lines(15),
            b"jjj2Du:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"), (7, "Line 8"), (8, "Line 9"),
            ],
            expect_cursor=(3, 0),
            expect_scroll_rows=[(4, {4, 5, 6, 7, 8})]
        )

        # Undo of cross-line de: cursor row should not be scrolled.
        # Start at end of Line 4, de deletes to end of word spanning newline.
        # Frames: 0=initial, 1=jjj, 2=$ (end), 3=de (delete scroll), 4=u (insert scroll)
        self.run_test_screen(
            "Scroll opt: de undo does not scroll cursor row",
            make_lines(15),
            b"jjj$deu:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"), (7, "Line 8"), (8, "Line 9"),
            ],
            expect_cursor=(3, 5),
            expect_scroll_rows=[(4, {4, 5, 6, 7, 8})]
        )

        # Redo of 2d$: re-deletes, line count decreases.
        # Frames: 0=initial, 1=jjj, 2=ll, 3=count '2', 4=d$, 5=u, 6=space noop, 7=u redo
        self.run_test_screen(
            "Scroll opt: 2d$ redo does not scroll cursor row",
            make_lines(15),
            b"jjjll2d$u u:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Li"), (4, "Line 6"), (5, "Line 7"),
                (6, "Line 8"), (7, "Line 9"), (8, "Line 10"),
            ],
            expect_cursor=(3, 1),
            expect_scroll_rows=[(7, {4, 5, 6, 7, 8})]
        )

        self._group("Scroll opt: charwise paste:", leading_blank=True)

        # Multi-line char paste p: yank with 2D (charwise, multi-line), then paste.
        # Cursor row content changes (line splits) but should NOT be in scroll region.
        # Frames: 0=initial, 1=count '2', 2=D (scroll: charwise delete), 3=p (insert)
        self.run_test_screen(
            "Scroll opt: multi-line char paste p does not scroll cursor row",
            make_lines(15),
            b"2Dp:q!\r",
            rows=10, cols=40,
            expect_scroll_rows=[(3, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # Multi-line char paste P: same yank, P pastes before cursor.
        # Cursor row should NOT be in scroll region.
        # Frames: 0=initial, 1=count '2', 2=D (scroll), 3=P (insert)
        self.run_test_screen(
            "Scroll opt: multi-line char paste P does not scroll cursor row",
            make_lines(15),
            b"2DP:q!\r",
            rows=10, cols=40,
            expect_scroll_rows=[(3, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # Undo of multi-line char paste p: deletes pasted content, line count decreases.
        # Undo uses delete_at_cursor which should not scroll cursor row.
        # Frames: 0=initial, 1=count '2', 2=D (delete scroll), 3=p (insert scroll), 4=u (delete scroll)
        self.run_test_screen(
            "Scroll opt: char paste p undo does not scroll cursor row",
            make_lines(15),
            b"2Dpu:q!\r",
            rows=10, cols=40,
            expect_scroll_rows=[(4, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # Redo of multi-line char paste p: re-inserts content, line count increases.
        # Cursor row should NOT be in scroll region (it'll be repainted).
        # Frames: ...4=u undo, 5=space noop, 6=u redo
        self.run_test_screen(
            "Scroll opt: char paste p redo does not scroll cursor row",
            make_lines(15),
            b"2Dpu u:q!\r",
            rows=10, cols=40,
            expect_scroll_rows=[(6, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        # Redo of multi-line char paste P: same, cursor row not in scroll region.
        # Frames: 0=initial, 1=count '2', 2=D, 3=P, 4=u, 5=space, 6=u redo
        self.run_test_screen(
            "Scroll opt: char paste P redo does not scroll cursor row",
            make_lines(15),
            b"2DPu u:q!\r",
            rows=10, cols=40,
            expect_scroll_rows=[(6, {1, 2, 3, 4, 5, 6, 7, 8})]
        )

        self._group("Scroll opt: paste-below undo:", leading_blank=True)

        # yypu at row 3: paste-below adds line 4, undo removes it.
        # The undo scroll should NOT include cursor row 3 in the scroll region.
        # Cursor row didn't change content, so scrolling it causes a glitch.
        # Frames: 0=initial, 1=jjj, 2=yy, 3=p (insert scroll), 4=u (delete scroll)
        self.run_test_screen(
            "Scroll opt: yypu undo does not scroll cursor row",
            make_lines(15),
            b"jjjyypu:q!\r",
            rows=10, cols=40,
            expect_lines=[
                (0, "Line 1"), (1, "Line 2"), (2, "Line 3"),
                (3, "Line 4"), (4, "Line 5"), (5, "Line 6"),
                (6, "Line 7"), (7, "Line 8"), (8, "Line 9"),
            ],
            expect_cursor=(3, 0),
            # Frame 4 (u): scroll region should NOT include cursor row 3
            expect_scroll_rows=[(4, {4, 5, 6, 7, 8})],
            # Cursor row 3 should NOT be repainted (content unchanged)
            expect_content_rows=[(4, {8})]
        )

        self._group("Scroll opt: insert mode wrap:", leading_blank=True)

        # Typing at end of line past screen width: line wraps, LINE_COUNT16 increases.
        # Line 0: 18 chars at 20 cols (1 screen row). A=append at EOL, type "abc"
        # makes it 21 chars → wraps to 2 screen rows. Lines below should scroll down
        # via scroll optimization, not a full repaint.
        # Frames: 0=initial, 1=A enter insert, 2=typed chars (wrap occurs)
        ins_wrap_content = ("123456789012345678\n"
                            + ''.join(f"Line {i}\n" for i in range(2, 12)))
        self.run_test_screen(
            "Scroll opt: insert typing at EOL causes wrap uses scroll",
            ins_wrap_content,
            b"Aabc\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "123456789012345678ab"),
                (1, "c"),
                (2, "Line 2"), (3, "Line 3"), (4, "Line 4"),
                (5, "Line 5"), (6, "Line 6"), (7, "Line 7"),
                (8, "Line 8"),
            ],
            expect_cursor=(1, 0),
            # Frame 2 (typing): cursor row redrawn + scroll pushes lines down.
            # Only the new cursor rows (1, 1) should be content-rendered, not all rows.
            # Note that row 0 does not need to be touched since it is unmodified
            expect_content_rows=[(2, {1, 1})]
        )

        # Typing within a line past screen width: same wrap, different cursor position.
        # Line 0: 18 chars at 20 cols. lllll=col 5, i=insert, type 6 i's.
        # 18+6=24 chars → wraps to 2 screen rows (20+4). Subsequent lines scroll down.
        # After ESC, cursor backs up 1 to col 10.
        # Frames: 0=initial, 1=lllll cursor, 2=i enter insert, 3=typed chars (wrap)
        self.run_test_screen(
            "Scroll opt: insert typing mid-line causes wrap uses scroll",
            ins_wrap_content,
            b"llllliiiiiii\x1b:q!\r",
            rows=10, cols=20,
            expect_lines=[
                (0, "12345iiiiii678901234"),
                (1, "5678"),
                (2, "Line 2"), (3, "Line 3"), (4, "Line 4"),
                (5, "Line 5"), (6, "Line 6"), (7, "Line 7"),
                (8, "Line 8"),
            ],
            expect_cursor=(0, 10),
            # Frame 3 (typing): only cursor line rows (0, 1) content-rendered
            expect_content_rows=[(3, {0, 1})]
        )

        self._group("Sub-line render optimization:", leading_blank=True)

        # Normal r: replace at col 3, partial render from col 3
        # lll=move to col 3, rZ=replace with 'Z'
        # Frame 0=initial, 1=lll move, 2=rZ replace
        self.run_test_screen(
            "r replace: partial render from cursor col",
            "Hello World\n",
            b"lllrZ:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "HelZo World")],
            expect_min_col=[(2, 0, 3)],
            expect_max_col=[(2, 0, 3)]
        )

        # Normal ~: toggle case at col 3, partial render from col 3
        # lll=move to col 3, ~=toggle case
        # Frame 0=initial, 1=lll move, 2=~ toggle
        self.run_test_screen(
            "~ toggle case: partial render from cursor col",
            "Hello World\n",
            b"lll~:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "HelLo World")],
            expect_min_col=[(2, 0, 3)],
            expect_max_col=[(2, 0, 3)]
        )

        # Counted ~ at end of line: 3~ on "Hi" from col 0 toggles 'H','i'
        # then stops (can't advance past end). Should not write past EOL.
        # Frame 0=initial, 1=count '3' display, 2=~ operation
        self.run_test_screen(
            "~ counted at end of line: no garbage past EOL",
            "Hi\n",
            b"3~:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "hI")],
            expect_max_col=[(2, 0, 1)]
        )

        # Normal x: delete at col 3, partial render from col 3
        # lll=move to col 3, x=delete char
        # Frame 0=initial, 1=lll move, 2=x delete
        self.run_test_screen(
            "x delete: partial render from cursor col",
            "Hello World\n",
            b"lllx:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Helo World")],
            # Frame 2 is the delete; first affected col is 3
            expect_min_col=[(2, 0, 3)]
        )

        # Insert at end of line: only render from cursor position
        # A=append at EOL, type "world", ESC. 'Hello' is 5 chars,
        # so first affected col is 5. Frame 0=initial, 1=enter insert, 2=typed chars
        self.run_test_screen(
            "Insert at end of line: partial render from cursor col",
            "Hello\n",
            b"Aworld\x1b",
            rows=10, cols=40,
            expect_lines=[(0, "Helloworld")],
            # Frame 2 is the 'world' insert; row 0 should start at col 5
            expect_min_col=[(2, 0, 5)]
        )

        # Insert mid-line: render from affected column
        # lll=move to col 3, i=insert, type "XYZ", ESC
        # Frame 0=initial, 1=lll move, 2=i enter insert, 3=XYZ typed
        self.run_test_screen(
            "Insert mid-line: partial render from insert col",
            "Hello World\n",
            b"llliXYZ\x1b",
            rows=10, cols=40,
            expect_lines=[(0, "HelXYZlo World")],
            # Frame 3 is the insert; first affected col is 3
            expect_min_col=[(3, 0, 3)]
        )

        # Backspace mid-line: batched insert+BS renders from affected col
        # lll=col 3, i=insert, XY+BS batched → net insert "X" at col 3
        self.run_test_screen(
            "Backspace mid-line in insert mode: partial render",
            "Hello World\n",
            b"llliXY\x08\x1b",
            rows=10, cols=40,
            expect_lines=[(0, "HelXlo World")],
            # Frame 3 is the batched insert; first affected col is 3
            expect_min_col=[(3, 0, 3)]
        )

        self._group("Undo (u):", leading_blank=True)

        # dd undo: restore deleted line
        self.run_test(
            "dd undo restores deleted line",
            "Hello\nWorld\n",
            b"ddu:wq\r",
            expected_content="Hello\nWorld\n"
        )

        # dd undo then redo
        self.run_test(
            "dd undo then redo",
            "Hello\nWorld\n",
            b"ddu u:wq\r",
            expected_content="World\n"
        )

        # dd undo on last line
        self.run_test(
            "dd undo on last line of 3-line file",
            "A\nB\nC\n",
            b"jjddu:wq\r",
            expected_content="A\nB\nC\n"
        )

        # 2dd undo
        self.run_test(
            "2dd undo restores both lines",
            "A\nB\nC\n",
            b"2ddu:wq\r",
            expected_content="A\nB\nC\n"
        )

        # dd then dd then undo: first dd stays, second dd undone
        self.run_test(
            "dd dd u: first dd stays, second dd undone",
            "A\nB\nC\n",
            b"ddjddu:wq\r",
            expected_content="B\nC\n"
        )

        # dd then insert clears undo
        self.run_test(
            "dd then oNew ESC u: insert clears undo",
            "A\nB\n",
            b"ddoNew\x1bu:wq\r",
            expected_content="B\nNew\n"
        )

        # u with no prior edit is no-op
        self.run_test(
            "u with no prior edit is no-op",
            "Hello\n",
            b"u:wq\r",
            expected_content="Hello\n",
            expect_unmodified=True
        )

        self._group("Undo char-delete (x, D, dw, db, de):", leading_blank=True)

        # x undo
        self.run_test(
            "x undo restores deleted char",
            "Hello\n",
            b"xu:wq\r",
            expected_content="Hello\n"
        )

        # x undo then redo
        self.run_test(
            "x undo then redo",
            "Hello\n",
            b"xu u:wq\r",
            expected_content="ello\n"
        )

        # D undo at col 2
        self.run_test(
            "D undo at col 2",
            "Hello\n",
            b"llDu:wq\r",
            expected_content="Hello\n"
        )

        # dw undo
        self.run_test(
            "dw undo restores deleted word",
            "Hello World\n",
            b"dwu:wq\r",
            expected_content="Hello World\n"
        )

        # db undo
        self.run_test(
            "db undo restores deleted word backward",
            "Hello World\n",
            b"edbu:wq\r",
            expected_content="Hello World\n"
        )

        # de undo
        self.run_test(
            "de undo restores deleted word end",
            "Hello World\n",
            b"deu:wq\r",
            expected_content="Hello World\n"
        )

        # 3x undo
        self.run_test(
            "3x undo restores 3 deleted chars",
            "Hello\n",
            b"3xu:wq\r",
            expected_content="Hello\n"
        )

        # d$ undo
        self.run_test(
            "d$ undo restores deleted text",
            "Hello\n",
            b"lld$u:wq\r",
            expected_content="Hello\n"
        )

        # d$ undo then redo
        self.run_test(
            "d$ undo then redo",
            "Hello\n",
            b"lld$u u:wq\r",
            expected_content="He\n"
        )

        # 2D undo restores multi-line delete
        self.run_test(
            "2D undo restores multi-line",
            "Hello\nWorld\nFoo\n",
            b"ll2Du:wq\r",
            expected_content="Hello\nWorld\nFoo\n"
        )

        # d0 undo
        self.run_test(
            "d0 undo restores deleted text",
            "Hello\n",
            b"llld0u:wq\r",
            expected_content="Hello\n"
        )

        # y$ doesn't set undo (yank only)
        self.run_test(
            "y$ u is no-op (yank doesn't set undo)",
            "Hello\n",
            b"lly$u:wq\r",
            expected_content="Hello\n"
        )

        # S undo (goes through cc path)
        self.run_test(
            "S ESC undo restores line",
            "Hello\nWorld\n",
            b"S\x1bu:wq\r",
            expected_content="Hello\nWorld\n"
        )

        # 2S undo
        self.run_test(
            "2S ESC undo restores both lines",
            "Hello\nWorld\nFoo\n",
            b"2S\x1bu:wq\r",
            expected_content="Hello\nWorld\nFoo\n"
        )

        # 2S undo then redo
        self.run_test(
            "2S ESC uu re-substitutes",
            "Hello\nWorld\nFoo\n",
            b"2S\x1buu:wq\r",
            expected_content="\nFoo\n"
        )

        self._group("Undo change commands (clean insert exit):", leading_blank=True)

        # s + ESC without typing + undo
        self.run_test(
            "s ESC undo restores char",
            "Hello\n",
            b"s\x1bu:wq\r",
            expected_content="Hello\n"
        )

        # s + typing clears undo
        self.run_test(
            "sX ESC: typing clears undo",
            "Hello\n",
            b"sX\x1bu:wq\r",
            expected_content="Xello\n"
        )

        # cc + ESC + undo
        self.run_test(
            "cc ESC undo restores line",
            "Hello\nWorld\n",
            b"cc\x1bu:wq\r",
            expected_content="Hello\nWorld\n"
        )

        # cc undo when next line is blank
        self.run_test(
            "cc ESC undo preserves following blank line",
            "Hello\n\nWorld\n",
            b"cc\x1bu:wq\r",
            expected_content="Hello\n\nWorld\n"
        )

        # 2cc undo when following line is blank
        self.run_test(
            "2cc ESC undo preserves following blank line",
            "A\nB\n\nC\n",
            b"2cc\x1bu:wq\r",
            expected_content="A\nB\n\nC\n"
        )

        # 3cc undo when following line is blank
        self.run_test(
            "3cc ESC undo preserves following blank line",
            "A\nB\nC\n\nD\n",
            b"3cc\x1bu:wq\r",
            expected_content="A\nB\nC\n\nD\n"
        )

        # 2cc ESC undo: screen shows both restored lines
        self.run_test_screen(
            "2cc ESC undo: screen shows both restored lines",
            "Line 1\nLine 2\nLine 3\n",
            b"2cc\x1bu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Line 1"), (1, "Line 2"), (2, "Line 3")],
            expect_cursor=(0, 0),
        )

        # cc undo preserves mark below (undo must adjust marks when deleting blank)
        self.run_test_screen(
            "cc undo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggcc\x1bu'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(2, 0),  # mark on "C" = line 2 after undo
        )

        # cc redo preserves mark below (redo must adjust marks when inserting blank)
        self.run_test_screen(
            "cc redo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggcc\x1bu u'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(2, 0),  # mark on "C" = line 2 after redo
        )

        # dd undo preserves mark below
        self.run_test_screen(
            "dd undo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggddu'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(2, 0),  # mark on "C" = line 2 after undo
        )

        # dd redo preserves mark below
        self.run_test_screen(
            "dd redo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggddu u'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(1, 0),  # mark on "C" = line 1 after redo (A deleted)
        )

        # cc + typing clears undo
        self.run_test(
            "cc New ESC: typing clears undo",
            "Hello\nWorld\n",
            b"ccNew\x1bu:wq\r",
            expected_content="New\nWorld\n"
        )

        # C + ESC + undo
        self.run_test(
            "C ESC undo at col 2",
            "Hello\n",
            b"llC\x1bu:wq\r",
            expected_content="Hello\n"
        )

        # cw + ESC + undo
        self.run_test(
            "cw ESC undo restores word",
            "Hello World\n",
            b"cw\x1bu:wq\r",
            expected_content="Hello World\n"
        )

        self._group("Undo join (J):", leading_blank=True)

        # J undo: restore joined lines
        self.run_test(
            "J undo restores original lines",
            "Hello\nWorld\n",
            b"Ju:wq\r",
            expected_content="Hello\nWorld\n"
        )

        # J undo then redo
        self.run_test(
            "J undo then redo",
            "Hello\nWorld\n",
            b"Ju u:wq\r",
            expected_content="Hello World\n"
        )

        # 3J undo restores all 3 original lines (3J joins 2 lines)
        self.run_test(
            "3J undo restores all 3 original lines",
            "A\nB\nC\nD\n",
            b"3Ju:wq\r",
            expected_content="A\nB\nC\nD\n"
        )

        # 3J undo then redo
        self.run_test(
            "3J undo then redo",
            "A\nB\nC\nD\n",
            b"3Ju u:wq\r",
            expected_content="A B C\nD\n"
        )

        # J on last line is no-op, no undo state
        self.run_test(
            "J on last line is no-op",
            "Hello\n",
            b"Ju:wq\r",
            expected_content="Hello\n",
            expect_unmodified=True
        )

        # JJ batched: undo only undoes last join (second J)
        # A\nB\nC\n -> JJ batched -> A B C\n -> u -> A B\nC\n
        self.run_test(
            "JJ batched: undo only undoes last join",
            "A\nB\nC\n",
            b"JJ u:wq\r",
            expected_content="A B\nC\n"
        )

        # JJ batched: redo re-does the last join
        # A\nB\nC\n -> JJ -> A B C\n -> u -> A B\nC\n -> u -> A B C\n
        self.run_test(
            "JJ batched: redo re-joins",
            "A\nB\nC\n",
            b"JJ u u:wq\r",
            expected_content="A B C\n"
        )

        # J then other edit then undo: J not undoable (superseded)
        self.run_test(
            "J then x then u: J superseded by x",
            "AB\nCD\n",
            b"Jxu:wq\r",
            expected_content="AB CD\n"
        )

        # Join limit: 129J on 130-line file exceeds JOIN_UNDO_MAX (128)
        # Should show error and not modify buffer (keypress dismisses msg)
        content_130 = ''.join(f"{i}\n" for i in range(130))
        self.run_test(
            "129J exceeds limit: no modification",
            content_130,
            b"130J :wq\r",  # space dismisses error msg
            expected_content=content_130,
            expect_unmodified=True
        )

        # 128J should work fine (exactly at limit)
        content_129 = ''.join(f"{i}\n" for i in range(129))
        expected_128j = ' '.join(str(i) for i in range(129)) + '\n'
        self.run_test(
            "128J at limit succeeds",
            content_129,
            b"129J:wq\r",
            expected_content=expected_128j
        )

        # J undo preserves mark below
        # ma on C (line 2), go to line 0, J joins A+B, undo restores,
        # mark should still be on C (line 2)
        self.run_test_screen(
            "J undo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggJu'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(2, 0),  # mark on "C" = line 2 after undo
        )

        # J redo preserves mark below
        # ma on C (line 2), go to line 0, J joins A+B, undo, redo re-joins,
        # mark should be on C but now line 1 (A B merged)
        self.run_test_screen(
            "J redo preserves mark set below",
            "A\nB\nC\nD\n",
            b"jjmaggJu u'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(1, 0),  # mark on "C" = line 1 after redo (A+B joined)
        )

        # 3J undo preserves mark below
        # ma on D (line 3), go to line 0, 3J joins A+B+C, undo restores,
        # mark should still be on D (line 3)
        self.run_test_screen(
            "3J undo preserves mark set below",
            "A\nB\nC\nD\nE\n",
            b"jjjmagg3Ju'a:q!\r",
            rows=10, cols=40,
            expect_cursor=(3, 0),  # mark on "D" = line 3 after undo
        )

        # JJ batched undo: screen shows correct content
        # A\nB\nC\n -> JJ -> A B C\n -> u -> A B\nC\n
        self.run_test_screen(
            "JJ batched undo: screen correct",
            "A\nB\nC\n",
            b"JJ u:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A B"), (1, "C")],
        )

        # JJ batched redo: screen shows correct content
        # A\nB\nC\n -> JJ -> A B C\n -> u -> A B\nC\n -> u -> A B C\n
        self.run_test_screen(
            "JJ batched redo: screen correct",
            "A\nB\nC\n",
            b"JJ u u:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A B C"), (1, "~")],
        )

        # Non-batched J undo: screen shows restored lines
        self.run_test_screen(
            "J undo: screen correct",
            "Hello\nWorld\n",
            b"Ju:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello"), (1, "World")],
        )

        # Non-batched 3J undo: screen shows all restored lines
        self.run_test_screen(
            "3J undo: screen correct",
            "A\nB\nC\nD\n",
            b"3Ju:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "B"), (2, "C"), (3, "D")],
        )

        # JJ batched undo: cursor stays at col 0
        self.run_test_screen(
            "JJ batched undo: cursor position",
            "A\nB\nC\n",
            b"JJ u:q!\r",
            rows=10, cols=40,
            expect_cursor=(0, 0),
        )

        self._group("Undo batching (u):", leading_blank=True)

        # uu batched: even count = noop, no content redraw
        # Frames: initial (True), dd (True), uu noop (False)
        self.run_test_screen(
            "uu batched: even count is noop after dd",
            "A\nB\nC\n",
            b"dduu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "B"), (1, "C")],
            expect_content_redraws=[True, True, False],
        )

        # uuu batched: odd count = one undo, one content redraw
        # Frames: initial (True), dd (True), uuu = one undo (True)
        self.run_test_screen(
            "uuu batched: odd count does undo after dd",
            "A\nB\nC\n",
            b"dduuu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "A"), (1, "B"), (2, "C")],
            expect_content_redraws=[True, True, True],
        )

        # uuuu batched: even count = noop, no content redraw
        # Frames: initial (True), dd (True), uuuu noop (False)
        self.run_test_screen(
            "uuuu batched: even count is noop after dd",
            "A\nB\nC\n",
            b"dduuuu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "B"), (1, "C")],
            expect_content_redraws=[True, True, False],
        )

        # uu batched after x: noop, no content redraw
        # Frames: initial (True), x (True), uu noop (False)
        self.run_test_screen(
            "uu batched: even count is noop after x",
            "Hello\n",
            b"xuu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "ello")],
            expect_content_redraws=[True, True, False],
        )

        # uuu batched after J: odd count = one undo, one content redraw
        # Frames: initial (True), J (True), uuu = one undo (True)
        self.run_test_screen(
            "uuu batched: odd count does undo after J",
            "Hello\nWorld\n",
            b"Juuu:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello"), (1, "World")],
            expect_content_redraws=[True, True, True],
        )

        # J undo scroll region should exclude cursor row
        # When J is undone, cursor row content changes but doesn't need to scroll.
        # Only rows below cursor should scroll down.
        # For cursor at row 0 with 10 rows: scroll region should be ESC[2;9r
        # (rows 2-9 in 1-based = rows 1-8 in 0-based), not ESC[1;9r
        self.run_test_screen(
            "J undo scroll excludes cursor row",
            "Hello\nWorld\n",
            b"Ju:q!\r",
            rows=10, cols=40,
            expect_lines=[(0, "Hello"), (1, "World")],
            expect_ansi_contains="\x1b[2;9r",
        )

        self._group("Undo line paste below (p):", leading_blank=True)

        # dd then p then u: undo removes pasted line (dd already committed)
        self.run_test(
            "ddpu undoes paste (dd stays)",
            "A\nB\nC\n",
            b"ddpu:wq\r",
            expected_content="B\nC\n"
        )

        # dd then p then uu: redo re-pastes
        self.run_test(
            "ddpuu redo re-pastes",
            "A\nB\nC\n",
            b"ddpuu:wq\r",
            expected_content="B\nA\nC\n"
        )

        # yy then p then u: removes pasted copy
        self.run_test(
            "yypu removes pasted copy",
            "A\nB\n",
            b"yypu:wq\r",
            expected_content="A\nB\n"
        )

        # yy then 2p then u: removes all pasted copies
        self.run_test(
            "yy2pu removes all copies",
            "A\nB\n",
            b"yy2pu:wq\r",
            expected_content="A\nB\n"
        )

        # yy then 2p then uu: redo re-pastes both
        self.run_test(
            "yy2puu redo re-pastes both",
            "A\nB\n",
            b"yy2puu:wq\r",
            expected_content="A\nA\nA\nB\n"
        )

        # yy then pp (batched) then u: undo removes entire batched paste
        self.run_test(
            "yyppu undo removes batched paste",
            "A\nB\n",
            b"yyppu:wq\r",
            expected_content="A\nB\n"
        )

        # Cursor position after undo: back to pre-paste line+col
        self.run_test_screen(
            "ddpu cursor at original position",
            "AB\nCD\nEF\n",
            b"l" +              # cursor at col 1
            b"ddpu:q!\r",
            expect_cursor=(0, 1),
        )

        # Mark adjustment on undo: mark shifts back
        self.run_test_screen(
            "ddpu mark preserved",
            "A\nB\nC\n",
            b"jjma" +           # mark C (line 2)
            b"ggyy p" +         # yank A, paste below line 0 -> C shifts to 3
            b"u" +              # undo paste -> C shifts back to 2
            b"'a:q!\r",
            expect_cursor=(2, 0),
        )

        # Mark adjustment on redo: mark shifts forward again
        self.run_test_screen(
            "ddpuu mark preserved on redo",
            "A\nB\nC\n",
            b"jjma" +           # mark C (line 2)
            b"ggyy p" +         # paste -> C at 3
            b"uu" +             # undo+redo -> C at 3
            b"'a:q!\r",
            expect_cursor=(3, 0),
        )

        self._group("Undo line paste above (P):", leading_blank=True)

        # jdd then P then u: undo removes pasted line
        self.run_test(
            "jddPu undoes paste (dd stays)",
            "A\nB\nC\n",
            b"jddPu:wq\r",
            expected_content="A\nC\n"
        )

        # jdd then P then uu: redo re-pastes
        self.run_test(
            "jddPuu redo re-pastes",
            "A\nB\nC\n",
            b"jddPuu:wq\r",
            expected_content="A\nB\nC\n"
        )

        # yy then P then u: removes pasted copy
        self.run_test(
            "yyPu removes pasted copy",
            "A\nB\n",
            b"yyPu:wq\r",
            expected_content="A\nB\n"
        )

        # yy then 2P then u: removes all copies
        self.run_test(
            "yy2Pu removes all copies",
            "A\nB\n",
            b"yy2Pu:wq\r",
            expected_content="A\nB\n"
        )

        # Cursor position after undo
        self.run_test_screen(
            "jddPu cursor at original position",
            "AB\nCD\nEF\n",
            b"l" +              # cursor at col 1
            b"jddPu:q!\r",
            expect_cursor=(1, 1),
        )

        # Mark adjustment on undo
        self.run_test_screen(
            "yyPu mark preserved",
            "A\nB\nC\n",
            b"jjma" +           # mark C (line 2)
            b"ggyy P" +         # paste above line 0 -> C shifts to 3
            b"u" +              # undo -> C back to 2
            b"'a:q!\r",
            expect_cursor=(2, 0),
        )

        self._group("Undo char paste below (p):", leading_blank=True)

        # x then p then u: undo removes pasted char (x already committed)
        self.run_test(
            "xpu undoes char paste (x stays)",
            "AB\n",
            b"xpu:wq\r",
            expected_content="B\n"
        )

        # x then p then uu: redo re-pastes
        self.run_test(
            "xpuu redo re-pastes",
            "AB\n",
            b"xpuu:wq\r",
            expected_content="BA\n"
        )

        # D then p then u: undo removes pasted chars (D already committed)
        self.run_test(
            "Dpu undoes char paste (D stays)",
            "Hello World\n",
            b"llDpu:wq\r",
            expected_content="He\n"
        )

        # x then 2p then u: undo removes both pasted copies (x already committed)
        self.run_test(
            "x2pu undoes counted char paste (x stays)",
            "AB\n",
            b"x2pu:wq\r",
            expected_content="B\n"
        )

        # Multiline char paste undo (content with newlines)
        self.run_test(
            "multiline char paste p undo",
            "AB\nCD\nEF\n",
            b"$de" +            # delete "B\nCD" (multiline yank)
            b"pu:wq\r",        # paste then undo
            expected_content="A\nEF\n"
        )

        # Empty line char paste undo
        self.run_test(
            "empty line char paste p undo",
            "\nB\n",
            b"jx" +             # delete B from second line
            b"kpu:wq\r",       # go to empty line, paste, undo
            expected_content="\n\n"
        )

        # Cursor position after undo: back to pre-paste col
        self.run_test_screen(
            "xpu cursor restored",
            "ABC\n",
            b"lxpu:q!\r",      # col1, x deletes B, p pastes after cursor, u undoes
            expect_cursor=(0, 1),
        )

        # Multiline char paste mark adjustment on undo
        self.run_test_screen(
            "multiline char paste p undo preserves mark",
            "AB\nCD\nEF\n",
            b"jjma" +           # mark EF (line 2)
            b"gg$de" +          # delete "B\nCD" -> EF at line 1
            b"pu" +             # paste then undo -> EF back at 1
            b"'a:q!\r",
            expect_cursor=(1, 0),
        )

        self._group("Undo char paste above (P):", leading_blank=True)

        # x then P then u: undo removes pasted char (x already committed)
        self.run_test(
            "xPu undoes char paste (x stays)",
            "AB\n",
            b"xPu:wq\r",
            expected_content="B\n"
        )

        # x then P then uu: redo re-pastes
        self.run_test(
            "xPuu redo re-pastes",
            "AB\n",
            b"xPuu:wq\r",
            expected_content="AB\n"
        )

        # x then 2P then u: undo removes both copies
        self.run_test(
            "x2Pu undoes counted char paste (x stays)",
            "AB\n",
            b"x2Pu:wq\r",
            expected_content="B\n"
        )

        # Multiline char paste above undo
        self.run_test(
            "multiline char paste P undo",
            "AB\nCD\nEF\n",
            b"$de" +            # delete "B\nCD" (multiline yank)
            b"Pu:wq\r",        # paste above then undo
            expected_content="A\nEF\n"
        )

        # Cursor position after undo
        self.run_test_screen(
            "xPu cursor restored",
            "ABC\n",
            b"lxPu:q!\r",      # col1, x deletes B, P pastes at cursor, u undoes
            expect_cursor=(0, 1),
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
