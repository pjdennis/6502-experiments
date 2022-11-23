; Provided by environment:
;   read:    Returns next character in A
;            C set when at end
;            Automatically restarts input after reaching end
;
;   write_b: Writes A to output
read     = $F006
write_b  = $F009

TEMP     = $0000       ; 1 byte
TABL     = $0001       ; 1 byte
TABH     = $0002       ; 1 byte
PCL      = $0003       ; 1 byte
PCH      = $0004       ; 1 byte
HEX1     = $0005       ; 1 byte
HEX2     = $0006       ; 1 byte
PASS     = $0007       ; 1 byte $00 = pass 1 $FF = pass 2
TOKEN    = $0008       ; multiple bytes

;LBTAB    = $3000

*        = $2000       ; Set PC


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
  DATA "CMP#"    $00 $00 $C9
  DATA "CMP,Y"   $00 $00 $D9
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
  DATA "PHA"     $00 $00 $48
  DATA "PLA"     $00 $00 $68
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
;         X is preserved
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
  BNE ~fit_skipcurrent ; Current symbol not a match
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


; On exit A contains the next character
readandfindexistinglabel
  JSR readtoken
  BITZ <PASS
  BMI ~rafel_pass2
  ; Pass 1
  RTS
rafel_pass2
  PHA                  ; Save next char
  JSR findlabel
  BCC ~rafel_found
  PLA                  ; Restore next char
  JMP err_labelnotfound
rafel_found
  ; Store value of label into HEX2 and HEX1
  LDA(),Y <TABL
  STAZ <HEX2
  INY
  LDA(),Y <TABL
  STAZ <HEX1
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
  JSR findlabel
  BCS ~cl_notfound
  PLA                  ; Restore next char
  JMP err_duplicatelabel
cl_notfound
cl_loop                ; Copy TOKEN to table
  LDA,Y TOKEN
  STA(),Y <TABL
  BEQ ~cl_copyvalue
  INY
  JMP cl_loop
cl_copyvalue           ; Copy value or PC value to table
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
  INY
  LDAZ <HEX2
  STA(),Y <TABL
  INY
  LDAZ <HEX1
  STA(),Y <TABL
  ; Skip past rest of table
  PLA                  ; Restore next char
  JSR skiprestofline
  ; Terminate table value
  ; No need to retain next char as caller
  ; goes straight to next line
  INY
  LDA# $00
  STA(),Y <TABL
  RTS


; Emit the opcode
; On exit A contains the next character
emitopcode
  JSR readtoken
  PHA                  ; Save next char
  LDA# <MNTAB
  STAZ <TABL
  LDA# >MNTAB
  STAZ <TABH
  JSR findintab
  BCC ~eo_found
  PLA                  ; Restore next char
  JMP err_opcodenotfound
eo_found
  LDA(),Y <TABL
  BNE ~eo_done         ; Not opcode (DATA command)
  ; Opcode
  INY
  LDA(),Y <TABL
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
  LDA# $00
  STA LBTAB
  STAZ <PASS           ; Bit 7 = 0 (pass 1)
  JSR assemble
  LDA# $FF
  STAZ <PASS           ; Bit 7 = 1 (pass 2)
  JSR assemble
  BRK $00              ; Success


LBTAB                  ; Labels table comes after code


  DATA start ; Emulation environment jumps to address in last 2 bytes
