; test_runner.asm - Native 6502 test runner for the assembler
;
; Runs assembler test files entirely within the emulated environment.
; The assembler code is called as a black box via JSR start.
; Vectors (exit, argc, argv, write_d) are intercepted to capture results.
; Output is verified by reading back the output file after assembly.
;
; Build:
;   (cd 17 && ../emulator.out out/asm.out asm.asm out/test_runner.out define:enable_test_runner)
;
; Usage:
;   (cd 17/tests/asm && ../../../emulator.out ../../out/test_runner.out 01-instructions.txt)
;
; Directory mode (no arguments):
;   (cd 17/tests/asm && ../../../emulator.out ../../out/test_runner.out)
;
; When no filename is given, opendir(".") is used to discover and run all
; .txt files in the current directory in alphabetical order.


; ============================================================================
; ZERO PAGE VARIABLES
; ============================================================================
; These are allocated after all assembler ZP variables and are NOT clobbered
; by the assembler when it runs.

  .zeropage

TR_SAVED_SP:       .byte       ; Stack pointer saved before JSR start
TR_EXIT_CODE:      .byte       ; Exit code captured from assembler
TR_ARGC:           .byte       ; Virtual argument count for assembler
TR_STDERR_LEN:     .byte       ; Length of captured stderr output
TR_EXPECT_LEN16:   .word       ; Length of expected hex bytes
TR_FILE_HANDLE:    .byte       ; Test file handle
TR_INPUT_HANDLE:   .byte       ; Temp input file handle
TR_LINE_LEN:       .byte       ; Current line buffer length
TR_STATE:          .byte       ; Parser state (0=none, 1=input)
TR_SKIP_FLAG:      .byte       ; Skip flag for current test
TR_EXPECT_ERROR:   .byte       ; Expected error code
TR_EXPECT_LINE16:  .word       ; Expected line number
TR_PASS_COUNT16:   .word       ; Number of passed tests
TR_FAIL_COUNT16:   .word       ; Number of failed tests
TR_SKIP_COUNT16:   .word       ; Number of skipped tests
TR_TEST_TYPE:      .byte       ; 0=hex test, 1=error test
TR_HAS_TEST:       .byte       ; Nonzero if a test has been parsed
TR_ACTUAL_LEN16:   .word       ; Length of actual output bytes
TR_ARGV_COUNT:     .byte       ; Number of extra ARGS entries
TR_LINE_TRUNC:     .byte       ; Nonzero if line was truncated (more in file)
TR_ACTUAL_PTR16:   .word       ; Pointer into TR_EXPECT_BUF for comparison
TR_MISMATCH_FLAG:  .byte       ; Nonzero if byte mismatch detected
TR_MISMATCH_ACTUAL: .byte      ; Actual byte at first mismatch
TR_MISMATCH_EXPECT: .byte      ; Expected byte at first mismatch
TR_MISMATCH_POS16: .word       ; Position of first mismatch
TR_LIMIT_FLAG:     .byte       ; Nonzero if runner hit a resource limit
TR_DIR_HANDLE:     .byte       ; Directory handle for directory scanning mode
TR_DIR_META:       .byte       ; Current directory entry metadata byte

  .code


; ============================================================================
; BUFFER LAYOUT ($0900-$0FFF)
; ============================================================================

TR_EXPECT_BUF   = $0900  ; Expected hex bytes (512 bytes, $0900-$0AFF)
TR_STDERR_BUF   = $0B00  ; Captured stderr output (256 bytes, $0B00-$0BFF)
TR_EXPECT_MSG   = $0C00  ; Expected error message (256 bytes, $0C00-$0CFF)
TR_NAME_BUF     = $0D00  ; Test name (256 bytes, $0D00-$0DFF)
TR_ARGV_PTRS    = $0E00  ; Virtual argv pointers (16 entries x 2 = 32 bytes)
TR_ARGV_STRS    = $0E20  ; Virtual argv strings (224 bytes, $0E20-$0EFF)
TR_LINE_BUF     = $0F00  ; Line read buffer (256 bytes, $0F00-$0FFF)

; Temp file names (stored in code)
TR_INPUT_FILE:  .asciiz "_tr_in.tmp"
TR_OUTPUT_FILE: .asciiz "_tr_out.tmp"


; ============================================================================
; ENTRY POINT
; ============================================================================

test_runner_start:
  ; Save original vector targets before any patching
  JSR tr_save_vectors
  ; Check if a filename was specified
  JSR argc
  CMP #$01
  BCC .dir_mode
  ; --- Single file mode ---
  LDA #$00
  JSR argv
  JSR open
  STA TR_FILE_HANDLE
  ; Print header
  SHOW_MESSAGEI tr_msg_running
  LDA #$00
  JSR argv
  STAX16 TABP16
  JSR show_message
  SHOW_CHAR '\n'
  ; Run all tests from this file
  JSR tr_run_file
  JMP .summary
.dir_mode:
  ; --- Directory mode: scan for .txt files ---
  JSR tr_run_directory
.summary:
  ; Print summary
  JSR tr_print_summary
  ; Exit with failure code if any tests failed
  LDA TR_FAIL_COUNT16
  ORA TR_FAIL_COUNT16 + 1
  BNE .exit_fail
  LDA #$00
  JMP exit
.exit_fail:
  LDA #$01
  JMP exit

tr_msg_running:
  .asciiz "Running tests from "


; ============================================================================
; FILE PROCESSING
; ============================================================================

; Run all tests from the file in TR_FILE_HANDLE
; On entry: TR_FILE_HANDLE = open file handle
; On exit: TR_FILE_HANDLE is closed, pass/fail/skip counts updated
tr_run_file:
  JSR tr_init_test
.main_loop:
  JSR tr_read_line
  BCS .eof
  ; Check for --- separator (always, even in input state)
  JSR tr_check_separator
  BCC .handle_sep
  ; Try field keywords (ends input state if matched)
  JSR tr_dispatch_field
  BCC .field_done
  ; No field matched
  LDA TR_STATE
  BNE .input_line
  ; Not in a section: skip empty lines and comments
  JSR tr_skip_rest_of_line
  JMP .main_loop
.input_line:
  JSR tr_handle_input_line
  JMP .main_loop
.field_done:
  JSR tr_skip_rest_of_line
  JMP .main_loop
.handle_sep:
  JSR tr_skip_rest_of_line
  JSR tr_close_input_state
  JSR tr_handle_separator
  JMP .main_loop
.eof:
  ; Handle last test in file (no trailing ---)
  JSR tr_close_input_state
  LDA TR_HAS_TEST
  BEQ .done
  JSR tr_finalize_test
.done:
  ; Close test file
  LDA TR_FILE_HANDLE
  JSR close
  RTS


; ============================================================================
; DIRECTORY SCANNING
; ============================================================================

; Scan current directory for .txt files and run each one
; Uses opendir(".") to list entries, filters for non-directory .txt files
tr_run_directory:
  LDA #<tr_dot_path
  LDX #>tr_dot_path
  JSR opendir
  CMP #$00
  BEQ .done
  STA TR_DIR_HANDLE
.entry_loop:
  ; Read metadata byte
  LDA TR_DIR_HANDLE
  JSR read
  BCS .close_dir
  STA TR_DIR_META
  ; Read filename into TR_LINE_BUF (null-terminated by opendir)
  LDY #$00
.name_loop:
  LDA TR_DIR_HANDLE
  JSR read
  BCS .close_dir               ; Unexpected EOF mid-entry
  STA TR_LINE_BUF,Y
  BEQ .name_done               ; Null terminator
  INY
  JMP .name_loop
.name_done:
  STY TR_LINE_LEN
  ; Skip directories
  LDA TR_DIR_META
  AND #DIR_ENTRY_DIR
  BNE .entry_loop
  ; Check if filename ends with ".txt"
  JSR tr_check_txt_extension
  BCS .entry_loop
  ; Print header for this file
  SHOW_MESSAGEI tr_msg_running
  SET16 TR_LINE_BUF, TABP16
  JSR show_message
  SHOW_CHAR '\n'
  ; Open the file and run all tests from it
  LDA #<TR_LINE_BUF
  LDX #>TR_LINE_BUF
  JSR open
  STA TR_FILE_HANDLE
  JSR tr_run_file
  JMP .entry_loop
.close_dir:
  LDA TR_DIR_HANDLE
  JSR close
.done:
  RTS

tr_dot_path: .asciiz "."


; Check if TR_LINE_BUF[0..TR_LINE_LEN) ends with ".txt"
; On exit: C clear = ends with .txt, C set = does not
tr_check_txt_extension:
  LDA TR_LINE_LEN
  CMP #$05                    ; Must be at least 5 chars (x.txt)
  BCC .no
  TAY
  DEY                          ; Y = index of last char
  LDA TR_LINE_BUF,Y
  CMP #'t'
  BNE .no
  DEY
  LDA TR_LINE_BUF,Y
  CMP #'x'
  BNE .no
  DEY
  LDA TR_LINE_BUF,Y
  CMP #'t'
  BNE .no
  DEY
  LDA TR_LINE_BUF,Y
  CMP #'.'
  BNE .no
  CLC
  RTS
.no:
  SEC
  RTS


; ============================================================================
; TEST EXECUTION
; ============================================================================

; Finalize the current test: skip or run it
tr_finalize_test:
  ; Auto-skip tests needing special builds
  LDA TR_ARGV_COUNT
  BEQ .check_limit
  JSR tr_check_auto_skip
.check_limit:
  ; Check for runner resource limitations
  LDA TR_LIMIT_FLAG
  BEQ .check_skip
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_limit
  INC16 TR_FAIL_COUNT16
  RTS
.check_skip:
  LDA TR_SKIP_FLAG
  BEQ .run
  ; Skip this test
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_skip
  INC16 TR_SKIP_COUNT16
  RTS
.run:
  JMP tr_run_test           ; Tail call

; Run a single test: set up argv, patch vectors, call assembler
tr_run_test:
  ; Set up virtual argv
  JSR tr_setup_argv
  ; Clear stderr capture
  LDA #$00
  STA TR_STDERR_LEN
  ; Patch vectors to intercept
  JSR tr_patch_vectors
  ; Save stack pointer
  TSX
  STX TR_SAVED_SP
  ; Run assembler (skip the JMP test_runner_start at start:)
  JSR start + $03
  ; NOTE: We never reach here - fake_exit intercepts and jumps to tr_test_resume

; Resume point after assembler exits (fake_exit jumps here via stack unwind)
; The stack has been restored to the state before JSR start+3,
; so RTS returns to the caller of tr_run_test.
tr_test_resume:
  ; Restore original vectors immediately
  JSR tr_restore_vectors
  ; Verify results based on test type
  LDA TR_TEST_TYPE
  BNE .error_test
  ; === Hex test ===
  JSR tr_verify_hex
  BCS .fail
  JMP .pass
.error_test:
  ; === Error test ===
  JSR tr_verify_error
  BCS .fail
.pass:
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_pass
  INC16 TR_PASS_COUNT16
  RTS
.fail:
  INC16 TR_FAIL_COUNT16
  RTS

; Set up virtual argv for the assembler
; argv[0] = "_tr_in.tmp", argv[1] = "_tr_out.tmp", argv[2+] = ARGS tokens
tr_setup_argv:
  SET16 TR_INPUT_FILE, TR_ARGV_PTRS
  SET16 TR_OUTPUT_FILE, TR_ARGV_PTRS + $02
  LDA #$02
  STA TR_ARGC
  ; Parse ARGS string if present
  LDX TR_ARGV_COUNT
  BEQ .done
  ; Walk TR_ARGV_STRS, splitting on spaces
  ; Each token becomes argv[TR_ARGC]
  LDY #$00                 ; Index into TR_ARGV_STRS
.skip_spaces:
  LDA TR_ARGV_STRS,Y
  BEQ .done                ; Null terminator
  CMP #' '
  BNE .start_token
  INY
  JMP .skip_spaces
.start_token:
  ; Record pointer to this token in argv table
  LDX TR_ARGC
  CPX #$08                 ; Max 8 argv entries (16 bytes of pointers)
  BCS .done
  TXA
  ASL                      ; *2 for word-sized entries
  TAX
  CLC
  TYA
  ADC #<TR_ARGV_STRS
  STA TR_ARGV_PTRS,X
  LDA #$00
  ADC #>TR_ARGV_STRS
  STA TR_ARGV_PTRS + 1,X
  INC TR_ARGC
.scan_token:
  LDA TR_ARGV_STRS,Y
  BEQ .done                ; End of string
  CMP #' '
  BEQ .end_token
  INY
  JMP .scan_token
.end_token:
  LDA #$00
  STA TR_ARGV_STRS,Y       ; Null-terminate this token
  INY
  JMP .skip_spaces
.done:
  RTS

tr_msg_skip:        .asciiz " SKIP\n"
tr_msg_limit:       .asciiz " LIMIT (input line exceeds 255 chars)\n"
tr_msg_pass:        .asciiz " PASS\n"
tr_msg_fail:        .asciiz " FAIL"
tr_msg_close_paren: .asciiz ")\n"
tr_msg_expected:    .asciiz " (expected "
tr_msg_got:         .asciiz ", got "
tr_msg_bytes:       .asciiz " bytes"
tr_msg_error:       .asciiz "error "
tr_msg_line:        .asciiz "line "
tr_msg_msg:         .asciiz "msg \""
tr_msg_quote:       .asciiz "\""
tr_msg_byte_at:     .asciiz " (byte "
tr_msg_colon_space: .asciiz ": "


; ============================================================================
; HEX VERIFICATION
; ============================================================================

; Verify hex test: read back output file and compare with expected bytes
; On exit: C clear = pass, C set = fail (details already printed)
tr_verify_hex:
  ; First check: assembler should have succeeded
  LDA TR_EXIT_CODE
  BEQ .exit_ok
  ; Assembler failed unexpectedly
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_expected
  SHOW_MESSAGEI tr_msg_error
  SHOW_CHAR '0'
  SHOW_MESSAGEI tr_msg_got
  SHOW_MESSAGEI tr_msg_error
  JSR tr_print_exit_code
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS
.exit_ok:
  ; Open output file for reading
  LDA #<TR_OUTPUT_FILE
  LDX #>TR_OUTPUT_FILE
  JSR open
  STA tr_verify_handle
  ; Initialize comparison state
  LDA #$00
  STA_LH16 TR_ACTUAL_LEN16
  STA TR_MISMATCH_FLAG
  SET16 TR_EXPECT_BUF, TR_ACTUAL_PTR16
  ; Read loop: compare each output byte with expected
.read_loop:
  LDA tr_verify_handle
  JSR read
  BCS .eof
  STA tr_verify_byte
  ; Compare if within expected range
  CMP16 TR_ACTUAL_LEN16, TR_EXPECT_LEN16
  BCS .beyond
  LDY #$00
  LDA tr_verify_byte
  CMP (TR_ACTUAL_PTR16),Y
  BEQ .match
  ; Mismatch - record if first one
  LDX TR_MISMATCH_FLAG
  BNE .match              ; Already recorded
  STA TR_MISMATCH_ACTUAL
  LDA (TR_ACTUAL_PTR16),Y
  STA TR_MISMATCH_EXPECT
  CP16 TR_ACTUAL_LEN16, TR_MISMATCH_POS16
  LDA #$01
  STA TR_MISMATCH_FLAG
.match:
  INC16 TR_ACTUAL_PTR16
.beyond:
  INC16 TR_ACTUAL_LEN16
  JMP .read_loop
.eof:
  ; Close output file
  LDA tr_verify_handle
  JSR close
  ; Check lengths match
  CMP16 TR_ACTUAL_LEN16, TR_EXPECT_LEN16
  BEQ .lengths_match
  ; Length mismatch
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_expected
  JSR tr_print_expect_len
  SHOW_MESSAGEI tr_msg_bytes
  SHOW_MESSAGEI tr_msg_got
  JSR tr_print_actual_len
  SHOW_MESSAGEI tr_msg_bytes
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS
.lengths_match:
  ; Check for byte mismatch
  LDA TR_MISMATCH_FLAG
  BEQ .hex_pass
  ; Byte mismatch - print details
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_byte_at
  CP16 TR_MISMATCH_POS16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_colon_space
  LDA TR_MISMATCH_EXPECT
  JSR tr_print_hex_byte
  SHOW_MESSAGEI tr_msg_got
  LDA TR_MISMATCH_ACTUAL
  JSR tr_print_hex_byte
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS
.hex_pass:
  CLC
  RTS

tr_verify_handle: .byte 0
tr_verify_byte:   .byte 0


; ============================================================================
; ERROR VERIFICATION
; ============================================================================

; Verify error test: check exit code, line number, and message
; On exit: C clear = pass, C set = fail (details already printed)
tr_verify_error:
  ; Check exit code
  LDA TR_EXIT_CODE
  CMP TR_EXPECT_ERROR
  BEQ .code_ok
  JMP .wrong_code
.code_ok:
  ; Check line number (if expected)
  LDA TR_EXPECT_LINE16
  ORA TR_EXPECT_LINE16 + 1
  BEQ .skip_line
  JSR tr_check_stderr_line
  BCC .skip_line
  JMP .wrong_line
.skip_line:
  ; Check message (if expected)
  LDA TR_EXPECT_MSG
  BEQ .pass
  JSR tr_check_stderr_msg
  BCC .pass
  JMP .wrong_msg
.pass:
  CLC
  RTS
.wrong_code:
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_expected
  SHOW_MESSAGEI tr_msg_error
  LDA TR_EXPECT_ERROR
  STA TO_DECIMAL_VALUE16
  LDA #$00
  STA TO_DECIMAL_VALUE16 + 1
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_got
  SHOW_MESSAGEI tr_msg_error
  JSR tr_print_exit_code
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS
.wrong_line:
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_expected
  SHOW_MESSAGEI tr_msg_line
  CP16 TR_EXPECT_LINE16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_got
  SHOW_MESSAGEI tr_msg_line
  CP16 HEX16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS
.wrong_msg:
  JSR tr_print_test_name
  SHOW_MESSAGEI tr_msg_fail
  SHOW_MESSAGEI tr_msg_expected
  SHOW_MESSAGEI tr_msg_msg
  SET16 TR_EXPECT_MSG, TABP16
  JSR show_message
  SHOW_MESSAGEI tr_msg_quote
  SHOW_MESSAGEI tr_msg_close_paren
  SEC
  RTS

; Check "at line N" in stderr, compare N with TR_EXPECT_LINE16
; On exit: C clear = match, C set = mismatch
;          HEX16 = parsed line number (for error reporting)
tr_check_stderr_line:
  ; Search for "at line " in stderr buffer
  LDY #$00
.search:
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'a'
  BNE .next
  ; Check "at line " (8 chars)
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'t'
  BNE .search              ; Restart from current Y (already past 'a')
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #' '
  BNE .search
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'l'
  BNE .search
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'i'
  BNE .search
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'n'
  BNE .search
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #'e'
  BNE .search
  INY
  CPY TR_STDERR_LEN
  BCS .not_found
  LDA TR_STDERR_BUF,Y
  CMP #' '
  BNE .search
  INY
  ; Y now points to the line number digits
  JSR tr_parse_decimal_from_stderr
  ; Compare with expected
  CMP16 HEX16, TR_EXPECT_LINE16
  BEQ .match
  SEC
  RTS
.match:
  CLC
  RTS
.next:
  INY
  JMP .search
.not_found:
  SEC
  RTS

; Check message after ": " in stderr matches TR_EXPECT_MSG
; On exit: C clear = match, C set = mismatch
tr_check_stderr_msg:
  ; Search backwards for ": " (the message delimiter)
  LDY TR_STDERR_LEN
  DEY
.search:
  CPY #$01
  BCC .not_found            ; Reached start without finding ": "
  LDA TR_STDERR_BUF - 1,Y
  CMP #':'
  BNE .dec
  LDA TR_STDERR_BUF,Y
  CMP #' '
  BEQ .found
.dec:
  DEY
  JMP .search
.found:
  INY                       ; Y past ": " → start of message
  LDX #$00
.cmp:
  LDA TR_EXPECT_MSG,X
  BEQ .end_expected
  CPY TR_STDERR_LEN
  BCS .mismatch
  CMP TR_STDERR_BUF,Y
  BNE .mismatch
  INX
  INY
  JMP .cmp
.end_expected:
  ; Expected msg fully matched; check actual has ended (newline or end)
  CPY TR_STDERR_LEN
  BCS .match
  LDA TR_STDERR_BUF,Y
  CMP #$0A
  BEQ .match
.mismatch:
.not_found:
  SEC
  RTS
.match:
  CLC
  RTS

; Parse decimal from TR_STDERR_BUF starting at Y, result in HEX16
tr_parse_decimal_from_stderr:
  LDA #$00
  STA HEX16
  STA HEX16 + 1
.loop:
  CPY TR_STDERR_LEN
  BCS .done
  LDA TR_STDERR_BUF,Y
  CMP #'0'
  BCC .done
  CMP #':'
  BCS .done
  SEC
  SBC #'0'
  STA TEMP
  CP16 HEX16, PC16
  ASL16 HEX16
  ASL16 HEX16
  CLC
  ADC16 HEX16, PC16, HEX16
  ASL16 HEX16
  LDA TEMP
  CLC
  ADC HEX16
  STA HEX16
  BCC .no_carry
  INC HEX16 + 1
.no_carry:
  INY
  JMP .loop
.done:
  RTS


; ============================================================================
; PRINT HELPERS
; ============================================================================

; Print TR_EXIT_CODE as decimal
tr_print_exit_code:
  LDA TR_EXIT_CODE
  STA TO_DECIMAL_VALUE16
  LDA #$00
  STA TO_DECIMAL_VALUE16 + 1
  JMP show_decimal

; Print TR_EXPECT_LEN16 as decimal
tr_print_expect_len:
  CP16 TR_EXPECT_LEN16, TO_DECIMAL_VALUE16
  JMP show_decimal

; Print TR_ACTUAL_LEN16 as decimal
tr_print_actual_len:
  CP16 TR_ACTUAL_LEN16, TO_DECIMAL_VALUE16
  JMP show_decimal

; Print byte in A as two hex digits
tr_print_hex_byte:
  PHA
  LSR
  LSR
  LSR
  LSR
  JSR .nibble
  PLA
  AND #$0F
.nibble:
  CMP #$0A
  BCC .digit
  CLC
  ADC #'a'-$0A
  JMP .out
.digit:
  CLC
  ADC #'0'
.out:
  STA $F002               ; Write to stderr
  RTS


; Print summary: "N passed, M failed, K skipped"
tr_print_summary:
  CP16 TR_PASS_COUNT16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_sum_passed
  CP16 TR_FAIL_COUNT16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_sum_failed
  CP16 TR_SKIP_COUNT16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_sum_skipped
  RTS

tr_msg_sum_passed:  .asciiz " passed, "
tr_msg_sum_failed:  .asciiz " failed, "
tr_msg_sum_skipped: .asciiz " skipped\n"

; Check if test ARGS require a special build; set TR_SKIP_FLAG if so
; Auto-skips tests with "debug", "small_heap", or "show_captured_macros" in ARGS
tr_check_auto_skip:
  ; Check for "debug"
  SET16 tr_skip_debug, TABP16
  JSR tr_args_contains
  BCC .skip
  ; Check for "small_heap"
  SET16 tr_skip_small_heap, TABP16
  JSR tr_args_contains
  BCC .skip
  ; Check for "show_captured_macros"
  SET16 tr_skip_show_macros, TABP16
  JSR tr_args_contains
  BCC .skip
  RTS
.skip:
  LDA #$01
  STA TR_SKIP_FLAG
  RTS

tr_skip_debug:       .asciiz "debug"
tr_skip_small_heap:  .asciiz "small_heap"
tr_skip_show_macros: .asciiz "show_captured_macros"

; Check if TR_ARGV_STRS contains the null-terminated string at (TABP16)
; On exit: C clear = found, C set = not found
tr_args_contains:
  LDX #$00                 ; Index into TR_ARGV_STRS
.outer:
  LDA TR_ARGV_STRS,X
  BEQ .not_found           ; End of args string
  ; Try to match from current position
  STX tr_args_start        ; Save start of this token
  LDY #$00                 ; Index into search string
.inner:
  LDA (TABP16),Y
  BEQ .check_boundary      ; End of search string - check word boundary
  CMP TR_ARGV_STRS,X
  BNE .next
  INX
  INY
  JMP .inner
.check_boundary:
  ; Full search string matched - check word boundary
  LDA TR_ARGV_STRS,X
  BEQ .found               ; End of args = valid boundary
  CMP #' '
  BEQ .found               ; Space = valid boundary
  ; Partial match - fall through to advance past this token
.next:
  ; Advance X to next space or end from the token start
  LDX tr_args_start
.advance:
  LDA TR_ARGV_STRS,X
  BEQ .not_found
  CMP #' '
  BEQ .skip_space
  INX
  JMP .advance
.skip_space:
  INX
  JMP .outer
.found:
  CLC
  RTS
.not_found:
  SEC
  RTS

tr_args_start: .byte 0


; ============================================================================
; FIELD DISPATCH
; ============================================================================

; Check if line is a --- separator
; On exit: C clear = is separator, C set = not
tr_check_separator:
  LDA TR_LINE_LEN
  CMP #$03
  BNE .no
  LDA TR_LINE_BUF
  CMP #'-'
  BNE .no
  LDA TR_LINE_BUF + 1
  CMP #'-'
  BNE .no
  LDA TR_LINE_BUF + 2
  CMP #'-'
  BNE .no
  CLC
  RTS
.no:
  SEC
  RTS

; Try to match field keywords. Closes input state on match.
; On exit: C clear = field matched and handled
;          C set = no field matched
tr_dispatch_field:
  SET16 tr_pfx_name, TABP16
  JSR tr_match_prefix
  BCS .not_name
  JSR tr_close_input_state
  JMP tr_handle_name      ; Returns (C clear via tail path)
.not_name:
  SET16 tr_pfx_input, TABP16
  JSR tr_match_prefix
  BCS .not_input
  JSR tr_close_input_state
  JMP tr_handle_input
.not_input:
  SET16 tr_pfx_expect_hex, TABP16
  JSR tr_match_prefix
  BCS .not_hex
  JSR tr_close_input_state
  JMP tr_handle_expect_hex
.not_hex:
  SET16 tr_pfx_expect_error, TABP16
  JSR tr_match_prefix
  BCS .not_error
  JSR tr_close_input_state
  JMP tr_handle_expect_error
.not_error:
  SET16 tr_pfx_expect_line, TABP16
  JSR tr_match_prefix
  BCS .not_line
  JSR tr_close_input_state
  JMP tr_handle_expect_line
.not_line:
  SET16 tr_pfx_expect_msg, TABP16
  JSR tr_match_prefix
  BCS .not_msg
  JSR tr_close_input_state
  JMP tr_handle_expect_msg
.not_msg:
  SET16 tr_pfx_skip, TABP16
  JSR tr_match_prefix
  BCS .not_skip
  JSR tr_close_input_state
  JMP tr_handle_skip
.not_skip:
  SET16 tr_pfx_args, TABP16
  JSR tr_match_prefix
  BCS .not_args
  JSR tr_close_input_state
  JMP tr_handle_args
.not_args:
  SET16 tr_pfx_expect_stderr, TABP16
  JSR tr_match_prefix
  BCS .no_match
  JSR tr_close_input_state
  JMP tr_handle_skip         ; Treat as skip (can't verify stderr)
.no_match:
  SEC
  RTS


; ============================================================================
; FIELD HANDLERS
; ============================================================================

; Handle --- separator: finalize previous test, reset state
tr_handle_separator:
  LDA TR_HAS_TEST
  BEQ .no_prev_test
  JSR tr_finalize_test
.no_prev_test:
  JMP tr_init_test        ; Tail call - reset for next test

; Handle NAME: field - copy test name
; On entry: Y = offset past prefix
tr_handle_name:
  JSR tr_copy_field_to_name
  LDA #$01
  STA TR_HAS_TEST
  CLC
  RTS

; Handle INPUT: field - open temp file, enter input state
tr_handle_input:
  LDA #<TR_INPUT_FILE
  LDX #>TR_INPUT_FILE
  JSR openout
  STA TR_INPUT_HANDLE
  LDA #$01
  STA TR_STATE            ; Enter input state
  CLC
  RTS

; Handle an input content line (strip "N: " prefix, write to temp file)
tr_handle_input_line:
  ; Flag if this line was truncated (runner limitation)
  LDA TR_LINE_TRUNC
  BEQ .no_trunc
  ORA TR_LIMIT_FLAG         ; Don't clear if already set
  STA TR_LIMIT_FLAG
.no_trunc:
  ; Strip line number prefix: skip spaces, digits, ": "
  LDY #$00
  ; Skip leading spaces
.skip_spaces:
  CPY TR_LINE_LEN
  BCS .write
  LDA TR_LINE_BUF,Y
  CMP #' '
  BNE .skip_digits
  INY
  JMP .skip_spaces
.skip_digits:
  CPY TR_LINE_LEN
  BCS .write
  LDA TR_LINE_BUF,Y
  CMP #'0'
  BCC .write              ; Not a digit
  CMP #':'                ; ':' = $3A, after '9' = $39
  BCS .check_colon
  INY
  JMP .skip_digits
.check_colon:
  CMP #':'
  BNE .write
  INY
  CPY TR_LINE_LEN
  BCS .write
  LDA TR_LINE_BUF,Y
  CMP #' '
  BNE .write
  INY                     ; Skip the space after colon
.write:
  ; Write from Y to end of line to temp file
.write_loop:
  CPY TR_LINE_LEN
  BCS .write_nl
  LDA TR_LINE_BUF,Y
  LDX TR_INPUT_HANDLE
  JSR write
  INY
  JMP .write_loop
.write_nl:
  LDA #$0A
  LDX TR_INPUT_HANDLE
  JSR write
  RTS

; Handle EXPECT_HEX: field - parse hex bytes
; On entry: Y = offset past prefix
tr_handle_expect_hex:
  LDA #$00
  STA TR_TEST_TYPE        ; Mark as hex test
  STA_LH16 TR_EXPECT_LEN16
  ; Parse hex bytes from buffer
  JSR tr_parse_hex_from_buf
  ; If line was truncated, continue reading hex from file
  LDA TR_LINE_TRUNC
  BEQ .done
  JSR tr_parse_hex_from_file
.done:
  CLC
  RTS

; Handle EXPECT_ERROR: field - parse decimal error code
; On entry: Y = offset past prefix
tr_handle_expect_error:
  LDA #$01
  STA TR_TEST_TYPE        ; Mark as error test
  JSR tr_parse_decimal
  LDA HEX16
  STA TR_EXPECT_ERROR
  CLC
  RTS

; Handle EXPECT_LINE: field - parse decimal line number
; On entry: Y = offset past prefix
tr_handle_expect_line:
  JSR tr_parse_decimal
  CP16 HEX16, TR_EXPECT_LINE16
  CLC
  RTS

; Handle EXPECT_MSG: field - copy message string
; On entry: Y = offset past prefix
tr_handle_expect_msg:
  LDX #$00
.loop:
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  STA TR_EXPECT_MSG,X
  INY
  INX
  BNE .loop
.done:
  LDA #$00
  STA TR_EXPECT_MSG,X     ; Null-terminate
  CLC
  RTS

; Handle SKIP: field - set skip flag
tr_handle_skip:
  LDA #$01
  STA TR_SKIP_FLAG
  CLC
  RTS

; Handle ARGS: field - store args string (parsed later)
; On entry: Y = offset past prefix
tr_handle_args:
  ; Copy args to TR_ARGV_STRS for later parsing
  LDX #$00
.loop:
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  STA TR_ARGV_STRS,X
  INY
  INX
  BNE .loop
.done:
  LDA #$00
  STA TR_ARGV_STRS,X      ; Null-terminate
  LDA #$01
  STA TR_ARGV_COUNT        ; Mark that args exist
  CLC
  RTS

; Close input state (close temp file if input was being written)
; Preserves Y (callers depend on Y being the prefix offset)
tr_close_input_state:
  LDA TR_STATE
  BEQ .done
  TYA
  PHA                       ; Save Y
  LDA TR_INPUT_HANDLE
  JSR close
  LDA #$00
  STA TR_STATE
  PLA
  TAY                       ; Restore Y
.done:
  RTS


; ============================================================================
; FIELD MATCHING
; ============================================================================

; Check if TR_LINE_BUF starts with the string at (TABP16)
; On entry: TABP16 points to null-terminated prefix string
; On exit: C clear = match, Y = offset past prefix in TR_LINE_BUF
;          C set = no match
tr_match_prefix:
  LDY #$00
.loop:
  LDA (TABP16),Y
  BEQ .match              ; End of prefix → match
  CPY TR_LINE_LEN
  BCS .no_match           ; Line shorter than prefix
  CMP TR_LINE_BUF,Y
  BNE .no_match
  INY
  BNE .loop
.no_match:
  SEC
  RTS
.match:
  CLC
  RTS

; Field prefix strings
tr_pfx_name:          .asciiz "NAME: "
tr_pfx_input:         .asciiz "INPUT:"
tr_pfx_expect_hex:    .asciiz "EXPECT_HEX: "
tr_pfx_expect_error:  .asciiz "EXPECT_ERROR: "
tr_pfx_expect_line:   .asciiz "EXPECT_LINE: "
tr_pfx_expect_msg:    .asciiz "EXPECT_MSG: "
tr_pfx_skip:          .asciiz "SKIP:"
tr_pfx_args:          .asciiz "ARGS: "
tr_pfx_expect_stderr: .asciiz "EXPECT_STDERR:"


; ============================================================================
; HEX PARSER
; ============================================================================

; Parse hex byte pairs from TR_LINE_BUF into TR_EXPECT_BUF
; On entry: Y = offset in TR_LINE_BUF
; On exit: TR_EXPECT_LEN16 updated
tr_parse_hex_from_buf:
.loop:
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  CMP #' '
  BNE .hex_hi
  INY
  JMP .loop
.hex_hi:
  JSR tr_hex_char_to_val
  BCS .done
  ASL
  ASL
  ASL
  ASL
  STA TEMP                ; High nibble
  INY
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  JSR tr_hex_char_to_val
  BCS .done
  ORA TEMP                ; Combine nibbles
  JSR tr_store_expect_byte
  INY
  JMP .loop
.done:
  RTS

; Continue parsing hex bytes directly from the file (for truncated lines)
; Reads chars until newline or EOF
tr_parse_hex_from_file:
  LDA #$00
  STA TEMP                ; State: 0=need hi, 1=need lo
.loop:
  LDA TR_FILE_HANDLE
  JSR read
  BCS .done
  CMP #$0A
  BEQ .done
  CMP #' '
  BEQ .loop               ; Skip spaces
  JSR tr_hex_char_to_val
  BCS .loop               ; Skip non-hex
  LDX TEMP
  BNE .lo_nibble
  ; High nibble
  ASL
  ASL
  ASL
  ASL
  STA PC16                ; Temp store high nibble
  LDA #$01
  STA TEMP
  JMP .loop
.lo_nibble:
  ORA PC16
  JSR tr_store_expect_byte
  LDA #$00
  STA TEMP
  JMP .loop
.done:
  LDA #$00
  STA TR_LINE_TRUNC
  RTS

; Store a byte in TR_EXPECT_BUF and increment TR_EXPECT_LEN16
; On entry: A = byte to store
; Preserves Y (caller uses Y as buffer index)
; Fails fast if buffer would overflow (512 byte limit)
tr_store_expect_byte:
  STY tr_store_save_y       ; Save caller's Y
  PHA
  ; Check for buffer overflow (512 bytes max)
  CMPI16 TR_EXPECT_LEN16, $0200
  BCC .ok
  JMP tr_err_expect_overflow
.ok:
  ; Use 16-bit index for >256 byte buffers
  LDAX16 TR_EXPECT_LEN16
  STX TABP16 + 1
  CLC
  ADC #<TR_EXPECT_BUF
  STA TABP16
  LDA TABP16 + 1
  ADC #>TR_EXPECT_BUF
  STA TABP16 + 1
  PLA
  LDY #$00
  STA (TABP16),Y
  INC16 TR_EXPECT_LEN16
  LDY tr_store_save_y       ; Restore caller's Y
  RTS

tr_store_save_y: .byte 0

; Convert ASCII hex char in A to value 0-15
; On exit: A = value, C clear = valid, C set = invalid
tr_hex_char_to_val:
  CMP #'0'
  BCC .invalid
  CMP #':'                ; '9' + 1
  BCC .digit
  CMP #'a'
  BCC .invalid
  CMP #'g'                ; 'f' + 1
  BCS .invalid
  SEC
  SBC #'a'-$0A
  CLC
  RTS
.digit:
  SEC
  SBC #'0'
  CLC
  RTS
.invalid:
  SEC
  RTS


; ============================================================================
; DECIMAL PARSER
; ============================================================================

; Parse decimal number from TR_LINE_BUF starting at offset Y
; Result stored in HEX16 (16-bit)
; On exit: Y = past last digit, HEX16 = parsed value
tr_parse_decimal:
  LDA #$00
  STA HEX16
  STA HEX16 + 1
.loop:
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  CMP #'0'
  BCC .done
  CMP #':'                ; '9' + 1
  BCS .done
  SEC
  SBC #'0'
  STA TEMP                ; Save digit
  ; HEX16 *= 10 = (x*4 + x) * 2
  CP16 HEX16, PC16        ; PC16 = saved x
  ASL16 HEX16             ; x*2
  ASL16 HEX16             ; x*4
  CLC
  ADC16 HEX16, PC16, HEX16  ; x*4 + x = x*5
  ASL16 HEX16             ; x*10
  ; Add digit
  LDA TEMP
  CLC
  ADC HEX16
  STA HEX16
  BCC .no_carry
  INC HEX16 + 1
.no_carry:
  INY
  JMP .loop
.done:
  RTS


; ============================================================================
; TEST STATE MANAGEMENT
; ============================================================================

; Initialize/reset test state for a new test
tr_init_test:
  LDA #$00
  STA TR_HAS_TEST
  STA TR_NAME_BUF         ; Clear name (null terminator at start)
  STA TR_SKIP_FLAG
  STA TR_EXPECT_ERROR
  STA_LH16 TR_EXPECT_LEN16
  STA_LH16 TR_EXPECT_LINE16
  STA TR_EXPECT_MSG        ; Clear expected message
  STA TR_TEST_TYPE
  STA TR_STATE
  STA TR_ARGV_COUNT
  STA TR_LIMIT_FLAG
  RTS

; Print the test name (indented, no newline)
tr_print_test_name:
  SHOW_MESSAGEI tr_msg_indent
  SET16 TR_NAME_BUF, TABP16
  JMP show_message          ; Tail call

tr_msg_indent:    .asciiz "  "

; Copy from TR_LINE_BUF[Y..TR_LINE_LEN) to TR_NAME_BUF
; On entry: Y = starting offset in TR_LINE_BUF
tr_copy_field_to_name:
  LDX #$00
.loop:
  CPY TR_LINE_LEN
  BCS .done
  LDA TR_LINE_BUF,Y
  STA TR_NAME_BUF,X
  INY
  INX
  BNE .loop
.done:
  LDA #$00
  STA TR_NAME_BUF,X       ; Null-terminate
  RTS


; ============================================================================
; LINE READER
; ============================================================================

; Read one line from the test file into TR_LINE_BUF
; On exit: TR_LINE_LEN = length (excluding newline)
;          TR_LINE_TRUNC = 1 if line was truncated (more data in file)
;          C clear = line read OK (or truncated)
;          C set = EOF reached (TR_LINE_LEN may be >0 for partial line)
;          A, X, Y not preserved
tr_read_line:
  LDY #$00              ; Buffer index
.loop:
  CPY #$FF              ; Buffer full? Check BEFORE reading
  BCS .full
  LDA TR_FILE_HANDLE
  JSR read              ; Read char; C set at EOF
  BCS .eof
  CMP #$0A              ; Newline?
  BEQ .eol
  STA TR_LINE_BUF,Y
  INY
  JMP .loop
.full:
  STY TR_LINE_LEN       ; 255 chars stored
  LDA #$01
  STA TR_LINE_TRUNC     ; More data in file for this line
  CLC
  RTS
.eol:
  STY TR_LINE_LEN
  LDA #$00
  STA TR_LINE_TRUNC
  CLC                   ; Line read OK
  RTS
.eof:
  STY TR_LINE_LEN
  LDA #$00
  STA TR_LINE_TRUNC
  SEC                   ; EOF
  RTS

; Skip remaining chars on current line (when truncated)
; Reads from file until newline or EOF
tr_skip_rest_of_line:
  LDA TR_LINE_TRUNC
  BEQ .done
.loop:
  LDA TR_FILE_HANDLE
  JSR read
  BCS .eof
  CMP #$0A
  BNE .loop
.eof:
  LDA #$00
  STA TR_LINE_TRUNC
.done:
  RTS


; ============================================================================
; VECTOR INTERCEPTION
; ============================================================================
; The emulator's environment vectors are JMP instructions at fixed addresses.
; Each JMP is 3 bytes: opcode ($4C) + 2-byte target address.
; We patch the target bytes to redirect to our fake handlers.
;
;   Vector    JMP at   Target bytes    Fake handler
;   ------    ------   ------------    ------------
;   write_d   $F00C    $F00D-$F00E     fake_write_d
;   exit      $F00F    $F010-$F011     fake_exit
;   argc      $F01B    $F01C-$F01D     fake_argc
;   argv      $F01E    $F01F-$F020     fake_argv

; Save original vector target addresses
tr_save_vectors:
  LDA $F00D
  STA tr_orig_write_d
  LDA $F00E
  STA tr_orig_write_d + 1
  LDA $F010
  STA tr_orig_exit
  LDA $F011
  STA tr_orig_exit + 1
  LDA $F01C
  STA tr_orig_argc
  LDA $F01D
  STA tr_orig_argc + 1
  LDA $F01F
  STA tr_orig_argv
  LDA $F020
  STA tr_orig_argv + 1
  RTS

; Patch vectors to point to fake handlers
tr_patch_vectors:
  LDA #<fake_write_d
  STA $F00D
  LDA #>fake_write_d
  STA $F00E
  LDA #<fake_exit
  STA $F010
  LDA #>fake_exit
  STA $F011
  LDA #<fake_argc
  STA $F01C
  LDA #>fake_argc
  STA $F01D
  LDA #<fake_argv
  STA $F01F
  LDA #>fake_argv
  STA $F020
  RTS

; Restore original vector targets
tr_restore_vectors:
  LDA tr_orig_write_d
  STA $F00D
  LDA tr_orig_write_d + 1
  STA $F00E
  LDA tr_orig_exit
  STA $F010
  LDA tr_orig_exit + 1
  STA $F011
  LDA tr_orig_argc
  STA $F01C
  LDA tr_orig_argc + 1
  STA $F01D
  LDA tr_orig_argv
  STA $F01F
  LDA tr_orig_argv + 1
  STA $F020
  RTS

; Storage for original vector targets
tr_orig_write_d:  .word 0
tr_orig_exit:     .word 0
tr_orig_argc:     .word 0
tr_orig_argv:     .word 0


; ============================================================================
; FAKE HANDLERS
; ============================================================================

; fake_exit - Capture exit code and return control to test runner
; Called when assembler hits BRK → interrupt → JMP exit
; On entry: A = exit code
fake_exit:
  STA TR_EXIT_CODE        ; Save exit code
  LDX TR_SAVED_SP
  TXS                     ; Atomically unwind stack
  JMP tr_test_resume      ; Continue in test runner

; fake_argc - Return virtual argument count
; On entry: nothing
; On exit: A = argument count, X and Y preserved
fake_argc:
  LDA TR_ARGC
  RTS

; fake_argv - Return virtual argument pointer
; On entry: A = argument index
; On exit: A = low byte, X = high byte, Y preserved
fake_argv:
  STY tr_save_y           ; Save Y
  ASL                     ; index * 2 (word-sized entries)
  TAY
  LDX TR_ARGV_PTRS + 1,Y ; X = high byte
  LDA TR_ARGV_PTRS,Y     ; A = low byte
  LDY tr_save_y           ; Restore Y
  RTS

tr_save_y: .byte 0

; fake_write_d - Buffer stderr byte and forward to real port
; On entry: A = byte to write
; On exit: A, X, Y preserved (matches real write_d contract)
; Caps buffer at 255 bytes (stops buffering, still forwards to stderr)
fake_write_d:
  STA $F002               ; Forward to real stderr port
  STX tr_save_x           ; Save X
  LDX TR_STDERR_LEN
  CPX #$FF                ; Buffer full?
  BCS .skip               ; Don't buffer, but keep forwarding
  STA TR_STDERR_BUF,X     ; Buffer the byte
  INC TR_STDERR_LEN
.skip:
  LDX tr_save_x           ; Restore X
  RTS

tr_save_x: .byte 0


; ============================================================================
; ERROR HANDLERS
; ============================================================================

; Fatal error: EXPECT_HEX buffer overflow (>512 bytes)
tr_err_expect_overflow:
  SHOW_MESSAGEI tr_err_msg_expect_overflow
  SET16 TR_NAME_BUF, TABP16
  JSR show_message
  SHOW_CHAR '\n'
  BRK
  .byte 1

tr_err_msg_expect_overflow:
  .asciiz "FATAL: EXPECT_HEX buffer overflow (>512 bytes) in test: "
