# Editor Performance Plan

## Completed

### Incremental line pointer adjustment

When inserting/deleting a non-newline character, line pointers after the edit
point shift by +1/-1. `buf_adjust_lines_inc` and `buf_adjust_lines_dec` walk
LINE_TBL and adjust each pointer, replacing a full `buf_rebuild_lines` scan.

For a 318-line file: ~12K cycles vs ~194K cycles.

### Page-at-a-time byte shifting

`buf_insert_char` and `buf_delete_char` use Y-indexed inner loops to process
up to 256 bytes per page, avoiding per-byte 16-bit pointer manipulation.

~16-18 cycles/byte vs ~47 cycles/byte.

## Future Work

### Step 3: Batch insert when keys are buffered

**Problem:** When holding a key, multiple keystrokes buffer in stdin. Each is
processed individually: shift buffer by 1, adjust lines, render. If N keys are
buffered, we do N separate shifts of the entire buffer tail.

**Design:** After processing an insert-mode printable character, check
`con_ready` before rendering. If more printable keys are pending, read them
all (up to a limit) and batch the operation:

1. Read all pending printable characters into a small staging buffer (cap at
   32 or so to bound latency).
2. Shift the buffer right by N once, instead of N shifts by 1. The
   page-at-a-time shift loop already supports this by adjusting the
   SRC/DST offset from 1 to N.
3. Copy all N characters into the opened gap.
4. Call `buf_adjust_lines_inc` once (adjusting pointers by +N instead of +1).
   This requires a parameterized version that takes the delta.
5. Render once.

This reduces N keystrokes from `N * (shift + adjust + render)` to
`1 * (shift_N + adjust_N + render)`. The total bytes shifted is the same,
but setup overhead, line adjustment, and render happen only once.

**Call sites:**
- `editor/insert.asm` `insert_char`: after inserting the first character,
  loop reading `con_ready` / `con_read` for additional printable chars.
- `editor/buffer.asm`: add `buf_insert_chars` (shift by N, fill N bytes)
  and a parameterized `buf_adjust_lines_add` (add N to pointers).

**Newline handling in batch:** If a newline (Enter) is encountered in the
pending keys, stop the batch before it and process the newline separately,
since newlines require a full `buf_rebuild_lines`.

### Step 4: Gap buffer

**Problem:** Even with optimized shifting, inserting a character in a large
file requires moving all bytes after the edit point. This is O(file_size) per
keystroke.

**Design:** Replace the contiguous buffer with a gap buffer:

```
[text before cursor] [--- gap ---] [text after cursor]
```

- **Insert:** Write character at gap start, shrink gap by 1. O(1).
- **Delete:** Expand gap by 1. O(1).
- **Move cursor:** Shift bytes across the gap boundary. O(distance moved).
  Between keystrokes the cursor typically moves by at most one line, so
  this is cheap.

**Data structures:**
- `GAP_START16`: pointer to first byte of gap.
- `GAP_END16`: pointer to first byte after gap.
- Buffer content is `[TEXT_BUF .. GAP_START16)` + `[GAP_END16 .. BUF_END16)`.

**Line table:** LINE_TBL stores absolute buffer positions. Positions before
the gap are direct. Positions after the gap are stored as their actual
address (past the gap), so `buf_get_line_ptr` needs gap-aware translation:
if the stored pointer >= GAP_START16, the real content is at
`stored_ptr + (GAP_END16 - GAP_START16)`.

Alternatively, store positions as logical offsets (pretending the gap
doesn't exist) and translate on access. The first approach is simpler since
most line table operations just compare or iterate.

**Affected code:**
- `editor/buffer.asm`: buf_insert_char, buf_delete_char become O(1).
  buf_get_line_ptr needs gap translation. buf_rebuild_lines scans
  non-gap regions. buf_insert_newline and buf_delete_line need gap
  awareness.
- `editor/render.asm`: render_line_chars reads buffer content that may
  span the gap. Needs to check if current line crosses the gap and
  handle the split.
- `editor/insert.asm`, `editor/normal.asm`: Cursor movement may need to
  shift bytes across the gap, but the high-level logic stays the same.

**Incremental line adjustment with gap buffer:** With a gap buffer,
buf_adjust_lines_inc/dec are no longer needed since insert/delete don't
shift the buffer. The line table just needs one new entry (for newline
insert) or one removed entry (for newline delete), plus the gap position
bookkeeping.

**Complexity:** This is a significant refactor. Plan in detail after
evaluating whether steps 1-3 provide sufficient performance.
