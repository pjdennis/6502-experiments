KEY_RESERVED   = $00
KEY_F1         = $07
KEY_ESC        = $08
KEY_TAB        = $0d
KEY_GRAVE      = $0e ; Back tick
KEY_F2         = $0f
KEY_LEFTCTRL   = $11
KEY_LEFTSHIFT  = $12
KEY_CAPSLOCK   = $14
KEY_Q          = $15
KEY_1          = $16
KEY_F3         = $16
KEY_LEFTALT    = $19
KEY_Z          = $1a
KEY_S          = $1b
KEY_A          = $1c
KEY_W          = $1d
KEY_2          = $1e
KEY_F4         = $1f
KEY_C          = $21
KEY_X          = $22
KEY_D          = $23
KEY_E          = $24
KEY_4          = $25
KEY_3          = $26
KEY_F5         = $27
KEY_SPACE      = $29
KEY_V          = $2a
KEY_F          = $2b
KEY_T          = $2c
KEY_R          = $2d
KEY_5          = $2e
KEY_F6         = $2f
KEY_N          = $31
KEY_B          = $32
KEY_H          = $33
KEY_G          = $34
KEY_Y          = $35
KEY_6          = $36
KEY_F7         = $37
KEY_RIGHTALT   = $39
KEY_M          = $3a
KEY_J          = $3b
KEY_U          = $3c
KEY_7          = $3d
KEY_8          = $3e
KEY_F8         = $3f
KEY_COMMA      = $41
KEY_K          = $42
KEY_I          = $43
KEY_O          = $44
KEY_0          = $45
KEY_9          = $46
KEY_F9         = $47
KEY_DOT        = $49 ; Period
KEY_SLASH      = $4a
KEY_L          = $4b
KEY_SEMICOLON  = $4c
KEY_P          = $4d
KEY_MINUS      = $4e
KEY_F10        = $4f
KEY_APOSTROPHE = $52
KEY_LEFTBRACE  = $54
KEY_EQUAL      = $55
KEY_F11        = $56
KEY_SYSRQ      = $57 ; Print screen
KEY_RIGHTCTRL  = $58
KEY_RIGHTSHIFT = $59
KEY_ENTER      = $5a
KEY_RIGHTBRACE = $5b
KEY_BACKSLASH  = $5c
KEY_F12        = $5e
KEY_SCROLLLOCK = $5f
KEY_DOWN       = $60
KEY_LEFT       = $61
KEY_PAUSE      = $62
KEY_UP         = $63
KEY_DELETE     = $64
KEY_END        = $65
KEY_BACKSPACE  = $66
KEY_INSERT     = $67
KEY_KP1        = $69
KEY_RIGHT      = $6a
KEY_KP4        = $6b
KEY_KP7        = $6c
KEY_PAGEDOWN   = $6d
KEY_HOME       = $6e
KEY_PAGEUP     = $6f
KEY_KP0        = $70
KEY_KPDOT      = $71
KEY_KP2        = $72
KEY_KP5        = $73
KEY_KP6        = $74
KEY_KP8        = $75
KEY_NUMLOCK    = $76
KEY_KPSLASH    = $77
KEY_KPENTER    = $79
KEY_KP3        = $7a
KEY_KPPLUS     = $7c
KEY_KP9        = $7d
KEY_KPASTERISK = $7e
KEY_SLEEP      = $7f
KEY_KPMINUS    = $84
KEY_LEFTMETA   = $8b ; Left Windows / GUI
KEY_RIGHTMETA  = $8c ; Right Windows / GUI
KEY_MENU       = $8d


; Translation tables to convert from PS/2 code set 2 to PS/2 code set 3. We use Code set 3
; for convenience as it has a single byte per key with no extended prefix
kb_normal_translation_table:
  .byte $14, KEY_LEFTCTRL
  .byte $11, KEY_LEFTALT
  .byte $77, KEY_NUMLOCK
  .byte $7c, KEY_KPASTERISK
  .byte $7b, KEY_KPMINUS
  .byte $79, KEY_KPPLUS
  .byte $76, KEY_ESC
  .byte $05, KEY_F1
  .byte $06, KEY_F2
  .byte $04, KEY_F3
  .byte $0c, KEY_F4
  .byte $03, KEY_F5
  .byte $0b, KEY_F6
  .byte $83, KEY_F7
  .byte $0a, KEY_F8
  .byte $01, KEY_F9
  .byte $09, KEY_F10
  .byte $78, KEY_F11
  .byte $07, KEY_F12
  .byte $7e, KEY_SCROLLLOCK
  .byte $5d, KEY_BACKSLASH
  .byte $58, KEY_CAPSLOCK
  .byte $84, KEY_SYSRQ
  .byte $00

kb_extended_translation_table:
  .byte $11, KEY_RIGHTALT
  .byte $14, KEY_RIGHTCTRL
  .byte $70, KEY_INSERT
  .byte $71, KEY_DELETE
  .byte $6b, KEY_LEFT
  .byte $6c, KEY_HOME
  .byte $69, KEY_END
  .byte $75, KEY_UP
  .byte $72, KEY_DOWN
  .byte $7d, KEY_PAGEUP
  .byte $7a, KEY_PAGEDOWN
  .byte $74, KEY_RIGHT
  .byte $4a, KEY_KPSLASH
  .byte $5a, KEY_KPENTER
  .byte $1f, KEY_LEFTMETA
  .byte $27, KEY_RIGHTMETA
  .byte $2f, KEY_MENU
  .byte $7e, KEY_PAUSE
  .byte $3f, KEY_SLEEP
  .byte $37, KEY_RESERVED ; Power (not mapped)
  .byte $5e, KEY_RESERVED ; Wake  (not mapped)
  .byte $7c, KEY_SYSRQ
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


kb_ascii_translation_table:

; Mapping from PS/2 code set 3 to ASCII
kb_code_to_ascii_lookup_table:
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
  .byte $09  ;  0d  Tab
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
kb_code_to_ascii_lookup_table_end:

