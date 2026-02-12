; Search mode handler
;
; Handles '/' command for forward search in the text buffer.
; Pattern is stored in SEARCH_BUF for reuse with 'n' command.
;
; Memory layout:
;   SEARCH_BUF   ($DF54) - Search pattern buffer (after MARK_TBL)
;   SEARCH_LIMIT ($E000) - One past last byte of search buffer
;   SEARCH_MAX   (172)   - Maximum pattern length (SEARCH_LIMIT - SEARCH_BUF)

SEARCH_BUF   = $DF54
SEARCH_LIMIT = $E000
SEARCH_MAX   = SEARCH_LIMIT - SEARCH_BUF

  .zeropage

SEARCH_LEN:   .byte     ; Length of current search pattern
SEARCH_IDX:   .byte     ; Current index during search input
SEARCH_LINE16: .word    ; Line number being searched
SEARCH_COL:   .byte     ; Column position of match
SEARCH_DIR:   .byte     ; Search direction: 0=forward (/), 1=backward (?)

  .code

; Initialize search state (call once at startup)
search_init:
  LDA #0
  STA SEARCH_LEN
  STA SEARCH_DIR
  RTS

; Handle '/' search command
search_handle:
  LDA #'/'
  JMP search_input_handle

; Handle '?' backward search command
search_backward_handle:
  LDA #'?'
  ; Fall through

; Unified search input handler
; A = prompt character ('/' or '?')
search_input_handle:
  STA BUF_TEMP           ; Save prompt char
  LDA #0
  STA SEARCH_IDX

  ; Show prompt on status line
  LDA BUF_TEMP
  JSR show_prompt

.read_loop:
  JSR get_key

  CMP #KEY_ESC
  BEQ .cancel
  CMP #$1B
  BEQ .cancel
  CMP #KEY_ENTER
  BEQ .execute
  CMP #'\r'
  BEQ .execute
  CMP #KEY_BS
  BEQ .backspace
  CMP #$7F
  BEQ .backspace

  ; Printable character?
  CMP #' '
  BCC .read_loop
  CMP #$7F
  BCS .read_loop

  ; Add to buffer
  LDX SEARCH_IDX
  CPX #SEARCH_MAX
  BCS .read_loop   ; Buffer full
  STA SEARCH_BUF,X
  INC SEARCH_IDX

  ; Echo character
  JSR io_write
  JSR io_flush
  JMP .read_loop

.backspace:
  LDA SEARCH_IDX
  BEQ .cancel       ; Nothing to delete, cancel
  DEC SEARCH_IDX
  JSR erase_char
  JMP .read_loop

.cancel:
  RTS

.execute:
  ; If empty search, reuse previous pattern
  LDA SEARCH_IDX
  BEQ .reuse_pattern
  ; Update search length
  STA SEARCH_LEN
  JMP .do_search

.reuse_pattern:
  ; Check if there's a previous pattern
  LDA SEARCH_LEN
  BEQ .cancel       ; No previous pattern either

.do_search:
  ; Set direction based on prompt char
  LDA BUF_TEMP
  CMP #'?'
  BNE .forward
  LDA #1
  STA SEARCH_DIR
  JMP search_backward
.forward:
  LDA #0
  STA SEARCH_DIR
  JMP search_forward

; Search forward from current line
; Scans from FILE_LINE16+1, wraps around to FILE_LINE16
; Sets cursor to matching line/col on success
; Shows "Pattern not found" on failure
search_forward:
  ; Start searching from next line
  CLC
  ADCI16 FILE_LINE16, $0001, SEARCH_LINE16

.line_loop:
  ; Wrap around if past end
  CMP16 SEARCH_LINE16, LINE_COUNT16
  BCC .no_wrap
  SET16 $0000, SEARCH_LINE16
.no_wrap:

  ; Check if we've wrapped all the way back to start line
  CMP16 SEARCH_LINE16, FILE_LINE16
  BEQ .check_current

  ; Search this line
  JSR search_in_line
  BCC .found

  ; Next line
  INC16 SEARCH_LINE16
  JMP .line_loop

.check_current:
  ; Also check the current line (wrapping complete)
  JSR search_in_line
  BCC .found

  ; Not found
  JSR search_show_not_found
  RTS

.found:
  JMP search_move_to_match

; Search backward from current line
; Scans from FILE_LINE16-1, wraps around to FILE_LINE16
; Sets cursor to matching line/col on success
; Shows "Pattern not found" on failure
search_backward:
  ; Start searching from previous line
  TST16 FILE_LINE16
  BNE .no_wrap
  ; FILE_LINE16 is 0, wrap to last line
  SEC
  SBCI16 LINE_COUNT16, $0001, SEARCH_LINE16
  JMP .loop
.no_wrap:
  SEC
  SBCI16 FILE_LINE16, $0001, SEARCH_LINE16

.loop:
  ; Check if we've wrapped all the way back to start line
  CMP16 SEARCH_LINE16, FILE_LINE16
  BEQ .check_current

  ; Search this line
  JSR search_in_line
  BCC .found

  ; Previous line
  TST16 SEARCH_LINE16
  BEQ .wrap
  DEC16 SEARCH_LINE16
  JMP .loop

.wrap:
  ; At line 0, wrap to last line
  SEC
  SBCI16 LINE_COUNT16, $0001, SEARCH_LINE16
  JMP .loop

.check_current:
  ; Also check the current line (wrapping complete)
  JSR search_in_line
  BCC .found

  ; Not found
  JSR search_show_not_found
  RTS

.found:
  JMP search_move_to_match

; Move cursor to search match position
; SEARCH_LINE16 = line of match, SEARCH_COL = column of match
search_move_to_match:
  CP16 SEARCH_LINE16, FILE_LINE16
  LDA SEARCH_COL
  STA CURSOR_COL16
  LDA #0
  STA CURSOR_COL16 + 1
  JSR ensure_cursor_visible
  JMP clamp_cursor_col

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
  BCS .not_found_here        ; Sum > 255, can't index with Y
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
  BEQ .not_found_in_line     ; Y wrapped past 255
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
  JSR status_line_clear
  PRINT_STR str_not_found

  ; Print the pattern
  LDX #0
.print_pattern:
  CPX SEARCH_LEN
  BEQ .print_done
  LDA SEARCH_BUF,X
  JSR io_write
  INX
  JMP .print_pattern
.print_done:
  JSR io_flush
  JSR get_key                  ; Wait for keypress
  RTS

; String constants
str_not_found: .asciiz "Pattern not found: "
