; test16.asm - Test program for new conventional syntax
; This file grows as we implement each addressing mode in asm16
;
; New syntax examples:
;   LDA #$42      ; immediate
;   LDA $12       ; zero page (value < $100)
;   LDA $1234     ; absolute
;   LDA $12,X     ; zero page indexed X
;   LDA $1234,X   ; absolute indexed X
;   LDA ($12),Y   ; indirect indexed Y
;   LDA ($12,X)   ; indirect indexed X
;   ASL A         ; accumulator

* = $2000

; === Test implied mode instructions ===
start
  NOP
  CLC
  SEC
  TAX
  TXA
  TAY
  TYA
  INX
  INY
  DEX
  DEY
  PHA
  PLA
  RTS

; === Test immediate mode ===
  LDA #$42
  LDX #$55
  LDY #$AA
  ADC #$01
  SBC #$02
  AND #$0F
  ORA #$F0
  EOR #$FF
  CMP #$00
  CPX #$10
  CPY #$20

; === Test zero page mode ===
  LDA $10
  LDX $20
  LDY $30
  STA $40
  STX $50
  STY $60
  INC $70
  DEC $80
  BIT $90

; === Test absolute mode ===
  LDA $1234
  LDX $2345
  LDY $3456
  STA $4567
  STX $5678
  STY $6789
  INC $789A
  DEC $89AB
  BIT $9ABC
  JMP $ABCD
  JSR $BCDE

; === Test indexed modes ===
  ; Zero page indexed X
  LDA $10,X
  STA $20,X
  LDY $30,X
  STY $40,X

  ; Zero page indexed Y
  LDX $50,Y
  STX $60,Y

  ; Absolute indexed X
  LDA $1234,X
  STA $2345,X
  LDY $3456,X
  INC $4567,X
  DEC $5678,X

  ; Absolute indexed Y
  LDA $6789,Y
  STA $789A,Y
  LDX $89AB,Y

; === Test indirect modes ===
  ; Indirect indexed Y - ($zp),Y
  LDA ($10),Y
  STA ($20),Y
  ADC ($30),Y
  SBC ($40),Y
  AND ($50),Y
  ORA ($60),Y
  EOR ($70),Y
  CMP ($80),Y

  ; Indirect indexed X - ($zp,X)
  LDA ($12,X)
  STA ($34,X)
  ADC ($56,X)
  SBC ($78,X)

; === Test accumulator mode ===
  ASL A
  LSR A
  ROL A
  ROR A

; === Test branch instructions ===
  BCC branch_target
  BCS branch_target
  BEQ branch_target
  BNE branch_target
  BMI branch_target
  BPL branch_target
  BVC branch_target
  BVS branch_target

branch_target
  NOP

; === Test label starting with 'A' (must not be mistaken for accumulator mode) ===
ABSOLUTE
  JMP ABSOLUTE         ; Should use absolute mode, not accumulator!
  LDA #$AA

; Padding to make output visible
  DATA $00 $00
