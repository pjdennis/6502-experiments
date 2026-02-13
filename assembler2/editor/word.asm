; Word motion support - character classification and word boundary routines
;
; Provides char_class (classify byte) and word motions w, b, e.

  .zeropage

WORD_CLASS:    .byte     ; Character class of current char
WORD_PREV:     .byte     ; Previous character class (for boundary detection)

  .code

; Classify byte in A -> A = 0 (whitespace), 1 (word: a-zA-Z0-9_), 2 (punct)
char_class:
  CMP #' '
  BEQ .whitespace
  CMP #'\t'
  BEQ .whitespace
  CMP #'\n'
  BEQ .whitespace
  ; Check a-z
  CMP #'a'
  BCC .not_lower
  CMP #'z' + 1
  BCC .word
.not_lower:
  ; Check A-Z
  CMP #'A'
  BCC .not_upper
  CMP #'Z' + 1
  BCC .word
.not_upper:
  ; Check 0-9
  CMP #'0'
  BCC .not_digit
  CMP #'9' + 1
  BCC .word
.not_digit:
  ; Check underscore
  CMP #'_'
  BEQ .word
  ; Everything else is punctuation
  LDA #2
  RTS
.whitespace:
  LDA #0
  RTS
.word:
  LDA #1
  RTS

; --- w command: move to start of next word ---
; Accepts count prefix.
; Skip current word-class chars, skip whitespace.
; If at EOL, move to next line col 0.
normal_word_forward:
  JSR get_batched_count
  JSR word_forward_x
  JSR clamp_cursor_col
  JMP clear_count

; Core word-forward motion: move cursor forward X words
; Input: X = count of words to move
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16
word_forward_x:

.w_loop:
  STX NORMAL_TEMP         ; Save counter

  ; Get current line length
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .w_next_line        ; Empty line -> try next line

  ; If cursor at or past end, go to next line
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .w_next_line

  ; Get line pointer + cursor col
  JSR get_cursor_buf_ptr  ; BUF_PTR16 = cursor position

  ; Get class of current char
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS

  ; If current char is whitespace, just skip whitespace
  CMP #0
  BEQ .w_skip_ws

  ; Skip chars of same class as current
.w_skip_same:
  INC16 CURSOR_COL16
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .w_at_eol
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .w_skip_same

  ; Class changed - if now whitespace, skip it
  CMP #0
  BNE .w_done_one         ; Non-whitespace non-same class = word start

  ; Skip whitespace
.w_skip_ws:
  INC16 CURSOR_COL16
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .w_at_eol
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BEQ .w_skip_ws
  ; Found non-whitespace = word start
  JMP .w_done_one

.w_at_eol:
  ; At end of line - go to next line col 0 (acts like reaching word start)
.w_next_line:
  ; Check if there's a next line
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .w_done_final       ; No next line, stay put
  INC16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16

.w_done_one:
  LDX NORMAL_TEMP
  DEX
  BEQ .w_done_final
  JMP .w_loop

.w_done_final:
  RTS

; --- b command: move to start of previous word ---
; Accepts count prefix.
normal_word_backward:
  JSR get_batched_count
  JSR word_backward_x
  JSR clamp_cursor_col
  JMP clear_count

; Core word-backward motion: move cursor backward X words
; Input: X = count of words to move
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16
word_backward_x:

.b_loop:
  STX NORMAL_TEMP         ; Save counter

  ; If at col 0, move to previous line end
  TST16 CURSOR_COL16
  BNE .b_not_bol

  ; At beginning of line - move to prev line end
  TST16 FILE_LINE16
  BEQ .b_done_final       ; Already at first line, col 0
  DEC16 FILE_LINE16
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .b_done_one         ; Prev line is empty, at col 0
  SEC
  SBCI16 LINE_LEN16, 1, CURSOR_COL16
  JMP .b_done_one

.b_not_bol:
  ; Move left one to start scanning
  DEC16 CURSOR_COL16

  ; Skip whitespace backward
.b_skip_ws:
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .b_found_nonws
  ; Still whitespace - move left
  TST16 CURSOR_COL16
  BEQ .b_done_one         ; Hit col 0 during whitespace skip
  DEC16 CURSOR_COL16
  JMP .b_skip_ws

.b_found_nonws:
  ; Remember class of this non-whitespace char
  STA WORD_CLASS

  ; Scan backward through same-class chars
.b_skip_same:
  TST16 CURSOR_COL16
  BEQ .b_done_one         ; At col 0, this is the word start
  DEC16 CURSOR_COL16
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .b_skip_same
  ; Different class - word start is one to the right
  INC16 CURSOR_COL16

.b_done_one:
  LDX NORMAL_TEMP
  DEX
  BEQ .b_done_final
  JMP .b_loop

.b_done_final:
  RTS

; --- e command: move to end of current/next word ---
; Accepts count prefix.
normal_word_end:
  JSR get_batched_count

.e_loop:
  STX NORMAL_TEMP         ; Save counter

  ; Get current line length
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .e_not_empty
  JMP .e_next_line        ; Empty line -> try next line
.e_not_empty:

  ; Move right first (e moves past current position)
  SEC
  SBCI16 LINE_LEN16, 1, BUF_TEMP16  ; BUF_TEMP16 = max col
  CMP16 CURSOR_COL16, BUF_TEMP16
  BCC .e_can_move
  JMP .e_next_line        ; Already at or past last char
.e_can_move:

  INC16 CURSOR_COL16

  ; Skip whitespace
.e_skip_ws:
  CMP16 CURSOR_COL16, LINE_LEN16
  BCC .e_ws_in_range
  JMP .e_next_line        ; At EOL during whitespace skip
.e_ws_in_range:
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .e_found_nonws
  INC16 CURSOR_COL16
  JMP .e_skip_ws

.e_found_nonws:
  ; Remember class
  STA WORD_CLASS

  ; Skip forward through same-class chars, stop on last one
.e_skip_same:
  ; Check if next char exists and is same class
  CLC
  ADCI16 CURSOR_COL16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_LEN16
  BCS .e_done_one         ; Next would be past end, current is the end
  CP16 BUF_PTR16, CURSOR_COL16  ; Advance cursor
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .e_skip_same
  ; Different class - back up one
  DEC16 CURSOR_COL16

.e_done_one:
  LDX NORMAL_TEMP
  DEX
  BEQ .e_done_final
  JMP .e_loop

.e_done_final:
  JSR clamp_cursor_col
  JMP clear_count

.e_next_line:
  ; Move to next line and find first word end
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCC .e_has_next
  JMP .e_done_final       ; No next line
.e_has_next:
  INC16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16

  ; Skip whitespace on new line
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .e_nl_not_empty
  JMP .e_done_one         ; Empty line counts as done for e
.e_nl_not_empty:

.e_newline_skip_ws:
  CMP16 CURSOR_COL16, LINE_LEN16
  BCC .e_nl_ws_ok
  JMP .e_done_one         ; All whitespace line
.e_nl_ws_ok:
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .e_newline_found
  INC16 CURSOR_COL16
  JMP .e_newline_skip_ws

.e_newline_found:
  ; Found non-whitespace, now skip to end of this word
  STA WORD_CLASS
.e_newline_same:
  CLC
  ADCI16 CURSOR_COL16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_LEN16
  BCC .e_nl_same_ok
  JMP .e_done_one         ; At end of line
.e_nl_same_ok:
  CP16 BUF_PTR16, CURSOR_COL16
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .e_newline_same
  DEC16 CURSOR_COL16
  JMP .e_done_one

; --- Word boundary helpers (used by dw/db/cw/cb) ---

; Skip forward past chars of WORD_CLASS, starting from BUF_LEN16
; Input: BUF_LEN16 = start col, LINE_LEN16 = line length, WORD_CLASS = class to skip
; Output: BUF_LEN16 = col after last same-class char
;         Carry set = at/past end of line
;         Carry clear = found different class, A = new class
; Clobbers: A, X, Y, BUF_PTR16
skip_word_class_forward:
  INC16 BUF_LEN16
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .swcf_at_end
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ skip_word_class_forward
  CLC
  RTS
.swcf_at_end:
  RTS

; Find word start scanning backward from CURSOR_COL16 - 1
; Output: BUF_LEN16 = column of word start
; Assumes CURSOR_COL16 > 0 (caller checks)
; Clobbers: A, X, Y, BUF_PTR16, WORD_CLASS
find_word_start_backward:
  SEC
  SBCI16 CURSOR_COL16, 1, BUF_LEN16

  ; Skip whitespace backward
.fwsb_skip_ws:
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .fwsb_found_nonws
  TST16 BUF_LEN16
  BEQ .fwsb_done
  DEC16 BUF_LEN16
  JMP .fwsb_skip_ws

.fwsb_found_nonws:
  STA WORD_CLASS

  ; Skip same-class chars backward
.fwsb_skip_same:
  TST16 BUF_LEN16
  BEQ .fwsb_done
  DEC16 BUF_LEN16
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .fwsb_skip_same
  INC16 BUF_LEN16           ; Different class - word starts one to right

.fwsb_done:
  RTS

; Scan forward N words from BUF_LEN16
; Input: X = count, BUF_LEN16 = start column, LINE_LEN16 = line length
; Output: BUF_LEN16 = column after N words (stops at EOL)
; Clobbers: A, X, Y, BUF_PTR16, WORD_CLASS, NORMAL_TEMP
scan_words_forward:
.swf_loop:
  STX NORMAL_TEMP

  ; At/past end of line? Done.
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .swf_done

  ; Classify char at BUF_LEN16
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
  CMP #0
  BEQ .swf_skip_ws

  ; Skip same-class chars
  JSR skip_word_class_forward
  BCS .swf_done_one          ; Hit EOL
  CMP #0
  BNE .swf_done_one          ; Hit different non-ws class

  ; Skip trailing whitespace
.swf_skip_ws:
  LDA #0
  STA WORD_CLASS
  JSR skip_word_class_forward

.swf_done_one:
  LDX NORMAL_TEMP
  DEX
  BNE .swf_loop

.swf_done:
  RTS

; Scan backward N words from CURSOR_COL16
; Input: X = count, CURSOR_COL16 = start position (must be > 0)
; Output: CURSOR_COL16 = position after scanning back N words (stops at BOL)
; Clobbers: A, X, Y, BUF_PTR16, BUF_LEN16, WORD_CLASS, NORMAL_TEMP
scan_words_backward:
.swb_loop:
  STX NORMAL_TEMP
  TST16 CURSOR_COL16
  BEQ .swb_done               ; At col 0, stop
  JSR find_word_start_backward ; BUF_LEN16 = word start
  CP16 BUF_LEN16, CURSOR_COL16
  LDX NORMAL_TEMP
  DEX
  BNE .swb_loop
.swb_done:
  RTS

; Scan forward N words with cw semantics from BUF_LEN16
; Like scan_words_forward but does NOT skip trailing whitespace on non-ws chars.
; On whitespace: skips ws then next word class.
; Input: X = count, BUF_LEN16 = start column, LINE_LEN16 = line length
; Output: BUF_LEN16 = column after N words (stops at EOL)
; Clobbers: A, X, Y, BUF_PTR16, WORD_CLASS, NORMAL_TEMP
scan_cw_forward:
.scf_loop:
  STX NORMAL_TEMP

  ; At/past end of line? Done.
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .scf_done

  ; Classify char at BUF_LEN16
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
  CMP #0
  BEQ .scf_on_ws

  ; Non-whitespace: skip same-class chars only (no trailing ws)
  JSR skip_word_class_forward
  JMP .scf_done_one

.scf_on_ws:
  ; On whitespace: skip ws, then skip next word class
  JSR skip_word_class_forward
  BCS .scf_done_one           ; Hit EOL
  STA WORD_CLASS
  JSR skip_word_class_forward

.scf_done_one:
  LDX NORMAL_TEMP
  DEX
  BNE .scf_loop

.scf_done:
  RTS

; Get buffer pointer at BUF_LEN16 offset on current line
; Sets BUF_PTR16 = start of FILE_LINE16 + BUF_LEN16
; Clobbers A, X, Y
get_scan_buf_ptr:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CLC
  ADC16 BUF_LEN16, BUF_PTR16, BUF_PTR16
  RTS

; --- ^ command: move to first non-blank character ---
normal_first_nonblank:
  LDA #0
  STA_LH16 CURSOR_COL16

  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .done               ; Empty line

  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr     ; BUF_PTR16 = start of line

  LDY #0
.scan:
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .not_space
  INY
  BNE .scan               ; Continue scanning (up to 255)
  JMP .done               ; All spaces (unlikely but safe)
.not_space:
  CMP #'\n'
  BEQ .done               ; All spaces before newline
  ; Found first non-blank at offset Y
  STY CURSOR_COL16
  LDA #0
  STA CURSOR_COL16 + 1

.done:
  LDA #0
  STA RENDER_FLAG
  JMP clear_count
