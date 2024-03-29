; Display commands
CMD_CLEAR_DISPLAY           = %00000001
CMD_RETURN_HOME             = %00000010
CMD_ENTRY_MODE_SET          = %00000100
CMD_DISPLAY_ON_OFF_CONTROL  = %00001000
CMD_CURSOR_OR_DISPLAY_SHIFT = %00010000
CMD_FUNCTION_SET            = %00100000
CMD_SET_CGRAM_ADDRESS       = %01000000
CMD_SET_DDRAM_ADDRESS       = %10000000

; Display command bits
CMD_PARAM_DISPLAY_ON        = %00000100
CMD_PARAM_CURSOR_ON         = %00000010
CMD_PARAM_CURSOR_BLINK      = %00000001

; Display paramters
DISPLAY_FIRST_LINE  = $00
DISPLAY_SECOND_LINE = $40
DISPLAY_THIRD_LINE  = DISPLAY_FIRST_LINE + 20
DISPLAY_FOURTH_LINE = DISPLAY_SECOND_LINE + 20
