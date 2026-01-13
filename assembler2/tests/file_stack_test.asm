; File Stack Test Program
; Usage: file_stack_test <mode> <input_file>
; Modes:
;   echo   - Read file char by char, write to stdout
;   lines  - Read file, output "N:content" for each line
;   nested - Handle @include markers, echo all content
;   info   - Read file, output statistics

* = $0200

FILE_STACK = $F000
TOKEN      = $1D00

  .zeropage

; File state
CURR_FILE   .data $00   ; Current file handle
CURLINEL    .data $00   ; Current line number (low)
CURLINEH    .data $00   ; Current line number (high)
NEXT_CHAR   .data $00   ; Last character read

; Test state
TEST_MODE   .data $00   ; 0=echo, 1=lines, 2=nested, 3=info
CHAR_COUNT_L .data $00  ; Character count (low)
CHAR_COUNT_H .data $00  ; Character count (high)
LINE_COUNT_L .data $00  ; Line count (low)
LINE_COUNT_H .data $00  ; Line count (high)
AT_LINE_START .data $00 ; Flag: at start of line (for lines mode)

; For decimal printing
NUM_L       .data $00
NUM_H       .data $00
DIVISOR_L   .data $00
DIVISOR_H   .data $00
PRINT_ZERO  .data $00   ; Flag to print leading zeros

; Temporary
TEMP        .data $00
TABPL       .data $00
TABPH       .data $00

  .code

  JMP main

  .include environment11.asm

; File stack configuration
FS_FILENAME   = TOKEN
FS_CURR_FILE  = CURR_FILE
FS_CURR_LINEL = CURLINEL
FS_CURR_LINEH = CURLINEH
FS_NEXT_CHAR  = NEXT_CHAR
  .include file_stack21.asm
read_char = file_stack_read_char


main:
  JSR file_stack_init
  JSR parse_args
  BCC .args_ok
  JMP error_usage

.args_ok:
  ; Initialize counters
  LDA #$00
  STA CHAR_COUNT_L
  STA CHAR_COUNT_H
  STA LINE_COUNT_L
  STA LINE_COUNT_H
  LDA #$01
  STA AT_LINE_START

  ; Dispatch based on mode
  LDA TEST_MODE
  BEQ mode_echo
  CMP #$01
  BEQ mode_lines
  CMP #$02
  BEQ .go_nested
  CMP #$03
  BEQ .go_info
  JMP error_usage
.go_nested:
  JMP mode_nested
.go_info:
  JMP mode_info

; ============================================================================
; MODE: echo - Simply read and echo each character
; ============================================================================
mode_echo:
.loop:
  JSR read_char
  BCS .done
  JSR write_b
  JMP .loop
.done:
  LDA #$00
  JMP exit

; ============================================================================
; MODE: lines - Output "N:content" for each line
; ============================================================================
mode_lines:
.loop:
  ; If at line start, save line number BEFORE read_char can increment it
  LDA AT_LINE_START
  BEQ .do_read
  LDA CURLINEL
  STA NUM_L
  LDA CURLINEH
  STA NUM_H
.do_read:
  ; Read first, then decide if we need line prefix
  JSR read_char_track_line
  BCS .done
  ; Check if at start of line - output prefix before the char
  LDX AT_LINE_START
  BEQ .not_start
  ; Save char, print saved line number, restore char
  PHA
  JSR print_num
  LDA #':'
  JSR write_b
  LDA #$00
  STA AT_LINE_START
  PLA
.not_start:
  JSR write_b
  CMP #$0A            ; newline
  BNE .loop
  LDA #$01
  STA AT_LINE_START
  JMP .loop
.done:
  LDA #$00
  JMP exit

; ============================================================================
; MODE: nested - Handle @include markers
; ============================================================================
mode_nested:
.loop:
  JSR read_char_track_line
  BCS .done
  ; Check for '@' at start of line
  CMP #'@'
  BNE .not_include
  LDA AT_LINE_START
  BEQ .not_include
  ; Might be @include - check
  JSR check_include_marker
  BCC .loop           ; Was @include, continue reading from new file
  JMP .loop           ; Not @include, but already output - continue
.not_include:
  JSR write_b
  ; Track line start
  CMP #$0A
  BNE .not_newline
  LDA #$01
  STA AT_LINE_START
  JMP .loop
.not_newline:
  LDA #$00
  STA AT_LINE_START
  JMP .loop
.done:
  LDA #$00
  JMP exit

; Check if we're at "@include " and handle it
; On entry: just read '@'
; On exit: C=0 if was include (file pushed), C=1 if not (already output '@')
check_include_marker:
  ; Read and check "include "
  LDX #$00
.check_loop:
  JSR read_char_track_line
  BCS .not_include_eof
  CMP include_marker,X
  BNE .not_include_char
  INX
  CPX #$08            ; Length of "include "
  BNE .check_loop
  ; It's @include - read filename into TOKEN
  JSR read_include_filename
  JSR push_file_stack
  LDA #$01
  STA AT_LINE_START
  CLC
  RTS
.not_include_char:
  ; Not @include - output '@' and what we read, then return char
  PHA
  LDA #'@'
  JSR write_b
  ; Output matched portion
  TXA
  BEQ .output_current
  LDY #$00
.output_matched:
  LDA include_marker,Y
  JSR write_b
  INY
  DEX
  BNE .output_matched
.output_current:
  PLA
  JSR write_b
  ; Check if what we just output was a newline
  CMP #$0A
  BNE .not_newline_after
  LDA #$01
  STA AT_LINE_START
  SEC
  RTS
.not_newline_after:
  LDA #$00
  STA AT_LINE_START
  SEC
  RTS
.not_include_eof:
  ; EOF during check - output '@' and matched portion
  LDA #'@'
  JSR write_b
  TXA
  BEQ .eof_done
  LDY #$00
.output_matched_eof:
  LDA include_marker,Y
  JSR write_b
  INY
  DEX
  BNE .output_matched_eof
.eof_done:
  SEC
  RTS

include_marker:
  .data "include "

; Read filename until newline into TOKEN
read_include_filename:
  LDX #$00
.loop:
  JSR read_char_track_line
  BCS .done
  CMP #$0A
  BEQ .done
  CMP #$0D            ; Also handle CR
  BEQ .skip_cr
  STA TOKEN,X
  INX
  JMP .loop
.skip_cr:
  JMP .loop
.done:
  LDA #$00
  STA TOKEN,X
  RTS

; ============================================================================
; MODE: info - Read file and output statistics
; ============================================================================
mode_info:
.loop:
  JSR read_char
  BCS .done
  ; Count characters
  INC CHAR_COUNT_L
  BNE .no_carry
  INC CHAR_COUNT_H
.no_carry:
  ; Count newlines
  CMP #$0A
  BNE .loop
  INC LINE_COUNT_L
  BNE .loop
  INC LINE_COUNT_H
  JMP .loop
.done:
  ; Output "chars:N"
  JSR print_str_chars
  LDA CHAR_COUNT_L
  STA NUM_L
  LDA CHAR_COUNT_H
  STA NUM_H
  JSR print_num
  LDA #$0A
  JSR write_b
  ; Output "lines:N"
  JSR print_str_lines
  LDA LINE_COUNT_L
  STA NUM_L
  LDA LINE_COUNT_H
  STA NUM_H
  JSR print_num
  LDA #$0A
  JSR write_b
  ; Output "stack:empty" or "stack:active"
  JSR print_str_stack
  JSR file_stack_empty
  BNE .stack_not_empty
  JSR print_str_empty
  JMP .info_done
.stack_not_empty:
  JSR print_str_active
.info_done:
  LDA #$0A
  JSR write_b
  LDA #$00
  JMP exit

; ============================================================================
; String printing utilities
; ============================================================================

print_str_chars:
  LDA #<str_chars
  STA TABPL
  LDA #>str_chars
  STA TABPH
  JMP print_str

print_str_lines:
  LDA #<str_lines
  STA TABPL
  LDA #>str_lines
  STA TABPH
  JMP print_str

print_str_stack:
  LDA #<str_stack
  STA TABPL
  LDA #>str_stack
  STA TABPH
  JMP print_str

print_str_empty:
  LDA #<str_empty
  STA TABPL
  LDA #>str_empty
  STA TABPH
  JMP print_str

print_str_active:
  LDA #<str_active
  STA TABPL
  LDA #>str_active
  STA TABPH
  JMP print_str

print_str:
  LDY #$00
.loop:
  LDA (TABPL),Y
  BEQ .done
  JSR write_b
  INY
  JMP .loop
.done:
  RTS

str_chars:
  .data "chars:" $00
str_lines:
  .data "lines:" $00
str_stack:
  .data "stack:" $00
str_empty:
  .data "empty" $00
str_active:
  .data "active" $00

; ============================================================================
; Simple decimal print for 16-bit number in NUM_L/NUM_H
; ============================================================================
print_num:
  LDA #$00
  STA PRINT_ZERO      ; Don't print leading zeros yet
  ; Try 10000 ($2710)
  LDA #$10
  STA DIVISOR_L
  LDA #$27
  STA DIVISOR_H
  JSR print_digit
  ; Try 1000 ($03E8)
  LDA #$E8
  STA DIVISOR_L
  LDA #$03
  STA DIVISOR_H
  JSR print_digit
  ; Try 100 ($64)
  LDA #$64
  STA DIVISOR_L
  LDA #$00
  STA DIVISOR_H
  JSR print_digit
  ; Try 10 ($0A)
  LDA #$0A
  STA DIVISOR_L
  LDA #$00
  STA DIVISOR_H
  JSR print_digit
  ; Always print ones digit
  LDA NUM_L
  CLC
  ADC #'0'
  JSR write_b
  RTS

; Print one decimal digit by repeated subtraction
; Divides NUM by DIVISOR, prints digit, leaves remainder in NUM
print_digit:
  LDX #$00            ; Digit counter
.sub_loop:
  ; Check if NUM >= DIVISOR
  LDA NUM_H
  CMP DIVISOR_H
  BCC .done_sub       ; NUM_H < DIVISOR_H, done
  BNE .do_sub         ; NUM_H > DIVISOR_H, subtract
  ; High bytes equal, check low
  LDA NUM_L
  CMP DIVISOR_L
  BCC .done_sub       ; NUM < DIVISOR, done
.do_sub:
  ; NUM -= DIVISOR
  SEC
  LDA NUM_L
  SBC DIVISOR_L
  STA NUM_L
  LDA NUM_H
  SBC DIVISOR_H
  STA NUM_H
  INX
  JMP .sub_loop
.done_sub:
  ; X = digit value
  TXA
  BNE .print_it
  ; Digit is 0 - only print if we've printed something
  LDA PRINT_ZERO
  BEQ .skip_it
.print_it:
  TXA
  CLC
  ADC #'0'
  JSR write_b
  LDA #$01
  STA PRINT_ZERO      ; Now print zeros
.skip_it:
  RTS

; ============================================================================
; Read character with line tracking (wrapper around file_stack's read_char)
; On exit: A = character, C = 0 if char read, C = 1 if all done
;          CURLINEL/H updated on newline
; ============================================================================
read_char_track_line:
  JSR read_char
  BCS .done
  ; Track line numbers (preserve A and C=0)
  CMP #$0A
  BNE .success
  INC CURLINEL
  BNE .success
  INC CURLINEH
.success:
  LDA NEXT_CHAR       ; Restore A (CMP changed flags)
  CLC                 ; Ensure C=0 for success
.done:
  RTS

; ============================================================================
; Argument parsing
; On exit: C=0 if OK (TEST_MODE set, file opened), C=1 if error
; ============================================================================
parse_args:
  ; Check argc >= 2 (mode, file - emulator doesn't include program name)
  JSR argc
  CMP #$02
  BCC .error

  ; Get mode argument (argv[0])
  LDA #$00
  JSR argv
  STA TABPL
  STX TABPH
  JSR parse_mode
  BCS .error

  ; Get filename argument (argv[1])
  LDA #$01
  JSR argv
  STA TABPL
  STX TABPH
  ; Copy to TOKEN
  LDY #$00
.copy_filename:
  LDA (TABPL),Y
  STA TOKEN,Y
  BEQ .filename_done
  INY
  JMP .copy_filename
.filename_done:
  ; Open file via file stack (this resets line number to 0)
  JSR push_file_stack
  ; Initialize line number to 1 (first line is line 1)
  LDA #$01
  STA CURLINEL
  LDA #$00
  STA CURLINEH
  CLC
  RTS
.error:
  SEC
  RTS

; Parse mode string at TABPL/H
; Sets TEST_MODE, returns C=0 on success
parse_mode:
  LDY #$00
  LDA (TABPL),Y
  CMP #'e'
  BEQ .check_echo
  CMP #'l'
  BEQ .check_lines
  CMP #'n'
  BEQ .check_nested
  CMP #'i'
  BEQ .check_info
  SEC
  RTS
.check_echo:
  LDA #$00
  STA TEST_MODE
  CLC
  RTS
.check_lines:
  LDA #$01
  STA TEST_MODE
  CLC
  RTS
.check_nested:
  LDA #$02
  STA TEST_MODE
  CLC
  RTS
.check_info:
  LDA #$03
  STA TEST_MODE
  CLC
  RTS

; ============================================================================
; Error handling
; ============================================================================
error_usage:
  LDA #<msg_usage
  STA TABPL
  LDA #>msg_usage
  STA TABPH
  JSR print_str_err
  LDA #$01
  JMP exit

print_str_err:
  LDY #$00
.loop:
  LDA (TABPL),Y
  BEQ .done
  JSR write_d
  INY
  JMP .loop
.done:
  RTS

msg_usage:
  .data "Usage: file_stack_test <mode> <file>" $0A
  .data "Modes: echo, lines, nested, info" $0A $00

start = $0200

* = $FFFC
  .data start           ; Reset vector
  .data start           ; Interrupt vector (unused)
