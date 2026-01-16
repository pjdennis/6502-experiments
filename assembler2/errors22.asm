; Error handling and messages
;
; Requires:
;   TEMP                 - zero page location for temporary storage
;   TABP16               - zero page location for table pointer
;   CURR_LINE16          - zero page location for current line number
;   FS_P16               - zero page locations for file stack pointer
;   file_stack_empty     - function to check if file stack is empty
;   write_d              - function to write character to stderr
;   exit                 - function to exit program

  .include to_decimal22.asm

; Error labels - each triggers BRK with inline error code and message
err_label_not_found
  BRK
  .data $01 "Label not found" $00

err_duplicate_label
  BRK
  .data $02 "Duplicate label" $00

err_opcode_not_found
  BRK
  .data $03 "Opcode not found" $00

err_branch_out_of_range
  BRK
  .data $05 "Branch out of range" $00

err_value_out_of_range
  BRK
  .data $06 "Value out of range" $00

err_invalid_hex
  BRK
  .data $07 "Invalid hex" $00

err_pc_value_expected
  BRK
  .data $08 "PC value expected" $00

err_closing_quote_not_found
  BRK
  .data $09 "Closing quote not found" $00

err_cannot_move_pc_backwards
  BRK
  .data $0A "Cannot move PC backwards" $00

err_unknown_directive
  BRK
  .data $0B "Unknown directive" $00

err_filename_expected
  BRK
  .data $0C "Filename expected" $00

err_too_many_forward_refs
  BRK
  .data $13 "Too many forward references" $00

err_usage
  BRK
  .data $0D "Usage <assembler> <input> <output> [debug]" $00

err_invalid_arg
  BRK
  .data $10 "Invalid argument" $00

err_no_global_for_local
  BRK
  .data $0F "No global label for local" $00

err_invalid_addressing_mode
  BRK
  .data $11 "Invalid addressing mode for instruction" $00

err_invalid_char_literal
  BRK
  .data $12 "Invalid character literal" $00

err_invalid_operand
  BRK
  .data $14 "Invalid operand" $00

err_unexpected_text
  BRK
  .data $15 "Unexpected text after operand" $00

err_endif_without_ifdef
  BRK
  .data $17 ".endif without .ifdef" $00

err_unclosed_ifdef
  BRK
  .data $18 "Unclosed .ifdef" $00

err_label_expected
  BRK
  .data $19 "Label expected" $00

err_expected_shift
  BRK
  .data $1A "Expected << or >>" $00

err_macro_name_expected
  BRK
  .data $1B "Macro name expected" $00

err_macro_shadows_instruction
  BRK
  .data $1C "Macro name shadows instruction" $00

err_duplicate_macro
  BRK
  .data $1D "Duplicate macro definition" $00

err_endmacro_without_macro
  BRK
  .data $1E ".endmacro without .macro" $00

err_unclosed_macro
  BRK
  .data $1F "Unclosed .macro" $00

err_recursive_macro
  BRK
  .data $20 "Recursive macro invocation" $00

err_too_few_arguments
  BRK
  .data $21 "Too few macro arguments" $00

err_too_many_arguments
  BRK
  .data $22 "Too many macro arguments" $00

err_out_of_memory
  BRK
  .data $23 "Out of memory" $00

err_macro_nesting_too_deep
  BRK
  .data $24 "Macro nesting too deep" $00

err_too_many_macro_arguments
  BRK
  .data $25 "Too many macro arguments" $00

err_token_too_long
  BRK
  .data $26 "Token too long" $00

err_too_many_ifdefs
  BRK
  .data $27 "Too many .ifdef directives" $00

  .ifdef enable_debug
err_fwdref_tracking
  BRK
  .data $16 "Internal error - reference tracking" $00

err_no_file
  BRK
  .data $0E "Attempt to read with no file open" $00
  .endif


; Interrupt handler - processes BRK for error display
interrupt
; Retrieve pointer to error code
  TSX
  INX
  INX
  SEC
  LDA $0100,X
  SBC #$01
  STA TABP16
  INX
  LDA $0100,X
  SBC #$00
  STA TABP16+$01
; Retrieve error code and skip diagnostics if no error
  LDY #$00
  LDA (TABP16),Y
  BNE .error
  JMP exit ; Done
.error
; Save error code
  STA TEMP
; Close the ouptut file if open
  LDA CURR_OUT_FILE
  BEQ .output_not_open
  JSR close
  LDA #$00
  STA CURR_OUT_FILE
.output_not_open
; Print the "Error " message
  SET16 msg_error TABP16
  JSR show_message
; Print the error code in decimal
  LDA TEMP
  STA TO_DECIMAL_VALUE16
  LDA #$00
  STA TO_DECIMAL_VALUE16+$01
  JSR show_decimal
; Print the current file and line if any file is open
  JSR file_stack_empty
  BEQ .location_done
; Print the " in file " message
  SET16 msg_error_file TABP16
  JSR show_message
; Print the filename (at FS_P16)
  CP16 FS_P16 TABP16
  JSR show_message
; Print the " at line " message
  SET16 msg_error_line TABP16
  JSR show_message
; Print the current line in decimal
  CP16 CURR_LINE16 TO_DECIMAL_VALUE16
  JSR show_decimal
.location_done
; Print the ": " message
  LDA #':'
  JSR write_d
  LDA #' '
  JSR write_d
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
.traceback_done
; Print the final newline
  LDA #'\n'
  JSR write_d
; Load the error code so that it is returned
  LDA TEMP
  JMP exit ; Done

msg_error
  .data "Error " $00
msg_error_line
  .data " at line " $00
msg_error_file
  .data " in file " $00


; Show a decimal value to the error output
; On entry TO_DECIMAL_VALUE16 contains the value to show
; On exit X, Y are preserved
;         A is not preserved
;         Decimal number string stored at TO_DECIMAL_RESULT
show_decimal
  JSR to_decimal
  SET16 TO_DECIMAL_RESULT TABP16
  JMP show_message ; tail call


; Show message to the error output
; On entry TABP16 points to the zero-terminated message
; On exit X is preserved
;         A, Y are not preserved
show_message
  LDY #$00
.loop
  LDA (TABP16),Y
  BEQ .done
  JSR write_d
  INY
  JMP .loop
.done
  RTS


; Show include traceback - uses file stack API to walk include chain
; On entry FS_P16 points to current file stack entry
; On exit A, X, Y not preserved
;         TABP16;TABP16+$01 not preserved
;         All files in stack are closed
show_include_traceback
.loop
  ; Pop current entry (closes file, restores parent's handle and line)
  JSR pop_file_stack
  ; Check if stack is now empty (no more parents)
  JSR file_stack_empty
  BEQ .done
  ; Print newline
  LDA #'\n'
  JSR write_d
  ; Print "  included from " message
  SET16 msg_included_from TABP16
  JSR show_message
  ; Print filename (FS_P16 points to parent entry's name)
  CP16 FS_P16 TABP16
  JSR show_message
  ; Print ":"
  LDA #':'
  JSR write_d
  ; Print line number (CURR_LINE16 has line where include was)
  CP16 CURR_LINE16 TO_DECIMAL_VALUE16
  JSR show_decimal
  ; Continue to next parent
  JMP .loop
.done
  RTS

msg_included_from
  .data "  included from " $00
