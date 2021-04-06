PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

E  = %10000000
RW = %01000000
RS = %00100000

  .org $8000

reset:
  ldx #$ff
  txs

  lda #%11111111
  sta DDRB

  lda #%11100000
  sta DDRA

  lda #%00111000 ; Set 8-bit mode; 2-line display; 5x8 font
  sta PORTB

  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #E         ; Set E bit to send instruction
  sta PORTA

  lda #0         ; Clear RS/RW/E bits
  sta PORTA


  lda #%00001110 ; Display on; cursor on; blink off
  sta PORTB

  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #E         ; Set E bit to send instruction
  sta PORTA

  lda #0         ; Clear RS/RW/E bits
  sta PORTA


  lda #%00000110 ; Increment and shift cursor; don't shift display
  sta PORTB

  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #E         ; Set E bit to send instruction
  sta PORTA

  lda #0         ; Clear RS/RW/E bits
  sta PORTA


  lda #RS        ; Set RS bit; clear RW/E bits
  sta PORTA

  lda #"H"
  jsr display_character

  lda #"e"
  jsr display_character

  lda #"l"
  jsr display_character

  lda #"l"
  jsr display_character
  
  lda #"o"
  jsr display_character

  lda #","
  jsr display_character

  lda #" "
  jsr display_character

  lda #"r"
  jsr display_character

  lda #"a"
  jsr display_character

  lda #"m"
  jsr display_character

  lda #"!"
  jsr display_character

loop:
  jmp loop

display_character:
  sta PORTB
  lda #(RS | E)  ; Set E bit to send instruction
  sta PORTA
  lda #RS        ; Set RS bit; clear RW/E bits
  sta PORTA
  rts

  .org $fffc
  .word reset
  .word $0000
