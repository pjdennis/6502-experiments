; Key codes can be found here: https://wiki.osdev.org/PS/2_Keyboard
; Key names can be found here:
;   https://manpages.ubuntu.com/manpages/focal/man7/virkeycode-linux.7.html

  .include ASCII.inc

KP_OFFSET   = %10000000
FN_OFFSET   = %11000000
MISC_OFFSET = FN_OFFSET + 13

; Key codes - a superset of ASCII
KEY_BACKSPACE    = ASCII_BACKSPACE
KEY_TAB          = ASCII_TAB
KEY_ENTER        = ASCII_LF
KEY_SPACE        = ' '
KEY_APOSTROPHE   = "'"
KEY_COMMA        = ','
KEY_MINUS        = '-'
KEY_DOT          = '.'
KEY_SLASH        = '/'
KEY_0            = '0'
KEY_1            = '1'
KEY_2            = '2'
KEY_3            = '3'
KEY_4            = '4'
KEY_5            = '5'
KEY_6            = '6'
KEY_7            = '7'
KEY_8            = '8'
KEY_9            = '9'
KEY_SEMICOLON    = ';'
KEY_EQUAL        = '='
KEY_LEFTBRACE    = '['
KEY_BACKSLASH    = '\\'
KEY_RIGHTBRACE   = ']'
KEY_GRAVE        = '`'
KEY_A            = 'a'
KEY_B            = 'b'
KEY_C            = 'c'
KEY_D            = 'd'
KEY_E            = 'e'
KEY_F            = 'f'
KEY_G            = 'g'
KEY_H            = 'h'
KEY_I            = 'i'
KEY_J            = 'j'
KEY_K            = 'k'
KEY_L            = 'l'
KEY_M            = 'm'
KEY_N            = 'n'
KEY_O            = 'o'
KEY_P            = 'p'
KEY_Q            = 'q'
KEY_R            = 'r'
KEY_S            = 's'
KEY_T            = 't'
KEY_U            = 'u'
KEY_V            = 'v'
KEY_W            = 'w'
KEY_X            = 'x'
KEY_Y            = 'y'
KEY_Z            = 'z'

KEY_F1           =  1 + FN_OFFSET
KEY_F2           =  2 + FN_OFFSET
KEY_F3           =  3 + FN_OFFSET
KEY_F4           =  4 + FN_OFFSET
KEY_F5           =  5 + FN_OFFSET
KEY_F6           =  6 + FN_OFFSET
KEY_F7           =  7 + FN_OFFSET
KEY_F8           =  8 + FN_OFFSET
KEY_F9           =  9 + FN_OFFSET
KEY_F10          = 10 + FN_OFFSET
KEY_F11          = 11 + FN_OFFSET
KEY_F12          = 12 + FN_OFFSET

KEY_KP0          = '0' + KP_OFFSET
KEY_KP1          = '1' + KP_OFFSET
KEY_KP2          = '2' + KP_OFFSET
KEY_KP3          = '3' + KP_OFFSET
KEY_KP4          = '4' + KP_OFFSET
KEY_KP5          = '5' + KP_OFFSET
KEY_KP6          = '6' + KP_OFFSET
KEY_KP7          = '7' + KP_OFFSET
KEY_KP8          = '8' + KP_OFFSET
KEY_KP9          = '9' + KP_OFFSET
KEY_KPSLASH      = '/' + KP_OFFSET
KEY_KPASTERISK   = '*' + KP_OFFSET
KEY_KPMINUS      = '-' + KP_OFFSET
KEY_KPPLUS       = '+' + KP_OFFSET
KEY_KPDOT        = '.' + KP_OFFSET
KEY_KPENTER      = ASCII_LF + KP_OFFSET

KEY_ESC          =  0 + MISC_OFFSET

KEY_LEFTCTRL     =  1 + MISC_OFFSET
KEY_LEFTSHIFT    =  2 + MISC_OFFSET
KEY_LEFTALT      =  3 + MISC_OFFSET
KEY_LEFTMETA     =  4 + MISC_OFFSET ; Left Windows / GUI
KEY_RIGHTCTRL    =  5 + MISC_OFFSET
KEY_RIGHTSHIFT   =  6 + MISC_OFFSET
KEY_RIGHTALT     =  7 + MISC_OFFSET
KEY_RIGHTMETA    =  8 + MISC_OFFSET ; Right Windows / GUI
KEY_MENU         =  9 + MISC_OFFSET

KEY_NUMLOCK      = 10 + MISC_OFFSET
KEY_CAPSLOCK     = 11 + MISC_OFFSET
KEY_SCROLLLOCK   = 12 + MISC_OFFSET

KEY_SYSRQ        = 13 + MISC_OFFSET ; Print screen
KEY_PAUSE        = 14 + MISC_OFFSET

KEY_LEFT         = 15 + MISC_OFFSET
KEY_RIGHT        = 16 + MISC_OFFSET
KEY_UP           = 17 + MISC_OFFSET
KEY_DOWN         = 18 + MISC_OFFSET
KEY_PAGEUP       = 19 + MISC_OFFSET
KEY_PAGEDOWN     = 20 + MISC_OFFSET
KEY_HOME         = 21 + MISC_OFFSET
KEY_END          = 22 + MISC_OFFSET
KEY_INSERT       = 23 + MISC_OFFSET
KEY_DELETE       = 24 + MISC_OFFSET

KEY_PREVIOUSSONG = 25 + MISC_OFFSET
KEY_PLAYPAUSE    = 26 + MISC_OFFSET
KEY_STOPCD       = 27 + MISC_OFFSET
KEY_NEXTSONG     = 28 + MISC_OFFSET
KEY_MUTE         = 29 + MISC_OFFSET
KEY_VOLUMEDOWN   = 30 + MISC_OFFSET
KEY_VOLUMEUP     = 31 + MISC_OFFSET
KEY_POWER        = 32 + MISC_OFFSET
KEY_SLEEP        = 33 + MISC_OFFSET
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
