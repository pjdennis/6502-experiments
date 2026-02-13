; test_runner.asm - Native 6502 test runner for the assembler
;
; Runs assembler test files entirely within the emulated environment.
; The assembler code is called as a black box via JSR start.
; Vectors (exit, argc, argv, write_d) are intercepted to capture results.
;
; Build:
;   (cd 17 && ../emulator.out out/asm.out asm.asm out/test_runner.out define:enable_test_runner)
;
; Usage:
;   (cd 17 && ../emulator.out out/test_runner.out tests/asm/01-instructions.txt)


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
  ; Open test file from argv[0]
  LDA #$00
  JSR argv
  JSR open
  STA TR_FILE_HANDLE
  ; Print filename
  SHOW_MESSAGEI tr_msg_running
  LDA #$00
  JSR argv
  STAX16 TABP16
  JSR show_message
  SHOW_CHAR '\n'
  ; Count lines
  SET16 $0000, TR_PASS_COUNT16
.count_loop:
  JSR tr_read_line
  BCS .count_done
  INC16 TR_PASS_COUNT16
  JMP .count_loop
.count_done:
  ; Count partial final line (no trailing newline)
  LDA TR_LINE_LEN
  BEQ .no_final_line
  INC16 TR_PASS_COUNT16
.no_final_line:
  ; Print line count
  CP16 TR_PASS_COUNT16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_lines
  ; Close test file
  LDA TR_FILE_HANDLE
  JSR close
  BRK
  .byte 0

tr_msg_running:
  .asciiz "Running tests from "
tr_msg_lines:
  .asciiz " lines\n"

; Resume point after assembler exits (fake_exit jumps here)
tr_test_resume:
  ; Placeholder - full implementation in later commits
  JSR tr_restore_vectors
  BRK
  .byte 0


; ============================================================================
; LINE READER
; ============================================================================

; Read one line from the test file into TR_LINE_BUF
; On exit: TR_LINE_LEN = length (excluding newline)
;          C clear = line read OK
;          C set = EOF reached (TR_LINE_LEN may be >0 for partial line)
;          A, X, Y not preserved
tr_read_line:
  LDY #$00              ; Buffer index
.loop:
  LDA TR_FILE_HANDLE
  JSR read              ; Read char; C set at EOF
  BCS .eof
  CMP #$0A              ; Newline?
  BEQ .eol
  CPY #$FF              ; Buffer full? (255 chars max)
  BCS .loop             ; Discard excess chars, keep reading
  STA TR_LINE_BUF,Y
  INY
  JMP .loop
.eol:
  STY TR_LINE_LEN
  CLC                   ; Line read OK
  RTS
.eof:
  STY TR_LINE_LEN
  SEC                   ; EOF
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
fake_write_d:
  STA $F002               ; Forward to real stderr port
  STX tr_save_x           ; Save X
  LDX TR_STDERR_LEN
  STA TR_STDERR_BUF,X     ; Buffer the byte
  INC TR_STDERR_LEN       ; Wraps at 256 (truncates long output)
  LDX tr_save_x           ; Restore X
  RTS

tr_save_x: .byte 0
