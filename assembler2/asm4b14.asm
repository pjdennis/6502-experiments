; Addresses
TOKEN      = $1D00      ; Buffer for the current token being read
LHASHTAB   = $1E00      ; Label hash table
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
CURR_GLOBAL_HEAP_L DATA $00 ; Heap address of current global label string
CURR_GLOBAL_HEAP_H DATA $00 ; "
DEBUG_FLAG  DATA $00 ; Non-zero if debug output enabled

  .code


; Include files
  .include inst14.asm.out   ; This goes first since the tables should start on a page boundary
  .include environment.asm
  .include common14.asm
FS_FILENAME   = TOKEN
FS_CURR_FILE  = CURR_FILE
FS_CURR_LINEL = CURLINEL
FS_CURR_LINEH = CURLINEH
  .include file_stack14.asm
  .include to_decimal14.asm


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
  BRK $0D "Usage <assembler> <input> <output> [debug]" $00

err_no_file
  BRK $0E "Attempt to read with no file open" $00

err_invalid_debug_arg
  BRK $10 "Invalid third argument (expected 'debug')" $00

err_no_global_for_local
  BRK $0F "No global label for local" $00


; Read next character from file stack
; On entry CURR_FILE contains the current file handle
;          FILE_STACK is not empty
; On exit A contains the character read
;         C is set if at end of all file data
;         CURR_FILE is potentially updated with a new file handle
read_char
  LDAZ CURR_FILE
  BEQ .no_file
  JSR read
  BCS .at_end_file
  RTS
.at_end_file
  JSR pop_file_stack
  LDAZ CURR_FILE
  BEQ .at_end_all
  JMP read_char          ; Recursive tail call
.at_end_all
  SEC
  RTS
.no_file
  JMP err_no_file


select_label_hash_table
  LDA# <LHASHTAB
  STAZ HTPL
  LDA# >LHASHTAB
  STAZ HTPH
  RTS


; Emit value (pass 2 only) and increment PC
; On entry A contains the byte to emit
;          X contains the file handle to write to
; On exit A, X, Y are preserved
; TODO: Consolidate the PASS and IN_ZEROPAGE flags so that emit can
;       do a single check instead of two for suppression of output
emit
  BITZ PASS
  BPL .incpc           ; Skip writing during pass 1
  BITZ IN_ZEROPAGE
  BMI .incpc           ; Skip writing when in zero page section
  JSR write
.incpc
  INCZ PCL
  BNE .done
  INCZ PCH
.done
  RTS


; Read and discard characters up to the end of the current line
; On entry A contains the next character
; On exit A contains "\n"
;         X, Y are preserved
skip_rest_of_line
.loop
  CMP# "\n"
  BEQ .done
  JSR read_char
  JMP .loop
.done
  RTS


; Read and discard space characters
; On entry A contains the next character
; On exit A contains the next character following the last space
;         X, Y are preserved
skip_spaces
.loop
  CMP# " "
  BNE .done
  JSR read_char
  JMP .loop
.done
  RTS


; Check whether the next character (in A) is NOT a token character
; On entry A contains the next character
; On exit Z is set if current character terminates the current token, unset otherwise
;         A, X, Y are preserved
compare_end_of_token
  CMP# " "
  BEQ .end
  CMP# "\n"
  BEQ .end
  CMP# ";"
.end
  RTS


; Checks for end of line and skips past if at end
; On entry A contains next character
; On exit C set if end of line, clear otherwise
;         A contains next character
;         X, Y are preserved
check_for_end_of_line
  CMP# ";"
  BEQ .end
  CMP# "\n"
  BEQ .done
  ; Not at end
  CLC
  RTS
.end
  JSR skip_rest_of_line
.done
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
.loop
  JSR compare_end_of_token
  BEQ .done
  STA,X TOKEN
  INX
  JSR read_char
  JMP .loop
.done
  TAY                  ; Save next char
  LDA# $00
  STA,X TOKEN
  TYA                  ; Restore next char
  LDXZ TEMP
  RTS


; Check if token is a local label and set IS_LOCAL_LABEL flag
; On entry TOKEN contains the token (may start with '.')
; On exit IS_LOCAL_LABEL set appropriately ($FF if local, $00 if global)
;         C = 1 if was local label, C = 0 if was global
;         TOKEN is NOT modified (no expansion)
;         A not preserved
;         X, Y are preserved
check_local_label
  LDA TOKEN
  CMP# "."
  BNE .not_local
  ; Local label - set flag
  LDA# $FF
  STAZ IS_LOCAL_LABEL
  ; Check if CURR_GLOBAL_HEAP is set (error check)
  LDAZ CURR_GLOBAL_HEAP_L
  ORAZ CURR_GLOBAL_HEAP_H
  BNE .have_global
  JMP err_no_global_for_local
.have_global
  SEC                  ; C=1 means was local
  RTS
.not_local
  LDA# $00
  STAZ IS_LOCAL_LABEL
  CLC                  ; C=0 means was global
  RTS


; Update CURR_GLOBAL_HEAP by looking up TOKEN in hash table
; Used in pass 2 to set the heap pointer for local label scope matching
; On entry TOKEN contains the global label name
;          IS_LOCAL_LABEL = 0 (global label)
; On exit CURR_GLOBAL_HEAP_L/H points to the token string on heap
;         CACHED_HASH is set (needed for subsequent local label lookups)
;         A, Y not preserved
;         X is preserved
update_global_heap_from_lookup
  JSR select_label_hash_table
  JSR find_in_hash       ; TABPL now points to token string
  JSR commit_cached_hash ; Commit hash since this is a non-assignment global
  ; After find_in_hash, TABPL points to token string (entry_start + 2)
  LDAZ TABPL
  STAZ CURR_GLOBAL_HEAP_L
  LDAZ TABPH
  STAZ CURR_GLOBAL_HEAP_H
  RTS


; Read a label, look up in the label hash table and return the associated value
; On entry A contains the first character of the label
; On exit HEX1 and HEX2 contains the MSB and LSB of the hash table value
;         A contains the next character following the token
;         X is preserved
;         Y is not preserved
; Raises 'Label not found' error if label is not found in hash table
read_and_find_existing_label
  JSR read_token
  PHA                  ; Save next char
  JSR check_local_label
  JSR select_label_hash_table
  JSR find_in_hash
  PLA                  ; Restore next char
  BCC .done            ; Label found
  BITZ PASS
  BMI .pass2
  LDY# $00
  STYZ HEX1
  STYZ HEX2
.done
  RTS
.pass2
  JMP err_label_not_found


; Convert hex character to associated value
; On entry, A contains a hex character A-Z|0-9
; On exit A contains the value (0-15)
;         X, Y are preserved
; Raises 'Invalid hex' error if input is not a valid hex character
convert_hex_character
  CMP# "A"
  BCC .numeric         ; < 'A'
  SBC# "A"             ; Carry already set
  CMP# $06
  BCC .alpha_ok
  JMP err_invalid_hex
.alpha_ok
  CLC
  ADC# $0A             ; ADC# 10
  RTS
.numeric
  SEC
  SBC# "0"
  CMP# $0A
  BCC .numeric_ok
  JMP err_invalid_hex
.numeric_ok
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
  BNE .second
  CLC                  ; No second byte so return C = 0
  RTS
.second
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
  BCC .one
  LDAZ HEX2
  JSR emit
.one
  LDAZ HEX1
  JSR emit
  TYA                       ; Restore next char
  RTS


; Attempt to read an assigned value
; On entry A contains the next character
; On exit C set if value read; clear otherwise
;         HEX2 and HEX1 contain the LSB and MSB of the value read
;         A contains the next character
;         X is preserved
;         Y is not preserved
; Raises 'Bad hex' error if non-hex characters were encountered
read_value
  JSR skip_spaces
  CMP# "="
  BEQ .value
  CLC                  ; Did not find value so return C = 0
  RTS
.value
  JSR read_char        ; Read the character after the "="
  JSR skip_spaces
  CMP# "$"
  BEQ .hex_value
  JSR read_and_find_existing_label
  SEC
  RTS
.hex_value
  JSR read_char
  JSR read_hex_byte_or_word
  BCS .done            ; 2 bytes were read
  ; 1 byte was read - shift into LSB position (HEX2)
  LDYZ HEX1
  STYZ HEX2
  LDY# $00
  STYZ HEX1
.done
  SEC
  RTS


; Fast forward the program counter
; On entry PCL;PCH contains the current program counter
;          HEX2;HEX1 contains the new PC value
; On exit
; Raises 'Cannot move PC backwards' error if attempting to move PC backwards
update_pc
  BITZ IN_ZEROPAGE
  BMI .no_fill
  BITZ STARTED
  BMI .started
  DECZ STARTED
  JMP .no_fill
.started
  LDAZ HEX1            ; High byte
  CMPZ PCH
  BCC .less
  BNE .notless
  LDAZ HEX2            ; Low byte
  CMPZ PCL
  BCC .less
.notless
  BITZ PASS
  BPL .no_fill         ; skip writing during pass 1
.loop
  LDAZ HEX1
  CMPZ PCH
  BNE .loop_not_done
  LDAZ HEX2
  CMPZ PCL
  BEQ .loop_done
.loop_not_done
  LDA# $00
  JSR write
  INCZ PCL
  BNE .loop
  INCZ PCH
  JMP .loop
.loop_done
  RTS
.less
  JMP err_cannot_move_pc_backwards
.no_fill
  LDAZ HEX2
  STAZ PCL
  LDAZ HEX1
  STAZ PCH
.done
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
;        'Bad hex' error if non-hex characters were encountered
capture_label
  JSR read_token
  TAY                       ; Save next char
  LDA TOKEN
  CMP# "*"
  BNE .normal_label
  ; Set PC
  TYA                       ; Restore next char
  JSR read_value
  BCS .pc_value_read
  JMP err_pc_value_expected
.pc_value_read
  JSR skip_rest_of_line
  ; No need to retain next char as caller
  ; goes straight to next line
  JSR update_pc
  SEC                       ; Indicate line is fully processed
  RTS
.normal_label
  BITZ PASS
  BPL .pass_1
  ; Pass 2 - don't capture label, but must track globals for local label scoping
  TYA
  PHA                       ; Save next char
  JSR check_local_label     ; Sets IS_LOCAL_LABEL, validates scope for locals
  ; Now continue with value reading
  PLA                       ; Restore next char
  JSR read_value
  BCS .has_equals_2         ; If = found, branch
  ; No = found - update global heap if this was not a local label
  PHA                       ; Save next char
  LDAZ IS_LOCAL_LABEL
  BNE .was_local_2          ; If local flag != 0, skip update
  JSR update_global_heap_from_lookup  ; Set CURR_GLOBAL_HEAP for local label lookups
.was_local_2
  PLA                       ; Restore next char
  JMP .skip_spaces_and_return_processed_flag
.has_equals_2
  JMP .skip_and_return_processed
.pass_1
  TYA
  PHA                       ; Save next char
  JSR check_local_label     ; Sets IS_LOCAL_LABEL, validates scope for locals
  ; Save MEMPL before hash_add (to calculate token address for global labels)
  LDAZ MEMPL
  PHA
  LDAZ MEMPH
  PHA
  ; Add key to hash table first (before read_value may overwrite TOKEN)
  JSR select_label_hash_table
  JSR hash_add
  BCS .duplicate_label
  ; Pop saved MEMPL to temporaries (needed for CURR_GLOBAL_HEAP calculation)
  PLA                       ; MEMPH
  STAZ HTTPH
  PLA                       ; MEMPL
  STAZ HTTPL
  ; Now read the value (TOKEN can be overwritten, but HTTPL/HTTPH preserved if no =)
  PLA                       ; Restore next char
  JSR read_value
  BCS .has_equals           ; If = found, branch
  ; No = found, use program counter
  PHA                       ; Save next char (before A is overwritten)
  LDAZ PCL
  STAZ HEX2
  LDAZ PCH
  STAZ HEX1
  JSR store_hash_value
  ; Update CURR_GLOBAL_HEAP and commit hash for non-local labels
  LDAZ IS_LOCAL_LABEL
  BNE .was_local_1          ; If local flag != 0, skip
  ; Compute token address (saved_MEMPL + 2) for global labels
  CLC
  LDAZ HTTPL
  ADC# $02                  ; Token starts 2 bytes after entry start (past next pointer)
  STAZ CURR_GLOBAL_HEAP_L
  LDAZ HTTPH
  ADC# $00
  STAZ CURR_GLOBAL_HEAP_H
  JSR commit_cached_hash    ; Commit hash for local label lookups
.was_local_1
  PLA                       ; Restore next char
  JMP .skip_spaces_and_return_processed_flag
.has_equals
  PHA                       ; Save next char
  JSR store_hash_value
  PLA                       ; Restore next char
  JMP .skip_and_return_processed
.skip_spaces_and_return_processed_flag
  JSR skip_spaces
  JMP check_for_end_of_line ; Tail call - returns with C set if at end of line
.skip_and_return_processed
  JSR skip_rest_of_line
  SEC                       ; Indicate line is fully processed
  ; No need to retain next char as caller
  ; goes straight to next line
  RTS

.duplicate_label
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
  JSR find_in_hash_instruction
  BCC .found
  JMP err_opcode_not_found
.found
  LDAZ HEX2
  STAZ INST_FLAG
  AND# INST_PSUEDO
  BNE .done            ; Not opcode (DATA command)
  ; Opcode
  LDAZ HEX1
  JSR emit
.done
  PLA                  ; Restore next char
  RTS


; Read and emit quoted ASCII
; On entry A countains the first character within quotes
; On exit A contains the next character after the closing quote
;         X, Y are preserved
; Raises 'Closing quote not found' error if closing quote not found on current line
emit_quoted
.loop
  CMP# "\n"
  BEQ .err_closing_quote
  CMP# "\""
  BEQ .done
  CMP# "\\"
  BNE .not_escaped
  JSR read_char
  CMP# "\n"
  BEQ .err_closing_quote
  CMP# "n"
  BNE .not_escaped
  LDA# "\n"            ; Escaped "n" is linefeed
.not_escaped
  JSR emit
  JSR read_char
  JMP .loop
.done
  JSR read_char        ; Done; read next char
  RTS
.err_closing_quote
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
  BPL .ok              ; Skip validation on pass 1
  LDAZ HEX1
  BEQ .ok
  JMP err_value_out_of_range
.ok
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
  BPL .ok              ; Skip calculations and validations on pass 1

  ; Calculate target - PC - 1
  CLC ; for the - 1
  LDAZ HEX2
  SBCZ PCL
  STAZ HEX2
  LDAZ HEX1
  SBCZ PCH

  CMP# $00
  BEQ .forward
  CMP# $FF
  BEQ .backward
  JMP err_branch_out_of_range

.forward
  LDAZ HEX2
  BPL .ok
  JMP err_branch_out_of_range

.backward
  LDAZ HEX2
  BMI .ok
  JMP err_branch_out_of_range

.ok
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
  BEQ .include
  ; Check for 'zeropage'
  LDA# <directive_zeropage
  STAZ TABPL
  LDA# >directive_zeropage
  STAZ TABPH
  JSR compare_token
  BEQ .zeropage
  ; Check for 'code'
  LDA# <directive_code
  STAZ TABPL
  LDA# >directive_code
  STAZ TABPH
  JSR compare_token
  BEQ .code
  ; Directive not recognized
  PLA                  ; Restore next char
  JMP err_unknown_directive
.include
  PLA                  ; Restore next char
  JSR skip_spaces
  JSR check_for_end_of_line
  BCC .get_name
  JMP err_filename_expected
.get_name
  JSR read_token
  JSR skip_rest_of_line
  JSR push_file_stack
  RTS
.zeropage
  BITZ IN_ZEROPAGE
  BMI .in_zeropage
  LDA# $FF
  STAZ IN_ZEROPAGE
  JSR swap_pc_with_save
.in_zeropage
  PLA                  ; Restore next char
  JSR skip_rest_of_line
  RTS
.code
  BITZ IN_ZEROPAGE
  BPL .in_code
  LDA# $00
  STAZ IN_ZEROPAGE
  JSR swap_pc_with_save
.in_code
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
;          X contains the file handle of the output file
; On exit X is preserved
;         A, Y are not preserved
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
  STAZ CURR_GLOBAL_HEAP_L ; Initialize global heap pointer (0 = no global yet)
  STAZ CURR_GLOBAL_HEAP_H ; "
  STAZ IS_LOCAL_LABEL  ; Initialize local label flag
.line_loop
  JSR read_char
  BCC .character_read
  RTS                  ; At end of input
.character_read
  INCZ CURLINEL
  BNE .line_incremented
  INCZ CURLINEH
.line_incremented
  JSR check_for_end_of_line
  BCS .line_loop
  CMP# " "
  BEQ .line_starts_with_space
  JSR capture_label
  BCC .check_for_opcode
  JMP .line_loop
.line_starts_with_space
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS .line_loop
.check_for_opcode
  CMP# "."
  BNE .opcode
; Directive
  JSR read_char
  JSR process_directive
  JMP .line_loop
.opcode
  ; Read mnemonic and emit opcode
  JSR emit_opcode
  JMP .parameters_loop_entry
.parameters_loop
  TAY                  ; Save next char
  LDA# $00
  STAZ INST_FLAG       ; Reset instruction flags after first iteration
  TYA                  ; Restore next char
.parameters_loop_entry
  JSR skip_spaces
  JSR check_for_end_of_line
  BCS .line_loop       ; End of line
  CMP# "\""            ; Quoted string
  BNE .check_for_hex
  JSR read_char
  JSR emit_quoted
  JMP .parameters_loop
.check_for_hex
  CMP# "$"             ; 1 or 2 byte hex
  BNE .check_for_lsb
  JSR read_char
  JSR emit_hex
  JMP .parameters_loop
.check_for_lsb
  CMP# "<"             ; LSB of variable
  BNE .check_for_msb
  JSR read_char
  JSR emit_label_lsb
  JMP .parameters_loop
.check_for_msb
  CMP# ">"             ; MSB of variable
  BNE .check_for_relative
  JSR read_char
  JSR emit_label_msb
  JMP .parameters_loop
.check_for_relative
  TAY                  ; Save next char
  LDAZ INST_FLAG
  AND# INST_RELATIVE
  BEQ .check_for_byte
  TYA                  ; Restore next char
  JSR emit_label_relative
  JMP .parameters_loop
.check_for_byte
  LDAZ INST_FLAG
  AND# INST_BYTE
  BEQ .label
  TYA                  ; Restore next char
  JSR emit_label_byte
  JMP .parameters_loop
.label
  TYA                  ; Restore next char
  JSR emit_label       ; 2 byte variable
  JMP .parameters_loop


; Opens the file with name from the first command line argument, pushing
; to the file stack
; On exit X is preserved
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
.loop
  INY
  LDAZ(),Y TABPL
  STA,Y TOKEN
  BNE .loop
  JMP push_file_stack ; tail call


; Check if string at TABPL;TABPH equals "debug"
; On exit C = 0 if equal, C = 1 if not equal
;         A, Y are not preserved
check_debug_string
  LDY# $00
.loop
  LDAZ(),Y TABPL
  CMP,Y str_debug
  BNE .not_equal
  CMP# $00
  BEQ .equal
  INY
  JMP .loop
.equal
  CLC
  RTS
.not_equal
  SEC
  RTS

str_debug
  DATA "debug" $00


; Entry point
start
  ; Initialize file stack early so interrupt handler works correctly
  JSR file_stack_init
  ; Initialize debug flag to 0
  LDA# $00
  STAZ DEBUG_FLAG
  ; Check argument count (must be 2 or 3)
  JSR argc
  CMP# $02
  BEQ .args_ok
  CMP# $03
  BEQ .check_debug_arg
  JMP err_usage
.check_debug_arg
  ; Third argument present - must be "debug"
  LDA# $02
  JSR argv
  STAZ TABPL
  STXZ TABPH
  JSR check_debug_string
  BCS .invalid_debug_arg
  ; Valid "debug" argument - set flag
  LDA# $FF
  STAZ DEBUG_FLAG
  JMP .args_ok
.invalid_debug_arg
  JMP err_invalid_debug_arg
.args_ok
  JSR init_heap
  JSR select_label_hash_table
  JSR init_hash_table

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

  ; Print heap usage if debug flag is set
  LDAZ DEBUG_FLAG
  BEQ .skip_debug_output
  LDA# <msg_heap_used
  STAZ TABPL
  LDA# >msg_heap_used
  STAZ TABPH
  JSR show_message
  ; Calculate heap used: MEMPL - HEAP
  SEC
  LDAZ MEMPL
  SBC# <HEAP
  STAZ TO_DECIMAL_VALUE_L
  LDAZ MEMPH
  SBC# >HEAP
  STAZ TO_DECIMAL_VALUE_H
  JSR show_decimal
  LDA# <msg_bytes
  STAZ TABPL
  LDA# >msg_bytes
  STAZ TABPH
  JSR show_message
.skip_debug_output

  BRK $00              ; Success


; Interrupt handler, entered upon BRK
interrupt
; Retrieve pointer to error code
  TSX
  INX
  INX
  SEC
  LDA,X $0100
  SBC# $01
  STAZ TABPL
  INX
  LDA,X $0100
  SBC# $00
  STAZ TABPH
; Retrieve error code and skip diagnostics if no error
  LDY# $00
  LDAZ(),Y TABPL
  BEQ .done
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
; Print the current file and line if any file is open
  JSR file_stack_empty
  BEQ .location_done
; Print the " in file " message
  LDA# <msg_error_file
  STAZ TABPL
  LDA# >msg_error_file
  STAZ TABPH
  JSR show_message
; Print the filename
  LDAZ FS_PL
  STAZ TABPL
  LDAZ FS_PH
  STAZ TABPH
  JSR show_message
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
.location_done
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
.done
  JMP exit

msg_error
  DATA "Error " $00
msg_error_line
  DATA " at line " $00
msg_error_file
  DATA " in file " $00
msg_heap_used
  DATA "Heap used: " $00
msg_bytes
  DATA " bytes\n" $00


; Show message to the error output
; On entry TABPL;TABPH points to the zero-terminated message
; On exit X is preserved
;         A, Y are not preserved
show_message
  LDY# $00
.loop
  LDAZ(),Y TABPL
  BEQ .done
  JSR write_d
  INY
  JMP .loop
.done
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
