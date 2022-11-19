read_b   = $f006
write_b  = $f009

TEMP     = $00 ; 1 byte
TEMP2    = $01 ; 1 byte
TAB      = $02 ; 2 bytes
PC       = $04 ; 2 bytes
TOKEN    = $06 ; multiple bytes

PC_START = $2000
LF       = $0A

  .org $2000

start:
  lda #<PC_START
  sta PC
  lda #>PC_START
  sta PC+1
  ldy #0 ; Y remains 0 (for indirect addressing)
  jsr assemble
  brk


assemble:
lnloop:
  jsr read_b
  bcc lnloop1
  rts ; at end of input
lnloop1:
  cmp #';'
  bne lnloop2
  jsr ignln ; comment: skip rest of line
  jmp lnloop
lnloop2:
  cmp #LF ; newline
  bne lnloop3
  jmp lnloop ; blank line
lnloop3:
  cmp #' '
  bne lnloop3a
  jmp maybemnemonic
lnloop3a:
  ; Label
  jsr readtoken
  sta TEMP
  jsr capturelabel
  lda TEMP
  cmp #LF
  bne lnloop3aa
  jmp lnloop
lnloop3aa:
  jsr ignln
  jmp lnloop
maybemnemonic:
  jsr skipspc
  cmp #';'
  bne lnloop3b
  jsr ignln
  jmp lnloop
lnloop3b:
  cmp #LF
  bne lnloop3c
  jmp lnloop
lnloop3c:
; Read and emit mnemonic
  jsr readtoken
  sta TEMP
  lda #0
  sta TOKEN,X
  jsr emitoc
  lda TEMP
tokloop:
  jsr skipspc
  cmp #';'
  bne tokloop1
  jsr ignln ; handle comment
  jmp lnloop
tokloop1:
  cmp #LF
  bne tokloop2
  jmp lnloop ; end of line
tokloop2:
  cmp #'"'
  bne tokloop3
  jsr emitqu
  jmp tokloop
tokloop3:
  cmp #'$'
  bne tokloop3b
  jsr emithex
  jmp tokloop
tokloop3b:
  ; label
  jsr emitlabel
  jmp tokloop


; read and emit quoted ASCII
emitqu:
  jsr read_b
  cmp #'"'
  bne emitqu1
  jsr read_b
  rts
emitqu1:
  cmp #'\\'
  bne emitqu2
  jsr read_b
emitqu2:
  jsr emit
  jmp emitqu


ignln:
  jsr read_b
  cmp #LF ; newline
  bne ignln
  rts


readtoken:
  ldx #0
readtokenloop:
  sta TOKEN,X
  inx
  jsr read_b
  cmp #' '
  beq readtokendone ; done
  cmp #LF
  beq readtokendone
  jmp readtokenloop
readtokendone:
  rts


emithex:
  jsr read_b
emithex2:
  jsr readhex
  sta TEMP2
  jsr read_b
  cmp #' '
  beq emithex3
  cmp #LF
  beq emithex3
  cmp #';'
  beq emithex3
  jsr readhex
  jsr emit ; write the low byte
  jsr read_b
emithex3:
  sta TEMP
  lda TEMP2
  jsr emit
  lda TEMP
  rts


readhex:
  jsr convhex
  asl
  asl
  asl
  asl
  sta TEMP
  jsr read_b
  jsr convhex
  ora TEMP
  rts


skipspc:
  cmp #' '
  bne skipspc2
  jsr read_b
  jmp skipspc
skipspc2:
  rts


convhex:
  cmp #'A'
  bcc convhex1 ; < 'A'
  sbc #'A'
  clc
  adc #10
  rts
convhex1:
  sec
  sbc #'0'
  rts


; Emit the opcode
emitoc:
  lda #<MNTAB
  sta TAB
  lda #>MNTAB
  sta TAB+1
  jsr findintab
  bcs emitocnotfound
  lda (TAB),Y
  jsr emit
emitocnotfound:
  rts


emitlabel:
  jsr readtoken
  sta TEMP
  lda #<LBTAB
  sta TAB
  lda #>LBTAB
  sta TAB+1
  jsr findintab
  bcc emitlabel2
  brk ; label not found
emitlabel2:
  lda (TAB),Y
  jsr emit
  jsr inctab
  lda (TAB),Y
  jsr emit
  lda TEMP
  rts


capturelabel:
  lda #<LBTAB
  sta TAB
  lda #>LBTAB
  sta TAB+1
  jsr findintab
  bcs clnotfound
  brk ; duplicate label
clnotfound:
clloop:
  lda TOKEN,Y
  sta (TAB),Y
  beq cldone
  iny
  jmp clloop
cldone:
  iny
  lda PC
  sta (TAB),Y
  iny
  lda PC+1
  sta (TAB),Y
  iny
  lda #0
  sta (TAB),Y
  ldy #0 ; restore
  rts


findintab:
findintab1: ; outer loop
  ldx #0 ; pointer into mnenomic
  lda (TAB),Y
  beq findintab6 ; not found
;invariant: pointed at first char
; first char of mnenomic in table loaded
findintab2: ; inner loop
  cmp TOKEN,X
  bne findintab3 ; no match
  cmp #0
  beq findintab5 ; match
  inx
  jsr inctab
  lda (TAB),Y
  jmp findintab2 ; inner loop
findintab3: ; no match
  lda (TAB),Y
  beq findintab4 ; done skipping
  jsr inctab
  jmp findintab3
findintab4: ; done skipping
  jsr inctab ; move past 0 terminator
  jsr inctab ; move past opcode
  jsr inctab ; move past dummy byte
  jmp findintab1 ; outer loop
findintab5: ; match
  jsr inctab ; move past 0 terminator
  clc
  rts
findintab6: ; not found
  sec
  rts


inctab:
  inc TAB
  bne inctabdone
  inc TAB + 1
inctabdone:
  rts


emit:
  jsr write_b
  inc PC
  bne emitdone
  inc PC+1
emitdone:
  rts


; Instruction table
MNTAB:
  .BYTE "ADC#",   0, $69, 0
  .BYTE "ASLA",   0, $0A, 0
  .BYTE "BCC",    0, $90, 0
  .BYTE "BEQ",    0, $F0, 0
  .BYTE "BNE",    0, $D0, 0
  .BYTE "BRK",    0, $00, 0
  .BYTE "CLC",    0, $18, 0
  .BYTE "CMPZ,X", 0, $D5, 0
  .BYTE "CMP#",   0, $C9, 0
  .BYTE "INX",    0, $E8, 0
  .BYTE "INY",    0, $C8, 0
  .BYTE "JMP",    0, $4C, 0
  .BYTE "JSR",    0, $20, 0
  .BYTE "LDAZ",   0, $A5, 0
  .BYTE "LDA#",   0, $A9, 0
  .BYTE "LDA,Y",  0, $B9, 0
  .BYTE "LDX#",   0, $A2, 0
  .BYTE "LDY#",   0, $A0, 0
  .BYTE "ORAZ",   0, $05, 0
  .BYTE "RTS",    0, $60, 0
  .BYTE "SBC#",   0, $E9, 0
  .BYTE "SEC",    0, $38, 0
  .BYTE "STAZ",   0, $85, 0
  .BYTE "STAZ,X", 0, $95, 0
  .BYTE 0


;Labels table
LBTAB:
  .BYTE 0

  .WORD start
