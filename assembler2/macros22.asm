; Utility macros for 16-bit operations
;
; These macros assume consecutive zero-page locations for 16-bit values
; (low byte at ptr, high byte at ptr+$01)


; INC16 ptr - Increment 16-bit value at ptr/ptr+$01
; Preserves A, X, Y
  .macro INC16 ptr
  INC ptr
  BNE .skip
  INC ptr+$01
.skip
  .endmacro


; ADD16 val1 val2 - Add two 16 bit values val1 and val2, storing result in val2
; Clobbers A
; TODO add a third parameter to specify result location
  .macro ADD16 val1 val2
  LDA val1
  ADC val2
  STA val2
  LDA val1+$01
  ADC val2+$01
  STA val2+$01
  .endmacro


; ADDI16 addr1 val addr2 - Adds val to  variable at addr1, storing the result at addr2
; Clobbers A
  .macro ADDI16 addr1 val addr2
  LDA addr1
  ADC #<val
  STA addr2
  LDA addr1+$01
  ADC #>val
  STA addr2+$01
  .endmacro


; SUB16_2 val1 val2 - Subtracts the variable at addr2 from that at addr1, storing the result at addr2
; Clobbers A
  .macro SUB16_2 addr1 addr2
  LDA addr1
  SBC addr2
  STA addr2
  LDA addr1+$01
  SBC addr2+$01
  STA addr2+$01
  .endmacro


; ASL16 ptr - Shift 16 bit value left
; Clobbers A
  .macro ASL16 val
  ASL val
  ROL val+$01
  .endmacro


; LSR16 ptr - Shift 16 bit value right
; Clobbers A
  .macro LSR16 val
  LSR val+$01
  ROR val
  .endmacro


; CP16 src dst - Copy 16-bit value from src to dst
; Clobbers A
  .macro CP16 src dst
  LDA src
  STA dst
  LDA src+$01
  STA dst+$01
  .endmacro


; SET16 addr ptr - Load 16-bit immediate value into ptr/ptr+$01
; Clobbers A
  .macro SET16 value ptr
  LDA #<value
  STA ptr
  LDA #>value
  STA ptr+$01
  .endmacro


; STA_LH16 addr - Store A into the low and high bytes of addr
; Most useful for A = $00 or A = $FF
; Preserves A, X, Y
  .macro STA_LH16 addr
  STA addr
  STA addr+$01
  .endmacro


; PUSH16 addr - Push the value at addr to the stack
; Clobbers A
  .macro PUSH16 addr
  LDA addr
  PHA
  LDA addr+$01
  PHA
  .endmacro


; POP16 addr - Pops the value at addr from the stack
; Clobbers A
  .macro POP16 addr
  PLA
  STA addr+$01
  PLA
  STA addr
  .endmacro
