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


; CP16 src dst - Copy 16-bit value from src to dst
; Clobbers A
  .macro CP16 src dst
  LDA src
  STA dst
  LDA src+$01
  STA dst+$01
  .endmacro
