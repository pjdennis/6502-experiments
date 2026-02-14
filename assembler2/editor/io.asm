; I/O abstraction layer
;
; Provides io_write, io_read, io_flush, io_ready that map to either
; console I/O (write_b, con_read, con_flush, con_ready) or serial I/O
; depending on whether terminal_mode is defined.

  .ifndef terminal_mode

; Console mode: direct aliases (zero overhead)
io_write = write_b
io_flush = con_flush
io_read  = con_read
io_ready = con_ready

  .else

; Terminal mode: serial I/O with spin loops

  .zeropage
SERIAL_BYTE:     .byte    ; Byte buffered by io_ready
SERIAL_HAS_BYTE: .byte    ; $FF if SERIAL_BYTE valid
DSR_VALUE:       .byte    ; Temp for parsing DSR decimal values
DSR_TERM:        .byte    ; Terminator char for parse_dsr_value

  .code

; Write byte in A to serial output (blocking spin loop)
; A, X, Y preserved (same contract as write_b)
io_write:
  JSR serial_write
  BCS io_write
  RTS

; Flush - no-op for serial (data is sent immediately)
io_flush:
  RTS

; Read one byte from serial input (blocking)
; Returns byte in A
io_read:
  LDA SERIAL_HAS_BYTE
  BNE .from_buffer
.spin:
  JSR serial_read
  BCS .spin
  RTS
.from_buffer:
  LDA #$00
  STA SERIAL_HAS_BYTE
  LDA SERIAL_BYTE
  RTS

; Non-blocking check if input byte is available
; Returns: A=$FF if ready, A=$00 if not
; Preserves X, Y
io_ready:
  LDA SERIAL_HAS_BYTE
  BNE .ready
  JSR serial_read
  BCS .not_ready
  STA SERIAL_BYTE
  LDA #$FF
  STA SERIAL_HAS_BYTE
.ready:
  LDA #$FF
  RTS
.not_ready:
  LDA #$00
  RTS

; Query terminal size via DSR (Device Status Report)
; Sends ESC[999;999H to move cursor to bottom-right (clamped by terminal)
; Then sends ESC[6n to query cursor position
; Parses response ESC[{rows};{cols}R
; Stores results in SCREEN_ROWS and SCREEN_COLS
query_terminal_size:
  ; Send ESC[999;999H (move cursor to max position)
  LDA #$1B
  JSR io_write
  LDA #'['
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #';'
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #'9'
  JSR io_write
  LDA #'H'
  JSR io_write

  ; Send ESC[6n (request cursor position)
  LDA #$1B
  JSR io_write
  LDA #'['
  JSR io_write
  LDA #'6'
  JSR io_write
  LDA #'n'
  JSR io_write

  ; Read response: ESC[{rows};{cols}R
  ; Skip ESC
  JSR io_read
  ; Skip [
  JSR io_read

  ; Parse rows (decimal digits until ';')
  LDA #';'
  JSR parse_dsr_value
  LDA DSR_VALUE
  STA SCREEN_ROWS

  ; Parse cols (decimal digits until 'R')
  LDA #'R'
  JSR parse_dsr_value
  LDA DSR_VALUE
  STA SCREEN_COLS

  ; Send ESC[H to move cursor back to home position
  LDA #$1B
  JSR io_write
  LDA #'['
  JSR io_write
  LDA #'H'
  JSR io_write
  RTS

; Parse decimal digits from serial input until terminator char
; Input: A = terminator character
; Output: DSR_VALUE = parsed decimal value
; Clobbers: A
parse_dsr_value:
  STA DSR_TERM
  LDA #0
  STA DSR_VALUE
.loop:
  JSR io_read
  CMP DSR_TERM
  BEQ .done
  SEC
  SBC #'0'
  PHA
  LDA DSR_VALUE
  ASL        ; *2
  STA DSR_VALUE
  ASL        ; *4
  ASL        ; *8
  CLC
  ADC DSR_VALUE  ; *10
  STA DSR_VALUE
  PLA
  CLC
  ADC DSR_VALUE
  STA DSR_VALUE
  JMP .loop
.done:
  RTS

  .endif
