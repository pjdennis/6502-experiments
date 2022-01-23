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
KEY_F3         = $17
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

; These are made up (not part of PS/2 set 3)
KEY_PREVIOUSSONG = $91
KEY_PLAYPAUSE    = $92
KEY_STOPCD       = $93
KEY_NEXTSONG     = $94
KEY_MUTE         = $95
KEY_VOLUMEDOWN   = $96
KEY_VOLUMEUP     = $97


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
  .byte $15, KEY_PREVIOUSSONG
  .byte $34, KEY_PLAYPAUSE
  .byte $3b, KEY_STOPCD
  .byte $4d, KEY_NEXTSONG
  .byte $23, KEY_MUTE
  .byte $21, KEY_VOLUMEDOWN
  .byte $32, KEY_VOLUMEUP
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
  .byte KEY_TAB,        $09
  .byte KEY_GRAVE,      '`'
  .byte KEY_Q,          'q'
  .byte KEY_1,          '1'
  .byte KEY_Z,          'z'
  .byte KEY_S,          's'
  .byte KEY_A,          'a'
  .byte KEY_W,          'w'
  .byte KEY_2,          '2'
  .byte KEY_C,          'c'
  .byte KEY_X,          'x'
  .byte KEY_D,          'd'
  .byte KEY_E,          'e'
  .byte KEY_4,          '4'
  .byte KEY_3,          '3'
  .byte KEY_SPACE,      ' '
  .byte KEY_V,          'v'
  .byte KEY_F,          'f'
  .byte KEY_T,          't'
  .byte KEY_R,          'r'
  .byte KEY_5,          '5'
  .byte KEY_N,          'n'
  .byte KEY_B,          'b'
  .byte KEY_H,          'h'
  .byte KEY_G,          'g'
  .byte KEY_Y,          'y'
  .byte KEY_6,          '6'
  .byte KEY_M,          'm'
  .byte KEY_J,          'j'
  .byte KEY_U,          'u'
  .byte KEY_7,          '7'
  .byte KEY_8,          '8'
  .byte KEY_COMMA,      ','
  .byte KEY_K,          'k'
  .byte KEY_I,          'i'
  .byte KEY_O,          'o'
  .byte KEY_0,          '0'
  .byte KEY_9,          '9'
  .byte KEY_DOT,        '.'
  .byte KEY_SLASH,      '/'
  .byte KEY_L,          'l'
  .byte KEY_SEMICOLON,  ';'
  .byte KEY_P,          'p'
  .byte KEY_MINUS,      '-'
  .byte KEY_APOSTROPHE, "'"
  .byte KEY_LEFTBRACE,  '['
  .byte KEY_EQUAL,      '='
  .byte KEY_RIGHTBRACE, ']'
  .byte KEY_ENTER,      $0a
  .byte KEY_BACKSLASH,  '\'
  .byte KEY_BACKSPACE,  $08
  .byte $00


kb_kp_ascii_fixed_translation_table:
  .byte KEY_KPSLASH,    '/'
  .byte KEY_KPPLUS,     '+'
  .byte KEY_KPASTERISK, '*'
  .byte KEY_KPMINUS,    '-'
  .byte KEY_KPENTER,    $0a
  .byte $00

kb_kp_ascii_num_translation_table:
  .byte KEY_KP0,        '0'
  .byte KEY_KP1,        '1'
  .byte KEY_KP2,        '2'
  .byte KEY_KP3,        '3'
  .byte KEY_KP4,        '4'
  .byte KEY_KP5,        '5'
  .byte KEY_KP6,        '6'
  .byte KEY_KP7,        '7'
  .byte KEY_KP8,        '8'
  .byte KEY_KP9,        '9'
  .byte KEY_KPDOT,      '.'
  .byte $00
