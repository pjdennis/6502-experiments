; ============================================================================
; VI - Minimal Vi-like Text Editor for 6502
; ============================================================================
;
; A vi-like text editor running on the 6502 emulator in console mode.
;
; Usage:
;   ./emulator.out editor/out/editor.out 0400 --console outfile.txt infile.txt
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
;   TEXT_BUF      Text buffer ($2000-$BFFF)
;   LINE_TBL      Line pointer table ($C000-$DFFF)
;   $E000-$EFFF   Scratch space
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
  SET16 addr STR_PTR16
  JSR write_string
  .endmacro

  .include 23/to_decimal.asm
  .include editor/terminal.asm
  .include editor/input.asm
  .include editor/buffer.asm
  .include editor/render.asm
  .include editor/normal.asm
  .include editor/insert.asm
  .include editor/command.asm

; ============================================================================
; Entry point
; ============================================================================
editor_main
  ; Initialize flags
  LDA #$00
  STA CMD_QUIT
  STA READONLY
  LDA #>TEXT_LIMIT
  STA BUF_LIMIT

  ; Get filename from argv
  JSR argc
  CMP #$01
  BCC .no_file
  ; Get first argument (the input filename)
  LDA #$00
  JSR argv
  ; A;X = pointer to filename string, copy to FNAME_BUF and set FNAME_PTR16
  STA BUF_PTR16
  STX BUF_PTR16+$01
  LDY #$00
.copy_fname
  LDA (BUF_PTR16),Y
  STA FNAME_BUF,Y
  BEQ .fname_copied
  INY
  BNE .copy_fname
.fname_copied
  SET16 FNAME_BUF FNAME_PTR16

  .ifdef enable_debug
  ; Parse additional arguments (debug build only)
  JSR parse_debug_args
  .endif

  ; Try to open the file for reading (returns 0 if not found)
  LDA FNAME_PTR16
  LDX FNAME_PTR16+$01
  JSR open
  CMP #$00
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

.new_file
  ; File doesn't exist - start with empty buffer
  JSR buf_init
  JMP .init_display

.no_file
  ; No file specified - use default name and empty buffer
  SET16 str_untitled FNAME_PTR16
  ; Copy to FNAME_BUF
  LDY #$00
.copy_default
  LDA str_untitled,Y
  STA FNAME_BUF,Y
  BEQ .default_copied
  INY
  BNE .copy_default
.default_copied
  JSR buf_init

.init_display
  ; Initialize rendering
  JSR render_init

  ; Draw initial screen
  JSR render_screen

  ; Show truncation warning if file was truncated
  LDA READONLY
  BEQ .no_truncation_warning
  SET16 str_truncated STR_PTR16
  JSR show_status_message
.no_truncation_warning

; ============================================================================
; Main loop
; ============================================================================
main_loop
  ; If entering command mode, handle it specially (it does own I/O)
  LDA MODE
  CMP #MODE_COMMAND
  BNE .not_command_entry
  JSR command_handle
  JMP .after_key
.not_command_entry

  ; Read a key
  JSR read_key

  ; EOT ($04) = end of input (for scripted/test mode)
  CMP #$04
  BNE .not_eot
  JMP .editor_exit
.not_eot

  ; Dispatch based on mode
  LDX MODE
  CPX #MODE_INSERT
  BEQ .insert_mode

  ; Normal mode
  JSR normal_handle_key
  JMP .after_key

.insert_mode
  JSR insert_handle_key
  JMP .after_key

.after_key
  ; Check if we should quit
  LDA CMD_QUIT
  BNE .editor_exit

  ; Update file line from view top + cursor row
  CLC
  LDA VIEW_TOP16
  ADC CURSOR_ROW
  STA FILE_LINE16
  LDA VIEW_TOP16+$01
  ADC #$00
  STA FILE_LINE16+$01

  ; Redraw screen
  JSR render_screen

  JMP main_loop

.editor_exit
  ; Clear screen and exit
  JSR ansi_clear_screen
  JSR con_flush
  LDA #$00
  JSR exit

; ============================================================================
; Debug support (compiled in only with define:enable_debug)
; ============================================================================

  .ifdef enable_debug

  .zeropage
DBG_ARG_IDX   .data $00   ; Current argument index
DBG_ARG_COUNT .data $00   ; Total argument count
  .code

; Parse additional command line arguments (after filename)
; Looks for: bufsize:NN (hex high byte of buffer limit)
parse_debug_args
  JSR argc
  STA DBG_ARG_COUNT
  LDA #$01              ; Start at argv(1), argv(0) is filename
  STA DBG_ARG_IDX

.arg_loop
  LDA DBG_ARG_IDX
  CMP DBG_ARG_COUNT
  BCS .args_done        ; No more arguments
  JSR argv
  STA BUF_PTR16
  STX BUF_PTR16+$01

  ; Check for "bufsize:" prefix (8 chars)
  LDY #$00
  LDA (BUF_PTR16),Y
  CMP #'b'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'u'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'f'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'s'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'i'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'z'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #'e'
  BNE .next_arg
  INY
  LDA (BUF_PTR16),Y
  CMP #':'
  BNE .next_arg

  ; Found "bufsize:" - parse 2-digit hex value at Y+1
  INY
  LDA (BUF_PTR16),Y
  JSR parse_hex_digit
  ASL
  ASL
  ASL
  ASL
  STA BUF_TEMP
  INY
  LDA (BUF_PTR16),Y
  JSR parse_hex_digit
  ORA BUF_TEMP
  STA BUF_LIMIT
  JMP .next_arg

.next_arg
  INC DBG_ARG_IDX
  JMP .arg_loop

.args_done
  RTS

; Parse a single hex digit in A, return value in A (0-15)
; Handles 0-9, A-F, a-f
parse_hex_digit
  CMP #'a'
  BCS .lower
  CMP #'A'
  BCS .upper
  ; 0-9
  SEC
  SBC #'0'
  RTS
.upper
  SEC
  SBC #'A'-$0A
  RTS
.lower
  SEC
  SBC #'a'-$0A
  RTS

  .endif

; ============================================================================
; Data
; ============================================================================
str_untitled .data "[No Name]" $00

; Entry point address - emulator uses last 2 bytes of binary as reset vector
  .data editor_main
