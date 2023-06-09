; Requires HT_KEY - the address of the key used for hash table operations
  .zeropage

HASH      DATA $00     ; 1 byte hash value
HTLPL     DATA $00     ; 2 byte pointer to low byte hash table
HTLPH     DATA $00     ; "
HTHPL     DATA $00     ; 2 byte pointer to high byte hash table
HTHPH     DATA $00     ; "

  .code

; Contains each byte $00-$FF exactly once in random order
scramble_table
  DATA $01 $20 $33 $1B $1C $16 $29 $1F $3A $75 $62 $42 $68 $79 $00 $52
  DATA $32 $0B $22 $77 $72 $71 $10 $59 $06 $4D $17 $37 $40 $0C $66 $21
  DATA $1E $43 $3E $30 $13 $07 $7E $44 $6C $58 $15 $1A $5A $24 $0F $7A
  DATA $7B $39 $4B $53 $70 $73 $19 $69 $55 $7D $4C $2C $7C $47 $23 $61
  DATA $56 $48 $74 $2F $76 $26 $2E $2B $6B $57 $12 $4F $25 $64 $0A $27
  DATA $50 $65 $5D $31 $2A $46 $6F $5F $67 $54 $18 $49 $05 $11 $03 $6E
  DATA $02 $0E $34 $5E $63 $08 $6D $14 $6A $0D $3B $4E $3D $60 $41 $38
  DATA $45 $7F $3F $3C $5C $2D $35 $51 $04 $28 $09 $4A $78 $1D $36 $5B


; Initialize a hash table
; On entry HTLPL;HTLPH, HTHPL;HTHOH point to the hash table
; On exit hash entries are initialized to 0 (empty table)
;         X is preserved
;         A, Y are not preserved
init_hash_table
  LDY# $00
  TYA                  ; A <- 0
iht_loop
  STAZ(),Y HTLPL
  STAZ(),Y HTHPL
  INY
  CPY# $80
  BNE iht_loop
  RTS


; On entry HT_KEY contains the token to calculate hash from
; On exit HASH contains the calculated hash value
;         X is preserved
;         A, Y are not preserved
calculate_hash
  TXA
  PHA
  LDA# $00
  STAZ HASH
  LDX# $00
ch_loop
  LDA,X HT_KEY
  BEQ ch_done
  AND# $7F
  EORZ HASH
  TAY
  LDA,Y scramble_table
  STAZ HASH
  INX
  JMP ch_loop
ch_done
  PLA
  TAX
  RTS
