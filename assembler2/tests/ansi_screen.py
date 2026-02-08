"""
ANSI virtual terminal emulator for testing editor screen output.

Processes ANSI escape sequences into a virtual screen buffer with cursor
tracking. Only handles sequences the editor actually emits.

Supported sequences:
    ESC[2J          - Clear screen
    ESC[{r};{c}H    - Cursor move (1-based)
    ESC[H           - Cursor home (1,1)
    ESC[K           - Clear to end of line
    ESC[7m / ESC[0m - Reverse/normal video (tracked, not stored per-cell)
    ESC[?25l        - Cursor hide
    ESC[?25h        - Cursor show (triggers frame snapshot)
"""


class AnsiScreen:
    def __init__(self, rows, cols):
        self.rows = rows
        self.cols = cols
        self.buffer = [[' '] * cols for _ in range(rows)]
        self.cursor_row = 0  # 0-based
        self.cursor_col = 0
        self.reverse_video = False
        self.cursor_visible = True
        # Snapshot of last rendered frame (captured at ESC[?25h)
        self.frame_buffer = None
        self.frame_cursor = (0, 0)

    def _clear_screen(self):
        self.buffer = [[' '] * self.cols for _ in range(self.rows)]

    def _clear_to_eol(self):
        row = self.cursor_row
        if 0 <= row < self.rows:
            for c in range(self.cursor_col, self.cols):
                self.buffer[row][c] = ' '

    def _move_cursor(self, row, col):
        self.cursor_row = row
        self.cursor_col = col

    def _put_char(self, ch):
        if self.cursor_row < 0 or self.cursor_row >= self.rows:
            return
        if self.cursor_col < 0 or self.cursor_col >= self.cols:
            return
        self.buffer[self.cursor_row][self.cursor_col] = ch
        self.cursor_col += 1

    def _snapshot(self):
        """Capture current buffer and cursor as a frame."""
        self.frame_buffer = [row[:] for row in self.buffer]
        self.frame_cursor = (self.cursor_row, self.cursor_col)

    def process(self, data: str) -> 'AnsiScreen':
        """Process ANSI output data through the virtual terminal."""
        NORMAL = 0
        ESC = 1
        CSI = 2

        state = NORMAL
        params = ""
        i = 0

        while i < len(data):
            ch = data[i]
            i += 1

            if state == NORMAL:
                if ch == '\x1b':
                    state = ESC
                    params = ""
                elif ch == '\n':
                    self.cursor_row += 1
                    self.cursor_col = 0
                elif ch == '\r':
                    self.cursor_col = 0
                elif ch >= ' ' and ch <= '~':
                    self._put_char(ch)
            elif state == ESC:
                if ch == '[':
                    state = CSI
                else:
                    state = NORMAL
            elif state == CSI:
                if ch.isdigit() or ch == ';' or ch == '?':
                    params += ch
                else:
                    # Dispatch CSI sequence
                    self._dispatch_csi(params, ch)
                    state = NORMAL

        return self

    def _dispatch_csi(self, params, final):
        if final == 'J':
            # Clear screen (only ESC[2J supported)
            if params == '2':
                self._clear_screen()
        elif final == 'H':
            # Cursor position
            if params == '' or params == ';':
                self._move_cursor(0, 0)
            else:
                parts = params.split(';')
                row = int(parts[0]) - 1 if parts[0] else 0
                col = int(parts[1]) - 1 if len(parts) > 1 and parts[1] else 0
                self._move_cursor(row, col)
        elif final == 'K':
            # Clear to end of line
            self._clear_to_eol()
        elif final == 'm':
            # SGR - Select Graphic Rendition
            if params == '7':
                self.reverse_video = True
            elif params == '0' or params == '':
                self.reverse_video = False
        elif final == 'l':
            # Private mode reset
            if params == '?25':
                self.cursor_visible = False
        elif final == 'h':
            # Private mode set
            if params == '?25':
                self.cursor_visible = True
                self._snapshot()

    def get_row_text(self, row: int) -> str:
        """Row text from last rendered frame, rstripped."""
        if self.frame_buffer is None:
            return ""
        if row < 0 or row >= self.rows:
            return ""
        return ''.join(self.frame_buffer[row]).rstrip()

    def get_cursor(self) -> tuple:
        """Cursor (row, col) from last rendered frame, 0-based."""
        return self.frame_cursor

    def dump(self) -> str:
        """Return a string representation of the last rendered frame for debugging."""
        if self.frame_buffer is None:
            return "(no frame captured)"
        lines = []
        r, c = self.frame_cursor
        for i in range(self.rows):
            row_text = ''.join(self.frame_buffer[i]).rstrip()
            if i == r:
                lines.append(f"  {i:2d}: {row_text!r}  <- cursor at col {c}")
            else:
                lines.append(f"  {i:2d}: {row_text!r}")
        return '\n'.join(lines)


if __name__ == "__main__":
    # Self-test
    s = AnsiScreen(5, 20)

    # Test basic character output
    s.process("Hello")
    assert s.buffer[0][:5] == list("Hello"), f"got {s.buffer[0][:5]}"

    # Test cursor move and write
    s.process("\x1b[2;3HXY")
    assert s.buffer[1][2] == 'X'
    assert s.buffer[1][3] == 'Y'

    # Test clear screen
    s.process("\x1b[2J")
    assert s.buffer[0] == [' '] * 20
    assert s.buffer[1] == [' '] * 20

    # Test clear to end of line
    s.process("\x1b[1;1H")
    s.process("ABCDEF")
    s.process("\x1b[1;3H")  # col 3 (0-based: 2)
    s.process("\x1b[K")
    assert s.buffer[0][:6] == ['A', 'B', ' ', ' ', ' ', ' ']

    # Test frame snapshot on cursor show
    s2 = AnsiScreen(3, 10)
    s2.process("\x1b[2J\x1b[1;1HLine1\x1b[2;1HLine2\x1b[1;4H")
    s2.process("\x1b[?25h")  # cursor show -> snapshot
    assert s2.get_row_text(0) == "Line1"
    assert s2.get_row_text(1) == "Line2"
    assert s2.get_cursor() == (0, 3)

    # Test that cursor home works
    s3 = AnsiScreen(3, 10)
    s3.process("\x1b[5;5H")
    s3.process("\x1b[H")
    s3.process("\x1b[?25h")
    assert s3.get_cursor() == (0, 0)

    print("All self-tests passed.")
