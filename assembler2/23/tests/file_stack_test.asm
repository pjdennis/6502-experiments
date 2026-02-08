; File Stack Test Program
; Usage: file_stack_test <mode> <input_file>
; Modes:
;   echo   - Read file char by char, write to stdout
;   lines  - Read file, output "N:content" for each line
;   info   - Read file, output statistics
;   memory - Handle @memory, @include, and @traceback markers

* = $0200

FILE_STACK = $F000
TOKEN      = $1D00
TOKEN_MEM  = $1D80  ; Offset in TOKEN buffer for memory content

  .zeropage

; Test state
TEST_MODE:     .byte 0       ; 0=echo, 1=lines, 2=info, 3=memory
CHAR_COUNT16:  .word 0       ; Character count
LINE_COUNT16:  .word 0       ; Line count
AT_LINE_START: .byte 0       ; Flag: at start of line (for lines mode)

; Temporary
TEMP:        .byte 0
TABP16:      .word 0
MARKER_TERM: .byte 0       ; Character that terminated the keyword ($FF = EOF)

  .code

  .include environment.asm
  .include macros.asm
  .include to_decimal.asm

  .macro PRINT_STR str_addr
  SET16 str_addr, TABP16
  JSR print_str
  .endmacro

; File stack configuration
FS_FILENAME   = TOKEN

; CHECK_FOR_OUT_OF_MEMORY - Macro placeholder for use by file stack
  .macro CHECK_FOR_OUT_OF_MEMORY fs_ptr
  ; Do nothing, for the purposes of the file stack test.
  ; TODO: Consider writing to debug output when it's called, and extend tests to confirm
  .endmacro

; Error handler for file-not-found (required by file_stack.asm)
err_file_not_found:
  BRK
  .asciiz 36, "File not found"

  .include file_stack.asm
read_char = file_stack_read_char
CURLINE16 = FS_CURR_LINE16
CURR_CHAR = FS_CURR_CHAR


main:
  JSR file_stack_init
  JSR parse_args
  BCC .args_ok
  JMP error_usage

.args_ok:
  ; Initialize counters
  SET16 $00, CHAR_COUNT16
  SET16 $00, LINE_COUNT16
  LDA #$01
  STA AT_LINE_START

  ; Dispatch based on mode
  LDA TEST_MODE
  BEQ mode_echo
  CMP #$01
  BEQ mode_lines
  CMP #$02
  BEQ .go_info
  CMP #$03
  BEQ .go_memory
  JMP error_usage
.go_info:
  JMP mode_info
.go_memory:
  JMP mode_memory

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
  CP16 CURLINE16, TO_DECIMAL_VALUE16
.do_read:
  ; Read first, then decide if we need line prefix
  JSR read_char_track_line
  BCS .done
  ; Check if at start of line - output prefix before the char
  LDX AT_LINE_START
  BEQ .not_start
  ; Save char, print saved line number, restore char
  PHA
  JSR print_decimal
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

; Read filename until newline into TOKEN
; Note: Uses read_char (not read_char_track_line) to avoid incrementing
; line number - the line should be saved BEFORE reading the filename
read_include_filename:
  LDX #$00
.loop:
  JSR read_char
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
  INC16 CHAR_COUNT16
  ; Count newlines
  CMP #$0A
  BNE .loop
  INC16 LINE_COUNT16
  JMP .loop
.done:
  ; Output "chars:N"
  PRINT_STR str_chars
  CP16 CHAR_COUNT16, TO_DECIMAL_VALUE16
  JSR print_decimal
  LDA #$0A
  JSR write_b
  ; Output "lines:N"
  PRINT_STR str_lines
  CP16 LINE_COUNT16, TO_DECIMAL_VALUE16
  JSR print_decimal
  LDA #$0A
  JSR write_b
  ; Output "stack:empty" or "stack:active"
  PRINT_STR str_stack
  JSR file_stack_empty
  BNE .stack_not_empty
  PRINT_STR str_empty
  JMP .info_done
.stack_not_empty:
  PRINT_STR str_active
.info_done:
  LDA #$0A
  JSR write_b
  LDA #$00
  JMP exit

; ============================================================================
; MODE: memory - Handle @memory, @include, and @traceback markers
; ============================================================================
mode_memory:
.loop:
  JSR read_char_track_line
  BCS .done
  ; Check for '@' at start of line
  CMP #'@'
  BNE .not_at_sign
  LDA AT_LINE_START
  BEQ .at_not_start
  ; Might be a marker - check
  JSR check_markers
  BCC .loop           ; Was a marker, continue reading
  JMP .loop           ; Not a marker, but already output - continue
.at_not_start:
  LDA #'@'            ; Restore the clobbered character
.not_at_sign:
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

; ============================================================================
; Buffer-based marker matching
; On entry: just read '@' at start of line
; Buffers keyword into TOKEN, then compares against known markers.
; On exit: C=0 if marker handled, C=1 if not (text already flushed)
; ============================================================================
check_markers:
  ; Buffer the keyword after '@' into TOKEN
  LDX #$00
.buffer_loop:
  JSR read_char
  BCS .buffer_eof
  CMP #' '
  BEQ .buffer_done
  CMP #$0A
  BEQ .buffer_done
  STA TOKEN,X
  INX
  JMP .buffer_loop
.buffer_eof:
  LDA #$FF            ; Sentinel for EOF
.buffer_done:
  STA MARKER_TERM     ; Save terminator (space, $0A, or $FF)
  LDA #$00
  STA TOKEN,X         ; Null-terminate the keyword

  ; Try matching against each known marker
  SET16 str_include, TABP16
  JSR cmp_marker
  BCC .handle_include

  SET16 str_memory, TABP16
  JSR cmp_marker
  BCC .handle_memory

  SET16 str_traceback, TABP16
  JSR cmp_marker
  BCC .handle_traceback

  ; No match - flush '@' + keyword + terminator as text
  JMP flush_as_text

.handle_include:
  ; @include requires space terminator (filename follows)
  LDA MARKER_TERM
  CMP #' '
  BNE flush_as_text   ; Not followed by space, treat as text
  ; Read filename into TOKEN (overwrites keyword)
  JSR read_include_filename
  JSR push_file_stack
  ; Initialize line to 1 for included file
  SET16 $01, CURLINE16
  LDA #$01
  STA AT_LINE_START
  CLC
  RTS

.handle_memory:
  LDA MARKER_TERM
  CMP #' '
  BEQ .memory_with_content
  CMP #$0A
  BEQ .memory_empty
  ; EOF after @memory = empty content
  ; ($FF terminator means EOF)
.memory_empty:
  ; @memory with no content - just set line start
  ; Increment line if terminated by newline
  LDA MARKER_TERM
  CMP #$0A
  BNE .memory_empty_no_newline
  INC16 CURLINE16
.memory_empty_no_newline:
  LDA #$01
  STA AT_LINE_START
  CLC
  RTS
.memory_with_content:
  ; Read content into TOKEN until newline
  JSR read_memory_content
  JMP setup_memory_source

.handle_traceback:
  ; Consume any remaining content on the line
  ; Use read_char to avoid incrementing line number
  LDA MARKER_TERM
  CMP #$0A
  BEQ .do_traceback
  CMP #$FF
  BEQ .do_traceback
  ; Terminator was space - skip to end of line
.skip_to_eol:
  JSR read_char
  BCS .do_traceback
  CMP #$0A
  BNE .skip_to_eol
.do_traceback:
  ; Print the traceback (pops all stack entries, closes files)
  JSR print_traceback
  LDA #$01
  STA AT_LINE_START
  CLC
  RTS

; Compare null-terminated keyword in TOKEN against pattern at (TABP16)
; Returns: C=0 if match, C=1 if no match
cmp_marker:
  LDY #$00
.loop:
  LDA TOKEN,Y
  CMP (TABP16),Y
  BNE .no_match
  ; If both are null, it's a match
  CMP #$00
  BEQ .match
  INY
  JMP .loop
.match:
  CLC
  RTS
.no_match:
  SEC
  RTS

; Flush '@' + TOKEN keyword + terminator as literal text
; Updates AT_LINE_START and CURLINE16 as needed
; Returns: C=1 (not a marker)
flush_as_text:
  LDA #'@'
  JSR write_b
  ; Output keyword from TOKEN
  LDY #$00
.loop:
  LDA TOKEN,Y
  BEQ .keyword_done
  JSR write_b
  INY
  JMP .loop
.keyword_done:
  ; Output the terminator character
  LDA MARKER_TERM
  CMP #$FF
  BEQ .eof_term       ; EOF - nothing to output
  JSR write_b
  CMP #$0A
  BNE .not_newline
  INC16 CURLINE16
  LDA #$01
  STA AT_LINE_START
  SEC
  RTS
.not_newline:
  LDA #$00
  STA AT_LINE_START
  SEC
  RTS
.eof_term:
  LDA #$00
  STA AT_LINE_START
  SEC
  RTS

; Set up memory source from content in TOKEN (X = length)
setup_memory_source:
  ; TOKEN contains the content, X = length
  ; Problem: FS_FILENAME = TOKEN, so we can't put name there without losing content
  ; Solution: Copy content to TOKEN+$80, then put name in TOKEN
  ; Save X (content length)
  STX TEMP
  ; Copy content from TOKEN to TOKEN_MEM
  LDY #$00
.copy_content:
  CPY TEMP
  BEQ .content_done
  LDA TOKEN,Y
  STA TOKEN_MEM,Y
  INY
  JMP .copy_content
.content_done:
  ; Add null terminator after content (Y = length)
  LDA #$00
  STA TOKEN_MEM,Y
  ; Copy "MEMORY" to TOKEN (which is FS_FILENAME)
  LDY #$00
.copy_name:
  LDA str_memory_source,Y
  STA TOKEN,Y
  BEQ .name_done
  INY
  JMP .copy_name
.name_done:
  ; Set memory pointer to TOKEN_MEM (content is now zero-terminated)
  SET16 TOKEN_MEM, FS_MEM_PTR16
  ; Push memory source (FS_FILENAME has name, pointer is set)
  JSR push_memory_source
  ; Initialize line to 1 for memory source, at start of line
  SET16 $01, CURLINE16
  LDA #$01
  STA AT_LINE_START
  CLC
  RTS

str_include:
  .asciiz "include"
str_memory:
  .asciiz "memory"
str_traceback:
  .asciiz "traceback"
str_memory_source:
  .asciiz "MEMORY"

; Read memory content until newline into TOKEN
; Returns length in X (includes trailing newline)
; Note: Uses read_char (not read_char_track_line) to avoid incrementing
; line number - the line should be saved BEFORE reading the content
read_memory_content:
  LDX #$00
.loop:
  JSR read_char
  BCS .add_newline    ; EOF - add newline and done
  CMP #$0A
  BEQ .add_newline    ; Newline - add it and done
  CMP #$0D            ; Also handle CR
  BEQ .skip_cr
  STA TOKEN,X
  INX
  JMP .loop
.skip_cr:
  JMP .loop
.add_newline:
  LDA #$0A
  STA TOKEN,X
  INX
.done:
  RTS

; Print traceback of file stack - pops all entries, closes files
; Output format: "type:name:line\n" for each entry in stack
; where type is "file" or "memory"
; Loop: check if empty → print current → pop → repeat
print_traceback:
  ; Preserve X (output file handle)
  TXA
  PHA
.loop:
  ; Check if stack is empty (no sources)
  JSR file_stack_empty
  BEQ .done
  ; Find curr_type by scanning past the name
  ; FS_P16 points to: name\0 | curr_type | ...
  CP16 FS_P16, TABP16
  LDY #$00
.find_null:
  LDA (TABP16),Y
  BEQ .found_null
  INY
  JMP .find_null
.found_null:
  ; Y points at null, curr_type is at Y+1
  INY
  LDA (TABP16),Y
  BNE .print_memory_type
  ; curr_type = 0: print "file:"
  SET16 str_type_file, TABP16
  JSR print_str
  JMP .print_name
.print_memory_type:
  ; curr_type = 1: print "memory:"
  SET16 str_type_memory, TABP16
  JSR print_str
.print_name:
  ; Print name (FS_PL points to current entry's name)
  CP16 FS_P16, TABP16
  JSR print_basename
  ; Print ":"
  LDA #':'
  JSR write_b
  ; Print line number
  CP16 CURLINE16, TO_DECIMAL_VALUE16
  JSR print_decimal
  ; Print newline
  LDA #$0A
  JSR write_b
  ; Pop current entry (closes file, restores parent's handle and line)
  JSR pop_file_stack
  ; Continue to next
  JMP .loop
.done:
  ; Restore X
  PLA
  TAX
  RTS

str_type_file:
  .asciiz "file:"
str_type_memory:
  .asciiz "memory:"

; Print just the basename from a path at TABP16 (skips everything before last '/')
print_basename:
  ; Find the last '/' in the string
  LDY #$00
  STY TEMP              ; TEMP = index of char after last '/'
.scan:
  LDA (TABP16),Y
  BEQ .print_it         ; End of string
  CMP #'/'
  BNE .not_slash
  ; Found '/', remember position after it
  TYA
  CLC
  ADC #$01
  STA TEMP
.not_slash:
  INY
  JMP .scan
.print_it:
  ; Print from TEMP to end
  LDY TEMP
.print_loop:
  LDA (TABP16),Y
  BEQ .print_done
  JSR write_b
  INY
  JMP .print_loop
.print_done:
  RTS

print_str:
  LDY #$00
.loop:
  LDA (TABP16),Y
  BEQ .done
  JSR write_b
  INY
  JMP .loop
.done:
  RTS

str_chars:
  .asciiz "chars:"
str_lines:
  .asciiz "lines:"
str_stack:
  .asciiz "stack:"
str_empty:
  .asciiz "empty"
str_active:
  .asciiz "active"

; ============================================================================
; Print 16-bit decimal number (converts TO_DECIMAL_VALUE16 and prints it)
; ============================================================================
print_decimal:
  JSR to_decimal
  LDY #$00
.loop:
  LDA TO_DECIMAL_RESULT,Y
  BEQ .done
  JSR write_b
  INY
  BNE .loop           ; Always taken (string < 256 chars)
.done:
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
  INC16 CURLINE16
.success:
  LDA CURR_CHAR       ; Restore A (CMP changed flags)
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
  ; A/X contains pointer to arg string
  STA TABP16
  STX TABP16+$01
  JSR parse_mode
  BCS .error

  ; Get filename argument (argv[1])
  LDA #$01
  JSR argv
  ; A/X contains pointer to arg string
  STA TABP16
  STX TABP16+$01
  ; Copy to TOKEN
  LDY #$00
.copy_filename:
  LDA (TABP16),Y
  STA TOKEN,Y
  BEQ .filename_done
  INY
  JMP .copy_filename
.filename_done:
  ; Open file via file stack (this resets line number to 0)
  JSR push_file_stack
  ; Initialize line number to 1 (first line is line 1)
  SET16 $01, CURLINE16
  CLC
  RTS
.error:
  SEC
  RTS

; Parse mode string at TABP16/H
; Sets TEST_MODE, returns C=0 on success
parse_mode:
  LDY #$00
  LDA (TABP16),Y
  CMP #'e'
  BEQ .check_echo
  CMP #'l'
  BEQ .check_lines
  CMP #'i'
  BEQ .check_info
  CMP #'m'
  BEQ .check_memory
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
.check_info:
  LDA #$02
  STA TEST_MODE
  CLC
  RTS
.check_memory:
  LDA #$03
  STA TEST_MODE
  CLC
  RTS

; ============================================================================
; Error handling
; ============================================================================
error_usage:
  SET16 msg_usage, TABP16
  JSR print_str_err
  LDA #$01
  JMP exit

print_str_err:
  LDY #$00
.loop:
  LDA (TABP16),Y
  BEQ .done
  JSR write_d
  INY
  JMP .loop
.done:
  RTS

msg_usage:
  .asciiz "Usage: file_stack_test <mode> <file>\nModes: echo, lines, info, memory\n"

; Emulator convention - start address is the last 2 bytes of the file
  .word main
