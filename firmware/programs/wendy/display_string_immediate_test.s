  .include base_config_v1.inc

DSIPL  = $00
DSIPH  = $01

  .org $2000
  jmp program_entry

  .include display_update_routines.inc

program_entry:
  jsr display_string_immediate
  .asciiz "Hello, "

  jsr display_string_immediate
  .asciiz "world!"
  
wait:
  wai
  bra wait

; On exit A is not preserved
display_string_immediate:
   pla                   ; get low part of (string address - 1)
   sta DSIPL
   pla                   ; get high part of (string address - 1)
   sta DSIPH
   bra .2
.1 jsr display_character ; output a string char
.2 inc DSIPL             ; advance the string pointer
   bne .3
   inc DSIPH
.3 lda (DSIPL)           ; get string char
   bne .1                ; output and continue if not NUL
   lda DSIPH
   pha
   lda DSIPL
   pha
   rts                   ; proceed at code following the NUL
