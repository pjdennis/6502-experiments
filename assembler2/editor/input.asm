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
KEY_DEL   = $88
KEY_ESC   = $1B
KEY_ENTER = $0D
KEY_BS    = $08
KEY_TAB   = $09

  .zeropage
INPUT_TEMP:  .byte     ; Temp for input processing
SPIN_COUNT:  .byte     ; Spin loop counter for escape detection
PUSHBACK:    .byte     ; Pushback byte ($00 = none)
HAS_PUSHBACK: .byte    ; $FF if pushback has a byte
KEY_DECODED:     .byte  ; Buffered decoded key
HAS_KEY_DECODED: .byte  ; $FF if KEY_DECODED has a value

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
  JSR con_read
  RTS

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
  JSR con_ready       ; Non-blocking poll
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
  JSR con_ready
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
  BNE .not_csi
  ; CSI sequence - read the final byte
  JSR input_read_byte
  STA INPUT_TEMP

  ; Check for arrow keys: A=up, B=down, C=right, D=left
  CMP #'A'
  BEQ .key_up
  CMP #'B'
  BEQ .key_down
  CMP #'C'
  BEQ .key_right
  CMP #'D'
  BEQ .key_left
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
  ; It's a digit 1-6, read the next char expecting ~
  STA INPUT_TEMP
  JSR input_read_byte
  CMP #'~'
  BNE .unknown_eat ; unknown sequence, discard
  LDA INPUT_TEMP
  CMP #'3'
  BEQ .key_delete
  CMP #'5'
  BEQ .key_pgup
  CMP #'6'
  BEQ .key_pgdn
  ; Unknown Fn key - return ESC
  LDA #KEY_ESC
  RTS

.key_up:
  LDA #KEY_UP
  RTS
.key_down:
  LDA #KEY_DOWN
  RTS
.key_right:
  LDA #KEY_RIGHT
  RTS
.key_left:
  LDA #KEY_LEFT
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

.not_tilde:
.unknown_csi:
.unknown_eat:
  ; Unknown escape sequence - return ESC
  LDA #KEY_ESC
  RTS
.not_csi:
  ; Byte after ESC was not '[' - push it back and return bare ESC
  JSR input_unread
  LDA #KEY_ESC
  RTS

.done:
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
