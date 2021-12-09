; Translation tables to convert from PS/2 code set 2 to PS/2 code set 3. We use Code set 3
; for convenience as it has a single byte per key with no extended prefix
kb_normal_translation_table:
  .byte $14, $11
  .byte $11, $19
  .byte $77, $76
  .byte $7c, $7e
  .byte $7b, $84
  .byte $79, $7c
  .byte $76, $08
  .byte $05, $07
  .byte $06, $0f
  .byte $04, $17
  .byte $0c, $1f
  .byte $03, $27
  .byte $0b, $2f
  .byte $83, $37
  .byte $0a, $3f
  .byte $01, $47
  .byte $09, $4f
  .byte $78, $56
  .byte $07, $5e
  .byte $7e, $5f
  .byte $5d, $5c
  .byte $58, $14
  .byte $84, $57
  .byte $00

kb_extended_translation_table:
  .byte $11, $39
  .byte $14, $58
  .byte $70, $67
  .byte $71, $64
  .byte $6b, $61
  .byte $6c, $6e
  .byte $69, $65
  .byte $75, $63
  .byte $72, $60
  .byte $7d, $6f
  .byte $7a, $6d
  .byte $74, $6a
  .byte $4a, $77
  .byte $5a, $79
  .byte $1f, $8b
  .byte $27, $8c
  .byte $2f, $8d
  .byte $7e, $62
  .byte $3f, $7f
  .byte $37, $00
  .byte $5e, $00
  .byte $7c, $57
  .byte $00


; Translation table to convert from unshifted to shifted characters
; (excluding the alphabetic characters)
kb_shift_translation_table:
  .byte '`', '~'
  .byte '1', '!'
  .byte '2', '@'
  .byte '3', '#'
  .byte '4', '$'
  .byte '5', '%'
  .byte '6', '^'
  .byte '7', '&'
  .byte '8', '*'
  .byte '9', '('
  .byte '0', ')'
  .byte '-', '_'
  .byte '=', '+'
  .byte '[', '{'
  .byte ']', '}'
  .byte '\', '|'
  .byte ';', ':'
  .byte "'", '"'
  .byte ',', '<'
  .byte '.', '>'
  .byte '/', '?'
  .byte $00


; Mapping from PS/2 code set 3 to ASCII
key_codes_unshifted:
  .byte key_codes_unshifted_end - key_codes_unshifted
  .byte $00  ;  00
  .byte $00  ;  01
  .byte $00  ;  02
  .byte $00  ;  03
  .byte $00  ;  04
  .byte $00  ;  05
  .byte $00  ;  06
  .byte $00  ;  07  F1
  .byte $00  ;  08  Esc
  .byte $00  ;  09
  .byte $00  ;  0a
  .byte $00  ;  0b
  .byte $00  ;  0c
  .byte $00  ;  0d  Tab
  .byte $60  ;  0e  ` ~
  .byte $00  ;  0f  F2
  .byte $00  ;  10
  .byte $00  ;  11  LCtrl
  .byte $00  ;  12  LShift
  .byte $00  ;  13
  .byte $00  ;  14  CapsLock
  .byte $71  ;  15  q
  .byte $31  ;  16  1 !
  .byte $00  ;  17  F3
  .byte $00  ;  18
  .byte $00  ;  19  LAlt
  .byte $7a  ;  1a  z
  .byte $73  ;  1b  s
  .byte $61  ;  1c  a
  .byte $77  ;  1d  w
  .byte $32  ;  1e  2 @
  .byte $00  ;  1f  F4
  .byte $00  ;  20
  .byte $63  ;  21  c
  .byte $78  ;  22  x
  .byte $64  ;  23  d
  .byte $65  ;  24  e
  .byte $34  ;  25  4 $
  .byte $33  ;  26  3 #
  .byte $00  ;  27  F5
  .byte $00  ;  28
  .byte $20  ;  29  space
  .byte $76  ;  2a  v
  .byte $66  ;  2b  f
  .byte $74  ;  2c  t
  .byte $72  ;  2d  r
  .byte $35  ;  2e  5 %
  .byte $00  ;  2f  F6
  .byte $00  ;  30
  .byte $6e  ;  31  n
  .byte $62  ;  32  b
  .byte $68  ;  33  h
  .byte $67  ;  34  g
  .byte $79  ;  35  y
  .byte $36  ;  36  6 ^
  .byte $00  ;  37  F7
  .byte $00  ;  38
  .byte $00  ;  39  RAlt
  .byte $6d  ;  3a  m
  .byte $6a  ;  3b  j
  .byte $75  ;  3c  u
  .byte $37  ;  3d  7 &
  .byte $38  ;  3e  8 *
  .byte $00  ;  3f  F8
  .byte $00  ;  40
  .byte $2c  ;  41  , <
  .byte $6b  ;  42  k
  .byte $69  ;  43  i
  .byte $6f  ;  44  o
  .byte $30  ;  45  0 )
  .byte $39  ;  46  9 (
  .byte $00  ;  47  F9
  .byte $00  ;  48
  .byte $2e  ;  49  . >
  .byte $2f  ;  4a  / ?
  .byte $6c  ;  4b  l
  .byte $3b  ;  4c  ; :
  .byte $70  ;  4d  p
  .byte $2d  ;  4e  - _
  .byte $00  ;  4f  F10
  .byte $00  ;  50
  .byte $00  ;  51
  .byte $27  ;  52  ' "
  .byte $00  ;  53
  .byte $5b  ;  54  [ {
  .byte $3d  ;  55  = +
  .byte $00  ;  56  F11
  .byte $00  ;  57  PrtScr
  .byte $00  ;  58  RCtrl
  .byte $00  ;  59  RShift
  .byte $00  ;  5a  Enter
  .byte $5d  ;  5b  ] }
  .byte $5c  ;  5c  \ |
  .byte $00  ;  5d
  .byte $00  ;  5e  F12
  .byte $00  ;  5f  ScrollLock
  .byte $00  ;  60  Down
  .byte $00  ;  61  Left
  .byte $00  ;  62  Pause
  .byte $00  ;  63  Up
  .byte $00  ;  64  Delete
  .byte $00  ;  65  End
  .byte $08  ;  66  Backspace                  ********** Hand edited
  .byte $00  ;  67  Insert
  .byte $00  ;  68
  .byte $31  ;  69  KP-1 / End
  .byte $00  ;  6a  Right
  .byte $34  ;  6b  KP-4 / Left
  .byte $37  ;  6c  KP-7 / Home
  .byte $00  ;  6d  PgDn
  .byte $00  ;  6e  Home
  .byte $00  ;  6f  PgUp
  .byte $30  ;  70  KP-0 / Ins
  .byte $2e  ;  71  KP-. / Del
  .byte $32  ;  72  KP-2 / Down
  .byte $35  ;  73  KP-5
  .byte $36  ;  74  KP-6 / Right
  .byte $38  ;  75  KP-8 / Up
  .byte $00  ;  76  NumLock
  .byte $2f  ;  77  KP-/
  .byte $00  ;  78
  .byte $00  ;  79  KP-Enter
  .byte $33  ;  7a  KP-3 / PgDn
  .byte $00  ;  7b
  .byte $2b  ;  7c  KP-+
  .byte $39  ;  7d  KP-9 / PgUp
  .byte $2a  ;  7e  KP-*
  .byte $00  ;  7f  Sleep
  .byte $00  ;  80
  .byte $00  ;  81
  .byte $00  ;  82
  .byte $00  ;  83
  .byte $2d  ;  84  KP--
  .byte $00  ;  85
  .byte $00  ;  86
  .byte $00  ;  87
  .byte $00  ;  88
  .byte $00  ;  89
  .byte $00  ;  8a
  .byte $00  ;  8b  LWin (USB: LGUI)
  .byte $00  ;  8c  RWin (USB: RGUI)
  .byte $00  ;  8d  Menu
key_codes_unshifted_end:

