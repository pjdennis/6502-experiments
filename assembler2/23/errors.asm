; Error handling and messages
;
; Requires:
;   TEMP                 - zero page location for temporary storage
;   TABP16               - zero page location for table pointer
;   CURR_LINE16          - zero page location for current line number
;   CURR_OUT_FILE        - output file handle (for close on error)
;   FS_P16               - zero page locations for file stack pointer
;   FS_SRC_TYPE          - zero page location for source type (0=file, 1=memory)
;   file_stack_empty     - function to check if file stack is empty
;   pop_file_stack       - function to pop file stack entry
;   close                - function to close file handles
;   write_d              - function to write character to stderr
;   exit                 - function to exit program

  .include to_decimal.asm

; ============================================================================
; ERROR HANDLERS - Grouped by category with sequential error codes
; ============================================================================

; --- Label errors (1-4) ---
err_label_not_found:
  BRK
  .asciiz 1, "Label not found"

err_duplicate_label:
  BRK
  .asciiz 2, "Duplicate label"

err_no_global_for_local:
  BRK
  .asciiz 3, "No global label for local"

err_label_expected:
  BRK
  .asciiz 4, "Label expected"

; --- Symbol/Opcode errors (5) ---
err_opcode_not_found:
  BRK
  .asciiz 5, "Opcode not found"

; --- Value/Expression errors (6-13) ---
err_value_out_of_range:
  BRK
  .asciiz 6, "Value out of range"

err_invalid_hex:
  BRK
  .asciiz 7, "Invalid hex"

err_branch_out_of_range:
  BRK
  .asciiz 8, "Branch out of range"

err_invalid_operand:
  BRK
  .asciiz 9, "Invalid operand"

err_unexpected_text:
  BRK
  .asciiz 10, "Unexpected text after operand"

err_expected_shift:
  BRK
  .asciiz 11, "Expected << or >>"

err_invalid_char_literal:
  BRK
  .asciiz 12, "Invalid character literal"

err_invalid_addressing_mode:
  BRK
  .asciiz 13, "Invalid addressing mode"

; --- Directive errors (14-18) ---
err_unknown_directive:
  BRK
  .asciiz 14, "Unknown directive"

err_pc_value_expected:
  BRK
  .asciiz 15, "PC value expected"

err_cannot_move_pc_backwards:
  BRK
  .asciiz 16, "Cannot move PC backwards"

err_filename_expected:
  BRK
  .asciiz 17, "Filename expected"

err_closing_quote_not_found:
  BRK
  .asciiz 18, "Closing quote not found"

; --- Conditional assembly errors (19-21) ---
err_endif_without_ifdef:
  BRK
  .asciiz 19, ".endif without .ifdef"

err_unclosed_ifdef:
  BRK
  .asciiz 20, "Unclosed .ifdef"

err_too_many_ifdefs:
  BRK
  .asciiz 21, "Too many .ifdef directives"

; --- Macro errors (22-31) ---
err_macro_name_expected:
  BRK
  .asciiz 22, "Macro name expected"

err_macro_shadows_instruction:
  BRK
  .asciiz 23, "Macro name shadows instruction"

err_duplicate_macro:
  BRK
  .asciiz 24, "Duplicate macro definition"

err_endmacro_without_macro:
  BRK
  .asciiz 25, ".endmacro without .macro"

err_unclosed_macro:
  BRK
  .asciiz 26, "Unclosed .macro"

err_nested_macro_definition:
  BRK
  .asciiz 27, "Nested macro definition"

err_recursive_macro:
  BRK
  .asciiz 28, "Recursive macro invocation"

err_too_few_arguments:
  BRK
  .asciiz 29, "Too few macro arguments"

err_too_many_arguments:
  BRK
  .asciiz 30, "Too many macro arguments"

err_macro_nesting_too_deep:
  BRK
  .asciiz 31, "Macro nesting too deep"

; --- Resource limit errors (32-34) ---
err_out_of_memory:
  BRK
  .asciiz 32, "Out of memory"

err_token_too_long:
  BRK
  .asciiz 33, "Token too long"

err_too_many_forward_refs:
  BRK
  .asciiz 34, "Too many forward references"

; --- Memory section errors (35) ---
err_zeropage_overflow:
  BRK
  .asciiz 35, "Zero page overflow"

; --- File I/O errors (36) ---
err_file_not_found:
  BRK
  .asciiz 36, "File not found"

; --- Syntax errors (37) ---
err_comma_expected:
  BRK
  .asciiz 37, "Comma expected"

; --- Zeropage directive errors (38-39) ---
err_asciiz_in_zeropage:
  BRK
  .asciiz 38, ".asciiz not allowed in .zeropage"

err_operand_in_zeropage:
  BRK
  .asciiz 39, "Operand not allowed on .byte/.word in .zeropage"

; --- Command line/usage errors (240-241) ---
err_usage:
  BRK
  .asciiz 240, "Usage: <assembler> <input> <output> [debug]"

err_invalid_arg:
  BRK
  .asciiz 241, "Invalid argument"

; --- Debug/internal errors (254-255, debug build only) ---
  .ifdef enable_debug
err_no_file:
  BRK
  .asciiz 254, "Attempt to read with no file open"

err_fwdref_tracking:
  BRK
  .asciiz 255, "Internal error - reference tracking"
  .endif


  .macro SHOW_MESSAGEI addr
  SET16 addr, TABP16
  JSR show_message
  .endmacro

  .macro SHOW_MESSAGE ptr
  CP16 ptr, TABP16
  JSR show_message
  .endmacro

  .macro SHOW_CHAR val
  LDA #val
  JSR write_d
  .endmacro


; Interrupt handler - processes BRK for error display
interrupt:
; Retrieve pointer to error code
  TSX
  SEC
  LDA $0102,X
  SBC #$01
  STA TABP16
  LDA $0103,X
  SBC #$00
  STA TABP16+$01
; Retrieve error code and skip diagnostics if no error
  LDY #$00
  LDA (TABP16),Y
  BNE .error
  JMP exit ; Done
.error:
; Save error code
  STA TEMP
; Close the ouptut file if open
  LDA CURR_OUT_FILE
  BEQ .output_not_open
  JSR close
  LDA #$00
  STA CURR_OUT_FILE
.output_not_open:
; Print the "Error " message
  SHOW_MESSAGEI msg_error
; Print the error code in decimal
  LDA TEMP
  STA TO_DECIMAL_VALUE16
  LDA #$00
  STA TO_DECIMAL_VALUE16+$01
  JSR show_decimal
; Print the current file and line if any file is open
  JSR file_stack_empty
  BEQ .location_done
; Print " in file " or " in macro " based on source type
  LDA FS_SRC_TYPE
  BNE .in_macro
  SHOW_MESSAGEI msg_error_file
  JMP .show_source_name
.in_macro:
  SHOW_MESSAGEI msg_error_macro
.show_source_name:
; Print the filename (at FS_P16)
  SHOW_MESSAGE FS_P16
; Print the " at line " message
  SHOW_MESSAGEI msg_error_line
; Print the current line in decimal
  CP16 CURR_LINE16, TO_DECIMAL_VALUE16
  JSR show_decimal
.location_done:
; Print the ": " message
  SHOW_CHAR ':'
  SHOW_CHAR ' '
; Retrieve pointer to the error message and show it
  TSX
  LDA $0102,X
  STA TABP16
  LDA $0103,X
  STA TABP16+$01
  JSR show_message
; Print include traceback (if any files open)
  JSR file_stack_empty
  BEQ .traceback_done
  JSR show_include_traceback
.traceback_done:
; Print the final newline
  SHOW_CHAR '\n'
; Load the error code so that it is returned
  LDA TEMP
  JMP exit ; Done

msg_error:
  .asciiz "Error "
msg_error_line:
  .asciiz " at line "
msg_error_file:
  .asciiz " in file "


; Show a decimal value to the error output
; On entry TO_DECIMAL_VALUE16 contains the value to show
; On exit X, Y are preserved
;         A is not preserved
;         Decimal number string stored at TO_DECIMAL_RESULT
show_decimal:
  JSR to_decimal
  SET16 TO_DECIMAL_RESULT, TABP16
  JMP show_message ; tail call


; Show message to the error output
; On entry TABP16 points to the zero-terminated message
; On exit (TABP16),Y points to the zero terminator
;         X is preserved
;         A is not preserved
show_message:
  LDY #$00
.loop:
  LDA (TABP16),Y
  BEQ .done
  JSR write_d
  INY
  BNE .loop
  INC TABP16+$01
  BNE .loop        ; Always taken
.done:
  RTS


; Show traceback - uses file stack API to walk include/expansion chain
; On entry FS_P16 points to current file stack entry
; On exit A, X, Y not preserved
;         TABP16;TABP16+$01 not preserved
;         All files in stack are closed
show_include_traceback:
.loop:
  ; Save child source type before popping
  LDA FS_SRC_TYPE
  PHA
  ; Pop current entry (closes file, restores parent's handle and line)
  JSR pop_file_stack
  ; Check if stack is now empty (no more parents)
  JSR file_stack_empty
  BEQ .done_cleanup
  ; Print newline
  SHOW_CHAR '\n'
  ; Print verb based on child type (saved on stack)
  PLA
  BEQ .verb_included
  ; Child was macro → "expanded from"
  SHOW_MESSAGEI msg_expanded_from
  JMP .show_parent
.verb_included:
  ; Child was file → "included from"
  SHOW_MESSAGEI msg_included_from
.show_parent:
  ; Check parent type for "macro " prefix
  LDA FS_SRC_TYPE
  BEQ .parent_is_file
  SHOW_MESSAGEI msg_macro_prefix
.parent_is_file:
  ; Print name (FS_P16 points to parent entry's name)
  SHOW_MESSAGE FS_P16
  ; Print ":"
  SHOW_CHAR ':'
  ; Print line number (CURR_LINE16 has line where include was)
  CP16 CURR_LINE16, TO_DECIMAL_VALUE16
  JSR show_decimal
  ; Continue to next parent
  JMP .loop
.done_cleanup:
  PLA                    ; Clean up saved child type from stack
.done:
  RTS

msg_error_macro:
  .asciiz " in macro "
msg_included_from:
  .asciiz "  included from "
msg_expanded_from:
  .asciiz "  expanded from "
msg_macro_prefix:
  .asciiz "macro "
