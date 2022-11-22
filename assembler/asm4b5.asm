; Provided by environment:
;   read:    Returns next character in A
;            C set when at end
;            Automatically restarts input after reaching end
;
;   write_b: Writes A to output
read     = $F006
write_b  = $F009

TEMP     = $0000       ; 1 byte
NEXTCHAR = $0001       ; 1 byte
TABL     = $0002       ; 1 byte
TABH     = $0003       ; 1 byte
PCL      = $0004       ; 1 byte
PCH      = $0005       ; 1 byte
HEX1     = $0006       ; 1 byte
HEX2     = $0007       ; 1 byte
PASS     = $0008       ; 1 byte $00 = pass1 $FF = pass2
TOKEN    = $0009       ; multiple bytes

;LBTAB    = $3000

*        = $2000       ; Set PC


; Environment should surface error codes and messages upon BRK
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
;      Mnemonic          Opcode
  DATA "ADC#"    $00 $00 $69
  DATA "ADCZ"    $00 $00 $65
  DATA "ASLA"    $00 $00 $0A
  DATA "BCC"     $00 $00 $90
  DATA "BCS"     $00 $00 $B0
  DATA "BEQ"     $00 $00 $F0
  DATA "BITZ"    $00 $00 $24
  DATA "BMI"     $00 $00 $30
  DATA "BNE"     $00 $00 $D0
  DATA "BPL"     $00 $00 $10
  DATA "BRK"     $00 $00 $00
  DATA "CLC"     $00 $00 $18
  DATA "CMPZ,X"  $00 $00 $D5
  DATA "CMP#"    $00 $00 $C9
  DATA "CMP,Y"   $00 $00 $D9
  DATA "DEY"     $00 $00 $88
  DATA "INCZ"    $00 $00 $E6
  DATA "INX"     $00 $00 $E8
  DATA "INY"     $00 $00 $C8
  DATA "JMP"     $00 $00 $4C
  DATA "JSR"     $00 $00 $20
  DATA "LDAZ"    $00 $00 $A5
  DATA "LDA#"    $00 $00 $A9
  DATA "LDA(),Y" $00 $00 $B1
  DATA "LDA,Y"   $00 $00 $B9
  DATA "LDX#"    $00 $00 $A2
  DATA "LDY#"    $00 $00 $A0
  DATA "ORAZ"    $00 $00 $05
  DATA "RTS"     $00 $00 $60
  DATA "SBC#"    $00 $00 $E9
  DATA "SBCZ"    $00 $00 $E5
  DATA "SEC"     $00 $00 $38
  DATA "STA"     $00 $00 $8D
  DATA "STA(),Y" $00 $00 $91
  DATA "STAZ"    $00 $00 $85
  DATA "STAZ,X"  $00 $00 $95
  DATA "TYA"     $00 $00 $98
  DATA "DATA"    $00 $01 $00 ; Directive
  DATA $00


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
  BNE ~ceof_notspace 
  RTS
ceof_notspace
  CMP# "\n"
  BNE ~ceof_notnewline
  RTS
ceof_notnewline
  CMP# ";"
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
; On exit NEXTCHAR contains next character after token
;         Y is preserved
;         A, X are not preserved
readtoken
  LDX# $00
readtokenloop
  STAZ,X <TOKEN
  INX
  JSR read
  JSR cmpendoftoken
  BEQ ~rt_done
  JMP readtokenloop
rt_done
  STAZ <NEXTCHAR
  LDA# $00
  STAZ,X <TOKEN
  RTS


; On entry Y contains offset into TAB
; On exit TABL;TABH += Y + 1
;         Y = 0
;         A is not preserved
advanceintab
  INY
  TYA
  LDY# $00
  CLC
  ADCZ <TABL
  STAZ <TABL
  TYA                  ; A <- 0
  ADCZ <TABH
  STAZ <TABH
  RTS


; On entry TOKEN contains token to find
;          TABL;TABH points to table
; On exit C clear if found; set if not found
;         TABL;TABH points to token value if found
;                   or to end of table if not found
;         Y = 0
;         A is not preserved
findintab
  LDY# $00
fit_tokenloop          ; Outer loop
  LDA(),Y <TABL
  BNE ~fit_charloop
  ; not found
  SEC
  RTS
;invariant: pointed at first char
; first char of mnenomic in table loaded
fit_charloop           ; inner loop
  CMP,Y TOKEN
  BNE ~fit_skipcurrent
  CMP# $00
  BNE ~fit_nextchar
  ; found a match
  JSR advanceintab
  CLC
  RTS
fit_nextchar           ; Move to next char
  INY
  LDA(),Y <TABL
  JMP fit_charloop     ; Inner loop
fit_skipcurrent        ; Skip current symbol in table
  LDA(),Y <TABL
  BEQ ~fit_nextsymbol
  INY
  JMP fit_skipcurrent
fit_nextsymbol         ; Move to next symbol in table
  INY                  ; Move past 2 data bytes
  INY
  JSR advanceintab
  JMP fit_tokenloop    ; Outer loop


; On entry TOKEN contains a label
; On exit C clear if found; set if not found
;         TABL;TABH points to token value if found
;                   or to end of table if not found
;         Y = 0
;         A is not preserved
findlabel
  LDA# <LBTAB
  STAZ <TABL
  LDA# >LBTAB
  STAZ <TABH
  JMP findintab        ; Tail call


; On exit NEXTCHAR contains the next character
readandfindexistinglabel
  JSR readtoken
  BITZ <PASS
  BMI ~rafel_pass2
  ; Pass 1
  RTS
rafel_pass2
  JSR findlabel
  BCC ~rafel_found
  JMP err_labelnotfound
rafel_found
  LDA(),Y <TABL
  STAZ <HEX2
  INY
  LDA(),Y <TABL
  STAZ <HEX1
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
  JSR read             ; Read the first hex character
  JSR readhex
  STAZ <HEX1
  JSR read
  JSR cmpendoftoken
  BNE ~gh_second
  CLC
  RTS
gh_second
  JSR readhex
  STAZ <HEX2
  JSR read
  SEC
  RTS


; Read 2 to 4 hex characters and emit 1 or 2 bytes
; When 2 bytes, emit LSB then MSB
; Uses HEX1, HEX2 and NEXTCHAR
; On exit A contains next character
emithex
  JSR grabhex
  STAZ <NEXTCHAR
  BCC ~eh_one
  LDAZ <HEX2
  JSR emit
eh_one
  LDAZ <HEX1
  JSR emit
  LDAZ <NEXTCHAR
  RTS

; On entry NEXTCHAR contains the next character
; On exit C set if value read; clear otherwise
readvalue
  LDAZ <NEXTCHAR
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
  JMP grabhex          ; Tail call


; capturelabel helper
cl_setpc
  JSR readvalue
  JSR skiprestofline
  LDAZ <HEX2
  STAZ <PCL
  LDAZ <HEX1
  STAZ <PCH
  RTS

; capturelabel
capturelabel
  JSR readtoken
  LDAZ <TOKEN
  CMP# "*"
  BNE ~cl_normallabel
  JMP cl_setpc
cl_normallabel
  BITZ <PASS
  BPL ~cl_pass1
  ; Pass 2 - don't capture
  LDAZ <NEXTCHAR
  JMP skiprestofline   ; Tail call
cl_pass1
  JSR findlabel
  BCS ~cl_notfound
  JMP err_duplicatelabel
cl_notfound
cl_loop                ; Copy TOKEN to table
  LDA,Y TOKEN
  STA(),Y <TABL
  BEQ ~cl_copyvalue
  INY
  JMP cl_loop
cl_copyvalue           ; Copy value or PC value to table
  JSR readvalue
  STAZ <NEXTCHAR
  BCS ~cl_hextotable
  ; Store program counter
  LDAZ <PCL
  STAZ <HEX2
  LDAZ <PCH
  STAZ <HEX1
cl_hextotable
  INY
  LDAZ <HEX2
  STA(),Y <TABL
  INY
  LDAZ <HEX1
  STA(),Y <TABL
  ; Skip past rest of table
  LDAZ <NEXTCHAR
  JSR skiprestofline
  ; Terminate table value
  INY
  LDA# $00
  STA(),Y <TABL
  RTS


; Emit the opcode
; On exit A contains the next character
emitopcode
  JSR readtoken
  LDA# <MNTAB
  STAZ <TABL
  LDA# >MNTAB
  STAZ <TABH
  JSR findintab
  BCC ~eo_found
  JMP err_opcodenotfound
eo_found
  LDA(),Y <TABL
  BNE ~eo_done         ; Not opcode (DATA command)
  ; Opcode
  INY
  LDA(),Y <TABL
  JSR emit
eo_done
  LDAZ <NEXTCHAR
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
  ; Emit low byte then high byte from table
  LDAZ <HEX2
  JSR emit
  LDAZ <HEX1
  JSR emit
  LDAZ <NEXTCHAR       ; Load next character
  RTS


; On exit A contains the next character
emitlabellsb
  JSR readandfindexistinglabel
  ; Emit low byte
  LDAZ <HEX2
  JSR emit
  LDAZ <NEXTCHAR       ; Load next character
  RTS


; On exit A contains the next character
emitlabelmsb
  JSR readandfindexistinglabel
  ; Emit high byte
  LDAZ <HEX1
  JSR emit
  LDAZ <NEXTCHAR       ; Load next character
  RTS


emitlabelrel
  BITZ <PASS
  BMI ~elr_pass2
  ; Pass 1
  JSR readtoken
  JSR emit
  LDAZ <NEXTCHAR
  RTS
elr_pass2
  JSR readandfindexistinglabel
  ; Calculate target - PC - 1
  CLC ; for the - 1
  LDAZ <HEX2
  SBCZ <PCL
  JSR emit
  LDAZ <NEXTCHAR
  RTS


; Main assembler
assemble
lnloop
  JSR read
  BCC ~lnloop1
  RTS                  ; At end of input
lnloop1
  JSR checkforend
  BCC ~lnloop2
  JMP lnloop
lnloop2
  CMP# " "
  BEQ ~lnloop3
  JSR capturelabel
  JMP lnloop
lnloop3
  JSR skipspaces
  JSR checkforend
  BCC ~lnloop4
  JMP lnloop
lnloop4
; Read mnemonic and emit opcode
  JSR emitopcode
tokloop
  JSR skipspaces
  JSR checkforend
  BCC ~tokloop1
  JMP lnloop           ; End of line
tokloop1
  CMP# "\""            ; Quoted string
  BNE ~tokloop2
  JSR emitquoted
  JMP tokloop
tokloop2
  CMP# "$"             ; 1 or 2 byte hex
  BNE ~tokloop3
  JSR emithex
  JMP tokloop
tokloop3
  CMP# "<"             ; LSB of variable
  BNE ~tokloop4
  JSR read
  JSR emitlabellsb
  JMP tokloop
tokloop4
  CMP# ">"             ; MSB of variable
  BNE ~tokloop5
  JSR read
  JSR emitlabelmsb
  JMP tokloop
tokloop5
  CMP# "~"             ; Relative address
  BNE ~tokloop6
  JSR read
  JSR emitlabelrel
  JMP tokloop
tokloop6
  JSR emitlabel        ; 2 byte variable
  JMP tokloop

; Entry point
start
  LDA# $00
  STAZ <PCL
  STAZ <PCH
  STA LBTAB
  STAZ <PASS           ; Bit 7 = 0 (pass 1)
  JSR assemble
  LDA# $00
  STAZ <PCL
  STAZ <PCH
  LDA# $FF
  STAZ <PASS           ; Bit 7 = 1 (pass 2)
  JSR assemble
  BRK $00              ; Success


LBTAB                  ; Labels table comes after code


  DATA start ; Emulation environment jumps to address in last 2 bytes
