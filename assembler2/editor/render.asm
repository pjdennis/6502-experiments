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

CURSOR_ROW:    .byte     ; Cursor screen row (0-based, derived from wrap computation)
CURSOR_COL:    .byte     ; Cursor column (0-based, can exceed SCREEN_COLS for wrapped lines)
VIEW_TOP16:    .word     ; First visible line number (0-based)
SCREEN_ROWS:   .byte     ; Terminal height
SCREEN_COLS:   .byte     ; Terminal width
FILE_LINE16:   .word     ; Current file line (0-based)
MODE:          .byte     ; Current mode: MODE_NORMAL, MODE_INSERT, MODE_COMMAND
MODIFIED:      .byte     ; File modified flag ($00 = no, $FF = yes)
READONLY:      .byte     ; Read-only mode ($00 = no, $FF = yes)
RENDER_ROW:    .byte     ; Current row being rendered
RENDER_LINE16: .word     ; Current file line being rendered
RENDER_COL:    .byte     ; Column counter during rendering
FNAME_PTR16:   .word     ; Pointer to filename string (null-terminated)
RENDER_FLAG:   .byte     ; $FF = full repaint, $01 = current line+status, $00 = cursor+status only
VIEW_TOP_WRAP: .byte     ; Wrap row offset for first visible line (0 = start of line)
WRAP_QUOT:     .byte     ; Scratch: quotient from CURSOR_COL / SCREEN_COLS
WRAP_REM:      .byte     ; Scratch: remainder from CURSOR_COL % SCREEN_COLS
RENDER_WRAP:   .byte     ; Current wrap row offset during rendering

  .code

; Initialize rendering state
render_init:
  JSR term_rows
  STA SCREEN_ROWS
  JSR term_cols
  STA SCREEN_COLS
  LDA #0
  STA CURSOR_ROW
  STA CURSOR_COL
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

.row_loop:
  ; Position cursor at start of this row
  LDA RENDER_ROW
  CLC
  ADC #1           ; ANSI rows are 1-based
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor

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
  BEQ .line_done
  ; More wrap rows remain
  JSR ansi_clear_line
  INC RENDER_WRAP
  INC RENDER_ROW
  JMP .row_loop

.line_done:
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
  JSR write_b
  JSR ansi_clear_line

  INC RENDER_ROW
  JMP .row_loop

.row_done:
  ; Draw status line
  JSR render_status_line

  ; Position cursor
  JSR render_position_cursor

  JSR ansi_cursor_show
  JSR con_flush
  RTS

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

  ; Print separator and line/col
  PRINT_STR str_separator

  ; Line number (1-based)
  CLC
  ADCI16 FILE_LINE16, $0001, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  LDA #','
  JSR write_b

  ; Column (1-based)
  LDA CURSOR_COL
  CLC
  ADC #1
  JSR write_byte_dec

  ; Print total lines
  LDA #' '
  JSR write_b
  LDA #'/'
  JSR write_b

  CP16 LINE_COUNT16, TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  ; Clear rest of status line and restore normal video
  JSR ansi_clear_line
  JSR ansi_normal_video
  RTS

; Position cursor at the editing position (wrap-aware)
render_position_cursor:
  LDA CURSOR_ROW
  CLC
  ADC #1           ; ANSI 1-based
  STA ANSI_ROW
  ; Screen column = CURSOR_COL % SCREEN_COLS + 1
  LDA CURSOR_COL
  JSR div_mod_screen_cols
  ; A = remainder (screen col 0-based)
  CLC
  ADC #1           ; ANSI 1-based
  STA ANSI_COL
  JSR ansi_move_cursor
  RTS

; Render just the current line (optimization for insert mode)
; Redraws the line at CURSOR_ROW and repositions cursor
render_current_line:
  JSR ansi_cursor_hide

  LDA CURSOR_ROW
  CLC
  ADC #1
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Get current line pointer
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr

  JSR render_line_chars
  JSR ansi_clear_line

  JSR render_position_cursor
  JSR ansi_cursor_show
  JSR con_flush
  RTS

; Redraw just the current line and status bar (optimization for single-line edits)
render_current_line_and_status:
  ; If line wraps (len >= SCREEN_COLS), upgrade to full repaint
  JSR get_current_line_len
  CMP SCREEN_COLS
  BCC .single_row

  ; Line wraps - do full repaint
  JMP render_screen

.single_row:
  JSR ansi_cursor_hide

  LDA CURSOR_ROW
  CLC
  ADC #1
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor

  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr

  JSR render_line_chars
  JSR ansi_clear_line

  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JSR con_flush
  RTS

; Dispatch: full repaint, current line, or cursor+status only, based on RENDER_FLAG
render_update:
  LDA RENDER_FLAG
  BEQ .cursor_only
  CMP #1
  BEQ .current_line
  JMP render_screen
.current_line:
  JMP render_current_line_and_status
.cursor_only:
  JMP render_cursor_and_status

; Render just the status bar and reposition cursor (no content redraw)
render_cursor_and_status:
  JSR ansi_cursor_hide
  JSR render_status_line
  JSR render_position_cursor
  JSR ansi_cursor_show
  JSR con_flush
  RTS

; Print line characters from BUF_PTR16 up to SCREEN_COLS or newline
; Replaces control chars with spaces. Clobbers A, Y.
render_line_chars:
  LDA #0
  STA RENDER_COL
  LDY #0
.rlc_loop:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .rlc_done
  CMP #' '
  BCC .rlc_ctrl
  JSR write_b
  JMP .rlc_next
.rlc_ctrl:
  LDA #' '
  JSR write_b
.rlc_next:
  INY
  INC RENDER_COL
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCC .rlc_loop
.rlc_done:
  RTS

; === Wrap utility functions ===

; Divide A by SCREEN_COLS using repeated subtraction
; Returns: X = quotient, A = remainder
; Clobbers: X
div_mod_screen_cols:
  LDX #0
.div_loop:
  CMP SCREEN_COLS
  BCC .div_done
  SEC
  SBC SCREEN_COLS
  INX
  JMP .div_loop
.div_done:
  RTS

; Compute number of screen rows a line occupies
; Input: A = line length
; Returns: A = number of screen rows (1 for empty/short, ceil(len/SCREEN_COLS) for longer)
; Clobbers: X
line_screen_rows:
  CMP #0
  BNE .ls_not_empty
  LDA #1
  RTS
.ls_not_empty:
  JSR div_mod_screen_cols
  ; X = quotient, A = remainder
  STA WRAP_REM
  TXA              ; A = quotient
  LDX WRAP_REM
  CPX #0
  BEQ .ls_exact
  CLC
  ADC #1           ; Add 1 for partial last row
.ls_exact:
  RTS

; Ensure cursor is visible on screen (wrap-aware)
; Updates CURSOR_ROW from FILE_LINE16 and VIEW_TOP16
; Scrolls if needed, setting RENDER_FLAG=$FF on scroll
; Preserves RENDER_FLAG if no scroll needed
ensure_cursor_visible:
  ; Compute cursor's wrap row: CURSOR_COL / SCREEN_COLS
  LDA CURSOR_COL
  JSR div_mod_screen_cols
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
  LDA #$FF
  STA RENDER_FLAG
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
  BNE .ecv_walk_top

  ; Same line
  SEC
  LDA WRAP_QUOT
  SBC VIEW_TOP_WRAP
  STA CURSOR_ROW
  JMP .ecv_check_below

.ecv_walk_top:
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

.ecv_walk_loop:
  ; Are we at FILE_LINE16?
  CMP16 RENDER_LINE16, FILE_LINE16
  BEQ .ecv_at_cursor

  ; Add screen rows for this intermediate line
  LDAX16 RENDER_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  CLC
  ADC CURSOR_ROW
  STA CURSOR_ROW

  INC16 RENDER_LINE16
  JMP .ecv_walk_loop

.ecv_at_cursor:
  ; Add cursor's wrap row within FILE_LINE16
  LDA CURSOR_ROW
  CLC
  ADC WRAP_QUOT
  STA CURSOR_ROW

.ecv_check_below:
  ; Check if cursor is below view (CURSOR_ROW >= SCREEN_ROWS - 1)
  LDA CURSOR_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCC .ecv_visible

  ; Need to scroll down
  ; We need CURSOR_ROW = SCREEN_ROWS - 2
  ; Scroll VIEW_TOP forward until cursor fits
  LDA #$FF
  STA RENDER_FLAG

  ; Compute target CURSOR_ROW (store in RENDER_ROW as safe temp)
  LDA SCREEN_ROWS
  SEC
  SBC #2
  STA RENDER_ROW     ; target CURSOR_ROW

.ecv_scroll_down:
  ; Advance VIEW_TOP_WRAP/VIEW_TOP16 one screen row at a time
  ; Get height of VIEW_TOP line
  LDAX16 VIEW_TOP16
  JSR buf_get_line_len
  JSR line_screen_rows
  ; A = total screen rows for VIEW_TOP line
  STA RENDER_COL     ; temp: line_height

  ; Can we advance within this line?
  LDA VIEW_TOP_WRAP
  CLC
  ADC #1
  CMP RENDER_COL
  BCC .ecv_advance_wrap

  ; Advance to next file line
  INC16 VIEW_TOP16
  LDA #0
  STA VIEW_TOP_WRAP
  JMP .ecv_shed_row

.ecv_advance_wrap:
  INC VIEW_TOP_WRAP

.ecv_shed_row:
  DEC CURSOR_ROW
  LDA CURSOR_ROW
  CMP RENDER_ROW
  BNE .ecv_scroll_down
  ; Falls through when CURSOR_ROW == target

.ecv_visible:
  RTS

; === String constants ===
str_normal:        .asciiz "NORMAL"
str_insert:        .asciiz "INSERT"
str_command:       .asciiz "COMMAND"
mode_strings:      .word str_normal, str_insert, str_command
str_ro_indicator:  .asciiz " [RO]"
str_mod_indicator: .asciiz " [+]"
str_separator:     .asciiz " - "
