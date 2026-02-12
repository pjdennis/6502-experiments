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

  .endif
