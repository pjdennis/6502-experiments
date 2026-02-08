; ============================================================================
; ASM23 - Self-Hosting 6502 Assembler
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
;   CURR_CHAR     Current character (last byte read by read_char)
;   TOKEN         Buffer holding current token being parsed
;   PASS          $00 = pass 1, $FF = pass 2
;   PC16          Current program counter (where code is being generated)
;   MEMP16        Heap pointer (grows upward from end of generated code)
;   FS_P16        File stack pointer (grows downward from FILE_STACK)
;
; PARSING MODEL
;   read_char advances input, stores result in both A and CURR_CHAR
;   Token reading uses TOKEN buffer, writes null terminator
;   Single-character lookahead via CURR_CHAR for parsing decisions
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
;   Shared code with instgen.asm via common.asm
;
; ============================================================================

; Addresses
FWDREF_LIST     = $0200  ; Forward reference list (512 bytes, $0200-$03FF)
FWDREF_LIMIT    = FWDREF_LIST + $0200 ; Limit for forward reference list data
SCOPE_STACK     = $0400  ; Label scope stack for macro expansions (256 bytes, $0400-$04FF)
SCOPE_LIMIT     = SCOPE_STACK + $0100 ; Limit for scope stack
MACRO_ARG_BUF   = $0500  ; Temp buffer for macro args during expansion (256 bytes)
MACRO_ARG_LIMIT = MACRO_ARG_BUF + $0100 ; Limit for macro arg buffer
TOKEN           = $0600  ; Buffer for the current token being read
LHASHTAB        = $0700  ; Label hash table
IFDEF_DECISIONS = $0800  ; Buffer for .ifdef decisions (256 bytes)
*               = $2000  ; Code generates here follwed by HEAP
FILE_STACK      = $F000  ; File stack will grow down from 1 below here


  .zeropage

; Zero page locations
TEMP:            .byte        ; 1 byte
PC16:            .word        ; 2 byte program counter
HEX16:           .word        ; 2 byte hex value, also aliased as OPERAND16
OPERAND16 = HEX16             ; Operand value - alias for HEX16
PASS:            .byte        ; 1 byte $00 = pass 1 $FF = pass 2
STARTED:         .byte        ; flag to indicate output has started
CURR_OUT_FILE:   .byte        ; Current output file (for closing on error)
IN_ZEROPAGE:     .byte        ; Flag indicating if in zero page section
PC_SAVE16:       .word        ; Save location for PC when switching sections
INST_PTR16:      .word        ; Pointer to instruction mode table entry, aliased as MACRO_DEF_PTR16
MACRO_DEF_PTR16 = INST_PTR16  ; Heap pointer where macro body is being stored, aliased to INST_PTR16
IS_FWDREF:       .byte        ; $FF if current label is forward ref (pass 1 only)
ARG_COUNT:       .byte        ; Total command line argument count
MACRO_ENTRY16:   .word        ; Original macro hash entry address (for recursion check)

  .ifdef enable_debug
DEBUG_FLAG:      .byte        ; Non-zero if debug output enabled
PASS_1_FWDREF16: .word        ; Forward ref pointer after pass 1
SMALL_HEAP_FLAG: .byte        ; Non-zero if small_heap argument was passed
SHOW_MACROS:     .byte        ; Non-zero if captured macro definitions should be printed
MACRO_PTR16:     .word        ; Pointer to macro name (for show_captured_macros)
  .endif

  .code


; Include files
  .include out/inst.asm.out   ; This goes first since the tables should start on a page boundary
  .include environment.asm
  .include macros.asm
  .include common.asm
  .include label_scope.asm
  .include forward_ref.asm
FS_FILENAME        = TOKEN
FS_POP_MEMORY_HOOK = pop_label_scope
  .ifdef enable_debug
FS_ERR_NO_FILE     = err_no_file
  .endif
  .include file_stack.asm
read_char          = file_stack_read_char
CURR_CHAR          = FS_CURR_CHAR
CURR_LINE16        = FS_CURR_LINE16
  .include errors.asm
  .include from_decimal.asm
  .include tokenizer.asm
  .include expressions.asm
  .include labels.asm
  .include instructions.asm
  .include directives.asm
  .include macro_expansion.asm


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
assemble_code:
  LDA #$00
  STA STARTED
  STA IN_ZEROPAGE
  STA_LH16 PC16
  STA_LH16 PC_SAVE16
  STA_LH16 CURR_LINE16
  STA_LH16 LABEL_SCOPE16 ; Initialize scope (0 = no global yet)
  STA LABEL_TYPE         ; Initialize local label flag
  STA COND_DEPTH         ; Clear conditional depth
  STA SKIP_DEPTH         ; Clear skip depth
  STA IN_MACRO_DEF       ; Clear macro definition flag
  STA IFDEF_INDEX        ; Clear .ifdef decision index
.line_loop:
  JSR read_char
  BCC .character_read
  ; End of input - check for unclosed conditional
  LDA COND_DEPTH
  BEQ .no_unclosed_ifdef
  JMP err_unclosed_ifdef
.no_unclosed_ifdef:
  ; Check for unclosed macro definition
  LDA IN_MACRO_DEF
  BEQ .no_unclosed_macro
  JMP err_unclosed_macro
.no_unclosed_macro:
  RTS
.character_read:
  INC16 CURR_LINE16
  ; Check if we're capturing macro body
  LDY IN_MACRO_DEF
  BEQ .not_capturing_macro
  JSR capture_macro_line
  JMP .line_loop
.not_capturing_macro:
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
.skip_not_space:
  JSR check_for_end_of_line
  BCS .line_loop
  ; Line starts with non-space - skip label, check for directive
  JSR skip_token
  JSR check_for_end_of_line
  BCS .line_loop
.skip_check_directive:
  CMP #'.'
  BNE .skip_line
  ; It's a directive - only process ifdef/endif
  JSR read_char
  JSR read_token
  JSR process_conditional_directive
  BCC .back_to_line_loop ; directive processed; already skipped line
.skip_line:
  JSR skip_rest_of_line
  JMP .line_loop
.not_skipping:
  CMP #' '
  BEQ .line_starts_with_space
  JSR check_for_end_of_line
  BCS .back_to_line_loop
  JSR capture_label
  BCC .check_for_opcode
  BCS .back_to_line_loop   ; Always taken
.line_starts_with_space:
  JSR check_for_end_of_line
  BCS .back_to_line_loop
.check_for_opcode:
  CMP #'.'
  BNE .opcode
; Directive
  JSR read_char
  JSR process_directive
  JMP .line_loop
.opcode:
  ; Read mnemonic and look up in instruction table
  JSR lookup_mnemonic      ; Returns with C=0 for mnemonic or C=1 for macro
  ; A contains current char after mnemonic or macro name
  BCS .macro
  ; Parse operand to capture value and determine addressing mode
  JSR parse_operand
  ; Emit the instruction
  JSR emit_instruction 
  ; A contains current char after operand - check for garbage
  ; Skip trailing spaces, then check for end of line (handles comments)
  JSR check_for_end_of_line
  BCS .back_to_line_loop
  JMP err_unexpected_text
.macro:
  JSR expand_macro
.back_to_line_loop:
  JMP .line_loop


; ============================================================================
; TIER 12: INITIALIZATION & I/O
; Program initialization and file operations
; ============================================================================

; Opens the file with name from the first command line argument, pushing
; to the file stack
; On exit X is preserved
open_input:
  TXA
  PHA
  LDA #$00
  JSR argv
  STA TABP16
  STX TABP16+$01
  PLA
  TAX
  JSR copy_string_to_token
  JMP push_file_stack ; tail call


MATCH_PARTIAL = 0
MATCH_FULL    = 1

COMMAND_LINE_ARGS:
  .ifdef enable_debug
  .asciiz "debug"
  .byte MATCH_FULL
  .word handle_debug
  .asciiz "small_heap"
  .byte MATCH_FULL
  .word handle_small_heap
  .asciiz "show_captured_macros"
  .byte MATCH_FULL
  .word handle_show_captured_macros
  .endif
  .asciiz "define:"
  .byte MATCH_PARTIAL
  .word handle_define
  .byte 0 ; End of list


  .ifdef enable_debug

; Handle the 'debug' command line argument
handle_debug:
  LDA #$FF
  STA DEBUG_FLAG
  RTS

; Handle the 'small_heap' command line argument
handle_small_heap:
  LDA #$FF
  STA SMALL_HEAP_FLAG
  JMP init_heap          ; Tail call

; Handle the 'show_captured_macros' command line argument
handle_show_captured_macros:
  LDA #$FF
  STA SHOW_MACROS
  .endif

; Handle the 'define:' command line argument
; On entry TABP16 points past "define:" to label name
handle_define:
  JSR copy_string_to_token
  SET16 $0001, HEX16
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR hash_add
  JMP store_hash_value   ; Store value and advance heap


  .zeropage

JUMP_TARGET16: .word       ; Target for indirect jumps
ARG_PTR16:     .word       ; Pointer into COMMAND_LINE_ARGS table

  .code


; Match command line argument against table
; On entry TABP16 points to the argument string
; Calls the handler if match found (with TAB16 pointed to remainder of argument for partial)
; On exit C = 0 if match found
;         C = 1 if no match
;         X, Y are preserved
;         A is not preserved
match_command_line_arg:
  TYA
  PHA
  SET16 COMMAND_LINE_ARGS, ARG_PTR16
.try_entry:
  ; Check for end of table (first byte = 0)
  LDY #$00
  LDA (ARG_PTR16),Y
  BEQ .no_match
  ; Compare strings
.compare_loop:
  LDA (ARG_PTR16),Y
  BEQ .string_end        ; End of table string
  CMP (TABP16),Y
  BNE .next_entry        ; Mismatch, try next
  INY
  BNE .compare_loop      ; Always taken
.string_end:
  ; Table string ended - check match type
  ; Y = length of matched string (points to null terminator)
  INY                    ; Skip null terminator
  LDA (ARG_PTR16),Y      ; Load match type
  BNE .check_full_match  ; MATCH_FULL (non-zero)
  ; MATCH_PARTIAL - prefix matched, advance TABP16
  DEY                    ; Back up to the match position
  TYA                    ; Y is pointing at the text following the match
  CLC
  ADCA16 TABP16, TABP16
  INY                    ; Skip forwards to the handler position
  JMP .load_handler
.check_full_match:
  ; MATCH_FULL - argument string must also end here
  DEY                    ; Undo the INY to check at same position as null
  LDA (TABP16),Y
  BNE .next_entry        ; Arg string continues, not a match
  INY                    ; Skip past the match type
.load_handler:
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
.next_entry:
  ; Advance ARG_PTR16 to next entry
  ; Find null terminator
.find_null:
  LDA (ARG_PTR16),Y
  BEQ .found_null
  INY
  BNE .find_null
.found_null:
  ; Y points to null, skip null + match_type + 2-byte address = 4 more bytes
  TYA
  CLC
  ADC #$04
  ADCA16 ARG_PTR16, ARG_PTR16
  JMP .try_entry
.no_match:
  SEC
  PLA                    ; Restore Y
  TAY
  RTS

; Execute handler via indirect jump
; On entry JUMP_TARGET16 contains the handler address
do_jump:
  JMP (JUMP_TARGET16)


; Copy null-terminated string from TABP16 to TOKEN
; On exit: Y contains length (excluding null terminator)
;          A is not preserved
copy_string_to_token:
  LDY #$00
.loop:
  LDA (TABP16),Y
  BEQ .done
  STA TOKEN,Y
  INY
  BNE .loop              ; A is guaranteed non-zero (BEQ .done above)
.done:
  LDA #$00
  STA TOKEN,Y          ; Null-terminate
  RTS


; ============================================================================
; TIER 13: DEUBUG and TEST support
; Support for debugging and testing
; ============================================================================

  .ifdef enable_debug

show_macros:
  ; Output "Macro: "
  SHOW_MESSAGEI .macro_prefix
  ; Output macro name
  CP16 MACRO_PTR16, TABP16
  JSR show_message
  ; Skip past the trailing null and MODE_MACRO byte
  INY
  INY
  JSR .advance_tabp
.show_params:
  ; Output first param preceded by space
  LDA (TABP16),Y
  BEQ .show_params_done    ; Empty string = end of params
  LDA #' '
  JSR write_d
  JSR show_message
  ; Skip past null terminator
  INY
  JSR .advance_tabp
.show_more_params:
  ; Output subsequent params preceded by comma+space
  LDA (TABP16),Y
  BEQ .show_params_done    ; Empty string = end of params
  LDA #','
  JSR write_d
  LDA #' '
  JSR write_d
  JSR show_message
  ; Skip past null terminator
  INY
  JSR .advance_tabp
  JMP .show_more_params
.show_params_done:
  ; Advance past the trailing null
  INY
  JSR .advance_tabp
  LDA #'\n'
  JSR write_d
  ; Output macro body
  JMP show_message         ; Tail call
.advance_tabp:
  TYA
  CLC
  ADCA16 TABP16, TABP16
  LDY #$00
  RTS
.macro_prefix:
  .asciiz "Macro: "

  .endif


; ============================================================================
; TIER 14: ENTRY POINT
; Program entry and main control flow
; ============================================================================

; Entry point
start:
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
.arg_loop:
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
.invalid_argument:
  JMP err_invalid_arg
.err_usage:
  JMP err_usage
.args_done:
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
  CP16 FWDREF16, PASS_1_FWDREF16
  .endif

  LDA #$FF
  STA PASS            ; Bit 7 = 1 (pass 2)
  JSR reset_fwdref_ptr
  JSR reset_scope_stack   ; Reset so pass 2 uses same scope IDs as pass 1
  JSR open_input
  JSR assemble_code

  .ifdef enable_debug
  ; Verify forward ref pointer matches pass 1
  CMP16 FWDREF16, PASS_1_FWDREF16
  BEQ .fwdref_ok
  ; Mismatch in ref counts
  JMP err_fwdref_tracking
.fwdref_ok:
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
  SBCI16 MEMP16, HEAP, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI msg_bytes
  ; Print forward reference count
  SHOW_MESSAGEI msg_fwdref_count
  ; Calculate forward ref count: (PASS_1_FWDREF16 - FWDREF_LIST) / 2
  SEC
  SBCI16 PASS_1_FWDREF16, FWDREF_LIST, TO_DECIMAL_VALUE16
  ; Divide by 2 (16-bit right shift)
  LSR16 TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_CHAR '\n'
.skip_debug_output:
  .endif

  ; All done, successfully
  BRK
  .byte 0               ; Success code


  .ifdef enable_debug
msg_heap_used:
  .asciiz "Heap used: "
msg_bytes:
  .asciiz " bytes\n"
msg_fwdref_count:
  .asciiz "Forward references forced to absolute: "
  .endif


HEAP:                   ; Heap goes after the program code


* = $FFFC
  .word start           ; Reset vector
  .word interrupt       ; Interrupt vector
