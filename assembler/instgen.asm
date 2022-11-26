; Provided by environment:
;   read:    Returns next character in A
;            C set when at end
;            Automatically restarts input after reaching end
;
;   write_b: Writes A to output
read      = $F006
write_b   = $F009

IHASHTABL = $4200      ; Instruction hash table (low and high)
IHASHTABH = $4300      ; "
HEAP      = $4400      ; Data heap

TEMP      = $0000      ; 1 byte temporary value
TABPL     = $0001      ; 2 byte table pointer
TABPH     = $0002      ; "
HEX1      = $0003      ; 1 byte
HEX2      = $0004      ; 1 byte
MEMPL     = $0005      ; 2 byte heap pointer
MEMPH     = $0006      ; "
PL        = $0007      ; 2 byte pointer
PH        = $0008      ; "
P2L       = $0009      ; 2 byte pointer
P2H       = $000A      ; "
HASH      = $000B      ; 1 byte hash value
CHAR      = $000C      ; 1 byte character value
HTLPL     = $000D      ; 2 byte pointer to low byte hash table
HTLPH     = $000D      ; "
HTHPL     = $000F      ; 2 byte pointer to high byte hash table
HTHPH     = $0010      ; "
TOKEN     = $0011      ; multiple bytes


*         = $2000       ; Set PC


; Contains each byte $00-$FF exactly once in random order
scramble_table
  DATA $01 $70 $DE $CD $50 $E6 $D2 $27 $7E $DB $15 $F0 $AF $F1 $A6 $CA
  DATA $31 $03 $C4 $B5 $B3 $A2 $9C $19 $AB $2C $DA $46 $E8 $0F $59 $68
  DATA $09 $69 $9B $FA $3C $E1 $41 $5E $8A $1B $93 $6D $6E $22 $71 $44
  DATA $D4 $FC $24 $E3 $08 $6C $2B $EA $85 $B1 $E4 $FF $37 $F3 $5D $18
  DATA $25 $4E $8F $0C $9E $F9 $3D $58 $76 $81 $0A $0B $D5 $53 $2A $91
  DATA $66 $B0 $95 $98 $AE $77 $60 $26 $80 $55 $ED $5A $14 $78 $FE $F8
  DATA $7B $2D $34 $8E $13 $87 $89 $4B $2E $2F $BF $3B $65 $29 $47 $49
  DATA $D1 $F6 $BD $3F $32 $CE $1F $20 $30 $36 $39 $0E $5F $04 $C0 $A8
  DATA $A5 $BA $43 $F5 $F2 $4C $06 $C3 $D9 $DF $B9 $1D $B7 $E7 $4A $4D
  DATA $73 $3A $C9 $C1 $DC $92 $A3 $7A $96 $BB $EC $61 $11 $E9 $6A $1A
  DATA $42 $75 $51 $A1 $97 $C8 $17 $1C $00 $5C $72 $94 $16 $7C $D3 $84
  DATA $5B $EF $9A $45 $FD $9F $F7 $EB $9D $8D $A4 $C2 $6F $C7 $D0 $64
  DATA $38 $83 $D7 $BC $B6 $74 $CC $07 $AC $7F $33 $99 $3E $EE $28 $8C
  DATA $A7 $57 $62 $1E $86 $4F $40 $D8 $B2 $CF $A9 $E2 $AA $CB $D6 $A0
  DATA $10 $E5 $02 $35 $21 $79 $B8 $C6 $23 $0D $E0 $56 $8B $F4 $52 $12
  DATA $7D $05 $67 $54 $63 $90 $B4 $DD $AD $C5 $6B $82 $FB $BE $48 $88


; Instruction table
MNTAB
;      Mnemonic           Opcode
  DATA "ADC#"     $00 $00 $69
  DATA "ADCZ"     $00 $00 $65
  DATA "AND#"     $00 $00 $29
  DATA "ASLA"     $00 $00 $0A
  DATA "BCC"      $00 $00 $90
  DATA "BCS"      $00 $00 $B0
  DATA "BEQ"      $00 $00 $F0
  DATA "BITZ"     $00 $00 $24
  DATA "BMI"      $00 $00 $30
  DATA "BNE"      $00 $00 $D0
  DATA "BPL"      $00 $00 $10
  DATA "BRK"      $00 $00 $00
  DATA "CLC"      $00 $00 $18
  DATA "CMP#"     $00 $00 $C9
  DATA "CMP,Y"    $00 $00 $D9
  DATA "EORZ"     $00 $00 $45
  DATA "INCZ"     $00 $00 $E6
  DATA "INX"      $00 $00 $E8
  DATA "INY"      $00 $00 $C8
  DATA "JMP"      $00 $00 $4C
  DATA "JSR"      $00 $00 $20
  DATA "LDA#"     $00 $00 $A9
  DATA "LDAZ(),Y" $00 $00 $B1
  DATA "LDA,X"    $00 $00 $BD
  DATA "LDA,Y"    $00 $00 $B9
  DATA "LDAZ"     $00 $00 $A5
  DATA "LDAZ,X"   $00 $00 $B5
  DATA "LDX#"     $00 $00 $A2
  DATA "LDY#"     $00 $00 $A0
  DATA "LSRA"     $00 $00 $4A
  DATA "ORAZ"     $00 $00 $05
  DATA "PHA"      $00 $00 $48
  DATA "PLA"      $00 $00 $68
  DATA "RTS"      $00 $00 $60
  DATA "SBC#"     $00 $00 $E9
  DATA "SBCZ"     $00 $00 $E5
  DATA "SEC"      $00 $00 $38
  DATA "STA"      $00 $00 $8D
  DATA "STAZ(),Y" $00 $00 $91
  DATA "STA,X"    $00 $00 $9D
  DATA "STA,Y"    $00 $00 $99
  DATA "STAZ"     $00 $00 $85
  DATA "STAZ,X"   $00 $00 $95
  DATA "TAY"      $00 $00 $A8
  DATA "TYA"      $00 $00 $98
  DATA "DATA"     $00 $01 $00 ; Directive
  DATA $00


init_heap
  LDA# <HEAP
  STAZ <MEMPL
  LDA# >HEAP
  STAZ <MEMPH
  RTS


advance_heap
  TYA
  LDY# $00
  CLC
  ADCZ <MEMPL
  STAZ <MEMPL
  TYA
  ADCZ <MEMPH
  STAZ <MEMPH
  RTS


select_instruction_hash_table
  LDA# <IHASHTABL
  STAZ <HTLPL
  LDA# >IHASHTABL
  STAZ <HTLPH
  LDA# <IHASHTABH
  STAZ <HTHPL
  LDA# >IHASHTABH
  STAZ <HTHPH
  RTS


populate_instruction_hash_table
  LDA# <MNTAB
  STAZ <P2L
  LDA# >MNTAB
  STAZ <P2H
piht_entry_loop
  LDY# $00
  LDAZ(),Y <P2L
  BEQ ~piht_done
piht_token_loop
  STA,Y TOKEN
  BEQ ~piht_token_loop_done
  INY
  LDAZ(),Y <P2L
  JMP piht_token_loop
piht_token_loop_done
  INY
  LDAZ(),Y <P2L
  STAZ <HEX2
  INY
  LDAZ(),Y <P2L
  STAZ <HEX1
  INY
  ; Advance
  TYA
  CLC
  ADCZ <P2L
  STAZ <P2L
  LDA# $00
  ADCZ <P2H
  STAZ <P2H
  ; Store entry
  JSR hash_add
  JMP piht_entry_loop
piht_done
  RTS


init_hash_table
  LDY# $00
  LDA# $00
iht_loop
  STAZ(),Y <HTLPL
  STAZ(),Y <HTHPL
  INX
  BNE ~iht_loop
  RTS
  

calculate_hash
  LDA# $00
  STAZ <HASH
  LDX# $00
ch_loop
  LDAZ,X <TOKEN
  BEQ ~ch_done
  EORZ <HASH
  TAY
  LDA,Y scramble_table
  STAZ <HASH
  INX
  JMP ch_loop
ch_done
  RTS


; On exit Z = 1 if entry is empty
hash_entry_empty
  LDAZ <HASH
  TAY
  LDAZ(),Y <HTLPL
  BNE ~hee_done
  LDAZ(),Y <HTHPL
hee_done
  RTS


; Load from hash table to tab_l;tab_h
load_hash_entry
  LDAZ <HASH
  TAY
  LDAZ(),Y <HTLPL
  STAZ <TABPL
  LDAZ(),Y <HTHPL
  STAZ <TABPH
  RTS


; Store current memory pointer in hash table
store_hash_entry
  LDAZ <HASH
  TAY
  LDAZ <MEMPL
  STAZ(),Y <HTLPL
  LDAZ <MEMPH
  STAZ(),Y <HTHPL
  RTS


; Store current memory pointer in table
store_table_entry
  LDAZ <MEMPL
  STAZ(),Y <TABPL
  INY
  LDAZ <MEMPH
  STAZ(),Y <TABPL
  INY
  RTS


; On entry TABPL;TABPH point to head of list of entries
;          TOKEN contains the token to find
; On exit C clear if found; set if not found
;         TABPL;TABPHi,Y points to value if found
;         or to 'next' pointer if not found
find_token
ft_tokenloop
  ; Store the current pointer
  LDAZ <TABPL
  STAZ <PL
  LDAZ <TABPH
  STAZ <PH
  ; Advance past 'next' pointer
  CLC
  LDA# $02
  ADCZ <TABPL
  STAZ <TABPL
  LDA# $00
  ADCZ <TABPH
  STAZ <TABPH
  ; Check for matching token
  LDY# $FF
ft_charloop
  INY
  LDAZ(),Y <TABPL
  CMP,Y TOKEN
  BNE ~ft_notmatch
  CMP# $00
  BNE ~ft_charloop
  ; Match
  INY                  ; point tab,Y to value
  CLC
  RTS
ft_notmatch            ; Not a match - move to next
  ; Check if 'next' pointer is 0
  LDY# $00
  LDAZ(),Y <PL
  BNE ~ft_notmatch1 ; not zero
  INY
  LDAZ(),Y <PL
  BEQ ~ft_atend
  ; Not at end
  STAZ <TABPH
  LDA# $00
  STAZ <TABPL
  JMP ft_tokenloop
ft_notmatch1
  STAZ <TABPL
  INY
  LDAZ(),Y <PL
  STAZ <TABPH
  JMP ft_tokenloop
ft_atend
  ; point tabp,Y to the zero 'next' pointer
  LDAZ <PL
  STAZ <TABPL
  LDAZ <PH
  STAZ <TABPH
  LDY# $00
  SEC ; Carry set indicates not found
  RTS


; On entry HEX1 and HEX2 contain MSB and LSB of value
;          TOKEN contains name of token
; Stores null next pointer, token and value on heap
; and advances heap pointer 
store_token
  LDY# $00
  ; Store null pointer (pointer to next)
  LDA# $00
  STAZ(),Y <MEMPL
  INY
  STAZ(),Y <MEMPL
  INY
  JSR advance_heap
  ; Store token name
  LDY# $FF         ; Alternative: DEY
st_loop
  INY
  LDA,Y TOKEN
  STAZ(),Y <MEMPL
  BNE ~st_loop
  INY
  ; Store value
  LDAZ <HEX2
  STAZ(),Y <MEMPL
  INY
  LDAZ <HEX1
  STAZ(),Y <MEMPL
  INY
  JMP advance_heap ; Tail call


; On entry TOKEN contains token
;          HEX1 and HEX2 contain MSB and LSB of value
; On exit C = 0 if added or 1 if already exists
hash_add
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ ~ha_entry_empty
  JSR load_hash_entry
  JSR find_token
  BCS ~ha_new
  SEC
  RTS
ha_new
  JSR store_table_entry
  JMP ha_store
ha_entry_empty
  JSR store_hash_entry
ha_store
  JSR store_token
  CLC
  RTS


display_hex_char
  CMP# $0A
  BCS ~display_hex_char_low
  ; Carry alrady clear
  ADC# "0"
  JMP write_b          ; Tail call
display_hex_char_low
  ; C already set
  SBC# $0A ; Subtract 10
  CLC
  ADC# "A"
  JMP write_b ; Tail call


display_hex
  PHA
  LSRA
  LSRA
  LSRA
  LSRA
  JSR display_hex_char
  PLA
  AND# $0F
  JMP display_hex_char ; Tail call


display_byte
  PHA
  LDA# "$"
  JSR write_b
  PLA
  JMP display_hex


display_newline
  LDA# "\n"
  JMP write_b


display_data_prefix
  LDA# " "
  JSR write_b
  JSR write_b
  LDA# <msg_data
  STAZ <PL
  LDA# >msg_data
  STAZ <PH
  JMP display_text


; On entry PL;PH points to the text
; On exit Y points to the terminating 0
display_text
  LDY# $00
dtext_loop
  LDAZ(),Y <PL
  BEQ ~dtext_done
  JSR write_b
  INY
  JMP dtext_loop
dtext_done
  RTS


display_scramble_table
  LDA# $00
  STAZ <HASH
dst_loop
  JSR display_data_prefix
  LDA# $00
  STAZ <TEMP
dst_lineloop
  LDA# " "
  JSR write_b
  LDAZ <HASH
  TAY
  LDA,Y scramble_table
  JSR display_byte
  CLC
  LDAZ <HASH
  ADC# $01
  STAZ <HASH  
  LDAZ <TEMP
  CLC
  ADC# $01
  STAZ <TEMP
  CMP# $10
  BEQ ~dst_next1
  JMP dst_lineloop
dst_next1
  JSR display_newline
  LDAZ <HASH
  BEQ ~dst_done
  JMP dst_loop
dst_done
  RTS


display_table
  LDA# $00
  STAZ <HASH
dt_loop
  ; Display line start
  JSR display_data_prefix
  ; Display line
  LDA# $00
  STAZ <TEMP
dt_lineloop
  LDA# " "
  JSR write_b
  JSR hash_entry_empty
  BNE ~dt_not_empty
  ; empty
  LDA# $00
  JSR display_byte
  JMP dt_next
dt_not_empty
  ; Display byte selector < or >
  LDAZ <CHAR
  JSR write_b
  ; Display instruction label prefix
  LDA# <msg_instprefix
  STAZ <PL
  LDA# >msg_instprefix
  STAZ <PH
  JSR display_text
  ; Display hash entry
  LDAZ <HASH
  TAY
  ; Load pointer to hash entry
  LDAZ(),Y <HTLPL
  STAZ <TABPL
  LDAZ(),Y <HTHPL
  STAZ <TABPH
  CLC
  LDAZ <TABPL
  ADC# $02
  STAZ <PL
  LDAZ <TABPH
  ADC# $00
  STAZ <PH
  JSR display_text
dt_next
  LDAZ <HASH
  CLC
  ADC# $01
  STAZ <HASH
  LDAZ <TEMP
  CLC
  ADC# $01
  STAZ <TEMP
  CMP# $08
  BEQ ~dt_next1
  JMP dt_lineloop
dt_next1
  JSR display_newline
  LDAZ <HASH
  BEQ ~dt_done 
  JMP dt_loop
dt_done
  RTS


write_label
  LDA# " "
  JSR write_b
  LDA# "\""
  JSR write_b
  CLC
  LDAZ <TABPL
  ADC# $02
  STAZ <PL
  LDAZ <TABPH
  ADC# $00
  STAZ <PH
  JSR display_text
  LDA# "\""
  JSR write_b
  LDA# " "
  JSR write_b
  LDA# $00
  JSR display_byte
  LDA# " "
  JSR write_b
  INY
  LDAZ(),Y <PL
  JSR display_byte
  LDA# " "
  JSR write_b
  INY
  LDAZ(),Y <PL
  JSR display_byte
  JSR display_newline
  RTS 


display_data
  LDA# $00
  STAZ <HASH
dd_loop
  JSR hash_entry_empty
  BNE ~dd_not_empty
  JMP dd_next
dd_not_empty
  ; Load pointer to hash entry
  LDAZ <HASH
  TAY
  LDAZ(),Y <HTLPL
  STAZ <TABPL
  LDAZ(),Y <HTHPL
  STAZ <TABPH
dd_entry_loop
  ; Display instruction label prefix
  LDA# <msg_instprefix
  STAZ <PL
  LDA# >msg_instprefix
  STAZ <PH
  JSR display_text
  CLC
  LDAZ <TABPL
  ADC# $02
  STAZ <PL
  LDAZ <TABPH
  ADC# $00
  STAZ <PH
  JSR display_text
  JSR display_newline
  JSR display_data_prefix
  LDA# " "
  JSR write_b
  ; Display next pointer
  LDY# $00
  LDAZ(),Y <TABPL
  BNE ~dd_not_zero
  INY
  LDAZ(),Y <TABPL
  BNE ~dd_not_zero
  ; Zero
  LDA# "$"
  JSR write_b
  LDA# "0"
  JSR write_b
  JSR write_b
  JSR write_b
  JSR write_b
  JSR write_label
  JMP dd_next
dd_not_zero
  LDA# <msg_instprefix
  STAZ <PL
  LDA# >msg_instprefix
  STAZ <PH
  JSR display_text
  CLC
  LDY# $00
  LDAZ(),Y <TABPL
  ADC# $02
  STAZ <PL
  INY
  LDAZ(),Y <TABPL
  ADC# $00
  STAZ <PH
  JSR display_text
  JSR write_label
  LDY# $00
  LDAZ(),Y <TABPL
  STAZ <PL
  INY
  LDAZ(),Y <TABPL
  STAZ <PH
  LDAZ <PL
  STAZ <TABPL
  LDAZ <PH
  STAZ <TABPH
  JMP dd_entry_loop
dd_next
  LDAZ <HASH
  CLC
  ADC# $01
  STAZ <HASH
  BEQ ~dd_done
  JMP dd_loop
dd_done
  RTS


; Entry point
start
  JSR init_heap
  JSR select_instruction_hash_table
  JSR init_hash_table
  JSR populate_instruction_hash_table
 
  LDA# <msg_setpc
  STAZ <PL
  LDA# >msg_setpc
  STAZ <PH

  JSR display_text
  JSR display_newline
  JSR display_newline

  LDA# <msg_scramble_table
  STAZ <PL
  LDA# >msg_scramble_table
  STAZ <PH
  JSR display_text
  JSR display_newline
  JSR display_scramble_table

  JSR display_newline
 
  LDA# <msg_IHASHTABL
  STAZ <PL
  LDA# >msg_IHASHTABL
  STAZ <PH
  JSR display_text
  JSR display_newline
  LDA# "<"
  STAZ <CHAR
  JSR display_table

  JSR display_newline

  LDA# <msg_IHASHTABH
  STAZ <PL
  LDA# >msg_IHASHTABH
  STAZ <PH
  JSR display_text
  JSR display_newline
  LDA# ">"
  STAZ <CHAR
  JSR display_table

  JSR display_newline

  JSR display_data

  BRK $00              ; Success


msg_setpc
  DATA "* = $2000" $00

msg_scramble_table
  DATA "scramble_table" $00

msg_data
  DATA "DATA" $00

msg_instprefix
  DATA "i_" $00

msg_IHASHTABL
  DATA "IHASHTABL" $00

msg_IHASHTABH
  DATA "IHASHTABH" $00


  DATA start ; Emulation environment jumps to address in last 2 bytes
