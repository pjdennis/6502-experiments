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

### Batch insert when keys are buffered

After inserting a printable character, `insert_batch_pending` checks for
additional buffered input. Pending printable characters (up to 32) are read
into a staging buffer at `BATCH_BUF` ($E000), then inserted with a single
`buf_shift_right` + copy via `buf_insert_chars`. Line pointer adjustment
(`buf_adjust_lines_inc`) and rendering happen once for the whole batch.

The shift-right loop uses `BUF_DELTA` to parameterize the shift amount,
so `buf_shift_right` works for both single-char (delta=1) and batch
(delta=N) operations. Non-printable characters (Enter, ESC, arrow keys)
stop the batch and are pushed back for normal processing.

This reduces N buffered keystrokes from `N * (shift + adjust + render)` to
`1 * (shift + adjust + render) + 1 * (shift_N + adjust_N)`.

### Batch delete when keys are buffered

After deleting a character (backspace in insert mode, x in normal mode),
`count_pending_key` (shared in input.asm) checks for additional buffered
matching keys. Pending deletes are counted and executed with a single
`buf_shift_left` via `buf_delete_chars`, with one `buf_adjust_lines_dec`
call for the batch.

Backspace batching stops at column 0 (join-lines requires full
`buf_rebuild_lines` and is not batched). x batching stops when no
deleteable characters remain on the line. `count_pending_key` handles
both $08 and $7F for backspace matching.

### Batch Enter when keys are buffered

After inserting a newline in insert mode, `enter_batch_pending` counts
buffered Enter keys via `count_pending_key`. The matching keys (up to 32)
are filled as `$0A` bytes into `BATCH_BUF` and inserted with a single
`buf_insert_chars` call. `FILE_LINE16` is advanced by the batch count,
then one `buf_rebuild_lines` rebuilds the line table for the whole batch.

This reduces N+1 Enter keystrokes from `(N+1) * (shift + rebuild)` to
`1 * (shift + rebuild) + 1 * (shift_N + rebuild)`.

### Batch join-lines when keys are buffered

After backspace at column 0 joins with an empty line above,
`joinlines_batch_pending` checks for more buffered backspace keys. Unlike
`count_pending_key`, it reads one key at a time, verifying the line above
is empty before consuming each key. An empty line is identified by a `\n`
preceded by another `\n` or at the start of the text buffer.

Matched empty-line newlines are deleted with a single `buf_delete_chars`,
`FILE_LINE16` is decremented by the batch count, and one `buf_rebuild_lines`
call updates the line table.

## Future Work

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
