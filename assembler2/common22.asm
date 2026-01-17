; Addressing mode constants
MODE_NONE  = $00   ; Implied (no operand)
MODE_ACC   = $01   ; Accumulator
MODE_IMM   = $02   ; Immediate
MODE_ZP    = $03   ; Zero page
MODE_ZPX   = $04   ; Zero page, X
MODE_ZPY   = $05   ; Zero page, Y
MODE_ABS   = $06   ; Absolute
MODE_ABSX  = $07   ; Absolute, X
MODE_ABSY  = $08   ; Absolute, Y
MODE_INDX  = $09   ; Indirect, X - ($zp,X)
MODE_INDY  = $0A   ; Indirect, Y - ($zp),Y
MODE_REL   = $0B   ; Relative (branches)
MODE_IND   = $0C   ; Indirect - JMP ($xxxx)
MODE_MACRO = $FE   ; Sentinel marker to indicate macro 
MODE_END   = $FF   ; Terminates the list of modes

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


; CHECK_FOR_OUT_OF_MEMORY - Verify heap/stack don't collide
; Macro performs the check, to minimize function call overhead
; On entry: fs_ptr = file stack pointer to check against MEMP16
; Raises err_out_of_memory if fs_ptr - MEMP16 < 256
; On exit: A not preserved, X and Y preserved
  .macro CHECK_FOR_OUT_OF_MEMORY fs_ptr
  ; Quick check: if ptr_H - MEMP16_H > 1, we have >= 512 bytes free
  LDA fs_ptr+$01
  SEC
  SBC MEMP16+$01        ; A = high byte difference
  CMP #$02
  BCS .oom_ok           ; >= 2 means >= 512 bytes, definitely safe
  ; High bytes are close (differ by 0 or 1) - do precise check
  ; Check: ptr - MEMP16 >= 256 (high byte of difference must be non-zero)
  LDA fs_ptr
  SEC
  SBC MEMP16            ; Low byte of difference (result discarded, need borrow)
  LDA fs_ptr+$01
  SBC MEMP16+$01        ; A = high byte of (ptr - MEMP16)
  BNE .oom_ok           ; Non-zero means >= 256 bytes free
  JMP err_out_of_memory
.oom_ok
  .endmacro


init_heap
  .ifdef enable_debug
  LDA SMALL_HEAP_FLAG
  BEQ .normal_heap
  ; Small heap for testing: only ~256 bytes available
  SET16 FILE_STACK-$0100 MEMP16
  RTS
.normal_heap
  .endif
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
  ; Check for collision with file stack
  CHECK_FOR_OUT_OF_MEMORY FS_P16
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
  STA LABEL_TYPE       ; Clear local label flag for instruction lookup
  SET16 IHASHTAB HTP16
  RTS
