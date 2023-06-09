; Addresses
TOKEN2     = $1D00
TOKEN      = $1E00      ; Buffer for the current token being read
LHASHTABL  = $1F00      ; Label hash table (low and high)
LHASHTABH  = $1F80      ; "
*          = $2000      ; Code generates here
FILE_STACK = $F000      ; File stack will grow down from 1 below here


  .zeropage

; Zero page locations
TEMP        DATA $00 ; 1 byte
PCL         DATA $00 ; 2 byte program counter
PCH         DATA $00 ; "
HEX1        DATA $00 ; 1 byte
HEX2        DATA $00 ; 1 byte
PASS        DATA $00 ; 1 byte $00 = pass 1 $FF = pass 2
MEMPL       DATA $00 ; 2 byte heap pointer
MEMPH       DATA $00 ; "
INST_FLAG   DATA $00 ; flags associated with instruction
STARTED     DATA $00 ; flag to indicate output has started
CURR_FILE   DATA $00 ; current file handle
CURLINEL    DATA $00 ; Current line (L)
CURLINEH    DATA $00 ; Current line (H)
IN_ZEROPAGE DATA $00 ; Flag indicating if in zero page section
PC_SAVEL    DATA $00 ; Save location for PC when switching sections
PC_SAVEH    DATA $00 ; "

  .code


; Include files
  .include inst12.asm.out   ; This goes first since the tables should start on a page boundary
  .include environment.asm
  .include common12.asm
FS_FILENAME   = TOKEN
FS_CURR_FILE  = CURR_FILE
FS_CURR_LINEL = CURLINEL
FS_CURR_LINEH = CURLINEH
  .include file_stack.asm
  .include to_decimal.asm


; Constants
INST_PSUEDO   = $01
INST_RELATIVE = $02
INST_BYTE     = $04


; Error messages
err_label_not_found
  BRK $01 "Label not found" $00

err_duplicate_label
  BRK $02 "Duplicate label" $00

err_opcode_not_found
  BRK $03 "Opcode not found" $00

err_branch_out_of_range
  BRK $05 "Branch out of range" $00

err_value_out_of_range
  BRK $06 "Value out of range" $00

err_invalid_hex
  BRK $07 "Invalid hex" $00

err_pc_value_expected
  BRK $08 "PC value expected" $00

err_closing_quote_not_found
  BRK $09 "Closing quote not found" $00

err_cannot_move_pc_backwards
  BRK $0A "Cannot move PC backwards" $00

err_unknown_directive
  BRK $0B "Unknown directive" $00

err_filename_expected
  BRK $0C "Filename expected" $00

err_usage
  BRK $0D "Usage <assebler> <input> <output>" $00


read_char
  LDAZ CURR_FILE
  JSR read
  BCS rc_at_end
  RTS
rc_at_end
  JSR file_stack_empty
  BEQ rc_done
  JSR pop_file_stack
  LDAZ CURR_FILE
  BEQ rc_set_carry
  JMP read_char          ; Recursive tail call
rc_set_carry
  SEC
rc_done
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


; Emit value (pass 2 only) and increment PC
; On entry A contains the byte to emit
; On exit A, X, Y are preserved
emit
  BITZ PASS
  BPL emit_incpc       ; Skip writing during pass 1
  BITZ IN_ZEROPAGE
  BMI emit_incpc       ; Skip writing when in zero page section
  JSR write
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
  JSR read_char
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
  JSR read_char
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
;         X is preserved
;         Y is not preserved
read_token
  STXZ TEMP
  LDX# $00
rt_loop
  JSR compare_end_of_token
  BEQ rt_done
  STA,X TOKEN
  INX
  JSR read_char
  JMP rt_loop
rt_done
  TAY                  ; Save next char
  LDA# $00
  STA,X TOKEN
  TYA                  ; Restore next char
  LDXZ TEMP
  RTS


; Read a label, look up in the current hash table and return the associated value
; On entry A contains the first character of the label
; On exit HEX1 and HEX2 contains the MSB and LSB of the hash table value
;         A contains the next character following the token
;         X is preserved
;       , Y is not preserved
; Raises 'Label not found' error if label is not found in hash table
read_and_find_existing_label
  JSR read_token
  PHA                  ; Save next char
  JSR select_label_hash_table
  JSR find_in_hash
  BCC rafel_found
  BITZ PASS
  BMI rafel_pass2
  LDA# $00
  STAZ HEX1
  STAZ HEX2
  PLA                  ; Restore next char
  RTS
rafel_pass2
  JMP err_label_not_found
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
  BCC chc_numeric      ; < 'A'
  SBC# "A"             ; Carry already set
  CMP# $06
  BCC chc_ok1
  JMP err_invalid_hex
chc_ok1
  CLC
  ADC# $0A             ; ADC# 10
  RTS
chc_numeric
  SEC
  SBC# "0"
  CMP# $0A
  BCC chc_ok2
  JMP err_invalid_hex
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
  JSR read_char
  JSR convert_hex_character
  ORAZ TEMP
  RTS


; Reads 1 or 2 byte (2 or 4 character) hex value
; On entry, A contains the first hex character
; On exit C set if 2 bytes read clear if 1 byte read
;         A contains the next character
;         X, Y are preserved
; Rasises 'Invalid hex' error if encountering non-hex characters
read_hex_byte_or_word
  JSR read_hex_byte    ; Read 2nd hex character and convert
  STAZ HEX1
  JSR read_char        ; Read 3rd hex char or terminator
  JSR compare_end_of_token
  BNE rhbow_second
  CLC                  ; No second byte so return C = 0
  RTS
rhbow_second
  JSR read_hex_byte    ; Read 4th hex char and convert
  STAZ HEX2
  JSR read_char        ; Read next char
  SEC                  ; Second byte so return C = 1
  RTS


; Read 2 to 4 hex characters and emit 1 or 2 bytes
; When 2 bytes, emit LSB then MSB
; Uses HEX1, HEX2
; On entry A contains the first hex character
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


; Save the current token
; On exit X is preserved
;         A, Y are not preserved
save_token
  PHA
  LDY# $FF
st2_loop
  INY
  LDA,Y TOKEN
  STA,Y TOKEN2
  BNE st2_loop
  PLA
  RTS


; Restore the current token
; On exit X is preserved
;         A, Y are not preserved
restore_token
  PHA
  LDY# $FF
rt2_loop
  INY
  LDA,Y TOKEN2
  STA,Y TOKEN
  BNE rt2_loop
  PLA
  RTS


; Attempt to read an assigned value
; On entry A contains the next character
; On exit C set if value read; clear otherwise
;         HEX2 and HEX1 contain the LSB and MSB of the value read
;         A contains the next character
;         X is preserved
;         Y is not preserved
; Raises 'Expected hex' error if value was not identified as hex (via '$')
;        'Bad hex' error if non-hex characters were encountered
read_value
  JSR skip_spaces
  CMP# "="
  BEQ rv_value
  CLC                  ; Did not find value so return C = 0
  RTS
rv_value
  JSR read_char        ; Read the character after the "="
  JSR skip_spaces
  CMP# "$"
  BEQ rv_hex_value
  JSR save_token
  JSR read_and_find_existing_label
  JSR restore_token
  JMP rv_ok
rv_hex_value
  JSR read_char
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


; Fast forward the program counter
; On entry PCL;PCH contains the current program counter
;          HEX2;HEX1 contains the new PC value
; On exit
; Raises 'Cannot move PC backwards' error if attempting to move PC backwards
update_pc
  BITZ STARTED
  BMI up_started
  DECZ STARTED
  JMP up_no_fill
up_started
  LDAZ HEX1            ; High byte
  CMPZ PCH
  BCC up_less
  BNE up_notless
  LDAZ HEX2            ; Low byte
  CMPZ PCL
  BCC up_less
up_notless
  BITZ PASS
  BPL up_no_fill       ; skip writing during pass 1
  BITZ IN_ZEROPAGE
  BMI up_no_fill
up_loop
  LDAZ HEX1
  CMPZ PCH
  BNE up_loop_not_done
  LDAZ HEX2
  CMPZ PCL
  BEQ up_loop_done
up_loop_not_done
  LDA# $00
  JSR write
  INCZ PCL
  BNE up_loop
  INCZ PCH
  JMP up_loop
up_loop_done
  RTS
up_less
  JMP err_cannot_move_pc_backwards
up_no_fill
  LDAZ HEX2
  STAZ PCL
  LDAZ HEX1
  STAZ PCH
up_done
  RTS


; Reads a label, and optionally an assigned value. The label is stored in the current hash table
; mapped to the assigned value (if provided) otherwise the current PC value. The special label '*'
; is not stored in the hash table but instead requires an assigned value which sets PC
; On entry A contains the first character of the label
; On exit the hash table or PC is updated accordingly
;         C is set if line fully processed, clear otherwise
;         A, X, Y are not preserved
; Raises 'PC value expected' if no value provided when setting PC via '*'
;        'Duplicate label' error if label has already been encountered
;        'Expected hex' error if assigned value was not identified as hex (via '$')
;        'Bad hex' error if non-hex characters were encountered
capture_label
  JSR read_token
  TAY                       ; Save next char
  LDA TOKEN
  CMP# "*"
  BNE cl_normal_label
  ; Set PC
  TYA                       ; Restore next char
  JSR read_value
  BCS cl_pc_value_read
  JMP err_pc_value_expected
cl_pc_value_read
  JSR skip_rest_of_line
  ; No need to retain next char as caller
  ; goes straight to next line
  JSR update_pc
  SEC                       ; Indicate line is fully processed
  RTS
cl_normal_label
  BITZ PASS
  BPL cl_pass_1
  ; Pass 2 - don't capture
  TYA                       ; Restore next char
  JSR read_value
  BCS cl_skip_and_return_processed
  JMP cl_skip_spaces_and_return_processed_flag
cl_pass_1
  TYA                       ; Restore next char
  JSR read_value
  PHA                       ; Save next char
  BCS cl_hex_to_table
  ; Store program counter
  LDAZ PCL
  STAZ HEX2
  LDAZ PCH
  STAZ HEX1
  JSR select_label_hash_table
  JSR hash_add
  PLA                       ; Restore next char
  BCS cl_duplicate_label
cl_skip_spaces_and_return_processed_flag
  JSR skip_spaces
  JMP check_for_end_of_line ; Tail call - returns with C set if at end of line
cl_hex_to_table
  JSR select_label_hash_table
  JSR hash_add
  PLA                       ; Restore next char
  BCS cl_duplicate_label
cl_skip_and_return_processed
  JSR skip_rest_of_line
  SEC                       ; Indicate line is fully processed
  ; No need to retain next char as caller
  ; goes straight to next line
  RTS

cl_duplicate_label
  JMP err_duplicate_label


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
  JMP err_opcode_not_found
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
; On entry A countains the first character within quotes
; On exit A contains the next character after the closing quote
;         X, Y are preserved
; Raises 'Closing quote not found' error if closing quote not found on current line
emit_quoted
eq_loop
  CMP# "\n"
  BEQ eq_err_closing_quote
  CMP# "\""
  BEQ eq_done
  CMP# "\\"
  BNE eq_not_escaped
  JSR read_char
  CMP# "\n"
  BEQ eq_err_closing_quote
  CMP# "n"
  BNE eq_not_escaped
  LDA# "\n"            ; Escaped "n" is linefeed
eq_not_escaped
  JSR emit
  JSR read_char
  JMP eq_loop
eq_done
  JSR read_char        ; Done; read next char
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
  JMP err_value_out_of_range
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
  JMP err_branch_out_of_range

elr_forward
  LDAZ HEX2
  AND# $80
  BEQ elr_ok
  JMP err_branch_out_of_range

elr_backward
  LDAZ HEX2
  AND# $80
  BNE elr_ok
  JMP err_branch_out_of_range

elr_ok
  LDAZ HEX2
  JSR emit
  TYA                  ; Restore next char
  RTS


; Swap PCL;PCH with PC_SAVEL;PC_SAVEH
; On exit A, X, Y are preserved
swap_pc_with_save
  ; Swap PC L with save location
  LDAZ PCL
  PHA
  LDAZ PC_SAVEL
  STAZ PCL
  PLA
  STAZ PC_SAVEL
  ; Swap PC H with save location
  LDAZ PCH
  PHA
  LDAZ PC_SAVEH
  STAZ PCH
  PLA
  STAZ PC_SAVEH
  RTS


; On entry, A contains the first character of the directive
process_directive
  JSR read_token
  PHA                  ; Save next char
  ; Check for 'include'
  LDA# <directive_include
  STAZ TABPL
  LDA# >directive_include
  STAZ TABPH
  JSR compare_token
  BEQ pd_include
  ; Check for 'zeropage'
  LDA# <directive_zeropage
  STAZ TABPL
  LDA# >directive_zeropage
  STAZ TABPH
  JSR compare_token
  BEQ pd_zeropage
  ; Check for 'code'
  LDA# <directive_code
  STAZ TABPL
  LDA# >directive_code
  STAZ TABPH
  JSR compare_token
  BEQ pd_code
  ; Directive not recognized
  PLA                  ; Restore next char
  JMP err_unknown_directive
pd_include
  PLA                  ; Restore next char
  JSR skip_spaces
  JSR check_for_end_of_line
  BCC pd_get_name
  JMP err_filename_expected
pd_get_name
  JSR read_token
  JSR skip_rest_of_line
  JSR push_file_stack
  RTS
pd_zeropage
  BITZ IN_ZEROPAGE
  BMI pd_in_zeropage
  LDA# $FF
  STAZ IN_ZEROPAGE
  JSR swap_pc_with_save
pd_in_zeropage
  PLA                  ; Restore next char
  JSR skip_rest_of_line
  RTS
pd_code
  BITZ IN_ZEROPAGE
  BPL pd_in_code
  LDA# $00
  STAZ IN_ZEROPAGE
  JSR swap_pc_with_save
pd_in_code
  PLA                  ; Restore next char
  JSR skip_rest_of_line
  RTS

directive_include
  DATA "include" $00

directive_zeropage
  DATA "zeropage" $00

directive_code
  DATA "code" $00


; Read from input, assemble code and write to output
; On entry PASS indicates the current pass:
;            bit 7 clear = pass 1
;            bit 7 set = pass 2
; On exit A, X, Y are not preserved
assemble_code
  LDA# $00
  STAZ STARTED
  STAZ IN_ZEROPAGE
  STAZ PCL
  STAZ PCH
  STAZ PC_SAVEL
  STAZ PC_SAVEH
  STAZ CURLINEL
  STAZ CURLINEH
ac_line_loop
  JSR read_char
  BCC ac_character_read
  RTS                  ; At end of input
ac_character_read
  INCZ CURLINEL
  BNE ac_line_incremented
  INCZ CURLINEH
ac_line_incremented
  JSR check_for_end_of_line
  BCS ac_line_loop
  CMP# " "
  BEQ ac_line_starts_with_space
  JSR capture_label
  BCC ac_check_for_opcode
  JMP ac_line_loop
ac_line_starts_with_space
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS ac_line_loop
ac_check_for_opcode
  CMP# "."
  BNE ac_opcode
; Directive
  JSR read_char
  JSR process_directive
  JMP ac_line_loop
ac_opcode
  ; Read mnemonic and emit opcode
  JSR emit_opcode
  JMP ac_parameters_loop_entry
ac_parameters_loop
  TAY                  ; Save next char
  LDA# $00
  STAZ INST_FLAG       ; Reset instruction flags after first iteration
  TYA                  ; Restore next char
ac_parameters_loop_entry
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS ac_line_loop     ; End of line
  CMP# "\""            ; Quoted string
  BNE ac_check_for_hex
  JSR read_char
  JSR emit_quoted
  JMP ac_parameters_loop
ac_check_for_hex
  CMP# "$"             ; 1 or 2 byte hex
  BNE ac_check_for_lsb
  JSR read_char
  JSR emit_hex
  JMP ac_parameters_loop
ac_check_for_lsb
  CMP# "<"             ; LSB of variable
  BNE ac_check_for_msb
  JSR read_char
  JSR emit_label_lsb
  JMP ac_parameters_loop
ac_check_for_msb
  CMP# ">"             ; MSB of variable
  BNE ac_check_for_relative
  JSR read_char
  JSR emit_label_msb
  JMP ac_parameters_loop
ac_check_for_relative
  TAY                  ; Save next char
  LDAZ INST_FLAG
  AND# INST_RELATIVE
  BEQ ac_check_for_byte
  TYA                  ; Restore next char
  JSR emit_label_relative
  JMP ac_parameters_loop
ac_check_for_byte
  LDAZ INST_FLAG
  AND# INST_BYTE
  BEQ ac_label
  TYA                  ; Restore next char
  JSR emit_label_byte
  JMP ac_parameters_loop
ac_label
  TYA                  ; Restore next char
  JSR emit_label       ; 2 byte variable
  JMP ac_parameters_loop


open_input
  TXA
  PHA
  LDA# $00
  JSR argv
  STAZ TABPL
  STXZ TABPH
  PLA
  TAX
  LDY# $FF
oi_loop
  INY
  LDAZ(),Y TABPL
  STA,Y TOKEN
  BNE oi_loop
  JMP push_file_stack ; tail call


; Entry point
start
  JSR argc
  CMP# $02
  BEQ s_args_ok
  JMP err_usage
s_args_ok
  JSR init_heap
  JSR select_label_hash_table
  JSR init_hash_table
  JSR file_stack_init

  LDA# $00
  STAZ CURR_FILE
  STAZ PASS            ; Bit 7 = 0 (pass 1)
  JSR open_input

  ; Open output file
  LDA# $01
  JSR argv
  JSR openout
  TAX

  JSR assemble_code

  LDA# $FF
  STAZ PASS            ; Bit 7 = 1 (pass 2)
  JSR open_input
  JSR assemble_code

  ; Close output file
  TXA
  JSR close

  BRK $00              ; Success


; Interrupt handler, entered upon BRK
interrupt
; Retrieve pointer to error code
  TSX
  SEC
  LDA,X $0102
  SBC# $01
  STAZ TABPL
  LDA,X $0103
  SBC# $00
  STAZ TABPH
; Retrieve error code and skip diagnostics if no error
  LDY# $00
  LDAZ(),Y TABPL
  BEQ i_done
; Save error code
  STAZ TEMP
; Print the "Error " message
  LDA# <msg_error
  STAZ TABPL
  LDA# >msg_error
  STAZ TABPH
  JSR show_message
; Print the error code in decimal
  LDAZ TEMP
  STAZ TO_DECIMAL_VALUE_L
  LDA# $00
  STAZ TO_DECIMAL_VALUE_H
  JSR show_decimal
; Print the current file if any
  JSR file_stack_empty
  BEQ i_file_done
; Print the " in file " message
  LDA# <msg_error_file
  STAZ TABPL
  LDA# >msg_error_file
  STAZ TABPH
  JSR show_message
; Print the filename
  CLC
  LDAZ FS_PL
  ADC# $03
  STAZ TABPL
  LDAZ FS_PH
  ADC# $00
  STAZ TABPH
  JSR show_message
i_file_done
; Print the " at line " messaage
  LDA# <msg_error_line
  STAZ TABPL
  LDA# >msg_error_line
  STAZ TABPH
  JSR show_message
; Print the current line in decimal
  LDAZ CURLINEL
  STAZ TO_DECIMAL_VALUE_L
  LDAZ CURLINEH
  STAZ TO_DECIMAL_VALUE_H
  JSR show_decimal
; Print the ": " message
  LDA# ":"
  JSR write_d
  LDA# " "
  JSR write_d
; Retrieve pointer to the error message and show it
  TSX
  LDA,X $0102
  STAZ TABPL
  LDA,X $0103
  STAZ TABPH
  JSR show_message
; Print the final newline
  LDA# "\n"
  JSR write_d
; Load the error code so that it is returned
  LDAZ TEMP
i_done
  JMP exit

msg_error
  DATA "Error " $00
msg_error_line
  DATA " at line " $00
msg_error_file
  DATA " in file " $00


; Show message to the error output
; On entry TABPL;TABPH points to the zero-terminated message
; On exit X is preserved
;         A, Y are not preserved
show_message
  LDY# $00
sm_loop
  LDAZ(),Y TABPL
  BEQ sm_done
  JSR write_d
  INY
  JMP sm_loop
sm_done
  RTS


; Show a decimal value to the error ouptut
; On entry TO_DECIMAL_VALUE_L;TO_DECIMAL_VALUE_H contains the value to show
; On exit X, Y are preserved
;         A is not preserved
;         Decimal number string stored at TO_DECIMAL_RESULT
show_decimal
  JSR to_decimal
  LDA# <TO_DECIMAL_RESULT
  STAZ TABPL
  LDA# >TO_DECIMAL_RESULT
  STAZ TABPH
  JMP show_message ; tail call


HEAP                   ; Heap goes after the program code


* = $FFFC
  DATA start           ; Reset vector
  DATA interrupt       ; Interrupt vector
