; ============================================================================
; VI - Minimal Vi-like Text Editor for 6502
; ============================================================================
;
; A vi-like text editor running on the 6502 emulator in console mode.
;
; Usage:
;   ./emulator.out editor/out/editor.out --load 0400 --console outfile.txt infile.txt
;
; Modes:
;   Normal:  h/j/k/l movement, x/dd delete, i/a/o/O insert, : command
;   Insert:  Type text, Enter for newline, Backspace to delete, ESC to exit
;   Command: :w save, :q quit, :wq save+quit, :q! force quit, :NNN goto line
;
; MEMORY LAYOUT
;   $0000-$00FF   Zero page variables
;   $0100-$01FF   6502 stack
;   $0200-$02FF   Filename buffer
;   $0300-$03FF   Command buffer
;   $0400         Editor code loads here
;   TEXT_BUF      Text buffer (page-aligned after code, up to $BFFF)
;   $C000-$DEFF   Line pointer table (LINE_TBL)
;   $DF00-$DF1F   Batch insert staging buffer (BATCH_BUF)
;   $DF20-$DF53   Mark table (MARK_TBL)
;   $E000-$EFFF   Yank buffer (4KB)
;   $F000+        Emulator I/O
; ============================================================================

FNAME_BUF   = $0200   ; Filename buffer (256 bytes)

* = $0400

  JMP editor_main

  .include 23/environment.asm
  .include 23/macros.asm

; PRINT_STR addr - Print null-terminated string at addr
; Clobbers A, Y
  .macro PRINT_STR addr
  SET16 addr, STR_PTR16
  JSR write_string
  .endmacro

  .include 23/to_decimal.asm
  .include editor/terminal.asm
  .include editor/input.asm
  .include editor/buffer.asm
  .include editor/render.asm
  .include editor/yank.asm
  .include editor/search.asm
  .include editor/normal.asm
  .include editor/insert.asm
  .include editor/command.asm
  .include editor/mark.asm

; ============================================================================
; Entry point
; ============================================================================
editor_main:
  ; Initialize flags
  LDA #0
  STA CMD_QUIT
  STA READONLY
  LDA #>TEXT_LIMIT
  STA BUF_LIMIT

  ; Get filename from argv
  JSR argc
  CMP #1
  BCC .no_file
  ; Get first argument (the input filename)
  LDA #0
  JSR argv
  ; A;X = pointer to filename string, copy to FNAME_BUF and set FNAME_PTR16
  STAX16 BUF_PTR16
  LDY #0
.copy_fname:
  LDA (BUF_PTR16),Y
  STA FNAME_BUF,Y
  BEQ .fname_copied
  INY
  BNE .copy_fname
.fname_copied:
  SET16 FNAME_BUF, FNAME_PTR16

  ; Try to open the file for reading (returns 0 if not found)
  LDAX16 FNAME_PTR16
  JSR open
  CMP #0
  BEQ .new_file

  ; File exists - load it
  STA FILE_HANDLE
  LDA FILE_HANDLE
  JSR buf_load_file
  PHP                  ; Save carry (truncation flag)
  LDA FILE_HANDLE
  JSR close
  PLP                  ; Restore carry
  BCC .init_display
  ; File was truncated - set read-only mode
  LDA #$FF
  STA READONLY
  JMP .init_display

.new_file:
  ; File doesn't exist - start with empty buffer
  JSR buf_init
  JMP .init_display

.no_file:
  ; No file specified - use default name and empty buffer
  SET16 str_untitled, FNAME_PTR16
  ; Copy to FNAME_BUF
  LDY #0
.copy_default:
  LDA str_untitled,Y
  STA FNAME_BUF,Y
  BEQ .default_copied
  INY
  BNE .copy_default
.default_copied:
  JSR buf_init

.init_display:
  ; Initialize rendering and normal mode state
  JSR render_init
  JSR normal_init
  JSR yank_init
  JSR search_init
  JSR mark_init

  ; Draw initial screen
  JSR render_screen

  ; Show truncation warning if file was truncated
  LDA READONLY
  BEQ .no_truncation_warning
  SET16 str_truncated, STR_PTR16
  JSR show_status_message
.no_truncation_warning:

; ============================================================================
; Main loop
; ============================================================================
main_loop:
  ; Default to full repaint; handlers clear for cursor-only updates
  LDA #$FF
  STA RENDER_FLAG

  ; If entering command mode, handle it specially (it does own I/O)
  LDA MODE
  CMP #MODE_COMMAND
  BNE .not_command_entry
  JSR command_handle
  JMP .after_key
.not_command_entry:

  ; Poll for input (non-blocking)
  JSR key_ready
  CMP #$FF
  BEQ .key_available

  ; No input - do background work and loop
  JSR background_work
  JMP main_loop

.key_available:
  ; Read a key
  JSR get_key

  ; EOT ($04) = end of input (for scripted/test mode)
  CMP #$04
  BNE .not_eot
  JMP .editor_exit
.not_eot:

  ; Dispatch based on mode
  LDX MODE
  CPX #MODE_INSERT
  BEQ .insert_mode

  ; Normal mode
  JSR normal_handle_key
  JMP .after_key

.insert_mode:
  JSR insert_handle_key
  JMP .after_key

.after_key:
  ; Check if we should quit
  LDA CMD_QUIT
  BNE .editor_exit

  ; Redraw screen (full or cursor-only based on RENDER_FLAG)
  JSR render_update

  JMP main_loop

.editor_exit:
  ; Clear screen and exit
  JSR ansi_clear_screen
  JSR con_flush
  LDA #0
  JSR exit

; ============================================================================
; Background work
; ============================================================================

; Called when no input is available - hook for background tasks
background_work:
  RTS

; ============================================================================
; Data
; ============================================================================
str_untitled: .asciiz "[No Name]"

; Entry point address - emulator uses last 2 bytes of binary as reset vector
  .word editor_main

; ============================================================================
; TEXT_BUF - floating text buffer start address
; ============================================================================
; Page-aligned to the next page boundary after the end of program code.
; This ensures TEXT_BUF automatically moves as the code grows, preventing
; overlap between program code and the text buffer.
_code_end:
TEXT_BUF = _code_end + $00FF >> $08 << $08

; Buffer size: normal build = up to $C000 (LINE_TBL), small build = 256 bytes
  .ifndef small_buffer
TEXT_LIMIT  = $C000  ; End of text buffer space (up to start of LINE_TBL)
  .else
TEXT_LIMIT  = TEXT_BUF + $0100  ; Small test buffer (256 bytes)
  .endif
