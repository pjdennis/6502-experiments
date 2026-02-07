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
INPUT_TEMP  .data $00   ; Temp for input processing
SPIN_COUNT  .data $00   ; Spin loop counter for escape detection

  .code

; Read one key from console, handling escape sequences
; Returns key code in A
; Arrow keys: KEY_UP ($80), KEY_DOWN ($81), KEY_LEFT ($82), KEY_RIGHT ($83)
; Bare ESC: $1B
; Backspace ($7F or $08) normalized to KEY_BS ($08)
; Clobbers X, Y
read_key
  JSR con_read

  ; Normalize backspace: $7F -> $08
  CMP #$7F
  BNE .not_del_bs
  LDA #KEY_BS
  RTS
.not_del_bs

  ; Check for ESC
  CMP #$1B
  BNE .done

  ; Got ESC - check if more bytes follow (escape sequence)
  ; Spin loop to wait briefly for next byte
  LDA #$FF
  STA SPIN_COUNT
.spin
  JSR con_ready
  CMP #$FF
  BEQ .got_more
  DEC SPIN_COUNT
  BNE .spin
  ; No more bytes - bare ESC
  LDA #KEY_ESC
  RTS

.got_more
  ; Read the next byte - should be '['
  JSR con_read
  CMP #'['
  BNE .not_csi
  ; CSI sequence - read the final byte
  JSR con_read
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
  JSR con_read
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

.key_up
  LDA #KEY_UP
  RTS
.key_down
  LDA #KEY_DOWN
  RTS
.key_right
  LDA #KEY_RIGHT
  RTS
.key_left
  LDA #KEY_LEFT
  RTS
.key_home
  LDA #KEY_HOME
  RTS
.key_end
  LDA #KEY_END
  RTS
.key_delete
  LDA #KEY_DEL
  RTS
.key_pgup
  LDA #KEY_PGUP
  RTS
.key_pgdn
  LDA #KEY_PGDN
  RTS

.not_tilde
.unknown_csi
.unknown_eat
.not_csi
  ; Unknown escape sequence - return ESC
  LDA #KEY_ESC
  RTS

.done
  RTS
