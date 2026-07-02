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
  JMP clamp_and_clear_count

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
  JMP clamp_and_clear_count

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
  CP16 LINE_LEN16, CURSOR_COL16  ; Set col = line_len (one past end)
  ; Fall through to .b_not_bol which DECs then scans backward to word start

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
  JSR word_end_x
  JMP clamp_and_clear_count

; Core word-end motion: move cursor to end of Xth word
; Input: X = count of words to move
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16, BUF_TEMP16
word_end_x:

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
  RTS

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


; Compute forward character range from cursor
; Input: X = char count (8-bit), LINE_LEN16 = line length (from check_cursor_in_line)
; Output: BUF_LEN16 = min(X, available chars on line), carry set if nothing
; Clobbers: A
compute_char_range_forward:
  STX BUF_LEN16
  LDA #0
  STA BUF_LEN16 + 1
  ; available = LINE_LEN16 - CURSOR_COL16
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_DST16
  CMP16 BUF_LEN16, BUF_DST16
  BCC .ok
  BEQ .ok
  CP16 BUF_DST16, BUF_LEN16     ; Clamp to available
.ok:
  TST16 BUF_LEN16
  BEQ .nothing
  CLC
  RTS
.nothing:
  SEC
  RTS


; --- Multi-line range computation routines ---

; Compute forward word range (multi-line) for dw/yw
; Applies exclusive-linewise adjustment when motion ends at col 0 of different line
; Input: X = word count
; Output: BUF_LEN16 = byte count, carry set if nothing to operate on
; Side effect: cursor restored to original position
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16
compute_multiline_word_range_forward:
  STX NORMAL_TEMP                   ; save word count (X clobbered by get_cursor_buf_ptr)
  CP16 FILE_LINE16, BUF_DST16      ; save start_line
  PUSH16 CURSOR_COL16              ; save original cursor
  PUSH16 FILE_LINE16
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = start_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16        ; save start_buf_ptr (safe across word_forward_x)
  LDX NORMAL_TEMP                   ; restore word count
  JSR word_forward_x                ; move cursor forward N words
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = end_buf_ptr
  ; Exclusive-linewise check: if different line AND col 0, back up past '\n'
  CMP16 FILE_LINE16, BUF_DST16
  BEQ .cmwrf_no_adj                 ; same line, no adjustment
  TST16 CURSOR_COL16
  BNE .cmwrf_no_adj                 ; not at col 0, no adjustment
  DEC16 BUF_PTR16                   ; back up past '\n'
.cmwrf_no_adj:
  SEC
  SBC16 BUF_PTR16, BUF_SRC16, BUF_LEN16
  POP16 FILE_LINE16                 ; restore cursor
  POP16 CURSOR_COL16
  TST16 BUF_LEN16
  BEQ .cmwrf_nothing
  CLC
  RTS
.cmwrf_nothing:
  SEC
  RTS

; Compute forward cw-semantics word range (multi-line) for cw
; Like word range but strips trailing whitespace when cursor starts on non-whitespace
; Input: X = word count
; Output: BUF_LEN16 = byte count, carry set if nothing to operate on
; Side effect: cursor restored to original position
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16
compute_multiline_cw_range_forward:
  STX NORMAL_TEMP                   ; save word count (X clobbered by get_cursor_buf_ptr)
  JSR get_cursor_buf_ptr            ; get char under cursor
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  PHA                               ; save original char class on stack
  PUSH16 CURSOR_COL16              ; save original cursor
  PUSH16 FILE_LINE16
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = start_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16        ; save start_buf_ptr
  LDX NORMAL_TEMP                   ; restore word count
  JSR word_forward_x                ; move cursor forward N words
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = end_buf_ptr
  ; No exclusive-linewise adjustment for cw:
  ; non-ws path strips trailing ws (handles it); ws path extends past word
  ; Check original char class to determine cw behavior
  TSX
  LDA $0105,X                      ; peek at original char class (under 4 bytes of PUSH16s)
  CMP #0
  BEQ .cmcrf_on_ws                 ; cursor was on whitespace: extend past word
  ; Non-whitespace: strip trailing whitespace (ce semantics)
.cmcrf_strip_loop:
  CMP16 BUF_PTR16, BUF_SRC16       ; would range become 0?
  BEQ .cmcrf_strip_done
  DEC16 BUF_PTR16                   ; back up
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BEQ .cmcrf_strip_loop             ; still whitespace, keep stripping
  INC16 BUF_PTR16                   ; non-ws, include this char
  JMP .cmcrf_strip_done
.cmcrf_on_ws:
  ; On whitespace: w landed at start of next word, extend past same-class chars
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
.cmcrf_ws_extend:
  INC16 BUF_PTR16
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .cmcrf_ws_extend
.cmcrf_strip_done:
  SEC
  SBC16 BUF_PTR16, BUF_SRC16, BUF_LEN16
  POP16 FILE_LINE16                 ; restore cursor
  POP16 CURSOR_COL16
  PLA                               ; clean up char class from stack
  TST16 BUF_LEN16
  BEQ .cmcrf_nothing
  CLC
  RTS
.cmcrf_nothing:
  SEC
  RTS

; Compute backward word range (multi-line) for db/yb/cb
; Input: X = word count
; Output: BUF_LEN16 = byte count, carry set if nothing to operate on
; Side effect: cursor STAYS at new backward position (start of range)
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16
compute_multiline_word_range_backward:
  STX NORMAL_TEMP                   ; save word count (X clobbered by get_cursor_buf_ptr)
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = original position (end of range)
  CP16 BUF_PTR16, BUF_SRC16        ; save end_ptr (safe across word_backward_x)
  LDX NORMAL_TEMP                   ; restore word count
  JSR word_backward_x               ; move cursor backward N words
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = new position (start of range)
  SEC
  SBC16 BUF_SRC16, BUF_PTR16, BUF_LEN16  ; range = end - start
  TST16 BUF_LEN16
  BEQ .cmwrb_nothing
  CLC
  RTS
.cmwrb_nothing:
  SEC
  RTS

; Compute forward word-end range (multi-line) for de/ye/ce
; e is an inclusive motion: range includes the character at the end position.
; Input: X = word count
; Output: BUF_LEN16 = byte count, carry set if nothing to operate on
; Side effect: cursor restored to original position
; Clobbers: A, X, Y, NORMAL_TEMP, WORD_CLASS, LINE_LEN16, BUF_PTR16, BUF_TEMP16
compute_multiline_word_end_range_forward:
  STX NORMAL_TEMP                   ; save word count (X clobbered by get_cursor_buf_ptr)
  PUSH16 CURSOR_COL16              ; save original cursor
  PUSH16 FILE_LINE16
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = start_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16        ; save start_buf_ptr (safe across word_end_x)
  LDX NORMAL_TEMP                   ; restore word count
  JSR word_end_x                    ; move cursor to end of Nth word
  JSR get_cursor_buf_ptr            ; BUF_PTR16 = end_buf_ptr
  INC16 BUF_PTR16                   ; inclusive: include end char
  SEC
  SBC16 BUF_PTR16, BUF_SRC16, BUF_LEN16
  POP16 FILE_LINE16                 ; restore cursor
  POP16 CURSOR_COL16
  TST16 BUF_LEN16
  BEQ .cmwerf_nothing
  CLC
  RTS
.cmwerf_nothing:
  SEC
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
  JMP clear_count
