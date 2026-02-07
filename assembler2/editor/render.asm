; Screen rendering engine
;
; Renders the editor view to the terminal using ANSI escape sequences.
; The view shows text lines starting from VIEW_TOP16, with the cursor
; at CURSOR_ROW/CURSOR_COL. The last line is a status bar.

; Mode constants
MODE_NORMAL  = $00
MODE_INSERT  = $01
MODE_COMMAND = $02

  .zeropage

CURSOR_ROW    .data $00   ; Cursor row (0-based, relative to view)
CURSOR_COL    .data $00   ; Cursor column (0-based)
VIEW_TOP16    .data $0000 ; First visible line number (0-based)
SCREEN_ROWS   .data $00   ; Terminal height
SCREEN_COLS   .data $00   ; Terminal width
FILE_LINE16   .data $0000 ; Current file line (0-based, = VIEW_TOP16 + CURSOR_ROW)
MODE          .data $00   ; Current mode: MODE_NORMAL, MODE_INSERT, MODE_COMMAND
MODIFIED      .data $00   ; File modified flag ($00 = no, $FF = yes)
READONLY      .data $00   ; Read-only mode ($00 = no, $FF = yes)
RENDER_ROW    .data $00   ; Current row being rendered
RENDER_LINE16 .data $0000 ; Current file line being rendered
RENDER_COL    .data $00   ; Column counter during rendering
FNAME_PTR16   .data $0000 ; Pointer to filename string (null-terminated)

  .code

; Initialize rendering state
render_init
  JSR term_rows
  STA SCREEN_ROWS
  JSR term_cols
  STA SCREEN_COLS
  LDA #$00
  STA CURSOR_ROW
  STA CURSOR_COL
  STA MODE
  STA MODIFIED
  STA_LH16 VIEW_TOP16
  STA_LH16 FILE_LINE16
  RTS

; Full screen redraw
; Renders all visible lines plus status bar, positions cursor
render_screen
  JSR ansi_cursor_hide

  LDA #$00
  STA RENDER_ROW
  CP16 VIEW_TOP16 RENDER_LINE16

.row_loop
  ; Position cursor at start of this row
  LDA RENDER_ROW
  CLC
  ADC #$01         ; ANSI rows are 1-based
  STA ANSI_ROW
  LDA #$01
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Check if this is the status line row (last row)
  LDA RENDER_ROW
  CLC
  ADC #$01
  CMP SCREEN_ROWS
  BCS .row_done    ; At or past last row = done with text

  ; Check if line exists
  LDA RENDER_LINE16+$01
  CMP LINE_COUNT16+$01
  BCC .line_exists
  BNE .past_eof
  LDA RENDER_LINE16
  CMP LINE_COUNT16
  BCS .past_eof

.line_exists
  ; Render this line
  LDA RENDER_LINE16
  LDX RENDER_LINE16+$01
  JSR buf_get_line_ptr

  JSR render_line_chars
  JMP .clear_eol

.past_eof
  ; Draw tilde for lines past end of file
  LDA #'~'
  JSR write_b

.clear_eol
  JSR ansi_clear_line

.next_row
  INC RENDER_ROW
  INC16 RENDER_LINE16
  JMP .row_loop

.row_done
  ; Draw status line
  JSR render_status_line

  ; Position cursor
  JSR render_position_cursor

  JSR ansi_cursor_show
  JSR con_flush
  RTS

; Render just the status line (last row)
render_status_line
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #$01
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_reverse_video

  ; Print filename
  LDY #$00
.fname_loop
  LDA (FNAME_PTR16),Y
  BEQ .fname_done
  JSR write_b
  INY
  CPY #$20         ; Cap filename at 32 chars
  BCC .fname_loop
.fname_done

  ; Print read-only indicator
  LDA READONLY
  BEQ .not_readonly
  PRINT_STR str_ro_indicator
.not_readonly

  ; Print modified flag
  LDA MODIFIED
  BEQ .not_modified
  PRINT_STR str_mod_indicator
.not_modified

  ; Print separator
  PRINT_STR str_separator

  ; Print mode
  LDA MODE
  ASL
  TAX
  LDA mode_strings,X
  STA STR_PTR16
  LDA mode_strings+$01,X
  STA STR_PTR16+$01
  JSR write_string

  ; Print separator and line/col
  PRINT_STR str_separator

  ; Line number (1-based)
  CLC
  LDA FILE_LINE16
  ADC #$01
  STA TO_DECIMAL_VALUE16
  LDA FILE_LINE16+$01
  ADC #$00
  STA TO_DECIMAL_VALUE16+$01
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  LDA #','
  JSR write_b

  ; Column (1-based)
  LDA CURSOR_COL
  CLC
  ADC #$01
  JSR write_byte_dec

  ; Print total lines
  LDA #' '
  JSR write_b
  LDA #'/'
  JSR write_b

  CP16 LINE_COUNT16 TO_DECIMAL_VALUE16
  JSR to_decimal
  PRINT_STR TO_DECIMAL_RESULT

  ; Clear rest of status line and restore normal video
  JSR ansi_clear_line
  JSR ansi_normal_video
  RTS

; Position cursor at the editing position
render_position_cursor
  LDA CURSOR_ROW
  CLC
  ADC #$01         ; ANSI 1-based
  STA ANSI_ROW
  LDA CURSOR_COL
  CLC
  ADC #$01         ; ANSI 1-based
  STA ANSI_COL
  JSR ansi_move_cursor
  RTS

; Render just the current line (optimization for insert mode)
; Redraws the line at CURSOR_ROW and repositions cursor
render_current_line
  JSR ansi_cursor_hide

  LDA CURSOR_ROW
  CLC
  ADC #$01
  STA ANSI_ROW
  LDA #$01
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Get current line pointer
  LDA FILE_LINE16
  LDX FILE_LINE16+$01
  JSR buf_get_line_ptr

  JSR render_line_chars
  JSR ansi_clear_line

  JSR render_position_cursor
  JSR ansi_cursor_show
  JSR con_flush
  RTS

; Print line characters from BUF_PTR16 up to SCREEN_COLS or newline
; Replaces control chars with spaces. Clobbers A, Y.
render_line_chars
  LDA #$00
  STA RENDER_COL
  LDY #$00
.rlc_loop
  LDA (BUF_PTR16),Y
  CMP #$0A
  BEQ .rlc_done
  CMP #$20
  BCC .rlc_ctrl
  JSR write_b
  JMP .rlc_next
.rlc_ctrl
  LDA #' '
  JSR write_b
.rlc_next
  INY
  INC RENDER_COL
  LDA RENDER_COL
  CMP SCREEN_COLS
  BCC .rlc_loop
.rlc_done
  RTS

; === String constants ===
str_normal        .data "NORMAL" $00
str_insert        .data "INSERT" $00
str_command       .data "COMMAND" $00
mode_strings      .data str_normal str_insert str_command
str_ro_indicator  .data " [RO]" $00
str_mod_indicator .data " [+]" $00
str_separator     .data " - " $00
