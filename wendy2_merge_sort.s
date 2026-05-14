; wendy2 merge-sort demo (skeleton phase).
;
; See plan-for-wendy2-merge-sort-demo.md for the full design. This file
; is built up TDD-style across multiple commits; right now it just sets
; up the machine, shows a banner with the build-time N_ELEMENTS, and
; halts via STP. Subsequent commits add the fill, sort, and verify
; phases.
;
; Build-time knobs (override on the vasm command line with -DNAME=VAL):
;   N_ELEMENTS  number of 16-bit values to sort. Default 57344 = 0xE000
;               (the full 4-bank side; see plan). Smaller values let
;               tests iterate quickly: 64 fits in one bank, 16384 spans
;               two banks, 32768 spans three, 57344 spans four.

  .ifndef N_ELEMENTS
N_ELEMENTS = 57344
  .endif

  .include base_config_wendy2c.inc

; ----- zero page layout -----
; $00..$0C reserved for the display helpers (display_string_immediate,
; display_decimal, display_string). $10+ is ours.
D_S_I_P              = $00 ; 2 bytes -- display_string_immediate
TEMP                 = $02 ; 1 byte  -- switch_to_space + display helpers
TO_DECIMAL_PARAM     = $03 ; 10 bytes -- display_decimal (incl. result buf)
DISPLAY_STRING_PARAM = $0D ; 2 bytes -- display_string

  .org $4000
  jmp program_entry

  ; delay_routines first so timing loops don't cross a page boundary
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc
  .include display_decimal.inc
  .include display_string_immediate.inc

; switch_to_space scratch lives in fixed RAM ($4000-$7FFF), NOT in ZP.
; ZP is part of the banked lower 16K and gets wiped on bank changes,
; which would clobber a return address mid-routine.
switch_to_space_return: .word 0
switch_to_space_space:  .byte 0


program_entry:
  ; Pick a stable lower bank (bank 2) + upper bank 0. cfg %11000 = $18.
  ; This is the C3=1 group, the one the PLD fix in commit 8a8eb82 made
  ; valid for upper-RAM access. The fill/sort phases will only ever
  ; touch cfgs $18..$1F, so the lower 16K mapping stays put and ZP
  ; remains stable across every switch_to_space call.
  lda #%11000
  jsr switch_to_space
  ldx #$ff
  txs

  jsr clear_display

  jsr display_string_immediate
  .asciiz "Merge Sort"

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz "N="
  lda #<N_ELEMENTS
  ldx #>N_ELEMENTS
  jsr display_decimal
  jsr display_string_immediate
  .asciiz " Ready"

  stp


; switch_to_space: change the bank-select register to the cfg in A,
; preserving A, X, Y. Lifted from verification_wendy2c.s.
switch_to_space:
  sta switch_to_space_space
  pla
  sta switch_to_space_return
  pla
  sta switch_to_space_return + 1

  lda switch_to_space_space
  and #BANK_MASK
  sta TEMP
  lda BANK_PORT
  and #~BANK_MASK
  ora TEMP
  sta BANK_PORT

  lda switch_to_space_return + 1
  pha
  lda switch_to_space_return
  pha
  lda switch_to_space_space
  rts
