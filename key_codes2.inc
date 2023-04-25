  .include ASCII.inc

KP_OFFSET   = %10000000
FN_OFFSET   = %11000000
MISC_OFFSET = FN_OFFSET + 13

KEY_F1         = 1 + FN_OFFSET
KEY_ESC        = 0 + MISC_OFFSET
KEY_TAB        = ASCII_TAB
KEY_GRAVE      = '`'
KEY_F2         = 2 + FN_OFFSET
KEY_LEFTCTRL   = 1 + MISC_OFFSET
KEY_LEFTSHIFT  = 2 + MISC_OFFSET
KEY_CAPSLOCK   = 3 + MISC_OFFSET
KEY_Q          = 'q'
KEY_1          = '1'
KEY_F3         = 3 + FN_OFFSET
KEY_LEFTALT    = 4 + MISC_OFFSET
KEY_Z          = 'z'
KEY_S          = 's'
KEY_A          = 'a'
KEY_W          = 'w'
KEY_2          = '2'
KEY_F4         = 4 + FN_OFFSET
KEY_C          = 'c'
KEY_X          = 'x'
KEY_D          = 'd'
KEY_E          = 'e'
KEY_4          = '4'
KEY_3          = '3'
KEY_F5         = 5 + FN_OFFSET
KEY_SPACE      = ' '
KEY_V          = 'v'
KEY_F          = 'f'
KEY_T          = 't'
KEY_R          = 'r'
KEY_5          = '5'
KEY_F6         = 6 + FN_OFFSET
KEY_N          = 'n'
KEY_B          = 'b'
KEY_H          = 'h'
KEY_G          = 'g'
KEY_Y          = 'y'
KEY_6          = '6'
KEY_F7         = 7 + FN_OFFSET
KEY_RIGHTALT   = 5 + MISC_OFFSET
KEY_M          = 'm'
KEY_J          = 'j'
KEY_U          = 'u'
KEY_7          = '7'
KEY_8          = '8'
KEY_F8         = 8 + FN_OFFSET
KEY_COMMA      = ','
KEY_K          = 'k'
KEY_I          = 'i'
KEY_O          = 'o'
KEY_0          = '0'
KEY_9          = '9'
KEY_F9         = 9 + FN_OFFSET
KEY_DOT        = '.'
KEY_SLASH      = '/'
KEY_L          = 'l'
KEY_SEMICOLON  = ';'
KEY_P          = 'p'
KEY_MINUS      = '-'
KEY_F10        = 10 + FN_OFFSET
KEY_APOSTROPHE = "'"
KEY_LEFTBRACE  = '['
KEY_EQUAL      = '='
KEY_F11        = 11 + FN_OFFSET
KEY_SYSRQ      = 6 + MISC_OFFSET ; Print screen
KEY_RIGHTCTRL  = 7 + MISC_OFFSET
KEY_RIGHTSHIFT = 8 + MISC_OFFSET
KEY_ENTER      = ASCII_LF
KEY_RIGHTBRACE = ']'
KEY_BACKSLASH  = '\\'
KEY_F12        = 12 + FN_OFFSET
KEY_SCROLLLOCK = 9 + MISC_OFFSET
KEY_DOWN       = 10 + MISC_OFFSET
KEY_LEFT       = 11 + MISC_OFFSET
KEY_PAUSE      = 12 + MISC_OFFSET
KEY_UP         = 13 + MISC_OFFSET
KEY_DELETE     = 14 + MISC_OFFSET
KEY_END        = 15 + MISC_OFFSET
KEY_BACKSPACE  = ASCII_BACKSPACE
KEY_INSERT     = 16 + MISC_OFFSET
KEY_KP1        = '1' + KP_OFFSET
KEY_RIGHT      = 17 + MISC_OFFSET
KEY_KP4        = '4' + KP_OFFSET
KEY_KP7        = '7' + KP_OFFSET
KEY_PAGEDOWN   = 18 + MISC_OFFSET
KEY_HOME       = 19 + MISC_OFFSET
KEY_PAGEUP     = 20 + MISC_OFFSET
KEY_KP0        = '0' + KP_OFFSET
KEY_KPDOT      = '.' + KP_OFFSET
KEY_KP2        = '2' + KP_OFFSET
KEY_KP5        = '5' + KP_OFFSET
KEY_KP6        = '6' + KP_OFFSET
KEY_KP8        = '8' + KP_OFFSET
KEY_NUMLOCK    = 21 + MISC_OFFSET
KEY_KPSLASH    = '/' + KP_OFFSET
KEY_KPENTER    = ASCII_LF + KP_OFFSET
KEY_KP3        = '3' + KP_OFFSET
KEY_KPPLUS     = '+' + KP_OFFSET
KEY_KP9        = '9' + KP_OFFSET
KEY_KPASTERISK = '*' + KP_OFFSET
KEY_SLEEP      = 22 + MISC_OFFSET
KEY_KPMINUS    = '-' + KP_OFFSET
KEY_LEFTMETA   = 23 + MISC_OFFSET ; Left Windows / GUI
KEY_RIGHTMETA  = 24 + MISC_OFFSET ; Right Windows / GUI
KEY_MENU       = 25 + MISC_OFFSET

; These are made up (not part of PS/2 set 3)
KEY_PREVIOUSSONG = 26 + MISC_OFFSET
KEY_PLAYPAUSE    = 27 + MISC_OFFSET
KEY_STOPCD       = 28 + MISC_OFFSET
KEY_NEXTSONG     = 29 + MISC_OFFSET
KEY_MUTE         = 30 + MISC_OFFSET
KEY_VOLUMEDOWN   = 31 + MISC_OFFSET
KEY_VOLUMEUP     = 32 + MISC_OFFSET
KEY_POWER        = 33 + MISC_OFFSET
KEY_WAKE         = 34 + MISC_OFFSET


; Translation tables to convert from PS/2 code set 2 to ASCII-derived code set.
kb_normal_translation_table:
  .byte $01, KEY_F9
  .byte $03, KEY_F5
  .byte $04, KEY_F3
  .byte $05, KEY_F1
  .byte $06, KEY_F2
  .byte $07, KEY_F12
  .byte $09, KEY_F10
  .byte $0a, KEY_F8
  .byte $0b, KEY_F6
  .byte $0c, KEY_F4
  .byte $0d, KEY_TAB
  .byte $0e, KEY_GRAVE
  .byte $11, KEY_LEFTALT
  .byte $12, KEY_LEFTSHIFT
  .byte $14, KEY_LEFTCTRL
  .byte $15, KEY_Q
  .byte $16, KEY_1
  .byte $1a, KEY_Z
  .byte $1b, KEY_S
  .byte $1c, KEY_A
  .byte $1d, KEY_W
  .byte $1e, KEY_2
  .byte $21, KEY_C
  .byte $22, KEY_X
  .byte $23, KEY_D
  .byte $24, KEY_E
  .byte $25, KEY_4
  .byte $26, KEY_3
  .byte $29, KEY_SPACE
  .byte $2a, KEY_V
  .byte $2b, KEY_F
  .byte $2c, KEY_T
  .byte $2d, KEY_R
  .byte $2e, KEY_5
  .byte $31, KEY_N
  .byte $32, KEY_B
  .byte $33, KEY_H
  .byte $34, KEY_G
  .byte $35, KEY_Y
  .byte $36, KEY_6
  .byte $3a, KEY_M
  .byte $3b, KEY_J
  .byte $3c, KEY_U
  .byte $3d, KEY_7
  .byte $3e, KEY_8
  .byte $41, KEY_COMMA
  .byte $42, KEY_K
  .byte $43, KEY_I
  .byte $44, KEY_O
  .byte $45, KEY_0
  .byte $46, KEY_9
  .byte $49, KEY_DOT
  .byte $4a, KEY_SLASH
  .byte $4b, KEY_L
  .byte $4c, KEY_SEMICOLON
  .byte $4d, KEY_P
  .byte $4e, KEY_MINUS
  .byte $52, KEY_APOSTROPHE
  .byte $54, KEY_LEFTBRACE
  .byte $55, KEY_EQUAL
  .byte $58, KEY_CAPSLOCK
  .byte $59, KEY_RIGHTSHIFT
  .byte $5a, KEY_ENTER
  .byte $5b, KEY_RIGHTBRACE
  .byte $5d, KEY_BACKSLASH
  .byte $66, KEY_BACKSPACE
  .byte $69, KEY_KP1
  .byte $6b, KEY_KP4
  .byte $6c, KEY_KP7
  .byte $70, KEY_KP0
  .byte $71, KEY_KPDOT
  .byte $72, KEY_KP2
  .byte $73, KEY_KP5
  .byte $74, KEY_KP6
  .byte $75, KEY_KP8
  .byte $76, KEY_ESC
  .byte $77, KEY_NUMLOCK
  .byte $78, KEY_F11
  .byte $79, KEY_KPPLUS
  .byte $7a, KEY_KP3
  .byte $7b, KEY_KPMINUS
  .byte $7c, KEY_KPASTERISK
  .byte $7d, KEY_KP9
  .byte $7e, KEY_SCROLLLOCK
  .byte $83, KEY_F7
  .byte $84, KEY_SYSRQ
  .byte $00

kb_extended_translation_table:
  .byte $11, KEY_RIGHTALT
  .byte $14, KEY_RIGHTCTRL
  .byte $15, KEY_PREVIOUSSONG
  .byte $1f, KEY_LEFTMETA
  .byte $21, KEY_VOLUMEDOWN
  .byte $23, KEY_MUTE
  .byte $27, KEY_RIGHTMETA
  .byte $2f, KEY_MENU
  .byte $32, KEY_VOLUMEUP
  .byte $34, KEY_PLAYPAUSE
  .byte $37, KEY_POWER
  .byte $3b, KEY_STOPCD
  .byte $3f, KEY_SLEEP
  .byte $4a, KEY_KPSLASH
  .byte $4d, KEY_NEXTSONG
  .byte $5a, KEY_KPENTER
  .byte $5e, KEY_WAKE
  .byte $69, KEY_END
  .byte $6b, KEY_LEFT
  .byte $6c, KEY_HOME
  .byte $70, KEY_INSERT
  .byte $71, KEY_DELETE
  .byte $72, KEY_DOWN
  .byte $74, KEY_RIGHT
  .byte $75, KEY_UP
  .byte $7a, KEY_PAGEDOWN
  .byte $7c, KEY_SYSRQ
  .byte $7d, KEY_PAGEUP
  .byte $7e, KEY_PAUSE
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
  .byte '\\', '|'
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
  .byte KEY_BACKSLASH,  '\\'
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
