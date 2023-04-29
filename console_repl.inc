; Requires:
;   graphics_console.inc
;   command_table.inc

cr_repl:
.loop:
  jsr gc_show_prompt
  jsr gc_getline
  jsr cr_execute_command
  bcc .loop
  rts


; On exit C set if 'exit' command was encountered
cr_execute_command:
  ; remove the newline from the command buffer
  jsr gc_line_buffer_delete ; terminating 0
  jsr gc_line_buffer_delete ; newline
  lda #0
  jsr gc_line_buffer_add

  ; check for empty command line
  jsr cr_check_line_blank
  bcs .done

  lda #<GC_LINE_BUFFER
  ldx #>GC_LINE_BUFFER
  jsr ct_find_command
  bcc .not_found

  jsr gc_initialize_line_ptr
  stz GC_LINE_BUFFER

  lda CT_COMMAND_FUNCTION_PTR
  bne .not_exit
  lda CT_COMMAND_FUNCTION_PTR + 1
  bne .not_exit
; exit
  sec
  bra .return

.not_exit:
  jsr cr_jump_to_command_function
  bra .done

.not_found:
  lda #<.unknown_command_string
  ldx #>.unknown_command_string
  jsr gc_putstring

  jsr gc_show_line_buffer

  lda #ASCII_LF
  jsr gc_putchar
.done:
  clc
.return
  rts

.unknown_command_string: .asciiz "Unknown command: "


; On exit C set if line is blank, clear otherwise
;         X, Y are preserved
;         A is not preserved
cr_check_line_blank:
  jsr gc_initialize_line_ptr
.loop:
  lda (GC_LINE_PTR)
  beq .is_blank
  cmp #' '
  beq .blank_char
  cmp #ASCII_TAB
  beq .blank_char
; non-blank character
  clc
  bra .done
.blank_char
  inc GC_LINE_PTR
  bne .loop
  inc GC_LINE_PTR + 1
  bra .loop
.is_blank
  sec
.done
  rts


cr_jump_to_command_function:
  jmp (CT_COMMAND_FUNCTION_PTR)
