; ============================================================================
; ASM22 - Self-Hosting 6502 Assembler
; ============================================================================
;
; ARCHITECTURE
;   Two-pass assembler with hash tables for labels/instructions/macros.
;   Pass 1: Collect labels and macro definitions, mark forward references.
;   Pass 2: Resolve all references and emit code.
;
; MEMORY LAYOUT
;   $0000-$00FF   Zero page variables
;   $0200-$03FF   Forward reference list (512 bytes)
;   $0400-$04FF   Label scope stack for macro expansions (256 bytes)
;   $0500-$05FF   Macro argument buffer (256 bytes)
;   $0600         TOKEN buffer (current token being parsed)
;   $0700         LHASHTAB - Label hash table
;   $2000+        Generated code, then heap (grows upward via MEMP16)
;   $F000         FILE_STACK - Include/memory source stack (grows downward via FS_P16)
;
; REGISTER CONVENTIONS
;   X - Output file handle (preserved across most function calls)
;   Y - General purpose indexing (often clobbered)
;   A - Accumulator (generally clobbered unless documented otherwise)
;
; KEY GLOBAL STATE
;   NEXT_CHAR     Lookahead character (last byte read by read_char)
;   TOKEN         Buffer holding current token being parsed
;   PASS          $00 = pass 1, $FF = pass 2
;   PC16          Current program counter (where code is being generated)
;   MEMP16        Heap pointer (grows upward from end of generated code)
;   FS_P16        File stack pointer (grows downward from FILE_STACK)
;
; PARSING MODEL
;   read_char advances input, stores result in both A and NEXT_CHAR
;   Token reading uses TOKEN buffer, writes null terminator
;   Single-character lookahead via NEXT_CHAR for parsing decisions
;
; MACRO SYSTEM
;   Macro definitions stored on heap with body and parameter names
;   Macro expansions use synthetic scope IDs (EXPANSION_ID16) for local labels
;   Parameters shadow global labels with same name during expansion
;   Recursion detected by walking scope stack (SCOPE_PTR16)
;
; MEMORY PROTECTION
;   Heap (MEMP16) and file stack (FS_P16) collision is detected
;   256-byte safety buffer maintained for indexed addressing (Y register 0-255)
;   err_out_of_memory raised when heap and stack would collide
;
; CODE ORGANIZATION
;   Functions organized in tiers by dependency level
;   Include files provide subsystems: hash tables, file stack, errors, etc.
;   Shared code with instgen22.asm via common22.asm
;
; ============================================================================

; Addresses
FWDREF_LIST     = $0200  ; Forward reference list (512 bytes, $0200-$03FF)
FWDREF_LIMIT    = FWDREF_LIST+$0200 ; Limit for forward reference list data
SCOPE_STACK     = $0400  ; Label scope stack for macro expansions (256 bytes, $0400-$04FF)
SCOPE_LIMIT     = SCOPE_STACK+$0100 ; Limit for scope stack
MACRO_ARG_BUF   = $0500  ; Temp buffer for macro args during expansion (256 bytes)
MACRO_ARG_BUF_LIMIT = MACRO_ARG_BUF+$0100 ; Limit for macro arg buffer
TOKEN           = $0600  ; Buffer for the current token being read
LHASHTAB        = $0700  ; Label hash table
IFDEF_DECISIONS = $0800  ; Buffer for .ifdef decisions (256 bytes)
*               = $2000  ; Code generates here
FILE_STACK      = $F000  ; File stack will grow down from 1 below here


  .zeropage

; Zero page locations
TEMP            .data $00   ; 1 byte
PC16            .data $0000 ; 2 byte program counter
HEX16           .data $0000 ; 2 byte hex value, also aliased as OPERAND16)
OPERAND16 = HEX16           ; Operand value - alias for HEX16
PASS            .data $00   ; 1 byte $00 = pass 1 $FF = pass 2
STARTED         .data $00   ; flag to indicate output has started
CURR_OUT_FILE   .data $00   ; Current output file (for closing on error)
IN_ZEROPAGE     .data $00   ; Flag indicating if in zero page section
PC_SAVE16       .data $0000 ; Save location for PC when switching sections
ADDR_MODE       .data $00   ; Current addressing mode
INST_PTR16      .data $0000 ; Pointer to instruction mode table entry
IS_FWDREF       .data $00   ; $FF if current label is forward ref (pass 1 only)
EXPR_ACCU16     .data $0000 ; Expression accumulator
EXPR_FWDREF     .data $00   ; Accumulated forward ref flag
COND_DEPTH      .data $00   ; Conditional assembly nesting depth
SKIP_DEPTH      .data $00   ; Depth where skipping started (0 = not skipping)
ARG_COUNT       .data $00   ; Total command line argument count
IN_MACRO_DEF    .data $00   ; Flag: currently capturing macro body ($FF = capturing)
MACRO_DEF_PTR16 .data $0000 ; Heap pointer where macro body is being stored
MACRO_ENTRY16   .data $0000 ; Original macro hash entry address (for recursion check)
IFDEF_INDEX     .data $00   ; Current index into IFDEF_DECISIONS buffer

  .ifdef enable_debug
DEBUG_FLAG      .data $00   ; Non-zero if debug output enabled
PASS_1_FWDREF16 .data $0000 ; Forward ref pointer after pass 1
SMALL_HEAP_FLAG .data $00   ; Non-zero if small_heap argument was passed
SHOW_MACROS     .data $00   ; Non-zero if captured macro definitions should be printed
MACRO_NAME_PTR16   .data $0000 ; Pointer to macro name (for show_captured_macros)
  .endif

  .code


; Include files
  .include out/inst22.asm.out   ; This goes first since the tables should start on a page boundary
  .include environment11.asm
  .include macros22.asm
  .include common22.asm
  .include label_scope22.asm
  .include errors22.asm
  .include fwdref22.asm
FS_FILENAME        = TOKEN
FS_POP_MEMORY_HOOK = pop_label_scope
  .ifdef enable_debug
FS_ERR_NO_FILE     = err_no_file
  .endif
  .include file_stack22.asm
read_char          = file_stack_read_char
NEXT_CHAR          = FS_NEXT_CHAR
CURR_LINE16        = FS_CURR_LINE16


; ============================================================================
; TIER 1: PRIMITIVES
; Basic operations with no dependencies on other functions
; ============================================================================

; Check whether the next character (in A) is NOT a token character
; On entry A contains the next character
; On exit Z is set if current character terminates the current token, unset otherwise
;         A, X, Y are preserved
compare_end_of_token
  CMP #' '
  BEQ .end
  CMP #'\n'
  BEQ .end
  CMP #';'
  BEQ .end
  CMP #','             ; Comma terminates token for indexed modes
  BEQ .end
  CMP #')'             ; Close paren terminates for indirect modes
  BEQ .end
  CMP #'+'             ; Plus terminates for expressions
  BEQ .end
  CMP #'-'             ; Minus terminates for expressions
  BEQ .end
  CMP #'<'             ; Less-than terminates for shift operators
  BEQ .end
  CMP #'>'             ; Greater-than terminates for shift operators
  BEQ .end
  CMP #':'             ; Colon terminates for optional label suffix
  BEQ .end
  CMP #'='             ; Equals terminates for label assignments
.end
  RTS


; Skip characters until token terminator
; On exit: A contains terminating character
skip_token
  JSR read_char
  JSR compare_end_of_token
  BNE skip_token
  RTS


; Convert hex character to associated value
; On entry, A contains a hex character A-Z|0-9
; On exit A contains the value (0-15)
;         X, Y are preserved
; Raises 'Invalid hex' error if input is not a valid hex character
convert_hex_character
  CMP #'A'
  BCS .alpha           ; >= 'A'
  ; Numeric path: '0'-'9' → 0-9
  SEC
  SBC #'0'
  CMP #'9'-'0'+$01     ; Check if result 0-9
  BCS .error           ; >= 10, invalid
  RTS
.alpha
  ; Alpha path: 'A'-'F' → 10-15
  SBC #'A'             ; Carry already set from CMP
  CMP #'F'-'A'+$01     ; Check if result 0-5
  BCS .error           ; >= 6, invalid
  ADC #'9'-'0'+$01     ; Add 10 (carry clear from CMP)
  RTS
.error
  JMP err_invalid_hex


; Swap PC16 with PC_SAVE16
; On exit A, Y are not preserved
;         X is preserved
swap_pc_with_save
  ; Swap PC16 low byte with save location
  LDA PC16
  LDY PC_SAVE16
  STY PC16
  STA PC_SAVE16
  ; Swap PC16 high byte with save location
  LDA PC16+$01
  LDY PC_SAVE16+$01
  STY PC16+$01
  STA PC_SAVE16+$01
  RTS


; ============================================================================
; TIER 2: CHARACTER I/O & SKIPPING
; File reading and character classification
; ============================================================================

; read_char is provided by file_stack22.asm

; Read and discard space characters
; On entry NEXT_CHAR contains the next character
; On exit A contains the next character following the last space
;         X, Y are preserved
skip_spaces
  LDA NEXT_CHAR
.loop
  CMP #' '
  BNE .done
  JSR read_char
  BCC .loop
.done
  RTS


; Read and discard characters up to the end of the current line
; On entry NEXT_CHAR contains the next character
; On exit A contains "\n"
;         X, Y are preserved
skip_rest_of_line
  LDA NEXT_CHAR
.loop
  CMP #'\n'
  BEQ .done
  JSR read_char
  BCC .loop
.done
  RTS


; Skips spaces and checks for end of line and skips past if at end
; On entry NEXT_CHAR contains next character
; On exit C set if end of line, clear otherwise
;         A contains next character
;         X, Y are preserved
check_for_end_of_line
  JSR skip_spaces
  CMP #';'
  BEQ .end
  CMP #'\n'
  BEQ .done
  ; Not at end
  CLC
  RTS
.end
  JSR skip_rest_of_line
.done
  SEC
  RTS


; ============================================================================
; TIER 3: TOKEN & HEX READING
; Token and hexadecimal value parsing
; ============================================================================

; Reads 1 byte (2 character) hex value
; On entry A contains first hex character
; On exit A contains 2 character value (0-255)
;         X, Y are preserved
;         TEMP is not preserved
; Raises 'Invalid hex' error if encountering non-hex characters
read_hex_byte
  JSR convert_hex_character
  ASL
  ASL
  ASL
  ASL
  STA TEMP
  JSR read_char
  JSR convert_hex_character
  ORA TEMP
  RTS


; Reads 1 or 2 byte (2 or 4 character) hex value
; On entry, A contains the first hex character
; On exit HEX16 contains the read value
;         C set if 2 bytes read clear if 1 byte read
;         X, Y are preserved
;         A is ot preserved
; Rasises 'Invalid hex' error if encountering non-hex characters
read_hex_byte_or_word
  JSR read_hex_byte    ; Read 2nd hex character and convert
  STA HEX16+$01
  JSR read_char        ; Read 3rd hex char or terminator
  JSR compare_end_of_token
  BNE .second
  LDA HEX16+$01        ; No second byte so move result and return C = 0
  STA HEX16
  LDA #$00
  STA HEX16+$01
  CLC
  RTS
.second
  JSR read_hex_byte    ; Read 4th hex char and convert
  STA HEX16
  JSR read_char        ; Read next char
  SEC                  ; Second byte so return C = 1
  RTS


; Reads token into TOKEN (zero terminated)
; On entry A contains first character of token
; On exit NEXT_CHAR contains next character after token
;         X is preserved
;         Y is not preserved
read_token
  STX TEMP
  LDX #$00
.loop
  JSR compare_end_of_token
  BEQ .done
  ; TOKEN buffer bounds check (conservative 127-char limit)
  STA TOKEN,X
  INX
  BMI .token_overflow
  JSR read_char
  BCC .loop
.done
  LDA #$00
  STA TOKEN,X
  LDX TEMP
  RTS
.token_overflow
  JMP err_token_too_long


; ============================================================================
; TIER 4: VALUE PARSING
; Parse values: hex, labels, character literals
; ============================================================================

; Parse character literal: 'x' or escape sequences
; On entry: A contains the opening quote character '
; On exit: A contains next character (for garbage checking)
;          OPERAND16 contains character value
;          X is preserved
;          Y is not preserved
; Raises 'Invalid character literal' error on malformed input
parse_char_literal
  JSR read_char        ; Skip opening quote
  CMP #'\''
  BEQ .char_invalid    ; Empty literal - error
  CMP #'\\'
  BEQ .char_escape
  CMP #'\n'
  BEQ .char_invalid    ; Newline without closing quote - error
  ; Regular character
  STA OPERAND16
  JMP .char_check_close
.char_escape
  ; Escape sequence: \n \\ \'
  JSR read_char
  CMP #'n'
  BNE .esc_not_n
  LDA #'\n'            ; Only \n needs value substitution
  BNE .esc_done        ; Always taken (\n = $0A != 0)
.esc_not_n
  ; For \\ and \', character is already in A
  CMP #'\\'
  BEQ .esc_done
  CMP #'\''
  BNE .char_invalid
.esc_done
  STA OPERAND16
.char_check_close
  JSR read_char        ; Should be closing quote
  CMP #'\''
  BNE .char_invalid
  LDA #$00
  STA OPERAND16+$01
  ; Read next char for garbage check
  JMP read_char        ; Tail call
.char_invalid
  JMP err_invalid_char_literal


; Check for the existance of an assigned value (read the equals sign)
; On entry NEXT_CHAR contains the next character
; On exit C set if value exists; clear otherwise
;         A contains the next character
;         X, Y are preserved
check_for_value
  JSR skip_spaces
  CMP #'='
  BEQ .value
  CLC                  ; Did not find value so return C = 0
  RTS
.value
  SEC                  ; Found value so return C = 1
  RTS


; Read a value
; On entry A contains the next character
; On exit HEX16 contains the value read
;         A contains the next character
;         X is preserved
;         Y is not preserved
; Raises 'Bad hex' error if non-hex characters were encountered
; Supports: $xx, $xxxx, label, <label, >label
read_value
  JSR read_char        ; Read the character after the "="
  JSR skip_spaces
  JSR parse_value      ; Returns value in OPERAND16 (aliased to HEX16)
  ; No copy needed - OPERAND16 is aliased to HEX16
  RTS


; Parse a term (single value): $12, $1234, 'x', label, <label, or >label
; On entry A contains first character
; On exit  NEXT_CHAR contains next character
;          OPERAND16 contains parsed value
;          IS_FWDREF set if bare label was forward ref (pass 1 only)
;          C=1 if bare label, C=0 otherwise
;          X is preserved
;          Y is not preserved
parse_term
  CMP #'$'
  BEQ .hex
  CMP #'\''
  BEQ .char_literal
  ; Otherwise: bare label - needs forward ref tracking
  JSR read_token       ; Next char now in NEXT_CHAR
  ; Look up the token
  JSR check_local_label
  ; If in macro expansion with non-local label, try local hash first
  ; (parameters shadow globals with the same name)
  LDA LABEL_TYPE
  BNE .do_lookup           ; Already a .local label, use normal path
  LDA SCOPE_DEPTH
  BEQ .do_lookup           ; Not in macro, use normal path
  ; In macro with non-local label - try macro-local hash first for parameters
  LDA #LABEL_TYPE_MACRO
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR find_in_hash
  BCC .label_found         ; Found as parameter
  ; Not a parameter - restore to global lookup
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
.do_lookup
  JSR select_label_hash_table
  JSR find_in_hash
  BCC .label_found
  ; Label not found - check pass
  BIT PASS
  BMI .label_not_found_pass2
  ; Pass 1 - forward reference: use zero values
  LDY #$FF
  STY IS_FWDREF        ; Mark as forward reference
  LDY #$00
  STY HEX16
  STY HEX16+$01
  BEQ .label_store     ; Always taken
.label_not_found_pass2
  JMP err_label_not_found
.label_found
  ; Label found - clear forward ref flag
  LDA #$00
  STA IS_FWDREF
.label_store
  ; OPERAND16 already set (aliased to HEX16)
  SEC                  ; Signal 2-byte value (from bare label)
  RTS
.hex
  JSR read_char        ; Skip $
  JMP read_hex_byte_or_word  ; Tail call; Stores in HEX16
.char_literal
  JSR parse_char_literal
  ; Result in OPERAND16
  CLC                  ; Signal 1-byte value (character)
  RTS


; Parse a value (expression with optional byte selector prefix)
; On entry: A contains first character
; On exit: NEXT_CHAR contains next character
;          OPERAND16 contains result
;          IS_FWDREF set if expression contains forward ref (NOT set for byte selectors)
;          C=0 if first term is a single byte or C=1 if first term is two bytes
parse_value
  CMP #'<'
  BEQ .low_byte_selector
  CMP #'>'
  BEQ .high_byte_selector
  JMP parse_expression

.low_byte_selector
  JSR read_char        ; Skip '<'
  JSR parse_expression ; Next char now in NEXT_CHAR
  ; Apply low byte: keep OPERAND16, zero OPERAND16+$01
  LDA #$00
  STA OPERAND16+$01
  STA IS_FWDREF        ; Byte selectors don't set fwdref (always 1 byte result)
  CLC                  ; Byte selector = C=0 (1 byte)
  RTS

.high_byte_selector
  JSR read_char        ; Skip '>'
  JSR parse_expression ; Next char now in NEXT_CHAR
  ; Apply high byte: shift OPERAND16 right by 8 bits
  LDA OPERAND16+$01
  STA OPERAND16
  LDA #$00
  STA OPERAND16+$01
  STA IS_FWDREF        ; Byte selectors don't set fwdref (always 1 byte result)
  CLC                  ; Byte selector = C=0 (1 byte)
  RTS


; Parse term with optional byte selector prefix
; Unlike parse_value, does NOT handle chained operators - only byte selectors
; Used for shift counts to ensure left-to-right evaluation of shifts
; On entry: A contains first character
; On exit: NEXT_CHAR contains next character
;          OPERAND16 contains result
;          IS_FWDREF set if term is forward ref (NOT set for byte selectors)
;          C=1 if bare label, C=0 otherwise
parse_term_with_selector
  CMP #'<'
  BEQ .low_byte_selector
  CMP #'>'
  BEQ .high_byte_selector
  JMP parse_term

.low_byte_selector
  JSR read_char        ; Skip '<'
  JSR parse_term       ; Next char now in NEXT_CHAR
  ; Apply low byte: keep OPERAND16, zero OPERAND16+$01
  LDA #$00
  STA OPERAND16+$01
  STA IS_FWDREF        ; Byte selectors don't set fwdref
  CLC
  RTS

.high_byte_selector
  JSR read_char        ; Skip '>'
  JSR parse_term       ; Next char now in NEXT_CHAR
  ; Apply high byte: shift OPERAND16 right by 8 bits
  LDA OPERAND16+$01
  STA OPERAND16
  LDA #$00
  STA OPERAND16+$01
  STA IS_FWDREF        ; Byte selectors don't set fwdref
  CLC
  RTS


; Parse expression: term [+|-|<<|>> term]*
; On entry: A contains first character
; On exit: NEXT_CHAR contains next character
;          OPERAND16 contains result
;          IS_FWDREF set if any term is forward ref
;          C=1 if 2-byte value (bare label or $xxxx), C=0 if 1-byte ($xx, 'c')
;          (Carry from first term - used by .data to decide emit size)
parse_expression
  JSR parse_term       ; Parse first term, next char in NEXT_CHAR
  PHP ; Save carry flag

  ; Save IS_FWDREF from first term
  LDA IS_FWDREF
  STA EXPR_FWDREF

.loop
  LDA NEXT_CHAR
  CMP #'+'
  BEQ .add_op
  CMP #'-'
  BEQ .sub_op
  CMP #'<'
  BEQ .check_left_shift
  CMP #'>'
  BEQ .check_right_shift

  ; No more operators - restore and return
  LDA EXPR_FWDREF
  STA IS_FWDREF
  PLP ; Restore carry flag from first term
  RTS

.add_op
  ; Save current accumulator
  CP16 OPERAND16 EXPR_ACCU16

  ; Parse next term (skip '+' first)
  JSR read_char        ; Skip '+'
  JSR parse_term_with_selector  ; Next char in NEXT_CHAR

  ; Accumulate forward ref flag
  LDA IS_FWDREF
  ORA EXPR_FWDREF
  STA EXPR_FWDREF

  ; Add: accumulator + OPERAND → OPERAND
  CLC
  ADD16 EXPR_ACCU16 OPERAND16 OPERAND16
  JMP .loop

.sub_op
  ; Save current accumulator
  CP16 OPERAND16 EXPR_ACCU16

  ; Parse next term (skip '-' first)
  JSR read_char        ; Skip '-'
  JSR parse_term_with_selector  ; Next char in NEXT_CHAR

  ; Accumulate forward ref flag
  LDA IS_FWDREF
  ORA EXPR_FWDREF
  STA EXPR_FWDREF

  ; Subtract: accumulator - OPERAND → OPERAND
  SEC
  SUB16 EXPR_ACCU16 OPERAND16 OPERAND16
  JMP .loop

.check_left_shift
  ; Read next char to confirm second '<'
  JSR read_char
  CMP #'<'
  BEQ .left_shift_op
  JMP err_expected_shift    ; Single '<' in middle of expression is error

.check_right_shift
  ; Read next char to confirm second '>'
  JSR read_char
  CMP #'>'
  BEQ .right_shift_op
  JMP err_expected_shift    ; Single '>' in middle of expression is error

.left_shift_op
  ; Save current operand to EXPR_ACCU
  CP16 OPERAND16 EXPR_ACCU16

  ; Parse shift count (use parse_term_with_selector to support byte selectors like <<<)
  JSR read_char        ; Read char after second '<'
  JSR parse_term_with_selector  ; Next char in NEXT_CHAR

  ; Accumulate forward ref flag
  LDA IS_FWDREF
  ORA EXPR_FWDREF
  STA EXPR_FWDREF

  ; Check if shift count >= 16 (result will be 0)
  LDA OPERAND16+$01
  BNE .shift_zero     ; High byte != 0 means shift >= 256
  LDA OPERAND16
  CMP #$10
  BCS .shift_zero     ; Low byte >= 16 means shift >= 16
  TAY                      ; Transfer shift count to Y

  ; Restore value to shift from EXPR_ACCU
  CP16 EXPR_ACCU16 OPERAND16

  ; Perform left shift
.left_shift_loop
  DEY
  BMI .shift_done
  ASL16 OPERAND16
  JMP .left_shift_loop

.right_shift_op
  ; Save current operand to EXPR_ACCU
  CP16 OPERAND16 EXPR_ACCU16

  ; Parse shift count (use parse_term_with_selector to support byte selectors like >>>)
  JSR read_char        ; Read char after second '>'
  JSR parse_term_with_selector  ; Next char in NEXT_CHAR

  ; Accumulate forward ref flag
  LDA IS_FWDREF
  ORA EXPR_FWDREF
  STA EXPR_FWDREF

  ; Check if shift count >= 16 (result will be 0)
  LDA OPERAND16+$01
  BNE .shift_zero    ; High byte != 0 means shift >= 256
  LDA OPERAND16
  CMP #$10
  BCS .shift_zero    ; Low byte >= 16 means shift >= 16
  TAY                      ; Transfer shift count to Y

  ; Restore value to shift from EXPR_ACCU
  CP16 EXPR_ACCU16 OPERAND16

  ; Perform right shift (logical/unsigned)
.right_shift_loop
  DEY
  BMI .shift_done
  LSR16 OPERAND16
  JMP .right_shift_loop

.shift_zero
  ; Shift >= 16, result is 0
  LDA #$00
  STA_LH16 OPERAND16

.shift_done
  JMP .loop


; ============================================================================
; TIER 5: LABEL MANAGEMENT & HASH TABLE
; Label classification, lookup, and definition
; ============================================================================

; Check if token is a local label and set LABEL_TYPE flag
; On entry TOKEN contains the token (may start with '.')
; On exit LABEL_TYPE set appropriately:
;         - LABEL_TYPE_GLOBAL if global label
;         - LABEL_TYPE_LOCAL if local label under global (outside macro)
;         - LABEL_TYPE_MACRO if local label in macro expansion
;         TOKEN is NOT modified (no expansion)
;         A not preserved
;         X, Y are preserved
check_local_label
  LDA TOKEN
  CMP #'.'
  BNE .not_local
  ; Local label - Check if LABEL_SCOPE16 is set (error check)
  LDA LABEL_SCOPE16
  ORA LABEL_SCOPE16+$01
  BNE .have_scope
  JMP err_no_global_for_local
.have_scope
  ; Determine if in macro context by checking scope depth
  LDA SCOPE_DEPTH
  BNE .in_macro
  ; Not in macro - use LOCAL type
  LDA #LABEL_TYPE_LOCAL
  STA LABEL_TYPE
  RTS
.in_macro
  ; In macro expansion - use MACRO type
  LDA #LABEL_TYPE_MACRO
  STA LABEL_TYPE
  RTS
.not_local
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  RTS


select_label_hash_table
  SET16 LHASHTAB HTP16
  RTS


; Update LABEL_SCOPE16 by looking up TOKEN in hash table
; Used in pass 2 to set the scope for local label matching
; On entry TOKEN contains the global label name
;          LABEL_TYPE = 0 (global label)
; On exit LABEL_SCOPE16 points to the token string on heap
;         CACHED_HASH is set (needed for subsequent local label lookups)
;         A, Y not preserved
;         X is preserved
update_label_scope_from_lookup
  JSR select_label_hash_table
  JSR find_in_hash       ; TABP16 now points to token string
  JSR commit_cached_hash ; Commit hash since this is a non-assignment global
  ; After find_in_hash, TABP16 points to token string (entry_start + 2)
  CP16 TABP16 LABEL_SCOPE16
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
  CMP #'*'
  BEQ .set_pc
  JSR read_token            ; Next char in NEXT_CHAR
  LDA NEXT_CHAR             ; Check if terminated by colon
  CMP #':'
  BNE .no_colon
  JSR read_char             ; Skip past colon, update NEXT_CHAR
.no_colon
  ; Normal label
  BIT PASS
  BPL .pass_1
  ; Pass 2 - don't capture label, but must track globals for local label scoping
  ; NEXT_CHAR has the next char from read_token
  JSR check_local_label     ; Sets LABEL_TYPE, validates scope for locals
  ; Now continue with value reading
  JSR check_for_value
  BCS .has_equals_2         ; If = found, branch
  ; No = found - update global heap if this was not a local label
  ; check_for_value updated NEXT_CHAR if it called read_char
  LDA LABEL_TYPE
  BNE .was_local_2          ; If local flag != 0, skip update
  JSR update_label_scope_from_lookup  ; Set LABEL_SCOPE16 for local label lookups
.was_local_2
  JMP .skip_spaces_and_return_processed_flag
.set_pc
  ; Set PC
  JSR read_char             ; Skip the *
  JSR check_for_value
  BCS .pc_value_present
  JMP err_pc_value_expected
.pc_value_present
  JSR read_value
  JSR skip_rest_of_line
  JSR update_pc
  SEC                       ; Indicate line is fully processed
  RTS
.has_equals_2
  JSR read_value
  JMP .skip_and_return_processed
.pass_1
  ; NEXT_CHAR has the next char from read_token
  JSR check_local_label     ; Sets LABEL_TYPE, validates scope for locals
  ; Add key to hash table first (before read_value may overwrite TOKEN)
  JSR select_label_hash_table
  JSR hash_add
  BCS .duplicate_label
  ; Now read the value (TOKEN can be overwritten, but HTTPL/HTTPH preserved if no =)
  JSR check_for_value
  BCS .has_equals           ; If = found, branch
  ; No = found, save global label and use program counter
  ; Update LABEL_SCOPE16 and commit hash for non-local labels
  LDA LABEL_TYPE
  BNE .was_local_1          ; If local flag != 0, skip
  ; Store the address of the current global label
  CP16 TABP16 LABEL_SCOPE16
  JSR commit_cached_hash    ; Commit hash for local label lookups
.was_local_1
  ; Store current program counter as the hash value into HEX16
  CP16 PC16 HEX16
  JSR store_hash_value
  JMP .skip_spaces_and_return_processed_flag
.has_equals
  JSR read_value            ; Read the value after the equals, next char in NEXT_CHAR
  JSR store_hash_value
  JMP .skip_and_return_processed
.skip_spaces_and_return_processed_flag
  JMP check_for_end_of_line ; Tail call - returns with C set if at end of line
.skip_and_return_processed
  JSR skip_rest_of_line
  SEC                       ; Indicate line is fully processed
  ; No need to retain next char as caller
  ; goes straight to next line
  RTS
.duplicate_label
  JMP err_duplicate_label


; ============================================================================
; TIER 6: PC MANAGEMENT
; Program counter manipulation and byte emission
; ============================================================================

; Emit value (pass 2 only) and increment PC
; On entry A contains the byte to emit
;          X contains the file handle to write to
; On exit A, X, Y are preserved
; TODO: Consolidate the PASS and IN_ZEROPAGE flags so that emit can
;       do a single check instead of two for suppression of output
emit
  BIT IN_ZEROPAGE
  BMI .in_zeropage     ; If in zero page, handle separately
  ; Not in zero page - proceed with normal emit logic
  INC16 PC16
  BIT PASS
  BPL .skip            ; Skip writing during pass 1
  JMP write            ; Tail call
.skip
  RTS
.in_zeropage
  ; In zero page - check for overflow BEFORE incrementing
  ; If high byte already non-zero, we've already overflowed past $FF
  LDA PC16+$01
  BNE .overflow
  INC16 PC16           ; Safe to increment
  RTS                  ; No writing in zeropage
.overflow
  JMP err_zeropage_overflow


; Fast forward the program counter
; On entry PC16 contains the current program counter
;          HEX16 contains the new PC value
; On exit
; Raises 'Cannot move PC backwards' error if attempting to move PC backwards
update_pc
  BIT IN_ZEROPAGE
  BMI .no_fill
  BIT STARTED
  BMI .started
  DEC STARTED
  BNE .no_fill        ; Always taken
.started
  CMP16 HEX16 PC16
  BCC .less           ; HEX16 < PC16: error
  BIT PASS
  BPL .no_fill        ; skip writing during pass 1
.loop
  CMP16 HEX16 PC16
  BEQ .loop_done
  LDA #$00
  JSR write
  INC PC16
  BNE .loop
  INC PC16+$01
  BNE .loop           ; Always taken
.loop_done
  RTS
.less
  JMP err_cannot_move_pc_backwards
.no_fill
  CP16 HEX16 PC16
.done
  RTS


; ============================================================================
; TIER 7: INSTRUCTION LOOKUP & OPCODE
; Mnemonic lookup and opcode finding
; ============================================================================

; Look up mnemonic and save pointer to mode:opcode data
; On entry A contains the first character of the mnemonic
; On exit NEXT_CHAR contains the next character
;         INST_PTR16 points to mode:opcode data (past mnemonic)
;         X, Y are not preserved
; Raises 'Opcode not found' error if mnemonic is not found
lookup_mnemonic
  JSR read_token       ; Next char in NEXT_CHAR
  JSR select_instruction_hash_table
  JSR find_in_hash_instruction
  BCC .found
  JMP err_opcode_not_found
.found
  ; TABP16 + Y points to mode:opcode data or macro sentinel
  ; Check for macro sentinel (MODE_MACRO)
  LDA (TABP16),Y
  CMP #MODE_MACRO
  BNE .is_instruction
  ; It's a macro - compute pointer to macro data and expand
  ; MACRO_DEF_PTR = TABP16 + Y + 1 (skip past MODE_MACRO to point at args)
  TYA
  SEC ; +1
  ADDA16 TABP16 MACRO_DEF_PTR16
  ; Don't skip rest of line - expand_macro will parse arguments
  PLA                   ; Pop return address (we're not returning)
  PLA
  JMP expand_macro
.is_instruction
  ; Calculate INST_PTR = TABP16 + Y
  TYA
  CLC
  ADDA16 TABP16 INST_PTR16
  RTS


; Find opcode for addressing mode in mode:opcode list
; On entry INST_PTR16 points to mode:opcode data
;          ADDR_MODE contains the addressing mode to find
; On exit C = 0 if found, A contains opcode
;         C = 1 if not found
;         X is preserved
;         Y is not preserved
find_opcode_for_mode
  LDY #$00
.loop
  LDA (INST_PTR16),Y  ; Get mode byte
  CMP #MODE_END
  BEQ .not_found      ; End of list, mode not found
  CMP ADDR_MODE
  BEQ .found
  ; Not this mode, skip to next pair
  INY
  INY
  BNE .loop           ; Always taken
.found
  INY
  LDA (INST_PTR16),Y  ; Get opcode byte
  CLC
  RTS
.not_found
  SEC
  RTS


; Check if current instruction is a branch (supports MODE_REL)
; On entry INST_PTR16 points to mode:opcode data
; On exit C = 0 if branch, C = 1 if not branch
;         A, Y not preserved, X preserved
check_if_branch
  LDY #$00
.loop
  LDA (INST_PTR16),Y
  CMP #$FF
  BEQ .not_branch
  CMP #MODE_REL
  BEQ .is_branch
  INY
  INY
  JMP .loop
.is_branch
  CLC
  RTS
.not_branch
  SEC
  RTS


; ============================================================================
; TIER 8: INSTRUCTION EMISSION
; Emit instructions with operands
; ============================================================================

; Emit instruction based on addressing mode
; On entry INST_PTR16 points to mode:opcode data
;          ADDR_MODE contains the addressing mode
;          OPERAND16 contains operand value (if applicable)
; On exit X is preserved
;         A, Y are not preserved
; Raises error if addressing mode is not valid for this instruction
emit_instruction
  ; Find opcode for this addressing mode
  JSR find_opcode_for_mode
  BCS .invalid_mode
  ; Emit the opcode
  JSR emit
  ; Now emit operand(s) based on mode
  LDA ADDR_MODE
  CMP #MODE_NONE
  BEQ .done            ; No operand for implied mode
  CMP #MODE_REL
  BEQ .emit_relative   ; Relative needs special handling
  ; Check if 1-byte or 2-byte operand
  CMP #MODE_IMM
  BEQ .one_byte
  CMP #MODE_ZP
  BEQ .one_byte
  CMP #MODE_ZPX
  BEQ .one_byte
  CMP #MODE_ZPY
  BEQ .one_byte
  CMP #MODE_INDX
  BEQ .one_byte
  CMP #MODE_INDY
  BEQ .one_byte
  ; 2-byte operand (absolute modes)
  LDA OPERAND16
  JSR emit
  LDA OPERAND16+$01
  JSR emit
.done
  RTS
.one_byte
  ; Validate operand <= $FF
  BIT PASS
  BPL .one_byte_ok       ; Skip validation on pass 1
  LDA OPERAND16+$01
  BNE .one_byte_error
.one_byte_ok
  LDA OPERAND16
  JSR emit
  RTS
.one_byte_error
  JMP err_value_out_of_range
.emit_relative
  ; Calculate relative offset: target - PC - 1
  BIT PASS
  BPL .emit_relative_pass1  ; Skip validation on pass 1
  CLC                  ; For the - 1
  LDA OPERAND16
  SBC PC16
  STA OPERAND16
  LDA OPERAND16+$01
  SBC PC16+$01
  ; Check if within range
  CMP #$00
  BEQ .forward
  CMP #$FF
  BEQ .backward
  JMP err_branch_out_of_range
.forward
  LDA OPERAND16
  BPL .emit_relative_ok
  JMP err_branch_out_of_range
.backward
  LDA OPERAND16
  BMI .emit_relative_ok
  JMP err_branch_out_of_range
.emit_relative_pass1
  LDA OPERAND16
.emit_relative_ok
  JSR emit
  RTS
.invalid_mode
  JMP err_invalid_addressing_mode


; Checks mode availability, value size, and forward reference forcing
; On entry: ADDR_MODE set to ZP variant (MODE_ZP, MODE_ZPX, or MODE_ZPY)
;           INST_PTR16 points to instruction's mode:opcode data
;           OPERAND16 contains the operand value
;           IS_FWDREF set if operand is forward reference (pass 1)
;           PASS indicates current pass
; On exit: C=1 if must use ABS variant, C=0 if can use ZP variant
;          In pass 1 with forward ref: adds PC to forward ref list
;          In pass 2: consumes forward ref list entry if present
;          A, Y not preserved, X preserved
handle_fwdref_mode
  JSR find_opcode_for_mode
  BCS .use_abs             ; No ZP mode available, must use ABS
  ; Check forward reference forcing (must be done before value check
  ; to properly consume forward ref entries in pass 2)
  BIT PASS
  BMI .pass2
  ; Pass 1 - check if this is a forward reference
  BIT IS_FWDREF
  BPL .check_value         ; Not a forward ref, check value size
  ; Forward ref in pass 1 - add to list, return C=1 (use ABS)
  JSR add_forward_ref
  SEC
  RTS
.pass2
  ; Pass 2 - check the forward ref list
  JSR check_forward_ref    ; Returns C=1 if in list, C=0 if not
  BCS .use_abs             ; Was in list (forced to ABS), return C=1
.check_value
  ; Check if value requires absolute addressing (>= $100)
  LDA OPERAND16+$01
  BNE .use_abs             ; Value >= $100, must use ABS
  ; Can use ZP
  CLC
  RTS
.use_abs
  SEC
  RTS


; ============================================================================
; TIER 9: OPERAND PARSING & EMISSION
; Parse operands and emit complete instructions
; ============================================================================

; Parse operand and emit instruction
; On entry A contains the next character after mnemonic
;          INST_PTR16 points to mode:opcode data
; On exit flow continues to .line_loop
;         A, X, Y are not preserved
parse_operand_and_emit
  JSR check_for_end_of_line
  BCS .implied_mode    ; No operand = implied mode
  ; Check operand format to determine mode
  CMP #'#'
  BNE .not_imm
  JMP .immediate_mode
.not_imm
  CMP #'('
  BNE .not_ind
  JMP .indirect_mode
.not_ind
  ; Everything else: $xx, $xxxx, or label
  ; All handled uniformly by parse_term + mode selection
  JMP .value_operand

.implied_mode
  ; Next char in NEXT_CHAR (newline or semicolon)
  LDA #MODE_NONE
  STA ADDR_MODE
  LDA #$00
  STA_LH16 OPERAND16
  JMP emit_instruction ; Tail call

.immediate_mode
  ; #$xx or #<label or #>label or #label or #'x'
  LDA #MODE_IMM
  STA ADDR_MODE
  JSR read_char        ; Skip #
  JSR parse_value      ; Returns next char in A, OPERAND16 set
  JMP emit_instruction ; Tail call

.indirect_mode
  ; ($xx),Y - indirect indexed Y (1-byte operand)
  ; ($xx,X) - indirect indexed X (1-byte operand)
  ; ($xxxx) - indirect absolute for JMP (2-byte operand)
  JSR read_char        ; Skip (
  ; Parse value ($xx, <label, >label, or label)
  JSR parse_value      ; OPERAND16 set, next char in NEXT_CHAR
  ; Check suffix to determine addressing mode
  LDA NEXT_CHAR        ; Load next char (should be ) or ,)
  CMP #','
  BEQ .indirect_x
  ; Must be )
  CMP #')'
  BNE .ind_err_operand
  JSR read_char        ; Read char after )
  CMP #','
  BNE .ind_no_suffix
  JSR read_char        ; Should be Y
  CMP #'Y'
  BNE .ind_err
  LDA #MODE_INDY
  STA ADDR_MODE
  JSR read_char        ; Read char after Y for garbage check
  JMP emit_instruction ; Tail call
.indirect_x
  JSR read_char        ; Should be X
  CMP #'X'
  BNE .ind_err
  JSR read_char        ; Should be )
  CMP #')'
  BNE .ind_err
  LDA #MODE_INDX
  STA ADDR_MODE
  JSR read_char        ; Read char after ) for garbage check
  JMP emit_instruction ; Tail call
.ind_no_suffix
  ; Just ($xxxx) - JMP indirect mode (must be 2-byte operand)
  ; Next char in NEXT_CHAR (after ))
  LDA #MODE_IND
  STA ADDR_MODE
  JMP emit_instruction ; Tail call
.ind_err
  JMP err_invalid_addressing_mode
.ind_err_operand
  JMP err_invalid_operand

.value_operand
  ; Parse value: $xx, $xxxx, or label
  ; All handled uniformly with appropriate mode selection
  JSR parse_value      ; Returns C=1 for bare label, OPERAND16 set, IS_FWDREF set, next char in NEXT_CHAR
  ; Check if this is a branch instruction
  JSR check_if_branch
  BCS .not_branch
  JMP .label_is_branch
.not_branch
  ; Not a branch - check for indexed mode
  LDA NEXT_CHAR        ; Next char (might be comma)
  CMP #','
  BNE .label_no_index
  ; Has index suffix - read X or Y
  JSR read_char
  CMP #'X'
  BEQ .label_x_index
  CMP #'Y'
  BEQ .label_y_index
  JMP err_invalid_addressing_mode
.label_x_index
  JSR read_char            ; Read char after X for garbage check, stores in NEXT_CHAR
  LDA #MODE_ZPX
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .label_use_absx      ; Must use ABSX
  ; Use ZPX mode
  JMP emit_instruction
.label_use_absx
  LDA #MODE_ABSX
  STA ADDR_MODE
  JMP emit_instruction
.label_y_index
  JSR read_char            ; Read char after Y for garbage check, stores in NEXT_CHAR
  LDA #MODE_ZPY
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .label_use_absy      ; Must use ABSY
  ; Use ZPY mode
  JMP emit_instruction
.label_use_absy
  LDA #MODE_ABSY
  STA ADDR_MODE
  JMP emit_instruction
.label_no_index
  ; Next char in NEXT_CHAR
  LDA #MODE_ZP
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .label_use_abs       ; Must use ABS
  ; Use ZP mode
  JMP emit_instruction
.label_use_abs
  LDA #MODE_ABS
  STA ADDR_MODE
  JMP emit_instruction

.label_is_branch
  LDA #MODE_REL
  STA ADDR_MODE
  JMP emit_instruction


; Read and emit quoted ASCII
; On entry A contains the first character within quotes
; On exit A contains the next character after the closing quote
;         X, Y are preserved
; Raises 'Closing quote not found' error if closing quote not found on current line
emit_quoted
.loop
  CMP #'\n'
  BEQ .err_closing_quote
  CMP #'"'
  BEQ .done
  CMP #'\\'
  BNE .not_escaped
  JSR read_char
  CMP #'\n'
  BEQ .err_closing_quote
  CMP #'n'
  BNE .not_escaped
  LDA #'\n'            ; Escaped "n" is linefeed
.not_escaped
  JSR emit
  JSR read_char
  BCC .loop
.err_closing_quote
  JMP err_closing_quote_not_found
.done
  JSR read_char        ; Done; read next char
  RTS


; ============================================================================
; TIER 10: DIRECTIVE PROCESSING
; Handle assembler directives (.include, .data, etc.)
; ============================================================================

; On entry, A contains the first character of the directive
process_directive
  JSR read_token       ; Next char in NEXT_CHAR
  ; Reset LABEL_TYPE for directive string comparisons
  ; (compare_token checks LABEL_TYPE, must be GLOBAL for non-escape strings)
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  ; Check for 'include'
  SET16 directive_include TABP16
  JSR compare_token
  BEQ .include
  ; Check for 'zeropage'
  SET16 directive_zeropage TABP16
  JSR compare_token
  BEQ .zeropage
  ; Check for 'code'
  SET16 directive_code TABP16
  JSR compare_token
  BEQ .code
  ; Check for 'data'
  SET16 directive_data TABP16
  JSR compare_token
  BEQ .data
  JSR process_conditional_directive ; Returns with C=0 if processed
  BCC .directive_done
  ; Check for 'macro'
  SET16 directive_macro TABP16
  JSR compare_token
  BEQ .macro
  ; Check for 'endmacro'
  SET16 directive_endmacro TABP16
  JSR compare_token
  BEQ .endmacro
  JMP err_unknown_directive
.directive_done
  RTS
.macro
  JMP process_macro
.endmacro
  JMP process_endmacro
.include
  JSR check_for_end_of_line
  BCC .get_name
  JMP err_filename_expected
.get_name
  JSR read_token
  JSR skip_rest_of_line
  JSR push_file_stack
  RTS
.zeropage
  BIT IN_ZEROPAGE
  BMI .in_zeropage
  LDA #$FF
  STA IN_ZEROPAGE
  JSR swap_pc_with_save
.in_zeropage
  JSR skip_rest_of_line
  RTS
.code
  BIT IN_ZEROPAGE
  BPL .in_code
  LDA #$00
  STA IN_ZEROPAGE
  JSR swap_pc_with_save
.in_code
  JSR skip_rest_of_line
  RTS
.data
  JMP data_parameters_loop_entry


; On exit C=0 if processed; C=1 if not processed
;         A is not preserved
process_conditional_directive
  ; Check for 'ifdef'
  SET16 directive_ifdef TABP16
  JSR compare_token
  BEQ .ifdef
  ; Check for 'endif'
  SET16 directive_endif TABP16
  JSR compare_token
  BEQ .endif
  SEC ; Not processed
  RTS
.ifdef
  JSR process_ifdef
  CLC
  RTS
.endif
  JSR process_endif
  CLC
  RTS


directive_include
  .data "include" $00

directive_zeropage
  .data "zeropage" $00

directive_code
  .data "code" $00

directive_data
  .data "data" $00

directive_ifdef
  .data "ifdef" $00

directive_endif
  .data "endif" $00

directive_macro
  .data "macro" $00

directive_endmacro
  .data "endmacro" $00


data_parameters_loop
data_parameters_loop_entry
  JSR check_for_end_of_line
  BCS .data_done
  CMP #'"'            ; Quoted string
  BNE .data_value
  JSR read_char
  JSR emit_quoted
  JMP data_parameters_loop
.data_value
  ; Parse value: handles $hex, 'char', label, <expr, >expr, and expressions
  JSR parse_value      ; Returns C=1 for bare label, C=0 otherwise, next char in NEXT_CHAR
  BCS .data_emit_two_bytes
  ; C=0: expression/hex/'char'/</>  - emit 1 byte from OPERAND16
  LDA OPERAND16
  JSR emit
  JMP data_parameters_loop
.data_emit_two_bytes
  ; C=1: bare label - emit 2 bytes (LSB, MSB)
  LDA OPERAND16        ; Emit low byte
  JSR emit
  LDA OPERAND16+$01    ; Emit high byte
  JSR emit
  JMP data_parameters_loop
.data_done
  RTS


; Process .ifdef directive
; Records decision in pass 1, replays in pass 2 for consistency with forward refs
process_ifdef
  INC COND_DEPTH
  LDA SKIP_DEPTH
  BNE .pi_already_skipping ; Already skipping, don't record or evaluate
  ; Evaluate condition
  JSR check_for_end_of_line
  BCC .pi_has_label
  JMP err_label_expected
.pi_has_label
  JSR read_token           ; Expects next char in A
  ; Save X (global output file handle)
  TXA
  PHA
  ; Check for pass 2 - no need to look up label in pass 2
  BIT PASS
  BMI .pi_pass2
  ; --- Pass 1: Evaluate and store decision ---
  LDX IFDEF_INDEX
  ; Increment and check for overflow (wrap from 255 to 0 = buffer full)
  INC IFDEF_INDEX
  BEQ .pi_overflow         ; If wrapped to 0, we've used all 256 slots
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR find_in_hash         ; C=0 if found, C=1 if not found
  ; Save result: A = $FF if found (assemble), $00 if not found (skip)
  LDA #$00                 ; Default: not defined (skip)
  BCS .pi_save_result      ; C=1 means not found
  LDA #$FF                 ; Found: defined (assemble)
.pi_save_result
  STA IFDEF_DECISIONS,X
  ; Branch based on decision value
  BEQ .pi_start_skip       ; Not defined ($00) - start skipping
  BNE .pi_done             ; Defined ($FF) - continue (no skip)
  ; --- Pass 2: Replay stored decision ---
.pi_pass2
  LDX IFDEF_INDEX
  INC IFDEF_INDEX
  LDA IFDEF_DECISIONS,X
  BEQ .pi_start_skip
  BNE .pi_done
.pi_start_skip
  LDA COND_DEPTH
  STA SKIP_DEPTH
.pi_done
  ; Restore X (global output file handle)
  PLA
  TAX
.pi_already_skipping
  JMP skip_rest_of_line
.pi_overflow
  JMP err_too_many_ifdefs


; Process .endif directive
process_endif
  LDA COND_DEPTH
  BNE .pe_has_ifdef    ; In a conditional block
  JMP err_endif_without_ifdef
.pe_has_ifdef
  DEC COND_DEPTH
  ; Check if this ends our skip block
  LDA SKIP_DEPTH
  BEQ .pe_done         ; Not skipping, just decrement depth
  ; Currently skipping - check if we should stop
  LDA COND_DEPTH
  CMP SKIP_DEPTH
  BCS .pe_done         ; Still in nested block (COND_DEPTH >= SKIP_DEPTH)
  ; COND_DEPTH < SKIP_DEPTH, stop skipping
  LDA #$00
  STA SKIP_DEPTH
.pe_done
  JMP skip_rest_of_line ; Tail call


; Process .macro directive
; Syntax: .macro NAME [param1 param2 ...]
; Creates entry in IHASHTAB: [name $00][MODE_MACRO][body_ptr_L][body_ptr_H][params...][\0]
process_macro
  ; Skip spaces and read macro name
  JSR check_for_end_of_line
  BCC .pm_has_name
  JMP err_macro_name_expected
.pm_has_name
  JSR read_token       ; Macro name now in TOKEN, next char in NEXT_CHAR
  ; Check for instruction collision or duplicate macro
  JSR select_instruction_hash_table
  ; Optimistically attempt to add macro to the instruction hash table
  JSR hash_add_instruction
  BCC .pm_name_ok      ; C=0 means new, so move on to storing value
  ; Name was already present in hash table - is it an instruction or existing macro?
  ; Check first byte of value - MODE_MACRO means macro, else instruction
  LDA (TABP16),Y
  CMP #MODE_MACRO
  BEQ .pm_is_macro
  JMP err_macro_shadows_instruction
.pm_is_macro
  ; It's a macro - in pass 2 this is expected, just skip to capturing
  BIT PASS
  BMI .pm_pass2_skip_add
  JMP err_duplicate_macro
.pm_pass2_skip_add
  ; Pass 2: skip adding, just set flag to enable body skipping
  ; (body was already captured in pass 1)
  LDA #$FF
  STA IN_MACRO_DEF
  JMP skip_rest_of_line
.pm_name_ok
  ; Add macro entry value
  ; MEMP16 points to location at which to store the value
  ; TABP16 points to the macro name on heap
  .ifdef enable_debug
  CP16 TABP16 MACRO_NAME_PTR16
  .endif
  ; Store MODE_MACRO sentinel
  LDY #$00
  APPEND_HEAPI MODE_MACRO
  JSR advance_heap
.pm_param_loop
  JSR check_for_end_of_line
  BCS .pm_params_done  ; End of line, no more params
  ; Read parameter name
  JSR read_token       ; Param name in TOKEN, next char in NEXT_CHAR
  ; Store parameter name on heap (null-terminated)
  LDY #$FF
.pm_copy_param
  INY
  LDA TOKEN,Y
  STA (MEMP16),Y
  BNE .pm_copy_param
  INY
  JSR advance_heap
  JMP .pm_param_loop
.pm_params_done
  ; Write empty string terminator for parameter list
  LDY #$00
  APPEND_HEAPI $00
  JSR advance_heap
  ; Update MACRO_DEF_PTR to point where body will be stored
  CP16 MEMP16 MACRO_DEF_PTR16
  ; Set IN_MACRO_DEF flag to start capturing
  LDA #$FF
  STA IN_MACRO_DEF
  ; Skip rest of line (already done by check_for_end_of_line)
  RTS


; Process .endmacro directive
process_endmacro
  ; Check if we're in a macro definition
  LDA IN_MACRO_DEF
  BNE .pem_in_macro
  JMP err_endmacro_without_macro
.pem_in_macro
  ; In pass 2, skip heap write (body was already captured in pass 1)
  BIT PASS
  BPL .pem_pass1
  JMP .pem_clear_flag
.pem_pass1
  ; Pass 1: Write $00 terminator to body
  LDY #$00
  APPEND_HEAPI $00
  JSR advance_heap

  .ifdef enable_debug
  LDA SHOW_MACROS
  BEQ .not_showing_macros
  JSR show_macros
.not_showing_macros
  .endif

.pem_clear_flag
  ; Clear the capturing flag
  LDA #$00
  STA IN_MACRO_DEF
  JMP skip_rest_of_line


; Check if macro is already being expanded (recursion check)
; Walks the scope stack comparing 2-byte macro entry addresses
; On entry: MACRO_ENTRY16 contains the macro's hash table entry address
; On exit: Returns normally if no recursion, jumps to err_recursive_macro if found
;          Uses TABP16 as walk pointer, A/Y clobbered, X preserved
check_macro_recursion
  ; Walk scope stack from bottom to current position
  SET16 SCOPE_STACK TABP16
.cmr_loop
  ; Check if we've reached current scope pointer
  CMP16 TABP16 SCOPE_PTR16
  BEQ .cmr_done             ; Reached current position, no recursion
  ; Compare macro address at offset +3 with MACRO_ENTRY16
  LDY #$03
  LDA (TABP16),Y
  CMP MACRO_ENTRY16
  BNE .cmr_next
  INY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16+$01
  BNE .cmr_next
  ; Match found - recursion detected
  JMP err_recursive_macro
.cmr_next
  ; Advance to next entry (+5 bytes)
  LDA TABP16
  CLC
  ADC #$05
  STA TABP16
  BCC .cmr_loop
  INC TABP16+$01
  JMP .cmr_loop
.cmr_done
  RTS


; Expand a macro invocation
; On entry: MACRO_DEF_PTR points to the  macro entry
;           (param1\0, param2\0, ..., \0, body\0)
;           TOKEN contains the macro name
; On exit: Memory source pushed, jumps to asm_line_loop
expand_macro
.ARG_SIZE = $03 ; Size of each macro argument (value_L, value_H, is_fwdref)
  ; Save original macro entry address before MACRO_DEF_PTR is modified
  CP16 MACRO_DEF_PTR16 MACRO_ENTRY16
  ; Check for recursive macro invocation
  JSR check_macro_recursion
  ; Save X (output file handle) - we'll use X as index into MACRO_ARG_BUF
  TXA
  PHA
  ; DON'T push label scope yet - we need parent's scope to look up arguments
  ; Parse arguments first, storing values in fixed buffer

  ; ----- Phase 1: Capture argument values -----
  ; X = index into MACRO_ARG_BUF for storing values
  ; Each entry: [is_fwdref][value_L][value_H] = 3 bytes
  LDX #$00
.em_parse_loop
  ; Check if we're at end of parameter list (empty string)
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  BEQ .em_parse_done
  ; Skip past parameter name
  LDY #$FF
.em_skip_param
  INY
  LDA (MACRO_DEF_PTR16),Y
  BNE .em_skip_param
  ; Advance MACRO_DEF_PTR past the null terminator
  TYA
  SEC                   ; +1 for null
  ADDA16 MACRO_DEF_PTR16 MACRO_DEF_PTR16
  ; Check for argument in input
  JSR check_for_end_of_line
  BCC .em_have_arg
  JMP err_too_few_arguments
.em_have_arg
  ; Parse argument expression (using PARENT's scope for lookups)
  JSR parse_expression
  ; MACRO_ARG_BUF bounds check
  ; Check if X < MACRO_ARG_BUF_LIMIT-MACRO_ARG_BUF-.ARG_SIZE+$01 (room for one more entry)
  CPX #MACRO_ARG_BUF_LIMIT-MACRO_ARG_BUF-.ARG_SIZE+$01
  BCC .arg_ok         ; X < limit: safe
.arg_overflow
  JMP err_too_many_arguments
.arg_ok
  ; Store fwdref flag and value in fixed buffer
  LDA IS_FWDREF
  STA MACRO_ARG_BUF,X
  INX
  LDA OPERAND16
  STA MACRO_ARG_BUF,X
  INX
  LDA OPERAND16+$01
  STA MACRO_ARG_BUF,X
  INX
  JMP .em_parse_loop
.em_parse_done
  ; Check for extra arguments (should be at end of line now)
  JSR check_for_end_of_line
  BCC .em_too_many
  ; NOW push label scope for the child macro
  JSR push_label_scope

  ; ----- Phase 2: Populate child macro scope with parameter values -----
  ; Restore params start to MACRO_DEF_PTR
  CP16 MACRO_ENTRY16 MACRO_DEF_PTR16
  ; Reset X to read values from start of macro arg buffer
  LDX #$00
  ; Now iterate through params and add to hash with stored values
.em_add_loop
  ; Check if at end of parameter list
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  BEQ .em_add_done
  ; Copy param name to TOKEN
  LDY #$FF
.em_copy_param
  INY
  LDA (MACRO_DEF_PTR16),Y
  STA TOKEN,Y
  BNE .em_copy_param
  ; Advance MACRO_DEF_PTR past param name
  TYA
  SEC ; +1 for null terminator
  ADDA16 MACRO_DEF_PTR16 MACRO_DEF_PTR16 ; MACRO_DEF_PTR + A + 1 -> MACRO_DEF_PTR
  ; Load fwdref and value from buffer
  LDA MACRO_ARG_BUF,X
  STA IS_FWDREF
  INX
  LDA MACRO_ARG_BUF,X
  STA OPERAND16
  INX
  LDA MACRO_ARG_BUF,X
  STA OPERAND16+$01
  INX
  ; Skip adding if forward ref in pass 1
  LDA IS_FWDREF
  BEQ .em_do_add
  BIT PASS
  BPL .em_add_loop      ; Pass 1 fwdref: skip
  ; Pass 2: always add
.em_do_add
  ; Add parameter to macro-local scope
  LDA #LABEL_TYPE_MACRO
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR hash_add
  BCS .em_add_loop      ; Already exists (pass 1), skip store
  ; Store value (OPERAND16 aliased to HEX16)
  JSR store_hash_value
  JMP .em_add_loop
.em_add_done
  ; Push memory source and set up pointers
  JSR push_memory_source
  ; Set memory pointer to body_ptr from macro definition
  ; Add one to MACR_DEF_PTR16 to skip 0 terminator and save to memory source
  CLC
  ADDI16 MACRO_DEF_PTR16 $01 FS_MEM_PTR16
  ; Restore X (output file handle)
  PLA
  TAX
  JMP asm_line_loop
.em_too_many
  JMP err_too_many_arguments


; Capture a line during macro definition
; On entry: A contains first character of line
; On exit: Line copied to heap (with $0A), or .endmacro processed
;          Returns to caller (who should JMP .line_loop)
;
; Strategy: Copy whole line to heap, then check if it was .endmacro.
; If so, undo the copy and process .endmacro normally.
; In pass 2, skip heap copy - just scan for .endmacro detection.
capture_macro_line
  BIT PASS
  BPL .cml_pass1
  JMP .cml_pass2
.cml_pass1
  ; === Pass 1: Copy to heap ===
  ; Save X (output file handle)
  TXA
  PHA
  ; Save heap position in case we need to undo (for .endmacro)
  ; Use MACRO_DEF_PTR since we're not using it during capture
  CP16 MEMP16 MACRO_DEF_PTR16
  ; Restore first char
  LDA NEXT_CHAR
  ; Copy whole line to heap including newline
  ; Optimization: only call advance_heap when Y reaches 128 or at line end
  LDY #$00
.cml_copy_loop
  STA (MEMP16),Y
  CMP #'\n'
  BEQ .cml_line_done
  INY
  BPL .cml_read_next   ; Y still 0-127
  JSR advance_heap     ; Y hit 128, commit and Y resets to 0
.cml_read_next
  JSR read_char
  BCC .cml_copy_loop
  ; EOF during macro - error
  JMP err_unclosed_macro
.cml_line_done
  INY                  ; Include newline in count
  JSR advance_heap     ; Commit remaining bytes
  ; Now check if this line was .endmacro
  CP16 MACRO_DEF_PTR16 TABP16
  ; Skip leading spaces
  LDY #$00
.cml_skip_space
  LDA (TABP16),Y
  CMP #' '
  BNE .cml_check_dot
  INY
  BNE .cml_skip_space
.cml_check_dot
  CMP #'.'
  BNE .cml_keep_line
  ; It's a directive - check for .endmacro first (the usual case)
  INY                    ; Y now points past '.'
  TYA
  PHA                    ; Save Y for later .macro check
  LDX #$00
.cml_cmp_loop
  LDA directive_endmacro,X
  BEQ .cml_check_end     ; End of "endmacro" string
  CMP (TABP16),Y
  BNE .cml_not_endmacro
  INY
  INX
  BNE .cml_cmp_loop
.cml_check_end
  ; Matched "endmacro" - verify next char is not a token character
  LDA (TABP16),Y
  JSR compare_end_of_token
  BNE .cml_not_endmacro  ; Not end of token - keep as macro body
  ; Found .endmacro. Restore heap to undo the copy
  CP16 MACRO_DEF_PTR16 MEMP16
  PLA                    ; Discard the saved Y register
  ; Restore X (output file handle)
  PLA
  TAX
  JMP process_endmacro   ; Tail call
.cml_not_endmacro
  ; Not .endmacro - check if it's .macro (nested definition)
  PLA                    ; Restore Y position after '.'
  TAY
  LDX #$00
.cml_cmp_macro
  LDA directive_macro,X
  BEQ .cml_check_macro_end  ; End of "macro" string
  CMP (TABP16),Y
  BNE .cml_keep_line
  INY
  INX
  BNE .cml_cmp_macro
.cml_check_macro_end
  ; Matched "macro" - verify next char is not a token character
  LDA (TABP16),Y
  JSR compare_end_of_token
  BNE .cml_keep_line     ; Not end of token, not .macro
  ; Found nested macro definition - error
  JMP err_nested_macro_definition
.cml_keep_line
  ; Restore X (output file handle)
  PLA
  TAX
  RTS

  ; === Pass 2: Skip without copying to heap ===
  ; Just detect .endmacro to clear IN_MACRO_DEF flag
.cml_pass2
  LDA NEXT_CHAR
.cml_p2_scan
  CMP #' '
  BNE .cml_p2_not_space
  JSR read_char
  BCC .cml_p2_scan
  JMP err_unclosed_macro       ; EOF in macro
.cml_p2_not_space
  CMP #'\n'
  BEQ .cml_p2_done             ; Empty/blank line
  CMP #'.'
  BNE .cml_p2_skip             ; Not a directive
  ; Check if directive is .endmacro
  JSR read_char                ; Read char after '.'
  JSR read_token               ; Read directive name into TOKEN
  SET16 directive_endmacro TABP16
  JSR compare_token
  BNE .cml_p2_skip             ; Not .endmacro
  ; Found .endmacro
  JMP process_endmacro         ; Tail call
.cml_p2_skip
  JSR skip_rest_of_line
.cml_p2_done
  RTS


; ============================================================================
; TIER 11: ASSEMBLY ORCHESTRATION
; Main assembly loop
; ============================================================================

; Read from input, assemble code and write to output
; On entry PASS indicates the current pass:
;            bit 7 clear = pass 1
;            bit 7 set = pass 2
;          X contains the file handle of the output file
; On exit X is preserved
;         A, Y are not preserved
assemble_code
  LDA #$00
  STA STARTED
  STA IN_ZEROPAGE
  STA_LH16 PC16
  STA_LH16 PC_SAVE16
  STA_LH16 CURR_LINE16
  STA_LH16 LABEL_SCOPE16 ; Initialize scope (0 = no global yet)
  STA LABEL_TYPE  ; Initialize local label flag
  STA COND_DEPTH      ; Clear conditional depth
  STA SKIP_DEPTH      ; Clear skip depth
  STA IN_MACRO_DEF    ; Clear macro definition flag
  STA IFDEF_INDEX     ; Clear .ifdef decision index
asm_line_loop                 ; Global entry for macro expansion
.line_loop
  JSR read_char
  BCC .character_read
  ; End of input - check for unclosed conditional
  LDA COND_DEPTH
  BEQ .no_unclosed_ifdef
  JMP err_unclosed_ifdef
.no_unclosed_ifdef
  ; Check for unclosed macro definition
  LDA IN_MACRO_DEF
  BEQ .no_unclosed_macro
  JMP err_unclosed_macro
.no_unclosed_macro
  RTS
.character_read
  INC16 CURR_LINE16
  ; Check if we're capturing macro body
  LDY IN_MACRO_DEF
  BEQ .not_capturing_macro
  JSR capture_macro_line
  JMP .line_loop
.not_capturing_macro
  ; Check if we're skipping (conditional assembly)
  LDY SKIP_DEPTH
  BEQ .not_skipping
  ; --- Skipping mode: only process .ifdef/.endif ---
  CMP #' '
  BNE .skip_not_space
  ; Line starts with space - skip spaces to find directive
  JSR check_for_end_of_line
  BCS .line_loop
  JMP .skip_check_directive
.skip_not_space
  JSR check_for_end_of_line
  BCS .line_loop
  ; Line starts with non-space - skip label, check for directive
  JSR skip_token
  JSR check_for_end_of_line
  BCS .line_loop
.skip_check_directive
  CMP #'.'
  BNE .skip_line
  ; It's a directive - only process ifdef/endif
  JSR read_char
  JSR read_token
  JSR process_conditional_directive
  BCC .back_to_line_loop ; directive processed; already skipped line
.skip_line
  JSR skip_rest_of_line
  JMP .line_loop
.not_skipping
  CMP #' '
  BEQ .line_starts_with_space
  JSR check_for_end_of_line
  BCS .back_to_line_loop
  JSR capture_label
  BCC .check_for_opcode
  BCS .back_to_line_loop   ; Always taken
.line_starts_with_space
  JSR check_for_end_of_line
  BCS .back_to_line_loop
.check_for_opcode
  CMP #'.'
  BNE .opcode
; Directive
  JSR read_char
  JSR process_directive
  JMP .line_loop
.opcode
  ; Read mnemonic and look up in instruction table
  JSR lookup_mnemonic
  ; A contains next char after mnemonic
  ; Parse operand to determine addressing mode
  JSR parse_operand_and_emit
  ; A contains next char after operand - check for garbage
  ; Skip trailing spaces, then check for end of line (handles comments)
  JSR check_for_end_of_line
  BCS .back_to_line_loop
  JMP err_unexpected_text
.back_to_line_loop
  JMP .line_loop


; ============================================================================
; TIER 12: INITIALIZATION & I/O
; Program initialization and file operations
; ============================================================================

; Opens the file with name from the first command line argument, pushing
; to the file stack
; On exit X is preserved
open_input
  TXA
  PHA
  LDA #$00
  JSR argv
  STA TABP16
  STX TABP16+$01
  PLA
  TAX
  LDY #$FF
.loop
  INY
  LDA (TABP16),Y
  STA TOKEN,Y
  BNE .loop
  JMP push_file_stack ; tail call


MATCH_PARTIAL = $00
MATCH_FULL    = $01

COMMAND_LINE_ARGS
  .ifdef enable_debug
  .data "debug"                $00 <MATCH_FULL    handle_debug
  .data "small_heap"           $00 <MATCH_FULL    handle_small_heap
  .data "show_captured_macros" $00 <MATCH_FULL    handle_show_captured_macros
  .endif
  .data "define:"              $00 <MATCH_PARTIAL handle_define
  .data $00 ; End of list


  .ifdef enable_debug

; Handle the 'debug' command line argument
handle_debug
  LDA #$FF
  STA DEBUG_FLAG
  RTS

; Handle the 'small_heap' command line argument
handle_small_heap
  LDA #$FF
  STA SMALL_HEAP_FLAG
  JMP init_heap          ; Tail call

; Handle the 'show_captured_macros' command line argument
handle_show_captured_macros
  LDA #$FF
  STA SHOW_MACROS
  .endif

; Handle the 'define:' command line argument
; On entry TABP16 points past "define:" to label name
handle_define
  JSR copy_string_to_token
  SET16 $0001 HEX16
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JMP hash_add           ; Tail call


  .zeropage

JUMP_TARGET16 .data $0000 ; Target for indirect jumps
ARG_PTR16     .data $0000 ; Pointer into COMMAND_LINE_ARGS table

  .code


; Match command line argument against table
; On entry TABP16 points to the argument string
; Calls the handler if match found (with TAB16 pointed to remainder of argument for partial)
; On exit C = 0 if match found
;         C = 1 if no match
;         X, Y are preserved
;         A is not preserved
match_command_line_arg
  TYA
  PHA
  SET16 COMMAND_LINE_ARGS ARG_PTR16
.try_entry
  ; Check for end of table (first byte = 0)
  LDY #$00
  LDA (ARG_PTR16),Y
  BEQ .no_match
  ; Compare strings
.compare_loop
  LDA (ARG_PTR16),Y
  BEQ .string_end        ; End of table string
  CMP (TABP16),Y
  BNE .next_entry        ; Mismatch, try next
  INY
  BNE .compare_loop      ; Always taken
.string_end
  ; Table string ended - check match type
  ; Y = length of matched string (points to null terminator)
  INY                    ; Skip null terminator
  LDA (ARG_PTR16),Y      ; Load match type
  BNE .check_full_match  ; MATCH_FULL (non-zero)
  ; MATCH_PARTIAL - prefix matched, advance TABP16
  DEY                    ; Back up to the match position
  TYA                    ; Y is pointing at the text following the match
  CLC
  ADDA16 TABP16 TABP16
  INY                    ; Skip forwards to the handler position
  JMP .load_handler
.check_full_match
  ; MATCH_FULL - argument string must also end here
  DEY                    ; Undo the INY to check at same position as null
  LDA (TABP16),Y
  BNE .next_entry        ; Arg string continues, not a match
  INY                    ; Skip past the match type
.load_handler
  ; Load handler address (Y points to match type byte)
  INY                    ; Skip match type
  LDA (ARG_PTR16),Y
  STA JUMP_TARGET16
  INY
  LDA (ARG_PTR16),Y
  STA JUMP_TARGET16+$01
  JSR do_jump            ; Call handler
  CLC                    ; Match found
  PLA                    ; Restore Y
  TAY
  RTS
.next_entry
  ; Advance ARG_PTR16 to next entry
  ; Find null terminator
.find_null
  LDA (ARG_PTR16),Y
  BEQ .found_null
  INY
  BNE .find_null
.found_null
  ; Y points to null, skip null + match_type + 2-byte address = 4 more bytes
  TYA
  CLC
  ADC #$04
  ADDA16 ARG_PTR16 ARG_PTR16
  JMP .try_entry
.no_match
  SEC
  PLA                    ; Restore Y
  TAY
  RTS

; Execute handler via indirect jump
; On entry JUMP_TARGET16 contains the handler address
do_jump
  JMP (JUMP_TARGET16)


; Copy null-terminated string from TABP16 to TOKEN
; On exit: Y contains length (excluding null terminator)
;          A is not preserved
copy_string_to_token
  LDY #$00
.loop
  LDA (TABP16),Y
  BEQ .done
  STA TOKEN,Y
  INY
  JMP .loop
.done
  LDA #$00
  STA TOKEN,Y          ; Null-terminate
  RTS


; ============================================================================
; TIER 13: DEUBUG and TEST support
; Support for debugging and testing
; ============================================================================

  .ifdef enable_debug

show_macros
  ; Save X (output file handle)
  TXA
  PHA
  ; Output "Macro: "
  SHOW_MESSAGEI .macro_prefix
  LDY #$00
  ; Output macro name
  CP16 MACRO_NAME_PTR16 TABP16
  JSR show_message
  ; Skip past the trailing null and MODE_MACRO byte
  INY
  TYA
  SEC ; +1
  ADDA16 TABP16 TABP16
  LDY #$00
.show_params
  ; Output each param preceded by space
  LDA (TABP16),Y
  BEQ .show_params_done    ; Empty string = end of params
  LDA #' '
  JSR write_d
  JSR show_message
  ; Skip past null terminator
  TYA
  SEC
  ADDA16 TABP16 TABP16
  LDY #$00
  BEQ .show_params         ; Always taken
.show_params_done
  ; Advance past the trailing null
  TYA
  SEC ; +1
  ADDA16 TABP16 TABP16
  LDY #$00
  LDA #'\n'
  JSR write_d
  ; Output macro body
.show_body
  LDA (TABP16),Y
  BEQ .show_done
  JSR write_d
  INY
  BNE .show_body
  INC TABP16+$01
  JMP .show_body
.macro_prefix
  .data "Macro: " $00
.show_done
  ; Restore X (output file handle)
  PLA
  TAX
  RTS

  .endif


; ============================================================================
; TIER 14: ENTRY POINT
; Program entry and main control flow
; ============================================================================

; Entry point
start
  ; Initialize output file handle to 0
  LDA #$00
  STA CURR_OUT_FILE
  .ifdef enable_debug
  ; Initialize debug flags to 0
  STA DEBUG_FLAG
  STA SMALL_HEAP_FLAG
  STA SHOW_MACROS
  .endif
  ; Initialize file stack early so interrupt handler works correctly
  JSR file_stack_init
  ; Initialize scope stack for macro expansions
  JSR init_scope_stack
  ; Check argument count (must be at least 2)
  JSR argc
  CMP #$02
  BCC .err_usage         ; Less than 2 args
  STA ARG_COUNT          ; Save total arg count
  ; Initialize heap and hash table early for define: args
  JSR init_heap
  JSR select_label_hash_table
  JSR init_hash_table
  ; Process arguments 2 onwards (arg 0 = input, arg 1 = output)
  LDY #$02               ; Argument index
.arg_loop
  CPY ARG_COUNT
  BCS .args_done         ; Processed all args
  TYA                    ; Argument index
  JSR argv               ; Get arg[Argument index]
  STA TABP16
  STX TABP16+$01
  JSR match_command_line_arg
  BCS .invalid_argument  ; Match not found
  INY                    ; Move to next argument
  BNE .arg_loop          ; Always taken. TODO: if this wraps raise a too many arguments error
.invalid_argument
  JMP err_invalid_arg
.err_usage
  JMP err_usage
.args_done
  LDA #$00
  STA PASS            ; Bit 7 = 0 (pass 1)
  JSR init_fwdref_list
  JSR open_input

  ; Open output file
  LDA #$01
  JSR argv
  JSR openout
  STA CURR_OUT_FILE
  TAX

  JSR assemble_code
  JSR finalize_fwdref_list

  .ifdef enable_debug
  ; Capture forward ref pointer after pass 1
  CP16 FWDREF16 PASS_1_FWDREF16
  .endif

  LDA #$FF
  STA PASS            ; Bit 7 = 1 (pass 2)
  JSR reset_fwdref_ptr
  JSR reset_scope_stack   ; Reset so pass 2 uses same scope IDs as pass 1
  JSR open_input
  JSR assemble_code

  .ifdef enable_debug
  ; Verify forward ref pointer matches pass 1
  CMP16 FWDREF16 PASS_1_FWDREF16 
  BEQ .fwdref_ok
  ; Mismatch in ref counts
  JMP err_fwdref_tracking
.fwdref_ok
  .endif

  ; Close output file
  TXA
  JSR close
  LDA #$00
  STA CURR_OUT_FILE

  .ifdef enable_debug
  ; Print heap usage if debug flag is set
  LDA DEBUG_FLAG
  BEQ .skip_debug_output
  SHOW_MESSAGEI msg_heap_used
  ; Calculate heap used: MEMP16 - HEAP
  SEC
  SUBI16 MEMP16 HEAP TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI msg_bytes
  ; Print forward reference count
  SHOW_MESSAGEI msg_fwdref_count
  ; Calculate forward ref count: (PASS_1_FWDREF16 - FWDREF_LIST) / 2
  SEC
  SUBI16 PASS_1_FWDREF16 FWDREF_LIST TO_DECIMAL_VALUE16
  ; Divide by 2 (16-bit right shift)
  LSR16 TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_CHAR '\n'
.skip_debug_output
  .endif

  ; All done, successfully
  BRK
  .data $00             ; Success code


  .ifdef enable_debug
msg_heap_used
  .data "Heap used: " $00
msg_bytes
  .data " bytes\n" $00
msg_fwdref_count
  .data "Forward references forced to absolute: " $00
  .endif


HEAP                   ; Heap goes after the program code


* = $FFFC
  .data start           ; Reset vector
  .data interrupt       ; Interrupt vector
