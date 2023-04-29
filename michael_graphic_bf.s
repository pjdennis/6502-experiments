  .include base_config_v2.inc

;TODO ran into a bug that I can't recreate: scrolled past bottom; entered several
;lines of text; backspaced and it didn't stop at the cursor start position

INTERRUPT_ROUTINE        = $3f00

; Zero page allocations
GCF_ZERO_PAGE_BASE       = $00
BF_ZERO_PAGE_BASE        = GCF_ZERO_PAGE_STOP

bf_getchar               = gc_getchar
bf_putchar               = gc_putchar

; Other memory allocations
SIMPLE_BUFFER            = $0200 ; 256 bytes
GC_LINE_BUFFER           = $0300 ; GD_CHAR_ROWS * GD_CHAR_COLS = 400 bytes including terminating 0

cells                    = GC_LINE_BUFFER_STOP
cellsEnd                 = cells + 1024
code                     = cellsEnd
codeEnd                  = $2000 

  .org $2000                     ; Loader loads programs to this address
  jmp initialize_machine         ; Initialize hardware and then jump to program_start

  ; The initialize_machine routine in this include will set up hardware registers and then
  ; jump to program_start. We do not call a subroutine because for some machine designs the
  ; stack is not usable until after the hardware registers have been initialized
  .include delay_routines.inc
  .include initialize_machine_v2.inc
  .include graphics_console_full.inc
  .include brainfotc.inc


CT_COMMANDS:
  .asciiz "exit"
                      .word 0
  .byte 0

 
program_start:
  ; Initialize stack
  ldx #$ff
  txs

  jsr gcf_init

;  jsr cr_repl

  jsr main


;  lda #<.exit_message
;  ldx #>.exit_message
;  jsr gc_putstring

  stp

.exit_message: .asciiz "Exited.\n"
