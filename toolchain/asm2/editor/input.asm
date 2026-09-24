; Keyboard input library with escape sequence parsing
;
; Arrow keys are returned as high-bit codes:
KEY_UP    = $80
KEY_DOWN  = $81
KEY_LEFT  = $82
KEY_RIGHT = $83
KEY_HOME  = $84
KEY_END   = $85
KEY_PGUP  = $86
KEY_PGDN  = $87
KEY_DEL       = $88
KEY_WORD_FWD  = $89    ; Ctrl+Right (ESC[1;5C)
KEY_WORD_BACK = $8A    ; Ctrl+Left  (ESC[1;5D)
KEY_ESC   = $1B
KEY_ENTER = $0D
KEY_BS    = $08
KEY_TAB   = $09

  .zeropage

INPUT_TEMP:       .byte  ; Temp for input processing
SPIN_COUNT:       .byte  ; Spin loop counter for escape detection
PUSHBACK:         .byte  ; Pushback byte ($00 = none)
HAS_PUSHBACK:     .byte  ; $FF if pushback has a byte
KEY_DECODED:      .byte  ; Buffered decoded key
HAS_KEY_DECODED:  .byte  ; $FF if KEY_DECODED has a value

  .code

; Read one byte from input, with pushback support
; Returns byte in A
input_read_byte:
  LDA HAS_PUSHBACK
  BEQ .no_pushback
  LDA #0
  STA HAS_PUSHBACK
  LDA PUSHBACK
  RTS
.no_pushback:
  JMP io_read

; Push back one byte into the input stream
; A = byte to push back
input_unread:
  STA PUSHBACK
  LDA #$FF
  STA HAS_PUSHBACK
  RTS

; Check if input is available (non-blocking)
; Returns: A=$FF if ready, A=$00 if not
input_ready:
  LDA HAS_PUSHBACK
  BNE .ready          ; Pushback byte waiting - ready
  JSR io_ready       ; Non-blocking poll
  RTS
.ready:
  LDA #$FF
  RTS

; Count pending keys matching BUF_TEMP
; Input: BUF_TEMP = key code to match
; Returns: X = count of matching keys (0 to BATCH_MAX)
; Non-matching key is pushed back
count_pending_key:
  LDX #0
.loop:
  JSR key_ready
  CMP #$FF
  BNE .done
  JSR get_key
  CMP BUF_TEMP
  BEQ .match
  ; Push back the non-matching key
  JSR unget_key
  JMP .done
.match:
  INX
  CPX #BATCH_MAX
  BEQ .done
  JMP .loop
.done:
  RTS

; Read one key from console, handling escape sequences
; Returns key code in A
; Arrow keys: KEY_UP ($80), KEY_DOWN ($81), KEY_LEFT ($82), KEY_RIGHT ($83)
; Bare ESC: $1B
; Backspace ($7F or $08) normalized to KEY_BS ($08)
; Clobbers X, Y
read_key:
  JSR input_read_byte

  ; Skip non-ASCII bytes (>= $80): UTF-8 multi-byte sequences
  ; would collide with KEY_UP..KEY_DEL codes ($80-$88)
  CMP #$80
  BCC .not_high_byte
  LDA #$00         ; Harmless: no dispatch match, not printable (< $20)
  RTS
.not_high_byte:

  ; Normalize backspace: $7F -> $08
  CMP #$7F
  BNE .not_del_bs
  LDA #KEY_BS
  RTS
.not_del_bs:

  ; Check for ESC
  CMP #$1B
  BNE .not_esc
  JMP .is_esc
.not_esc:
  JMP .done
.is_esc:

  ; Got ESC - check if more bytes follow (escape sequence)
  ; Spin loop to wait briefly for next byte
  LDA #$FF
  STA SPIN_COUNT
.spin:
  JSR io_ready
  CMP #$FF
  BEQ .got_more
  DEC SPIN_COUNT
  BNE .spin
  ; No more bytes - bare ESC
  LDA #KEY_ESC
  RTS

.got_more:
  ; Read the next byte - should be '['
  JSR input_read_byte
  CMP #'['
  BEQ .is_csi
  JMP .not_csi
.is_csi:
  ; CSI sequence - read the final byte
  JSR input_read_byte
  STA INPUT_TEMP

  ; Check for arrow keys: A=up, B=down, C=right, D=left (table lookup)
  CMP #'A'
  BCC .not_arrow
  CMP #'E'
  BCS .not_arrow
  SBC #'A'-1              ; C=0 from failed BCS: yields 0-3
  TAX
  LDA .arrow_tbl,X
  RTS
.arrow_tbl:
  .byte $80, $81, $83, $82  ; KEY_UP, KEY_DOWN, KEY_RIGHT, KEY_LEFT
                            ; (C -> right, D -> left: non-linear order)
.not_arrow:
  CMP #'H'
  BEQ .key_home
  CMP #'F'
  BEQ .key_end

  ; Check for sequences with numeric parameter: ESC[N~
  ; where N is: 1=Home, 3=Delete, 4=End, 5=PgUp, 6=PgDn
  CMP #'~'
  BEQ .not_tilde  ; ~ can't be the char right after [, need a digit first

  ; Could be a digit followed by ~
  CMP #'1'
  BCC .unknown_csi
  CMP #'7'
  BCS .unknown_csi
  ; It's a digit 1-6, read the next char expecting ~ or ;
  STA INPUT_TEMP
  JSR input_read_byte
  CMP #'~'
  BEQ .is_tilde
  CMP #';'
  BNE .unknown_eat        ; Not ~ or ; -> consume rest, return $00
  ; ESC[digit;modifier<final> - read modifier
  JSR input_read_byte
  CMP #'5'                ; Ctrl modifier?
  BNE .eat_after_semi     ; No -> consume rest, return $00
  JSR input_read_byte     ; Read final byte
  CMP #'C'
  BEQ .key_word_fwd
  CMP #'D'
  BEQ .key_word_back
  ; Unknown Ctrl+key final byte - already consumed if >= $40
  CMP #$40
  BCS .csi_consumed
  JSR consume_csi_tail
  JMP .csi_consumed
.eat_after_semi:
  ; Non-Ctrl modifier - consume remaining bytes
  CMP #$40
  BCS .csi_consumed
  JSR consume_csi_tail
  JMP .csi_consumed
.is_tilde:
  LDA INPUT_TEMP
  CMP #'3'
  BEQ .key_delete
  CMP #'5'
  BEQ .key_pgup
  CMP #'6'
  BEQ .key_pgdn
  ; Unknown Fn key (e.g. Insert) - return no-op
  LDA #$00
  RTS

.key_home:
  LDA #KEY_HOME
  RTS
.key_end:
  LDA #KEY_END
  RTS
.key_delete:
  LDA #KEY_DEL
  RTS
.key_pgup:
  LDA #KEY_PGUP
  RTS
.key_pgdn:
  LDA #KEY_PGDN
  RTS
.key_word_fwd:
  LDA #KEY_WORD_FWD
  RTS
.key_word_back:
  LDA #KEY_WORD_BACK
  RTS

.not_tilde:
.unknown_csi:
.unknown_eat:
  ; Unknown CSI sequence - consume remaining bytes and return no-op
  ; CSI final bytes are >= $40 ('@'-'~'); params/intermediates are < $40
  CMP #$40
  BCS .csi_consumed      ; Last byte read was already a final byte
  JSR consume_csi_tail   ; Drain until final byte
.csi_consumed:
  LDA #$00
  RTS
.not_csi:
  ; Check for SS3 sequences: ESC O <final byte> (F1-F4 on some terminals)
  CMP #'O'
  BNE .not_ss3
  JSR input_read_byte    ; Read and discard the final byte
  LDA #$00
  RTS
.not_ss3:
  ; Unknown byte after ESC - push it back and return bare ESC
  JSR input_unread
  LDA #KEY_ESC
  RTS

.done:
  RTS

; Drain remaining bytes of a CSI sequence until final byte (>= $40)
consume_csi_tail:
  JSR input_read_byte
  CMP #$40
  BCC consume_csi_tail   ; Keep reading param/intermediate bytes (< $40)
  RTS

; Read one decoded key (with decoded pushback support)
; Returns key code in A. Preserves X, Y.
get_key:
  LDA HAS_KEY_DECODED
  BEQ .no_decoded
  LDA #0
  STA HAS_KEY_DECODED
  LDA KEY_DECODED
  RTS
.no_decoded:
  TXA
  PHA
  TYA
  PHA
  JSR read_key
  STA KEY_DECODED
  PLA
  TAY
  PLA
  TAX
  LDA KEY_DECODED
  RTS

; Push back one decoded key
; A = key to push back. Preserves X, Y.
unget_key:
  STA KEY_DECODED
  LDA #$FF
  STA HAS_KEY_DECODED
  RTS

; Check if a decoded key is available (non-blocking)
; Returns: A=$FF if ready, A=$00 if not. Preserves X, Y.
key_ready:
  LDA HAS_KEY_DECODED
  BNE .ready
  JSR input_ready
  CMP #$FF
  BNE .not_ready
  ; Raw input available - speculatively decode
  TXA
  PHA
  TYA
  PHA
  JSR read_key
  STA KEY_DECODED
  LDA #$FF
  STA HAS_KEY_DECODED
  PLA
  TAY
  PLA
  TAX
.ready:
  LDA #$FF
  RTS
.not_ready:
  LDA #0
  RTS
