write_b    = $F009

hash       = $0000
memp_l     = $0001
memp_h     = $0002
tabp_l     = $0003
tabp_h     = $0004
val_l      = $0005
val_h      = $0006
token      = $0007 ; Multiple bytes

hash_tab_l = $3000
hash_tab_h = $3100
heap       = $3200


* = $2000


; Contains each byte $00-$FF exactly once in random order
scramble_tab
  DATA $01 $70 $DE $CD $50 $E6 $D2 $27 $7E $DB $15 $F0 $AF $F1 $A6 $CA
  DATA $31 $03 $C4 $B5 $B3 $A2 $9C $19 $AB $2C $DA $46 $E8 $0F $59 $68
  DATA $09 $69 $9B $FA $3C $E1 $41 $5E $8A $1B $93 $6D $6E $22 $71 $44
  DATA $D4 $FC $24 $E3 $08 $6C $2B $EA $85 $B1 $E4 $FF $37 $F3 $5D $18
  DATA $25 $4E $8F $0C $9E $F9 $3D $58 $76 $81 $0A $0B $D5 $53 $2A $91
  DATA $66 $B0 $95 $98 $AE $77 $60 $26 $80 $55 $ED $5A $14 $78 $FE $F8
  DATA $7B $2D $34 $8E $13 $87 $89 $4B $2E $2F $BF $3B $65 $29 $47 $49
  DATA $D1 $F6 $BD $3F $32 $CE $1F $20 $30 $36 $39 $0E $5F $04 $C0 $A8
  DATA $A5 $BA $43 $F5 $F2 $4C $06 $C3 $D9 $DF $B9 $1D $B7 $E7 $4A $4D
  DATA $73 $3A $C9 $C1 $DC $92 $A3 $7A $96 $BB $EC $61 $11 $E9 $6A $1A
  DATA $42 $75 $51 $A1 $97 $C8 $17 $1C $00 $5C $72 $94 $16 $7C $D3 $84
  DATA $5B $EF $9A $45 $FD $9F $F7 $EB $9D $8D $A4 $C2 $6F $C7 $D0 $64
  DATA $38 $83 $D7 $BC $B6 $74 $CC $07 $AC $7F $33 $99 $3E $EE $28 $8C
  DATA $A7 $57 $62 $1E $86 $4F $40 $D8 $B2 $CF $A9 $E2 $AA $CB $D6 $A0
  DATA $10 $E5 $02 $35 $21 $79 $B8 $C6 $23 $0D $E0 $56 $8B $F4 $52 $12
  DATA $7D $05 $67 $54 $63 $90 $B4 $DD $AD $C5 $6B $82 $FB $BE $48 $88


display_hex_char
  CMP# $0A
  BCS ~display_hex_char_low
  ; Carry alrady clear
  ADC# "0"
  JMP write_b          ; Tail call
display_hex_char_low
  ; C already set
  SBC# $0A ; Subtract 10
  CLC
  ADC# "A"
  JMP write_b ; Tail call


display_hex
  PHA
  LSRA
  LSRA
  LSRA
  LSRA
  JSR display_hex_char
  PLA
  AND# $0F
  JMP display_hex_char ; Tail call


copy_token
  LDY# $FF
ct_loop
  INY
  LDAZ(),Y <tabp_l
  STA,Y token
  BNE ~ct_loop
  RTS


init_hash_tab
  LDX# $00
  LDA# $00
iht_loop
  STA,X hash_tab_l
  STA,X hash_tab_h
  INX
  BNE ~iht_loop
  

init_heap
  LDA# <heap
  STAZ <memp_l
  LDA# >heap
  STAZ <memp_h

  RTS


advance_heap
  TYA
  LDY# $00
  CLC
  ADCZ <memp_l
  STAZ <memp_l
  TYA
  ADCZ <memp_h
  STAZ <memp_h
  RTS


; On exit Z = 1 if entry is empty
hash_entry_empty
  LDAZ <hash
  TAY
  LDA,Y hash_tab_l
  BNE ~hee_done
  LDA,Y hash_tab_h
hee_done
  RTS


load_hash_entry
  LDAZ <hash
  TAY
  LDA,Y hash_tab_l
  STAZ <tabp_l
  LDA,Y hash_tab_h
  STAZ <tabp_h
  RTS


store_hash_entry
  LDAZ <hash
  TAY
  LDAZ <memp_l
  STA,Y hash_tab_l
  LDAZ <memp_h
  STA,Y hash_tab_h
  RTS


store_token
  LDY# $FF
st_loop
  INY
  LDA,Y token
  STAZ(),Y <memp_l
  BNE ~st_loop
  INY
  ; Store null pointer (pointer to next)
  LDA# $00
  STAZ(),Y <memp_l
  INY
  STAZ(),Y <memp_l
  INY
  ; Store value
  LDAZ <val_l
  STAZ(),Y <memp_l
  INY
  LDAZ <val_h
  STAZ(),Y <memp_l
  INY
  JMP advance_heap ; Tail call


calculate_hash
  LDA# $00
  STAZ <hash
  LDX# $00
ch_loop
  LDAZ,X <token
  BEQ ~ch_done
  EORZ <hash
  TAY
  LDA,Y scramble_tab
  STAZ <hash
  INX
  JMP ch_loop
ch_done
  RTS


start
  LDA# <message1
  STAZ <tabp_l
  LDA# >message1
  STAZ <tabp_h
  JSR copy_token

  LDY# $00
loop1
  LDA,Y token
  BEQ ~done1
  JSR write_b
  INY
  JMP loop1
done1

  JSR init_hash_tab
  JSR init_heap

  JSR calculate_hash
  LDAZ <hash
  JSR display_hex
  LDA# "\n"
  JSR write_b

  LDA# "P"
  STAZ <val_l
  LDA# "D"
  STAZ <val_h

  JSR store_hash_entry
  JSR store_token 

  LDA# <message2
  STAZ <tabp_l
  LDA# >message2
  STAZ <tabp_h
  JSR copy_token

  JSR calculate_hash

  LDA# "K"
  STAZ <val_l
  LDA# "M"
  STAZ <val_h

  JSR store_hash_entry
  JSR store_token 

  BRK $00 ; Completed successfully


message1
  DATA "Hello, world!\n" $00
message2
  DATA "Once upon a time\n" $00


  DATA start

