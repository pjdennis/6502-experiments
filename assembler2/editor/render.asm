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
RENDER_FLAG:    .byte   ; $FF=full, $01=current line, $02/$06=line delete, $03/$04/$05=line insert, $0B=range repaint. $00=auto
VIEW_TOP_WRAP:  .byte   ; Wrap row offset for first visible line (0 = start of line)
WRAP_QUOT:      .byte   ; Scratch: quotient from CURSOR_COL / SCREEN_COLS
WRAP_REM:       .byte   ; Scratch: remainder from CURSOR_COL % SCREEN_COLS
RENDER_WRAP:    .byte   ; Current wrap row offset during rendering
DIV_INPUT16:    .word   ; Scratch for 16-bit division
PREV_LINE_ROWS: .byte   ; Screen rows the current line occupied before the edit
PREV_LINE_FULL: .byte   ; Non-zero if old line's last row was full (len % cols == 0)
SNAP_VIEW_TOP16: .word  ; Snapshot of VIEW_TOP16 before handler
SNAP_VIEW_TOP_WRAP: .byte ; Snapshot of VIEW_TOP_WRAP before handler
SNAP_LINE_COUNT16: .word ; Snapshot of LINE_COUNT16 before handler
SNAP_BUF_END16: .word   ; Snapshot of BUF_END16 before handler
SCROLL_DELTA:   .byte   ; Screen rows to scroll (unsigned)
RENDER_LIMIT:   .byte   ; Max rows to render (0=unlimited)
DELETE_SCREEN_ROWS: .byte ; Pre-computed screen rows for line-delete scroll (0=use file delta)
RENDER_FROM_COL16: .word  ; First affected line column for partial render ($FFFF = full line)
INSERT_LINE_COUNT:  .byte ; Override line count for line-insert scroll (0=use file delta)

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

; Set up RENDER_ROW/RENDER_LINE16/RENDER_WRAP from cursor first_row,
; then fall through to render_from_row.
; Expects ansi_cursor_hide already called.
render_from_first_row_limited:
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  STA RENDER_ROW
  CP16 FILE_LINE16, RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JMP render_limited_rows

render_from_first_row:
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  STA RENDER_ROW
  CP16 FILE_LINE16, RENDER_LINE16
  LDA #0
  STA RENDER_WRAP

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
  BEQ .same_row_count
  JMP .rows_changed

.same_row_count:
  ; --- Same row count: render just the line's rows ---
  TAX                          ; X = row count (loop counter)
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  BPL .row_visible             ; first row on screen
  JMP .do_full                 ; first row above visible area
.row_visible:
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
  BCC .not_at_status           ; not at status bar
  JMP .wrap_done               ; at status bar row, stop
.not_at_status:
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  STX RENDER_WRAP              ; save loop counter
  JSR ansi_move_cursor

  ; --- Partial render check ---
  LDA RENDER_FROM_COL16 + 1
  AND RENDER_FROM_COL16
  CMP #$FF
  BEQ .wrap_loop              ; $FFFF → render all rows normally

  ; Compute from_wrap and from_col
  CP16 RENDER_FROM_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16   ; X=from_wrap, A=from_col
  STA WRAP_REM                 ; save from_col

  ; Skip from_wrap wrap rows
  CPX #0
  BEQ .partial_same_row
.partial_skip_loop:
  CLC
  LDA SCREEN_COLS
  ADCA16 BUF_PTR16, BUF_PTR16
  INC RENDER_ROW
  LDY RENDER_WRAP
  DEY
  STY RENDER_WRAP
  BEQ .wrap_done               ; no more rows to render
  DEX
  BNE .partial_skip_loop

.partial_same_row:
  ; Reposition cursor at (RENDER_ROW+1, from_col+1)
  LDA RENDER_ROW
  CLC
  ADC #1
  STA ANSI_ROW
  LDA WRAP_REM
  CLC
  ADC #1
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Render from from_col
  LDA WRAP_REM
  STA RENDER_COL
  JSR render_line_chars_from
  JMP .check_clear

.wrap_loop:
  JSR render_line_chars
.check_clear:
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
  ; A = current rows, PREV_LINE_ROWS = old rows
  STA SCROLL_DELTA              ; temp: current_rows
  LDA CURSOR_ROW
  SEC
  SBC WRAP_QUOT
  BPL .rc_row_ok
  JMP .do_full
.rc_row_ok:
  STA RENDER_ROW                ; first_row (0-based)
  LDA SCROLL_DELTA              ; current_rows
  CMP PREV_LINE_ROWS
  BCC .rc_rows_decreased         ; rows decreased: scroll up
  JMP .rc_render_from_row        ; rows increased or equal: scroll down
.rc_rows_decreased:

  ; --- Rows decreased: scroll UP ---
  STA DELETE_SCREEN_ROWS        ; current_rows (for scroll region skip)
  LDA PREV_LINE_ROWS
  SEC
  SBC SCROLL_DELTA              ; displacement = old - new
  STA SCROLL_DELTA
  JSR ansi_cursor_hide
  ; Scroll region: past cursor line to status bar - 1
  LDA RENDER_ROW
  CLC
  ADC DELETE_SCREEN_ROWS
  CLC
  ADC #1                        ; 1-based
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  CMP ANSI_ROW
  BCC .rc_no_scroll
  BEQ .rc_no_scroll
  JSR ansi_set_scroll_region
  LDA SCROLL_DELTA
  JSR ansi_scroll_up
  JSR ansi_reset_scroll_region
.rc_no_scroll:
  ; Check if cursor line rendering can be skipped/reduced
  LDA RENDER_FROM_COL16 + 1
  AND RENDER_FROM_COL16
  CMP #$FF
  BNE .rc_check_partial        ; not $FFFF: check for partial render
  JMP .rc_render_all_cursor    ; $FFFF = unknown change, render all
.rc_check_partial:
  CP16 RENDER_FROM_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16   ; X = change_wrap_row, A = from_col
  STA WRAP_REM                 ; save from_col
  CPX DELETE_SCREEN_ROWS       ; compare with current_rows
  BCS .rc_skip_cursor          ; change >= current: skip cursor rendering
  ; Partial: render from change_wrap_row
  STX RENDER_WRAP
  LDA SCROLL_DELTA
  PHA                          ; save displacement for bottom rows
  LDA DELETE_SCREEN_ROWS
  SEC
  SBC RENDER_WRAP              ; current_rows - change_wrap_row
  STA SCROLL_DELTA
  LDA RENDER_WRAP
  CLC
  ADC RENDER_ROW
  STA RENDER_ROW               ; advance to change_wrap_row screen row
  ; Check for partial first row
  LDA WRAP_REM
  BEQ .rc_full_rows            ; from_col=0: render full rows
  ; --- Partial first row ---
  LDA RENDER_ROW
  CLC
  ADC #1
  STA ANSI_ROW
  LDA WRAP_REM
  CLC
  ADC #1
  STA ANSI_COL
  JSR ansi_move_cursor
  ; Get line pointer, advance to wrap row
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  LDX RENDER_WRAP
  BEQ .rc_no_advance
.rc_advance_loop:
  CLC
  LDA BUF_PTR16
  ADC SCREEN_COLS
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1
  DEX
  BNE .rc_advance_loop
.rc_no_advance:
  LDA WRAP_REM
  STA RENDER_COL
  JSR render_line_chars_from
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCS .rc_partial_no_clear
  JSR ansi_clear_line
.rc_partial_no_clear:
  INC RENDER_ROW
  INC RENDER_WRAP
  DEC SCROLL_DELTA
.rc_full_rows:
  LDA #0
  STA DELETE_SCREEN_ROWS
  CP16 FILE_LINE16, RENDER_LINE16
  JSR render_limited_loop
  PLA
  STA SCROLL_DELTA             ; restore displacement
  JMP .rc_bottom_rows
.rc_skip_cursor:
  LDA #0
  STA DELETE_SCREEN_ROWS
  JMP .rc_bottom_rows
.rc_render_all_cursor:
  LDA #0
  STA DELETE_SCREEN_ROWS
  CP16 FILE_LINE16, RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JSR render_limited_loop
.rc_bottom_rows:
  ; Render bottom exposed rows
  LDA SCREEN_ROWS
  SEC
  SBC #1
  SEC
  SBC SCROLL_DELTA
  STA RENDER_ROW
  CMP CURSOR_ROW
  BCC .rc_status_only
  BEQ .rc_status_only
  JSR find_line_at_render_row
  JMP render_limited_rows
.rc_status_only:
  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JMP io_flush

.rc_render_from_row:
  ; --- Rows increased: scroll DOWN ---
  ; displacement = current_rows - PREV_LINE_ROWS
  LDA SCROLL_DELTA              ; current_rows (saved at .rows_changed entry)
  SEC
  SBC PREV_LINE_ROWS
  STA SCROLL_DELTA
  JSR ansi_cursor_hide
  ; Scroll region: past old line end to status bar - 1
  LDA RENDER_ROW
  CLC
  ADC PREV_LINE_ROWS
  CLC
  ADC #1                        ; 1-based
  STA ANSI_ROW
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA ANSI_COL
  CMP ANSI_ROW
  BCC .ri_no_scroll
  BEQ .ri_no_scroll
  JSR ansi_set_scroll_region
  LDA SCROLL_DELTA
  JSR ansi_scroll_down
  JSR ansi_reset_scroll_region
.ri_no_scroll:
  ; Check if old wrap rows can be skipped
  LDA RENDER_FROM_COL16 + 1
  AND RENDER_FROM_COL16
  CMP #$FF
  BEQ .ri_all_rows             ; $FFFF = unknown change, render all
  CP16 RENDER_FROM_COL16, DIV_INPUT16
  JSR div_mod_screen_cols_16   ; X = change_wrap_row, A = from_col
  STA WRAP_REM                 ; save from_col
  STX RENDER_WRAP
  ; SCROLL_DELTA = current_rows - change_wrap_row
  LDA SCROLL_DELTA             ; displacement
  CLC
  ADC PREV_LINE_ROWS           ; = current_rows
  SEC
  SBC RENDER_WRAP              ; - change_wrap_row
  STA SCROLL_DELTA
  ; RENDER_ROW += change_wrap_row
  LDA RENDER_WRAP
  CLC
  ADC RENDER_ROW
  STA RENDER_ROW
  ; Check for partial first row
  LDA WRAP_REM
  BEQ .ri_full_rows            ; from_col=0: render full rows
  ; --- Partial first row ---
  LDA RENDER_ROW
  CLC
  ADC #1
  STA ANSI_ROW
  LDA WRAP_REM
  CLC
  ADC #1
  STA ANSI_COL
  JSR ansi_move_cursor
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  LDX RENDER_WRAP
  BEQ .ri_no_advance
.ri_advance_loop:
  CLC
  LDA BUF_PTR16
  ADC SCREEN_COLS
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1
  DEX
  BNE .ri_advance_loop
.ri_no_advance:
  LDA WRAP_REM
  STA RENDER_COL
  JSR render_line_chars_from
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCS .ri_partial_no_clear
  JSR ansi_clear_line
.ri_partial_no_clear:
  INC RENDER_ROW
  INC RENDER_WRAP
  DEC SCROLL_DELTA
.ri_full_rows:
  CP16 FILE_LINE16, RENDER_LINE16
  JMP render_limited_rows
.ri_all_rows:
  LDA SCROLL_DELTA
  CLC
  ADC PREV_LINE_ROWS           ; = current_rows
  STA SCROLL_DELTA
  CP16 FILE_LINE16, RENDER_LINE16
  LDA #0
  STA RENDER_WRAP
  JMP render_limited_rows

.do_full:
  JMP render_screen
