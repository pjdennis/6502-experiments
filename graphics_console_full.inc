; Requires:
;   INTERRUPT_ROUTINE         - Address to which interrupt handler will be copied
;   GCF_ZERO_PAGE_BASE        - Zero page location for variables
;   SIMPLE_BUFFER             - Buffer to be used for keyboard bytes
;   GC_LINE_BUFFER            - Buffer for storing characters typed
;
; Optional:
;   callback_key_f1 etc.      - Callbacks for keys F1, etc.
;   gc_callback_char_received - Callback when a character is received


; Zero page allocations
CP_M_DEST_P              = GCF_ZERO_PAGE_BASE + $00 ; 2 bytes
CP_M_SRC_P               = GCF_ZERO_PAGE_BASE + $02 ; 2 bytes
CP_M_LEN                 = GCF_ZERO_PAGE_BASE + $04 ; 2 bytes

SIMPLE_BUFFER_WRITE_PTR  = GCF_ZERO_PAGE_BASE + $06 ; 1 byte
SIMPLE_BUFFER_READ_PTR   = GCF_ZERO_PAGE_BASE + $07 ; 1 byte

DISPLAY_STRING_PARAM     = GCF_ZERO_PAGE_BASE + $08 ; 2 bytes
MULTIPLY_8X8_RESULT_LOW  = GCF_ZERO_PAGE_BASE + $0a ; 1 byte
MULTIPLY_8X8_TEMP        = GCF_ZERO_PAGE_BASE + $0b ; 1 byte

GD_ZERO_PAGE_BASE        = GCF_ZERO_PAGE_BASE + $0c

KB_ZERO_PAGE_BASE        = GD_ZERO_PAGE_STOP
GC_ZERO_PAGE_BASE        = KB_ZERO_PAGE_STOP
CT_ZERO_PAGE_BASE        = GC_ZERO_PAGE_STOP

GCF_ZERO_PAGE_STOP       = CT_ZERO_PAGE_STOP

  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc
  .include keyboard_typematic.inc
KB_BUFFER_INITIALIZE = simple_buffer_initialize
KB_BUFFER_WRITE      = simple_buffer_write
KB_BUFFER_READ       = simple_buffer_read
  .include keyboard_driver.inc
  .include multiply8x8.inc
  .include graphics_display.inc
  .include graphics_console.inc
  .include write_string_to_screen.inc
  .include command_table.inc
  .include console_repl.inc

