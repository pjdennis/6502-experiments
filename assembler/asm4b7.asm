; inst.asm prepended to provide instruction hash table


; Provided by environment:
;   read_b:  Returns next character in A
;            C set when at end
;            Automatically restarts input after reaching end
;
;   write_b: Writes A to output
read_b    = $F006
write_b   = $F009

LHASHTABL = $4000      ; Label hash table (low and high)
LHASHTABH = $4080      ; "
HEAP      = $4100      ; Data heap

TEMP      = $00        ; 1 byte
TABPL     = $01        ; 2 byte table pointer
TABPH     = $02        ; "
PCL       = $03        ; 2 byte program counter
PCH       = $04        ; "
HEX1      = $05        ; 1 byte
HEX2      = $06        ; 1 byte
PASS      = $07        ; 1 byte $00 = pass 1 $FF = pass 2
MEMPL     = $08        ; 2 byte heap pointer
MEMPH     = $09        ; "
PL        = $0A        ; 2 byte pointer
PH        = $0B        ; "
HASH      = $0C        ; 1 byte hash value
HTLPL     = $0D        ; 2 byte pointer to low byte hash table
HTLPH     = $0E        ; "
HTHPL     = $0F        ; 2 byte pointer to high byte hash table
HTHPH     = $10        ; "
INST_FLAG = $11        ; flags associated with instruction
TOKEN     = $12        ; multiple bytes

INST_PSUEDO   = $01
INST_RELATIVE = $02
INST_BYTE     = $04


; Environment should surface error codes and messages on BRK
err_labelnotfound
  BRK $01 "Label not found" $00

err_duplicatelabel
  BRK $02 "Duplicate label" $00

err_opcodenotfound
  BRK $03 "Opcode not found" $00

err_expectedhex
  BRK $04 "Expected hex value" $00

err_branchoutofrange
  BRK $05 "Branch out of range" $00

err_valueoutofrange
  BRK $06 "Value out of range" $00

err_invalidhex
  BRK $07 "Invalid hex" $00

err_pc_value_expected
  BRK $08 "PC value expected" $00

err_closing_quote_not_found
  BRK $09 "Closing quote not found" $00


init_heap
  LDA# <HEAP
  STAZ MEMPL
  LDA# >HEAP
  STAZ MEMPH
  RTS


; On entry Y contains the amount to advance
; On exit MEMPL;MEMPH is incremented by Y
;         Y = 0
;         X is preserved
;         A is not preserved
advance_heap
  TYA
  LDY# $00
  CLC
  ADCZ MEMPL
  STAZ MEMPL
  TYA
  ADCZ MEMPH
  STAZ MEMPH
  RTS


select_label_hash_table
  LDA# <LHASHTABL
  STAZ HTLPL
  LDA# >LHASHTABL
  STAZ HTLPH
  LDA# <LHASHTABH
  STAZ HTHPL
  LDA# >LHASHTABH
  STAZ HTHPH
  RTS


select_instruction_hash_table
  LDA# <IHASHTABL
  STAZ HTLPL
  LDA# >IHASHTABL
  STAZ HTLPH
  LDA# <IHASHTABH
  STAZ HTHPL
  LDA# >IHASHTABH
  STAZ HTHPH
  RTS


init_hash_table
  LDY# $00
  TYA                  ; A <- 0
iht_loop
  STAZ(),Y HTLPL
  STAZ(),Y HTHPL
  INY
  BNE iht_loop
  RTS
  

; On entry TOKEN contains the token to calculate hash from
; On exit HASH contains the calculated hash value
;         A, X, Y are not preserved
calculate_hash
  LDA# $00
  STAZ HASH
  LDX# $00
ch_loop
  LDAZ,X TOKEN
  BEQ ch_done
  AND# $7F
  EORZ HASH
  TAY
  LDA,Y scramble_table
  STAZ HASH
  INX
  JMP ch_loop
ch_done
  RTS


; On entry HASH contains the hash value
; On exit Z set if entry is empty, clear otherwise
;         X is preserved
;         A, Y are not preserved
hash_entry_empty
  LDAZ HASH
  TAY
  LDAZ(),Y HTLPL
  BNE hee_done
  LDAZ(),Y HTHPL
hee_done
  RTS


; Load from hash table to TABPL;TABPH
; On entry HASH contains the hash value
; On exit TABPL;TABPH countains pointer corresponding to the hash value
;         X is preserved
;         A, Y are not preserved
load_hash_entry
  LDAZ HASH
  TAY
  LDAZ(),Y HTLPL
  STAZ TABPL
  LDAZ(),Y HTHPL
  STAZ TABPH
  RTS


; Store current memory pointer in hash table
; On entry HASH contains the hash code to store under
;          MEMPL;MEMPH contains the pointer to store in the hash table
; On exit X is preserved
;         A, Y are not preserved
store_hash_entry
  LDAZ HASH
  TAY
  LDAZ MEMPL
  STAZ(),Y HTLPL
  LDAZ MEMPH
  STAZ(),Y HTHPL
  RTS


; Store current memory pointer in table
; On entry TABPL;TABPH,Y points to location to store pointer
;          MEMPL;NENPL contains the pointer to store
; On exit TABPL;TABPH,Y points to the location following the stored pointer
;         X is preserved
;         A is not preserved
store_table_entry
  LDAZ MEMPL
  STAZ(),Y TABPL
  INY
  LDAZ MEMPH
  STAZ(),Y TABPL
  INY
  RTS


; On entry TABPL;TABPH point to head of list of entries
;          TOKEN contains the token to find
; On exit C clear if found; set if not found
;         TABPL;TABPH,Y points to value if found
;         or to 'next' pointer if not found
find_token
ft_tokenloop
  ; Store the current pointer
  LDAZ TABPL
  STAZ PL
  LDAZ TABPH
  STAZ PH
  ; Advance past 'next' pointer
  CLC
  LDA# $02
  ADCZ TABPL
  STAZ TABPL
  LDA# $00
  ADCZ TABPH
  STAZ TABPH
  ; Check for matching token
  LDY# $FF
ft_charloop
  INY
  LDAZ(),Y TABPL
  CMP,Y TOKEN
  BNE ft_notmatch
  CMP# $00
  BNE ft_charloop
  ; Match
  INY                  ; point tab,Y to value
  CLC
  RTS
ft_notmatch            ; Not a match - move to next
  ; Check if 'next' pointer is 0
  LDY# $00
  LDAZ(),Y PL
  BNE ft_notmatch1     ; not zero
  INY
  LDAZ(),Y PL
  BEQ ft_atend
  ; Not at end
  STAZ TABPH
  LDA# $00
  STAZ TABPL
  JMP ft_tokenloop
ft_notmatch1
  STAZ TABPL
  INY
  LDAZ(),Y PL
  STAZ TABPH
  JMP ft_tokenloop
ft_atend
  ; point tabp,Y to the zero 'next' pointer
  LDAZ PL
  STAZ TABPL
  LDAZ PH
  STAZ TABPH
  LDY# $00
  SEC ; Carry set indicates not found
  RTS


; On entry token contains the token to find
; On exit C = 0 if found or 1 if not found
; On exit HEX1 and HEX2 contains MSB and LSB of value if found
;         A, X, Y are not preserverd
find_in_hash
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ fih_notfound
  ; Entry exists
  JSR load_hash_entry
  JSR find_token
  BCS fih_notfound
  ; Found
  LDAZ(),Y TABPL
  STAZ HEX2
  INY
  LDAZ(),Y TABPL
  STAZ HEX1
  CLC
  RTS
fih_notfound
  SEC
  RTS


; Stores null next pointer, token and value on heap
; and advances heap pointer 
; On entry HEX1 and HEX2 contain MSB and LSB of value
;          TOKEN contains name of token
; On exit MEMPL;MEMPH points to the next free heap location
;         Y = 0
;         X is preserved
;         A is not preserved
store_token
  LDY# $00
  ; Store null pointer (pointer to next)
  LDA# $00
  STAZ(),Y MEMPL
  INY
  STAZ(),Y MEMPL
  INY
  JSR advance_heap
  ; Store token name
  LDY# $FF             ; Alternative: DEY
st_loop
  INY
  LDA,Y TOKEN
  STAZ(),Y MEMPL
  BNE st_loop
  INY
  ; Store value
  LDAZ HEX2
  STAZ(),Y MEMPL
  INY
  LDAZ HEX1
  STAZ(),Y MEMPL
  INY
  JMP advance_heap     ; Tail call


; Add TOKEN mapped to HEX2;HEX1 to hash table
; On entry TOKEN contains token
;          HEX1 and HEX2 contain MSB and LSB of value
; On exit C = 0 if added or 1 if already exists
;         A, X, Y are not preserved
hash_add
  JSR calculate_hash
  JSR hash_entry_empty
  BEQ ha_entry_empty
  JSR load_hash_entry
  JSR find_token
  BCS ha_new
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


; Emit value (pass 2 only) and increment PC
; On entry A contains the byte to emit
; On exit A, X, Y are preserved
emit
  BITZ PASS
  BPL emit_incpc       ; Skip writing during pass 1
  JSR write_b
emit_incpc
  INCZ PCL
  BNE emit_done
  INCZ PCH
emit_done
  RTS


; Read and discard characters up to the end of the current line
; On entry A contains the next character
; On exit A contains "\n"
;         X, Y are preserved
skip_rest_of_line
srol_loop
  CMP# "\n"
  BEQ srol_done
  JSR read_b
  JMP srol_loop
srol_done
  RTS


; Read and discard space characters
; On entry A contains the next character
; On exit A contains the next character following the last space
;         X, Y are preserved
skip_spaces
ss_loop
  CMP# " "
  BNE ss_done
  JSR read_b
  JMP ss_loop
ss_done
  RTS


; Check whether the next character (in A) is NOT a token character
; On entry A contains the next character
; On exit Z is set if current character terminates the current token, unset otherwise
;         A, X, Y are preserved
compare_end_of_token
  CMP# " "
  BEQ ceof_end
  CMP# "\n"
  BEQ ceof_end
  CMP# ";"
ceof_end
  RTS


; Checks for end of line and skips past if at end
; On entry A contains next character
; On exit C set if end of line, clear otherwise
;         A contains next character
;         X, Y are preserved
check_for_end_of_line
  CMP# ";"
  BEQ cfeol_end
  CMP# "\n"
  BEQ cfeol_done
  ; Not at end
  CLC
  RTS
cfeol_end
  JSR skip_rest_of_line
cfeol_done
  SEC
  RTS


; Reads token into TOKEN (zero terminated)
; On entry A contains first character of token
; On exit A contains next character after token
;         Y is preserved
;         X is not preserved
read_token
  LDX# $00
rt_loop
  STAZ,X TOKEN
  INX
  JSR read_b
  JSR compare_end_of_token
  BNE rt_loop
  TAY                  ; Save next char
  LDA# $00
  STAZ,X TOKEN
  TYA                  ; Restore next char
  RTS


; Read a label, look up in the current hash table and return the associated value
; On entry A contains the first character of the label
; On exit HEX1 and HEX2 contains the MSB and LSB of the hash table value
;         A contains the next character following the token
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found in hash table
read_and_find_existing_label
  JSR read_token
  BITZ PASS
  BMI rafel_pass2
  ; Pass 1
  RTS
rafel_pass2
  PHA                  ; Save next char
  JSR select_label_hash_table
  JSR find_in_hash
  BCC rafel_found
  JMP err_labelnotfound
rafel_found
  PLA                  ; Restore next char
  RTS


; Convert hex character to associated value
; On entry, A contains a hex character A-Z|0-9
; On exit A contains the value (0-15)
;         X, Y are preserved
; Raises 'Invalid hex' error if input is not a valid hex character
convert_hex_character
  CMP# "A"
  BCC chc_numeric       ; < 'A'
  SBC# "A"             ; Carry already set
  CMP# $06
  BCC chc_ok1
  JMP err_invalidhex
chc_ok1
  CLC
  ADC# $0A             ; ADC# 10
  RTS
chc_numeric
  SEC
  SBC# "0"
  CMP# $0A
  BCC chc_ok2
  JMP err_invalidhex
chc_ok2
  RTS


; Reads 1 byte (2 character) hex value
; On entry A contains first hex character
; On exit A contains 2 character value (0-255)
;         X, Y are preserved
;         TEMP is not preserved
; Raises 'Invalid hex' error if encountering non-hex characters
read_hex_byte
  JSR convert_hex_character
  ASLA
  ASLA
  ASLA
  ASLA
  STAZ TEMP
  JSR read_b
  JSR convert_hex_character
  ORAZ TEMP
  RTS


; Reads 1 or 2 byte (2 or 4 character) hex value
; On entry, next character read will be first hex character
; On exit C set if 2 bytes read clear if 1 byte read
;         A contains the next character
;         X, Y are preserved
; Rasises 'Invalid hex' error if encountering non-hex characters
read_hex_byte_or_word
  JSR read_b           ; Read the 1st hex character
  JSR read_hex_byte    ; Read 2nd hex character and convert
  STAZ HEX1
  JSR read_b           ; Read 3rd hex char or terminator
  JSR compare_end_of_token
  BNE rhbow_second
  CLC                  ; No second byte so return C = 0
  RTS
rhbow_second
  JSR read_hex_byte    ; Read 4th hex char and convert
  STAZ HEX2
  JSR read_b           ; Read next char
  SEC                  ; Second byte so return C = 1
  RTS


; Read 2 to 4 hex characters and emit 1 or 2 bytes
; When 2 bytes, emit LSB then MSB
; Uses HEX1, HEX2
; On exit A contains next character
emit_hex
  JSR read_hex_byte_or_word ; Returns C = 1 if 2 bytes read
  TAY                       ; Save next char
  BCC eh_one
  LDAZ HEX2
  JSR emit
eh_one
  LDAZ HEX1
  JSR emit
  TYA                       ; Restore next char
  RTS


; Attempt to read an assigned value
; On entry A contains the next character
; On exit C set if value read; clear otherwise
;         HEX2 and HEX1 contain the LSB and MSB of the value read
;         A contains the next character
;         X, Y are preserved
; Raises 'Expected hex' error if value was not identified as hex (via '$')
;        'Bad hex' error if non-hex characters were encountered
read_value
  JSR skip_spaces
  CMP# "="
  BEQ rv_value
  CLC                  ; Did not find valud so return C = 0
  RTS
rv_value
  JSR read_b           ; Read the character after the "="
  JSR skip_spaces
  CMP# "$"
  BEQ rv_hexvalue
  JMP err_expectedhex
rv_hexvalue
  JSR read_hex_byte_or_word
  BCS rv_ok            ; 2 bytes were read
  ; 1 byte was read - shift into LSB position (HEX2)
  TAY                  ; Save next char
  LDAZ HEX1
  STAZ HEX2
  LDA# $00
  STAZ HEX1
  TYA                  ; Restore next char
rv_ok
  SEC
  RTS


; Reads a label, and optionally an assigned value. The label is stored in the current hash table
; mapped to the assigned value (if provided) otherwise the current PC value. The special label '*'
; is not stored in the has table but instead requires an assigned value which sets PC
; On entry A contains the first character of the label
; On exit the hash table or PC is updated accordingly
;         A, X, Y are not preserved
; Raises 'PC value expected' if no value provided when setting PC via '*'
;        'Duplicate label' error if label has already been encountered
;        'Expected hex' error if assigned value was not identified as hex (via '$')
;        'Bad hex' error if non-hex characters were encountered
capture_label
  JSR read_token
  TAY                   ; Save next char
  LDAZ TOKEN
  CMP# "*"
  BNE cl_normallabel
  ; Set PC
  TYA                   ; Restore next char
  JSR read_value
  BCS cl_pc_value_read
  JMP err_pc_value_expected
cl_pc_value_read
  JSR skip_rest_of_line
  ; No need to retain next char as caller
  ; goes straight to next line
  LDAZ HEX2
  STAZ PCL
  LDAZ HEX1
  STAZ PCH
  RTS
cl_normallabel
  BITZ PASS
  BPL cl_pass1
  ; Pass 2 - don't capture
  TYA                   ; Restore next char
  JMP skip_rest_of_line ; Tail call
cl_pass1
  TYA                   ; Restore next char
  JSR read_value
  PHA                   ; Save next char
  BCS cl_hextotable
  ; Store program counter
  LDAZ PCL
  STAZ HEX2
  LDAZ PCH
  STAZ HEX1
cl_hextotable
  JSR select_label_hash_table
  JSR hash_add
  PLA                   ; Restore next char
  BCC cl_added
  JMP err_duplicatelabel
cl_added
  JSR skip_rest_of_line
  ; No need to retain next char as caller
  ; goes straight to next line
  RTS


; Read and emit an opcode
; On entry A contains the first character of the opcode
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Opcode not found' error if opcode is not found
emit_opcode
  JSR read_token
  PHA                  ; Save next char
  JSR select_instruction_hash_table
  JSR find_in_hash  
  BCC eo_found
  PLA                  ; Restore next char
  JMP err_opcodenotfound
eo_found
  LDAZ HEX2
  STAZ INST_FLAG
  AND# INST_PSUEDO
  BNE eo_done          ; Not opcode (DATA command)
  ; Opcode
  LDAZ HEX1
  JSR emit
eo_done
  PLA                  ; Restore next char
  RTS


; Read and emit quoted ASCII
; On entry next character read will be the first character within quotes
; On exit A contains the next character after the closing quote
;         X, Y are preserved
; Raises 'Closing quote not found' error if closing quote not found on current line
emit_quoted
eq_loop
  JSR read_b
  CMP# "\n"
  BEQ eq_err_closing_quote
  CMP# "\""
  BEQ eq_done
  CMP# "\\"
  BNE eq_notescaped
  JSR read_b
  CMP# "\n"
  BEQ eq_err_closing_quote
  CMP# "n"
  BNE eq_notescaped
  LDA# "\n"            ; Escaped "n" is linefeed
eq_notescaped
  JSR emit
  JMP eq_loop
eq_done
  JSR read_b           ; Done; read next char
  RTS
eq_err_closing_quote
  JMP err_closing_quote_not_found


; Read and emit a 2 byte label value
; On entry A countains the first character of the label
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found
emit_label
  JSR read_and_find_existing_label
  TAY                  ; Save next char
  ; Emit low byte then high byte from table
  LDAZ HEX2
  JSR emit
  LDAZ HEX1
  JSR emit
  TYA                  ; Restore next char
  RTS


; Read and emit a 1 byte label value
; On entry A countains the first character of the label
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found
;        'Value of of range' error if value is > 255 (> 1 byte)
emit_label_byte
  JSR read_and_find_existing_label
  TAY                  ; Save next char
  BITZ PASS
  BPL elb_ok           ; Skip validation on pass 1
  LDAZ HEX1
  BEQ elb_ok
  JMP err_valueoutofrange
elb_ok
  ; Emit low byte
  LDAZ HEX2
  JSR emit
  TYA                  ; Restore next char
  RTS 


; Read and emit the least significant byte of a label value
; On entry A countains the first character of the label
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found
emit_label_lsb
  JSR read_and_find_existing_label
  TAY                  ; Save next char
  ; Emit low byte
  LDAZ HEX2
  JSR emit
  TYA                  ; Restore next char
  RTS


; Read and emit the most significant byte of a label value
; On entry A countains the first character of the label
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found
emit_label_msb
  JSR read_and_find_existing_label
  TAY                  ; Save next char
  ; Emit high byte
  LDAZ HEX1
  JSR emit
  TYA                  ; Restore next character
  RTS


; Read and emit a label value relative to PC
; On entry A countains the first character of the label
; On exit A contains the next character
;         X, Y are not preserved
; Raises 'Label not found' error if label is not found
;        'Branch out of range' error if distance from value to PC exceeds 1 signed byte
emit_label_relative
  JSR read_and_find_existing_label
  TAY                  ; Save next char
  BITZ PASS
  BPL elr_ok           ; Skip calculations and validations on pass 1

  ; Calculate target - PC - 1
  CLC ; for the - 1
  LDAZ HEX2
  SBCZ PCL
  STAZ HEX2
  LDAZ HEX1
  SBCZ PCH

  CMP# $00
  BEQ elr_forward
  CMP# $FF
  BEQ elr_backward
  JMP err_branchoutofrange

elr_forward
  LDAZ HEX2
  AND# $80
  BEQ elr_ok
  JMP err_branchoutofrange

elr_backward
  LDAZ HEX2
  AND# $80
  BNE elr_ok
  JMP err_branchoutofrange

elr_ok
  LDAZ HEX2
  JSR emit
  TYA                  ; Restore next char
  RTS


; Read from input, assemble code and write to output
; On entry PASS indicates the current pass:
;            bit 7 clear = pass 1
;            bit 7 set = pass 2
; On exit A, X, Y are not preserved
assemble
  LDA# $00
  STAZ PCL
  STAZ PCH
lnloop
  JSR read_b
  BCC lnloop1
  RTS                  ; At end of input
lnloop1
  JSR check_for_end_of_line
  BCS lnloop
  CMP# " "
  BEQ lnloop2
  JSR capture_label
  JMP lnloop
lnloop2
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS lnloop
  ; Read mnemonic and emit opcode
  JSR emit_opcode
  JMP tokstart
tokloop
  TAY                  ; Save next char
  LDA# $00
  STAZ INST_FLAG       ; Reset instruction flags after first iteration
  TYA                  ; Restore next char
tokstart
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS lnloop           ; End of line
  CMP# "\""            ; Quoted string
  BNE tokloop1
  JSR emit_quoted
  JMP tokloop
tokloop1
  CMP# "$"             ; 1 or 2 byte hex
  BNE tokloop2
  JSR emit_hex
  JMP tokloop
tokloop2
  CMP# "<"             ; LSB of variable
  BNE tokloop3
  JSR read_b
  JSR emit_label_lsb
  JMP tokloop
tokloop3
  CMP# ">"             ; MSB of variable
  BNE tokloop4
  JSR read_b
  JSR emit_label_msb
  JMP tokloop
tokloop4
  TAY                  ; Save next char
  LDAZ INST_FLAG
  AND# INST_RELATIVE
  BEQ tokloop5
  TYA                  ; Restore next char
  JSR emit_label_relative
  JMP tokloop
tokloop5
  LDAZ INST_FLAG
  AND# INST_BYTE
  BEQ tokloop6
  TYA                  ; Restore next char
  JSR emit_label_byte
  JMP tokloop
tokloop6
  TYA                  ; Restore next char
  JSR emit_label        ; 2 byte variable
  JMP tokloop


; Entry point
start
  JSR init_heap
  JSR select_label_hash_table
  JSR init_hash_table
  LDA# $00
  STAZ PASS           ; Bit 7 = 0 (pass 1)
  JSR assemble
  LDA# $FF
  STAZ PASS           ; Bit 7 = 1 (pass 2)
  JSR assemble
  BRK $00              ; Success


  DATA start ; Emulation environment jumps to address in last 2 bytes
