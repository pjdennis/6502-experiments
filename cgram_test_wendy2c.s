; cgram_test_wendy2c.s -- exercises HD44780 CGRAM custom characters.
;
; Writes two 5x8 bitmaps to CGRAM slots 0 and 1 (a heart and a right
; arrow), then displays a line that uses them next to ASCII text.
; Loop forever so the LCD frame stays drawn for inspection in the
; wendy2c web UI / live render.
;
; Loads at $4000 like the other "uploaded payload" demos -- launch via
; assembler2/emulator/demo_wendy2c.sh DEMO_PAYLOAD=cgram_test_wendy2c.s.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

  .org $4000
  jmp program_entry

  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  ; Set CGRAM address to 0 and stream 16 bytes (2 slots x 8 rows).
  ; The HD44780's address counter auto-increments after each data write.
  lda #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldx #0
cgram_loop:
  lda cgram_data,X
  jsr display_character
  inx
  cpx #16
  bne cgram_loop

  ; Park DDRAM address back at the start so the message we print next
  ; lands on line 0.
  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command

  ; "wendy<heart>2c<arrow>!<heart>"  -- the HD44780 mirrors codes
  ; $08..$0F to CGRAM slots 0..7, so we use $08 (heart) and $09
  ; (arrow) to avoid colliding with display_string's null terminator.
  lda #<line1
  ldx #>line1
  jsr display_string

  ; Line 2: "CGRAM:<h><a><h><a><h><h>".
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda #<line2
  ldx #>line2
  jsr display_string

forever:
  bra forever

line1: .byte "wendy", $08, "2c", $09, "!", $08, 0
line2: .byte "CGRAM:", $08, $09, $08, $09, $08, $08, 0


; --- CGRAM bitmaps ---
; Each character is 8 bytes; only the low 5 bits are used (MSB-of-the-
; 5-bit-field is the leftmost pixel). Eighth row is the cursor line and
; conventionally left blank.

cgram_data:
  ; Slot 0: heart
  ;  . X . X .
  ;  X X X X X
  ;  X X X X X
  ;  X X X X X
  ;  . X X X .
  ;  . . X . .
  ;  . . . . .
  ;  . . . . .
  .byte %00001010
  .byte %00011111
  .byte %00011111
  .byte %00011111
  .byte %00001110
  .byte %00000100
  .byte %00000000
  .byte %00000000

  ; Slot 1: right arrow
  ;  . . . . .
  ;  . . X . .
  ;  . . X X .
  ;  X X X X X
  ;  . . X X .
  ;  . . X . .
  ;  . . . . .
  ;  . . . . .
  .byte %00000000
  .byte %00000100
  .byte %00000110
  .byte %00011111
  .byte %00000110
  .byte %00000100
  .byte %00000000
  .byte %00000000
