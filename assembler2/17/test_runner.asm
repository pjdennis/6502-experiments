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
TR_LINE_TRUNC:     .byte       ; Nonzero if line was truncated (more in file)

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
  ; Print header
  SHOW_MESSAGEI tr_msg_running
  LDA #$00
  JSR argv
  STAX16 TABP16
  JSR show_message
  SHOW_CHAR '\n'
  ; Initialize test state
  JSR tr_init_test
  ; Main parse loop
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
  JSR tr_print_test_name
.done:
  ; Close test file
  LDA TR_FILE_HANDLE
  JSR close
  BRK
  .byte 0

tr_msg_running:
  .asciiz "Running tests from "

; Resume point after assembler exits (fake_exit jumps here)
tr_test_resume:
  ; Placeholder - full implementation in later commits
  JSR tr_restore_vectors
  BRK
  .byte 0


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
  BCS .no_match
  JSR tr_close_input_state
  JMP tr_handle_args
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
  JSR tr_print_test_name
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
  RTS

; Print test name with parsed info (for verification)
tr_print_test_name:
  SHOW_MESSAGEI tr_msg_indent
  SET16 TR_NAME_BUF, TABP16
  JSR show_message
  ; Print parsed details
  LDA TR_TEST_TYPE
  BNE .error_test
  ; Hex test: print expected byte count
  SHOW_MESSAGEI tr_msg_hex_count
  CP16 TR_EXPECT_LEN16, TO_DECIMAL_VALUE16
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_bytes
  RTS
.error_test:
  ; Error test: print expected error code
  SHOW_MESSAGEI tr_msg_err_code
  LDA TR_EXPECT_ERROR
  STA TO_DECIMAL_VALUE16
  LDA #$00
  STA TO_DECIMAL_VALUE16 + 1
  JSR show_decimal
  SHOW_MESSAGEI tr_msg_err_close
  RTS

tr_msg_indent:    .asciiz "  "
tr_msg_hex_count: .asciiz " (hex: "
tr_msg_bytes:     .asciiz " bytes)\n"
tr_msg_err_code:  .asciiz " (error: "
tr_msg_err_close: .asciiz ")\n"

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
