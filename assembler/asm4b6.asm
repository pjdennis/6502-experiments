; Provided by environment:
;   read:    Returns next character in A
;            C set when at end
;            Automatically restarts input after reaching end
;
;   write_b: Writes A to output
read     = $F006
write_b  = $F009

hash_tab_l = $4000
hash_tab_h = $4100
heap       = $4200

TEMP     = $0000       ; 1 byte
TABPL    = $0001       ; 2 byte table pointer
TABPH    = $0002       ; "
PCL      = $0003       ; 2 byte program counter
PCH      = $0004       ; "
HEX1     = $0005       ; 1 byte
HEX2     = $0006       ; 1 byte
PASS     = $0007       ; 1 byte $00 = pass 1 $FF = pass 2
MEMPL    = $0008       ; 2 byte heap pointer
MEMPH    = $0009       ; "
PL       = $000A       ; 2 byte pointer
PH       = $000B       ; "
hash     = $000C       ; 1 byte hash value
TOKEN    = $000D       ; multiple bytes


*        = $2000       ; Set PC


; Contains each byte $00-$FF exactly once in random order
scramble_tab
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


; Environment should surface error codes and messages on BRK
err_labelnotfound
  BRK $01 "Label not found" $00

err_duplicatelabel
  BRK $02 "Duplicate label" $00

err_opcodenotfound
  BRK $03 "Opcode not found" $00

err_expectedhex
  BRK $04 "Expected hex value" $00

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
  LDA# <heap
  STAZ <MEMPL
  LDA# >heap
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


init_hash_tab
  LDX# $00
  LDA# $00
iht_loop
  STA,X hash_tab_l
  STA,X hash_tab_h
  INX
  BNE ~iht_loop
  

calculate_hash
  LDA# $00
  STAZ <hash
  LDX# $00
ch_loop
  LDAZ,X <TOKEN
  BEQ ~ch_done
  EORZ <hash
  TAY
  LDA,Y scramble_tab
  STAZ <hash
  INX
  JMP ch_loop
ch_done
  RTS


; On exit Z = 1 if entry is empty
hash_entry_empty
  LDAZ <hash
  TAY
  LDA,Y hash_tab_l
  BNE ~hee_done
  LDA,Y hash_tab_h
hee_done
  RTS


; Load from hash table to tab_l;tab_h
load_hash_entry
  LDAZ <hash
  TAY
  LDA,Y hash_tab_l
  STAZ <TABPL
  LDA,Y hash_tab_h
  STAZ <TABPH
  RTS


; Store current memory pointer in hash table
store_hash_entry
  LDAZ <hash
  TAY
  LDAZ <MEMPL
  STA,Y hash_tab_l
  LDAZ <MEMPH
  STA,Y hash_tab_h
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


; On entry token contains the token to find
; Raises error if not found
; On exit HEX1 and HEX2 contains MSB and LSB of value
find_in_hash
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ ~fih_notfound
fih_entry_exists
  JSR load_hash_entry
  JSR find_token
  BCS ~fih_notfound
  ; Found
  LDAZ(),Y <TABPL
  STAZ <HEX2
  INY
  LDAZ(),Y <TABPL
  STAZ <HEX1
  RTS
fih_notfound
  BRK $02 "Token not found" $00


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
hash_add
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ ~ha_entry_empty
  JSR load_hash_entry
  JSR find_token
  BCS ~ha_new
  BRK $01 "Token already exists" $00
ha_new
  JSR store_table_entry
  JMP store_token ; Tail call
ha_entry_empty
  JSR store_hash_entry
ha_store
  JMP store_token ; Tail call


; On entry A contains the byte to emit
; On exit A, X, Y are preserved
emit
  BITZ <PASS
  BPL ~emit_incpc      ; Skip writing during pass 1
  JSR write_b
emit_incpc
  INCZ <PCL
  BNE ~emit_done
  INCZ <PCH
emit_done
  RTS


skiprestofline
  CMP# "\n"
  BEQ ~srol_done
  JSR read
  JMP skiprestofline
srol_done
  RTS


skipspaces
  CMP# " "
  BNE ~ss_done
  JSR read
  JMP skipspaces
ss_done
  RTS


cmpendoftoken
  CMP# " "
  BEQ ~ceof_end
  CMP# "\n"
  BEQ ~ceof_end
  CMP# ";"
ceof_end
  RTS


; Checks for end of line and skips past if at end
; On entry A contains next character
; On exit C set if end of line, clear otherwise
;         A contains next character
checkforend
  CMP# ";"
  BEQ ~cfe_end
  CMP# "\n"
  BEQ ~cfe_end
  ; Not at end
  CLC
  RTS
cfe_end
  JSR skiprestofline
  SEC
  RTS


; On entry A contains first character of token
; Reads token into TOKEN (zero terminated)
; On exit A contains next character after token
;         Y is preserved
;         X is not preserved
readtoken
  LDX# $00
readtokenloop
  STAZ,X <TOKEN
  INX
  JSR read
  JSR cmpendoftoken
  BNE ~readtokenloop
  PHA                  ; Save next char
  LDA# $00
  STAZ,X <TOKEN
  PLA                  ; Restore next char
  RTS


; On entry Y contains offset into TAB
; On exit TABPL;TABPH += Y + 1
;         Y = 0
;         A is not preserved
advanceintab
  INY
  TYA
  LDY# $00
  CLC
  ADCZ <TABPL
  STAZ <TABPL
  TYA                  ; A <- 0
  ADCZ <TABPH
  STAZ <TABPH
  RTS


; On entry TOKEN contains token to find
;          TABPL;TABPH points to table
; On exit C clear if found; set if not found
;         TABPL;TABPH points to token value if found
;                   or to end of table if not found
;         Y = 0
;         X is preserved
;         A is not preserved
findintab
  LDY# $00
fit_tokenloop          ; Outer loop
  LDAZ(),Y <TABPL
  BNE ~fit_charloop
  ; not found
  SEC
  RTS
;invariant: pointed at first char
; first char of mnenomic in table loaded
fit_charloop           ; inner loop
  CMP,Y TOKEN
  BNE ~fit_skipcurrent ; Current symbol not a match
  CMP# $00
  BNE ~fit_nextchar
  ; found a match
  JSR advanceintab
  CLC
  RTS
fit_nextchar           ; Move to next char
  INY
  LDAZ(),Y <TABPL
  JMP fit_charloop     ; Inner loop
fit_skipcurrent        ; Skip current symbol in table
  LDAZ(),Y <TABPL
  BEQ ~fit_nextsymbol
  INY
  JMP fit_skipcurrent
fit_nextsymbol         ; Move to next symbol in table
  INY                  ; Move past 2 data bytes
  INY
  JSR advanceintab
  JMP fit_tokenloop    ; Outer loop


; On exit A contains the next character
readandfindexistinglabel
  JSR readtoken
  BITZ <PASS
  BMI ~rafel_pass2
  ; Pass 1
  RTS
rafel_pass2
  PHA                  ; Save next char
  JSR find_in_hash
  PLA                  ; Restore next char
  RTS


; On entry, A contains a hex character A-Z|0-9
; On exit A contains the value (0-15)
convhex
  CMP# "A"
  BCC ~ch_numeric      ; < 'A'
  SBC# "A"             ; Carry already set
  CLC
  ADC# $0A             ; ADC# 10
  RTS
ch_numeric
  SEC
  SBC# "0"
  RTS


; On entry A contains first hex character
; Reads second hex character; Uses TEMP
; On exit A contains 2 character value (0-255)
readhex
  JSR convhex
  ASLA
  ASLA
  ASLA
  ASLA
  STAZ <TEMP
  JSR read
  JSR convhex
  ORAZ <TEMP
  RTS


; On entry, next character read will be first hex character
; On exit C set if 2 bytes read clear if 1 byte read
;         A contains the next character
grabhex
  JSR read             ; Read the 1st hex character
  JSR readhex          ; Read 2nd hex character and convert
  STAZ <HEX1
  JSR read             ; Read 3rd hex char or terminator
  JSR cmpendoftoken
  BNE ~gh_second
  CLC                  ; No second byte so return C = 0
  RTS
gh_second
  JSR readhex          ; Read 4th hex char and convert
  STAZ <HEX2
  JSR read             ; Read next char
  SEC                  ; Second byte so return C = 1
  RTS


; Read 2 to 4 hex characters and emit 1 or 2 bytes
; When 2 bytes, emit LSB then MSB
; Uses HEX1, HEX2
; On exit A contains next character
emithex
  JSR grabhex          ; Returns C = 1 if 2 bytes read
  PHA                  ; Save next char
  BCC ~eh_one
  LDAZ <HEX2
  JSR emit
eh_one
  LDAZ <HEX1
  JSR emit
  PLA                  ; Restore next char
  RTS

; On entry A contains the next character
; On exit C set if value read; clear otherwise
readvalue
  JSR skipspaces
  CMP# "="
  BEQ ~rv_value
  CLC
  RTS
rv_value
  JSR read             ; Read the character after the "="
  JSR skipspaces
  CMP# "$"
  BEQ ~rv_hexvalue
  JMP err_expectedhex
rv_hexvalue
  JSR grabhex
  SEC
  RTS


; capturelabel
capturelabel
  JSR readtoken
  PHA                  ; Save next char
  LDAZ <TOKEN
  CMP# "*"
  BNE ~cl_normallabel
  ; Set PC
  PLA                  ; Restore next char
  JSR readvalue
  JSR skiprestofline
  ; No need to retain next char as caller
  ; goes straight to next line
  LDAZ <HEX2
  STAZ <PCL
  LDAZ <HEX1
  STAZ <PCH
  RTS
cl_normallabel
  BITZ <PASS
  BPL ~cl_pass1
  ; Pass 2 - don't capture
  PLA                  ; Restore next char
  JMP skiprestofline   ; Tail call
cl_pass1
  PLA                  ; Restore next char
  JSR readvalue
  PHA                  ; Save next char
  BCS ~cl_hextotable
  ; Store program counter
  LDAZ <PCL
  STAZ <HEX2
  LDAZ <PCH
  STAZ <HEX1
cl_hextotable
  JSR hash_add
  PLA                  ; Restore next char
  JSR skiprestofline
  ; No need to retain next char as caller
  ; goes straight to next line
  RTS


; Emit the opcode
; On exit A contains the next character
emitopcode
  JSR readtoken
  PHA                  ; Save next char
  LDA# <MNTAB
  STAZ <TABPL
  LDA# >MNTAB
  STAZ <TABPH
  JSR findintab
  BCC ~eo_found
  PLA                  ; Restore next char
  JMP err_opcodenotfound
eo_found
  LDAZ(),Y <TABPL
  BNE ~eo_done         ; Not opcode (DATA command)
  ; Opcode
  INY
  LDAZ(),Y <TABPL
  JSR emit
eo_done
  PLA                  ; Restore next char
  RTS


; Read and emit quoted ASCII
emitquoted
  JSR read
  CMP# "\""
  BNE ~eq_notdone
  JSR read             ; Done; read next char
  RTS
eq_notdone
  CMP# "\\"
  BNE ~eq_notescaped
  JSR read
  CMP# "n"
  BNE ~eq_notescaped
  LDA# "\n"            ; Escaped "n" is linefeed
eq_notescaped
  JSR emit
  JMP emitquoted


; On exit A contains the next character
emitlabel
  JSR readandfindexistinglabel
  PHA                  ; Save next char
  ; Emit low byte then high byte from table
  LDAZ <HEX2
  JSR emit
  LDAZ <HEX1
  JSR emit
  PLA                  ; Restore next char
  RTS


; On exit A contains the next character
emitlabellsb
  JSR readandfindexistinglabel
  PHA                  ; Save next char
  ; Emit low byte
  LDAZ <HEX2
  JSR emit
  PLA                  ; Restore next char
  RTS


; On exit A contains the next character
emitlabelmsb
  JSR readandfindexistinglabel
  PHA                  ; Save next char
  ; Emit high byte
  LDAZ <HEX1
  JSR emit
  PLA                  ; Restore next character
  RTS


emitlabelrel
  BITZ <PASS
  BMI ~elr_pass2
  ; Pass 1
  JSR readtoken
  JSR emit
  RTS
elr_pass2
  JSR readandfindexistinglabel
  PHA                  ; Save next char
  ; Calculate target - PC - 1
  CLC ; for the - 1
  LDAZ <HEX2
  SBCZ <PCL
  JSR emit
  PLA                  ; Restore next char
  RTS


; Main assembler
assemble
  LDA# $00
  STAZ <PCL
  STAZ <PCH
lnloop
  JSR read
  BCC ~lnloop1
  RTS                  ; At end of input
lnloop1
  JSR checkforend
  BCS ~lnloop
  CMP# " "
  BEQ ~lnloop2
  JSR capturelabel
  JMP lnloop
lnloop2
  JSR skipspaces
  JSR checkforend
  BCS ~lnloop
  ; Read mnemonic and emit opcode
  JSR emitopcode
tokloop
  JSR skipspaces
  JSR checkforend
  BCS ~lnloop          ; End of line
  CMP# "\""            ; Quoted string
  BNE ~tokloop1
  JSR emitquoted
  JMP tokloop
tokloop1
  CMP# "$"             ; 1 or 2 byte hex
  BNE ~tokloop2
  JSR emithex
  JMP tokloop
tokloop2
  CMP# "<"             ; LSB of variable
  BNE ~tokloop3
  JSR read
  JSR emitlabellsb
  JMP tokloop
tokloop3
  CMP# ">"             ; MSB of variable
  BNE ~tokloop4
  JSR read
  JSR emitlabelmsb
  JMP tokloop
tokloop4
  CMP# "~"             ; Relative address
  BNE ~tokloop5
  JSR read
  JSR emitlabelrel
  JMP tokloop
tokloop5
  JSR emitlabel        ; 2 byte variable
  JMP tokloop

; Entry point
start
  JSR init_heap
  JSR init_hash_tab
  LDA# $00
  STAZ <PASS           ; Bit 7 = 0 (pass 1)
  JSR assemble
  LDA# $FF
  STAZ <PASS           ; Bit 7 = 1 (pass 2)
  JSR assemble
  BRK $00              ; Success


  DATA start ; Emulation environment jumps to address in last 2 bytes
