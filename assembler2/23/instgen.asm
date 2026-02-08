; Instruction table generator for new conventional syntax
; Written in new syntax (assembled by asm18)
;
; New table format: each instruction has mode:opcode pairs
;   [mnemonic string] $00 [mode1 opcode1] [mode2 opcode2] ... MODE_END
;
; Mode encoding:
;   MODE_NONE  = $00  ; Implied (no operand)
;   MODE_IMM   = $01  ; Immediate
;   MODE_ZP    = $02  ; Zero page
;   MODE_ZPX   = $03  ; Zero page, X
;   MODE_ZPY   = $04  ; Zero page, Y
;   MODE_ABS   = $05  ; Absolute
;   MODE_ABSX  = $06  ; Absolute, X
;   MODE_ABSY  = $07  ; Absolute, Y
;   MODE_INDX  = $08  ; Indirect, X - ($zp,X)
;   MODE_INDY  = $09  ; Indirect, Y - ($zp),Y
;   MODE_REL   = $0A  ; Relative (branches)
;   MODE_IND   = $0B  ; Indirect - JMP ($xxxx)
;   MODE_MACRO = $FE  ; Sentinel marker to indicate macro
;   MODE_END   = $FF  ; Terminator (end of mode list)

; Addresses
TOKEN       = $1E00     ; Buffer for the current token being read
IHASHTAB    = $1F00     ; Instruction hash table
FILE_STACK  = $F000     ; File stack (needed by advance_heap check)
*           = $2000     ; Code generates here


  .zeropage

TEMP:      .byte 0       ; 1 byte temporary value
HEX16:     .byte 0       ; 2 bytes
P16:       .word 0       ; 2 byte pointer
P2_16:     .word 0       ; 2 byte pointer
FS_P16:    .word 0       ; File stack pointer - needed by advance_heap check

  .code


; Include files
  .include environment.asm
  .include macros.asm
  .include common.asm


; Instruction table with mode:opcode pairs
; Format: "MNEMONIC" $00 [mode opcode]... MODE_END
MNTAB:
  ; Load/Store instructions
  .asciiz "LDA"
  .byte MODE_IMM, $A9, MODE_ZP, $A5, MODE_ZPX, $B5, MODE_ABS, $AD
  .byte MODE_ABSX, $BD, MODE_ABSY, $B9, MODE_INDX, $A1, MODE_INDY, $B1
  .byte MODE_END
  .asciiz "LDX"
  .byte MODE_IMM, $A2, MODE_ZP, $A6, MODE_ZPY, $B6
  .byte MODE_ABS, $AE, MODE_ABSY, $BE
  .byte MODE_END
  .asciiz "LDY"
  .byte MODE_IMM, $A0, MODE_ZP, $A4, MODE_ZPX, $B4
  .byte MODE_ABS, $AC, MODE_ABSX, $BC
  .byte MODE_END
  .asciiz "STA"
  .byte MODE_ZP, $85, MODE_ZPX, $95, MODE_ABS, $8D, MODE_ABSX, $9D
  .byte MODE_ABSY, $99, MODE_INDX, $81, MODE_INDY, $91
  .byte MODE_END
  .asciiz "STX"
  .byte MODE_ZP, $86, MODE_ZPY, $96, MODE_ABS, $8E, MODE_END
  .asciiz "STY"
  .byte MODE_ZP, $84, MODE_ZPX, $94, MODE_ABS, $8C, MODE_END

  ; Arithmetic instructions
  .asciiz "ADC"
  .byte MODE_IMM, $69, MODE_ZP, $65, MODE_ZPX, $75, MODE_ABS, $6D
  .byte MODE_ABSX, $7D, MODE_ABSY, $79, MODE_INDX, $61, MODE_INDY, $71
  .byte MODE_END
  .asciiz "SBC"
  .byte MODE_IMM, $E9, MODE_ZP, $E5, MODE_ZPX, $F5, MODE_ABS, $ED
  .byte MODE_ABSX, $FD, MODE_ABSY, $F9, MODE_INDX, $E1, MODE_INDY, $F1
  .byte MODE_END

  ; Logical instructions
  .asciiz "AND"
  .byte MODE_IMM, $29, MODE_ZP, $25, MODE_ZPX, $35, MODE_ABS, $2D
  .byte MODE_ABSX, $3D, MODE_ABSY, $39, MODE_INDX, $21, MODE_INDY, $31
  .byte MODE_END
  .asciiz "ORA"
  .byte MODE_IMM, $09, MODE_ZP, $05, MODE_ZPX, $15, MODE_ABS, $0D
  .byte MODE_ABSX, $1D, MODE_ABSY, $19, MODE_INDX, $01, MODE_INDY, $11
  .byte MODE_END
  .asciiz "EOR"
  .byte MODE_IMM, $49, MODE_ZP, $45, MODE_ZPX, $55, MODE_ABS, $4D
  .byte MODE_ABSX, $5D, MODE_ABSY, $59, MODE_INDX, $41, MODE_INDY, $51
  .byte MODE_END

  ; Compare instructions
  .asciiz "CMP"
  .byte MODE_IMM, $C9, MODE_ZP, $C5, MODE_ZPX, $D5, MODE_ABS, $CD
  .byte MODE_ABSX, $DD, MODE_ABSY, $D9, MODE_INDX, $C1, MODE_INDY, $D1
  .byte MODE_END
  .asciiz "CPX"
  .byte MODE_IMM, $E0, MODE_ZP, $E4, MODE_ABS, $EC, MODE_END
  .asciiz "CPY"
  .byte MODE_IMM, $C0, MODE_ZP, $C4, MODE_ABS, $CC, MODE_END

  ; Bit test
  .asciiz "BIT"
  .byte MODE_ZP, $24, MODE_ABS, $2C, MODE_END

  ; Increment/Decrement
  .asciiz "INC"
  .byte MODE_ZP, $E6, MODE_ZPX, $F6, MODE_ABS, $EE, MODE_ABSX, $FE, MODE_END
  .asciiz "DEC"
  .byte MODE_ZP, $C6, MODE_ZPX, $D6, MODE_ABS, $CE, MODE_ABSX, $DE, MODE_END
  .asciiz "INX"
  .byte MODE_NONE, $E8, MODE_END
  .asciiz "INY"
  .byte MODE_NONE, $C8, MODE_END
  .asciiz "DEX"
  .byte MODE_NONE, $CA, MODE_END
  .asciiz "DEY"
  .byte MODE_NONE, $88, MODE_END

  ; Shift/Rotate
  .asciiz "ASL"
  .byte MODE_NONE, $0A, MODE_ZP, $06, MODE_ZPX, $16, MODE_ABS, $0E
  .byte MODE_ABSX, $1E
  .byte MODE_END
  .asciiz "LSR"
  .byte MODE_NONE, $4A, MODE_ZP, $46, MODE_ZPX, $56, MODE_ABS, $4E
  .byte MODE_ABSX, $5E
  .byte MODE_END
  .asciiz "ROL"
  .byte MODE_NONE, $2A, MODE_ZP, $26, MODE_ZPX, $36, MODE_ABS, $2E
  .byte MODE_ABSX, $3E
  .byte MODE_END
  .asciiz "ROR"
  .byte MODE_NONE, $6A, MODE_ZP, $66, MODE_ZPX, $76, MODE_ABS, $6E
  .byte MODE_ABSX, $7E
  .byte MODE_END

  ; Branch instructions
  .asciiz "BCC"
  .byte MODE_REL, $90, MODE_END
  .asciiz "BCS"
  .byte MODE_REL, $B0, MODE_END
  .asciiz "BEQ"
  .byte MODE_REL, $F0, MODE_END
  .asciiz "BMI"
  .byte MODE_REL, $30, MODE_END
  .asciiz "BNE"
  .byte MODE_REL, $D0, MODE_END
  .asciiz "BPL"
  .byte MODE_REL, $10, MODE_END
  .asciiz "BVC"
  .byte MODE_REL, $50, MODE_END
  .asciiz "BVS"
  .byte MODE_REL, $70, MODE_END

  ; Jump instructions
  .asciiz "JMP"
  .byte MODE_ABS, $4C, MODE_IND, $6C, MODE_END
  .asciiz "JSR"
  .byte MODE_ABS, $20, MODE_END

  ; Stack instructions
  .asciiz "PHA"
  .byte MODE_NONE, $48, MODE_END
  .asciiz "PHP"
  .byte MODE_NONE, $08, MODE_END
  .asciiz "PLA"
  .byte MODE_NONE, $68, MODE_END
  .asciiz "PLP"
  .byte MODE_NONE, $28, MODE_END

  ; Transfer instructions
  .asciiz "TAX"
  .byte MODE_NONE, $AA, MODE_END
  .asciiz "TAY"
  .byte MODE_NONE, $A8, MODE_END
  .asciiz "TSX"
  .byte MODE_NONE, $BA, MODE_END
  .asciiz "TXA"
  .byte MODE_NONE, $8A, MODE_END
  .asciiz "TXS"
  .byte MODE_NONE, $9A, MODE_END
  .asciiz "TYA"
  .byte MODE_NONE, $98, MODE_END

  ; Flag instructions
  .asciiz "CLC"
  .byte MODE_NONE, $18, MODE_END
  .asciiz "CLD"
  .byte MODE_NONE, $D8, MODE_END
  .asciiz "CLI"
  .byte MODE_NONE, $58, MODE_END
  .asciiz "CLV"
  .byte MODE_NONE, $B8, MODE_END
  .asciiz "SEC"
  .byte MODE_NONE, $38, MODE_END
  .asciiz "SED"
  .byte MODE_NONE, $F8, MODE_END
  .asciiz "SEI"
  .byte MODE_NONE, $78, MODE_END

  ; Other
  .asciiz "BRK"
  .byte MODE_NONE, $00, MODE_END
  .asciiz "NOP"
  .byte MODE_NONE, $EA, MODE_END
  .asciiz "RTI"
  .byte MODE_NONE, $40, MODE_END
  .asciiz "RTS"
  .byte MODE_NONE, $60, MODE_END

  ; End of table
  .byte 0


; Populate instruction hash table from MNTAB
;
; MNTAB format (each entry):
;   "MNEMONIC" $00 [mode1 opcode1] [mode2 opcode2] ... MODE_END
;   - Null-terminated mnemonic string
;   - Pairs of (addressing_mode, opcode) bytes
;   - MODE_END terminator marks end of mode list
;   - $00 as first byte marks end of entire table
;
; Hash table entry format (on heap after hash_add):
;   [next_ptr_lo] [next_ptr_hi] [mnemonic $00] [mode opcode]... MODE_END
;   - hash_add stores next_ptr and mnemonic
;   - This routine appends the mode:opcode pairs and MODE_END terminator
;
; Register usage:
;   P2_16 = pointer to current entry in MNTAB (source)
;   MEMP16 = heap pointer (destination), managed by hash_add/advance_heap
;   Y = offset into current MNTAB entry
;
populate_instruction_hash_table:
  SET16 MNTAB P2_16           ; P2_16 points to start of instruction table

.entry_loop:
  ; Check for end of table ($00 as first byte of entry)
  LDY #$00
  LDA (P2_16),Y
  BEQ .done

  ; --- Phase 1: Copy mnemonic string to TOKEN buffer ---
  ; hash_add expects the key (mnemonic) in TOKEN
.token_loop:
  STA TOKEN,Y                 ; Copy byte to TOKEN
  BEQ .token_loop_done        ; Exit when null terminator copied
  INY
  LDA (P2_16),Y
  JMP .token_loop
.token_loop_done:
  ; Y now points at null terminator in source
  ; Mode data starts at Y+1

  ; Advance P2_16 to point to the mode data - P2_16 + Y + 1 -> P2_16
  TYA
  SEC                         ; Add 1
  ADCA16 P2_16 P2_16

  ; --- Phase 2: Add mnemonic to hash table ---
  ; hash_add:
  ;   - Calculates hash from TOKEN
  ;   - Allocates heap entry: [next_ptr $0000] [mnemonic $00]
  ;   - Returns with MEMP16 pointing to where value data should go
  JSR hash_add

  ; --- Phase 3: Copy mode:opcode pairs to heap ---
  ; Problem: both (P2_16),Y and (MEMP16),Y need Y for indirect indexed mode
  ; Solution: solved above by advancing P2_16 such that its required Y offset matches that required by the heap (i.e. starting at 0)
  LDY #$00                    ; Set initial source offset to mode data and to heap

.copy_modes:
  LDA (P2_16),Y               ; Load mode byte from source
  CMP #MODE_END
  BEQ .copy_done
  STA (MEMP16),Y
  INY
  LDA (P2_16),Y               ; Load opcode byte from source
  STA (MEMP16),Y
  INY
  JMP .copy_modes

.copy_done:
  ; Store MODE_END terminator
  APPEND_HEAPI MODE_END

  ; Advance P2_16 to next entry (add Y = total bytes consumed from this entry)
  TYA
  CLC
  ADCA16 P2_16 P2_16          ; P2_16 + Y -> P2_16

  ; Advance the heap
  JSR advance_heap

  JMP .entry_loop

.done:
  RTS


display_hex_char:
  CMP #$0A
  BCS .low
  ; Carry already clear
  ADC #'0'
  JMP write_b          ; Tail call
.low:
  ; C already set
  SBC #$0A ; Subtract 10
  CLC
  ADC #'A'
  JMP write_b ; Tail call


display_hex:
  PHA
  LSR
  LSR
  LSR
  LSR
  JSR display_hex_char
  PLA
  AND #$0F
  JMP display_hex_char ; Tail call


display_byte:
  PHA
  LDA #'$'
  JSR write_b
  PLA
  JMP display_hex


display_newline:
  LDA #'\n'
  JMP write_b


display_data_prefix:
  LDA #' '
  JSR write_b
  JSR write_b
  SET16 msg_data P16
  JMP display_text


; On entry P16 points to the text
; On exit Y points to the terminating 0
display_text:
  LDY #$00
.loop:
  LDA (P16),Y
  BEQ .done
  JSR write_b
  INY
  JMP .loop
.done:
  RTS


display_table:
  LDA #$00
  STA HASH
.loop:
  ; Display line start
  JSR display_data_prefix
  ; Display line
  LDA #$00
  STA TEMP
.lineloop:
  LDA #' '
  JSR write_b
  JSR hash_entry_empty
  BNE .not_empty
  ; empty
  LDA #'$'
  JSR write_b
  LDA #$00
  JSR display_hex
  LDA #$00
  JSR display_hex
  JMP .next
.not_empty:
  ; Display instruction label prefix
  SET16 msg_instprefix P16
  JSR display_text
  ; Display hash entry
  JSR load_hash_entry
  CLC
  ADCI16 TABP16 $02 P16
  JSR display_text
.next:
  LDA HASH
  CLC
  ADC #$02
  STA HASH
  LDA TEMP
  CLC
  ADC #$01
  STA TEMP
  CMP #$08
  BEQ .next1
  JMP .lineloop
.next1:
  JSR display_newline
  LDA HASH
  BEQ .done
  JMP .loop
.done:
  RTS


write_label_and_modes:
  ; Display the mnemonic string
  LDA #' '
  JSR write_b
  LDA #'"'
  JSR write_b
  ; Set P16 to point to mnemonic (TABP16 + 2)
  CLC
  ADCI16 TABP16 $02 P16
  ; Display mnemonic text
  JSR display_text
  ; Y now points to null terminator in mnemonic
  LDA #'"'
  JSR write_b
  LDA #' '
  JSR write_b
  LDA #$00
  JSR display_byte
  ; Now display mode:opcode pairs
  ; Y still valid from display_text, pointing at null
  INY                  ; Skip past null terminator to first mode byte
.mode_loop:
  LDA (P16),Y
  CMP #MODE_END
  BEQ .mode_done
  PHA                  ; Save mode byte
  LDA #' '
  JSR write_b
  PLA                  ; Restore mode byte
  JSR display_byte
  INY
  LDA #' '
  JSR write_b
  LDA (P16),Y           ; Opcode byte
  JSR display_byte
  INY
  JMP .mode_loop
.mode_done:
  LDA #' '
  JSR write_b
  LDA #MODE_END
  JSR display_byte
  JSR display_newline
  RTS


display_data:
  LDA #$00
  STA HASH
.loop:
  JSR hash_entry_empty
  BNE .not_empty
  JMP .next
.not_empty:
  ; Load pointer to hash entry
  JSR load_hash_entry
.entry_loop:
  ; Display instruction label prefix
  SET16 msg_instprefix P16
  JSR display_text
  CLC
  ADCI16 TABP16 $02 P16
  JSR display_text
  LDA #':'
  JSR write_b
  JSR display_newline
  JSR display_data_prefix
  LDA #' '
  JSR write_b
  ; Display next pointer
  LDY #$00
  LDA (TABP16),Y
  BNE .not_zero
  INY
  LDA (TABP16),Y
  BNE .not_zero
  ; Zero - no collision chain
  LDA #'$'
  JSR write_b
  LDA #'0'
  JSR write_b
  JSR write_b
  JSR write_b
  JSR write_b
  JSR write_label_and_modes
  JMP .next
.not_zero:
  ; Has collision chain - display pointer to next entry
  SET16 msg_instprefix P16
  JSR display_text
  CLC
  LDY #$00
  LDA (TABP16),Y
  ADC #$02
  STA P16
  INY
  LDA (TABP16),Y
  ADC #$00
  STA P16+$01
  JSR display_text
  JSR write_label_and_modes
  LDY #$00
  LDA (TABP16),Y
  STA P16
  INY
  LDA (TABP16),Y
  STA P16+$01
  CP16 P16 TABP16
  JMP .entry_loop
.next:
  LDA HASH
  CLC
  ADC #$02
  STA HASH
  BEQ .done
  JMP .loop
.done:
  RTS


; Entry point
start:
; Initialization
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE    ; Clear flag before using hash table
  JSR init_heap
  SET16 FILE_STACK FS_P16  ; Initialize so heap overflow check works
  JSR select_instruction_hash_table
  JSR init_hash_table
  JSR populate_instruction_hash_table

; Show the instructions hash table
  SET16 msg_hash_table_comment P16
  JSR display_text
  JSR display_newline
  SET16 msg_IHASHTAB P16
  JSR display_text
  LDA #':'
  JSR write_b
  JSR display_newline
  JSR display_table
  JSR display_newline

; Show the instructions heap data
  SET16 msg_heap_comment P16
  JSR display_text
  JSR display_newline
  JSR display_data

  BRK
  .byte 0                ; Success


msg_data:
  .asciiz ".data"

msg_instprefix:
  .asciiz "."

msg_IHASHTAB:
  .asciiz "IHASHTAB"

msg_hash_table_comment:
  .asciiz "; Instructions hash table (pointers)"

msg_heap_comment:
  .asciiz "; Instructions heap data"

; Error handler needed by advance_heap's overflow check
err_out_of_memory:
  BRK
  .asciiz 35, "Out of memory"


HEAP:                  ; Heap goes after the program code


  .word start ; Emulation environment jumps to address in last 2 bytes
