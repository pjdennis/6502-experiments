; Search mode handler
;
; Handles '/' command for forward search in the text buffer.
; Pattern is stored in SEARCH_BUF for reuse with 'n' command.
;
; Memory layout:
;   SEARCH_BUF  ($E020) - Search pattern buffer
;   SEARCH_MAX  (223)   - Maximum pattern length (buffer ends before YANK_BUF)

SEARCH_BUF = $E020
SEARCH_MAX = 223        ; $E100 - $E020 - 1 (null terminator)

  .zeropage

SEARCH_LEN:   .byte     ; Length of current search pattern
SEARCH_IDX:   .byte     ; Current index during search input
SEARCH_LINE16: .word    ; Line number being searched
SEARCH_COL:   .byte     ; Column position of match

  .code

; Initialize search state (call once at startup)
search_init:
  LDA #0
  STA SEARCH_LEN
  RTS

; Handle '/' search command
; Shows '/' prompt, reads pattern, searches forward
search_handle:
  LDA #0
  STA SEARCH_IDX

  ; Show '/' prompt on status line
  JSR search_show_prompt

.search_read_loop:
  JSR input_read_byte

  CMP #KEY_ESC
  BEQ .search_cancel
  CMP #$1B
  BEQ .search_cancel
  CMP #KEY_ENTER
  BEQ .search_execute
  CMP #'\r'
  BEQ .search_execute
  CMP #KEY_BS
  BEQ .search_backspace
  CMP #$7F
  BEQ .search_backspace

  ; Printable character?
  CMP #' '
  BCC .search_read_loop
  CMP #$7F
  BCS .search_read_loop

  ; Add to buffer
  LDX SEARCH_IDX
  CPX #SEARCH_MAX
  BCS .search_read_loop   ; Buffer full
  STA SEARCH_BUF,X
  INC SEARCH_IDX

  ; Echo character
  JSR write_b
  JSR con_flush
  JMP .search_read_loop

.search_backspace:
  LDA SEARCH_IDX
  BEQ .search_cancel       ; Nothing to delete, cancel
  DEC SEARCH_IDX
  ; Erase character on screen
  LDA #'\b'
  JSR write_b
  LDA #' '
  JSR write_b
  LDA #'\b'
  JSR write_b
  JSR con_flush
  JMP .search_read_loop

.search_cancel:
  RTS

.search_execute:
  ; If empty search, reuse previous pattern
  LDA SEARCH_IDX
  BEQ .reuse_pattern
  ; Update search length
  STA SEARCH_LEN
  JMP .do_search

.reuse_pattern:
  ; Check if there's a previous pattern
  LDA SEARCH_LEN
  BEQ .search_cancel       ; No previous pattern either

.do_search:
  JSR search_forward
  RTS

; Show the '/' prompt on the status line
search_show_prompt:
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_clear_line
  LDA #'/'
  JSR write_b
  JSR con_flush
  RTS

; Search forward from current line
; Scans from FILE_LINE16+1, wraps around to FILE_LINE16
; Sets cursor to matching line/col on success
; Shows "Pattern not found" on failure
search_forward:
  ; Start searching from next line
  CLC
  ADCI16 FILE_LINE16, $0001, SEARCH_LINE16

.search_line_loop:
  ; Wrap around if past end
  CMP16 SEARCH_LINE16, LINE_COUNT16
  BCC .search_no_wrap
  SET16 $0000, SEARCH_LINE16
.search_no_wrap:

  ; Check if we've wrapped all the way back to start line
  CMP16 SEARCH_LINE16, FILE_LINE16
  BEQ .search_check_current

  ; Search this line
  JSR search_in_line
  BCC .search_found

  ; Next line
  INC16 SEARCH_LINE16
  JMP .search_line_loop

.search_check_current:
  ; Also check the current line (wrapping complete)
  JSR search_in_line
  BCC .search_found

  ; Not found
  JSR search_show_not_found
  RTS

.search_found:
  ; Move cursor to match
  CP16 SEARCH_LINE16, FILE_LINE16
  LDA SEARCH_COL
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  RTS

; Search for pattern in line SEARCH_LINE16
; Returns carry clear = found (SEARCH_COL set), carry set = not found
; Uses BUF_TEMP to save pattern index during inner loop
search_in_line:
  LDAX16 SEARCH_LINE16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of line

  ; Outer loop: try each starting position in the line
  LDY #0                     ; Y = start position in line
.outer_loop:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .not_found_in_line     ; Reached end of line

  ; Inner loop: compare pattern starting at position Y
  STY SEARCH_COL             ; Save potential match start
  LDX #0                     ; X = pattern index
.inner_loop:
  CPX SEARCH_LEN
  BEQ .found_in_line         ; Matched entire pattern

  ; Compute line offset: Y = SEARCH_COL + X
  STX BUF_TEMP               ; Save pattern index
  TXA
  CLC
  ADC SEARCH_COL
  TAY

  ; Check for end of line
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .not_found_here        ; Hit end of line during match

  ; Compare with pattern char
  LDX BUF_TEMP               ; Restore pattern index
  CMP SEARCH_BUF,X
  BNE .not_found_here

  INX                        ; Next pattern char
  JMP .inner_loop

.not_found_here:
  LDY SEARCH_COL
  INY                        ; Try next start position
  JMP .outer_loop

.found_in_line:
  ; SEARCH_COL already set to match position
  CLC
  RTS

.not_found_in_line:
  SEC
  RTS

; Show "Pattern not found: <pattern>" on status line
search_show_not_found:
  ; Show prompt area
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_clear_line

  PRINT_STR str_not_found

  ; Print the pattern
  LDX #0
.print_pattern:
  CPX SEARCH_LEN
  BEQ .print_done
  LDA SEARCH_BUF,X
  JSR write_b
  INX
  JMP .print_pattern
.print_done:
  JSR con_flush
  JSR input_read_byte         ; Wait for keypress
  RTS

; String constants
str_not_found: .asciiz "Pattern not found: "
