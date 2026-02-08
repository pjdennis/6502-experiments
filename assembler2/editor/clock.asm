; Clock - displays a running HH:MM:SS clock
; Uses cycle-counting busy loops calibrated for 1 MHz
; Press 'q' to quit

* = $0400

  JMP main

  .include environment.asm

  .zeropage
SECONDS   .byte 0
MINUTES   .byte 0
HOURS     .byte 0
DELAY_CNT .byte 0
TEMP      .byte 0

  .code

main
  ; Initialize time to 00:00:00
  LDA #$00
  STA SECONDS
  STA MINUTES
  STA HOURS

  JSR clear_screen

.main_loop
  ; Move cursor to home position
  JSR cursor_home

  ; Display HH:MM:SS
  LDA HOURS
  JSR print_two_digits
  LDA #':'
  JSR write_b
  LDA MINUTES
  JSR print_two_digits
  LDA #':'
  JSR write_b
  LDA SECONDS
  JSR print_two_digits

  ; Print instruction
  LDX #$00
.print_msg
  LDA msg,X
  BEQ .msg_done
  JSR write_b
  INX
  BNE .print_msg
.msg_done

  JSR con_flush

  ; Delay approximately 1 second (1,000,000 cycles at 1 MHz)
  ; Outer loop: DELAY_CNT iterations
  ; Each middle iteration (Y=0 -> 256 inner): ~329,217 cycles
  ; 3 outer iterations: ~987,667 cycles
  ; Remaining ~12,333 cycles covered by display overhead
  LDA #$03
  STA DELAY_CNT
.delay_outer
  LDY #$00             ; 2 cycles
.delay_middle
  LDX #$00             ; 2 cycles
.delay_inner
  DEX                  ; 2 cycles
  BNE .delay_inner     ; 3 cycles (taken), 2 cycles (not taken)
  ; Inner loop: 255*5 + 4 = 1279 cycles + LDX = 1281
  DEY                  ; 2 cycles
  BNE .delay_middle    ; 3 cycles (taken), 2 cycles (not taken)
  ; Middle loop: 256*(1281+5)-1 = 329,215 + LDY = 329,217
  DEC DELAY_CNT        ; 5 cycles
  BNE .delay_outer     ; 3 cycles (taken), 2 cycles (not taken)

  ; Check for 'q' keypress (non-blocking)
  JSR con_ready
  CMP #$FF
  BNE .no_key
  JSR con_read
  CMP #'q'
  BEQ .quit
.no_key

  ; Increment time
  INC SECONDS
  LDA SECONDS
  CMP #$3C             ; 60
  BNE .main_loop
  LDA #$00
  STA SECONDS

  INC MINUTES
  LDA MINUTES
  CMP #$3C             ; 60
  BNE .main_loop
  LDA #$00
  STA MINUTES

  INC HOURS
  LDA HOURS
  CMP #$18             ; 24
  BNE .main_loop
  LDA #$00
  STA HOURS
  JMP .main_loop

.quit
  JSR clear_screen
  JSR con_flush
  LDA #$00
  JSR exit


; === Utility routines ===

; Print A as two decimal digits (00-99)
; A = value to print
print_two_digits
  STA TEMP
  LDA #$00             ; tens counter
  ; Divide by 10
.tens_loop
  LDX TEMP
  CPX #$0A
  BCC .tens_done
  LDX TEMP
  DEX
  DEX
  DEX
  DEX
  DEX
  DEX
  DEX
  DEX
  DEX
  DEX
  STX TEMP
  CLC
  ADC #$01
  JMP .tens_loop
.tens_done
  ; A = tens digit, TEMP = ones digit
  CLC
  ADC #'0'
  JSR write_b
  LDA TEMP
  CLC
  ADC #'0'
  JSR write_b
  RTS

; Clear screen
clear_screen
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'2'
  JSR write_b
  LDA #'J'
  JSR write_b
  ; Fall through to cursor_home

; Move cursor to row 1, col 1
cursor_home
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'H'
  JSR write_b
  RTS


; === Data ===

msg .asciiz "  Press q to quit\r\n"

; Entry point address
  .word main
