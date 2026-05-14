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
; $00..$0E reserved for the display helpers (display_string_immediate,
; display_decimal, display_string). $10+ is ours.
D_S_I_P              = $00 ; 2 bytes -- display_string_immediate
TEMP                 = $02 ; 1 byte  -- switch_to_space scratch (pre-bank-switch only)
TO_DECIMAL_PARAM     = $03 ; 10 bytes -- display_decimal (incl. result buf)
DISPLAY_STRING_PARAM = $0D ; 2 bytes -- display_string

; Merge-sort state. Cursors are laid out in three back-to-back 3-byte
; slots starting at $16 (offsets 0, 3, 6) so that advance_cursor_x can
; share one routine across all three via X-indexed ZP addressing.
LFSR                 = $10 ; 2 bytes
NEXT_A               = $12 ; 2 bytes -- cached element from source A
NEXT_B               = $14 ; 2 bytes -- cached element from source B
SRC_A_CFG            = $16 ; 1 byte
SRC_A_PTR            = $17 ; 2 bytes (16-bit address in $8000..$EFFE)
SRC_B_CFG            = $19 ; 1 byte  (= SRC_A_CFG + 3)
SRC_B_PTR            = $1A ; 2 bytes
TGT_CFG              = $1C ; 1 byte  (= SRC_A_CFG + 6)
TGT_PTR              = $1D ; 2 bytes
A_REM                = $1F ; 2 bytes -- elements left in current run-A
B_REM                = $21 ; 2 bytes
PASS_NUM             = $23 ; 1 byte
RUN_LEN              = $24 ; 2 bytes -- current L
CURRENT_SIDE_IS_A    = $26 ; 1 byte  -- 1 if pass reads from side A
CHUNK_REM            = $27 ; 2 bytes -- elements left in current 2L chunk
TOTAL_REM            = $29 ; 2 bytes -- elements left in pass
PROGRESS_TICK        = $2B ; 2 bytes -- counter for progress bar
PREV_ELEM            = $2D ; 2 bytes -- verify pass: previous element
EMIT_VAL             = $2F ; 2 bytes -- value to write through TGT cursor

CUR_OFFSET_SRC_A     = 0
CUR_OFFSET_SRC_B     = 3
CUR_OFFSET_TGT       = 6

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

  .ifdef SELFTEST_CURSORS
  jmp cursor_selftest
  .endif
  .ifdef SELFTEST_FILL
  jmp fill_selftest
  .endif

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


; ----- cursor primitives -----
;
; A cursor is a 3-byte ZP triple (CFG, PTR_LO, PTR_HI) that names an
; element-aligned position within a side's 4-bank region. PTR walks
; $8000..$EFFE within the current cfg; after the last element in a
; bank (PTR == $EFFE) the next advance produces PTR=$8000, CFG++.

; advance_cursor_x: advance the cursor at zero-page offset X by one
; 16-bit element. X must be 0 (SRC_A), 3 (SRC_B), or 6 (TGT).
; Wraps PTR=$F000 -> PTR=$8000 with CFG++.
advance_cursor_x:
  inc SRC_A_PTR,X
  bne .lo_no_carry
  inc SRC_A_PTR+1,X
.lo_no_carry:
  inc SRC_A_PTR,X
  bne .check_wrap
  inc SRC_A_PTR+1,X
.check_wrap:
  lda SRC_A_PTR+1,X
  cmp #$F0
  bne .done
  stz SRC_A_PTR,X
  lda #$80
  sta SRC_A_PTR+1,X
  inc SRC_A_CFG,X
.done:
  rts

; src_a_read_advance: switch to SRC_A's cfg, read 16-bit word at
; SRC_A_PTR into NEXT_A, then advance the cursor.
src_a_read_advance:
  lda SRC_A_CFG
  jsr switch_to_space
  ldy #0
  lda (SRC_A_PTR),Y
  sta NEXT_A
  iny
  lda (SRC_A_PTR),Y
  sta NEXT_A+1
  ldx #CUR_OFFSET_SRC_A
  jmp advance_cursor_x

src_b_read_advance:
  lda SRC_B_CFG
  jsr switch_to_space
  ldy #0
  lda (SRC_B_PTR),Y
  sta NEXT_B
  iny
  lda (SRC_B_PTR),Y
  sta NEXT_B+1
  ldx #CUR_OFFSET_SRC_B
  jmp advance_cursor_x

; tgt_write_advance: switch to TGT's cfg, write the 16-bit value in
; EMIT_VAL to *TGT_PTR, then advance the cursor.
tgt_write_advance:
  lda TGT_CFG
  jsr switch_to_space
  ldy #0
  lda EMIT_VAL
  sta (TGT_PTR),Y
  iny
  lda EMIT_VAL+1
  sta (TGT_PTR),Y
  ldx #CUR_OFFSET_TGT
  jmp advance_cursor_x


; ----- cursor selftest (built with -DSELFTEST_CURSORS=1) -----
;
; Exercises the wraparound case: write 4 distinct 16-bit values
; starting at cfg=$18, ptr=$EFFE (so the second write crosses into
; cfg=$19, ptr=$8000). Then read them back from the same start
; position and verify each one matches.
;
; Writes use the TGT cursor; reads use the SRC_A cursor.
  .ifdef SELFTEST_CURSORS

SELFTEST_START_CFG = $18
SELFTEST_START_PTR = $EFFE   ; deliberately near the bank boundary

cursor_selftest:
  ; -- write phase --
  lda #SELFTEST_START_CFG
  sta TGT_CFG
  lda #<SELFTEST_START_PTR
  sta TGT_PTR
  lda #>SELFTEST_START_PTR
  sta TGT_PTR+1

  ldx #0
.write_loop:
  ; EMIT_VAL = $ABCD + X (low byte gets X, high byte is $AB+X)
  txa
  clc
  adc #$CD
  sta EMIT_VAL
  txa
  clc
  adc #$AB
  sta EMIT_VAL+1
  phx
  jsr tgt_write_advance
  plx
  inx
  cpx #4
  bne .write_loop

  ; -- read-back phase --
  lda #SELFTEST_START_CFG
  sta SRC_A_CFG
  lda #<SELFTEST_START_PTR
  sta SRC_A_PTR
  lda #>SELFTEST_START_PTR
  sta SRC_A_PTR+1

  ldx #0
.read_loop:
  phx
  jsr src_a_read_advance
  plx

  ; Compare NEXT_A vs expected = $ABCD + X
  txa
  clc
  adc #$CD
  cmp NEXT_A
  bne .fail
  txa
  clc
  adc #$AB
  cmp NEXT_A+1
  bne .fail

  inx
  cpx #4
  bne .read_loop

  ; -- report PASS --
  jsr display_string_immediate
  .asciiz "Cursor: OK"
  stp

.fail:
  ; Clobbers X (= failure index) which we want to display.
  phx
  jsr display_string_immediate
  .asciiz "Cursor: FAIL@"
  plx
  txa
  jsr display_hex
  stp

  .endif


; ----- pseudo-random fill -----
;
; 16-bit Galois LFSR, polynomial $B400. Caller seeds LFSR before
; calling lfsr_step or fill_phase.
LFSR_SEED = $ACE1
LFSR_POLY_HI = $B4

; Step the LFSR by one bit. Cycles through all 65535 non-zero states.
; Preserves nothing.
lfsr_step:
  lsr LFSR+1
  ror LFSR
  bcc .skip_xor
  lda LFSR+1
  eor #LFSR_POLY_HI
  sta LFSR+1
.skip_xor:
  rts

; fill_phase: write N_ELEMENTS LFSR-sequence words through the TGT
; cursor (which the caller has positioned to the start of side A).
; Uses TOTAL_REM as a 16-bit countdown.
fill_phase:
  lda #<N_ELEMENTS
  sta TOTAL_REM
  lda #>N_ELEMENTS
  sta TOTAL_REM+1
.loop:
  lda TOTAL_REM
  ora TOTAL_REM+1
  beq .done
  ; emit current LFSR value as the next element
  lda LFSR
  sta EMIT_VAL
  lda LFSR+1
  sta EMIT_VAL+1
  jsr tgt_write_advance
  jsr lfsr_step
  ; decrement 16-bit TOTAL_REM
  lda TOTAL_REM
  bne .lo_nz
  dec TOTAL_REM+1
.lo_nz:
  dec TOTAL_REM
  bra .loop
.done:
  rts


; ----- fill selftest (built with -DSELFTEST_FILL=1) -----
;
; Runs fill_phase, then re-seeds the LFSR and walks the same side via
; SRC_A, comparing each element. On any mismatch displays
; 'Fill: FAIL@HHHH' (16-bit position); on full match 'Fill: OK'.
  .ifdef SELFTEST_FILL

fill_selftest:
  ; seed LFSR
  lda #<LFSR_SEED
  sta LFSR
  lda #>LFSR_SEED
  sta LFSR+1

  ; init TGT to start of side A (cfg=$18, ptr=$8000)
  lda #$18
  sta TGT_CFG
  stz TGT_PTR
  lda #$80
  sta TGT_PTR+1

  jsr fill_phase

  ; -- verify --
  ; re-seed LFSR, init SRC_A to side A start
  lda #<LFSR_SEED
  sta LFSR
  lda #>LFSR_SEED
  sta LFSR+1
  lda #$18
  sta SRC_A_CFG
  stz SRC_A_PTR
  lda #$80
  sta SRC_A_PTR+1
  ; reset counter, plus a separate position counter for FAIL display
  lda #<N_ELEMENTS
  sta TOTAL_REM
  lda #>N_ELEMENTS
  sta TOTAL_REM+1
  stz CHUNK_REM            ; 16-bit position counter
  stz CHUNK_REM+1
.verify_loop:
  lda TOTAL_REM
  ora TOTAL_REM+1
  beq .pass
  jsr src_a_read_advance
  lda NEXT_A
  cmp LFSR
  bne .fail
  lda NEXT_A+1
  cmp LFSR+1
  bne .fail
  jsr lfsr_step
  ; advance position
  inc CHUNK_REM
  bne .pos_no_carry
  inc CHUNK_REM+1
.pos_no_carry:
  ; decrement counter
  lda TOTAL_REM
  bne .lo_nz_v
  dec TOTAL_REM+1
.lo_nz_v:
  dec TOTAL_REM
  bra .verify_loop

.pass:
  jsr display_string_immediate
  .asciiz "Fill: OK"
  stp

.fail:
  jsr display_string_immediate
  .asciiz "Fill: FAIL@"
  lda CHUNK_REM+1
  jsr display_hex
  lda CHUNK_REM
  jsr display_hex
  stp

  .endif
