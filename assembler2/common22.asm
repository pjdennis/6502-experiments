; Addressing mode constants
MODE_NONE = $00   ; Implied (no operand)
MODE_ACC  = $01   ; Accumulator
MODE_IMM  = $02   ; Immediate
MODE_ZP   = $03   ; Zero page
MODE_ZPX  = $04   ; Zero page, X
MODE_ZPY  = $05   ; Zero page, Y
MODE_ABS  = $06   ; Absolute
MODE_ABSX = $07   ; Absolute, X
MODE_ABSY = $08   ; Absolute, Y
MODE_INDX = $09   ; Indirect, X - ($zp,X)
MODE_INDY = $0A   ; Indirect, Y - ($zp),Y
MODE_REL  = $0B   ; Relative (branches)
MODE_IND  = $0C   ; Indirect - JMP ($xxxx)

HT_KEY = TOKEN
HT_V16 = HEX16


  .zeropage

MEMP16          .data $0000 ; 2 byte heap pointer

  .code


  ; Append the value at ptr to the heap and increment Y
  ; Clobbers A
  .macro APPEND_HEAP ptr
  LDA ptr
  STA (MEMP16),Y
  INY
  .endmacro

  ; Append val to the heap and increment Y
  .macro APPEND_HEAPI val
  LDA #val
  STA (MEMP16),Y
  INY
  .endmacro


  .include hash_table22.asm


init_heap
  SET16 HEAP MEMP16
  RTS


; On entry Y contains the amount to advance
; On exit MEMP16 is incremented by Y
;         Y = 0
;         X is preserved
;         A is not preserved
advance_heap
  TYA
  LDY #$00
  CLC
  ADC MEMP16
  STA MEMP16
  TYA
  ADC MEMP16+$01
  STA MEMP16+$01
  RTS


; Store hash value at current heap location and advance heap
; On entry HT_V16 contains the value to store
;          MEMP16 points to where value should be stored
; On exit MEMP16 advanced past the value
;         Y = 0
;         X is preserved
;         A is not preserved
store_hash_value
  LDY #$00
  LDA HT_V16
  STA (MEMP16),Y
  INY
  LDA HT_V16+$01
  STA (MEMP16),Y
  INY
  JMP advance_heap     ; Tail call


select_instruction_hash_table
  LDA #$00
  STA IS_LOCAL_LABEL       ; Clear local label flag for instruction lookup
  SET16 IHASHTAB HTP16
  RTS
