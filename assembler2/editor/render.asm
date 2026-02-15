; Screen rendering engine
;
; Renders the editor view to the terminal using ANSI escape sequences.
; The view shows text lines starting from VIEW_TOP16, with the cursor
; at CURSOR_ROW/CURSOR_COL. The last line is a status bar.
; Long lines wrap visually across multiple screen rows (vi-style).

; Mode constants
MODE_NORMAL  = $00
MODE_INSERT  = $01
MODE_COMMAND = $02

  .zeropage

CURSOR_ROW:     .byte   ; Cursor screen row (0-based, derived from wrap computation)
CURSOR_COL16:   .word   ; Cursor column (0-based, 16-bit for lines >255 chars)
VIEW_TOP16:     .word   ; First visible line number (0-based)
SCREEN_ROWS:    .byte   ; Terminal height
SCREEN_COLS:    .byte   ; Terminal width
FILE_LINE16:    .word   ; Current file line (0-based)
MODE:           .byte   ; Current mode: MODE_NORMAL, MODE_INSERT, MODE_COMMAND
MODIFIED:       .byte   ; File modified flag ($00 = no, $FF = yes)
READONLY:       .byte   ; Read-only mode ($00 = no, $FF = yes)
RENDER_ROW:     .byte   ; Current row being rendered
RENDER_LINE16:  .word   ; Current file line being rendered
RENDER_COL:     .byte   ; Column counter during rendering
FNAME_PTR16:    .word   ; Pointer to filename string (null-terminated)
RENDER_FLAG:    .byte   ; Optional override: $FF = full, $01 = current line. Default $00 = auto-detect via snapshot
VIEW_TOP_WRAP:  .byte   ; Wrap row offset for first visible line (0 = start of line)
WRAP_QUOT:      .byte   ; Scratch: quotient from CURSOR_COL / SCREEN_COLS
WRAP_REM:       .byte   ; Scratch: remainder from CURSOR_COL % SCREEN_COLS
RENDER_WRAP:    .byte   ; Current wrap row offset during rendering
DIV_INPUT16:    .word   ; Scratch for 16-bit division
PREV_LINE_ROWS: .byte   ; Screen rows the current line occupied before the edit
SNAP_VIEW_TOP16: .word  ; Snapshot of VIEW_TOP16 before handler
SNAP_VIEW_TOP_WRAP: .byte ; Snapshot of VIEW_TOP_WRAP before handler
SNAP_LINE_COUNT16: .word ; Snapshot of LINE_COUNT16 before handler
SNAP_BUF_END16: .word   ; Snapshot of BUF_END16 before handler
SCROLL_DELTA:   .byte   ; Screen rows to scroll (unsigned)
RENDER_LIMIT:   .byte   ; Max rows to render (0=unlimited)

  .code

; Initialize rendering state
render_init:
  .ifdef terminal_mode
  JSR query_terminal_size
  .else
  JSR term_rows
  STA SCREEN_ROWS
  JSR term_cols
  STA SCREEN_COLS
  .endif
  LDA #0
  STA CURSOR_ROW
  STA_LH16 CURSOR_COL16
  STA MODE
  STA MODIFIED
  STA VIEW_TOP_WRAP
  STA_LH16 VIEW_TOP16
  STA_LH16 FILE_LINE16
  RTS

; Full screen redraw
; Renders all visible lines plus status bar, positions cursor
; Handles line wrapping: one file line can span multiple screen rows
render_screen:
  JSR ansi_cursor_hide

  LDA #0
  STA RENDER_ROW
  CP16 VIEW_TOP16, RENDER_LINE16
  LDA VIEW_TOP_WRAP
  STA RENDER_WRAP
  JMP render_from_row

; Render rows from RENDER_ROW/RENDER_LINE16/RENDER_WRAP to end of screen
; Expects ansi_cursor_hide already called
; Renders remaining text rows, status bar, positions cursor, shows cursor
render_from_row:
.row_loop:
  ; Position cursor at start of this row
  LDA RENDER_ROW
  CLC
  ADC #1           ; ANSI rows are 1-based
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
.row_no_cursor:

  ; Check if this is the status line row (last row)
  LDA RENDER_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .row_done    ; At or past last row = done with text

  ; Check if line exists
  CMP16 RENDER_LINE16, LINE_COUNT16
  BCS .past_eof

  ; Get line pointer
  LDAX16 RENDER_LINE16
  JSR buf_get_line_ptr

  ; Advance BUF_PTR16 by RENDER_WRAP * SCREEN_COLS
  LDA RENDER_WRAP
  BEQ .no_wrap_offset
  TAX
.wrap_offset_loop:
  CLC
  LDA BUF_PTR16
  ADC SCREEN_COLS
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1
  DEX
  BNE .wrap_offset_loop
.no_wrap_offset:

  JSR render_line_chars

  ; Check if the line has more wrap rows
  ; After render_line_chars, if it printed exactly SCREEN_COLS chars
  ; (RENDER_COL == SCREEN_COLS), check if there are more chars to wrap
  ; Note: must check before ansi_clear_line which clobbers Y
  LDA RENDER_COL
  CMP SCREEN_COLS
  BNE .line_done
  ; Check if next char is newline (line boundary at exact multiple)
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .line_ended
  ; More wrap rows remain (row is full, no clear needed)
  INC RENDER_WRAP
  INC RENDER_ROW
  JMP .row_no_cursor

.line_done:
  ; Row not full (RENDER_COL < SCREEN_COLS) - clear remainder
  JSR ansi_clear_line

.line_ended:
  ; Line ended (newline or fewer than SCREEN_COLS chars)
  ; Advance to next file line
  INC RENDER_ROW
  INC16 RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JMP .row_loop

.past_eof:
  ; Draw tilde for lines past end of file
  LDA #'~'
  JSR io_write
  JSR ansi_clear_line

  INC RENDER_ROW
  JMP .row_loop

.row_done:
  ; Draw status line
  JSR render_status_line

  ; Position cursor
  JSR render_position_cursor

  JSR ansi_cursor_show
  JMP io_flush

; Render just the status line (last row)
render_status_line:
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_reverse_video

  ; Print filename
  JSR write_fname

  ; Print read-only indicator
  LDA READONLY
  BEQ .not_readonly
  PRINT_STR str_ro_indicator
.not_readonly:

  ; Print modified flag
  LDA MODIFIED
  BEQ .not_modified
  PRINT_STR str_mod_indicator
.not_modified:

  ; Print separator
  PRINT_STR str_separator

  ; Print mode
  LDA MODE
  ASL
  TAX
  LDA mode_strings,X
  STA STR_PTR16
  LDA mode_strings + 1,X
  STA STR_PTR16 + 1
  JSR write_string

  ; Print separator and count (if active) or line/col
  PRINT_STR str_separator

  ; Show count/pending-key prefix if active
  LDA COUNT16
  ORA COUNT16 + 1
  BNE .has_count
  LDA LAST_KEY
  BNE .has_pending_no_count
  JMP .no_prefix_display
.has_count:
  CP16 COUNT16, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT
.has_pending_no_count:
  LDA LAST_KEY
  BEQ .done_prefix
  JSR io_write
.done_prefix:
  PRINT_STR str_separator
.no_prefix_display:

  ; Line number (1-based)
  CLC
  ADCI16 FILE_LINE16, $0001, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  LDA #','
  JSR io_write

  ; Column (1-based, 16-bit)
  CLC
  ADCI16 CURSOR_COL16, $0001, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  ; Print total lines
  LDA #' '
  JSR io_write
  LDA #'/'
  JSR io_write

  CP16 LINE_COUNT16, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  ; Clear rest of status line and restore normal video
  JSR ansi_clear_line
  JMP ansi_normal_video

; Position cursor at the editing position (wrap-aware)
render_position_cursor:
  LDA CURSOR_ROW
  CLC
  ADC #1           ; ANSI 1-based
  STA ANSI_ROW
  ; Screen column = CURSOR_COL16 % SCREEN_COLS + 1
  CP16 CURSOR_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16
  ; A = remainder (screen col 0-based)
  CLC
  ADC #1           ; ANSI 1-based
  STA ANSI_COL
  JMP ansi_move_cursor

; Redraw current line's wrap rows plus status bar (for single-line edits)
; If row count unchanged: renders just the line's rows + status bar.
; If row count changed: renders from line's first row to bottom of screen.
render_current_line_and_status:
  ; Compute cursor's wrap row from CURSOR_COL16
  CP16 CURSOR_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16
  STX WRAP_QUOT

  ; Get current line row count
  JSR get_current_line_len
  JSR line_screen_rows
  ; A = current row count

  CMP PREV_LINE_ROWS
  BNE .rows_changed

  ; --- Same row count: render just the line's rows ---
  TAX                          ; X = row count (loop counter)
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  BMI .do_full                 ; first row above visible area
  STA RENDER_ROW

  STX RENDER_WRAP              ; save loop counter (LDAX16 clobbers X)
  JSR ansi_cursor_hide
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  LDX RENDER_WRAP              ; restore loop counter

  ; Position cursor for first row only
  LDA RENDER_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .wrap_done               ; at status bar row, stop
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  STX RENDER_WRAP              ; save loop counter
  JSR ansi_move_cursor

.wrap_loop:
  JSR render_line_chars
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCS .no_clear            ; row full, skip clear for deferred-wrap terminals
  JSR ansi_clear_line
.no_clear:
  ; Advance BUF_PTR16 by SCREEN_COLS for next wrap row
  CLC
  LDA BUF_PTR16
  ADC SCREEN_COLS
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1
  INC RENDER_ROW
  LDX RENDER_WRAP              ; restore loop counter
  DEX
  BEQ .wrap_done
  STX RENDER_WRAP              ; save for next iteration
  ; Check if next row is the status bar
  LDA RENDER_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .wrap_done
  JMP .wrap_loop

.wrap_done:
  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JMP io_flush

.rows_changed:
  ; Different row count: render from first row of line to bottom
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  BMI .do_full
  STA RENDER_ROW
  JSR ansi_cursor_hide
  CP16 FILE_LINE16, RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JMP render_from_row

.do_full:
  JMP render_screen

; Capture state snapshot before handler runs
; Saves VIEW_TOP16, VIEW_TOP_WRAP, LINE_COUNT16, BUF_END16
render_snapshot:
  CP16 VIEW_TOP16, SNAP_VIEW_TOP16
  LDA VIEW_TOP_WRAP
  STA SNAP_VIEW_TOP_WRAP
  CP16 LINE_COUNT16, SNAP_LINE_COUNT16
  CP16 BUF_END16, SNAP_BUF_END16
  RTS

; Compare post-handler state against snapshot to decide render level
; Takes the max of handler-set RENDER_FLAG and snapshot-inferred level.
; Then dispatches to the appropriate render routine.
render_decide:
  ; If handler already set $FF, skip detection
  LDA RENDER_FLAG
  CMP #$FF
  BNE .not_forced
  JMP render_screen
.not_forced:

  ; Check VIEW_TOP16 changed -> try scroll optimization before full repaint
  CMP16 SNAP_VIEW_TOP16, VIEW_TOP16
  BEQ .view_same
  JMP .view_changed
.view_same:

  ; Check VIEW_TOP_WRAP changed -> full repaint
  LDA SNAP_VIEW_TOP_WRAP
  CMP VIEW_TOP_WRAP
  BNE .full

  ; Check LINE_COUNT16 changed
  CMP16 SNAP_LINE_COUNT16, LINE_COUNT16
  BEQ .line_count_same
  ; LINE_COUNT16 changed - check for scroll optimizations
  LDA RENDER_FLAG
  CMP #$02
  BEQ .line_delete_scroll
  CMP #$03
  BNE .not_line_insert
  JMP .line_insert_scroll
.not_line_insert:
  JMP .full
.line_count_same:

  ; Check BUF_END16 changed -> current line repaint (at least)
  CMP16 SNAP_BUF_END16, BUF_END16
  BNE .current_line

  ; No snapshot changes detected; use handler's RENDER_FLAG as-is
  LDA RENDER_FLAG
  BNE .current_line       ; $01 from handler -> current line
  JMP render_cursor_and_status

.full:
  JMP render_screen

.current_line:
  LDA RENDER_FLAG
  ORA #$01
  STA RENDER_FLAG
  JMP render_current_line_and_status

.line_delete_scroll:
  ; LINE_COUNT16 decreased and RENDER_FLAG=$02 (line delete at cursor).
  ; Compute delta = SNAP_LINE_COUNT16 - LINE_COUNT16
  SEC
  LDA SNAP_LINE_COUNT16
  SBC LINE_COUNT16
  STA SCROLL_DELTA
  LDA SNAP_LINE_COUNT16 + 1
  SBC LINE_COUNT16 + 1
  BNE .full                  ; Delta > 255, fall back
  LDA SCROLL_DELTA
  BEQ .full                  ; Delta 0, shouldn't happen

  ; Check delta < available rows below cursor
  ; available = SCREEN_ROWS - 1 - CURSOR_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  SEC
  SBC CURSOR_ROW
  CMP SCROLL_DELTA
  BCC .full                  ; delta > available
  BEQ .full                  ; delta == available (no point in scroll)

  JMP render_line_delete_scroll

.line_insert_scroll:
  ; LINE_COUNT16 increased and RENDER_FLAG=$03 (line insert at cursor).
  ; Compute delta = LINE_COUNT16 - SNAP_LINE_COUNT16
  SEC
  LDA LINE_COUNT16
  SBC SNAP_LINE_COUNT16
  STA SCROLL_DELTA
  LDA LINE_COUNT16 + 1
  SBC SNAP_LINE_COUNT16 + 1
  BNE .full                  ; Delta > 255, fall back
  LDA SCROLL_DELTA
  BEQ .full                  ; Delta 0, shouldn't happen

  ; Check delta < available rows below cursor
  ; available = SCREEN_ROWS - 1 - CURSOR_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  SEC
  SBC CURSOR_ROW
  CMP SCROLL_DELTA
  BCC .full                  ; delta > available
  BEQ .full                  ; delta == available (no benefit from scroll)

  JMP render_line_insert_scroll

.view_changed:
  ; VIEW_TOP16 changed. Try scroll optimization.
  ; Requirement: both old and new VIEW_TOP_WRAP must be 0 (no partial wraps)
  LDA SNAP_VIEW_TOP_WRAP
  BNE .full
  LDA VIEW_TOP_WRAP
  BNE .full

  ; Determine direction: new > old = scrolled down (scroll up on screen)
  CMP16 VIEW_TOP16, SNAP_VIEW_TOP16
  BCC .scroll_down_detect    ; VIEW_TOP16 < SNAP → scrolled up (screen scrolls down)

  ; Scrolled down: walk from old VIEW_TOP to new VIEW_TOP, summing screen rows
  ; If any line wraps (>1 row), fall back to full repaint
  CP16 SNAP_VIEW_TOP16, RENDER_LINE16
  LDA #0
  STA SCROLL_DELTA
.scroll_up_walk:
  CMP16 RENDER_LINE16, VIEW_TOP16
  BEQ .scroll_up_ready
  LDAX16 RENDER_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  CMP #1
  BNE .scroll_full           ; Wrapped line → fall back
  INC SCROLL_DELTA
  INC16 RENDER_LINE16
  JMP .scroll_up_walk

.scroll_up_ready:
  ; Check delta < SCREEN_ROWS - 1 (else full repaint is better)
  LDA SCROLL_DELTA
  BEQ .scroll_full           ; Delta 0 shouldn't happen, but safety
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .scroll_full           ; Delta >= SCREEN_ROWS-1, full repaint
  JMP render_scroll_up

.scroll_full:
  JMP render_screen

.scroll_down_detect:
  ; Scrolled up: walk from new VIEW_TOP to old VIEW_TOP
  CP16 VIEW_TOP16, RENDER_LINE16
  LDA #0
  STA SCROLL_DELTA
.scroll_down_walk:
  CMP16 RENDER_LINE16, SNAP_VIEW_TOP16
  BEQ .scroll_down_ready
  LDAX16 RENDER_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  CMP #1
  BNE .scroll_full           ; Wrapped line → fall back
  INC SCROLL_DELTA
  INC16 RENDER_LINE16
  JMP .scroll_down_walk

.scroll_down_ready:
  LDA SCROLL_DELTA
  BEQ .scroll_full
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .scroll_full
  JMP render_scroll_down

; Scroll screen up and render newly exposed bottom rows.
; SCROLL_DELTA = number of rows to scroll.
; Content moves up, blanks appear at bottom of scroll region.
render_scroll_up:
  JSR ansi_cursor_hide

  ; Set scroll region: rows 1 to SCREEN_ROWS-1 (1-based, excludes status bar)
  LDA #1
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  JSR ansi_set_scroll_region

  ; Scroll up by SCROLL_DELTA
  LDA SCROLL_DELTA
  JSR ansi_scroll_up
  JSR ansi_reset_scroll_region

  ; Render newly exposed bottom rows.
  ; RENDER_ROW = SCREEN_ROWS - 1 - SCROLL_DELTA
  LDA SCREEN_ROWS
  SEC
  SBC #1
  SEC
  SBC SCROLL_DELTA
  STA RENDER_ROW
  STA RENDER_LIMIT         ; Will render SCROLL_DELTA rows from here

  ; Find the file line at RENDER_ROW by walking from VIEW_TOP16
  JSR find_line_at_render_row
  LDA #0
  STA RENDER_WRAP
  JMP render_limited_rows

; Scroll screen down and render newly exposed top rows.
; SCROLL_DELTA = number of rows to scroll.
; Content moves down, blanks appear at top of scroll region.
render_scroll_down:
  JSR ansi_cursor_hide

  ; Set scroll region: rows 1 to SCREEN_ROWS-1 (1-based, excludes status bar)
  LDA #1
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  JSR ansi_set_scroll_region

  ; Scroll down by SCROLL_DELTA
  LDA SCROLL_DELTA
  JSR ansi_scroll_down
  JSR ansi_reset_scroll_region

  ; Render newly exposed top rows.
  ; RENDER_ROW = 0, RENDER_LINE16 = VIEW_TOP16, RENDER_WRAP = 0
  LDA #0
  STA RENDER_ROW
  STA RENDER_WRAP
  LDA SCROLL_DELTA
  STA RENDER_LIMIT
  CP16 VIEW_TOP16, RENDER_LINE16
  JMP render_limited_rows

; Scroll for line deletion at cursor.
; SCROLL_DELTA = lines deleted. CURSOR_ROW = screen row of deletion.
; Scrolls rows below cursor up, renders newly exposed bottom rows.
render_line_delete_scroll:
  JSR ansi_cursor_hide

  ; Set scroll region from CURSOR_ROW+1 (1-based) to SCREEN_ROWS-1 (1-based)
  ; This covers the cursor row through the bottom content row.
  LDA CURSOR_ROW
  CLC
  ADC #1           ; Convert to 1-based
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  JSR ansi_set_scroll_region

  ; Scroll up by SCROLL_DELTA
  LDA SCROLL_DELTA
  JSR ansi_scroll_up
  JSR ansi_reset_scroll_region

  ; Render the bottom SCROLL_DELTA rows (newly exposed content).
  ; RENDER_ROW = SCREEN_ROWS - 1 - SCROLL_DELTA
  LDA SCREEN_ROWS
  SEC
  SBC #1
  SEC
  SBC SCROLL_DELTA
  STA RENDER_ROW

  ; Find the file line at RENDER_ROW
  JSR find_line_at_render_row
  LDA #0
  STA RENDER_WRAP
  JMP render_limited_rows

; Scroll for line insertion at cursor.
; SCROLL_DELTA = lines inserted. CURSOR_ROW = screen row of insertion.
; Scrolls rows from cursor down, renders newly inserted rows at cursor.
render_line_insert_scroll:
  JSR ansi_cursor_hide

  ; Set scroll region from CURSOR_ROW+1 (1-based) to SCREEN_ROWS-1 (1-based)
  ; This covers the cursor row through the bottom content row.
  LDA CURSOR_ROW
  CLC
  ADC #1           ; Convert to 1-based
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  JSR ansi_set_scroll_region

  ; Scroll down by SCROLL_DELTA
  LDA SCROLL_DELTA
  JSR ansi_scroll_down
  JSR ansi_reset_scroll_region

  ; Render SCROLL_DELTA rows at CURSOR_ROW (newly inserted content).
  LDA CURSOR_ROW
  STA RENDER_ROW

  ; Find the file line at RENDER_ROW
  JSR find_line_at_render_row
  LDA #0
  STA RENDER_WRAP
  JMP render_limited_rows

; Render limited rows: renders SCROLL_DELTA rows starting at
; RENDER_ROW/RENDER_LINE16/RENDER_WRAP, then draws status bar + cursor.
render_limited_rows:
  ; RENDER_LIMIT = starting RENDER_ROW (used to compute how many rows to render)
  ; We need to render until RENDER_ROW reaches RENDER_LIMIT + SCROLL_DELTA
  ; Actually: we render from RENDER_ROW until we've done SCROLL_DELTA rows
  ; (or hit the status bar / end of file). Use RENDER_LIMIT as the stop row.
  LDA RENDER_ROW
  CLC
  ADC SCROLL_DELTA
  STA RENDER_LIMIT         ; Stop at this row

.limited_loop:
  ; Check if we've rendered enough rows
  LDA RENDER_ROW
  CMP RENDER_LIMIT
  BCS .limited_done

  ; Check if we've hit the status bar
  LDA RENDER_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .limited_done

  ; Position cursor at start of this row
  LDA RENDER_ROW
  CLC
  ADC #1              ; ANSI 1-based
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Check if line exists
  CMP16 RENDER_LINE16, LINE_COUNT16
  BCS .limited_past_eof

  ; Get line pointer
  LDAX16 RENDER_LINE16
  JSR buf_get_line_ptr

  ; Advance BUF_PTR16 by RENDER_WRAP * SCREEN_COLS
  LDA RENDER_WRAP
  BEQ .limited_no_wrap
  TAX
.limited_wrap_loop:
  CLC
  LDA BUF_PTR16
  ADC SCREEN_COLS
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1
  DEX
  BNE .limited_wrap_loop
.limited_no_wrap:

  JSR render_line_chars

  ; Check if line has more wrap rows
  LDA RENDER_COL
  CMP SCREEN_COLS
  BNE .limited_line_done
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .limited_line_ended
  ; More wrap rows
  INC RENDER_WRAP
  INC RENDER_ROW
  JMP .limited_loop

.limited_line_done:
  JSR ansi_clear_line

.limited_line_ended:
  INC RENDER_ROW
  INC16 RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JMP .limited_loop

.limited_past_eof:
  LDA #'~'
  JSR io_write
  JSR ansi_clear_line
  INC RENDER_ROW
  JMP .limited_loop

.limited_done:
  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JMP io_flush

; Walk from VIEW_TOP16 forward to find which file line corresponds
; to screen row RENDER_ROW. Sets RENDER_LINE16.
; Assumes no wrapping (lines occupy 1 row each - verified by caller).
; Input: RENDER_ROW = target screen row
; Output: RENDER_LINE16 = file line at that row
; Clobbers: A, X
find_line_at_render_row:
  CP16 VIEW_TOP16, RENDER_LINE16
  LDA RENDER_ROW
  BEQ .found
  TAX                     ; X = rows to skip
.walk:
  INC16 RENDER_LINE16
  DEX
  BNE .walk
.found:
  RTS

; Render just the status bar and reposition cursor (no content redraw)
render_cursor_and_status:
  JSR ansi_cursor_hide
  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JMP io_flush

; Print line characters from BUF_PTR16 up to SCREEN_COLS or newline
; Control chars: tab as '>' reverse, others as '.' reverse. Clobbers A, Y.
render_line_chars:
  LDA #0
  STA RENDER_COL
  LDY #0
.loop:
  LDA (BUF_PTR16),Y
  BMI .unprintable
  CMP #'\n'
  BEQ .done
  CMP #' '
  BCC .ctrl
  JSR io_write
  JMP .next
.ctrl:
  CMP #'\t'
  BNE .unprintable
  LDA #'>'
  JMP .rev_char
.unprintable:
  LDA #'?'
.rev_char:
  STA BUF_TEMP
  TYA
  PHA
  JSR ansi_reverse_video
  LDA BUF_TEMP
  JSR io_write
  JSR ansi_normal_video
  PLA
  TAY
.next:
  INY
  INC RENDER_COL
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCC .loop
.done:
  RTS

; === Wrap utility functions ===

; Divide 16-bit value in DIV_INPUT16 by SCREEN_COLS using repeated subtraction
; Returns: X = quotient (capped at 255), A = remainder
; Clobbers: X
div_mod_screen_cols_16:
  LDX #0
.div_loop:
  LDA DIV_INPUT16 + 1
  BNE .can_sub               ; High byte > 0, definitely >= SCREEN_COLS
  LDA DIV_INPUT16
  CMP SCREEN_COLS
  BCC .div_done              ; Value < SCREEN_COLS, done
  LDA DIV_INPUT16            ; Reload low byte for subtraction
.can_sub:
  SEC
  LDA DIV_INPUT16
  SBC SCREEN_COLS
  STA DIV_INPUT16
  LDA DIV_INPUT16 + 1
  SBC #0
  STA DIV_INPUT16 + 1
  INX
  BEQ .cap_255               ; Quotient wrapped to 0, cap at 255
  JMP .div_loop
.cap_255:
  LDX #$FF
  LDA #0                     ; Remainder doesn't matter at cap
.div_done:
  RTS

; Compute number of screen rows a line occupies
; Input: A/X = 16-bit line length (A=low, X=high)
; Returns: A = number of screen rows (1 for empty/short, ceil(len/SCREEN_COLS) for longer)
; Clobbers: X
line_screen_rows:
  STA DIV_INPUT16
  STX DIV_INPUT16 + 1
  ORA DIV_INPUT16 + 1
  BNE .not_empty
  LDA #1
  RTS
.not_empty:
  JSR div_mod_screen_cols_16
  ; X = quotient, A = remainder
  STA WRAP_REM
  TXA              ; A = quotient
  LDX WRAP_REM
  CPX #0
  BEQ .exact
  CLC
  ADC #1           ; Add 1 for partial last row
.exact:
  RTS

; Ensure cursor is visible on screen (wrap-aware)
; Updates CURSOR_ROW from FILE_LINE16 and VIEW_TOP16
; Scrolls VIEW_TOP16 if needed (render_decide detects the change)
ensure_cursor_visible:
  ; Compute cursor's wrap row: CURSOR_COL16 / SCREEN_COLS
  CP16 CURSOR_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16
  STX WRAP_QUOT      ; cursor_wrap_row
  STA WRAP_REM       ; not used here but available

  ; Check if cursor is above view
  ; FILE_LINE16 < VIEW_TOP16?
  CMP16 FILE_LINE16, VIEW_TOP16
  BCC .scroll_up
  BNE .not_above     ; FILE_LINE16 > VIEW_TOP16

  ; FILE_LINE16 == VIEW_TOP16: check wrap row
  LDA WRAP_QUOT
  CMP VIEW_TOP_WRAP
  BCS .not_above

.scroll_up:
  ; Scroll up: VIEW_TOP16 = FILE_LINE16, VIEW_TOP_WRAP = cursor_wrap_row
  CP16 FILE_LINE16, VIEW_TOP16
  LDA WRAP_QUOT
  STA VIEW_TOP_WRAP
  LDA #0
  STA CURSOR_ROW
  RTS

.not_above:
  ; Walk from (VIEW_TOP16, VIEW_TOP_WRAP) to (FILE_LINE16, cursor_wrap_row)
  ; summing screen rows to compute CURSOR_ROW

  ; Start with screen_row = 0
  LDA #0
  STA CURSOR_ROW

  ; current_line = VIEW_TOP16
  CP16 VIEW_TOP16, RENDER_LINE16

  ; If VIEW_TOP16 == FILE_LINE16, just compute cursor_wrap - VIEW_TOP_WRAP
  CMP16 RENDER_LINE16, FILE_LINE16
  BNE .walk_top

  ; Same line
  SEC
  LDA WRAP_QUOT
  SBC VIEW_TOP_WRAP
  STA CURSOR_ROW
  JMP .check_below

.walk_top:
  ; Add screen rows for VIEW_TOP16 line (minus VIEW_TOP_WRAP)
  LDAX16 RENDER_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  ; A = total screen rows for this line
  SEC
  SBC VIEW_TOP_WRAP
  STA CURSOR_ROW

  ; Advance to next line
  INC16 RENDER_LINE16

.walk_loop:
  ; Are we at FILE_LINE16?
  CMP16 RENDER_LINE16, FILE_LINE16
  BEQ .at_cursor

  ; Add screen rows for this intermediate line
  LDAX16 RENDER_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  CLC
  ADC CURSOR_ROW
  BCS .need_scroll_down  ; 8-bit overflow: cursor far below screen
  STA CURSOR_ROW

  INC16 RENDER_LINE16
  JMP .walk_loop

.at_cursor:
  ; Add cursor's wrap row within FILE_LINE16
  LDA CURSOR_ROW
  CLC
  ADC WRAP_QUOT
  BCS .need_scroll_down  ; 8-bit overflow
  STA CURSOR_ROW

.check_below:
  ; Check if cursor is below view (CURSOR_ROW >= SCREEN_ROWS - 1)
  LDA CURSOR_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCC .visible

.need_scroll_down:
  ; Cursor is below visible area
  ; Walk backward from FILE_LINE16 to find correct VIEW_TOP16

  LDA SCREEN_ROWS
  SEC
  SBC #2
  STA CURSOR_ROW      ; Target: cursor at row SCREEN_ROWS - 2
  STA RENDER_ROW      ; Rows to walk back

  ; Start from cursor position
  CP16 FILE_LINE16, VIEW_TOP16
  LDA WRAP_QUOT
  STA VIEW_TOP_WRAP

.walk_back:
  LDA RENDER_ROW
  BEQ .visible

  ; Can we go back within current line?
  LDA VIEW_TOP_WRAP
  BEQ .prev_line
  DEC VIEW_TOP_WRAP
  DEC RENDER_ROW
  JMP .walk_back

.prev_line:
  TST16 VIEW_TOP16
  BEQ .at_top
  DEC16 VIEW_TOP16
  LDAX16 VIEW_TOP16
  JSR buf_get_line_len
  JSR line_screen_rows
  SEC
  SBC #1
  STA VIEW_TOP_WRAP
  DEC RENDER_ROW
  JMP .walk_back

.at_top:
  ; Hit beginning of file - adjust cursor row
  LDA CURSOR_ROW
  SEC
  SBC RENDER_ROW
  STA CURSOR_ROW

.visible:
  RTS

; === String constants ===
str_ro_indicator:  .asciiz " [RO]"
str_mod_indicator: .asciiz " [+]"
str_separator:     .asciiz " - "
str_normal:        .asciiz "NORMAL"
str_insert:        .asciiz "INSERT"
str_command:       .asciiz "COMMAND"
mode_strings:      .word str_normal, str_insert, str_command
